class_name Level
extends Node2D
## A world being played: it creates or loads the world, streams chunks around the player, keeps the
## tile view, light, camera, sky and weather in step, owns the creatures, drops and projectiles, and
## is what every other part calls to change the world (breaking and placing blocks, doors, drops,
## explosions, the rift), to show things (messages, floating numbers, shake) and to open panels.

const PlayerScene = preload("res://scenes/player.tscn")
const MobScene = preload("res://scenes/mob.tscn")
const DropScene = preload("res://scenes/drop.tscn")
const ProjectileScene = preload("res://scenes/projectile.tscn")
const VehicleScene = preload("res://scenes/vehicle.tscn")

const DAY_LENGTH := 720.0

@onready var view: WorldView = $View
@onready var entities: Node2D = $Entities
@onready var projectiles_node: Node2D = $Projectiles
@onready var effects: Effects = $Effects
@onready var lighting: Lighting = $Light
@onready var camera: Camera2D = $Camera
@onready var hud: Hud = $HUD
@onready var ui_layer: CanvasLayer = $UI
@onready var sky: SkyView = $SkyLayer/Sky
@onready var weather: Weather = $Weather
@onready var weather_fx: WeatherFX = $WeatherFX
@onready var spawner: Spawner = $Spawner

var input := InputState.new()
var gen: WorldGen = null
var worlds := {}
var world: WorldData = null
var dim: int = 0
var player: Player = null
var mobs: Array = []
var vehicles: Array = []
var mode: String = "survival"
var world_name: String = "My World"
var slot: int = 0
var seed_value: int = 1
var infinite: bool = true
var options := {}
var time_of_day: float = 0.25
var day_count: int = 1
var play_seconds: float = 0.0
var hud_dirty: bool = true
var defeated := {}
var journal := Journal.new()
var portal_opened: bool = false
var spawn_point := Vector2.ZERO
var shake: float = 0.0
var hit_stop_t: float = 0.0
var autosave_t: float = 0.0
var hardcore_over: bool = false
var panel: Control = null
var panel_name: String = ""
var portal_t: float = 0.0
var portal_cool: float = 0.0
var portal_needs_exit: bool = false
var fade: float = 0.0
var discover_t: float = 0.0
var tick_t: float = 0.0
var boss: Mob = null
var free_time: bool = false
var show_hitboxes: bool = false
var _stream_cx: int = -2147483648


func _ready() -> void:
	Game.level = self
	var pending: Dictionary = Game.pending
	Game.pending = {}
	if pending.has("load") and SaveSystem.exists(int(pending["load"])):
		slot = int(pending["load"])
		var data: Dictionary = SaveSystem.read(slot)
		_setup_world(data.get("meta", {}))
		SaveSystem.apply(self, data)
	else:
		var params: Dictionary = pending.get("new", {})
		slot = int(params.get("slot", Game.first_free_slot()))
		_setup_world(params)
		_place_at_spawn()
		_starter_kit()
		say("Welcome to %s. Tap BAG to see what you have; build a workbench to start crafting." % world_name, 6.0)
	on_settings_changed()
	hud.attach(self)
	_snap_camera()
	hud_dirty = true


# ---------------------------------------------------------------------------------------------- setting up

func _setup_world(params: Dictionary) -> void:
	world_name = String(params.get("name", "My World"))
	mode = String(params.get("mode", "survival"))
	infinite = bool(params.get("infinite", true))
	var s = params.get("seed", null)
	if s == null or String(s) == "":
		seed_value = randi() % 2000000000 + 1
	elif String(s).is_valid_int():
		seed_value = int(String(s))
	else:
		seed_value = absi(String(s).hash()) + 1
	options = {"flat": bool(params.get("flat", false)), "trees": bool(params.get("trees", true)),
		"structures": bool(params.get("structures", true)), "caves": bool(params.get("caves", false)),
		"ponds": bool(params.get("ponds", false))}
	gen = WorldGen.new(seed_value, infinite, options)
	worlds.clear()
	_switch_world(WorldGen.DIM_OVERWORLD)
	player = PlayerScene.instantiate()
	player.level = self
	player.hair = int(Game.setting("hair", 0))
	player.scarf = int(Game.setting("scarf", 0))
	entities.add_child(player)
	player.actions.level = self


func _world_for(d: int) -> WorldData:
	if not worlds.has(d):
		var w := WorldData.new(gen, d)
		w.threaded = bool(Game.setting("threaded_gen", true))
		worlds[d] = w
	return worlds[d]


func _switch_world(d: int) -> void:
	dim = d
	world = _world_for(d)
	view.attach(world)
	_stream_cx = -2147483648


## A dry spot near the world's spawn column
func _place_at_spawn() -> void:
	var x: int = gen.spawn_x
	for attempt in range(80):
		var c: Array = gen.col(x)
		if int(c[1]) != WorldGen.OCEAN and int(c[0]) < WorldGen.SEA:
			break
		x += 7
	_load_around(x, 2)
	var y: int = _surface_row(x)
	spawn_point = Vector2(x * 8 + 4, y * 8)
	player.global_position = spawn_point


## The first row from the top in column x that can be stood on
func _surface_row(x: int) -> int:
	world.ensure(x >> 4)
	for y in range(2, world.h - 2):
		var t: int = world.get_tile(x, y)
		if (DB.solid[t] == 1 or DB.liquid[t] == 1) and world.get_tile(x, y - 1) == T.AIR and world.get_tile(x, y - 2) == T.AIR:
			return y
	return WorldGen.SEA


func _starter_kit() -> void:
	if mode == "creative":
		player.inv.add("tool:pickaxe:diamond", 1)
		player.inv.add("sword:diamond", 1)
		player.inv.add("block:torch", 99)
		player.inv.add("block:planks", 99)
		return
	player.inv.add("tool:pickaxe:wood", 1)
	player.inv.add("tool:axe:wood", 1)
	player.inv.add("sword:wood", 1)
	player.inv.add("block:torch", 8)
	player.inv.add("food:bread", 3)


