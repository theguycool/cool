extends Node
## Lookup tables for tiles, items, recipes and creatures (autoload "DB"). The tables come from the
## generated scripts in scripts/data, which are exported from the Swift game; this script turns them
## into fast arrays and dictionaries.

const TilesData = preload("res://scripts/data/tiles_data.gd")
const ItemsData = preload("res://scripts/data/items_data.gd")
const RecipesData = preload("res://scripts/data/recipes_data.gd")
const MobsData = preload("res://scripts/data/mobs_data.gd")
const MiscData = preload("res://scripts/data/misc_data.gd")
const LootData = preload("res://scripts/data/loot_data.gd")
const WallsData = preload("res://scripts/data/walls_data.gd")

const TOOL_PICKAXE := 0
const TOOL_AXE := 1
const TOOL_SHOVEL := 2
const TOOL_HOE := 3

const STATIONS := ["hand", "bench", "furnace", "campfire", "anvil", "tinker", "forge"]
const STATION_NAMES := {"hand": "By hand", "bench": "Workbench", "furnace": "Furnace", "campfire": "Campfire / Furnace",
	"anvil": "Anvil", "tinker": "Tinker's Bench", "forge": "Rift Forge"}
const CATEGORY_NAMES := {"basic": "Basics", "build": "Building", "tools": "Tools", "weapons": "Weapons", "armor": "Armor",
	"gear": "Gear", "smelt": "Smelting", "food": "Food", "vehicle": "Vehicles", "weather": "Weather", "power": "Power"}

var tiles: Array = []
var solid := PackedByteArray()
var opaque := PackedByteArray()
var light := PackedByteArray()
var liquid := PackedByteArray()
var platform := PackedByteArray()
var plant := PackedByteArray()
var hurts := PackedByteArray()
## gets the lit top and shaded bottom rim where it meets open space (solid or trunk, and opaque)
var edge := PackedByteArray()
var supports := PackedByteArray()
var needs_support := PackedByteArray()
var leaf := PackedByteArray()
var trunk := PackedByteArray()
var tier := PackedByteArray()
var tool_class := PackedByteArray()
var hardness := PackedFloat32Array()
var placed_form := PackedInt32Array()
var sound_mat := PackedByteArray()
var drop_of: Array = []
var tile_ids := {}

var items := {}
var item_order: Array = []
var recipes: Array = []
var mobs := {}
var mob_keys: Array = []
var walls := {}


func _init() -> void:
	var n: int = TilesData.TILES.size()
	# (packed arrays are values: each member is resized by name, not through a list of them)
	solid.resize(n)
	opaque.resize(n)
	light.resize(n)
	liquid.resize(n)
	platform.resize(n)
	plant.resize(n)
	hurts.resize(n)
	edge.resize(n)
	supports.resize(n)
	needs_support.resize(n)
	leaf.resize(n)
	trunk.resize(n)
	tier.resize(n)
	tool_class.resize(n)
	sound_mat.resize(n)
	hardness.resize(n)
	placed_form.resize(n)
	drop_of.resize(n)
	for t in TilesData.TILES:
		var id: int = t["id"]
		tiles.append(t)
		tile_ids[t["key"]] = id
		solid[id] = 1 if t["solid"] else 0
		opaque[id] = 1 if t["opaque"] else 0
		light[id] = int(t["light"])
		liquid[id] = 1 if t["liquid"] else 0
		platform[id] = 1 if t["platform"] else 0
		plant[id] = 1 if t["plant"] else 0
		hurts[id] = 1 if t["hurt"] else 0
		supports[id] = 1 if t["supports"] else 0
		edge[id] = 1 if (t["supports"] and t["opaque"]) else 0
		needs_support[id] = 1 if t["needsSupport"] else 0
		leaf[id] = 1 if t["leaf"] else 0
		trunk[id] = 1 if t["log"] else 0
		tier[id] = mini(255, int(t["tier"]))
		hardness[id] = float(t["hard"])
		placed_form[id] = int(t["placed"])
		sound_mat[id] = int(t["sound"])
		match String(t["toolClass"]):
			"axe": tool_class[id] = TOOL_AXE
			"shovel": tool_class[id] = TOOL_SHOVEL
			"hoe": tool_class[id] = TOOL_HOE
			_: tool_class[id] = TOOL_PICKAXE
		var drop: String = String(t["drop"])
		if t["noDrop"]:
			drop = ""
		elif drop == "":
			drop = "block:" + String(t["key"])
		drop_of[id] = drop
	for it in ItemsData.ITEMS:
		items[it["id"]] = it
		item_order.append(it["id"])
	recipes = RecipesData.RECIPES
	for m in MobsData.MOBS:
		mobs[m["key"]] = m
		mob_keys.append(m["key"])
	for w in WallsData.WALLS:
		walls[int(w["kind"])] = w


