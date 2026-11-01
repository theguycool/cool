class_name Spawner
extends Node
## Bringing creatures into the world around the player, as in the Swift game: animals by day on the
## grass of their own biome, night monsters on the surface (paced so they arrive one by one, never in
## light, never in sight), cave creatures by depth, fish in water, the Umbral Realm's own, and wild
## predators with a separate small allowance. The Nights setting (calm, normal, fierce) sets how many
## monsters may be about at once and how hard they hit.

var spawn_t: float = 1.0
var monster_cd: float = 0.0
## why recent spawn attempts failed (shown in the debug panel)
var spawn_log := {}
var enabled: bool = true
## time until pirates may next row ashore (they come every five to ten minutes near a coast)
var pirate_t: float = 300.0


func danger() -> int:
	return clampi(int(Game.setting("night_danger", 1)), 0, 2)


func monster_cap(place: String) -> int:
	var d: int = danger()
	if place == "surface":
		return [3, 6, 10][d]
	return [6, 9, 12][d]


func monster_damage_scale() -> float:
	return [0.75, 1.0, 1.25][danger()]


func _note(reason: String) -> void:
	spawn_log[reason] = int(spawn_log.get(reason, 0)) + 1


func update_spawning(lv: Level, delta: float) -> void:
	if not enabled or lv.player.dead:
		return
	if monster_cd > 0.0:
		monster_cd -= delta
	pirate_t -= delta
	if pirate_t <= 0.0:
		pirate_t = randf_range(300.0, 600.0)
		if lv.dim == WorldGen.DIM_OVERWORLD and not bool(Game.setting("peaceful", false)):
			_pirate_landing(lv)
	spawn_t -= delta
	if spawn_t > 0.0:
		return
	spawn_t = randf_range(0.45, 1.0)
	var peaceful: bool = bool(Game.setting("peaceful", false))
	if peaceful:
		# monsters fade away in peaceful mode (bosses, pets and anything angry at you stay)
		for m in lv.mobs.duplicate():
			var pm: Mob = m
			if pm.is_hostile() and not pm.tame and pm.boss_key == "" and not pm.persistent:
				lv.remove_mob(pm)
	var passive: int = 0
	var hostile: int = 0
	var predators: int = 0
	var fish: int = 0
	var px: float = lv.player.global_position.x
	for m in lv.mobs:
		var mm: Mob = m
		if mm.hp <= 0.0 or mm.tame or mm.persistent or mm.boss_key != "":
			continue
		if absf(mm.global_position.x - px) > 800.0:
			continue
		if mm.key == "fish":
			fish += 1
		elif mm.is_hostile():
			if bool(mm.def["predator"]):
				predators += 1
			else:
				hostile += 1
		else:
			passive += 1
	var w: WorldData = lv.world
	var pcx: int = floori(px / 8.0)
	var pcy: int = floori(lv.player.global_position.y / 8.0)
	if lv.dim == WorldGen.DIM_UMBRAL:
		if hostile < monster_cap("cave") and not peaceful:
			_spawn_in_cave(lv, ["imp", "imp", "emberSlime", "cinderBat"], pcx, pcy)
		return
	var surf: int = w.surface(pcx)
	var underground: bool = pcy > surf + 14
	if underground:
		if hostile < monster_cap("cave") and not peaceful:
			var kinds: Array
			if pcy < 200:
				kinds = ["bat", "slime", "zombie", "bat"]
			elif pcy < 330:
				kinds = ["skeleton", "crawler", "bat", "slime", "archer"]
			elif pcy < 450:
				kinds = ["golem", "skeleton", "crawler", "wraith", "archer"]
			else:
				kinds = ["wraith", "golem", "crawler", "skeleton"]
			if randf() < 0.03:
				kinds = ["mimic"]
			_spawn_in_cave(lv, kinds, pcx, pcy)
		return
	var night: bool = lv.is_night()
	var biome: int = lv.gen.biome_at(pcx)
	if night and hostile < monster_cap("surface") and monster_cd <= 0.0 and not peaceful:
		var kinds2: Array = ["zombie", "zombie", "zombie", "skeleton", "slime", "archer"]
		if biome == WorldGen.DESERT:
			kinds2 = ["zombie", "scorpion", "skeleton", "zombie"]
		elif biome == WorldGen.SWAMP:
			kinds2 = ["zombie", "slime", "slime", "zombie"]
		var m: Mob = _spawn_on_surface(lv, kinds2[randi() % kinds2.size()], pcx, true)
		if m != null:
			m.hunter = true
			monster_cd = [8.0, 4.0, 2.0][danger()] * randf_range(0.8, 1.25)
		return
	if not night and passive < 10 and randf() < 0.5:
		var animals: Array = _animals_for(biome)
		if not animals.is_empty():
			_spawn_on_surface(lv, animals[randi() % animals.size()], pcx, false)
			return
	if predators < 2 and randf() < 0.08 and not peaceful:
		var pred: String = ""
		match biome:
			WorldGen.TUNDRA:
				pred = "polarBear"
			WorldGen.MOUNTAIN:
				pred = "grizzly"
			WorldGen.SAVANNA, WorldGen.JUNGLE:
				pred = "tiger"
			WorldGen.DESERT:
				pred = "scorpion"
			WorldGen.FOREST:
				pred = "wolf" if randf() < 0.6 else "bear"
		if pred != "":
			_spawn_on_surface(lv, pred, pcx, false)
			return
	if fish < 6 and randf() < 0.3:
		_spawn_fish(lv, pcx, pcy)


