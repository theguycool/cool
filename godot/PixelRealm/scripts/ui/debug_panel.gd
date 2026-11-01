class_name DebugPanel
extends PanelBase
## The debug menu: live numbers about the game, cheats (fly, no-clip, god mode), the clock, teleports,
## damage and health multipliers, game speed, hazard tests, forced weather, the AI overlay and hit
## boxes, the spawn log (why night monsters did or did not appear) and a button for every creature.

const GREY := Color(0.36, 0.36, 0.36)
const RED := Color(0.63, 0.19, 0.19)
const PURPLE := Color(0.42, 0.23, 0.63)

var list: ScrollList
var _rows: Array = []
var _confirm: bool = false
var _with_vehicles: bool = false
var _refresh_t: float = 0.0


func setup(lv: Level) -> void:
	level = lv
	setup_frame(Vector2(760, 640), false, Color(0, 0, 0, 0.35))
	var head: HBoxContainer = UIKit.title_row("DEBUG", 20, Color(1.0, 0.88, 0.4))
	head.add_child(UIKit.button("CLOSE", RED, close, 0.0, 36.0))
	content.add_child(head)
	list = ScrollList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.font_size = 14
	list.row_tapped.connect(_on_row)
	content.add_child(list)
	_fill(false)


func _process(delta: float) -> void:
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.5
		_fill(true)


func _row(id: String, text: String, sub: String = "", buttons: Array = []) -> Dictionary:
	return {"id": id, "text": text, "sub": sub, "buttons": buttons}


func _toggle(id: String, text: String, on: bool) -> Dictionary:
	return {"id": id, "text": text, "toggle": on}


func _btns(labels: Array) -> Array:
	var out: Array = []
	for l in labels:
		out.append([String(l), GREY])
	return out