func _load_around(x: int, radius: int) -> void:
	var cx: int = x >> 4
	for c in range(cx - radius, cx + radius + 1):
		world.ensure(c)


# ---------------------------------------------------------------------------------------------- the frame

func _process(delta: float) -> void:
	if player == null:
		return
	world.poll()
	_stream()
	var vr: Rect2i = view_rect()
	view.follow(vr)
	var dyn: Array = []
	var lamp: int = held_light()
	if lamp > 0 and not player.dead:
		dyn.append([player.feet_cell() + Vector2i(0, -1), lamp])
	for p in projectiles_node.get_children():
		if p is Projectile and (p as Projectile).glow > 0:
			dyn.append([Vector2i(floori(p.global_position.x / 8.0), floori(p.global_position.y / 8.0)), (p as Projectile).glow])
	for f in effects.flash_lights():
		dyn.append(f)
	lighting.dynamic = dyn
	lighting.update_light(world, vr, sky_level(), delta, not dyn.is_empty())
	_update_camera(delta)
	sky.update_sky(self, delta)
	if hud_dirty:
		hud_dirty = false
		hud.refresh()
	hud.tick(delta)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	if hit_stop_t > 0.0:
		hit_stop_t -= delta
	if not free_time and dim == WorldGen.DIM_OVERWORLD:
		time_of_day += delta / DAY_LENGTH
		if time_of_day >= 1.0:
			time_of_day -= 1.0
			day_count += 1
			hud_dirty = true
	play_seconds += delta
	weather.update_weather(self, delta)
	spawner.update_spawning(self, delta)
	_world_ticks(delta)
	_update_portal(delta)
	_update_discoveries(delta)
	_update_bosses()
	player.actions.recharge_rods(delta)
	if player.dead:
		return
	autosave_t += delta
	if autosave_t >= 60.0 and bool(Game.setting("autosave", true)):
		autosave_t = 0.0
		save_game()
		float_text("Saved", player.global_position + Vector2(0, -24), Color(0.6, 1.0, 0.6))


func view_rect() -> Rect2i:
	var vs: Vector2 = get_viewport_rect().size / camera.zoom
	var c: Vector2 = camera.get_screen_center_position()
	var tl: Vector2 = c - vs * 0.5
	return Rect2i(floori(tl.x / 8.0), floori(tl.y / 8.0), ceili(vs.x / 8.0) + 2, ceili(vs.y / 8.0) + 2)


func _stream() -> void:
	var pcx: int = floori(player.global_position.x / 8.0) >> 4
	var vs: Vector2 = get_viewport_rect().size / camera.zoom
	var radius: int = ceili(vs.x / 8.0 * 0.5 / 16.0) + 3
	if pcx == _stream_cx and world.pending_count() == 0:
		return
	# nearest chunks first
	for k in range(radius + 1):
		world.request(pcx + k)
		if k > 0:
			world.request(pcx - k)
	if pcx != _stream_cx:
		_stream_cx = pcx
		world.unload_far(pcx, radius + 4)


func _update_camera(delta: float) -> void:
	var target: Vector2 = player.global_position + Vector2(0, -12.8)
	if player.riding != null:
		target = (player.riding as Node2D).global_position + Vector2(0, -12.8)
	var k: float = 1.0 - exp(-delta * 8.0)
	if camera.global_position.distance_to(target) > 320.0:
		k = 1.0
	camera.global_position = camera.global_position.lerp(target, k)
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 1.5)
		var s: float = shake * 2.4 * float(Game.setting("shake", 1.0))
		camera.offset = Vector2(randf_range(-s, s), randf_range(-s, s))
	else:
		camera.offset = Vector2.ZERO


func _snap_camera() -> void:
	camera.global_position = player.global_position + Vector2(0, -12.8)
	camera.reset_smoothing()


func on_settings_changed() -> void:
	var z: float = clampf(float(Game.setting("zoom", 4.0)), 2.0, 7.0)
	camera.zoom = Vector2(z, z)
	lighting.set_smooth(bool(Game.setting("smooth_light", true)))
	for w in worlds.values():
		(w as WorldData).threaded = bool(Game.setting("threaded_gen", true))
	if player != null:
		player.hair = int(Game.setting("hair", 0))
		player.scarf = int(Game.setting("scarf", 0))
		player.refresh_look()
	if hud != null:
		hud.layout_controls()


# ---------------------------------------------------------------------------------------------- time & light

func day_factor() -> float:
	if dim != WorldGen.DIM_OVERWORLD:
		return 0.0
	var t: float = time_of_day
	if t < 0.50:
		return 1.0
	if t < 0.58:
		return 1.0 - PRNG.smooth((t - 0.50) / 0.08)
	if t < 0.92:
		return 0.0
	return PRNG.smooth((t - 0.92) / 0.08)


func is_night() -> bool:
	return day_factor() < 0.35


func sky_level() -> int:
	if dim != WorldGen.DIM_OVERWORLD:
		return 0
	var dark: float = weather.darkness()
	return roundi((6.0 + 9.0 * day_factor()) * (1.0 - 0.35 * dark))


## The light the held or worn item gives off around the player
func held_light() -> int:
	var lv: int = 0
	var id: String = player.actions.held_id()
	if id == "block:torch":
		lv = 12
	elif id == "block:lantern":
		lv = 13
	elif id == "block:glowCrystal":
		lv = 10
	if player.inv.wearing("gear:headlamp"):
		lv = maxi(lv, 11)
	return lv


# ---------------------------------------------------------------------------------------------- weather on the player

func weather_walk_scale() -> float:
	return weather.walk_scale(self)


func weather_push(on_floor: bool) -> float:
	return weather.wind_push(self, on_floor)


func slipperiness(p: Player) -> float:
	if p.inv.wearing("gear:snowBoots"):
		return 0.0
	var below: int = world.get_tile(floori(p.global_position.x / 8.0), floori((p.global_position.y + 1.0) / 8.0))
	if below == T.ICE:
		return 0.85
	return weather.slip(self)


