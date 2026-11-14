// Items, stacks and the inventory (the Swift game's p03_items and p04_recipes). Items are strings, as
// the exporter names them: "block:dirt", "tool:pickaxe:iron", "mat:coal", "food:bread" ...

const TIERS = DATA.misc.tiers;                 // wood (1) ... voidium (9)
const tierByKey = {};
for (const t of TIERS) tierByKey[t.key] = t;
const ITEMS = new Map();
for (const it of DATA.items) ITEMS.set(it.id, it);
const ITEM_LIST = DATA.items.map((it) => it.id);

/** an item the exporter did not list (a block form that is never handed out, like a crop) */
function itemDef(id) {
	let d = ITEMS.get(id);
	if (d) return d;
	const p = id.split(":");
	if (p[0] === "block" && T[p[1]] !== undefined) {
		const t = T[p[1]];
		d = { id, name: TILE[t].name, maxStack: 99, sortGroup: 8, tile: t, info: ["Building block"], melee: ITEMS.get("block:dirt").melee, icon: -1 };
	} else {
		d = { id, name: p[p.length - 1], maxStack: 99, sortGroup: 9, info: [], melee: ITEMS.get("block:dirt").melee, icon: -1 };
	}
	ITEMS.set(id, d);
	return d;
}
const itemName = (id) => itemDef(id).name;
const maxStack = (id) => itemDef(id).maxStack;
const itemKind = (id) => id.slice(0, id.indexOf(":") < 0 ? id.length : id.indexOf(":"));
/** the tile a block item is, or -1 */
function itemTile(id) {
	if (!id.startsWith("block:")) return -1;
	const t = T[id.slice(6)];
	return t === undefined ? -1 : t;
}
const blockItem = (t) => "block:" + TILE[t].key;
const isWeaponItem = (id) => !!itemDef(id).isWeapon;
const isMeleeItem = (id) => !!itemDef(id).isMelee;
const isRangedItem = (id) => !!itemDef(id).isRanged;
/** the art for an item's icon: [x, y, w, h] in the atlas */
function iconRect(id) {
	const d = itemDef(id);
	if (d.icon >= 0) { const s = d.isz || 16; return [(d.icon % 64) * 16, DATA.atlas.itemY + Math.floor(d.icon / 64) * 16, s, s]; }
	const t = itemTile(id);
	if (t >= 0) return [tileAX(t), tileAY(t), 16, 16];
	return [0, 0, 1, 1];
}
const HOTBAR_N = DATA.misc.hotbar;     // 10
const BAG_N = DATA.misc.bag;           // 40
const ARMOR_N = 5;                     // head, chest, legs, then two gear slots
const FIRST_GEAR = 3;
const ARMOR_SLOTS = ["head", "chest", "legs"];

const stack = (id, n, extra = 0, inf = null) => ({ id, n, extra, inf });
const sameInf = (a, b) => (!a && !b) || (a && b && a.length === b.length && a.every((v, i) => v === b[i]));

