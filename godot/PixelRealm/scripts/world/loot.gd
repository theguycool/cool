class_name Loot
## What chests hold and what creatures drop. A chest's loot depends on where it stands (the
## Warden's hoard, the Umbral Realm, the rift vault, a boss lair, a grotto altar, a mine gallery, a
## ruin of each kind, or plain depth) and is the same every time for the same seed and place.

const ARMOR_SLOTS := ["head", "chest", "legs"]
const TIER_KEYS := ["", "wood", "stone", "copper", "iron", "gold", "diamond", "mythril", "ember", "voidium"]

## [item, min, max, weight, minimum gallery depth]
const MINE_COMMON := [
	["mat:coal", 3, 8, 10.0, 0], ["block:torch", 3, 8, 9.0, 0], ["block:planks", 4, 10, 5.0, 0], ["mat:stick", 3, 8, 4.0, 0],
	["mat:copperOre", 2, 5, 5.0, 0], ["mat:tinOre", 2, 4, 4.0, 0], ["mat:string", 1, 4, 3.0, 0], ["food:bread", 1, 2, 4.0, 0],
	["food:apple", 1, 3, 2.0, 0], ["block:ladder", 2, 6, 3.0, 0], ["block:rail", 3, 8, 2.0, 0], ["mat:ironOre", 1, 3, 3.0, 1],
]
const MINE_USEFUL := [
	["mat:ironBar", 1, 3, 6.0, 0], ["mat:bronzeBar", 2, 4, 6.0, 0], ["ammo:arrow", 6, 14, 4.0, 0], ["ammo:bolt", 4, 10, 4.0, 0],
	["ammo:bullet", 4, 8, 2.0, 1], ["mat:saltpeter", 2, 5, 3.0, 0], ["mat:gunpowder", 2, 4, 3.0, 0], ["gadget:fireFlask", 1, 2, 2.0, 0],
	["gadget:bomb", 1, 2, 2.0, 0], ["block:lantern", 1, 2, 3.0, 0], ["food:cookedMeat", 1, 3, 3.0, 0], ["mat:silverBar", 1, 2, 2.0, 1],
	["mat:goldBar", 1, 2, 2.0, 2], ["mat:amethyst", 1, 3, 1.5, 1], ["knife:iron", 1, 1, 1.5, 0], ["tool:pickaxe:iron", 1, 1, 1.2, 0],
	["club:studded", 1, 1, 1.0, 0], ["gun:crossbow", 1, 1, 0.8, 0], ["armor:head:iron", 1, 1, 0.8, 0],
]
const MINE_EXCEPTIONAL := [
	["relic:moonDagger", 1, 1, 2.0, 0], ["relic:emberCleaver", 1, 1, 1.5, 2], ["relic:quakeMaul", 1, 1, 1.5, 2],
	["gun:repeater", 1, 1, 2.0, 1], ["gun:stormRod", 1, 1, 1.0, 2], ["mat:diamond", 1, 3, 3.0, 1], ["mat:mythrilBar", 1, 2, 1.5, 2],
	["gear:swiftBoots", 1, 1, 1.5, 0], ["gear:headlamp", 1, 1, 2.0, 0], ["gear:silverCharm", 1, 1, 1.5, 0], ["mat:relicFragment", 1, 2, 2.0, 0],
]


static func stack(id: String, n: int) -> Dictionary:
	var ex: int = 0
	var g: Dictionary = DB.gun_info(id)
	if not g.is_empty():
		ex = int(g["magazine"])
	return {"id": id, "n": maxi(1, mini(n, DB.max_stack(id))), "x": ex}


class Roller:
	var rng: SplitRNG
	var out: Array = []

	func _init(seed_value: int) -> void:
		rng = SplitRNG.new(seed_value)

	func add(id: String, lo: int, hi: int, p: float) -> void:
		if rng.next_float() < p and DB.has_item(id):
			out.append(Loot.stack(id, lo + rng.below(maxi(1, hi - lo + 1))))

	func tier(lo: int, hi: int) -> String:
		return Loot.TIER_KEYS[clampi(lo + rng.below(maxi(1, hi - lo + 1)), 1, 9)]

	func armor_slot() -> String:
		return Loot.ARMOR_SLOTS[rng.below(3)]