# ---------------------------------------------------------------------------------------------- the world

## Rules for what a tile needing support may stand on
func supports(below: int, t: int) -> bool:
	if t == T.WHEAT1 or t == T.WHEAT2 or t == T.WHEAT3 or t == T.CARROT1 or t == T.CARROT2 or t == T.CARROT3:
		return below == T.FARMLAND
	if t == T.DOOR_CLOSED or t == T.DOOR_OPEN:
		return DB.solid[below] == 1 or below == T.DOOR_CLOSED or below == T.DOOR_OPEN
	return DB.supports[below] == 1 or below == T.PLATFORM


func place_tile(x: int, y: int, t: int) -> void:
	world.set_tile(x, y, t)
	if t == T.CHEST:
		world.chests[Vector2i(x, y)] = []
		(world.chests[Vector2i(x, y)] as Array).resize(WorldData.CHEST_SLOTS)


func place_door(cell: Vector2i) -> bool:
	var top: int = cell.y - 1
	var w: WorldData = world
	if w.get_tile(cell.x, cell.y) != T.AIR or w.get_tile(cell.x, top) != T.AIR:
		return false
	if not supports(w.get_tile(cell.x, cell.y + 1), T.DOOR_CLOSED):
		return false
	if not player.actions.in_reach(Vector2(cell.x * 8 + 4, cell.y * 8 + 4)):
		return false
	w.set_tile(cell.x, cell.y, T.DOOR_CLOSED)
	w.set_tile(cell.x, top, T.DOOR_CLOSED)
	Sfx.play("door", 0.6)
	return true


func toggle_door(x: int, y: int) -> void:
	var t: int = world.get_tile(x, y)
	if t != T.DOOR_CLOSED and t != T.DOOR_OPEN:
		return
	var to: int = T.DOOR_OPEN if t == T.DOOR_CLOSED else T.DOOR_CLOSED
	# the whole door: this block and the door blocks above and below it
	var y0: int = y
	while world.get_tile(x, y0 - 1) == t:
		y0 -= 1
	var y1: int = y
	while world.get_tile(x, y1 + 1) == t:
		y1 += 1
	if to == T.DOOR_CLOSED:
		var r := Rect2(x * 8, y0 * 8, 8, (y1 - y0 + 1) * 8)
		if r.intersects(player.body_rect()):
			return
	for yy in range(y0, y1 + 1):
		world.set_tile(x, yy, to)
	Sfx.play("door", 0.6)


## What a tile drops when broken: [[item id, count], ...]
func tile_drops(t: int, x: int, y: int) -> Array:
	var out: Array = []
	var r: float = randf()
	match t:
		T.TALL_GRASS:
			if r < 0.14:
				out.append(["mat:seeds", 1])
		T.LEAVES, T.JUNGLE_LEAVES:
			if r < 0.05:
				out.append(["food:apple", 1])
		T.WHEAT3:
			out.append(["food:wheat", 1 + randi() % 2])
			out.append(["mat:seeds", 1 + randi() % 3])
		T.WHEAT1, T.WHEAT2:
			out.append(["mat:seeds", 1])
		T.CARROT3:
			out.append(["food:carrot", 1 + randi() % 3])
		T.CARROT1, T.CARROT2:
			out.append(["food:carrot", 1])
		T.COBWEB:
			out.append(["mat:string", 1])
		T.SALTPETER:
			out.append(["mat:saltpeter", 1 + (1 if r < 0.35 else 0)])
		T.AMETHYST:
			out.append(["mat:amethyst", 1 + (1 if r < 0.5 else 0)])
		T.ORE_CART:
			var rng := SplitRNG.new(PRNG.hash_u(x, y, gen.world_seed + 911))
			out.append([["mat:coal", "mat:copperOre", "mat:ironOre", "mat:tinOre"][rng.below(4)], 2 + rng.below(4)])
		T.CHEST:
			for s in world.take_chest(x, y):
				out.append([String(s["id"]), int(s["n"]), int(s.get("x", 0))])
			out.append(["block:chest", 1])
		_:
			var d: String = String(DB.drop_of[t])
			if d != "":
				out.append([d, 1])
	return out


## Breaks a block: particles, drops, and anything resting on it comes down too
func break_tile(x: int, y: int, by_player: bool, drop_chance: float = 1.0) -> void:
	var t: int = world.get_tile(x, y)
	if t == T.AIR or DB.hardness[t] >= 9999.0:
		return
	if t == T.DOOR_CLOSED or t == T.DOOR_OPEN:
		for dy in [-1, 1]:
			var o: int = world.get_tile(x, y + int(dy))
			if o == T.DOOR_CLOSED or o == T.DOOR_OPEN:
				world.set_tile(x, y + int(dy), T.AIR)
	var drops: Array = tile_drops(t, x, y)
	world.set_tile(x, y, T.AIR)
	effects.burst(Vector2(x * 8 + 4, y * 8 + 4), Color.hex((int(DB.tiles[t]["color"]) << 8) | 0xFF), 6, 28.0, 0.5)
	if not (by_player and player.is_creative()):
		for d in drops:
			if drop_chance < 1.0 and randf() > drop_chance:
				continue
			spawn_drop(String(d[0]), int(d[1]), Vector2(x * 8 + 4, y * 8 + 3), Vector2(randf_range(-12.0, 12.0), -24.0), int(d[2]) if d.size() > 2 else 0)
	# what rested on it
	var above: int = world.get_tile(x, y - 1)
	if DB.needs_support[above] == 1 and not supports(world.get_tile(x, y), above):
		break_tile(x, y - 1, by_player)
	if t == T.FARMLAND and above >= T.WHEAT1 and above <= T.CARROT3:
		break_tile(x, y - 1, by_player)
	if world.get_tile(x, y - 1) == T.SAND:
		_drop_sand(x, y - 1)
	if DB.trunk[t] == 1:
		_queue_leaf_decay(x, y)
	hud_dirty = true