class Inventory {
	constructor() {
		this.slots = new Array(BAG_N).fill(null);
		this.armor = new Array(ARMOR_N).fill(null);
	}
	total(id) { let n = 0; for (const s of this.slots) if (s && s.id === id) n += s.n; return n; }
	/** adds items, gives back how many did not fit; infused items never merge with plain ones */
	add(id, count, extra = 0, inf = null) {
		let left = count;
		const ms = maxStack(id);
		if (ms > 1) {
			for (let i = 0; i < this.slots.length && left > 0; i++) {
				const st = this.slots[i];
				if (st && st.id === id && sameInf(st.inf, inf) && st.n < ms) { const put = Math.min(ms - st.n, left); st.n += put; left -= put; }
			}
		}
		for (let i = 0; i < this.slots.length && left > 0; i++) {
			if (!this.slots[i]) { const put = Math.min(ms, left); this.slots[i] = stack(id, put, extra, inf); left -= put; }
		}
		return left;
	}
	remove(id, count) {
		if (this.total(id) < count) return false;
		let left = count;
		for (let i = 0; i < this.slots.length && left > 0; i++) {
			const st = this.slots[i];
			if (st && st.id === id) { const take = Math.min(st.n, left); st.n -= take; left -= take; if (st.n <= 0) this.slots[i] = null; }
		}
		return true;
	}
	canAfford(cost) { for (const c of cost) if (this.total(c[0]) < c[1]) return false; return true; }
	canFit(id, count) {
		let room = 0;
		const ms = maxStack(id);
		for (const s of this.slots) { if (s) { if (s.id === id && ms > 1 && !s.inf) room += ms - s.n; } else room += ms; }
		return room >= count;
	}
	removeAt(i, n) {
		const st = this.slots[i];
		if (!st) return;
		st.n -= n;
		if (st.n <= 0) this.slots[i] = null;
	}
	swap(a, b) { const t = this.slots[a]; this.slots[a] = this.slots[b]; this.slots[b] = t; }
	/** folds partial stacks of the same item into the first of them */
	mergeStacks() {
		let merged = 0;
		for (let i = 0; i < this.slots.length; i++) {
			const a = this.slots[i];
			if (!a) continue;
			const ms = maxStack(a.id);
			if (ms <= 1 || a.n >= ms) continue;
			for (let j = i + 1; j < this.slots.length && a.n < ms; j++) {
				const b = this.slots[j];
				if (!b || b.id !== a.id || b.extra !== a.extra || !sameInf(b.inf, a.inf)) continue;
				const put = Math.min(ms - a.n, b.n);
				a.n += put; b.n -= put;
				if (b.n <= 0) this.slots[j] = null;
				merged++;
			}
		}
		return merged;
	}
	/** sorts the bag (everything past the hotbar): equal stacks merge, then by kind and name */
	sortBag() {
		const list = [];
		for (let i = HOTBAR_N; i < this.slots.length; i++) {
			const s = this.slots[i];
			if (!s) continue;
			this.slots[i] = null;
			const ms = maxStack(s.id);
			const j = ms > 1 ? list.findIndex((o) => o.id === s.id && o.extra === s.extra && sameInf(o.inf, s.inf) && o.n < ms) : -1;
			if (j >= 0) {
				const put = Math.min(ms - list[j].n, s.n);
				list[j].n += put;
				if (s.n - put > 0) list.push(stack(s.id, s.n - put, s.extra, s.inf));
			} else list.push(s);
		}
		list.sort((a, b) => {
			const ka = itemDef(a.id).sortGroup, kb = itemDef(b.id).sortGroup;
			if (ka !== kb) return ka - kb;
			const na = itemName(a.id), nb = itemName(b.id);
			if (na !== nb) return na < nb ? -1 : 1;
			return b.n - a.n;
		});
		list.forEach((s, k) => { if (HOTBAR_N + k < this.slots.length) this.slots[HOTBAR_N + k] = s; });
	}
	/** total armour defence */
	get defense() {
		let d = 0;
		for (const s of this.armor) if (s && s.id.startsWith("armor:")) d += itemDef(s.id).defense || 0;
		return d;
	}
	wearing(gear) { for (let i = FIRST_GEAR; i < this.armor.length; i++) { const s = this.armor[i]; if (s && s.id === "gear:" + gear) return true; } return false; }
	toJSON() { return { slots: this.slots, armor: this.armor }; }
	static from(o) {
		const v = new Inventory();
		if (o && o.slots) o.slots.forEach((s, i) => { if (i < BAG_N) v.slots[i] = s ? stack(s.id, s.n, s.extra || 0, s.inf || null) : null; });
		if (o && o.armor) o.armor.forEach((s, i) => { if (i < ARMOR_N) v.armor[i] = s ? stack(s.id, s.n, s.extra || 0, s.inf || null) : null; });
		return v;
	}
}