## Pirates row ashore: a crew lands on the nearest beach (if the sea is close) and comes for the
## player; their captain carries the ship's treasure
func _pirate_landing(lv: Level) -> void:
	var g: WorldGen = lv.gen
	var pcx: int = floori(lv.player.global_position.x / 8.0)
	if lv.player.global_position.y / 8.0 > float(g.surface_at(pcx) + 14):
		return
	for side in [-1, 1]:
		var k: int = 30
		while k <= 100:
			var x: int = pcx + int(side) * k
			if g.biome_at(x) == WorldGen.OCEAN and g.biome_at(x - int(side) * 3) != WorldGen.OCEAN:
				var bx: int = x - int(side) * 4
				if not lv.world.is_loaded_x(bx) or not lv.world.is_loaded_x(bx - int(side) * 3):
					return
				var crew: Array = ["pirate", "pirateGunner", "pirate"]
				if randf() < 0.45:
					crew.append("pirateCaptain")
				var n: int = 0
				for i in range(crew.size()):
					var cx: int = bx - int(side) * i
					var top: int = lv.world.sky_top(cx)
					if DB.liquid[lv.world.get_tile(cx, top)] == 1 or not spot_clear(lv.world, String(crew[i]), cx, top):
						continue
					var m: Mob = lv.spawn_mob(String(crew[i]), Vector2(cx * 8 + 4, top * 8))
					m.hunter = true
					m.angry = true
					n += 1
				if n > 0:
					Sfx.play("warn", 0.8)
					lv.say("Pirates are rowing ashore to the %s!" % ("east" if int(side) > 0 else "west"), 4.0)
				return
			k += 5


func _animals_for(biome: int) -> Array:
	match biome:
		WorldGen.PLAINS:
			return ["pig", "cow", "sheep", "chicken", "crow"]
		WorldGen.FOREST:
			return ["pig", "sheep", "chicken", "cat", "crow"]
		WorldGen.SAVANNA:
			return ["giraffe", "elephant", "chicken"]
		WorldGen.JUNGLE:
			return ["frog", "chicken", "crow"]
		WorldGen.SWAMP:
			return ["frog", "frog", "pig"]
		WorldGen.TUNDRA:
			return ["sheep", "wolf"]
		WorldGen.MOUNTAIN:
			return ["sheep", "crow"]
		WorldGen.DESERT:
			return ["chicken"]
	return []


## A torch, lantern, campfire or other strong light within 7 blocks keeps monsters away
func lit_spot(w: WorldData, x: int, y: int) -> bool:
	for ty in range(y - 7, y + 3):
		for tx in range(x - 7, x + 8):
			if DB.light[w.get_tile(tx, ty)] >= 9:
				return true
	return false


