// Using what is in hand: tapping the world, mining, felling trees, placing blocks and doors, farming,
// eating and chests (the Swift game's p14c_input and p14d_tools).

Object.assign(Game.prototype, {
	// ---- the pointer, in world blocks
	pointerDown(wx, wy) {
		this.aimX = wx; this.aimY = wy; this.aimValid = true;
		this.downTime = 0;
		this.usePressedFlag = false;
		this.touchActive = true;
		const fight = this.heldItem && isWeaponItem(this.heldItem) && this.hostileAt(wx, wy);
		if (!fight && this.isInteractive(wx, wy)) { this.pendingInteract = true; this.useHeld = false; }
		else { this.pendingInteract = false; this.useHeld = true; this.useWasHeld = false; }
		this.pointerStartX = wx; this.pointerStartY = wy;
	},
	pointerMove(wx, wy) {
		this.aimX = wx; this.aimY = wy; this.aimValid = true;
		if (this.pendingInteract) {
			const dx = wx - this.pointerStartX, dy = wy - this.pointerStartY;
			if (dx * dx + dy * dy > 0.5) { this.pendingInteract = false; this.useHeld = true; }
		}
	},
	pointerUp() {
		this.touchActive = false;
		if (this.pendingInteract) { if (this.downTime < 0.3) this.interact(this.aimX, this.aimY); this.pendingInteract = false; }
		if (this.useHeld) this.useReleasedFlag = true;
		this.useHeld = false; this.useWasHeld = false;
	},
	updatePointerTimers(dt) {
		if (this.pendingInteract) {
			this.downTime += dt;
			if (this.downTime >= 0.3) { this.pendingInteract = false; this.useHeld = true; this.useWasHeld = false; }
		}
	},
	hostileAt(wx, wy) { return hostileAtHook(this, wx, wy); },
	reachDistance() { return this.infiniteReach ? 60 : this.isCreative ? 8 : 5.5; },
	inReach(x, y) {
		const dx = x - this.pb.x, dy = y - (this.pb.y - this.pb.h * 0.6), r = this.reachDistance();
		return dx * dx + dy * dy <= r * r;
	},
	aimFacing() { return this.aimX >= this.pb.x ? 1 : -1; },

	// ---- tapping blocks that do something
	isInteractive(wx, wy) {
		const t = this.world.tile(Math.floor(wx), Math.floor(wy));
		if (INTERACTIVE.has(t)) return true;
		return interactiveHook(this, wx, wy, t);
	},
	interact(wx, wy) {
		const tx = Math.floor(wx), ty = Math.floor(wy);
		if (!this.inReach(wx, wy)) { this.say("Too far away.", 1.2); return; }
		const t = this.world.tile(tx, ty);
		if (t === T.chest && this.tryMimic(tx, ty)) return;
		if (t === T.chest || t === T.cabinet || t === T.wardrobe) {
			sfx("chestOpen", 0.7);
			this.spawnParticles(tx + 0.5, ty + 0.3, 0xC8A878, 5, 2, 0.4, 6);
			this.openChest = { x: tx, y: ty };
			this.world.chestItems(tx, ty);
			openPanel("inventory");
			return;
		}
		const st = STATION_OF_TILE.get(t);
		if (st) { this.craftStation = st; openPanel("inventory", "craft"); return; }
		if (t === T.doorClosed || t === T.doorOpen) { this.toggleDoor(tx, ty); return; }
		interactHook(this, tx, ty, t, wx, wy);
	},

	// ---- using what is in hand
	updateUse(dt) {
		if (this.useCD > 0) this.useCD -= dt;
		if (this.swingT > 0) this.swingT -= dt; else this.swingDur = 0.25;
		if (this.eatT > 0) this.eatT -= dt;
		if (this.placeCD > 0) this.placeCD -= dt;
		if (this.dead) { this.mining = false; this.usePressedFlag = false; this.useReleasedFlag = false; return; }
		const pressed = this.usePressedFlag; this.usePressedFlag = false;
		const released = this.useReleasedFlag; this.useReleasedFlag = false;
		const held = this.heldItem;
		// letting go always ends the hold, even when the finger is gone and nothing is aimed at any more
		if (!this.useHeld) { this.mining = false; this.mineP = Math.max(0, this.mineP - dt * 2); }
		if (!this.aimValid) { if (!this.useHeld) { this.handEmptied = false; this.lastUsedItem = null; } return; }
		if (useItemHook(this, held, dt, pressed, released)) return;
		if (!this.useHeld) { this.handEmptied = false; this.lastUsedItem = null; return; }
		if (pressed) this.holdItem = held;
		// what is picked up into an empty hand during a hold waits for the next press: the hold keeps digging
		if (held && this.holdItem === null && !pressed) { this.useBareHand(dt, pressed); return; }
		if (!held) {
			// a stack used up while held does not turn the hold into mining with bare hands
			if (this.lastUsedItem !== null) this.handEmptied = true;
			this.lastUsedItem = null;
			if (!this.handEmptied) this.useBareHand(dt, pressed);
			return;
		}
		this.lastUsedItem = held;
		const kind = itemKind(held);
		const d = itemDef(held);
		if (kind === "block") this.usePlaceBlock(itemTile(held), dt);
		else if (kind === "tool") this.useToolItem(d.toolKind, d.tier, d.mineSpeed, dt, pressed);
		else if (kind === "food") this.useFood(held, pressed);
		else if (held === "mat:seeds") this.usePlant(T.wheat1, pressed);
		else if (kind === "wall") this.usePlaceWall(d.wall);
		else if (kind === "armor" || kind === "gear") { if (pressed) { this.quickEquip(this.sel); this.say("Equipped.", 1); } }
		else if (isMeleeItem(held)) this.useMeleeWeapon(held, pressed, dt);
		else this.useBareHand(dt, pressed);
	},
	useBareHand(dt, pressed) {
		if (meleeHook(this, null, pressed)) return;
		this.mineStep(Math.floor(this.aimX), Math.floor(this.aimY), null, 0, dt, 1);
	},
	useToolItem(kind, tier, speed, dt, pressed) {
		const tx = Math.floor(this.aimX), ty = Math.floor(this.aimY);
		if (meleeHook(this, this.heldItem, pressed)) return;
		if (kind === "hoe" && this.useCD <= 0) {
			const t = this.world.tile(tx, ty);
			if ((t === T.grass || t === T.dirt || t === T.dryGrass || t === T.mossGrass) && this.inReach(tx + 0.5, ty + 0.5) && !this.world.solid(tx, ty - 1)) {
				this.world.set(tx, ty, T.farmland);
				if (PLANT[this.world.tile(tx, ty - 1)]) this.world.set(tx, ty - 1, T.air);
				this.useCD = 0.25; this.swingT = 0.2; this.swingDir = this.facing;
				this.spawnParticles(tx + 0.5, ty, 0x6B4626, 6, 2.5, 0.4, 12);
				return;
			}
		}
		this.mineStep(tx, ty, kind, tier, dt, speed);
	},

	// ---- mining
	mineStep(tx, ty, kind, tier, dt, toolSpeed) {
		const t = this.world.tile(tx, ty);
		if (t === T.air && this.mineWall(tx, ty, kind, tier, dt)) return;
		if (t === T.air || LIQUID[t]) {
			this.mining = false; this.mineP = 0;
			if (this.useCD <= 0 && kind && kind !== "hoe") { this.swingT = 0.2; this.swingDir = this.aimFacing(); this.facing = this.swingDir; this.useCD = 0.3; }
			return;
		}
		const def = TILE[t];
		if (def.hard >= 9999) { if (this.useCD <= 0) { this.say("That can't be broken.", 1.2); this.useCD = 0.6; } return; }
		if (!this.inReach(tx + 0.5, ty + 0.5)) { this.mining = false; this.mineP = 0; return; }
		const cls = TOOL_CLASS[t];
		if (def.tier > 0 && !this.isCreative) {
			// a tier asks for a strong enough tool of the block's own kind
			const pt = kind === cls ? tier : 0;
			if (pt < def.tier) {
				this.mining = false;
				if (this.useCD <= 0) {
					this.say(kind === cls ? "This needs a stronger " + cls + "." : "You need a " + cls + " for that.", 1.5);
					this.useCD = 0.8; this.swingT = 0.2; this.swingDir = this.aimFacing();
				}
				return;
			}
		}
		if (this.mineX !== tx || this.mineY !== ty || !this.mining) {
			if (this.mineX !== tx || this.mineY !== ty) this.mineP = 0;
			this.mineX = tx; this.mineY = ty;
		}
		this.mining = true;
		let speed = 1;
		if (kind) speed = toolSpeed * (kind === cls ? 1 : 0.35);
		if (this.isCreative) speed = 1000;
		this.mineNeed = Math.max(0.05, def.hard * 1.5);
		this.mineP += dt * speed * rule("mining");
		if (this.useCD <= 0) {
			this.swingT = 0.22; this.swingDir = this.aimFacing(); this.facing = this.swingDir; this.useCD = 0.26;
			this.spawnParticles(tx + 0.5, ty + 0.5, def.color, 3, 3, 0.4, 14);
			digSound(t, false);
		}
		if (this.mineP >= this.mineNeed) {
			this.mineP = 0; this.mining = false;
			digSound(t, true);
			if (IS_LOG[t] && kind === "axe") this.fellTree(tx, ty);
			else this.breakTile(tx, ty, true);
		}
	},
	/** pickaxes and axes knock out placed walls when nothing is in front of them */
	mineWall(tx, ty, kind, tier, dt) {
		const k = this.world.wall(tx, ty);
		if (k === 0 || !kind || kind === "hoe") return false;
		if (!this.inReach(tx + 0.5, ty + 0.5)) return false;
		if (this.mineX !== tx || this.mineY !== ty) { this.mineP = 0; this.mineX = tx; this.mineY = ty; }
		this.mining = true;
		this.mineNeed = 0.9;
		this.mineP += dt * (this.isCreative ? 1000 : TIERS[Math.max(1, tier) - 1].mineSpeed);
		if (this.useCD <= 0) { this.swingT = 0.22; this.swingDir = this.aimFacing(); this.facing = this.swingDir; this.useCD = 0.26; }
		if (this.mineP >= this.mineNeed) {
			this.mineP = 0; this.mining = false;
			this.world.setWall(tx, ty, 0);
			const back = k >= blockWallBase ? blockItem(k - blockWallBase) : "wall:" + k;
			if (!this.isCreative) this.spawnDrop(stack(back, 1), tx + 0.5, ty + 0.5, 0, -2);
		}
		return true;
	},
	minedDrops(t, x, y, byPlayer) {
		const out = tileDropStacks(t, x, y, this);
		if (!byPlayer) return out;
		const r = Math.random();
		if (t === T.tallGrass && r < 0.1) out.push(stack("mat:sunleaf", 1));
		else if ((t === T.flowerR || t === T.flowerY) && r < 0.35) out.push(stack("mat:sunleaf", 1));
		else if (t === T.mushroom && r < 0.3) out.push(stack("mat:glowcap", 1));
		else if (t === T.ice && r < 0.15) out.push(stack("mat:frostCrystal", 1));
		else if (t === T.snow && r < 0.03) out.push(stack("mat:frostCrystal", 1));
		return out;
	},
	breakTile(x, y, byPlayer, dropChance = 1) {
		const w = this.world;
		const t = w.tile(x, y);
		if (t === T.air || HARD[t] >= 9999) return;
		if (this.isDoor(t)) {
			if (this.isDoor(w.tile(x, y - 1))) w.set(x, y - 1, T.air);
			if (this.isDoor(w.tile(x, y + 1))) w.set(x, y + 1, T.air);
		}
		if (t === T.bedL && w.tile(x + 1, y) === T.bedR) w.set(x + 1, y, T.air);
		if (t === T.bedR && w.tile(x - 1, y) === T.bedL) w.set(x - 1, y, T.air);
		if (w.set(x, y, T.air) === T.air) return;
		if (IS_LOG[t] && this.decayZones.length < 24) this.decayZones.push({ x, y, t: 30 });
		if (IS_LEAF[t]) for (let k = 0; k < 3; k++) this.dropLeaf(x + rand(0.1, 0.9), y + rand(0.2, 0.8), t);
		this.spawnParticles(x + 0.5, y + 0.5, TILE[t].color, 6, 3.5, 0.5, 16);
		if (!(byPlayer && this.isCreative)) {
			for (const s of this.minedDrops(t, x, y, byPlayer)) {
				if (dropChance < 1 && Math.random() > dropChance) continue;
				this.spawnDrop(s, x + 0.5, y + 0.4, rand(-1.5, 1.5), -3);
			}
		} else if (t === T.chest) w.removeChest(x, y);
		// what stood on it falls with it
		const above = w.tile(x, y - 1);
		if (NEEDS_SUPPORT[above] && !w.supports(w.tile(x, y), above)) this.breakTile(x, y - 1, byPlayer);
		breakHooks.forEach((f) => f(this, x, y, t));
		this.bumpHUD();
	},
	fellTree(x, y) {
		const w = this.world;
		let by = y;
		while (IS_LOG[w.tile(x, by + 1)]) by++;
		let cy = by, top = y, count = 0;
		while (IS_LOG[w.tile(x, cy)] && count < 40) { top = cy; cy--; count++; }
		for (let yy = y; IS_LOG[w.tile(x, yy)] && yy >= top; yy--) this.breakTile(x, yy, true);
		for (let dy = -7; dy <= 3; dy++) for (let dx = -6; dx <= 6; dx++) {
			if (IS_LEAF[w.tile(x + dx, top + dy)] && Math.abs(dx) + Math.abs(dy + 1) <= 8) this.breakTile(x + dx, top + dy, true);
		}
	},

	// ---- placing
	canPlaceAt(tx, ty, t) {
		const w = this.world;
		if (ty < 2 || ty >= w.H - 2) return false;
		const cur = w.tile(tx, ty);
		if (!(cur === T.air || LIQUID[cur] || (PLANT[cur] && cur !== T.torch && cur !== T.lantern) || cur === T.cobweb)) return false;
		if (!this.inReach(tx + 0.5, ty + 0.5)) return false;
		if (SOLID[t]) {
			const pb = this.pb;
			if (bodyRight(pb) > tx + 0.02 && bodyLeft(pb) < tx + 0.98 && pb.y > ty + 0.02 && bodyTop(pb) < ty + 0.98 && !this.noclip) return false;
			for (const m of this.mobs) if (m.hp > 0 && bodyRight(m.b) > tx + 0.02 && bodyLeft(m.b) < tx + 0.98 && m.b.y > ty + 0.02 && bodyTop(m.b) < ty + 0.98) return false;
		}
		if (NEEDS_SUPPORT[t] && !w.supports(w.tile(tx, ty + 1), t)) return false;
		if (this.isCreative || this.flying) return true;
		// it needs a block beside it to hold on to, or a wall behind it
		for (const k of [w.tile(tx - 1, ty), w.tile(tx + 1, ty), w.tile(tx, ty - 1), w.tile(tx, ty + 1)]) if (k !== T.air && !LIQUID[k] && !(PLANT[k] && k !== T.torch)) return true;
		return w.wall(tx, ty) !== 0;
	},
	usePlaceBlock(t, dt) {
		if (this.placeCD > 0 || t < 0) return;
		const tx = Math.floor(this.aimX), ty = Math.floor(this.aimY);
		if (t === T.doorClosed || t === T.doorOpen) {
			if (this.placeDoor(tx, ty)) { if (!this.isCreative) this.inv.removeAt(this.sel, 1); this.placeCD = 0.25; this.swingT = 0.14; this.bumpHUD(); }
			return;
		}
		if (placeHook(this, t, tx, ty)) return;
		const placed = placedForm(t);
		if (!this.canPlaceAt(tx, ty, placed)) return;
		this.world.set(tx, ty, placed);
		this.world.setBuilt(tx, ty, true);
		if (t === T.chest || t === T.cabinet || t === T.wardrobe) this.world.setChestItems(tx, ty, []);
		if (!this.isCreative) this.inv.removeAt(this.sel, 1);
		sfx("place", 0.6);
		this.placeCD = 0.11; this.swingT = 0.14; this.swingDir = this.aimFacing(); this.facing = this.swingDir;
		this.bumpHUD();
	},
	placeDoor(tx, ty0) {
		const w = this.world;
		let ty = ty0;
		if (w.tile(tx, ty + 1) === T.air && w.solid(tx, ty + 2)) ty++;
		if (!w.solid(tx, ty + 1)) return false;
		for (const yy of [ty, ty - 1]) { const c = w.tile(tx, yy); if (!(c === T.air || (PLANT[c] && c !== T.torch && c !== T.lantern))) return false; }
		if (this.doorBlocked(tx, ty - 1, ty) || !this.inReach(tx + 0.5, ty + 0.5)) return false;
		w.set(tx, ty - 1, T.doorClosed); w.set(tx, ty, T.doorClosed);
		w.setBuilt(tx, ty - 1, true); w.setBuilt(tx, ty, true);
		sfx("place", 0.6);
		return true;
	},
	usePlaceWall(k) {
		if (this.placeCD > 0) return;
		const tx = Math.floor(this.aimX), ty = Math.floor(this.aimY);
		if (!this.inReach(tx + 0.5, ty + 0.5) || this.world.wall(tx, ty) !== 0) return;
		this.world.setWall(tx, ty, k);
		if (!this.isCreative) this.inv.removeAt(this.sel, 1);
		this.placeCD = 0.06; this.swingT = 0.12; this.swingDir = this.aimFacing(); this.facing = this.swingDir;
		this.bumpHUD();
	},
	usePlant(crop, pressed) {
		if (this.placeCD > 0) return;
		const tx = Math.floor(this.aimX), ty = Math.floor(this.aimY);
		if (this.world.tile(tx, ty) === T.air && this.world.tile(tx, ty + 1) === T.farmland && this.inReach(tx + 0.5, ty + 0.5)) {
			this.world.set(tx, ty, crop);
			if (!this.isCreative) this.inv.removeAt(this.sel, 1);
			this.placeCD = 0.2; this.swingT = 0.14;
			this.bumpHUD();
		}
	},
	useFood(id, pressed) {
		const tx = Math.floor(this.aimX), ty = Math.floor(this.aimY);
		if (id === "food:carrot" && this.world.tile(tx, ty) === T.air && this.world.tile(tx, ty + 1) === T.farmland) { this.usePlant(T.carrot1, pressed); return; }
		if (!pressed || this.eatT > 0) return;
		if (this.hunger >= 19.5 && this.hp >= this.maxHP && !this.isCreative) { this.say("You're not hungry.", 1.2); return; }
		const d = itemDef(id);
		this.hunger = Math.min(20, this.hunger + (d.hunger || 0));
		if (d.heal > 0) this.heal(d.heal);
		if (!this.isCreative) this.inv.removeAt(this.sel, 1);
		this.eatT = 0.5; this.useCD = 0.5;
		sfx("eat", 0.6);
		this.spawnParticles(this.pb.x + this.facing * 0.4, this.pb.y - 1.4, 0xC8A060, 5, 2, 0.4, 8);
		this.floatText("+" + Math.floor(d.hunger || 0), this.pb.x, this.pb.y - this.pb.h - 0.4, 0xE0A040);
		this.bumpHUD();
	},

	// ---- armour and gear
	/** puts on the armour or gear in a bag slot, swapping out what was worn there */
	quickEquip(i) {
		const s = this.inv.slots[i];
		if (!s) return;
		let slot = -1;
		if (s.id.startsWith("armor:")) slot = ARMOR_SLOTS.indexOf(s.id.split(":")[1]);
		else if (s.id.startsWith("gear:")) slot = this.inv.armor[FIRST_GEAR] ? (this.inv.armor[FIRST_GEAR + 1] ? FIRST_GEAR : FIRST_GEAR + 1) : FIRST_GEAR;
		if (slot < 0) return;
		const old = this.inv.armor[slot];
		this.inv.armor[slot] = s;
		this.inv.slots[i] = old;
		sfx("equip", 0.5);
		this.bumpHUD();
	},
	unequip(slot) {
		const s = this.inv.armor[slot];
		if (!s) return;
		if (this.inv.add(s.id, s.n, s.extra, s.inf) === 0) this.inv.armor[slot] = null;
		this.bumpHUD();
	},
	// ---- chests
	chestTake(cx, cy, k) {
		const items = this.world.chestItems(cx, cy);
		const s = items[k];
		if (!s) return;
		const left = this.inv.add(s.id, s.n, s.extra, s.inf);
		if (left === 0) items.splice(k, 1); else s.n = left;
		this.world.setChestItems(cx, cy, items);
		this.bumpHUD();
	},
	chestStore(cx, cy, i) {
		const s = this.inv.slots[i];
		if (!s) return;
		const items = this.world.chestItems(cx, cy);
		const ms = maxStack(s.id);
		for (const o of items) if (o.id === s.id && sameInf(o.inf, s.inf) && o.n < ms && s.n > 0) { const put = Math.min(ms - o.n, s.n); o.n += put; s.n -= put; }
		if (s.n > 0) {
			if (items.length >= 27) { this.say("Chest is full.", 1.5); this.bumpHUD(); return; }
			items.push(s);
		}
		this.inv.slots[i] = null;
		this.world.setChestItems(cx, cy, items);
		this.bumpHUD();
	},
	/** throws a stack from the bag onto the ground in front of the player */
	dropSlot(i, all = true) {
		const s = this.inv.slots[i];
		if (!s) return;
		const n = all ? s.n : 1;
		this.spawnDrop(stack(s.id, n, s.extra, s.inf), this.pb.x + this.facing * 0.6, this.pb.y - 1.2, this.facing * 4, -3, true);
		this.inv.removeAt(i, n);
		this.bumpHUD();
	},
});

const INTERACTIVE = new Set([T.chest, T.workbench, T.furnace, T.campfire, T.anvil, T.tinkerBench, T.riftForge, T.alchemyStill, T.doorClosed, T.doorOpen, T.cabinet, T.wardrobe]);
const STATION_OF_TILE = new Map([[T.workbench, "bench"], [T.furnace, "furnace"], [T.campfire, "campfire"], [T.anvil, "anvil"], [T.tinkerBench, "tinker"], [T.riftForge, "forge"], [T.alchemyStill, "still"]]);
const breakHooks = [];
// later phases fill these in (creatures, special blocks, weapons)
function placeHook(g, t, tx, ty) { return false; }