func _fill(keep: bool) -> void:
	var lv: Level = level
	var p: Player = lv.player
	var rows: Array = []
	rows.append({"kind": "header", "text": "STATS"})
	var dim_name: String = "Overworld" if lv.dim == WorldGen.DIM_OVERWORLD else "Umbral"
	var stats: Array = [
		"FPS %d · physics %d Hz · speed x%.1f" % [Engine.get_frames_per_second(), Engine.physics_ticks_per_second, Engine.time_scale],
		"XY %.1f, %.1f · %s · %s" % [p.global_position.x / 8.0, p.global_position.y / 8.0, dim_name, DB.biome_name(lv.gen.biome_at(floori(p.global_position.x / 8.0)))],
		"Seed %d · %s%s" % [lv.seed_value, "Infinite" if lv.infinite else "Classic", " flat" if bool(lv.options.get("flat", false)) else ""],
		"Chunks %d · building %d · stashed %d" % [lv.world.chunks.size(), lv.world.pending_count(), lv.world.stash.size()],
		"Mobs %d · drops/other %d · shots %d · vehicles %d" % [lv.mobs.size(), lv.entities.get_child_count() - lv.mobs.size(), lv.projectiles_node.get_child_count(), lv.vehicles.size()],
		"Time %.2f · day %d · sky %d · %s" % [lv.time_of_day, lv.day_count, lv.sky_level(), "night" if lv.is_night() else "day"],
		"Weather %s · cloud %.2f · rain %.2f · wind %.1f" % [lv.weather.kind, lv.weather.cloud, lv.weather.precip, lv.weather.wind],
		"Gate %d, %d%s · spawn %d" % [lv.gen.portal_x, lv.gen.portal_y, " (open)" if lv.portal_opened else "", lv.gen.spawn_x],
	]
	for s in stats:
		rows.append({"kind": "text", "text": String(s)})
	rows.append({"kind": "header", "text": "CHEATS AND VIEW"})
	rows.append(_toggle("fly", "Fly", p.flying))
	rows.append(_toggle("noclip", "No-clip (fly through blocks)", p.noclip))
	rows.append(_toggle("god", "God mode (no damage)", p.god_mode))
	rows.append(_toggle("free", "Stop the clock", lv.free_time))
	rows.append(_toggle("spawning", "Creature spawning", lv.spawner.enabled))
	rows.append(_toggle("freeze", "Freeze creatures", lv.freeze_mobs))
	rows.append(_toggle("ai", "AI overlay (state and reason over each creature)", lv.show_ai))
	rows.append(_toggle("boxes", "Hit boxes", lv.show_hitboxes))
	rows.append(_toggle("hudinfo", "Extra numbers on the HUD", lv.hud.overlay))
	rows.append({"kind": "header", "text": "TIME"})
	rows.append(_row("time", "Set the time", "", _btns(["Dawn", "Noon", "Dusk", "Night"])))
	rows.append({"kind": "header", "text": "PLAYER"})
	rows.append(_row("player", "Player", "", _btns(["Heal", "Give kit", "Kill hostiles", "Set on fire"])))
	rows.append({"kind": "header", "text": "TELEPORT"})
	rows.append(_row("tp1", "Places", "", _btns(["Spawn", "Surface", "Gate"])))
	rows.append(_row("tp2", "Lairs and realms", "", [["Bear den", GREY], ["Rex nest", GREY], ["Other realm", PURPLE]]))
	rows.append(_row("tp3", "Steps", "", _btns(["Up 20", "Down 20", "<- 200", "200 ->"])))
	rows.append({"kind": "header", "text": "SPEED AND MULTIPLIERS"})
	rows.append(_row("speed", "Game speed", "x%.1f" % Engine.time_scale, _btns(["-", "+"])))
	rows.append(_row("mobhp", "Creature health (new spawns)", "x%.2f" % lv.mob_health_mult, _btns(["-", "+"])))
	rows.append(_row("dmgout", "Damage dealt", "x%.2f" % lv.dmg_out_mult, _btns(["-", "+"])))
	rows.append(_row("dmgin", "Damage taken", "x%.2f" % lv.dmg_in_mult, _btns(["-", "+"])))
	rows.append(_row("reset", "Reset speed and multipliers", "", _btns(["Reset"])))
	rows.append({"kind": "header", "text": "HAZARD TESTS"})
	rows.append(_row("hazard", "Drop a hazard beside you", "", _btns(["Lava", "Explosion", "Sand", "Spikes"])))
	rows.append({"kind": "header", "text": "WEATHER"})
	rows.append(_row("wx1", "Force the weather", "", _btns(["Clear", "Rain", "Storm", "Wind"])))
	rows.append(_row("wx2", "", "", _btns(["Snow", "Hail", "Blizzard", "Tornado"])))
	rows.append({"kind": "header", "text": "NIGHTS: WHY SPAWNS FAILED"})
	var keys: Array = lv.spawner.spawn_log.keys()
	keys.sort()
	if keys.is_empty():
		rows.append({"kind": "text", "text": "No spawn attempts yet."})
	for k in keys:
		rows.append({"kind": "text", "text": "%s: %d" % [String(k), int(lv.spawner.spawn_log[k])]})
	rows.append(_row("log", "Monster limit %d surface / %d caves" % [lv.spawner.monster_cap("surface"), lv.spawner.monster_cap("cave")], "", _btns(["Clear log"])))
	rows.append({"kind": "header", "text": "ENTITIES"})
	rows.append(_toggle("withveh", "Include vehicles when deleting", _with_vehicles))
	if _confirm:
		rows.append(_row("delete", "Really delete every creature, drop and shot?", "", [["CONFIRM", Color(0.75, 0.13, 0.13)], ["Cancel", GREY]]))
	else:
		rows.append(_row("delete", "Delete all entities", "", [["Delete", RED]]))
	rows.append({"kind": "header", "text": "SPAWN A CREATURE"})
	for key in DB.mob_keys:
		var k2: String = String(key)
		if k2 == "villager":
			continue
		rows.append({"id": "spawn:" + k2, "text": String(DB.mob(k2).get("name", k2)), "sub": k2, "buttons": [["Spawn", GREY]]})
	_rows = rows
	list.set_rows(rows, keep)


