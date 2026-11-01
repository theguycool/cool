class_name DebugTools
## What the debug menu can do to the world, as in the Swift game: set the time, heal, hand out a kit,
## clear monsters, teleport (spawn, surface, gate, the lairs, the other realm, by steps), drop hazards
## to test with (lava, an explosion, falling sand, spikes, fire), force the weather and spawn any creature.


static func set_time(lv: Level, t: float) -> void:
	lv.time_of_day = t
	lv.hud_dirty = true


static func heal(lv: Level) -> void:
	var p: Player = lv.player
	p.hp = p.max_hp
	p.hunger = 20.0
	p.air = 10.0
	p.burn = 0.0
	lv.hud_dirty = true


static func give_kit(lv: Level) -> void:
	var inv: Inventory = lv.player.inv
	for e in [["tool:pickaxe:diamond", 1], ["tool:axe:diamond", 1], ["sword:diamond", 1], ["bow", 1], ["ammo:arrow", 99],
			["block:torch", 99], ["block:planks", 99], ["food:cookedMeat", 20], ["armor:head:iron", 1], ["armor:chest:iron", 1],
			["armor:legs:iron", 1], ["gun:pistol", 1], ["ammo:bullet", 60]]:
		var a: Array = e
		var id: String = String(a[0])
		if DB.has_item(id):
			var extra: int = int(DB.gun_info(id).get("magazine", 0)) if DB.kind_of(id) == "gun" else 0
			inv.add(id, int(a[1]), extra)
	lv.say("Kit given.", 1.2)


static func kill_hostiles(lv: Level) -> void:
	var n: int = 0
	for m in lv.mobs.duplicate():
		var mm: Mob = m
		if (mm.is_hostile() or mm.angry) and not mm.tame and mm.hp > 0.0:
			mm.take_damage({"amount": 99999.0, "from": mm.global_position, "knock": 0.0, "by_player": false})
			n += 1
	lv.say("Removed %d hostile creatures." % n, 1.5)


static func delete_entities(lv: Level, with_vehicles: bool) -> void:
	for m in lv.mobs.duplicate():
		var mm: Mob = m
		if not mm.tame:
			lv.remove_mob(mm)
	for e in lv.entities.get_children():
		if e is Drop:
			e.queue_free()
	for p in lv.projectiles_node.get_children():
		p.queue_free()
	if with_vehicles:
		lv.dismount()
		for v in lv.vehicles:
			(v as Node).queue_free()
		lv.vehicles.clear()
	lv.say("Entities cleared.", 1.2)


## Moves the player to a block position (x, feet row y), loading the world there first
static func teleport(lv: Level, x: int, y: int) -> void:
	lv.dismount()
	lv._load_around(x, 2)
	var p: Player = lv.player
	p.global_position = Vector2(x * 8 + 4, y * 8)
	p.velocity = Vector2.ZERO
	p.fall_peak = 0.0
	lv._snap_camera()
	lv.hud_dirty = true


static func to_surface(lv: Level) -> void:
	var x: int = floori(lv.player.global_position.x / 8.0)
	lv._load_around(x, 2)
	teleport(lv, x, lv._surface_row(x))


static func to_spawn(lv: Level) -> void:
	var x: int = floori(lv.spawn_point.x / 8.0)
	lv._load_around(x, 2)
	teleport(lv, x, lv._surface_row(x))


static func to_portal(lv: Level) -> void:
	if lv.dim != WorldGen.DIM_OVERWORLD:
		lv.travel(WorldGen.DIM_OVERWORLD)
	teleport(lv, lv.gen.portal_x + 6, lv.gen.portal_y + 5)


static func to_lair(lv: Level, kind: String) -> void:
	if lv.dim != WorldGen.DIM_OVERWORLD:
		lv.travel(WorldGen.DIM_OVERWORLD)
	for lair in lv.gen.lair_centers(floori(lv.player.global_position.x / 8.0)):
		if String(lair["kind"]) == kind:
			var x: int = int(lair["cx"]) - 30
			lv._load_around(x, 2)
			teleport(lv, x, lv._surface_row(x))
			return
	lv.say("No lair of that kind in this world.", 1.5)


static func switch_dimension(lv: Level) -> void:
	lv.travel(WorldGen.DIM_UMBRAL if lv.dim == WorldGen.DIM_OVERWORLD else WorldGen.DIM_OVERWORLD)


static func nudge(lv: Level, dx: int, dy: int) -> void:
	var c: Vector2i = lv.player.feet_cell()
	teleport(lv, c.x + dx, c.y + 1 + dy)


static func lava_pool(lv: Level) -> void:
	var c: Vector2i = lv.player.feet_cell()
	var x0: int = c.x + 4 * lv.player.facing
	for dx in range(0, 4):
		var x: int = x0 + dx * lv.player.facing
		lv.world.set_tile(x, c.y + 1, T.LAVA)


static func explosion(lv: Level) -> void:
	var p: Vector2 = lv.player.global_position + Vector2(float(lv.player.facing) * 40.0, -8.0)
	lv.explode(p, 3.0, 20.0, false, true)


static func sand_drop(lv: Level) -> void:
	var c: Vector2i = lv.player.feet_cell()
	for dx in range(-1, 2):
		for dy in range(8, 11):
			if lv.world.get_tile(c.x + dx, c.y - dy) == T.AIR:
				lv.world.set_tile(c.x + dx, c.y - dy, T.SAND)
	lv._drop_sand(c.x - 1, c.y - 8)
	lv._drop_sand(c.x, c.y - 8)
	lv._drop_sand(c.x + 1, c.y - 8)


static func spikes(lv: Level) -> void:
	var c: Vector2i = lv.player.feet_cell()
	for dx in range(3, 6):
		var x: int = c.x + dx * lv.player.facing
		if lv.world.get_tile(x, c.y) == T.AIR:
			lv.world.set_tile(x, c.y, T.SPIKES)


static func set_on_fire(lv: Level) -> void:
	lv.player.burn = 3.0


static func spawn(lv: Level, key: String) -> void:
	var p: Vector2 = lv.player.global_position + Vector2(float(lv.player.facing) * 32.0, -2.0)
	if bool(DB.mob(key).get("flying", false)):
		p.y -= 24.0
	if key == "fish":
		lv.say("Fish need water: try it in a lake.", 1.5)
	lv.spawn_mob(key, p)
