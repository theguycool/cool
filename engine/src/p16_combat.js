// Fighting (the Swift game's p16a_combat, p16c_damage and the player's weapons from p14d_tools and
// p20_assist). Every source of harm builds a damage record and goes through the same few functions:
// they decide who can be hurt (sides), stop one attack hitting the same target every frame (keys),
// apply armour and resistances, push targets back and remember whom to credit for a kill.

const BYPASS_ARMOR = new Set(["fire", "lava", "fall", "drown", "starve", "poison"]);
const AREA_DAMAGE = new Set(["explosion", "stomp", "impact", "crush", "fire", "lava", "hazard"]);
const SRC_PLAYER = { kind: "player", id: 0, faction: "player", mult: 1 };
const SRC_ENV = { kind: "env", id: -1, faction: "environment", mult: 1 };
const BARE_HANDS = { damage: 1.5, cooldown: 0.4, reach: 1.8, halfArc: 0.75, style: "bash", knock: 4, swingTime: 0.22, trail: 0xE8D8C8, band: 0.55, critChance: 0.1, backstab: 1, combo: false, heavy: false, daze: 0, burn: 0, maxHits: 99, undeadMult: 1, windup: 0, shockwave: false };
let attackSerial = 0;
const newAttackKey = () => ++attackSerial;
function dinfo(amount, type, source) { return { amount, type, source, dirX: 0, knock: 0, originX: 0, originY: 0, key: 0, cooldown: 0.5, heavy: false, crit: false }; }
const srcMob = (g, m) => ({ kind: "mob", id: m.id, faction: g.faction(m), mult: mobDmgMul(m) });

/** the share of damage of a type a creature takes (1 = all of it) */
function damageResist(k, t) {
	const r = DAMAGE_RESIST[k + ":" + t];
	return r === undefined ? 1 : r;
}
const DAMAGE_RESIST = {};
for (const [list, v] of [
	[["imp:fire", "emberSlime:fire", "cinderBat:fire", "imp:lava", "emberSlime:lava", "cinderBat:lava"], 0],
	[["wraith:fall", "bat:fall", "cinderBat:fall", "crow:fall", "sentinel:fall", "warden:fall", "warden:lava", "mimic:fall"], 0],
	[["skeleton:projectile"], 0.75], [["bearBoss:lava", "rex:lava"], 0.5], [["bearBoss:explosion", "rex:explosion"], 0.6],
	[["slime:fall", "emberSlime:fall", "cat:fall", "frog:fall"], 0.2], [["golem:melee", "golem:contact"], 0.55], [["golem:projectile"], 0.35],
	[["golem:fire", "golem:fall"], 0.2], [["golem:explosion"], 1.25], [["sentinel:projectile"], 0.8], [["warden:explosion"], 0.7],
	[["golem:shock"], 0.6], [["sentinel:shock"], 0.5], [["warden:shock"], 0.75],
	[["zombie:poison", "skeleton:poison", "wraith:poison", "golem:poison", "sentinel:poison", "warden:poison", "slime:poison", "emberSlime:poison"], 0],
]) for (const k of list) DAMAGE_RESIST[k] = v;

/** where a segment enters a box (0...1 along it), or -1 */
function segmentBoxT(x0, y0, x1, y1, bx0, by0, bx1, by1) {
	const dx = x1 - x0, dy = y1 - y0;
	let tmin = 0, tmax = 1;
	if (Math.abs(dx) < 1e-9) { if (x0 < bx0 || x0 > bx1) return -1; }
	else { let ta = (bx0 - x0) / dx, tb = (bx1 - x0) / dx; if (ta > tb) { const s = ta; ta = tb; tb = s; } tmin = Math.max(tmin, ta); tmax = Math.min(tmax, tb); if (tmin > tmax) return -1; }
	if (Math.abs(dy) < 1e-9) { if (y0 < by0 || y0 > by1) return -1; }
	else { let ta = (by0 - y0) / dy, tb = (by1 - y0) / dy; if (ta > tb) { const s = ta; ta = tb; tb = s; } tmin = Math.max(tmin, ta); tmax = Math.min(tmax, tb); if (tmin > tmax) return -1; }
	return tmin;
}
const SEG_HIT = [0, 0, 0];
Object.assign(World.prototype, {
	/** the first solid tile along a segment: SEG_HIT = [x, y, fraction] and true, or false */
	segmentSolid(x0, y0, x1, y1) {
		const dx = x1 - x0, dy = y1 - y0;
		const n = Math.max(1, Math.ceil(Math.hypot(dx, dy) / 0.2));
		for (let i = 1; i <= n; i++) {
			const t = i / n, tx = Math.floor(x0 + dx * t), ty = Math.floor(y0 + dy * t);
			if (SOLID[this.tile(tx, ty)]) {
				const et = segmentBoxT(x0, y0, x1, y1, tx, ty, tx + 1, ty + 1);
				SEG_HIT[0] = tx; SEG_HIT[1] = ty; SEG_HIT[2] = et < 0 ? t : et;
				return true;
			}
		}
		return false;
	},
	lineClear(x0, y0, x1, y1) { return !this.segmentSolid(x0, y0, x1, y1); },
});
function angleDiff(a, b) { let d = a - b; while (d > Math.PI) d -= 2 * Math.PI; while (d < -Math.PI) d += 2 * Math.PI; return d; }
/** the launch angle for a shot of speed v under gravity g to pass through (dx, dy), on the flatter arc */
function lobAngle(dx, dy, v, g) {
	if (g <= 0.001) return Math.atan2(dy, dx);
	const x = Math.max(0.001, Math.abs(dx)), up = -dy, v2 = v * v;
	const disc = v2 * v2 - g * (g * x * x + 2 * up * v2);
	const th = disc < 0 ? Math.PI * 0.25 : Math.atan((v2 - Math.sqrt(disc)) / (g * x));
	return dx >= 0 ? -th : Math.PI + th;
}
const THROW_SPEED = 15, THROW_GRAVITY = 22;
const BOW = { minSpeed: 20, maxSpeed: 40, baseDamage: 5, chargeDamage: 9, chargeTime: 0.55, useTime: 0.32, gravity: 15 };
const SLING_AMMO = ["block:stone", "block:slate", "block:deepRock", "block:sandstone", "block:ashStone"];
const MELEE_KINDS = new Set(["sword", "spear", "hammer", "knife", "club", "relic"]);
function meleeOf(id) { return id ? (itemDef(id).melee || BARE_HANDS) : BARE_HANDS; }
const MOB_GRID = 8;