static func chest_loot(g: WorldGen, dim: int, x: int, y: int) -> Array:
	var r := Roller.new(PRNG.hash_u(x, y, g.world_seed + 777))
	if dim == WorldGen.DIM_UMBRAL:
		var cit: Dictionary = g.citadel()
		if absi(x - Structures.hoard_x(cit)) <= 1 and absi(y - (int(cit["floor"]) - 1)) <= 1:
			r.add("mat:voidBar", 3, 6, 1.0)
			r.add("mat:emberBar", 4, 8, 1.0)
			r.add("mat:diamond", 3, 6, 1.0)
			r.add("mat:relicFragment", 2, 3, 1.0)
			r.add("armor:%s:voidium" % r.armor_slot(), 1, 1, 0.5)
			r.add("spear:voidium", 1, 1, 0.3)
			return r.out
		r.add("mat:emberBar", 2, 6, 0.8)
		r.add("mat:voidBar", 1, 3, 0.35)
		r.add("mat:diamond", 1, 4, 0.6)
		r.add("ammo:arrow", 15, 40, 0.5)
		r.add("ammo:bullet", 8, 20, 0.5)
		r.add("sword:" + r.tier(6, 8), 1, 1, 0.35)
		r.add("armor:%s:%s" % [r.armor_slot(), r.tier(6, 8)], 1, 1, 0.3)
		r.add("food:cookedMeat", 3, 6, 0.6)
		r.add("block:lantern", 2, 4, 0.5)
		return r.out
	if absi(x - g.portal_x) < 20 and y > 300:
		r.add("mat:diamond", 3, 7, 1.0)
		r.add("mat:mythrilBar", 2, 5, 0.9)
		r.add("mat:goldBar", 4, 9, 0.8)
		r.add("gun:rifle", 1, 1, 0.5)
		r.add("ammo:bullet", 12, 30, 0.9)
		r.add("food:cookedMeat", 4, 8, 0.8)
		return r.out
	var lair: Dictionary = g.lair_at(x, 70)
	if not lair.is_empty() and y < 200:
		r.add("mat:goldBar", 3, 8, 0.9)
		r.add("mat:diamond", 1, 3, 0.6)
		r.add("sword:" + r.tier(4, 6), 1, 1, 0.5)
		r.add("armor:%s:%s" % [r.armor_slot(), r.tier(4, 6)], 1, 1, 0.5)
		if lair["kind"] == "bear":
			r.add("mat:fur", 2, 5, 0.9)
			r.add("mat:claw", 1, 3, 0.7)
		else:
			r.add("mat:tusk", 1, 2, 0.5)
			r.add("mat:bone", 6, 14, 1.0)
		r.add("food:cookedMeat", 3, 6, 0.8)
		return r.out
	if y > 150:
		for s in Structures.grotto_sites(g, x - 2, x + 2):
			if absi(x - int(s["x"])) <= int(s["rx"]) and absi(y - int(s["floor"])) < 6:
				r.add("mat:crystalShard", 3, 7, 1.0)
				r.add("mat:diamond", 1, 3, 0.7)
				r.add("block:glowCrystal", 2, 5, 0.8)
				r.add("mat:relicFragment", 1, 2, 0.8)
				r.add("mat:mythrilBar", 1, 3, 0.45)
				r.add("gear:headlamp", 1, 1, 0.3)
				r.add("spear:" + r.tier(4, 6), 1, 1, 0.35)
				return r.out
	for m in Structures.mine_sites(g, x - 2, x + 2):
		var levels: Array = m["levels"]
		if y > int(m["ground"]) + 8 and y <= int(levels[levels.size() - 1]) + 2:
			var lv: int = 0
			for i in range(levels.size()):
				if y <= int(levels[i]):
					lv = i
					break
			return mine_roll(r, lv)
	if y < 260:
		for site in Structures.rare_sites(g, x - 40, x + 40):
			if absi(int(site["x"]) - x) > 40:
				continue
			match String(site["kind"]):
				"tower":
					r.add("bow", 1, 1, 0.45)
					r.add("ammo:arrow", 12, 30, 0.9)
					r.add("mat:goldBar", 1, 4, 0.5)
				"fort":
					r.add("sword:" + r.tier(3, 5), 1, 1, 0.6)
					r.add("armor:%s:%s" % [r.armor_slot(), r.tier(3, 5)], 1, 1, 0.6)
					r.add("ammo:bullet", 6, 14, 0.4)
				"camp":
					r.add("food:cookedMeat", 2, 5, 0.9)
					r.add("food:bread", 2, 4, 0.7)
					r.add("mat:string", 3, 7, 0.6)
					r.add("block:torch", 5, 12, 0.8)
				"overgrown":
					r.add("mat:seeds", 5, 12, 0.9)
					r.add("food:apple", 3, 6, 0.8)
					r.add("mat:diamond", 1, 2, 0.3)
					r.add("gadget:shears", 1, 1, 0.3)
				"bunker":
					r.add("gun:pistol", 1, 1, 0.55)
					r.add("gun:rifle", 1, 1, 0.18)
					r.add("ammo:bullet", 10, 28, 0.9)
					r.add("mat:goldBar", 3, 8, 0.8)
					r.add("mat:mythrilBar", 1, 3, 0.4)
				_:
					r.add("food:cookedFish", 2, 5, 0.7)
					r.add("block:lantern", 1, 3, 0.6)
					r.add("tool:axe:" + r.tier(2, 4), 1, 1, 0.4)
					r.add("mat:copperBar", 2, 6, 0.6)
			if r.out.is_empty():
				r.add("block:planks", 5, 10, 1.0)
			return r.out
	if y < WorldGen.SEA + 40:
		r.add("block:planks", 6, 14, 0.8)
		r.add("food:bread", 1, 3, 0.6)
		r.add("block:torch", 3, 8, 0.7)
		r.add("mat:copperBar", 1, 4, 0.5)
		r.add("mat:relicFragment", 1, 1, 0.15)
	elif y < 320:
		r.add("mat:ironBar", 2, 6, 0.8)
		r.add("mat:goldBar", 1, 4, 0.5)
		r.add("block:torch", 6, 14, 0.8)
		r.add("tool:pickaxe:" + r.tier(3, 5), 1, 1, 0.25)
		r.add("ammo:arrow", 10, 24, 0.5)
		r.add("food:cookedMeat", 2, 4, 0.6)
	else:
		r.add("mat:goldBar", 3, 8, 0.8)
		r.add("mat:diamond", 1, 4, 0.55)
		r.add("mat:mythrilBar", 1, 3, 0.4)
		r.add("sword:" + r.tier(5, 7), 1, 1, 0.3)
		r.add("ammo:bullet", 8, 20, 0.45)
		r.add("block:lantern", 2, 5, 0.6)
	if r.out.is_empty():
		r.add("block:torch", 3, 6, 1.0)
	return r.out


