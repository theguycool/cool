class_name SaveSystem
## Saving and loading a world: one JSON file per slot in user://saves, holding the world's settings,
## the player (where, health, hunger, inventory, armour), time and weather, bosses beaten, the
## journal, and every changed chunk (compressed) with its chests.

const VERSION := 1


static func exists(slot: int) -> bool:
	return FileAccess.file_exists(Game.slot_path(slot))


static func read(slot: int) -> Dictionary:
	var f: FileAccess = FileAccess.open(Game.slot_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed
	return {}


static func write(lv: Level, slot: int) -> bool:
	var p: Player = lv.player
	var worlds := {}
	for d in lv.worlds.keys():
		worlds[str(d)] = (lv.worlds[d] as WorldData).to_save()
	var data := {
		"meta": {"name": lv.world_name, "mode": lv.mode, "seed": lv.seed_value, "infinite": lv.infinite, "day": lv.day_count,
			"time": Time.get_unix_time_from_system(), "play_seconds": lv.play_seconds, "version": VERSION, "kills": lv.kills,
			"flat": bool(lv.options.get("flat", false)), "trees": bool(lv.options.get("trees", true)),
			"structures": bool(lv.options.get("structures", true)), "caves": bool(lv.options.get("caves", false)),
			"ponds": bool(lv.options.get("ponds", false)), "rare_chance": float(lv.options.get("rare_chance", 0.28))},
		"player": {"x": p.global_position.x, "y": p.global_position.y, "hp": p.hp, "hunger": p.hunger, "air": p.air,
			"sel": p.actions.sel, "cold": p.body_cold, "spawn_x": lv.spawn_point.x, "spawn_y": lv.spawn_point.y, "inv": p.inv.to_save()},
		"dim": lv.dim,
		"time_of_day": lv.time_of_day,
		"defeated": lv.defeated.keys(),
		"portal_opened": lv.portal_opened,
		"journal": lv.journal.to_save(),
		"weather": lv.weather.to_save(),
		"worlds": worlds,
		"pets": _pets(lv),
		"vehicles": lv.all_vehicles(),
	}
	var f: FileAccess = FileAccess.open(Game.slot_path(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true


## Tamed creatures (pets and a tamed Tyrannax) travel in the save with their health and orders
static func _pets(lv: Level) -> Array:
	var out: Array = []
	for m in lv.mobs:
		var mm: Mob = m
		if mm.tame and mm.hp > 0.0:
			out.append({"key": mm.key, "v": mm.variant, "x": mm.global_position.x, "y": mm.global_position.y,
				"hp": mm.hp, "max": mm.max_hp, "stay": mm.stay})
	return out


## Puts a loaded save into a level whose world has just been set up from the save's "meta"
static func apply(lv: Level, data: Dictionary) -> void:
	var worlds: Dictionary = data.get("worlds", {})
	for key in worlds.keys():
		var w: WorldData = lv._world_for(int(key))
		w.from_save(worlds[key])
	lv.time_of_day = float(data.get("time_of_day", 0.25))
	lv.day_count = int((data.get("meta", {}) as Dictionary).get("day", 1))
	lv.play_seconds = float((data.get("meta", {}) as Dictionary).get("play_seconds", 0.0))
	lv.kills = int((data.get("meta", {}) as Dictionary).get("kills", 0))
	for k in data.get("defeated", []):
		lv.defeated[String(k)] = true
	lv.portal_opened = bool(data.get("portal_opened", false))
	lv.journal.from_save(data.get("journal", {}))
	lv.weather.from_save(data.get("weather", {}))
	var pd: Dictionary = data.get("player", {})
	var p: Player = lv.player
	p.inv.from_save(pd.get("inv", {}))
	p.hp = float(pd.get("hp", 20.0))
	p.hunger = float(pd.get("hunger", 20.0))
	p.air = float(pd.get("air", 10.0))
	p.body_cold = clampf(float(pd.get("cold", 0.0)), 0.0, 1.0)
	p.actions.sel = int(pd.get("sel", 0))
	lv.spawn_point = Vector2(float(pd.get("spawn_x", 0.0)), float(pd.get("spawn_y", float(WorldGen.SEA * 8))))
	var d: int = int(data.get("dim", 0))
	if d != lv.dim:
		lv._switch_world(d)
	var pos := Vector2(float(pd.get("x", lv.spawn_point.x)), float(pd.get("y", lv.spawn_point.y)))
	lv._load_around(floori(pos.x / 8.0), 2)
	p.global_position = pos
	p.refresh_look()
	for e in data.get("pets", []):
		if not (e is Dictionary):
			continue
		var pd2: Dictionary = e
		var m: Mob = lv.spawn_mob(String(pd2.get("key", "wolf")), Vector2(float(pd2.get("x", pos.x)), float(pd2.get("y", pos.y))), int(pd2.get("v", -1)))
		m.tame = true
		m.persistent = true
		m.max_hp = float(pd2.get("max", m.max_hp))
		m.hp = float(pd2.get("hp", m.max_hp))
		m.stay = bool(pd2.get("stay", false))
		m.refresh_frames()
	for e in data.get("vehicles", []):
		if not (e is Array) or (e as Array).size() < 4:
			continue
		var a: Array = e
		var vd: int = int(a[3])
		if vd == lv.dim:
			lv.add_vehicle(String(a[0]), Vector2(float(a[1]), float(a[2])))
		else:
			var list: Array = lv.parked.get(vd, [])
			list.append([String(a[0]), float(a[1]), float(a[2])])
			lv.parked[vd] = list