## Sand with nothing under it falls straight down to the first thing it lands on
func _drop_sand(x: int, y: int) -> void:
	var yy: int = y
	while world.get_tile(x, yy) == T.SAND and yy > 1:
		var land: int = yy
		while land + 1 < world.h - 1 and world.get_tile(x, land + 1) == T.AIR:
			land += 1
		if land == yy:
			break
		world.set_tile(x, yy, T.AIR)
		world.set_tile(x, land, T.SAND)
		yy -= 1


## Chopping a trunk with an axe brings the whole tree down
func fell_tree(x: int, y: int) -> void:
	var top: int = y
	var count: int = 0
	var cy: int = y
	while DB.trunk[world.get_tile(x, cy)] == 1 and count < 40:
		top = cy
		cy -= 1
		count += 1
	var yy: int = y
	while yy >= top and DB.trunk[world.get_tile(x, yy)] == 1:
		break_tile(x, yy, true)
		yy -= 1
	for dy in range(-7, 4):
		for dx in range(-6, 7):
			var lt: int = world.get_tile(x + dx, top + dy)
			if DB.leaf[lt] == 1 and absi(dx) + absi(dy + 1) <= 8:
				break_tile(x + dx, top + dy, true)


var _decay_zones: Array = []


func _queue_leaf_decay(x: int, y: int) -> void:
	if _decay_zones.size() < 24:
		_decay_zones.append([x, y, 30.0])


## Leaves with no trunk near them wither away a little at a time
func _leaf_decay(delta: float) -> void:
	for z in _decay_zones:
		z[2] = float(z[2]) - delta
		var x: int = int(z[0]) + randi_range(-5, 5)
		var y: int = int(z[1]) + randi_range(-10, 2)
		if DB.leaf[world.get_tile(x, y)] == 1 and not _trunk_near(x, y):
			break_tile(x, y, false, 0.3)
	_decay_zones = _decay_zones.filter(func(z: Array) -> bool: return float(z[2]) > 0.0)


func _trunk_near(x: int, y: int) -> bool:
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			if DB.trunk[world.get_tile(x + dx, y + dy)] == 1:
				return true
	return false


func _world_ticks(delta: float) -> void:
	tick_t -= delta
	if tick_t > 0.0:
		return
	tick_t = 0.1
	var px: int = floori(player.global_position.x / 8.0)
	var py: int = floori(player.global_position.y / 8.0)
	var rain: float = weather.rain_here(self)
	for i in range(7):
		var x: int = px + randi_range(-40, 40)
		var y: int = py + randi_range(-26, 26)
		var t: int = world.get_tile(x, y)
		var grow: float = 0.035 + 0.03 * rain
		match t:
			T.WHEAT1:
				if randf() < grow:
					world.set_tile(x, y, T.WHEAT2)
			T.WHEAT2:
				if randf() < grow:
					world.set_tile(x, y, T.WHEAT3)
			T.CARROT1:
				if randf() < grow:
					world.set_tile(x, y, T.CARROT2)
			T.CARROT2:
				if randf() < grow:
					world.set_tile(x, y, T.CARROT3)
			T.DIRT:
				if dim == WorldGen.DIM_OVERWORLD and y < world.sky_top(x) + 1 and world.get_tile(x, y - 1) == T.AIR:
					if world.get_tile(x - 1, y) == T.GRASS or world.get_tile(x + 1, y) == T.GRASS:
						if randf() < 0.02:
							world.set_tile(x, y, T.GRASS)
			T.GRASS:
				if DB.opaque[world.get_tile(x, y - 1)] == 1 and randf() < 0.03:
					world.set_tile(x, y, T.DIRT)
	_leaf_decay(delta + 0.1)


func water_crop(cell: Vector2i) -> void:
	var t: int = world.get_tile(cell.x, cell.y)
	if t == T.WHEAT1 or t == T.WHEAT2 or t == T.CARROT1 or t == T.CARROT2:
		world.set_tile(cell.x, cell.y, t + 1)
		player.inv.remove_at(player.actions.sel, 1)
		effects.burst(Vector2(cell.x * 8 + 4, cell.y * 8 + 4), Color(0.5, 0.7, 1.0), 6, 20.0, 0.4)
		Sfx.play("splash", 0.6)
	else:
		say("Pour it on a young crop.", 1.4)


func collect_rainwater(cell: Vector2i) -> void:
	if player.inv.total("gadget:waterFlask") >= 10:
		say("Your flasks are full.", 1.2)
		return
	if weather.rain_here(self) > 0.1 or randf() < 0.5:
		player.inv.add("gadget:waterFlask", 1)
		say("You fill a flask with rainwater.", 1.5)
		Sfx.play("splash", 0.5)
	else:
		say("The barrel is dry. Wait for rain.", 1.5)


## Levers and switches flip the lamps, gates and shutters wired beside them (a short reach)
func toggle_power(cell: Vector2i) -> void:
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var x: int = cell.x + dx
			var y: int = cell.y + dy
			match world.get_tile(x, y):
				T.LAMP_OFF:
					world.set_tile(x, y, T.LAMP_ON)
				T.LAMP_ON:
					world.set_tile(x, y, T.LAMP_OFF)
				T.GATE_CLOSED:
					world.set_tile(x, y, T.GATE_OPEN)
				T.GATE_OPEN:
					world.set_tile(x, y, T.GATE_CLOSED)


## A clear line of sight between two points (no solid block on the way)
func line_clear(a: Vector2, b: Vector2) -> bool:
	var d: Vector2 = b - a
	var n: int = maxi(1, ceili(d.length() / 3.2))
	for i in range(1, n):
		var p: Vector2 = a + d * (float(i) / float(n))
		if world.solid(floori(p.x / 8.0), floori(p.y / 8.0)):
			return false
	return true