func _on_row(i: int, b: int) -> void:
	if i < 0 or i >= _rows.size():
		return
	var row: Dictionary = _rows[i]
	var id: String = String(row.get("id", ""))
	var lv: Level = level
	var p: Player = lv.player
	Sfx.play("tap", 0.4)
	if id.begins_with("spawn:"):
		DebugTools.spawn(lv, id.substr(6))
	else:
		match id:
			"fly":
				p.flying = not p.flying
				if not p.flying:
					p.noclip = false
				lv.hud_dirty = true
			"noclip":
				p.noclip = not p.noclip
				p.flying = p.noclip or p.flying
				lv.hud_dirty = true
			"god":
				p.god_mode = not p.god_mode
			"free":
				lv.free_time = not lv.free_time
			"spawning":
				lv.spawner.enabled = not lv.spawner.enabled
			"freeze":
				lv.freeze_mobs = not lv.freeze_mobs
			"ai":
				lv.show_ai = not lv.show_ai
			"boxes":
				lv.show_hitboxes = not lv.show_hitboxes
			"hudinfo":
				lv.hud.overlay = not lv.hud.overlay
			"time":
				if b >= 0:
					DebugTools.set_time(lv, [0.95, 0.25, 0.52, 0.75][b])
			"player":
				match b:
					0:
						DebugTools.heal(lv)
					1:
						DebugTools.give_kit(lv)
					2:
						DebugTools.kill_hostiles(lv)
					3:
						DebugTools.set_on_fire(lv)
			"tp1":
				match b:
					0:
						DebugTools.to_spawn(lv)
					1:
						DebugTools.to_surface(lv)
					2:
						DebugTools.to_portal(lv)
			"tp2":
				match b:
					0:
						DebugTools.to_lair(lv, "bear")
					1:
						DebugTools.to_lair(lv, "rex")
					2:
						DebugTools.switch_dimension(lv)
			"tp3":
				match b:
					0:
						DebugTools.nudge(lv, 0, -20)
					1:
						DebugTools.nudge(lv, 0, 20)
					2:
						DebugTools.nudge(lv, -200, 0)
					3:
						DebugTools.nudge(lv, 200, 0)
			"speed":
				if b >= 0:
					Engine.time_scale = clampf(Engine.time_scale + (0.5 if b == 1 else -0.5), 0.5, 4.0)
			"mobhp":
				if b >= 0:
					lv.mob_health_mult = clampf(lv.mob_health_mult + (0.25 if b == 1 else -0.25), 0.25, 5.0)
			"dmgout":
				if b >= 0:
					lv.dmg_out_mult = clampf(lv.dmg_out_mult + (0.25 if b == 1 else -0.25), 0.0, 10.0)
			"dmgin":
				if b >= 0:
					lv.dmg_in_mult = clampf(lv.dmg_in_mult + (0.25 if b == 1 else -0.25), 0.0, 5.0)
			"reset":
				Engine.time_scale = 1.0
				lv.mob_health_mult = 1.0
				lv.dmg_out_mult = 1.0
				lv.dmg_in_mult = 1.0
			"hazard":
				match b:
					0:
						DebugTools.lava_pool(lv)
					1:
						DebugTools.explosion(lv)
					2:
						DebugTools.sand_drop(lv)
					3:
						DebugTools.spikes(lv)
			"wx1":
				if b >= 0:
					lv.weather.force(lv, ["clear", "heavyRain", "thunderstorm", "windstorm"][b])
			"wx2":
				if b >= 0:
					lv.weather.force(lv, ["snowfall", "hailstorm", "blizzard", "tornado"][b])
			"log":
				lv.spawner.spawn_log.clear()
			"withveh":
				_with_vehicles = not _with_vehicles
			"delete":
				if not _confirm:
					_confirm = true
				else:
					if b == 0:
						DebugTools.delete_entities(lv, _with_vehicles)
					_confirm = false
	_fill(true)