static func _pick(table: Array, depth: int, rng: SplitRNG) -> Array:
	var ok: Array = []
	var total: float = 0.0
	for e in table:
		if int(e[4]) <= depth:
			ok.append(e)
			total += float(e[3])
	if ok.is_empty():
		return []
	var roll: float = rng.next_float() * total
	for e in ok:
		roll -= float(e[3])
		if roll <= 0.0:
			return e
	return ok[ok.size() - 1]


## A mine chest: two to four stacks, never the same item twice, deeper galleries a little richer
static func mine_roll(r: Roller, depth: int) -> Array:
	var n: int = 3 + r.rng.below(2)
	var got := {}
	var p_exc: float = minf(0.012 + 0.008 * float(depth) + 0.012, 0.12)
	if r.rng.next_float() < p_exc:
		var e: Array = _pick(MINE_EXCEPTIONAL, depth, r.rng)
		if not e.is_empty():
			r.out.append(stack(String(e[0]), int(e[1]) + r.rng.below(int(e[2]) - int(e[1]) + 1)))
			got[e[0]] = true
			n -= 1
	var p_use: float = minf(0.18 + 0.05 * float(depth) + 0.06, 0.55)
	var tries: int = 0
	while n > 0 and tries < 12:
		tries += 1
		var e: Array = _pick(MINE_USEFUL if r.rng.next_float() < p_use else MINE_COMMON, depth, r.rng)
		if e.is_empty() or got.has(e[0]):
			continue
		r.out.append(stack(String(e[0]), int(e[1]) + r.rng.below(int(e[2]) - int(e[1]) + 1)))
		got[e[0]] = true
		n -= 1
	if r.out.is_empty():
		r.out.append(stack("block:torch", 4))
	return r.out


## What a creature drops when it dies
static func mob_drops(key: String, sheared: bool) -> Array:
	var out: Array = []
	for e in DB.mob_drops(key):
		if String(e[4]) == "sheared" and sheared:
			continue
		if randf() < float(e[3]):
			var n: int = int(e[1]) + randi() % maxi(1, int(e[2]) - int(e[1]) + 1)
			if n > 0:
				out.append(stack(String(e[0]), n))
	return out