# ---------------------------------------------------------------------------------------------- creatures

func mobs_near(x0: float, x1: float) -> Array:
	var out: Array = []
	for m in mobs:
		var mm: Mob = m
		var x: float = mm.global_position.x
		if x >= x0 and x <= x1:
			out.append(mm)
	return out


func mob_at(p: Vector2) -> Mob:
	for m in mobs_near(p.x - 40.0, p.x + 40.0):
		var mm: Mob = m
		if mm.hp > 0.0 and mm.hit_rect().grow(1.6).has_point(p):
			return mm
	return null


func hostile_at(p: Vector2) -> bool:
	var m: Mob = mob_at(p)
	return m != null and (m.is_hostile() or m.angry) and not m.tame


func spawn_mob(key: String, pos: Vector2, variant: int = -1) -> Mob:
	var m: Mob = MobScene.instantiate()
	m.setup(self, key, variant)
	entities.add_child(m)
	m.global_position = pos
	mobs.append(m)
	return m


func remove_mob(m: Mob) -> void:
	mobs.erase(m)
	if m == boss:
		boss = null
		hud_dirty = true
	m.queue_free()


func interact_mob(m: Mob, held: String, held_sel: int) -> void:
	if m.tame and (m.key == "wolf" or m.key == "cat"):
		m.stay = not m.stay
		say("Your pet will stay here." if m.stay else "Your pet follows you.", 2.0)
		return
	if m.key == "rex" and m.tame:
		mount(m)
		return
	# taming: a bone for a wolf, fish for a cat
	var ok: bool = (m.key == "wolf" and held == "mat:bone") or (m.key == "cat" and (held == "food:rawFish" or held == "food:cookedFish"))
	if not ok:
		return
	if not player.is_creative():
		player.inv.remove_at(held_sel, 1)
	if randf() < 0.6:
		m.tame = true
		m.persistent = true
		m.angry = false
		m.hp = m.max_hp
		m.refresh_frames()
		say("You tamed the %s!" % m.display_name().to_lower(), 3.0)
		effects.burst(m.center(), Color(1.0, 0.4, 0.5), 10, 24.0, 0.8)
	else:
		say("The %s isn't convinced yet..." % m.display_name().to_lower(), 2.0)


func mount(m: Mob) -> void:
	player.riding = m
	m.ridden = true
	player.visible = false
	say("Riding Tyrannax. Walk with the stick, JUMP to leap, tap the rex button to get off.", 3.5)
	hud_dirty = true


func dismount() -> void:
	if player.riding == null:
		return
	var r: Node2D = player.riding
	if r is Mob:
		(r as Mob).ridden = false
	elif r is Vehicle:
		(r as Vehicle).rider = false
	player.riding = null
	player.visible = true
	player.global_position = r.global_position + Vector2(0, -4)
	player.velocity = Vector2(0, -40)
	hud_dirty = true


# ---------------------------------------------------------------------------------------------- items in the world

func spawn_drop(id: String, n: int, pos: Vector2, vel: Vector2 = Vector2.ZERO, extra: int = 0) -> void:
	if n <= 0 or id == "":
		return
	var d: Drop = DropScene.instantiate()
	d.setup(self, id, n, extra)
	entities.add_child(d)
	d.global_position = pos
	d.vel = vel if vel != Vector2.ZERO else Vector2(randf_range(-10.0, 10.0), -20.0)


func spawn_projectile(p: Dictionary) -> Projectile:
	var pr: Projectile = ProjectileScene.instantiate()
	pr.setup(self, p)
	projectiles_node.add_child(pr)
	return pr


## A blast: it hurts everything in reach (less at the edge, nothing behind walls) and breaks blocks
func explode(pos: Vector2, radius: float, power: float, by_player: bool, break_blocks: bool) -> void:
	Sfx.play("explosion", 1.0)
	var r_px: float = radius * 8.0
	for m in mobs_near(pos.x - r_px - 32.0, pos.x + r_px + 32.0):
		var mm: Mob = m
		var d: float = mm.box_distance(pos)
		if d > r_px or not line_clear(pos, mm.center()):
			continue
		var k: float = 1.0 - 0.65 * clampf(d / r_px, 0.0, 1.0)
		mm.take_damage({"amount": power * k, "from": pos, "knock": 11.0 * k, "by_player": by_player, "explosion": true})
	if not player.dead:
		var dp: float = player.body_rect().get_center().distance_to(pos)
		if dp <= r_px + 6.0 and line_clear(pos, player.center()):
			var k2: float = 1.0 - 0.65 * clampf(dp / r_px, 0.0, 1.0)
			player.hurt(power * (0.45 if by_player else 1.0) * k2, pos.x, 9.0)
	if break_blocks:
		var r: int = ceili(radius * 0.7)
		var tx: int = floori(pos.x / 8.0)
		var ty: int = floori(pos.y / 8.0)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if float(dx * dx + dy * dy) > radius * radius * 0.5:
					continue
				var t: int = world.get_tile(tx + dx, ty + dy)
				if t == T.AIR or DB.liquid[t] == 1 or DB.hardness[t] > 2.7 or DB.tier[t] > 4:
					continue
				if t == T.CHEST or t == T.PORTAL_OFF or t == T.PORTAL_ON or t == T.PORTAL_FRAME:
					continue
				break_tile(tx + dx, ty + dy, false, 0.35)
	effects.explosion(pos, r_px)
	add_shake(0.6)


## The quake maul's shockwave: it runs along the ground in front of the swing
func quake(origin: Vector2, dir: float, dmg: float) -> void:
	for k in range(1, 6):
		var p: Vector2 = origin + Vector2(dir * k * 8.0, -2.0)
		effects.burst(p, Color(0.9, 0.78, 0.47), 3, 20.0, 0.4)
		for m in mobs_near(p.x - 8.0, p.x + 8.0):
			var mm: Mob = m
			if mm.is_hostile() and not mm.tame and absf(mm.global_position.y - origin.y) < 16.0:
				mm.take_damage({"amount": dmg, "from": origin, "knock": 6.0, "by_player": true})
	add_shake(0.25)


