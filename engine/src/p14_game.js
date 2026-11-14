// The game: its state, the master tick, the player, survival, the camera, streaming and light (the
// Swift game's p14a_game and p14b_player).

const GameMode = { survival: 0, creative: 1, hardcore: 2 };
const MODE_NAMES = ["Survival", "Creative", "Hardcore"];
const playerMass = 1.0;

/** the player's settings, kept in this browser (see SettingsStore) */
function defaultSettings() {
	return {
		tilePx: 24, camSmoothOn: true, camFollow: 0.55, camDeadZone: 1.2, camLookAhead: true, camDirect: false, shakeScale: 1,
		showFPS: false, smoothLight: true, sound: true, volume: 0.8, music: false,
		hair: 0, hairStyle: 0, shirtColor: 0, shirtStyle: 0, pantsColor: 0, pantsStyle: 0, scarf: 0,
		weatherOn: true, rareChance: 0.35, autosave: true, leftHanded: false,
	};
}

let gameSerial = 0;

class Game {
	constructor(mode, infinite, seed, settings, genVersion = GEN_VERSION, options = null, loadSpawn = true) {
		this.serial = ++gameSerial;
		this.mode = mode;
		this.settings = settings;
		this.seedValue = seed >>> 0;
		this.gen = new WorldGen(seed, infinite, settings.rareChance, genVersion, options);
		this.world = new World(this.gen);
		this.tilePx = settings.tilePx;
		this.viewW = 1024; this.viewH = 768;
		this.pb = makeBody(this.gen.spawnX + 0.5, 100, 0.7, 1.8);
		this.inv = new Inventory();
		this.sel = 0;
		this.lastWeaponSel = 0;
		this.maxHP = 20; this.hp = 20; this.hunger = 20; this.air = 10;
		this.dead = false; this.deathT = 0; this.hardcoreOver = false;
		this.invuln = 0; this.hurtT = 0; this.shake = 0; this.landT = 0;
		this.facing = 1; this.walkAnim = 0; this.restT = 0; this.lastVy = 0; this.fallPeak = 0;
		this.coyote = 0; this.jumpBuf = 0; this.jumpPrev = false; this.dropT = 0; this.vaultT = 0;
		this.regenT = 0; this.starveT = 0; this.drownT = 0; this.lavaT = 0; this.playerBurn = 0;
		this.clock = 0; this.playSeconds = 0; this.timeOfDay = 0.06; this.dayCount = 0;
		this.message = null; this.messageT = 0;
		this.camX = 0; this.camY = 0; this.camTX = 0; this.camTY = 0; this.camLead = 0;
		// input
		this.stick = 0; this.stickY = 0; this.keyL = false; this.keyR = false; this.jumpHeld = false; this.downHeld = false;
		this.aimX = 0; this.aimY = 0; this.aimValid = false; this.useHeld = false; this.useWasHeld = false; this.usePressedFlag = false; this.useReleasedFlag = false;
		this.pendingInteract = false; this.touchActive = false; this.downTime = 0; this.pointerStartX = 0; this.pointerStartY = 0;
		this.handEmptied = false; this.lastUsedItem = null;
		// use and mining
		this.useCD = 0; this.swingT = 0; this.swingDur = 0.25; this.swingDir = 1; this.placeCD = 0; this.eatT = 0;
		this.mining = false; this.mineX = 0; this.mineY = 0; this.mineP = 0; this.mineNeed = 1; this.bowCharge = 0;
		// things in the world
		this.drops = []; this.particles = []; this.floats = []; this.leafFlakes = []; this.decayZones = []; this.walkDoors = [];
		this.mobs = []; this.projectiles = []; this.vehicles = []; this.flashes = [];
		// panels
		this.paused = false; this.showInventory = false; this.openChest = null; this.craftStation = "hand";
		// debug and creative
		this.flying = false; this.noclip = false; this.godMode = false; this.fullBright = false; this.infiniteReach = false; this.freezeTime = false;
		// light
		this.light = new LightMap(); this.lightTimer = 0; this.lightRev = 0;
		this.lightDark = new Uint8Array(0); this.lightGlow = new Uint8Array(0);
		this.slot = null;           // the save slot this world lives in
		this.worldName = "My World";
		this.autosaveT = 0;
		this.hudRev = 0;
		this.tickMs = 0;
		this.journal = { crafted: [], relics: 0 };
		if (loadSpawn) {
			this.world.loadAround(this.gen.spawnX, 6);
			this.pb.y = this.world.surfaceY(this.gen.spawnX);
		}
		this.spawnX = this.pb.x; this.spawnY = this.pb.y;
		this.camX = this.pb.x; this.camY = this.pb.y - 2; this.camTX = this.camX; this.camTY = this.camY;
		this.setupStartingKit();
	}

	get isCreative() { return this.mode === GameMode.creative; }
	get viewTilesW() { return this.viewW / this.tilePx; }
	get viewTilesH() { return this.viewH / this.tilePx; }
	get heldStack() { return this.inv.slots[this.sel]; }
	get heldItem() { const s = this.inv.slots[this.sel]; return s ? s.id : null; }

	setupStartingKit() {
		this.maxHP = rule("health"); this.hp = this.maxHP;
		if (this.mode === GameMode.creative) return;
		this.inv.add("block:torch", 4);
	}
	say(s, t = 3) { this.message = s; this.messageT = t; this.bumpHUD(); }
	bumpHUD() { this.hudRev++; }
	addShake(a) { this.shake = Math.max(this.shake, a * this.settings.shakeScale); }