Object.assign(Game.prototype, {
	// ---- sides
	faction(m) {
		if (m.tame) return "ally";
		if (m.kind === "pirate" || m.kind === "pirateGunner" || m.kind === "pirateCaptain") return "pirate";
		if (m.kind === "imp" || m.kind === "emberSlime" || m.kind === "cinderBat") return "umbral";
		if (BOSS_KINDS.has(m.kind)) return "boss";
		return m.def.hostile ? "hostile" : "wild";
	},
	canHarm(src, tf, targetID, area) {
		if (src.kind === "mob" && src.id === targetID) return false;
		if (src.kind === "player" && tf === "player") return false;
		switch (src.faction) {
			case "environment": case "boss": return true;
			case "player": return tf !== "ally";
			case "ally": return tf !== "player" && tf !== "ally";
			default: return area ? true : tf !== src.faction;
		}
	},
	// ---- creatures by place: buckets of 8 columns, made again each frame
	rebuildMobGrid() {
		const grid = this.mobGrid || (this.mobGrid = new Map());
		for (const b of grid.values()) b.length = 0;
		for (const m of this.mobs) {
			if (m.hp <= 0 || m.removed) continue;
			const k = floorDiv(Math.floor(m.b.x), MOB_GRID);
			let b = grid.get(k);
			if (!b) { b = []; grid.set(k, b); }
			b.push(m);
		}
		if (grid.size > 256) for (const [k, b] of grid) if (!b.length) grid.delete(k);
	},
	mobsNear(x0, x1) {
		const c0 = floorDiv(Math.floor(x0), MOB_GRID), c1 = floorDiv(Math.floor(x1), MOB_GRID);
		if (c1 - c0 > 64 || !this.mobGrid) return this.mobs;
		const out = [];
		for (let c = c0; c <= c1; c++) { const b = this.mobGrid.get(c); if (b) for (const m of b) out.push(m); }
		return out;
	},
	isThreat(m) {
		if (m.angry) return true;
		if (isWildAnimal(m.kind)) return this.clock - m.lastHitByPlayer < 12;
		return !!m.def.hostile;
	},
	wildProvoked(m) { return this.clock - m.lastHitByPlayer < 12; },
	heatImmune(m) { return HEAT_IMMUNE.has(m.kind); },

	// ---- applying damage
	applyMobDamage(m, info) {
		if (m.hp <= 0 || m.removed) return false;
		if (!this.canHarm(info.source, this.faction(m), m.id, AREA_DAMAGE.has(info.type))) return false;
		if (info.key !== 0) {
			const last = m.hitStamps.get(info.key);
			if (last !== undefined && this.clock - last < info.cooldown) return false;
			m.hitStamps.set(info.key, this.clock);
			if (m.hitStamps.size > 24) for (const [k, t] of m.hitStamps) if (this.clock - t >= 4) m.hitStamps.delete(k);
		}
		let amount = info.amount * damageResist(m.kind, info.type) * (info.source.kind === "mob" ? info.source.mult : 1);
		if (info.heavy && m.kind === "golem") amount *= 1.9;
		if (info.source.kind === "player") {
			amount *= this.dmgOutMult;
			if (this.inv.wearing("wardenSigil")) amount *= 1.2;
			if (isUndead(m.kind) && this.inv.wearing("silverCharm")) amount *= 1.25;
		}
		if (amount <= 0) return false;
		const byPlayer = info.source.kind === "player";
		if (byPlayer) m.lastHitByPlayer = this.clock;
		m.lastAttacker = info.source.id;
		let dir = info.dirX;
		if (dir === 0 && info.knock > 0) dir = m.b.x >= info.originX ? 1 : -1;
		this.hurtMob(m, amount, dir, info.knock, byPlayer, info.heavy, info.crit);
		return true;
	},
	hurtPlayer(info) {
		if (this.dead) return false;
		if (!this.canHarm(info.source, "player", 0, AREA_DAMAGE.has(info.type)) && info.source.kind !== "player") return false;
		const stamps = this.playerHitStamps || (this.playerHitStamps = new Map());
		if (info.key !== 0) {
			const last = stamps.get(info.key);
			if (last !== undefined && this.clock - last < info.cooldown) return false;
			stamps.set(info.key, this.clock);
			if (stamps.size > 24) for (const [k, t] of stamps) if (this.clock - t >= 4) stamps.delete(k);
		}
		const before = this.hp;
		let ward = (this.inv.wearing("wardenSigil") ? 0.85 : 1) * this.dmgInMult;
		if (info.source.kind === "mob" && this.inv.wearing("silverCharm")) { const s = this.mobs.find((o) => o.id === info.source.id); if (s && isUndead(s.kind)) ward *= 0.75; }
		const amount = info.amount * (info.source.kind === "mob" ? info.source.mult : 1);
		if (amount <= 0.001) return false;
		this.damagePlayer(amount * ward, info.originX, info.knock, BYPASS_ARMOR.has(info.type));
		return this.hp < before;
	},
	damageBox(x0, y0, x1, y1, info) {
		const pb = this.pb;
		if (!this.dead && bodyRight(pb) > x0 && bodyLeft(pb) < x1 && pb.y > y0 && bodyTop(pb) < y1) this.hurtPlayer(info);
		for (const m of this.mobsNear(x0 - 4, x1 + 4)) {
			if (m.hp <= 0) continue;
			if (bodyRight(m.b) > x0 && bodyLeft(m.b) < x1 && m.b.y > y0 && bodyTop(m.b) < y1) this.applyMobDamage(m, info);
		}
	},
	pointBoxDist(px, py, x0, y0, x1, y1) { const dx = Math.max(0, x0 - px, px - x1), dy = Math.max(0, y0 - py, py - y1); return Math.hypot(dx, dy); },
	damageArea(cx, cy, radius, info, falloff, los) {
		const scaled = (d) => { const i = Object.assign({}, info); const f = clampD(d / radius, 0, 1); if (falloff) i.amount = info.amount * (1 - 0.65 * f); i.knock = info.knock * (falloff ? 1 - 0.5 * f : 1); i.originX = cx; i.originY = cy; return i; };
		const pb = this.pb;
		if (!this.dead) {
			const d = this.pointBoxDist(cx, cy, bodyLeft(pb), bodyTop(pb), bodyRight(pb), pb.y);
			if (d <= radius && (!los || this.world.lineClear(cx, cy, pb.x, pb.y - pb.h * 0.5))) this.hurtPlayer(scaled(d));
		}
		for (const m of this.mobsNear(cx - radius - 4, cx + radius + 4)) {
			if (m.hp <= 0) continue;
			const d = this.pointBoxDist(cx, cy, bodyLeft(m.b), bodyTop(m.b), bodyRight(m.b), m.b.y);
			if (d > radius) continue;
			if (los && !this.world.lineClear(cx, cy, m.b.x, mobCY(m))) continue;
			this.applyMobDamage(m, scaled(d));
		}
	},
	explode(x, y, radius, power, source, breakBlocks) {
		sfx("explosion", 1);
		const info = dinfo(power, "explosion", source);
		info.knock = 11; info.key = newAttackKey(); info.cooldown = 1;
		this.damageArea(x, y, radius, info, true, true);
		if (source.kind === "player" && !this.dead) {
			const pb = this.pb, d = this.pointBoxDist(x, y, bodyLeft(pb), bodyTop(pb), bodyRight(pb), pb.y);
			if (d <= radius && this.world.lineClear(x, y, pb.x, pb.y - pb.h * 0.5)) this.damagePlayer(power * 0.45 * (1 - 0.65 * clampD(d / radius, 0, 1)), x, 9);
		}
		if (breakBlocks) blastHook(this, x, y, radius, power);
		this.spawnParticles(x, y, 0xFFC050, 18, 8, 0.5, 2);
		this.spawnParticles(x, y, 0x606060, 12, 4, 1, -3);
		this.addShake(0.6);
		this.addLightFlash(x, y, 15, 0.75, radius + 2.5);
	},
	addLightFlash(x, y, peak, dur, radius) {
		if (this.flashes.length >= 12) this.flashes.shift();
		this.flashes.push({ x, y, peak, dur, radius, age: 0 });
	},

	// ---- creatures hurt and killed
	hurtMob(m, dmg, dirX, knock, byPlayer, heavy = false, crit = false) {
		if (m.hp <= 0) return;
		if (byPlayer) m.lastHitByPlayer = this.clock;
		let d = byPlayer ? dmg * rule("hit") : dmg;
		let kb = knock;
		if (m.blocking && m.kind === "skeleton" && dirX !== 0 && dirX * m.dir < 0) {
			if (heavy) {
				m.blocking = false; m.cd = Math.max(m.cd, 0.9);
				this.spawnParticles(m.b.x - m.dir * 0.5, m.b.y - 1, 0xFFF0C0, 8, 5, 0.25, 0);
				this.floatText("Guard broken", m.b.x, bodyTop(m.b) - 0.4, 0xFFD080);
			} else {
				d *= 0.1; kb *= 0.25;
				this.spawnParticles(m.b.x - m.dir * 0.5, m.b.y - 1, 0xE8F0FF, 5, 4, 0.2, 0);
				this.floatText("Blocked", m.b.x, bodyTop(m.b) - 0.4, 0xA0C0FF);
			}
		}
		if (d < 0.5) d = 0.5;
		m.hp -= d; m.hurtT = 0.22; m.flash = 0.12;
		if (dirX !== 0 && kb > 0) m.lean = clampD(dirX * kb / 9, -1, 1);
		let resist = isBossMob(m) ? 0.97 : (m.def.w > 2 ? 0.6 : 0);
		if (m.kind === "golem") resist = heavy ? 0.45 : 0.88;
		if (dirX !== 0 && kb > 0) { m.b.vx = dirX * kb * (1 - resist); if (resist < 0.9) m.b.vy = Math.min(m.b.vy, -3.5); }
		if (crit && byPlayer) this.floatText(Math.round(d) + "!", m.b.x, bodyTop(m.b) - 0.35, 0xFFE040);
		else this.floatText(String(Math.round(d)), m.b.x, bodyTop(m.b) - 0.2, byPlayer ? 0xFFFFFF : 0xFFAA40);
		this.spawnParticles(m.b.x, mobCY(m), m.kind === "skeleton" ? 0xE8E8E0 : 0xB02828, 4, 3, 0.4, 14);
		const beh = m.def.behavior;
		if (beh === "passive" || beh === "skittish") { m.t2 = 3.5; m.tx = m.b.x - (dirX === 0 ? 1 : dirX) * 6; }
		else if (beh === "defensive" && byPlayer) {
			m.angry = true; m.t3 = 10;
			if (m.kind === "wolf") for (const o of this.mobs) if (o.kind === "wolf" && !o.tame && Math.abs(o.b.x - m.b.x) < 16) { o.angry = true; o.t3 = 12; }
		}
		if (m.hp <= 0) this.killMob(m, byPlayer);
	},
	killMob(m, byPlayer) {
		m.hp = 0; m.deathT = 0; m.burn = 0;
		const credit = byPlayer || this.clock - m.lastHitByPlayer < 6;
		const rng = new RNG(hashU(m.id, Math.floor(this.clock * 1000), 4242));
		for (const s of mobDrops(m.kind, rng, m.sheared)) this.spawnDrop(s, m.b.x, m.b.y - m.b.h * 0.5, rand(-2, 2), -4.5);
		let col = 0xB02828;
		if (m.kind === "skeleton") col = 0xE8E8E0;
		if (m.kind === "slime") col = 0x60C060;
		if (m.kind === "emberSlime") col = 0xFF8A20;
		this.spawnParticles(m.b.x, mobCY(m), col, Math.floor(10 + m.b.w * 4), 5, 0.7, 14);
		if (credit) this.kills = (this.kills || 0) + 1;
		killHooks.forEach((f) => f(this, m, credit));
		for (const s of m.loot) this.spawnDrop(s, m.b.x, m.b.y - m.b.h * 0.5, rand(-2.5, 2.5), -5);
		m.loot = [];
		if (m === this.activeBoss) this.activeBoss = null;
		this.bumpHUD();
	},
	addMob(kind, x, y) {
		const m = makeMob(kind, x, y);
		if (this.mobHealthMult !== 1) { m.maxHP *= this.mobHealthMult; m.hp = m.maxHP; }
		if (kind === "zombie") m.variant = randInt(0, 2);
		else if (MOBS[kind].variants.length > 1) m.variant = randInt(0, MOBS[kind].variants.length - 1);
		this.mobs.push(m);
		// it can be found at once (the buckets are made again each frame)
		if (this.mobGrid) { const k = floorDiv(Math.floor(x), MOB_GRID); let b = this.mobGrid.get(k); if (!b) { b = []; this.mobGrid.set(k, b); } b.push(m); }
		return m;
	},

	// ---- telegraphed blows
	warn(x0, y0, x1, y1, dur, color = 0xFF3A2A) {
		const z = this.dangerZones || (this.dangerZones = []);
		if (z.length >= 24) z.shift();
		sfx("warn", 0.6);
		z.push({ x0: Math.min(x0, x1), y0: Math.min(y0, y1), x1: Math.max(x0, x1), y1: Math.max(y0, y1), t: dur, dur: Math.max(0.05, dur), color });
	},
	mobAttackBox(m, x0, y0, x1, y1, dmg, knock, type = "melee") {
		const info = dinfo(dmg, type, srcMob(this, m));
		info.knock = knock; info.originX = m.b.x; info.originY = mobCY(m); info.key = newAttackKey();
		this.damageBox(Math.min(x0, x1), Math.min(y0, y1), Math.max(x0, x1), Math.max(y0, y1), info);
	},

	// ---- projectiles
	shoot(p) {
		const q = Object.assign({ w: 0.12, life: 3, stuck: 0, stuckAngle: 0, pierce: 0, knock: 0, lastHit: 0, trail: 0, owner: 0, uid: newAttackKey(), source: SRC_ENV, gravity: 0 }, p);
		this.projectiles.push(q);
		return q;
	},
	updateProjectiles(dt) {
		if (!this.projectiles.length) return;
		const list = this.projectiles;
		this.projectiles = [];
		const keep = [];
		for (const p of list) if (this.stepProjectile(p, dt)) keep.push(p);
		for (const p of this.projectiles) keep.push(p);
		this.projectiles = keep;
	},
	stepProjectile(p, dt) {
		p.life -= dt;
		if (p.life <= 0) {
			if (p.kind === "bomb") this.explode(p.x, p.y, 3.4, p.dmg, p.source, true);
			return false;
		}
		if (p.stuck > 0) {
			p.stuck -= dt;
			if (p.stuck <= 0 && (p.kind === "arrow" || p.kind === "quarrel") && p.source.kind === "player" && !this.isCreative && Math.random() < 0.35) this.spawnDrop(stack(p.kind === "arrow" ? "ammo:arrow" : "ammo:bolt", 1), p.x, p.y, 0, -1);
			return p.stuck > 0;
		}
		if (p.kind === "shock") return this.stepShock(p, dt);
		p.vy = Math.min(p.vy + p.gravity * dt, 40);
		const nx = p.x + p.vx * dt, ny = p.y + p.vy * dt;
		let wallT = 2, wtx = 0, wty = 0;
		if (this.world.segmentSolid(p.x, p.y, nx, ny)) { wallT = SEG_HIT[2]; wtx = SEG_HIT[0]; wty = SEG_HIT[1]; }
		if (p.kind !== "bomb") {
			const hit = this.firstEntityOnPath(p, nx, ny, wallT);
			if (hit) {
				const hx = p.x + (nx - p.x) * hit.t, hy = p.y + (ny - p.y) * hit.t;
				const info = dinfo(p.dmg, p.kind === "fireball" ? "fire" : "projectile", p.source);
				info.dirX = p.vx >= 0 ? 1 : -1;
				info.knock = p.knock > 0 ? p.knock : (p.kind === "bullet" ? 4 : p.kind === "arrow" ? 3.5 : 3);
				info.originX = p.x; info.originY = p.y; info.key = p.uid; info.cooldown = 1;
				if (p.kind === "fireball") info.type = "projectile";
				if (hit.mob) {
					const m = hit.mob;
					if (this.applyMobDamage(m, info)) {
						if (p.kind === "fireball") m.burn = Math.max(m.burn, 2.5);
						this.spawnParticles(hx, hy, p.kind === "fireball" ? 0xFF8030 : 0xE8E0D0, 3, 2.5, 0.25, 8);
						if (p.source.kind === "player") { sfx("arrowHit", 0.55); this.lockTarget = m; this.lockT = 2; }
					}
					p.lastHit = m.id;
				} else {
					this.hurtPlayer(info);
					if (p.kind === "fireball") { this.playerBurn = Math.max(this.playerBurn, 1.5); this.spawnParticles(hx, hy, 0xFF8030, 8, 4, 0.4, 6); }
				}
				if (p.pierce > 0 && hit.mob) { p.pierce--; p.dmg *= 0.7; }
				else return false;
			}
		}
		if (wallT <= 1) {
			const hx = p.x + (nx - p.x) * wallT, hy = p.y + (ny - p.y) * wallT;
			switch (p.kind) {
				case "pebble": this.spawnParticles(hx, hy, 0x9A9A9A, 4, 2.5, 0.3, 14); return false;
				case "arrow": case "quarrel":
					p.x = hx - p.vx * 0.004; p.y = hy - p.vy * 0.004;
					p.stuckAngle = Math.atan2(p.vy, p.vx);
					p.vx = 0; p.vy = 0; p.stuck = 4; p.gravity = 0;
					this.spawnParticles(hx, hy, 0xA0A0A0, 2, 1.5, 0.2, 8);
					return true;
				case "rock": this.rockImpact(p, hx, hy); return false;
				case "bomb": {
					const onTop = Math.abs(hy - wty) < 0.02 && p.vy > 0, onBottom = Math.abs(hy - (wty + 1)) < 0.02 && p.vy < 0;
					if (onTop || onBottom) {
						p.vy = -p.vy * 0.35; p.vx *= onTop ? 0.4 : 0.7; p.x = hx; p.y = onTop ? wty - 0.02 : wty + 1.02;
						if (onTop && Math.abs(p.vy) < 1.5) { p.vy = 0; p.vx *= 0.6; }
					} else { p.vx = -p.vx * 0.45; p.x = p.vx < 0 ? wtx - 0.02 : wtx + 1.02; p.y = hy; }
					if (this.world.solid(Math.floor(p.x), Math.floor(p.y))) p.y = this.world.groundBelow(Math.floor(p.x), Math.floor(p.y) - 4) - 0.02;
					return true;
				}
				default:
					this.spawnParticles(hx, hy, p.kind === "fireball" ? 0xFF8030 : 0xFFE080, 5, 3, 0.25, 6);
					if (p.kind === "fireball") this.igniteNear(hx, hy, p.source);
					return false;
			}
		}
		p.x = nx; p.y = ny;
		if (p.kind === "fireball" && Math.random() < 0.5) this.spawnParticles(p.x, p.y, 0xFFB040, 1, 1, 0.25, -2);
		if (p.kind === "arrow" && p.source.kind === "player" && p.trail < 6) p.trail++;
		return true;
	},
	firstEntityOnPath(p, nx, ny, maxT) {
		let best = null, bt = Math.min(1, maxT);
		const pad = Math.max(0.08, p.w * 0.5), pb = this.pb;
		if (!this.dead && this.canHarm(p.source, "player", 0, false)) {
			const t = segmentBoxT(p.x, p.y, nx, ny, bodyLeft(pb) - pad, bodyTop(pb) - pad, bodyRight(pb) + pad, pb.y + pad);
			if (t >= 0 && t <= bt) { bt = t; best = { t, mob: null }; }
		}
		for (const m of this.mobsNear(Math.min(p.x, nx) - 4, Math.max(p.x, nx) + 4)) {
			if (m.hp <= 0 || m.id === p.lastHit || m.downed) continue;
			if (!this.canHarm(p.source, this.faction(m), m.id, false)) continue;
			const t = segmentBoxT(p.x, p.y, nx, ny, bodyLeft(m.b) - pad, bodyTop(m.b) - pad, bodyRight(m.b) + pad, m.b.y + pad);
			if (t >= 0 && t <= bt) { bt = t; best = { t, mob: m }; }
		}
		return best;
	},
	/** a shockwave runs along the ground and hurts what stands in it */
	stepShock(p, dt) {
		p.x += p.vx * dt;
		p.y = this.world.groundBelow(Math.floor(p.x), Math.floor(p.y) - 3) - 0.5;
		if (this.world.solid(Math.floor(p.x), Math.floor(p.y - 0.6)) && this.world.solid(Math.floor(p.x + p.vx * 0.1), Math.floor(p.y - 0.4))) return false;
		const info = dinfo(p.dmg, "stomp", p.source);
		info.dirX = p.vx >= 0 ? 1 : -1; info.knock = 7; info.originX = p.x - p.vx; info.originY = p.y; info.key = p.uid; info.cooldown = 2;
		this.damageBox(p.x - 0.5, p.y - 0.9, p.x + 0.5, p.y + 0.5, info);
		if (Math.random() < 0.5) this.spawnParticles(p.x, p.y + 0.3, 0xA08860, 1, 1.5, 0.3, 6);
		return true;
	},
	rockImpact(p, x, y) {
		this.spawnParticles(x, y, 0x8A8A8A, 10, 5, 0.5, 16);
		this.addShake(0.25);
		const info = dinfo(p.dmg, "impact", p.source);
		info.knock = 5; info.originX = x; info.originY = y - 1; info.key = p.uid; info.cooldown = 1;
		this.damageArea(x, y - 0.8, 1.8, info, false, false);
	},
	igniteNear(x, y, src) {
		for (const m of this.mobsNear(x - 1.5, x + 1.5)) if (m.hp > 0 && !this.heatImmune(m) && Math.abs(mobCY(m) - y) < m.b.h * 0.5 + 1 && this.canHarm(src, this.faction(m), m.id, true)) m.burn = Math.max(m.burn, 2);
	},
	throwBomb() {
		if (this.useCD > 0) return;
		if (!this.isCreative) this.inv.removeAt(this.sel, 1);
		this.facing = this.aimFacing();
		const ox = this.pb.x + this.facing * 0.4, oy = this.pb.y - 1.3;
		const a = lobAngle(this.aimX - ox, this.aimY - oy, THROW_SPEED, THROW_GRAVITY);
		this.shoot({ kind: "bomb", x: ox, y: oy, vx: Math.cos(a) * THROW_SPEED, vy: Math.sin(a) * THROW_SPEED, dmg: 26, gravity: THROW_GRAVITY, life: 1.8, w: 0.4, source: SRC_PLAYER });
		this.useCD = 0.45; this.swingT = 0.18; this.swingDir = this.facing;
		this.bumpHUD();
	},

	// ---- hazards for creatures: lava, fire, spikes and cactus, falls
	mobHazards(m, dt) {
		if (m.removed || m.downed) return;
		if (m.slowT > 0) m.slowT -= dt;
		if (m.weakT > 0) m.weakT -= dt;
		if (m.hazardT > 0) m.hazardT -= dt;
		const b = m.b, w = this.world, hw = b.w * 0.5, immune = this.heatImmune(m), fx = Math.floor(b.x);
		const inLava = b.inLava || w.tile(fx, Math.floor(b.y - 0.1)) === T.lava;
		if (inLava && !immune) {
			m.burn = Math.max(m.burn, 3);
			if (m.hazardT <= 0) {
				m.hazardT = 0.35;
				const info = dinfo(isBossMob(m) ? 14 : 6, "lava", SRC_ENV); info.originX = b.x;
				this.applyMobDamage(m, info);
				if (m.hp > 0 && !m.def.flying) b.vy = Math.min(b.vy, -7);
			}
		}
		if (m.burn > 0) {
			if (immune || b.inWater) m.burn = 0;
			else {
				m.burn -= dt; m.burnTick += dt;
				if (m.burnTick >= 0.5) {
					m.burnTick = 0;
					const info = dinfo(isBossMob(m) ? 3 : 2, "fire", SRC_ENV); info.originX = b.x;
					this.applyMobDamage(m, info);
					this.spawnParticles(b.x, b.y - b.h * 0.7, 0xFF8030, 2, 1.5, 0.4, -4);
				}
			}
		}
		if (!m.def.flying && m.hazardT <= 0 && ((this.frameNo + m.id) & 3) === 0) {
			let t = w.boxHurts(b.x - hw + 0.05, b.y - 0.6, b.x + hw - 0.05, b.y + 0.05);
			if (t < 0) t = w.boxHurts(b.x - hw - 0.02, bodyTop(b) + 0.1, b.x + hw + 0.02, b.y - 0.1);
			if (t === T.spikes || t === T.cactus) {
				m.hazardT = 0.6;
				const info = dinfo(t === T.spikes ? 5 : 2, "hazard", SRC_ENV); info.originX = b.x - m.dir; info.knock = 3;
				this.applyMobDamage(m, info);
			}
			if (w.tile(fx, Math.floor(b.y - 0.5)) === T.campfire && !immune) m.burn = Math.max(m.burn, 2);
		}
		if (!m.def.flying && m.kind !== "fish") {
			if (!b.onGround && b.vy > 0 && !b.inWater) m.fallPeak = Math.max(m.fallPeak, b.vy);
			if (b.onGround || b.inWater) {
				if (m.fallPeak > 23 && !b.inWater && !isBossMob(m)) { const info = dinfo((m.fallPeak - 21) * 1.5, "fall", SRC_ENV); info.originX = b.x; this.applyMobDamage(m, info); }
				m.fallPeak = 0;
			}
		}
	},
	/** dead creatures topple, fall and fade for a moment before they go */
	updateDying(dt) {
		for (const m of this.mobs) {
			if (m.hp > 0 || m.removed) continue;
			if (m.deathT < 0) m.deathT = 0;
			m.deathT += dt;
			if (!m.def.flying || m.deathT > 0.1) {
				m.b.vy = Math.min(m.b.vy + gravityG() * dt, terminalV);
				m.b.vx *= 1 - Math.min(1, dt * 4);
				if (m.deathT < 0.8) this.world.moveBody(m.b, dt, 0, false, null);
			}
			if (m.deathT > 0.7) m.removed = true;
		}
	},

	// ---- the player's blows
	attackAngle() {
		if (this.aimValid) {
			const dx = this.aimX - this.shoulderX, dy = this.aimY - this.shoulderY;
			if (dx * dx + dy * dy > 0.36) return Math.atan2(dy, dx);
		}
		return this.facing >= 0 ? 0 : Math.PI;
	},
	boxDistance(m, ox, oy) { const nx = clampD(ox, bodyLeft(m.b), bodyRight(m.b)), ny = clampD(oy, bodyTop(m.b), m.b.y); return Math.hypot(nx - ox, ny - oy); },
	mobUnderAim(p) {
		if (!this.aimValid) return null;
		const pad = 0.9;
		let best = null, bd = 1e9;
		for (const m of this.mobsNear(this.aimX - 6, this.aimX + 6)) {
			if (m.hp <= 0 || m.removed || m.tame || m.downed) continue;
			if (this.aimX < bodyLeft(m.b) - pad || this.aimX > bodyRight(m.b) + pad || this.aimY < bodyTop(m.b) - pad || this.aimY > m.b.y + pad) continue;
			if (this.boxDistance(m, this.shoulderX, this.shoulderY) > Math.max(p.reach + 1.5, 4)) continue;
			let d = Math.abs(this.aimX - m.b.x) + Math.abs(this.aimY - mobCY(m));
			if (!this.isThreat(m)) d += 2;
			if (d < bd) { bd = d; best = m; }
		}
		return best;
	},
	/** whether a swing along (dirx, diry) reaches `m`: how far it is, or -1 */
	meleeReach(m, dirx, diry, p) {
		const ox = this.shoulderX, oy = this.shoulderY, hw = m.b.w * 0.5, hh = m.b.h * 0.5, cx = m.b.x, cy = m.b.y - hh;
		const nx = clampD(ox, cx - hw, cx + hw), ny = clampD(oy, cy - hh, cy + hh);
		const dist = Math.hypot(nx - ox, ny - oy);
		if (dist > p.reach) return -1;
		const vx = cx - ox, vy = cy - oy;
		if (p.style === "thrust") {
			const along = vx * dirx + vy * diry, ext = hw * Math.abs(dirx) + hh * Math.abs(diry);
			if (along + ext < 0 || along - ext > p.reach) return -1;
			if (Math.abs(vx * diry - vy * dirx) - (hw * Math.abs(diry) + hh * Math.abs(dirx)) > p.band) return -1;
		} else if (dist > 0.45) {
			const cd = Math.max(0.2, Math.hypot(vx, vy));
			const off = Math.abs(angleDiff(Math.atan2(vy, vx), Math.atan2(diry, dirx)));
			const ext = hw * Math.abs(vy / cd) + hh * Math.abs(vx / cd);
			if (off > p.halfArc + Math.atan(ext / cd)) return -1;
		} else if (vx * dirx < -0.3 && Math.abs(dirx) > 0.3) return -1;
		const ix = nx + (cx - nx) * 0.25, iy = ny + (cy - ny) * 0.25;
		if (!this.world.lineClear(ox, oy, ix, iy) && !this.world.lineClear(ox, oy, cx, cy)) return -1;
		return dist;
	},
	meleeCandidates(p) {
		const ang = this.attackAngle(), dirx = Math.cos(ang), diry = Math.sin(ang), ox = this.shoulderX;
		const out = [];
		for (const m of this.mobsNear(ox - p.reach - 4, ox + p.reach + 4)) {
			if (m.hp <= 0 || m.removed || m.tame || m.downed) continue;
			const d = this.meleeReach(m, dirx, diry, p);
			if (d >= 0) out.push([m, d]);
		}
		out.sort((a, b) => a[1] - b[1]);
		if (out.length > p.maxHits) out.length = p.maxHits;
		return out;
	},
	/** starts a blow with the held item (null: bare hands); a heavy weapon winds up first */
	startMelee(it, target = null) {
		if (this.useCD > 0 || this.strikeT > 0) return false;
		const p = meleeOf(it);
		this.useCD = p.cooldown; this.swingDur = p.swingTime; this.swingT = p.swingTime;
		const ang = this.attackAngle();
		this.swingDir = Math.abs(Math.cos(ang)) < 0.25 ? this.facing : (Math.cos(ang) >= 0 ? 1 : -1);
		this.facing = this.swingDir;
		this.strikeItem = it; this.strikeSel = this.sel; this.strikeTarget = target;
		if (p.windup > 0) this.strikeT = p.windup; else this.resolveMelee(it);
		return true;
	},
	resolveMelee(it) {
		const p = meleeOf(it), ox = this.shoulderX, oy = this.shoulderY, ang = this.attackAngle(), key = newAttackKey();
		let hits = 0, crits = 0, undead = false;
		for (const [m] of this.meleeCandidates(p)) {
			let d = p.damage, crit = false;
			if (p.combo) { this.comboN = this.clock - (this.comboT || -9) < 0.7 ? (this.comboN || 0) + 1 : 1; this.comboT = this.clock; if (this.comboN % 3 === 0) { d *= 2; crit = true; } }
			if (!crit && Math.random() < p.critChance) { d *= 1.5; crit = true; }
			if (p.backstab > 1 && (this.pb.x - m.b.x) * m.dir < 0 && !isBossMob(m)) { d *= p.backstab; crit = true; }
			if (p.undeadMult !== 1 && isUndead(m.kind)) { d *= p.undeadMult; undead = true; }
			const dx = m.b.x - ox;
			const info = dinfo(d, "melee", SRC_PLAYER);
			info.dirX = Math.abs(dx) > 0.2 ? (dx > 0 ? 1 : -1) : this.swingDir;
			info.knock = p.knock; info.originX = ox; info.originY = oy; info.key = key; info.cooldown = 0.3; info.heavy = p.heavy; info.crit = crit;
			if (this.applyMobDamage(m, info)) {
				hits++; if (crit) crits++;
				if (p.burn > 0 && !this.heatImmune(m)) m.burn = Math.max(m.burn, p.burn);
				if (p.daze > 0) this.dazeMob(m, p.daze);
				this.spawnSparks(m.b.x - info.dirX * m.b.w * 0.3, mobCY(m), info.dirX, p.trail, crit ? 7 : 4);
				this.lockTarget = m; this.lockT = 2;
			}
		}
		if (p.shockwave) {
			this.shoot({ kind: "shock", x: this.pb.x + this.swingDir * 1.2, y: this.pb.y - 0.5, vx: this.swingDir * 15, vy: 0, dmg: 12, life: 0.55, source: SRC_PLAYER });
			this.addShake(0.3);
			this.spawnParticles(this.pb.x + this.swingDir * 1.4, this.pb.y - 0.1, 0xA08860, 10, 4, 0.5, 12);
		}
		const sl = this.slashes || (this.slashes = []);
		if (sl.length > 8) sl.shift();
		const life = Math.max(0.12, p.swingTime * 0.7);
		sl.push({ x: ox, y: oy, ang, reach: p.reach, halfArc: p.halfArc, style: p.style, color: p.trail, life, maxLife: life, hit: hits > 0 });
		sfx(p.style === "stab" ? "swingLight" : p.style === "thrust" ? "thrust" : (p.heavy || p.daze > 0) && (p.style === "smash" || p.style === "bash") ? "swingHeavy" : "swing", 0.55);
		if (hits > 0) {
			this.hitStopT = Math.max(this.hitStopT || 0, p.heavy ? 0.07 : crits > 0 ? 0.05 : 0.03);
			this.addShake(p.heavy ? 0.18 : crits > 0 ? 0.12 : 0.07);
			sfx(crits > 0 ? "crit" : "hit", p.heavy ? 1 : 0.75);
			if (hits >= 2) { this.floatText("x" + hits, this.pb.x, this.pb.y - this.pb.h - 0.9, 0xFFD060); sfx("multiHit", 0.6); }
			if (undead && p.undeadMult > 1) this.spawnParticles(this.pb.x + this.swingDir * 1.2, this.pb.y - 1.2, 0xC8E8FF, 5, 2.5, 0.4, -2);
		} else {
			const t = this.strikeTarget || (this.lockT > 0 ? this.lockTarget : null);
			if (t && t.hp > 0 && !t.removed) this.floatText("miss", t.b.x, bodyTop(t.b) - 0.3, 0xA8A8A8);
		}
		this.strikeTarget = null;
	},
	dazeMob(m, t) {
		if (isBossMob(m) || m.dazeGuard > 0 || m.hp <= 0) return;
		m.daze = Math.max(m.daze, t * (m.kind === "golem" ? 0.5 : 1));
		m.atkT = 0; m.blocking = false;
		sfx("daze", 0.5);
	},
	spawnSparks(x, y, dirX, color, n) {
		if (this.particles.length > 160) return;
		for (let i = 0; i < n; i++) {
			const a = rand(-0.9, 0.9) + (dirX >= 0 ? 0 : Math.PI), sp = rand(4, 8);
			this.particles.push({ x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 2, life: rand(0.12, 0.25), maxLife: 0.25, color: artGrade(Math.random() < 0.5 ? color : 0xFFF4D0), size: rand(0.07, 0.13), gravity: 20 });
		}
	},
	/** a melee weapon: at what is aimed at; held, it swings again when ready while something is in reach */
	useMeleeWeapon(id, pressed) {
		const p = meleeOf(id), target = this.mobUnderAim(p);
		if (target) { this.aimX = target.b.x; this.aimY = mobCY(target); }
		if (!pressed) {
			if (this.useCD > 0 || this.strikeT > 0) return;
			const onStick = ActStick.held && !this.touchActive;
			if (!onStick && !this.meleeCandidates(p).length) return;
		}
		this.startMelee(id, target);
	},
	/** a tool or a fist aimed at a creature fights it instead of digging behind it; true when it did */
	fightWith(id, pressed) {
		const p = meleeOf(id), m = this.mobUnderAim(p);
		if (!m) return false;
		if (pressed || (this.useCD <= 0 && this.meleeCandidates(p).length)) this.startMelee(id, m);
		return true;
	},

	// ---- the bow: hold to draw, let go to loose; a full draw keeps firing
	handleBow(dt, pressed, released) {
		const has = this.isCreative || this.inv.total("ammo:arrow") > 0;
		if (this.useHeld) {
			if (!has) { if (pressed) this.say("No arrows!", 1.2); this.bowCharge = 0; return; }
			if (this.useCD > 0 && this.bowCharge === 0) return;
			this.bowCharge = Math.min(1, Math.max(this.bowCharge, 0.01) + dt / BOW.chargeTime);
			this.facing = this.aimFacing();
			if (this.bowCharge >= 1 && this.useCD <= 0) { this.fireArrow(1); this.bowCharge = 0.3; }
		} else if (released && this.bowCharge > 0 && has) { this.fireArrow(Math.max(0.45, this.bowCharge)); this.bowCharge = 0; }
		else this.bowCharge = 0;
	},
	arrowLaunch(charge) {
		const pb = this.pb, ox = pb.x + this.facing * 0.35, oy = pb.y - 1.2;
		let dx = this.aimX - ox, dy = this.aimY - oy;
		const len = Math.max(0.001, Math.hypot(dx, dy)); dx /= len; dy /= len;
		const speed = BOW.minSpeed + (BOW.maxSpeed - BOW.minSpeed) * charge;
		return [ox + dx * 0.4, oy + dy * 0.4, dx * speed + pb.vx * 0.3, dy * speed + Math.min(0, pb.vy) * 0.2];
	},
	fireArrow(charge) {
		if (!this.isCreative) this.inv.remove("ammo:arrow", 1);
		const l = this.arrowLaunch(charge);
		let dmg = BOW.baseDamage + BOW.chargeDamage * charge;
		if (charge >= 0.99 && Math.random() < 0.15) dmg *= 1.5;
		this.shoot({ kind: "arrow", x: l[0], y: l[1], vx: l[2], vy: l[3], dmg, gravity: BOW.gravity, life: 6, w: 0.22, source: SRC_PLAYER });
		sfx("bow", 0.7);
		this.useCD = BOW.useTime; this.swingT = 0.18; this.swingDir = this.facing;
		this.bumpHUD();
	},
	/** points along the shot's flight for the aiming arc */
	arrowPreview() {
		let l, grav;
		const it = this.heldItem;
		if (this.bowCharge > 0) { l = this.arrowLaunch(Math.max(0.45, this.bowCharge)); grav = BOW.gravity; }
		else if (this.useHeld && this.aimValid && it) {
			let speed = 0, ox = this.pb.x + this.facing * 0.4, oy = this.pb.y - 1.3;
			const gd = itemDef(it).gun;
			if (it === "sling") { speed = 23; grav = 16; }
			else if (gd && gd.bolts) { speed = gd.speed; grav = gd.gravity; ox = this.pb.x + this.facing * 0.7; oy = this.pb.y - 1.2; }
			else if (it === "gadget:bomb") { speed = THROW_SPEED; grav = THROW_GRAVITY; }
			else return null;
			const a = lobAngle(this.aimX - ox, this.aimY - oy, speed, grav);
			l = [ox, oy, Math.cos(a) * speed, Math.sin(a) * speed];
		} else return null;
		let x = l[0], y = l[1], vy = l[3];
		const vx = l[2], out = [];
		for (let i = 0; i < 40; i++) {
			vy = Math.min(vy + grav * 0.03, 40);
			const nx = x + vx * 0.03, ny = y + vy * 0.03;
			if (this.world.segmentSolid(x, y, nx, ny)) break;
			x = nx; y = ny;
			if (i % 2 === 1) out.push(x, y);
		}
		return out;
	},

	// ---- guns and crossbows: the count loaded is the stack's `extra`
	updateReload(dt) {
		if (!(this.reloadT > 0)) return;
		if (this.reloadSlot !== this.sel) { this.reloadT = 0; this.reloadSlot = -1; return; }
		this.reloadT -= dt;
		if (this.reloadT > 0) return;
		this.reloadT = 0; this.reloadSlot = -1;
		const st = this.inv.slots[this.sel];
		const g = st && itemDef(st.id).gun;
		if (!g || !g.ammo) return;
		const need = g.magazine - st.extra;
		let take = need;
		if (!this.isCreative) { take = Math.min(need, this.inv.total(g.ammo)); this.inv.remove(g.ammo, take); }
		st.extra += take;
		if (g.bolts) sfx("tap", 0.5);
		this.bumpHUD();
	},
	startReload() {
		const st = this.heldStack, g = st && itemDef(st.id).gun;
		if (!g || !g.ammo) return;
		if (this.reloadT > 0 || st.extra >= g.magazine) return;
		if (!this.isCreative && this.inv.total(g.ammo) <= 0) { this.say("Out of " + itemName(g.ammo).toLowerCase() + "!", 1.5); return; }
		this.reloadT = g.reload; this.reloadSlot = this.sel;
		if (g.magazine > 1) this.say("Reloading...", 1);
	},
	useGun(id, pressed) {
		const st = this.inv.slots[this.sel], g = itemDef(id).gun;
		if (!st || !g || this.reloadT > 0) return;
		if (st.extra <= 0) {
			if (id === "gun:stormRod") { if (pressed) this.say("The rod is still gathering its charge.", 1.2); return; }
			if (pressed || this.useCD <= 0) this.startReload();
			return;
		}
		if (this.useCD > 0) return;
		if (g.needsPress && !pressed) return;
		if (id === "gun:stormRod") { if (pressed) this.say("The storm rod comes with the weather.", 1.5); return; }
		st.extra--;
		this.useCD = g.cooldown;
		this.facing = this.aimFacing();
		const ox = this.pb.x + this.facing * 0.7, oy = this.pb.y - 1.2;
		const base = lobAngle(this.aimX - ox, this.aimY - oy, g.speed, g.gravity);
		const n = id === "gun:blunderbuss" ? 7 : 1;
		for (let i = 0; i < n; i++) {
			let a = base;
			if (n > 1) a += (i / (n - 1) - 0.5) * 0.6;
			const kind = n > 1 ? "pellet" : g.bolts ? "quarrel" : "bullet";
			this.shoot({ kind, x: ox, y: oy, vx: Math.cos(a) * g.speed, vy: Math.sin(a) * g.speed, dmg: g.damage, gravity: g.gravity, life: g.life * (n > 1 ? rand(0.85, 1.1) : 1), source: SRC_PLAYER, pierce: g.pierce, knock: g.knock, w: kind === "pellet" ? 0.16 : kind === "quarrel" ? 0.22 : 0.12 });
		}
		const heavy = id === "gun:rifle" || id === "gun:arbalest" || id === "gun:blunderbuss";
		sfx(id === "gun:blunderbuss" ? "blunderbuss" : g.bolts ? "crossbow" : "gun", 0.8);
		this.muzzleT = g.bolts ? 0 : 0.08;
		this.swingT = 0.1; this.swingDir = this.facing;
		this.addShake(heavy ? 0.16 : 0.07);
		this.pb.vx -= this.facing * (id === "gun:blunderbuss" ? 4 : heavy ? 2.5 : 1);
		if (g.firearm) this.spawnParticles(ox + Math.cos(base) * 0.4, oy + Math.sin(base) * 0.4, 0xFFE080, n > 1 ? 9 : 4, 3, 0.15, 0);
		if (st.extra <= 0 && (this.isCreative || this.inv.total(g.ammo) > 0)) this.startReload();
		this.bumpHUD();
	},
	useSling(pressed) {
		if (this.useCD > 0) return;
		let ammo = null;
		if (!this.isCreative) {
			ammo = SLING_AMMO.find((id) => this.inv.total(id) > 0) || null;
			if (!ammo) { if (pressed) this.say("The sling needs stones: any stone or slate in your bag.", 1.8); return; }
			this.inv.remove(ammo, 1);
		}
		this.facing = this.aimFacing();
		const ox = this.pb.x + this.facing * 0.4, oy = this.pb.y - 1.3;
		const a = lobAngle(this.aimX - ox, this.aimY - oy, 23, 16);
		this.shoot({ kind: "pebble", x: ox, y: oy, vx: Math.cos(a) * 23, vy: Math.sin(a) * 23, dmg: 4.5, gravity: 16, life: 3, w: 0.22, knock: 7.5, source: SRC_PLAYER });
		this.useCD = 0.55; this.swingDur = 0.2; this.swingT = 0.2; this.swingDir = this.facing;
		sfx("sling", 0.6);
		this.bumpHUD();
	},

	// ---- the attack stick: inside the dead zone the game aims for itself
	autoTarget(it) {
		const ranged = !!(it && isRangedItem(it)), weapon = !!(it && isWeaponItem(it)), p = meleeOf(it);
		const range = ranged ? 22 : p.reach + 3, ox = this.shoulderX, oy = this.shoulderY;
		let best = null, bs = 1e9;
		for (const m of this.mobsNear(ox - range - 4, ox + range + 4)) {
			if (m.hp <= 0 || m.removed || m.tame || m.downed) continue;
			const foe = this.isThreat(m);
			if (!foe && !weapon) continue;
			const d = this.boxDistance(m, ox, oy);
			if (d > range) continue;
			let s = d + (foe ? 0 : 8);
			if (!this.world.lineClear(ox, oy, m.b.x, mobCY(m))) { if (ranged) continue; s += 6; }
			if (m === this.lockTarget) s -= 1.5;
			if (s < bs) { bs = s; best = m; }
		}
		return best;
	},
	shotBallistics(it) {
		if (!it) return [0, 0];
		if (it === "bow") return [BOW.maxSpeed, BOW.gravity];
		const g = itemDef(it).gun;
		if (g) return [g.speed, g.gravity];
		if (it === "sling") return [23, 16];
		if (it === "gadget:bomb") return [THROW_SPEED, THROW_GRAVITY];
		return [0, 0];
	},
	aimPointFor(m, it) {
		let tx = m.b.x, ty = mobCY(m);
		const [spd, grav] = this.shotBallistics(it);
		if (spd > 0) {
			const t = Math.hypot(tx - this.pb.x, ty - (this.pb.y - 1.2)) / spd;
			tx += m.b.vx * t;
			if (it === "bow") ty -= 0.5 * grav * t * t;
		}
		return [tx, ty];
	},
	stickAim(it, dx, dy, power) {
		const ox = this.shoulderX, oy = this.shoulderY, reach = Math.min(this.reachDistance(), 5.5) - 0.3;
		if (!it) return this.stickDigPoint(dx, dy, reach);
		const k = itemKind(it);
		if (MELEE_KINDS.has(k)) { const d = Math.max(1, meleeOf(it).reach); return [ox + dx * d, oy + dy * d]; }
		if (k === "bow" || k === "gun") return [ox + dx * 14, oy + dy * 14];
		if (k === "sling") { const d = 4 + 9 * power; return [ox + dx * d, oy + dy * d]; }
		if (it === "gadget:bomb") { const d = 3 + 9 * power; return [ox + dx * d, oy + dy * d]; }
		if (k === "tool" || k === "gadget") return this.stickDigPoint(dx, dy, reach);
		if (k === "block" || k === "wall" || k === "part") return this.stickPlacePoint(dx, dy, reach);
		return [ox + dx * 1.5, oy + dy * 1.5];
	},
	stickDigPoint(dx, dy, r) {
		const ox = this.shoulderX, oy = this.shoulderY, near = this.mobsNear(ox - r - 1, ox + r + 1);
		for (let d = 0.7; d <= r; d += 0.25) {
			const x = ox + dx * d, y = oy + dy * d;
			for (const m of near) if (m.hp > 0 && !m.removed && !m.tame && !m.downed && x >= bodyLeft(m.b) - 0.2 && x <= bodyRight(m.b) + 0.2 && y >= bodyTop(m.b) - 0.2 && y <= m.b.y + 0.2) return [m.b.x, mobCY(m)];
			const tx = Math.floor(x), ty = Math.floor(y), t = this.world.tile(tx, ty);
			if (t !== T.air && !LIQUID[t]) return [tx + 0.5, ty + 0.5];
		}
		return [ox + dx * r, oy + dy * r];
	},
	stickPlacePoint(dx, dy, r) {
		const ox = this.shoulderX, oy = this.shoulderY;
		let last = null;
		for (let d = 0.7; d <= r; d += 0.25) {
			const tx = Math.floor(ox + dx * d), ty = Math.floor(oy + dy * d);
			if (this.world.solid(tx, ty)) break;
			last = [tx, ty];
		}
		return last ? [last[0] + 0.5, last[1] + 0.5] : [ox + dx * 1.2, oy + dy * 1.2];
	},
	/** once a frame before the tick: while the attack stick is held the game aims and acts */
	applyActButton() {
		const S = ActStick, held = S.held;
		const was = S.was;
		S.was = held;
		if (!held) {
			if (was && !this.touchActive) { this.useHeld = false; this.useWasHeld = false; this.useReleasedFlag = true; }
			return;
		}
		if (this.dead) return;
		if (this.touchActive) { this.useHeld = true; return; }
		const it = this.heldItem;
		if (S.manual) {
			const a = this.stickAim(it, S.dirX, S.dirY, S.power);
			this.aimX = a[0]; this.aimY = a[1]; this.aimValid = true; this.lockTarget = null;
			if (Math.abs(S.dirX) > 0.25) this.facing = S.dirX >= 0 ? 1 : -1;
			this.holdAction(was);
			return;
		}
		const pb = this.pb;
		let tx = pb.x + this.facing * 1.1, ty = pb.y - 1.3, aimed = false;
		const k = it ? itemKind(it) : "";
		const wantsMob = !(k === "block" || k === "part" || k === "mat" || k === "food" || k === "wall");
		if (wantsMob) {
			const m = this.autoTarget(it);
			if (m) { const a = this.aimPointFor(m, it); tx = a[0]; ty = a[1]; aimed = true; this.lockTarget = m; this.lockT = Math.max(this.lockT || 0, 0.5); }
		}
		if (!aimed) {
			const w = this.world, fx = Math.floor(pb.x + this.facing * (pb.w * 0.5 + 0.55));
			const chest = Math.floor(pb.y - 1.3), feet = Math.floor(pb.y - 0.4), below = Math.floor(pb.y + 0.5);
			if (k === "block" || k === "wall") {
				if (!w.solid(fx, feet)) { tx = fx + 0.5; ty = feet + 0.5; }
				else if (!w.solid(fx, chest)) { tx = fx + 0.5; ty = chest + 0.5; }
				else { tx = fx + 0.5; ty = chest - 1 + 0.5; }
			} else if (w.tile(fx, chest) !== T.air) { tx = fx + 0.5; ty = chest + 0.5; }
			else if (w.tile(fx, feet) !== T.air) { tx = fx + 0.5; ty = feet + 0.5; }
			else if (this.stickY > 0.5) { tx = Math.floor(pb.x) + 0.5; ty = below + 0.5; }
			else { tx = fx + 0.5; ty = chest + 0.5; }
		}
		this.aimX = tx; this.aimY = ty; this.aimValid = true;
		this.holdAction(was);
	},
	holdAction(was) {
		if (!was) { this.useWasHeld = false; this.usePressedFlag = false; }
		this.useHeld = true;
	},
	/** the hotbar's next weapon: the one used last, else the next along */
	nextWeaponSlot() {
		const holding = this.heldItem && isWeaponItem(this.heldItem);
		const lw = this.lastWeaponSel;
		if (!holding && lw >= 0 && lw < HOTBAR_N && lw !== this.sel) { const s = this.inv.slots[lw]; if (s && isWeaponItem(s.id)) return lw; }
		for (let k = 1; k <= HOTBAR_N; k++) { const i = (this.sel + k) % HOTBAR_N, s = this.inv.slots[i]; if (s && isWeaponItem(s.id)) return i; }
		return -1;
	},
	cycleWeapon() {
		const i = this.nextWeaponSlot();
		if (i < 0) { this.say("No weapon on the hotbar.", 1.2); return; }
		this.setSel(i); sfx("swap", 0.4);
	},
	/** a wolf takes a bone, a cat a fish: tamed now and then */
	tryTame(m) {
		if (m.tame) return false;
		const it = this.heldItem;
		if (!it) return false;
		const ok = (m.kind === "wolf" && it === "mat:bone") || (m.kind === "cat" && (it === "food:rawFish" || it === "food:cookedFish"));
		if (!ok) return false;
		if (!this.isCreative) this.inv.removeAt(this.sel, 1);
		if (Math.random() < 0.6) {
			m.tame = true; m.persistent = true; m.angry = false; m.hp = m.maxHP;
			this.say("You tamed the " + m.def.name.toLowerCase() + "!", 3);
			this.spawnParticles(m.b.x, m.b.y - 1, 0xFF6080, 10, 3, 0.8, -4);
		} else this.say("The " + m.def.name.toLowerCase() + " isn't convinced yet...", 2);
		this.useCD = 0.5;
		this.bumpHUD();
		return true;
	},
	/** once a frame: wind-ups land, the trail fades, the reload ticks, the lock wears off */
	updateCombatFX(dt) {
		if (this.strikeT > 0) {
			this.strikeT -= dt;
			if (this.strikeT <= 0) { this.strikeT = 0; if (this.strikeSel === this.sel && !this.dead) this.resolveMelee(this.strikeItem); }
		}
		if (this.slashes && this.slashes.length) { for (const s of this.slashes) s.life -= dt; this.slashes = this.slashes.filter((s) => s.life > 0); }
		if (this.dangerZones && this.dangerZones.length) { for (const z of this.dangerZones) z.t -= dt; this.dangerZones = this.dangerZones.filter((z) => z.t > 0); }
		if (this.lockT > 0) { this.lockT -= dt; if (this.lockT <= 0) this.lockTarget = null; }
		if (this.muzzleT > 0) this.muzzleT -= dt;
		if (this.flashes.length) { for (const f of this.flashes) f.age += dt; this.flashes = this.flashes.filter((f) => f.age < f.dur); }
		this.updateReload(dt);
	},
});
// where the player's blows start from
Object.defineProperty(Game.prototype, "shoulderX", { get() { return this.pb.x; } });
Object.defineProperty(Game.prototype, "shoulderY", { get() { return this.pb.y - this.pb.h * 0.55; } });
/** the attack stick's state (see the HUD): held, how far out the thumb is and which way */
const ActStick = { held: false, was: false, dirX: 0, dirY: 0, power: 0, manual: false, deadIn: 0.26, deadOut: 0.17,
	at(x, y) {
		const len = Math.hypot(x, y);
		this.power = Math.min(1, len);
		this.manual = this.power > (this.manual ? this.deadOut : this.deadIn);
		if (this.manual && len > 0.0001) { this.dirX = x / len; this.dirY = y / len; }
		this.held = true;
	},
	release() { this.held = false; this.manual = false; this.power = 0; this.dirX = 0; this.dirY = 0; },
};
/** creature deaths with consequences (bosses, lairs) are added by later code */
const killHooks = [];
/** blocks broken by blasts: a simple version until block physics (phase 4) */
function blastHook(g, x, y, radius, power) {
	const w = g.world, r = Math.ceil(radius);
	for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) {
		const tx = Math.floor(x) + dx, ty = Math.floor(y) + dy, d = Math.hypot(tx + 0.5 - x, ty + 0.5 - y);
		if (d > radius) continue;
		const t = w.tile(tx, ty);
		if (t === T.air || LIQUID[t] || HARD[t] >= 9999 || HARD[t] > power * 0.12) continue;
		if (Math.random() < 0.8 - d / radius * 0.4) {
			if (Math.random() < 0.3 && !g.isCreative) for (const s of tileDropStacks(t, tx, ty, g)) g.spawnDrop(s, tx + 0.5, ty + 0.5, rand(-3, 3), rand(-6, -2));
			w.set(tx, ty, T.air);
		}
	}
}
// light from flashes (explosions)
lightHooks.push((g, out) => {
	for (const f of g.flashes) {
		const t = clampD(f.age / Math.max(0.01, f.dur), 0, 1), u = 1 - t;
		const lv = Math.round(f.peak * u * u * (3 - 2 * u));
		if (lv > 0) out.push(Math.floor(f.x), Math.floor(f.y), lv);
	}
});