## The storm rod: lightning jumps to the first foe along the aim, then on to up to three more nearby
func storm_bolt(origin: Vector2, dir: Vector2, dmg: float) -> void:
	var hit: Array = []
	var from: Vector2 = origin
	var target: Mob = null
	var best: float = 1e9
	for m in mobs_near(origin.x - 160.0, origin.x + 160.0):
		var mm: Mob = m
		if mm.hp <= 0.0 or mm.tame:
			continue
		var v: Vector2 = mm.center() - origin
		if v.length() > 150.0 or v.normalized().dot(dir) < 0.85 or not line_clear(origin, mm.center()):
			continue
		if v.length() < best:
			best = v.length()
			target = mm
	var points: Array = [origin]
	if target == null:
		points.append(origin + dir * 90.0)
	var d: float = dmg
	while target != null and hit.size() < 4:
		hit.append(target)
		points.append(target.center())
		target.take_damage({"amount": d, "from": from, "knock": 3.0, "by_player": true, "shock": true})
		from = target.center()
		d *= 0.75
		var next: Mob = null
		var nb: float = 64.0
		for m in mobs_near(from.x - 64.0, from.x + 64.0):
			var mm: Mob = m
			if mm.hp <= 0.0 or mm.tame or hit.has(mm):
				continue
			var dist: float = mm.center().distance_to(from)
			if dist < nb and line_clear(from, mm.center()):
				nb = dist
				next = mm
		target = next
	effects.lightning(points, 0.25)


func place_vehicle(kit: String, at: Vector2) -> bool:
	var cell := Vector2i(floori(at.x / 8.0), floori(at.y / 8.0))
	var kind: String = "car"
	if kit == "gadget:boatKit":
		kind = "boat"
	elif kit == "gadget:motorboatKit":
		kind = "motorboat"
	var water: bool = world.get_tile(cell.x, cell.y) == T.WATER or world.get_tile(cell.x, cell.y + 1) == T.WATER
	if kind != "car" and not water:
		say("Put a boat on the water.", 1.6)
		return false
	if kind == "car" and water:
		say("Put the car on dry ground.", 1.6)
		return false
	var v: Vehicle = VehicleScene.instantiate()
	v.setup(self, kind)
	entities.add_child(v)
	v.global_position = Vector2(at.x, cell.y * 8 + 8)
	vehicles.append(v)
	say("Tap the %s to get in." % kind, 2.0)
	return true


# ---------------------------------------------------------------------------------------------- the rift

func try_open_portal(_cell: Vector2i) -> void:
	if not player.is_creative() and player.inv.total("gadget:portalKey") < 1:
		say("The rift is sealed. It needs a Portal Key.", 3.0)
		return
	var px: int = gen.portal_x
	var py: int = gen.portal_y
	for y in range(py - 12, py + 10):
		for x in range(px - 6, px + 7):
			if world.get_tile(x, y) == T.PORTAL_OFF:
				world.set_tile(x, y, T.PORTAL_ON)
	portal_opened = true
	Sfx.play("portal", 1.0)
	say("The rift tears open. Step inside to cross into the Umbral Realm.", 4.0)
	journal.discover("portal", "The Sealed Gate", px, "portal", day_count, dim)
	hud_dirty = true


func _update_portal(delta: float) -> void:
	portal_cool = maxf(0.0, portal_cool - delta)
	fade = maxf(0.0, fade - delta * 1.4)
	if player.dead:
		portal_t = 0.0
		return
	var c: Vector2 = player.center()
	var a: int = world.get_tile(floori(c.x / 8.0), floori(c.y / 8.0))
	var b: int = world.get_tile(floori(c.x / 8.0), floori((player.global_position.y - 2.4) / 8.0))
	var inside: bool = a == T.PORTAL_ON or b == T.PORTAL_ON
	if not inside:
		portal_needs_exit = false
		portal_t = 0.0
		return
	if portal_cool > 0.0 or portal_needs_exit:
		return
	portal_t += delta
	fade = maxf(fade, minf(1.0, portal_t / 1.1))
	if randf() < 0.5:
		effects.burst(c + Vector2(randf_range(-8.0, 8.0), randf_range(-12.0, 12.0)), Color(0.5, 0.91, 0.85), 1, 16.0, 0.6)
	if portal_t >= 1.1:
		portal_t = 0.0
		travel(WorldGen.DIM_UMBRAL if dim == WorldGen.DIM_OVERWORLD else WorldGen.DIM_OVERWORLD)


func travel(to_dim: int) -> void:
	for m in mobs.duplicate():
		var mm: Mob = m
		if not mm.tame:
			remove_mob(mm)
	for p in projectiles_node.get_children():
		p.queue_free()
	for e in entities.get_children():
		if e is Drop:
			e.queue_free()
	_switch_world(to_dim)
	var arrive := Vector2.ZERO
	if to_dim == WorldGen.DIM_UMBRAL:
		var fl: int = gen.umbral_portal_floor()
		_load_around(gen.portal_x, 2)
		arrive = Vector2((gen.portal_x + 5) * 8 + 4, fl * 8)
		journal.discover("umbral", "The Umbral Realm", gen.portal_x, "umbral", day_count, dim)
	else:
		_load_around(gen.portal_x, 2)
		arrive = Vector2((gen.portal_x + 6) * 8 + 4, (gen.portal_y + 5) * 8)
	player.global_position = arrive
	player.velocity = Vector2.ZERO
	portal_cool = 2.0
	portal_needs_exit = true
	fade = 1.0
	_snap_camera()
	Sfx.play("portal", 0.9)
	say("You step through the rift." if to_dim == WorldGen.DIM_UMBRAL else "You are home.", 2.5)
	hud_dirty = true


# ---------------------------------------------------------------------------------------------- bosses & discoveries

