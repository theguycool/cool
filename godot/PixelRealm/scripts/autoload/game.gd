extends Node
## The running game (autoload "Game"): settings, what the next world to open is, the level that is
## open now, saving when the app goes to the background, and moving between the menu and a world.

const SETTINGS_PATH := "user://settings.json"
const SAVE_DIR := "user://saves"
const SLOTS := 6
const LEVEL_SCENE := "res://scenes/level.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"

## Everything the player can change; saved to user://settings.json
var settings := {
	"touch_controls": true,
	"swap_sticks": false,
	"sfx_volume": 0.7,
	"ambience_volume": 0.5,
	"sound": true,
	"zoom": 4.0,
	"smooth_light": true,
	"show_fps": false,
	"show_coords": true,
	"night_danger": 1,
	"weather": true,
	"weather_hurts": true,
	"weather_alerts": true,
	"allow_rain": true,
	"allow_thunder": true,
	"allow_wind": true,
	"allow_hail": true,
	"allow_blizzard": true,
	"allow_tornado": true,
	"allow_hurricane": true,
	"peaceful": false,
	"fps60": true,
	"rare_chance": 0.28,
	"reduce_flashes": false,
	"shake": 1.0,
	"hair": 0,
	"scarf": 0,
	"trajectory": true,
	"autosave": true,
	"threaded_gen": true,
}

## What the level should do when it opens: {"new": {...world params}} or {"load": slot}
var pending: Dictionary = {}
## the open level (scripts/level.gd), or null in the menu
var level = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_settings()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var text: String = FileAccess.get_file_as_string(SETTINGS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var d: Dictionary = parsed
		for k in d.keys():
			if settings.has(k):
				settings[k] = d[k]


func save_settings() -> void:
	var f: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(settings, "\t"))
		f.close()


func apply_settings() -> void:
	Sfx.sfx_volume = float(settings["sfx_volume"])
	Sfx.ambience_volume = float(settings["ambience_volume"])
	Sfx.enabled = bool(settings["sound"])
	Engine.max_fps = 60 if bool(settings["fps60"]) else 30


func setting(key: String, fallback: Variant = null) -> Variant:
	return settings.get(key, fallback)


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	apply_settings()
	save_settings()
	if level != null and level.has_method("on_settings_changed"):
		level.call("on_settings_changed")


# ---------------------------------------------------------------------------------------------- worlds

## params: {"name", "seed", "mode" ("survival"/"creative"/"hardcore"), "infinite", "flat", "trees",
## "structures", "caves", "ponds", "slot"}
func start_new_world(params: Dictionary) -> void:
	pending = {"new": params}
	get_tree().paused = false
	get_tree().change_scene_to_file(LEVEL_SCENE)


func load_world(slot: int) -> void:
	pending = {"load": slot}
	get_tree().paused = false
	get_tree().change_scene_to_file(LEVEL_SCENE)


func quit_to_menu() -> void:
	if level != null and level.has_method("save_game"):
		level.call("save_game")
	level = null
	Sfx.stop_loops()
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


## The summary of every save slot: [{"slot", "name", "mode", "day", "seed", "time"} or {} for empty]
func list_slots() -> Array:
	var out: Array = []
	for i in range(SLOTS):
		var p: String = slot_path(i)
		if not FileAccess.file_exists(p):
			out.append({})
			continue
		var f: FileAccess = FileAccess.open(p, FileAccess.READ)
		if f == null:
			out.append({})
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary and (parsed as Dictionary).has("meta"):
			var meta: Dictionary = (parsed as Dictionary)["meta"]
			meta["slot"] = i
			out.append(meta)
		else:
			out.append({})
	return out


func first_free_slot() -> int:
	var slots: Array = list_slots()
	for i in range(slots.size()):
		if (slots[i] as Dictionary).is_empty():
			return i
	return 0


func delete_slot(slot: int) -> void:
	var p: String = slot_path(slot)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)


## Saves when the app goes to the background or is closed (iPad: switching apps, the home gesture)
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if level != null and level.has_method("save_game"):
			level.call("save_game")
		save_settings()