// ---- recipes
const STATION_NAMES = { hand: "By hand", bench: "Workbench", furnace: "Furnace", campfire: "Campfire / Furnace", anvil: "Anvil", tinker: "Tinker's Bench", forge: "Rift Forge", still: "Alchemy Still", infuser: "Infusion Crucible", assembly: "Assembly Station" };
const STATION_TILES = { bench: [T.workbench], furnace: [T.furnace], campfire: [T.furnace, T.campfire], anvil: [T.anvil], tinker: [T.tinkerBench], forge: [T.riftForge], still: [T.alchemyStill], infuser: [T.infuser], assembly: [T.exoStation] };
const RECIPE_CATS = ["basic", "build", "tools", "weapons", "armor", "gear", "smelt", "food", "vehicle", "weather", "power", "mods", "alchemy", "infusion", "exosuit"];
const CAT_NAMES = { basic: "Basics", build: "Building", tools: "Tools", weapons: "Weapons", armor: "Armor", gear: "Gear", smelt: "Smelting", food: "Food", vehicle: "Vehicles", weather: "Weather", power: "Power", mods: "Mods", alchemy: "Alchemy", infusion: "Infusion", exosuit: "Exosuit" };
const RECIPES = DATA.recipes.map((r, i) => ({ id: i, out: r.out, n: r.count, cost: r.cost, station: r.station, cat: r.cat }));

/** which way a tool works: "pickaxe", "axe", "shovel", "hoe" */
const TOOL_CLASS = TILE.map((t) => t.toolClass);
/** a tile's drops when broken (before tool and luck extras) */
function tileDropStacks(t, x, y, game) {
	const out = [];
	const r = Math.random();
	switch (t) {
		case T.tallGrass: if (r < 0.14) out.push(stack("mat:seeds", 1)); break;
		case T.leaves: case T.jungleLeaves: case T.birchLeaves: case T.pineLeaves:
			if ((t === T.leaves || t === T.jungleLeaves) && r < 0.05) out.push(stack("food:apple", 1));
			if (Math.random() < 0.085) out.push(stack("block:sapling", 1));
			break;
		case T.wheat3: out.push(stack("food:wheat", 1 + randInt(0, 1))); out.push(stack("mat:seeds", 1 + randInt(0, 2))); break;
		case T.wheat1: case T.wheat2: out.push(stack("mat:seeds", 1)); break;
		case T.carrot3: out.push(stack("food:carrot", 1 + randInt(0, 2))); break;
		case T.carrot1: case T.carrot2: out.push(stack("food:carrot", 1)); break;
		case T.cobweb: out.push(stack("mat:string", 1)); break;
		case T.saltpeter: out.push(stack("mat:saltpeter", 1 + (r < 0.35 ? 1 : 0))); break;
		case T.amethyst: out.push(stack("mat:amethyst", 1 + (r < 0.5 ? 1 : 0))); break;
		case T.chest: for (const s of game.world.removeChest(x, y)) out.push(s); out.push(stack("block:chest", 1)); break;
		case T.cabinet: case T.wardrobe: for (const s of game.world.removeChest(x, y)) out.push(s); out.push(stack(blockItem(t), 1)); break;
		default: {
			const d = TILE[t];
			if (d.drop) out.push(stack(d.drop, 1));
			else if (!d.noDrop) out.push(stack(blockItem(t), 1));
		}
	}
	return out;
}
const ORE_TILES = new Set([T.coal, T.copper, T.iron, T.gold, T.diamond, T.mythril, T.emberOre, T.voidOre, T.tin, T.silver, T.saltpeter, T.amethyst, T.crystalOre]);