func _update_bosses() -> void:
	if boss != null and (not is_instance_valid(boss) or boss.hp <= 0.0):
		boss = null
		hud_dirty = true
	if boss != null:
		return
	var px: int = floori(player.global_position.x / 8.0)
	if dim == WorldGen.DIM_OVERWORLD:
		for lair in gen.lair_centers(px):
			var key: String = "lair:%s:%d" % [String(lair["kind"]), int(lair["k"])]
			if defeated.has(key):
				continue
			var cx: int = int(lair["cx"])
			if absi(px - cx) < 46 and world.is_loaded_x(cx):
				var fy: int = Structures.lair_floor_row(gen)
				boss = spawn_mob("bearBoss" if lair["kind"] == "bear" else "rex", Vector2(cx * 8 + 4, fy * 8), 0)
				boss.boss_key = key
				boss.home = boss.global_position
				Sfx.play("roar", 1.0)
				say("Ursavor wakes!" if lair["kind"] == "bear" else "Tyrannax rises from the bones!", 3.0)
				hud_dirty = true
				return
		for s in Structures.grotto_sites(gen, px - 30, px + 30):
			var key2: String = "sentinel:%d" % int(s["cell"])
			if defeated.has(key2):
				continue
			if absi(px - int(s["x"])) < int(s["rx"]) and absf(player.global_position.y / 8.0 - float(s["floor"])) < 14.0:
				boss = spawn_mob("sentinel", Vector2(int(s["x"]) * 8 + 4, (int(s["floor"]) - 4) * 8), 0)
				boss.boss_key = key2
				boss.home = boss.global_position
				say("A Crystal Sentinel stirs.", 2.5)
				hud_dirty = true
				return
	else:
		var cit: Dictionary = gen.citadel()
		var key3: String = "warden"
		if not defeated.has(key3) and absi(px - int(cit["x"])) < 40 and world.is_loaded_x(int(cit["x"])):
			var tx: int = Structures.throne_x(cit)
			boss = spawn_mob("warden", Vector2(tx * 8 + 4, (int(cit["floor"]) - 2) * 8), 0)
			boss.boss_key = key3
			boss.home = boss.global_position
			Sfx.play("roar", 1.0)
			say("The Hollow Warden rises from its throne.", 3.0)
			journal.discover("citadel", "The Warden's Citadel", int(cit["x"]), "citadel", day_count, dim)
			hud_dirty = true


## A boss fell: its reward, and it does not come back
func on_boss_defeated(m: Mob) -> void:
	if m.boss_key != "":
		defeated[m.boss_key] = true
	match m.key:
		"bearBoss":
			spawn_drop("gadget:portalKey", 1, m.center())
			spawn_drop("gadget:treasureMap", 1, m.center() + Vector2(6, 0))
			say("Ursavor has fallen! It dropped a Portal Key and a Treasure Map.", 6.0)
		"rex":
			if not _has_tame_rex():
				m.tame = true
				m.persistent = true
				m.max_hp = 700.0
				m.hp = 420.0
				m.refresh_frames()
				say("Tyrannax is beaten and tamed! Tap it to ride.", 5.0)
				journal.add_lore("lair.rex")
		"sentinel":
			spawn_drop("mat:crystalShard", 4 + randi() % 4, m.center())
			say("The Crystal Sentinel shatters.", 3.0)
		"warden":
			spawn_drop("mat:umbralHeart", 1, m.center())
			spawn_drop("mat:voidBar", 4, m.center())
			say("The Hollow Warden is no more. Its heart lies in the ash.", 6.0)
	effects.burst(m.center(), Color(1.0, 0.88, 0.44), 40, 72.0, 1.2)
	add_shake(0.8)
	hud_dirty = true


func _has_tame_rex() -> bool:
	for m in mobs:
		if (m as Mob).key == "rex" and (m as Mob).tame:
			return true
	return false


func _update_discoveries(delta: float) -> void:
	discover_t -= delta
	if discover_t > 0.0 or player.dead:
		return
	discover_t = 0.5
	var px: int = floori(player.global_position.x / 8.0)
	var py: float = player.global_position.y / 8.0
	if dim == WorldGen.DIM_UMBRAL:
		journal.discover("umbral", "The Umbral Realm", px, "umbral", day_count, dim)
		var cit: Dictionary = gen.citadel()
		if absi(px - int(cit["x"])) < 42 and absf(py - float(cit["floor"])) < 14.0:
			journal.discover("citadel", "The Warden's Citadel", int(cit["x"]), "citadel", day_count, dim)
		return
	for r in Structures.rare_sites(gen, px - 20, px + 20):
		if absi(px - int(r["x"])) < 14 and absf(py - float(gen.surface_at(int(r["x"])))) < 14.0:
			if journal.discover("ruin:%d" % int(r["cell"]), Journal.ruin_name(String(r["kind"])), int(r["x"]), "ruin." + String(r["kind"]), day_count, dim):
				_announce(Journal.ruin_name(String(r["kind"])))
	for m in Structures.mine_sites(gen, px - 6, px + 6):
		var levels: Array = m["levels"]
		if px >= int(m["x"]) - 3 and px <= int(m["x"]) + 5 and py > float(int(m["ground"]) - 6) and py < float(int(levels[levels.size() - 1]) + 2):
			if journal.discover("mine:%d" % int(m["cell"]), "Old Mine", int(m["x"]), "mine", day_count, dim):
				_announce("Old Mine")
	for g in Structures.grotto_sites(gen, px - 2, px + 2):
		if absi(px - int(g["x"])) < int(g["rx"]) and absf(py - float(g["floor"])) < float(int(g["ry"]) + 2):
			if journal.discover("grotto:%d" % int(g["cell"]), "Crystal Grotto", int(g["x"]), "grotto", day_count, dim):
				_announce("Crystal Grotto")
	for lair in gen.lair_centers(px):
		if absi(px - int(lair["cx"])) < 40:
			var nm: String = "The Bear's Den" if lair["kind"] == "bear" else "The Bone Nest"
			if journal.discover("lair:%s:%d" % [String(lair["kind"]), int(lair["k"])], nm, int(lair["cx"]), "lair." + String(lair["kind"]), day_count, dim):
				_announce(nm)
	if absi(px - gen.portal_x) < 12 and absf(py - float(gen.portal_y)) < 10.0:
		if journal.discover("portal", "The Sealed Gate", gen.portal_x, "portal", day_count, dim):
			_announce("The Sealed Gate")