	// ---- time of day
	get dayLength() { return 60 * rule("day"); }
	/** 1 = full day, 0 = deep night */
	get dayFactor() {
		if (this.world.dim !== Dimension.overworld) return 0;
		const t = this.timeOfDay;
		if (t < 0.50) return 1;
		if (t < 0.58) return 1 - smooth((t - 0.50) / 0.08);
		if (t < 0.92) return 0;
		return smooth((t - 0.92) / 0.08);
	}
	/** how bright the open sky is (6 at night ... 15 at noon) */
	get skyLevel() {
		if (this.world.dim !== Dimension.overworld) return 0;
		const df = this.dayFactor;
		const night = 6 * (df + (1 - df) * rule("nights"));
		return Math.round(clampD(night + 9 * df, 0, 15));
	}
	get isNight() { return this.dayFactor < 0.35; }
	get biomeHere() { return this.gen.col(Math.floor(this.pb.x)).biome; }
	biomeAt(x) { return this.gen.col(Math.floor(x)).biome; }

	// ---- items
	giveItem(id, n, extra = 0) {
		const left = this.inv.add(id, n, extra);
		if (left > 0) this.spawnDrop(stack(id, left, extra), this.pb.x, this.pb.y - 1, this.facing * 3, -4);
		this.bumpHUD();
	}
	spawnDrop(s, x, y, vx, vy, heldBack = false) {
		if (!s || s.n <= 0) return;
		this.drops.push({ stack: s, x, y, vx, vy, age: 0, pickDelay: 0.5, onGround: false, heldBack });
	}
	spawnParticles(x, y, color0, n, speed, life = 0.6, grav = 18) {
		if (this.particles.length > 160) return;
		const color = artGrade(color0);
		for (let i = 0; i < n; i++) {
			const a = Math.random() * Math.PI * 2, s = rand(0.3, 1) * speed;
			this.particles.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s - speed * 0.3, life: life * rand(0.6, 1.2), maxLife: life, color, size: rand(0.08, 0.18), gravity: grav });
		}
	}
	floatText(s, x, y, color = 0xFFFFFF) {
		if (this.floats.length > 14) this.floats.shift();
		this.floats.push({ x, y, text: s, life: 1, color });
	}
	setSel(i) {
		const n = clampI(i, 0, HOTBAR_N - 1);
		if (n !== this.sel && this.heldItem && isWeaponItem(this.heldItem)) this.lastWeaponSel = this.sel;
		this.sel = n;
		this.bowCharge = 0; this.mining = false; this.mineP = 0;
		this.bumpHUD();
	}

	// ---- the master tick
	tick(rawDt) {
		if (this.paused) return;
		const t0 = performance.now();
		const dt = Math.min(Math.max(rawDt, 0.001), 0.05);
		this.clock += dt;
		if (!this.dead) this.playSeconds += dt;
		if (this.messageT > 0) { this.messageT -= dt; if (this.messageT <= 0) { this.message = null; this.bumpHUD(); } }
		this.updateTime(dt);
		this.updatePointerTimers(dt);
		this.updateInputEdges();
		this.updatePlayer(dt);
		this.updateUse(dt);
		tickHooks.forEach((f) => f(this, dt));
		this.updateDrops(dt);
		this.updateWorldTicks(dt);
		this.updateParticles(dt);
		this.updateLeafFall(dt);
		this.updateAutosave(dt);
		this.updateStreaming();
		this.updateCamera(dt);
		this.updateLight(dt);
		this.tickMs = this.tickMs * 0.9 + (performance.now() - t0) * 0.1;
	}
	updateTime(dt) {
		if (this.freezeTime || this.world.dim !== Dimension.overworld) return;
		this.timeOfDay += dt / this.dayLength;
		if (this.timeOfDay >= 1) { this.timeOfDay -= 1; this.dayCount++; }
	}
	updateInputEdges() {
		if (this.useHeld && !this.usePressedFlag && !this.useWasHeld) this.usePressedFlag = true;
		this.useWasHeld = this.useHeld;
	}

	// ---- the player
	updatePlayer(dt) {
		if (this.dead) { this.deathT += dt; return; }
		if (this.invuln > 0) this.invuln -= dt;
		if (this.hurtT > 0) this.hurtT -= dt;
		if (this.shake > 0) this.shake = Math.max(0, this.shake - dt * 1.5);
		if (this.landT > 0) this.landT -= dt;
		const pb = this.pb;
		let ix = this.stick;
		if (this.keyL) ix -= 1;
		if (this.keyR) ix += 1;
		ix = clampD(ix, -1, 1);
		if (Math.abs(ix) < 0.08) ix = 0;
		const jumpPressed = this.jumpHeld && !this.jumpPrev;
		this.jumpPrev = this.jumpHeld;
		if (playerControlHook(this, ix, jumpPressed, dt)) return;
		let runMax = 7.4 * rule("walk") * (this.inv.wearing("swiftBoots") ? 1.18 : 1);
		if (ix !== 0) this.facing = ix > 0 ? 1 : -1;
		if ((this.swingT > 0 || this.useHeld) && this.aimValid) this.facing = this.aimFacing();
		if (this.flying || this.noclip) {
			const tx = ix * 13, ty = this.jumpHeld ? -10 : (this.downHeld || this.stickY > 0.55) ? 10 : 0;
			pb.vx += (tx - pb.vx) * Math.min(1, dt * 9);
			pb.vy += (ty - pb.vy) * Math.min(1, dt * 9);
			if (this.noclip) { pb.x += pb.vx * dt; pb.y += pb.vy * dt; }
			else this.world.moveBody(pb, dt, 0, true, null);
			this.walkAnim += Math.abs(pb.vx) * dt * 0.5;
			this.lastVy = pb.vy;
			this.checkHazards(dt);
			return;
		}
		const inWater = pb.inWater, inLava = pb.inLava;
		// climbing out of water onto a ledge within reach
		if ((inWater || inLava) && this.vaultT <= 0 && this.jumpHeld && ix !== 0 && pb.hitWall && this.ledgeWithinReach(ix > 0 ? 1 : -1)) { this.vaultT = 0.32; pb.vy = -13; }
		if (this.vaultT > 0) this.vaultT -= dt;
		const swimming = (inWater || inLava) && this.vaultT <= 0;
		// ladders: jump or up to climb, down to go down
		const lc = swimming ? null : this.ladderColumn();
		if (lc !== null) {
			const climbUp = this.jumpHeld || this.stickY < -0.45, climbDown = this.downHeld || this.stickY > 0.45;
			const vyT = climbUp ? -5.2 : climbDown ? 5.2 : 0;
			pb.vy += (vyT - pb.vy) * Math.min(1, dt * 16);
			let tx = ix * runMax * 0.7;
			if (ix === 0 && (climbUp || climbDown)) tx = (lc + 0.5 - pb.x) * 8;
			pb.vx += (tx - pb.vx) * Math.min(1, dt * 14);
			this.world.moveBody(pb, dt, 1, climbDown, null);
			this.coyote = 0.11; this.jumpBuf = 0; this.fallPeak = 0;
			this.walkAnim += (Math.abs(pb.vy) + Math.abs(pb.vx)) * dt * 0.55;
			this.lastVy = pb.vy;
			this.checkHazards(dt);
			this.updateSurvival(dt, ix);
			return;
		}
		const target = ix * runMax * (swimming ? 0.55 : 1);
		const accel = pb.onGround ? 72 : 40;
		if (ix !== 0) {
			if (pb.vx < target) pb.vx = Math.min(target, pb.vx + accel * dt); else pb.vx = Math.max(target, pb.vx - accel * dt);
		} else {
			const fr = (pb.onGround ? 90 : 12) * dt;
			if (pb.vx > 0) pb.vx = Math.max(0, pb.vx - fr); else pb.vx = Math.min(0, pb.vx + fr);
		}
		if (pb.onGround) this.coyote = 0.11; else this.coyote -= dt;
		if (jumpPressed) this.jumpBuf = 0.13; else this.jumpBuf -= dt;
		if (this.jumpBuf > 0 && this.coyote > 0 && !swimming) {
			pb.vy = -15.9 * Math.sqrt(rule("jump"));
			this.coyote = 0; this.jumpBuf = 0; pb.onGround = false;
			this.spawnParticles(pb.x, pb.y, 0xB0A890, 4, 2.5, 0.35, 10);
		}
		if (swimming) {
			pb.vy += (inLava ? 14 : 11) * dt;
			if (this.jumpHeld) pb.vy = Math.max(pb.vy - 52 * dt, -6.5);
			pb.vy = clampD(pb.vy, -8, inLava ? 3 : 6);
		} else {
			let g = gravityG();
			if (!this.jumpHeld && pb.vy < -5) g *= 2.6;
			pb.vy = Math.min(pb.vy + g * dt, terminalV);
		}
		if (this.downHeld || this.stickY > 0.6) this.dropT = 0.22;
		if (this.dropT > 0) this.dropT -= dt;
		const wasAir = !pb.onGround;
		this.world.moveBody(pb, dt, 1, this.dropT > 0, null);
		this.doorTouch(ix);
		this.updateWalkDoors(dt);
		if (!pb.onGround && pb.vy > 0) this.fallPeak = Math.max(this.fallPeak, pb.vy);
		if (pb.onGround && wasAir) {
			if (this.fallPeak > 20 && !swimming && this.mode !== GameMode.creative && !this.godMode) {
				const dmg = (this.fallPeak - 20) * 1.15 * rule("falls");
				if (dmg > 0) this.damagePlayer(dmg, pb.x, 0, true);
				this.addShake(0.3);
			}
			if (this.fallPeak > 9) this.spawnParticles(pb.x, pb.y, 0xB0A890, 6, 3, 0.4, 10);
			if (this.fallPeak > 6) { sfx("land", clampD((this.fallPeak - 6) / 14, 0.2, 1)); this.landT = 0.12; }
			this.fallPeak = 0;
		}
		if (pb.onGround || swimming) this.fallPeak = 0;
		this.walkAnim += Math.abs(pb.vx) * dt * 0.55;
		const still = pb.onGround && Math.abs(pb.vx) < 0.15 && Math.abs(ix) < 0.1 && this.swingT <= 0 && !this.mining && this.hurtT <= 0;
		this.restT = still ? this.restT + dt : 0;
		this.lastVy = pb.vy;
		this.checkHazards(dt);
		this.updateSurvival(dt, ix);
	}
	/** the column of a ladder the body is on, or null */
	ladderColumn() {
		const pb = this.pb;
		const cx = Math.floor(pb.x), frac = pb.x - cx;
		const cols = [cx];
		if (frac < 0.34) cols.push(cx - 1); else if (frac > 0.66) cols.push(cx + 1);
		const y0 = Math.floor(bodyTop(pb) + 0.1), y1 = Math.floor(pb.y + 0.05);
		for (const tx of cols) for (let y = y0; y <= y1; y++) {
			const t = this.world.tile(tx, y);
			if (t === T.ladder) return tx;
			if (t === T.platform && this.world.tile(tx, y + 1) === T.ladder) return tx;
		}
		return null;
	}
	ledgeWithinReach(dir) {
		const pb = this.pb, w = this.world;
		const fx = Math.floor(pb.x + dir * (pb.w * 0.5 + 0.15)), feet = Math.floor(pb.y - 0.05);
		for (let k = 0; k <= 3; k++) {
			const row = feet - k;
			if (!w.solid(fx, row) && !w.solid(fx, row - 1) && w.solid(fx, row + 1)) return pb.y - (row + 1) <= 2.6;
		}
		return false;
	}
	checkHazards(dt) {
		if (this.mode === GameMode.creative || this.godMode) return;
		const pb = this.pb, w = this.world;
		let t = w.boxHurts(bodyLeft(pb) + 0.05, bodyTop(pb) + 0.1, bodyRight(pb) - 0.05, pb.y - 0.02);
		if (t < 0) t = w.boxHurts(bodyLeft(pb) - 0.04, bodyTop(pb) + 0.2, bodyRight(pb) + 0.04, pb.y - 0.1);
		if (t === T.spikes || t === T.cactus) this.damagePlayer(t === T.spikes ? 6 : 3, pb.x - this.facing, 5, false);
		if (w.tile(Math.floor(pb.x), Math.floor(pb.y - 0.5)) === T.campfire) this.playerBurn = Math.max(this.playerBurn, 1.2);
		if (pb.inLava) {
			const charm = this.inv.wearing("emberCharm");
			this.playerBurn = Math.max(this.playerBurn, charm ? 1 : 2.5);
			this.lavaT += dt;
			if (this.lavaT > 0.35) { this.lavaT = 0; this.damagePlayer(charm ? 2 : 5, pb.x, 0, false); }
		} else this.lavaT = 0;
		if (this.playerBurn > 0) {
			this.playerBurn -= dt;
			if (pb.inWater) this.playerBurn = 0;
			this.burnTick = (this.burnTick || 0) + dt;
			if (this.burnTick > 0.6) { this.burnTick = 0; this.damagePlayer(1, pb.x, 0, true); this.spawnParticles(pb.x, pb.y - 1, 0xFF8A2A, 3, 2, 0.4, -4); }
		}
	}
	headUnderWater() {
		const pb = this.pb;
		const hy = pb.y - pb.h * 0.92, hx = Math.floor(pb.x), hyI = Math.floor(hy);
		const t = this.world.tile(hx, hyI);
		if (!LIQUID[t] || t === T.lava) return false;
		if (hy - hyI < 1 - this.world.liquidAmount(hx, hyI)) return false;
		return true;
	}
	updateSurvival(dt, ix) {
		if (this.mode === GameMode.creative) return;
		if (this.headUnderWater()) {
			this.air -= dt * (this.inv.wearing("divingMask") ? 1 / 3 : 1);
			if (this.air <= 0) {
				this.air = 0;
				this.drownT += dt;
				if (this.drownT >= 1) { this.drownT = 0; this.damagePlayer(2, this.pb.x, 0, true); }
			}
		} else { this.air = Math.min(10, this.air + dt * 5); this.drownT = 0; }
		const rate = (ix !== 0 ? 0.030 : 0.016) * (this.pb.inWater ? 1.3 : 1);
		this.hunger = Math.max(0, this.hunger - rate * rule("hunger") * dt);
		if (this.hunger <= 0) {
			this.starveT += dt;
			if (this.starveT >= 3) { this.starveT = 0; if (this.hp > 1 || this.mode === GameMode.hardcore) this.damagePlayer(1, this.pb.x, 0, true); }
		} else this.starveT = 0;
		const healRule = rule("healing");
		if (this.hunger >= 14 && this.hp < this.maxHP && healRule > 0) {
			this.regenT += dt;
			if (this.regenT >= (this.hunger >= 18 ? 0.9 : 1.6) / healRule) { this.regenT = 0; this.hp = Math.min(this.maxHP, this.hp + 1); this.hunger = Math.max(0, this.hunger - 0.12); this.bumpHUD(); }
		} else this.regenT = 0;
	}
	/** the share of a blow armour takes: 4% a point, at most 80% */
	armorShare(defense) { return Math.min(0.8, Math.max(0, defense) * 0.04); }
	get totalDefense() { return this.inv.defense; }
	damagePlayer(dmg, sx, knock = 6, ignoreArmor = false) {
		if (this.dead || this.godMode || this.mode === GameMode.creative) return;
		if (this.invuln > 0 && !ignoreArmor) return;
		const hurtRule = rule("hurt");
		if (hurtRule <= 0) return;
		let d = dmg * hurtRule;
		if (!ignoreArmor) d *= 1 - this.armorShare(this.totalDefense);
		d = Math.max(1, Math.round(d));
		this.hp -= d;
		sfx("hurt", 0.8);
		this.invuln = 0.55; this.hurtT = 0.35;
		if (knock > 0) { this.pb.vx = (this.pb.x >= sx ? 1 : -1) * knock; this.pb.vy = -6; }
		this.floatText("-" + d, this.pb.x, this.pb.y - this.pb.h - 0.3, 0xFF5050);
		this.addShake(0.2);
		this.bumpHUD();
		if (this.hp <= 0) this.die();
	}
	heal(n) { this.hp = Math.min(this.maxHP, this.hp + n); this.bumpHUD(); }
	die() {
		if (this.dead) return;
		if (rule("deathDrop") > 0) {
			for (let i = 0; i < this.inv.slots.length; i++) { const s = this.inv.slots[i]; if (s) { this.spawnDrop(s, this.pb.x, this.pb.y - 1, rand(-3, 3), -4); this.inv.slots[i] = null; } }
		}
		this.dead = true; this.hp = 0; this.deathT = 0;
		this.spawnParticles(this.pb.x, this.pb.y - 1, 0xC03030, 24, 6, 0.9, 16);
		this.say(this.mode === GameMode.hardcore ? "You died. Your hardcore world is lost." : "You died!", 5);
		if (this.mode === GameMode.hardcore) this.hardcoreOver = true;
		this.bumpHUD();
	}
	respawn() {
		if (this.mode === GameMode.hardcore && this.hardcoreOver) return;
		this.dead = false; this.hp = this.maxHP; this.hunger = Math.max(this.hunger, 14); this.air = 10;
		const pb = this.pb;
		pb.x = this.spawnX; pb.y = this.spawnY; pb.vx = 0; pb.vy = 0;
		this.invuln = 3; this.fallPeak = 0;
		this.world.loadAround(Math.floor(this.spawnX), 3);
		if (SOLID[this.world.tile(Math.floor(pb.x), Math.floor(pb.y - 0.5))]) pb.y = this.world.surfaceY(Math.floor(this.spawnX));
		this.camX = pb.x; this.camY = pb.y - 2;
		this.say("Respawned.", 2);
	}

	// ---- camera, streaming, light
	updateCamera(dt) {
		const st = this.settings, pb = this.pb;
		let leadTarget = 0;
		if (st.camLookAhead && !st.camDirect && Math.abs(pb.vx) > 1) leadTarget = this.facing * 1.6;
		this.camLead += (leadTarget - this.camLead) * Math.min(1, dt * 2.5);
		const fx = pb.x + this.camLead, fy = pb.y - 1.6;
		const dz = st.camDirect ? 0 : clampD(st.camDeadZone, 0, 4);
		if (fx > this.camTX + dz) this.camTX = fx - dz; else if (fx < this.camTX - dz) this.camTX = fx + dz;
		const dzy = dz * 0.75;
		if (fy > this.camTY + dzy) this.camTY = fy - dzy; else if (fy < this.camTY - dzy) this.camTY = fy + dzy;
		if (Math.abs(this.camTX - this.camX) > 40 || Math.abs(this.camTY - this.camY) > 40 || !st.camSmoothOn) { this.camX = this.camTX; this.camY = this.camTY; }
		else {
			const rate = st.camDirect ? 12 : 2.5 + clampD(st.camFollow, 0, 1) * 11.5;
			const k = 1 - Math.exp(-rate * dt);
			this.camX += (this.camTX - this.camX) * k;
			this.camY += (this.camTY - this.camY) * k;
		}
		const halfW = this.viewTilesW * 0.5, halfH = this.viewTilesH * 0.5;
		if (!this.gen.infinite && this.viewTilesW < this.gen.width) this.camX = clampD(this.camX, halfW, this.gen.width - halfW);
		this.camY = clampD(this.camY, halfH - 14, this.world.H - halfH + 1);
	}
	updateStreaming() {
		const radius = Math.ceil(this.viewTilesW * 0.5 / chunkW) + 2;
		const keep = streamKeep(this);
		this.world.stream(Math.floor(this.camX), radius, 3, 1, keep);
		const pc = floorDiv(Math.floor(this.pb.x), chunkW);
		if (!this.world.chunks.has(pc)) this.world.loadChunk(pc);
	}
	heldLightLevel() {
		const id = this.heldItem;
		if (!id) return 0;
		const t = itemTile(id);
		if (t >= 0 && LIGHT[t] >= 9) return LIGHT[t] - 2;
		return 0;
	}
	/** moving lights: a flat list of x, y, level */
	dynamicLights() {
		const pb = this.pb;
		let hl = Math.max(this.heldLightLevel(), this.inv.wearing("headlamp") ? 11 : 5);
		const out = [Math.floor(pb.x), Math.floor(pb.y - pb.h * 0.6), hl];
		lightHooks.forEach((f) => f(this, out));
		return out;
	}
	updateLight(dt) {
		this.lightTimer -= dt;
		const dyn = this.dynamicLights();
		let key = dyn.length;
		for (let i = 0; i < dyn.length; i++) key = (Math.imul(key, 31) + dyn[i] * (i % 3 === 0 ? 7 : i % 3 === 1 ? 13 : 1)) | 0;
		const light = this.light, world = this.world;
		const vw = Math.ceil(this.viewTilesW) + 2, vh = Math.ceil(this.viewTilesH) + 2;
		const vx0 = Math.floor(this.camX - this.viewTilesW * 0.5) - 1, vy0 = Math.floor(this.camY - this.viewTilesH * 0.5) - 1;
		const covered = light.covers(vx0 - 3, vy0 - 3, vx0 + vw + 3, vy0 + vh + 3);
		let edited = false;
		if (world.editAny) {
			if (world.editX1 >= light.ox - 1 && world.editX0 <= light.ox + light.w && world.editY1 >= light.oy - 1 && world.editY0 <= light.oy + light.h) edited = true;
			else world.editAny = false;
		}
		const needsStatic = !light.valid || !covered || light.skyUsed !== this.skyLevel || light.dimUsed !== world.dim || edited || light.layoutUsed !== world.layoutVersion;
		const amb = this.ambientLight();
		const t0 = performance.now();
		if (!needsStatic) {
			if (light.dynUsed === key && light.ambUsed === amb && light.nightUsed === this.dayFactor) return;
			light.applyDynamic(dyn);
		} else {
			if (this.lightTimer > 0 && light.valid && covered && light.dimUsed === world.dim) return;
			this.lightTimer = 0.04;
			const m = 17;
			const ox = floorDiv(vx0 - m, 4) * 4, oy = floorDiv(vy0 - m, 4) * 4;
			const w = (Math.floor(((vx0 + vw + m) - ox + 4) / 4) + 1) * 4, h = (Math.floor(((vy0 + vh + m) - oy + 4) / 4) + 1) * 4;
			light.compute(world, ox, oy, w, h, this.skyLevel, dyn);
		}
		light.dynUsed = key; light.ambUsed = amb; light.nightUsed = this.dayFactor;
		const n = light.w * light.h * 4;
		if (this.lightDark.length !== n) { this.lightDark = new Uint8Array(n); this.lightGlow = new Uint8Array(n); }
		light.buildPixels(this.lightDark, this.lightGlow, amb, 1 - this.dayFactor);
		this.lightRev++;
		PERF.lightMs = PERF.lightMs * 0.9 + (performance.now() - t0) * 0.1;
	}
	ambientLight() {
		if (this.fullBright) return 1;
		return this.world.dim === Dimension.umbral ? 0.2 : 0.07;
	}

	// ---- random world ticks: crops grow, grass spreads, saplings grow, cut crowns wither
	updateWorldTicks(dt) {
		const px = Math.floor(this.pb.x), py = Math.floor(this.pb.y), w = this.world;
		for (let k = 0; k < 7; k++) {
			const x = px + randInt(-40, 40), y = py + randInt(-26, 26);
			const t = w.tile(x, y);
			const grow = 0.35;
			if (t === T.wheat1) { if (Math.random() < grow) w.set(x, y, T.wheat2); }
			else if (t === T.wheat2) { if (Math.random() < grow) w.set(x, y, T.wheat3); }
			else if (t === T.carrot1) { if (Math.random() < grow) w.set(x, y, T.carrot2); }
			else if (t === T.carrot2) { if (Math.random() < grow) w.set(x, y, T.carrot3); }
			else if (t === T.sapling) { if (Math.random() < grow * 0.4) this.growSapling(x, y); }
			else if (t === T.dirt) {
				if (w.dim === Dimension.overworld && y < w.skyTop(x) + 1 && w.tile(x, y - 1) === T.air) {
					if ((w.tile(x - 1, y) === T.grass || w.tile(x + 1, y) === T.grass) && Math.random() < 0.2) w.set(x, y, T.grass);
				}
			} else if (t === T.grass) {
				if (OPAQUE[w.tile(x, y - 1)] && Math.random() < 0.3) w.set(x, y, T.dirt);
			}
		}
		this.updateLeafDecay(dt);
	}
	treeRoom(t) { return t === T.air || t === T.tallGrass || t === T.flowerR || t === T.flowerY || t === T.deadBush; }
	/** a sapling grows into a tree that suits its land, as tall as the room above allows */
	growSapling(x, y) {
		const w = this.world;
		if (w.tile(x, y) !== T.sapling || !w.isSoil(w.tile(x, y + 1))) return false;
		const r = Math.random();
		let log = T.log, leaves = T.leaves, shape = 0;
		const B = Biome;
		switch (this.biomeAt(x)) {
			case B.tundra: case B.mountain: shape = 2; leaves = T.pineLeaves; break;
			case B.jungle: shape = 3; log = T.jungleLog; leaves = T.jungleLeaves; break;
			case B.savanna: shape = 4; break;
			case B.swamp: shape = 5; leaves = T.jungleLeaves; break;
			default: if (r < 0.3) { shape = 1; log = T.birchLog; leaves = T.birchLeaves; }
		}
		const wants = [4 + Math.floor(r * 4), 6 + Math.floor(r * 4), 6 + Math.floor(r * 5), 9 + Math.floor(r * 6), 5 + Math.floor(r * 3), 4 + Math.floor(r * 2)];
		const least = [4, 5, 6, 8, 5, 4];
		let room = 1;
		while (room < wants[shape] + 2 && this.treeRoom(w.tile(x, y - room))) room++;
		const th = Math.min(wants[shape], room - 2);
		if (th < least[shape]) return false;
		const gy = y + 1;
		for (let k = 1; k <= th; k++) w.set(x, gy - k, log);
		const leaf = (lx, ly) => { if (this.treeRoom(w.tile(lx, ly))) w.set(lx, ly, leaves); };
		const top = gy - th;
		if (shape === 1) { for (let dy = -4; dy <= 0; dy++) { const ww = (dy === -4 || dy === 0) ? 1 : 2; for (let dx = -ww; dx <= ww; dx++) leaf(x + dx, top + dy); } leaf(x, top - 5); }
		else if (shape === 2) { for (let layer = 0; layer < th - 1; layer++) { const ww = Math.min(3, 1 + Math.floor(layer / 2)); for (let dx = -ww; dx <= ww; dx++) leaf(x + dx, top - 1 + layer); } leaf(x, top - 2); }
		else if (shape === 3) { for (let dy = -3; dy <= 1; dy++) for (let dx = -4; dx <= 4; dx++) if (!(Math.abs(dx) === 4 && Math.abs(dy + 1) > 1) && Math.abs(dx) + Math.abs(dy + 1) <= 6) leaf(x + dx, top + dy); }
		else if (shape === 4) { for (let dx = -4; dx <= 4; dx++) leaf(x + dx, top); for (let dx = -2; dx <= 2; dx++) leaf(x + dx, top - 1); }
		else if (shape === 5) { for (let dx = -3; dx <= 3; dx++) { leaf(x + dx, top); if (Math.abs(dx) < 3) leaf(x + dx, top - 1); } }
		else { for (let dy = -3; dy <= 1; dy++) for (let dx = -2; dx <= 2; dx++) if (!(Math.abs(dx) === 2 && (dy === -3 || dy === 1))) leaf(x + dx, top + dy); }
		this.spawnParticles(x + 0.5, top + 0.5, 0x56A83F, 8, 3, 0.6, 10);
		return true;
	}
	logNear(x, y, r) {
		for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) if (IS_LOG[this.world.tile(x + dx, y + dy)]) return true;
		return false;
	}
	/** where a trunk was cut, leaves with no trunk nearby wither over half a minute */
	updateLeafDecay(dt) {
		if (!this.decayZones.length) return;
		const keep = [];
		for (const z of this.decayZones) {
			z.t -= dt;
			for (let k = 0; k < 4; k++) {
				const x = z.x + randInt(-7, 7), y = z.y + randInt(-10, 4);
				if (IS_LEAF[this.world.tile(x, y)] && !this.logNear(x, y, 4)) this.breakTile(x, y, false);
			}
			if (z.t > 0) keep.push(z);
		}
		this.decayZones = keep;
	}

	// ---- drops, particles, leaves, floating text
	updateDrops(dt) {
		const pb = this.pb;
		for (let i = 0; i < this.drops.length; i++) {
			const d = this.drops[i];
			d.age += dt;
			if (d.pickDelay > 0) d.pickDelay -= dt;
			if (d.age > 400) { this.drops.splice(i--, 1); continue; }
			const px = pb.x, py = pb.y - pb.h * 0.5;
			const dx = px - d.x, dy = py - (d.y - 0.15);
			const dist = Math.hypot(dx, dy);
			if (d.heldBack && dist > 3.6) d.heldBack = false;
			const canTake = !this.dead && d.pickDelay <= 0 && !d.heldBack && this.inv.canFit(d.stack.id, 1);
			if (canTake && dist < 3.2) {
				const k = 16 * (1 + (3.2 - dist) * 0.3) / Math.max(dist, 0.1);
				d.vx = dx * k; d.vy = dy * k;
				d.x += d.vx * dt; d.y += d.vy * dt;
			} else {
				const b = Drops.body;
				b.x = d.x; b.y = d.y; b.vx = d.vx; b.vy = d.vy; b.onGround = d.onGround;
				b.vy = Math.min(b.vy + gravityG() * 0.8 * dt, 18);
				b.vx *= 1 - Math.min(1, dt * (d.onGround ? 6 : 0.6));
				this.world.moveBody(b, dt, 0, false, null);
				if (b.inWater) { b.vy = Math.min(b.vy, 1.5); b.vx *= 0.9; }
				d.x = b.x; d.y = b.y; d.vx = b.vx; d.vy = b.vy; d.onGround = b.onGround;
			}
			if (canTake && dist < 0.9) {
				const left = this.inv.add(d.stack.id, d.stack.n, d.stack.extra, d.stack.inf);
				if (left < d.stack.n) {
					if (d.stack.id === "mat:relicFragment") this.journal.relics += d.stack.n - left;
					sfx("pickup", 0.5);
					this.floatText("+" + (d.stack.n - left) + " " + itemName(d.stack.id), px, pb.y - pb.h - 0.5, 0xFFF0A0);
					this.bumpHUD();
				}
				if (left === 0) { this.drops.splice(i--, 1); continue; }
				d.stack.n = left;
			}
		}
	}
	updateParticles(dt) {
		let w = 0;
		for (const p of this.particles) {
			p.life -= dt;
			if (p.life <= 0) continue;
			p.vy += p.gravity * dt; p.x += p.vx * dt; p.y += p.vy * dt;
			this.particles[w++] = p;
		}
		this.particles.length = w;
		w = 0;
		for (const f of this.floats) { f.life -= dt * 0.8; f.y -= dt * 0.9; if (f.life > 0) this.floats[w++] = f; }
		this.floats.length = w;
	}
	/** a leaf come loose from a canopy, drifting down */
	dropLeaf(x, y, t) {
		if (this.leafFlakes.length > 90) return;
		const tn = Painter.leafTones.get(t) || [0xFF4A9A6A, 0xFF3A7A4C];
		this.leafFlakes.push({ x, y, vy: rand(0.6, 1.2), phase: Math.random() * 6, life: rand(7, 11), light: tn[1], dark: tn[2] || tn[1], landed: false });
	}
	updateLeafFall(dt) {
		// leaves come loose from the canopies on screen now and then
		if (Math.random() < dt * 0.9) {
			const x = Math.floor(this.camX + rand(-0.5, 0.5) * this.viewTilesW), y0 = Math.floor(this.camY - this.viewTilesH * 0.5);
			for (let y = y0; y < y0 + this.viewTilesH; y++) {
				const t = this.world.tile(x, y);
				if (IS_LEAF[t]) { if (this.world.tile(x, y + 1) === T.air) this.dropLeaf(x + Math.random(), y + 1.0, t); break; }
				if (SOLID[t]) break;
			}
		}
		let w = 0;
		for (const f of this.leafFlakes) {
			f.life -= dt;
			if (f.life <= 0) continue;
			if (!f.landed) {
				f.phase += dt * 2.2;
				f.x += Math.sin(f.phase) * 0.9 * dt;
				f.y += f.vy * dt;
				const t = this.world.tile(Math.floor(f.x), Math.floor(f.y + 0.05));
				if (SOLID[t] || LIQUID[t]) { f.landed = true; f.y = Math.floor(f.y + 0.05) - 0.06; f.life = Math.min(f.life, 2.5); }
			}
			this.leafFlakes[w++] = f;
		}
		this.leafFlakes.length = w;
	}
	updateAutosave(dt) {
		if (!this.settings.autosave || this.isTest) return;
		this.autosaveT += dt;
		if (this.autosaveT >= 60) { this.autosaveT = 0; saveGameSoon(this); }
	}

	// ---- doors
	isDoor(t) { return t === T.doorClosed || t === T.doorOpen; }
	doorCells(x, y) {
		const w = this.world;
		let top = y, bot = y;
		if (this.isDoor(w.tile(x, y - 1)) && !this.isDoor(w.tile(x, y + 1))) top = y - 1;
		else if (this.isDoor(w.tile(x, y + 1))) bot = y + 1;
		return [top, bot];
	}
	doorBlocked(x, top, bot) {
		const pb = this.pb;
		if (bodyRight(pb) > x + 0.05 && bodyLeft(pb) < x + 0.95 && pb.y > top + 0.05 && bodyTop(pb) < bot + 0.95) return true;
		for (const m of this.mobs) if (m.hp > 0 && bodyRight(m.b) > x + 0.05 && bodyLeft(m.b) < x + 0.95 && m.b.y > top + 0.05 && bodyTop(m.b) < bot + 0.95) return true;
		return false;
	}
	setDoor(x, y, open) {
		const c = this.doorCells(x, y);
		if (!open && this.doorBlocked(x, c[0], c[1])) return;
		for (let yy = c[0]; yy <= c[1]; yy++) if (this.isDoor(this.world.tile(x, yy))) this.world.set(x, yy, open ? T.doorOpen : T.doorClosed);
	}
	toggleDoor(x, y) {
		this.setDoor(x, y, this.world.tile(x, y) === T.doorClosed);
		sfx("door", 0.7);
		this.spawnParticles(x + 0.5, y + 0.5, 0xA97B45, 2, 1.5, 0.3, 8);
	}
	/** walking into a closed door opens it, and it closes behind the player */
	doorTouch(ix) {
		if (ix === 0) return;
		const pb = this.pb;
		const fx = Math.floor(pb.x + (ix > 0 ? 1 : -1) * (pb.w * 0.5 + 0.2));
		for (const yy of [Math.floor(pb.y - 0.5), Math.floor(pb.y - 1.4)]) {
			if (this.world.tile(fx, yy) === T.doorClosed) {
				this.setDoor(fx, yy, true);
				const c = this.doorCells(fx, yy);
				if (!this.walkDoors.some((w) => w.x === fx && w.y === c[0]) && this.walkDoors.length < 16) this.walkDoors.push({ x: fx, y: c[0], t: 0 });
				break;
			}
		}
	}
	updateWalkDoors(dt) {
		if (!this.walkDoors.length) return;
		const keep = [], pb = this.pb;
		for (const w of this.walkDoors) {
			w.t += dt;
			if (this.world.tile(w.x, w.y) !== T.doorOpen) continue;
			const c = this.doorCells(w.x, w.y);
			const away = Math.abs(pb.x - (w.x + 0.5)) > pb.w * 0.5 + 1.1 || pb.y < c[0] - 0.5 || bodyTop(pb) > c[1] + 1.5;
			if (w.t > 0.5 && away && !this.doorBlocked(w.x, c[0], c[1])) { this.setDoor(w.x, w.y, false); sfx("door", 0.5); continue; }
			if (w.t < 60) keep.push(w);
		}
		this.walkDoors = keep;
	}

	// ---- crafting
	stationAvailable(s) {
		if (s === "hand" || this.isCreative) return true;
		const tiles = STATION_TILES[s];
		if (!tiles) return false;
		const px = Math.floor(this.pb.x), py = Math.floor(this.pb.y - 1);
		for (let dy = -4; dy <= 3; dy++) for (let dx = -5; dx <= 5; dx++) if (tiles.includes(this.world.tile(px + dx, py + dy))) return true;
		return false;
	}
	canCraft(r) { return this.stationAvailable(r.station) && this.inv.canAfford(r.cost) && this.inv.canFit(r.out, r.n); }
	craft(r) {
		if (!this.canCraft(r)) { if (!this.stationAvailable(r.station)) this.say("Needs a " + STATION_NAMES[r.station] + " nearby.", 2); return false; }
		for (const c of r.cost) this.inv.remove(c[0], c[1]);
		if (!this.journal.crafted.includes(r.out)) this.journal.crafted.push(r.out);
		sfx("craft", 0.6);
		const left = this.inv.add(r.out, r.n);
		if (left > 0) this.spawnDrop(stack(r.out, left), this.pb.x, this.pb.y - 1, 2, -3);
		this.floatText("+" + r.n + " " + itemName(r.out), this.pb.x, this.pb.y - 2.2, 0xFFE070);
		this.bumpHUD();
		return true;
	}
	/** how many times a recipe could be made now */
	craftableCount(r) {
		let n = 99;
		for (const c of r.cost) n = Math.min(n, Math.floor(this.inv.total(c[0]) / c[1]));
		return n;
	}
}

// Later phases add to the tick, the lights and what streaming keeps loaded through these lists.
const tickHooks = [];
const lightHooks = [];
function streamKeep(g) { return null; }
/** vehicles, mounts and seats take the controls in later phases; true when one did */
function playerControlHook(g, ix, jumpPressed, dt) { return false; }
const Drops = { body: makeBody(0, 0, 0.3, 0.3) };