// ---- chest loot: decided by a chest's place, the first time it is opened (the Swift game's
// generateChestLoot, without the structures that are not ported yet)
function generateChestLoot(g, dim, x, y) {
	const rng = new RNG(hashU(x, y, g.seed + 777));
	const out = [];
	const add = (id, lo, hi, p) => { if (rng.double() < p) out.push(stack(id, lo + rng.int(Math.max(1, hi - lo + 1)))); };
	const tierPick = (lo, hi) => TIERS[clampI(lo + rng.int(Math.max(1, hi - lo + 1)), 1, 9) - 1].key;
	const slots = ["head", "chest", "legs"];
	if (dim === Dimension.umbral) {
		add("mat:emberBar", 2, 6, 0.8); add("mat:voidBar", 1, 3, 0.35); add("mat:diamond", 1, 4, 0.6);
		add("ammo:arrow", 15, 40, 0.5); add("ammo:bullet", 8, 20, 0.5); add("sword:" + tierPick(6, 8), 1, 1, 0.35);
		add("armor:" + slots[rng.int(3)] + ":" + tierPick(6, 8), 1, 1, 0.3); add("food:cookedMeat", 3, 6, 0.6); add("block:lantern", 2, 4, 0.5);
		return out;
	}
	if (Math.abs(x - g.portalX) < 20 && y > 300) {
		add("mat:diamond", 3, 7, 1); add("mat:mythrilBar", 2, 5, 0.9); add("mat:goldBar", 4, 9, 0.8); add("gun:rifle", 1, 1, 0.5); add("ammo:bullet", 12, 30, 0.9); add("food:cookedMeat", 4, 8, 0.8);
		return out;
	}
	const L = g.lairAt(x, 70);
	if (L && y < 200) {
		add("mat:goldBar", 3, 8, 0.9); add("mat:diamond", 1, 3, 0.6); add("sword:" + tierPick(4, 6), 1, 1, 0.5);
		add("armor:" + slots[rng.int(3)] + ":" + tierPick(4, 6), 1, 1, 0.5);
		if (L.kind === 0) { add("mat:fur", 2, 5, 0.9); add("mat:claw", 1, 3, 0.7); } else { add("mat:tusk", 1, 2, 0.5); add("mat:bone", 6, 14, 1); }
		add("food:cookedMeat", 3, 6, 0.8);
		return out;
	}
	const special = chestLootHook(g, dim, x, y, rng, add, tierPick);
	if (special) return special;
	if (y < GEN_SEA + 40) {
		add("block:planks", 6, 14, 0.8); add("food:bread", 1, 3, 0.6); add("block:torch", 3, 8, 0.7); add("mat:copperBar", 1, 4, 0.5);
		if (g.genVersion >= 3) add("mat:relicFragment", 1, 1, 0.15);
	} else if (y < 320) {
		add("mat:ironBar", 2, 6, 0.8); add("mat:goldBar", 1, 4, 0.5); add("block:torch", 6, 14, 0.8); add("tool:pickaxe:" + tierPick(3, 5), 1, 1, 0.25);
		add("ammo:arrow", 10, 24, 0.5); add("food:cookedMeat", 2, 4, 0.6);
	} else {
		add("mat:goldBar", 3, 8, 0.8); add("mat:diamond", 1, 4, 0.55); add("mat:mythrilBar", 1, 3, 0.4); add("sword:" + tierPick(5, 7), 1, 1, 0.3);
		add("ammo:bullet", 8, 20, 0.45); add("block:lantern", 2, 5, 0.6);
	}
	if (!out.length) add("block:torch", 3, 6, 1);
	return out;
}
/** loot of structures added by later phases (ruins, mines, grottos); null when none applies */
function chestLootHook(g, dim, x, y, rng, add, tierPick) { return null; }

Object.assign(World.prototype, {
	chestKey(x, y) { return this.dim + ":" + x + ":" + y; },
	chestItems(x, y) {
		const k = this.chestKey(x, y);
		let it = this.chests.get(k);
		if (!it) { it = generateChestLoot(this.gen, this.dim, x, y); this.chests.set(k, it); }
		return it;
	},
	setChestItems(x, y, items) { this.chests.set(this.chestKey(x, y), items); },
	removeChest(x, y) {
		const k = this.chestKey(x, y);
		const out = this.chests.has(k) ? this.chests.get(k) : (y >= 0 ? this.chestItems(x, y) : []);
		this.chests.delete(k);
		return out;
	},
});