func _announce(place: String) -> void:
	Sfx.play("discovery", 0.8)
	say("Discovered: %s (written in your journal)" % place, 3.5)


# ---------------------------------------------------------------------------------------------- messages & effects

func say(msg: String, secs: float = 2.5) -> void:
	hud.show_message(msg, secs)


func float_text(text: String, pos: Vector2, color: Color) -> void:
	effects.float_text(text, pos, color)


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


## A landed blow holds the creatures still for a moment, which is what makes a hit feel solid
func hit_stop(t: float) -> void:
	hit_stop_t = maxf(hit_stop_t, t)


# ---------------------------------------------------------------------------------------------- panels

func open_panel(name_: String) -> void:
	close_panel()
	input.release_all()
	panel_name = name_
	panel = Panels.make(self, name_)
	if panel == null:
		panel_name = ""
		return
	ui_layer.add_child(panel)
	hud.set_controls_visible(false)
	if name_ == "pause":
		get_tree().paused = true


func close_panel() -> void:
	if panel != null:
		panel.queue_free()
		panel = null
	panel_name = ""
	get_tree().paused = false
	input.release_all()
	if hud != null:
		hud.set_controls_visible(true)
	hud_dirty = true


func open_chest(cell: Vector2i) -> void:
	Sfx.play("chestOpen", 0.7)
	open_panel("inventory")
	if panel != null and panel.has_method("show_chest"):
		panel.call("show_chest", cell)


func open_crafting(station: String) -> void:
	open_panel("inventory")
	if panel != null and panel.has_method("show_station"):
		panel.call("show_station", station)


# ---------------------------------------------------------------------------------------------- death & saving

func on_player_died() -> void:
	Sfx.play("hurt", 1.0)
	say("You died. Your hardcore world is lost." if mode == "hardcore" else "You died!", 4.0)
	if mode == "hardcore":
		hardcore_over = true
		Game.delete_slot(slot)
	dismount()
	open_panel("death")


func respawn() -> void:
	if mode == "hardcore" and hardcore_over:
		return
	close_panel()
	if dim != WorldGen.DIM_OVERWORLD:
		_switch_world(WorldGen.DIM_OVERWORLD)
	_load_around(floori(spawn_point.x / 8.0), 2)
	var y: int = _surface_row(floori(spawn_point.x / 8.0))
	player.respawn_at(Vector2(spawn_point.x, y * 8))
	_snap_camera()
	say("Respawned.", 2.0)
	hud_dirty = true


func save_game() -> void:
	if player == null or (mode == "hardcore" and hardcore_over):
		return
	SaveSystem.write(self, slot)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and Game.level == self:
		Game.level = null


# ---------------------------------------------------------------------------------------------- keyboard and the mouse

func _unhandled_input(event: InputEvent) -> void:
	if panel != null:
		if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
			close_panel()
		return
	var touch_world: bool = false
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			input.pointer_press(_to_world(st.position))
		else:
			input.pointer_release()
		touch_world = true
	elif event is InputEventScreenDrag:
		input.pointer_move(_to_world((event as InputEventScreenDrag).position))
		touch_world = true
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.device == -1:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				input.pointer_press(_to_world(mb.position))
			else:
				input.pointer_release()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			player.actions.set_sel(posmod(player.actions.sel - 1, Inventory.HOTBAR))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			player.actions.set_sel(posmod(player.actions.sel + 1, Inventory.HOTBAR))
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if mm.device != -1 and input.pointer_down:
			input.pointer_move(_to_world(mm.position))
	elif event is InputEventKey:
		_key(event as InputEventKey)
	if touch_world:
		get_viewport().set_input_as_handled()


func _to_world(screen: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen


var _keys := {}


func _key(e: InputEventKey) -> void:
	_keys[e.physical_keycode] = e.pressed
	if e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_ESCAPE:
				open_panel("pause")
			KEY_E, KEY_I, KEY_TAB:
				open_panel("inventory")
			KEY_J:
				open_panel("journal")
			KEY_M:
				if player.inv.total("gadget:treasureMap") > 0:
					open_panel("map")
			KEY_Q:
				player.actions.cycle_weapon()
			KEY_R:
				player.actions.start_reload()
			KEY_F3:
				open_panel("debug")
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				player.actions.set_sel(int(e.physical_keycode) - int(KEY_1))
			KEY_0:
				player.actions.set_sel(9)
	merge_controls()


func _k(code: Key) -> bool:
	return bool(_keys.get(code, false))


## Puts the touch controls (from the HUD) and the keyboard together into `input`
func merge_controls() -> void:
	var kx: float = (1.0 if (_k(KEY_D) or _k(KEY_RIGHT)) else 0.0) - (1.0 if (_k(KEY_A) or _k(KEY_LEFT)) else 0.0)
	var ky: float = (1.0 if (_k(KEY_S) or _k(KEY_DOWN)) else 0.0) - (1.0 if _k(KEY_UP) else 0.0)
	input.move_x = clampf(hud.stick_vec.x + kx, -1.0, 1.0)
	input.move_y = clampf(hud.stick_vec.y + ky, -1.0, 1.0)
	input.jump = hud.jump_down or _k(KEY_W) or _k(KEY_SPACE) or _k(KEY_UP)
	input.down = hud.down_down or _k(KEY_S) or _k(KEY_DOWN)
	if _k(KEY_F):
		input.attack_held = true
	elif not hud.attack_down:
		input.attack_stick_released()
