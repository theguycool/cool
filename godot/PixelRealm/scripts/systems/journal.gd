class_name Journal
extends RefCounted
## What the player has found and learned: places (with the day they were found), the lore they
## unlock, what has been crafted, relic fragments collected, and the goals worth chasing.

var places: Array = []
var lore: Array = []
var crafted: Array = []
var relics: int = 0

const LORE := {
	"ruin.house": ["A Ruined House", "A cellar ladder, a cold hearth, a child's carving of a bear above the door. Whoever lived here left in a hurry, and went down rather than out."],
	"ruin.tower": ["A Ruined Tower", "The watch log's last entry: 'Lights under the hill again. Nobody goes down there now.'"],
	"ruin.fort": ["An Old Fort", "Every arrowhead in these walls points outward and down. Whatever they fought came up out of the caves."],
	"ruin.camp": ["An Abandoned Camp", "Bedrolls for four, supplies for one. The tracks lead toward the mountains and do not come back."],
	"ruin.overgrown": ["An Overgrown Ruin", "Roots have split a shrine stone. Its carving shows a door torn open in the sky, and a hooded figure standing in it."],
	"ruin.bunker": ["A Buried Bunker", "Iron doors, rusted from the inside. Someone hoarded powder and shot for a war that never reached them."],
	"mine": ["An Old Mine", "A tally scratched into a support beam stops at forty-one. Under it, in a different hand: 'The rock sings this deep.'"],
	"grotto": ["A Crystal Grotto", "The crystals hum when you stand still. Something set them here, and something keeps them."],
	"lair.bear": ["The Bear's Den", "Claw marks ring the stones. The great bear sleeps on a seal it was set to guard, and the key to that seal sleeps with it."],
	"lair.rex": ["The Bone Nest", "Ribs older than the hills. Whatever crowned itself with these bones still nests among them."],
	"portal": ["The Sealed Gate", "A chamber built around a door, deep under the earth, and a key-shaped hollow worn smooth by many hands."],
	"umbral": ["The Umbral Realm", "No sky, no sun, only ash and ember. The rift hums behind you. It is not the only door that was opened."],
	"citadel": ["The Warden's Citadel", "Carved over the gate: HERE THE WARDEN KEEPS THE DOOR, HOLLOW SINCE THE RIFT TORE OPEN."],
	"sentinel": ["The Sentinel", "It came apart into shards that still glow. It was not alive, but it was waiting, and it was told what to guard."],
	"warden": ["The Hollow Warden", "There was nothing inside the armour. Its heart is warm and beats slowly. A rift forge could bind it into something worn."],
	"wx.lightning": ["Notes on Lightning", "It strikes the highest thing near it: a tree top, a roof, a hill. A copper rod standing high takes every strike within fourteen blocks safely into the ground."],
	"wx.wind": ["Notes on Wind", "A strong wind carries arrows and loose things with it and leans on you as you walk."],
	"wx.hail": ["Notes on Hail", "Most hail only bruises crops and flowers. Now and then it falls as big as eggs: then bare heads ache. A roof, or a helmet, is enough."],
	"wx.blizzard": ["Notes on Blizzards", "It is the wind on you that does the harm. A fire, a roof and walls, a good coat: any of them buys time. Snow boots keep you on your feet."],
	"wx.tornado": ["Notes on Tornadoes", "They grow out of the worst thunderstorms and travel with the wind. Underground you will hear it pass and little more. Out in the open it will pick you up."],
	"wx.hurricane": ["Notes on Hurricanes", "They come off the sea in walls of wind and rain. The calm in the middle is the eye; then the wind comes back from the other side."],
}


static func ruin_name(kind: String) -> String:
	match kind:
		"house": return "Ruined House"
		"tower": return "Ruined Tower"
		"fort": return "Old Fort"
		"camp": return "Abandoned Camp"
		"overgrown": return "Overgrown Ruin"
	return "Buried Bunker"


func has(key: String) -> bool:
	for p in places:
		if String(p["key"]) == key:
			return true
	return false


func has_kind(prefix: String) -> bool:
	for p in places:
		if String(p["key"]).begins_with(prefix):
			return true
	return false


## Notes a place (once); returns true if it is new
func discover(key: String, name_: String, x: int, lore_key: String, day: int, dim: int) -> bool:
	if has(key):
		return false
	places.append({"key": key, "name": name_, "x": x, "day": day, "dim": dim})
	add_lore(lore_key)
	return true


func add_lore(key: String) -> void:
	if key != "" and not lore.has(key):
		lore.append(key)


func note_item(id: String, n: int) -> void:
	if id == "mat:relicFragment":
		relics += n


func note_crafted(name_: String) -> void:
	if not crafted.has(name_):
		crafted.append(name_)


## [title, hint, done] for each goal
func goals(lv: Level) -> Array:
	var bear: bool = false
	var rex: bool = false
	var sentinel: bool = false
	for k in lv.defeated.keys():
		var s: String = String(k)
		if s.begins_with("lair:bear"):
			bear = true
		elif s.begins_with("lair:rex"):
			rex = true
		elif s.begins_with("sentinel"):
			sentinel = true
	var sigil: bool = crafted.has("Warden's Sigil") or lv.player.inv.wearing("gear:wardenSigil") or lv.player.inv.total("gear:wardenSigil") > 0
	return [
		["Set up a workbench", "Eight planks. Chop a tree with your hands or an axe, then make planks from the logs.", crafted.has("Workbench")],
		["Forge iron on an anvil", "Smelt iron ore in a furnace, then build an anvil (6 iron bars, 4 stone) at the workbench.", crafted.has("Anvil")],
		["Explore an old mine", "Look for a timber headframe over a covered shaft. The treasure map marks them.", has_kind("mine:")],
		["Find a crystal grotto", "Deep underground, sometimes with a cave mouth leading down.", has_kind("grotto:")],
		["Defeat Ursavor", "The great bear's den holds the Portal Key.", bear],
		["Open the sealed gate", "The Portal Key opens the rift chamber far below the surface. The treasure map narrows it down.", lv.portal_opened],
		["Defeat Tyrannax", "Something nests among enormous bones in the jungle.", rex],
		["Silence a Crystal Sentinel", "Each grotto has a guardian. Its shards are worth the fight.", sentinel],
		["Reach the Warden's citadel", "In the Umbral Realm, several hundred blocks from the rift.", has("citadel")],
		["Defeat the Hollow Warden", "Watch the ground: its strikes are marked before they land.", lv.defeated.has("warden")],
		["Forge the Warden's Sigil", "The Warden's heart, 4 voidium bars and 4 crystal shards at a rift forge.", sigil],
		["Recover relic fragments (%d/10)" % mini(relics, 10), "Found in ruins, mines, grottos and with the bosses.", relics >= 10],
	]


func to_save() -> Dictionary:
	return {"places": places, "lore": lore, "crafted": crafted, "relics": relics}


func from_save(d: Dictionary) -> void:
	places = d.get("places", [])
	lore = d.get("lore", [])
	crafted = d.get("crafted", [])
	relics = int(d.get("relics", 0))