# ---------------------------------------------------------------------------------------------- tiles

func tile_name(id: int) -> String:
	if id < 0 or id >= tiles.size():
		return "?"
	return String(tiles[id]["name"])


func tile_key(id: int) -> String:
	if id < 0 or id >= tiles.size():
		return "air"
	return String(tiles[id]["key"])


func tile_id(key: String) -> int:
	return int(tile_ids.get(key, 0))


func is_solid(id: int) -> bool:
	return solid[id] == 1


func is_opaque(id: int) -> bool:
	return opaque[id] == 1


func is_liquid(id: int) -> bool:
	return liquid[id] == 1


## things can rest on it or hang from it (solid, or a tree trunk)
func can_support(id: int) -> bool:
	return supports[id] == 1


# ---------------------------------------------------------------------------------------------- items

func item(id: String) -> Dictionary:
	if items.has(id):
		return items[id]
	return {"id": id, "name": id.capitalize(), "info": [], "maxStack": 99, "sortGroup": 10, "isWeapon": false,
		"isMelee": false, "isRanged": false, "icon": 0, "melee": items["block:dirt"]["melee"]}


func has_item(id: String) -> bool:
	return items.has(id)


func item_name(id: String) -> String:
	return String(item(id)["name"])


func max_stack(id: String) -> int:
	return int(item(id).get("maxStack", 99))


## "block", "tool", "sword"... the part of the id before the first colon
func kind_of(id: String) -> String:
	return id.get_slice(":", 0)


## the tile a block item places, or -1
func block_tile(id: String) -> int:
	var it: Dictionary = item(id)
	if it.has("tile"):
		return int(it["tile"])
	return -1


func is_weapon(id: String) -> bool:
	return bool(item(id).get("isWeapon", false))


func is_melee_weapon(id: String) -> bool:
	return bool(item(id).get("isMelee", false))


func is_ranged(id: String) -> bool:
	return bool(item(id).get("isRanged", false))


## How the item strikes when swung (bare hands when id is "")
func melee_of(id: String) -> Dictionary:
	if id == "":
		return BARE_HANDS
	return item(id)["melee"]


const BARE_HANDS := {"damage": 1.5, "cooldown": 0.4, "reach": 1.8, "halfArc": 0.75, "style": "bash", "band": 0.55, "maxHits": 99,
	"knock": 4.0, "heavy": false, "daze": 0.0, "windup": 0.0, "swingTime": 0.22, "moveScale": 1.0, "critChance": 0.1, "burn": 0.0,
	"undeadMult": 1.0, "combo": false, "backstab": 1.0, "shockwave": false, "trail": 15259848}


func tier_of(id: String) -> int:
	return int(item(id).get("tier", 0))


func tier_info(t: int) -> Dictionary:
	for e in MiscData.TIERS:
		if int(e["id"]) == t:
			return e
	return MiscData.TIERS[0]


func tool_kind(id: String) -> int:
	match String(item(id).get("toolKind", "")):
		"pickaxe": return TOOL_PICKAXE
		"axe": return TOOL_AXE
		"shovel": return TOOL_SHOVEL
		"hoe": return TOOL_HOE
	return -1


## what the item restores when eaten: [hunger, heal]
func food_values(id: String) -> Array:
	var it: Dictionary = item(id)
	return [float(it.get("hunger", 0.0)), float(it.get("heal", 0.0))]


func gun_info(id: String) -> Dictionary:
	return item(id).get("gun", {})


func wall_name(kind: int) -> String:
	if walls.has(kind):
		return String(walls[kind]["name"])
	return "Wall"


# ---------------------------------------------------------------------------------------------- creatures

func mob(key: String) -> Dictionary:
	return mobs.get(key, mobs["pig"])


func mob_drops(key: String) -> Array:
	return LootData.MOB_DROPS.get(key, [])


func biome_name(b: int) -> String:
	const NAMES := ["Ocean", "Plains", "Forest", "Desert", "Snowy Tundra", "Jungle", "Savanna", "Swamp", "Mountains", "Umbral Realm"]
	if b < 0 or b >= NAMES.size():
		return "?"
	return NAMES[b]