## Room for a creature of this size at (x, y) feet: nothing solid in its box, and footing under it
func spot_clear(w: WorldData, key: String, x: int, y: int) -> bool:
	var d: Dictionary = DB.mob(key)
	var wt: int = maxi(1, ceili(float(d["w"])))
	var ht: int = maxi(1, ceili(float(d["h"])))
	for dx in range(-(wt / 2), wt - wt / 2):
		for dy in range(1, ht + 1):
			var t: int = w.get_tile(x + dx, y - dy)
			if DB.solid[t] == 1 or DB.liquid[t] == 1:
				return false
	if bool(d["flying"]):
		return true
	return DB.solid[w.get_tile(x, y)] == 1 or w.get_tile(x, y) == T.PLATFORM


func _offscreen_x(lv: Level, pcx: int) -> int:
	var half: int = int(lv.view_rect().size.x / 2)
	var side: int = 1 if randf() < 0.5 else -1
	return pcx + side * randi_range(half + 4, half + 24)


func _spawn_on_surface(lv: Level, key: String, pcx: int, monster: bool) -> Mob:
	var w: WorldData = lv.world
	var x: int = _offscreen_x(lv, pcx)
	if not w.is_loaded_x(x):
		_note("not loaded")
		return null
	var top: int = w.sky_top(x)
	if top <= 2 or top >= w.h - 2:
		_note("no ground")
		return null
	var t: int = w.get_tile(x, top)
	if DB.liquid[t] == 1:
		_note("water")
		return null
	if bool(DB.mob(key)["flying"]):
		top -= 6
	if monster and lit_spot(w, x, top - 1):
		_note("lit")
		return null
	if not monster and not bool(DB.mob(key)["flying"]):
		if not (t == T.GRASS or t == T.SNOW or t == T.SAND or t == T.DRY_GRASS or t == T.JUNGLE_GRASS or t == T.MOSS_GRASS):
			_note("not grass")
			return null
	if not spot_clear(w, key, x, top):
		_note("blocked")
		return null
	_note("ok")
	return lv.spawn_mob(key, Vector2(x * 8 + 4, top * 8))


func _spawn_in_cave(lv: Level, kinds: Array, pcx: int, pcy: int) -> void:
	var w: WorldData = lv.world
	var key: String = kinds[randi() % kinds.size()]
	var flying: bool = bool(DB.mob(key)["flying"])
	for attempt in range(6):
		var ang: float = randf() * TAU
		var r: float = randf_range(20.0, 40.0)
		var x: int = pcx + int(cos(ang) * r)
		var y: int = pcy + int(sin(ang) * r * 0.6)
		if not w.is_loaded_x(x) or y < 4 or y >= w.h - 4:
			continue
		if w.get_tile(x, y - 1) != T.AIR:
			continue
		if not flying:
			# settle onto the floor below
			var k: int = 0
			while k < 12 and w.get_tile(x, y) == T.AIR:
				y += 1
				k += 1
			if DB.solid[w.get_tile(x, y)] != 1:
				continue
		if lv.dim == WorldGen.DIM_OVERWORLD and y < w.sky_top(x):
			continue
		if lit_spot(w, x, y - 1):
			_note("lit")
			continue
		if not spot_clear(w, key, x, y):
			continue
		var m: Mob = lv.spawn_mob(key, Vector2(x * 8 + 4, y * 8))
		if key == "mimic":
			m.persistent = false
		_note("ok")
		return
	_note("no cave spot")


func _spawn_fish(lv: Level, pcx: int, pcy: int) -> void:
	var w: WorldData = lv.world
	for attempt in range(4):
		var x: int = pcx + randi_range(-30, 30)
		var y: int = pcy + randi_range(-10, 16)
		if w.get_tile(x, y) == T.WATER and w.get_tile(x, y - 1) == T.WATER and w.get_tile(x, y + 1) == T.WATER:
			lv.spawn_mob("fish", Vector2(x * 8 + 4, y * 8 + 6))
			return
