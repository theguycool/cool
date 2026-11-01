class_name PlayerActions
extends Node
## What the player does with the item in hand: aiming (a finger on the world, the attack stick, or
## the game picking a target), mining with a tier check and speed, building with support and reach
## rules, melee swings shaped by each weapon's profile (arcs, thrusts, wind-ups, combos, backstabs,
## dazes, burns, quakes), bows drawn and loosed, guns that load and reload, slings, thrown bombs and
## flasks, eating, farming and the gadgets; and tapping doors, chests, crafting stations and the rift.

var player: Player
var level: Level

var sel: int = 0
var last_weapon_sel: int = -1
var aim := Vector2.ZERO
var aim_valid: bool = false
var use_held: bool = false
var use_was_held: bool = false
var pressed: bool = false
var released: bool = false
var pending_interact: bool = false
var _pointer_was_down: bool = false

var use_cd: float = 0.0
var swing_t: float = 0.0
var swing_dur: float = 0.25
var swing_angle: float = 0.0
var swing_style: String = "slash"
var strike_t: float = 0.0
var strike_item: String = ""
var strike_sel: int = 0
var combo_n: int = 0
var combo_t: float = 0.0
var bow_charge: float = 0.0
var reload_t: float = 0.0
var reload_slot: int = -1
var place_cd: float = 0.0
var eat_t: float = 0.0
var mining: bool = false
var mine_cell := Vector2i(-99999, -99999)
var mine_p: float = 0.0
var mine_need: float = 1.0
var lock_target: Mob = null
var lock_t: float = 0.0
var last_hits: int = 0


func _ready() -> void:
	player = get_parent() as Player


# ---------------------------------------------------------------------------------------------- held item

func held_slot():
	return player.inv.slots[sel]


func held_id() -> String:
	var s = player.inv.slots[sel]
	if s == null:
		return ""
	return String(s["id"])


func held_is_ranged() -> bool:
	var id: String = held_id()
	return id != "" and DB.is_ranged(id)


func move_scale() -> float:
	var id: String = held_id()
	if id == "" or not DB.is_melee_weapon(id):
		return 1.0
	return float(DB.melee_of(id)["moveScale"])


func is_aiming() -> bool:
	return aim_valid and (use_held or swing_t > 0.0)


func set_sel(i: int) -> void:
	var n: int = clampi(i, 0, Inventory.HOTBAR - 1)
	if n == sel:
		return
	var cur: String = held_id()
	if cur != "" and DB.is_weapon(cur):
		last_weapon_sel = sel
	# switching while attacking must not fire the new weapon in the same instant
	if use_held:
		use_cd = maxf(use_cd, 0.15)
	sel = n
	bow_charge = 0.0
	mining = false
	mine_p = 0.0
	strike_t = 0.0
	combo_n = 0
	reload_t = 0.0
	level.hud_dirty = true


## The next weapon in the hotbar after the one in hand (from a tool: the weapon used last), or -1
func next_weapon_slot() -> int:
	var cur: String = held_id()
	if (cur == "" or not DB.is_weapon(cur)) and last_weapon_sel >= 0:
		var s = player.inv.slots[last_weapon_sel]
		if s != null and DB.is_weapon(String(s["id"])):
			return last_weapon_sel
	for k in range(1, Inventory.HOTBAR + 1):
		var i: int = (sel + k) % Inventory.HOTBAR
		var s2 = player.inv.slots[i]
		if s2 != null and DB.is_weapon(String(s2["id"])) and i != sel:
			return i
	return -1


func cycle_weapon() -> void:
	var i: int = next_weapon_slot()
	if i < 0:
		level.say("No other weapon in your hotbar.", 1.2)
		return
	set_sel(i)
	Sfx.play("swap", 0.6)
	level.float_text(DB.item_name(held_id()), player.global_position + Vector2(0, -22), Color(0.9, 0.9, 0.9))


func shoulder() -> Vector2:
	return player.global_position + Vector2(0, -Player.BODY_H * 0.55)


func attack_angle() -> float:
	if aim_valid:
		var d: Vector2 = aim - shoulder()
		if d.length() > 4.8:
			return d.angle()
	return 0.0 if player.facing >= 0 else PI


## Turning to face the aim; straight up or down keeps the way the player already faces
func aim_facing() -> int:
	var d: float = aim.x - player.global_position.x
	if absf(d) < 2.4:
		return player.facing
	return 1 if d >= 0.0 else -1


func reach_px() -> float:
	return (8.0 if player.is_creative() else 5.5) * 8.0


func in_reach(p: Vector2) -> bool:
	var c: Vector2 = player.global_position + Vector2(0, -Player.BODY_H * 0.6)
	return c.distance_to(p) <= reach_px()


# ---------------------------------------------------------------------------------------------- the frame

func _physics_process(delta: float) -> void:
	if level == null or player.dead:
		use_held = false
		return
	_timers(delta)
	var inp: InputState = level.input
	_read_controls(inp)
	pressed = use_held and not use_was_held
	released = (not use_held) and use_was_held
	use_was_held = use_held
	if player.riding == null:
		_update_use(delta)
	_update_held_sprite()


func _timers(delta: float) -> void:
	use_cd = maxf(0.0, use_cd - delta)
	swing_t = maxf(0.0, swing_t - delta)
	place_cd = maxf(0.0, place_cd - delta)
	lock_t = maxf(0.0, lock_t - delta)
	combo_t = maxf(0.0, combo_t - delta)
	if combo_t <= 0.0:
		combo_n = 0
	if lock_target != null and (not is_instance_valid(lock_target) or lock_target.hp <= 0.0):
		lock_target = null
	if strike_t > 0.0:
		strike_t -= delta
		if strike_t <= 0.0:
			strike_t = 0.0
			if sel == strike_sel and held_id() == strike_item:
				_resolve_melee(strike_item)
	if reload_t > 0.0:
		if reload_slot != sel:
			reload_t = 0.0
		else:
			reload_t -= delta
			if reload_t <= 0.0:
				_finish_reload()


func _read_controls(inp: InputState) -> void:
	# a finger on the world aims for itself; a quick tap on a door, chest or station uses it
	if inp.pointer_down:
		aim = inp.pointer_world
		aim_valid = true
		if not _pointer_was_down:
			var cell := Vector2i(floori(aim.x / 8.0), floori(aim.y / 8.0))
			var fight: bool = held_id() != "" and DB.is_weapon(held_id()) and level.hostile_at(aim)
			pending_interact = not fight and is_interactive(cell)
		if pending_interact and inp.pointer_moved:
			pending_interact = false
		use_held = not pending_interact
		inp.pointer_time += get_physics_process_delta_time()
	elif inp.attack_held:
		_aim_from_attack_stick(inp)
		use_held = true
	else:
		use_held = false
	if _pointer_was_down and not inp.pointer_down and pending_interact:
		pending_interact = false
		if inp.tap_pending:
			interact(Vector2i(floori(inp.tap_world.x / 8.0), floori(inp.tap_world.y / 8.0)))
	if inp.tap_pending and not inp.pointer_down:
		inp.tap_pending = false
	_pointer_was_down = inp.pointer_down


## The attack stick: past the dead zone it aims by hand (each kind of item its own way), inside it
## the game aims (the best foe for the weapon, else the block in front)
func _aim_from_attack_stick(inp: InputState) -> void:
	var id: String = held_id()
	if inp.attack_manual:
		aim = stick_aim(id, inp.attack_dir, inp.attack_power)
		aim_valid = true
		lock_target = null
		if absf(inp.attack_dir.x) > 0.25:
			player.facing = 1 if inp.attack_dir.x >= 0.0 else -1
		return
	var wants_mob: bool = true
	var kind: String = DB.kind_of(id)
	if kind in ["block", "part", "mat", "food", "wall"]:
		wants_mob = false
	if wants_mob:
		var m: Mob = auto_target(id)
		if m != null:
			aim = m.center()
			aim_valid = true
			lock_target = m
			lock_t = maxf(lock_t, 0.5)
			return
	var w: WorldData = level.world
	var fx: int = floori((player.global_position.x + float(player.facing) * (Player.BODY_W * 0.5 + 4.4)) / 8.0)
	var chest_row: int = floori((player.global_position.y - 10.4) / 8.0)
	var feet_row: int = floori((player.global_position.y - 3.2) / 8.0)
	var below: int = floori((player.global_position.y + 4.0) / 8.0)
	var target := Vector2i(fx, chest_row)
	if kind == "block" or kind == "wall":
		if not w.solid(fx, feet_row):
			target = Vector2i(fx, feet_row)
		elif not w.solid(fx, chest_row):
			target = Vector2i(fx, chest_row)
		else:
			target = Vector2i(fx, chest_row - 1)
	elif w.get_tile(fx, chest_row) != T.AIR:
		target = Vector2i(fx, chest_row)
	elif w.get_tile(fx, feet_row) != T.AIR:
		target = Vector2i(fx, feet_row)
	elif inp.move_y > 0.5:
		target = Vector2i(floori(player.global_position.x / 8.0), below)
	aim = Vector2(target.x * 8 + 4, target.y * 8 + 4)
	aim_valid = true


## Where the attack stick aims for this item: blades along the direction, bows and guns along it,
## slings and thrown flasks further out the further the thumb is pushed, tools and fists at the
## first creature or block that way, blocks against the first surface that way
func stick_aim(id: String, dir: Vector2, power: float) -> Vector2:
	var o: Vector2 = shoulder()
	var r: float = minf(reach_px(), 44.0) - 2.4
	var kind: String = DB.kind_of(id)
	if id == "":
		return _dig_point(dir, r)
	match kind:
		"sword", "spear", "hammer", "knife", "club", "relic":
			return o + dir * maxf(8.0, float(DB.melee_of(id)["reach"]) * 8.0)
		"bow", "gun":
			return o + dir * 112.0
		"sling":
			return o + dir * (4.0 + 9.0 * power) * 8.0
		"gadget":
			if id == "gadget:bomb" or id == "gadget:fireFlask":
				return o + dir * (3.0 + 9.0 * power) * 8.0
			return _dig_point(dir, r)
		"tool":
			return _dig_point(dir, r)
		"block", "wall", "part":
			return _place_point(dir, r)
	return o + dir * 12.0


func _dig_point(dir: Vector2, r: float) -> Vector2:
	var o: Vector2 = shoulder()
	var near: Array = level.mobs_near(o.x - r - 8.0, o.x + r + 8.0)
	var d: float = 5.6
	while d <= r:
		var p: Vector2 = o + dir * d
		for m in near:
			var mm: Mob = m
			if mm.hp > 0.0 and not mm.tame and mm.hit_rect().grow(1.6).has_point(p):
				return mm.center()
		var t: int = level.world.get_tile(floori(p.x / 8.0), floori(p.y / 8.0))
		if t != T.AIR and DB.liquid[t] == 0:
			return Vector2(floorf(p.x / 8.0) * 8.0 + 4.0, floorf(p.y / 8.0) * 8.0 + 4.0)
		d += 2.0
	return o + dir * r


func _place_point(dir: Vector2, r: float) -> Vector2:
	var o: Vector2 = shoulder()
	var last := Vector2i(-99999, -99999)
	var d: float = 5.6
	while d <= r:
		var p: Vector2 = o + dir * d
		var c := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
		if level.world.solid(c.x, c.y):
			break
		last = c
		d += 2.0
	if last.x != -99999:
		return Vector2(last.x * 8 + 4, last.y * 8 + 4)
	return o + dir * 9.6


## The foe the attack stick goes for when aiming for you: hostile ones first, the one already locked
## on, in sight for ranged weapons
func auto_target(id: String) -> Mob:
	var ranged: bool = id != "" and DB.is_ranged(id)
	var weapon: bool = id != "" and DB.is_weapon(id)
	var p: Dictionary = DB.melee_of(id)
	var range_px: float = (22.0 if ranged else float(p["reach"]) + 3.0) * 8.0
	var o: Vector2 = shoulder()
	var best: Mob = null
	var bs: float = 1e9
	for m in level.mobs_near(o.x - range_px - 32.0, o.x + range_px + 32.0):
		var mm: Mob = m
		if mm.hp <= 0.0 or mm.tame or mm.downed:
			continue
		var foe: bool = mm.is_hostile() or mm.angry
		if not foe and not weapon:
			continue
		var d: float = mm.box_distance(o)
		if d > range_px:
			continue
		if ranged and not level.line_clear(o, mm.center()):
			continue
		var score: float = d
		if not foe:
			score += 400.0
		if mm == lock_target:
			score -= 40.0
		if score < bs:
			bs = score
			best = mm
	return best


# ---------------------------------------------------------------------------------------------- using the item

func _update_use(delta: float) -> void:
	var id: String = held_id()
	if not use_held:
		mining = false
		mine_p = maxf(0.0, mine_p - delta * 2.0)
		level.effects.crack_cell = Vector2i(-99999, -99999)
	if id == "bow":
		_handle_bow(delta)
		return
	elif bow_charge > 0.0:
		bow_charge = 0.0
	if not use_held or not aim_valid:
		eat_t = 0.0
		return
	var kind: String = DB.kind_of(id)
	match kind:
		"":
			_use_bare_hand(delta)
		"block":
			_use_place_block(id)
		"tool":
			_use_tool(id, delta)
		"sword", "spear", "hammer", "knife", "club", "relic":
			_use_melee_weapon(id)
		"gun":
			_use_gun(id)
		"sling":
			_use_sling()
		"food":
			_use_food(id, delta)
		"mat":
			if id == "mat:seeds":
				_use_plant(T.WHEAT1, id)
		"gadget":
			_use_gadget(id)
		"wall":
			_use_place_wall(int(id.get_slice(":", 1)))
		"armor", "gear":
			if pressed and player.inv.equip_from(sel):
				level.say("Equipped.", 1.0)
		"part":
			if pressed:
				level.say("Vehicles are built from kits in this version: craft a Car or Boat Kit at the tinker's bench.", 3.0)


func _use_bare_hand(delta: float) -> void:
	var m: Mob = mob_under_aim(DB.BARE_HANDS)
	if m != null:
		if pressed or (use_cd <= 0.0 and not melee_candidates(DB.BARE_HANDS).is_empty()):
			start_melee("", m)
		return
	_mine_step(Vector2i(floori(aim.x / 8.0), floori(aim.y / 8.0)), -1, 0, delta)


func _use_tool(id: String, delta: float) -> void:
	var tool_kind: int = DB.tool_kind(id)
	var tier: int = DB.tier_of(id)
	var p: Dictionary = DB.melee_of(id)
	var m: Mob = mob_under_aim(p)
	if m != null:
		if pressed or (use_cd <= 0.0 and not melee_candidates(p).is_empty()):
			start_melee(id, m)
		return
	var cell := Vector2i(floori(aim.x / 8.0), floori(aim.y / 8.0))
	if tool_kind == DB.TOOL_HOE:
		if use_cd <= 0.0 and in_reach(aim):
			var t: int = level.world.get_tile(cell.x, cell.y)
			if (t == T.GRASS or t == T.DIRT or t == T.DRY_GRASS or t == T.JUNGLE_GRASS or t == T.MOSS_GRASS) and level.world.get_tile(cell.x, cell.y - 1) == T.AIR:
				level.world.set_tile(cell.x, cell.y, T.FARMLAND)
				Sfx.play("digDirt", 0.7)
				use_cd = 0.25
				_swing_anim(0.2)
				return
		if level.world.get_tile(cell.x, cell.y) != T.AIR:
			_mine_step(cell, tool_kind, tier, delta)
		return
	_mine_step(cell, tool_kind, tier, delta)


func _swing_anim(t: float) -> void:
	swing_t = t
	swing_dur = t
	swing_style = "slash"
	swing_angle = attack_angle()
	player.facing = aim_facing()


## Digs at a block: the right tool is faster, ores need a pickaxe of at least their tier
func _mine_step(cell: Vector2i, tool_kind: int, tier: int, delta: float) -> void:
	var w: WorldData = level.world
	var t: int = w.get_tile(cell.x, cell.y)
	if t == T.AIR and w.get_wall(cell.x, cell.y) != 0 and tool_kind >= 0 and tool_kind != DB.TOOL_HOE:
		_mine_wall(cell, tier, delta)
		return
	if t == T.AIR or DB.liquid[t] == 1:
		mining = false
		mine_p = 0.0
		level.effects.crack_cell = Vector2i(-99999, -99999)
		if use_cd <= 0.0 and tool_kind >= 0:
			_swing_anim(0.2)
			use_cd = 0.3
		return
	var hard: float = DB.hardness[t]
	if hard >= 9999.0:
		if use_cd <= 0.0:
			level.say("That can't be broken.", 1.2)
			use_cd = 0.6
		return
	if not in_reach(Vector2(cell.x * 8 + 4, cell.y * 8 + 4)):
		mining = false
		mine_p = 0.0
		return
	var need_tier: int = DB.tier[t]
	if need_tier > 0 and not player.is_creative():
		var pt: int = tier if tool_kind == DB.TOOL_PICKAXE else 0
		if pt < need_tier:
			mining = false
			if use_cd <= 0.0:
				level.say("This needs a stronger pickaxe." if tool_kind == DB.TOOL_PICKAXE else "You need a pickaxe for that.", 1.5)
				use_cd = 0.8
				_swing_anim(0.2)
			return
	if mine_cell != cell:
		mine_p = 0.0
		mine_cell = cell
	mining = true
	var speed: float = 1.0
	if tool_kind >= 0 and tier > 0:
		speed = float(DB.tier_info(tier)["mineSpeed"]) * (1.0 if tool_kind == DB.tool_class[t] else 0.35)
	if player.is_creative():
		speed = 1000.0
	mine_need = maxf(0.05, hard * 1.5)
	mine_p += delta * speed
	level.effects.crack_cell = cell
	level.effects.crack_stage = clampi(int(mine_p / mine_need * 5.0), 0, 4)
	if use_cd <= 0.0:
		_swing_anim(0.22)
		use_cd = 0.26
		level.effects.burst(Vector2(cell.x * 8 + 4, cell.y * 8 + 4), DB_color(t), 3, 24.0, 0.4)
		Sfx.play(Sfx.dig_sound(t, false), 0.6)
	if mine_p >= mine_need:
		mine_p = 0.0
		mining = false
		level.effects.crack_cell = Vector2i(-99999, -99999)
		Sfx.play(Sfx.dig_sound(t, true), 0.8)
		if DB.trunk[t] == 1 and tool_kind == DB.TOOL_AXE:
			level.fell_tree(cell.x, cell.y)
		else:
			level.break_tile(cell.x, cell.y, true)


func DB_color(t: int) -> Color:
	return Color.hex((int(DB.tiles[t]["color"]) << 8) | 0xFF)


func _mine_wall(cell: Vector2i, tier: int, delta: float) -> void:
	if not in_reach(Vector2(cell.x * 8 + 4, cell.y * 8 + 4)):
		return
	if mine_cell != cell:
		mine_p = 0.0
		mine_cell = cell
	mining = true
	mine_need = 0.9
	mine_p += delta * (1000.0 if player.is_creative() else float(DB.tier_info(maxi(1, tier))["mineSpeed"]))
	if use_cd <= 0.0:
		_swing_anim(0.22)
		use_cd = 0.26
	if mine_p >= mine_need:
		mine_p = 0.0
		var k: int = level.world.get_wall(cell.x, cell.y)
		level.world.set_wall(cell.x, cell.y, 0)
		Sfx.play("breakStone", 0.6)
		if not player.is_creative() and k > 0:
			level.spawn_drop("wall:%d" % k, 1, Vector2(cell.x * 8 + 4, cell.y * 8 + 4))


# ---------------------------------------------------------------------------------------------- building

func can_place_at(cell: Vector2i, t: int) -> bool:
	var w: WorldData = level.world
	if cell.y < 2 or cell.y >= w.h - 2:
		return false
	var cur: int = w.get_tile(cell.x, cell.y)
	if not (cur == T.AIR or DB.liquid[cur] == 1 or (DB.plant[cur] == 1 and cur != T.TORCH and cur != T.LANTERN) or cur == T.COBWEB):
		return false
	if not in_reach(Vector2(cell.x * 8 + 4, cell.y * 8 + 4)):
		return false
	if DB.solid[t] == 1:
		var r := Rect2(cell.x * 8 + 0.2, cell.y * 8 + 0.2, 7.6, 7.6)
		if r.intersects(player.body_rect()) and not player.noclip:
			return false
		for m in level.mobs_near(r.position.x - 32.0, r.end.x + 32.0):
			var mm: Mob = m
			if mm.hp > 0.0 and r.intersects(mm.hit_rect()):
				return false
	if DB.needs_support[t] == 1:
		if not level.supports(w.get_tile(cell.x, cell.y + 1), t):
			return false
	if player.is_creative() or player.flying:
		return true
	for n in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var k: int = w.get_tile(cell.x + n.x, cell.y + n.y)
		if k != T.AIR and DB.liquid[k] == 0 and not (DB.plant[k] == 1 and k != T.TORCH):
			return true
	if w.get_wall(cell.x, cell.y) != 0:
		return true
	return false


func _use_place_block(id: String) -> void:
	if place_cd > 0.0:
		return
	var cell := Vector2i(floori(aim.x / 8.0), floori(aim.y / 8.0))
	var t: int = DB.block_tile(id)
	if t < 0:
		return
	if t == T.DOOR_CLOSED or t == T.DOOR_OPEN:
		if level.place_door(cell):
			_consume_one()
			place_cd = 0.25
			_swing_anim(0.14)
		return
	var placed: int = DB.placed_form[t]
	if not can_place_at(cell, placed):
		return
	level.place_tile(cell.x, cell.y, placed)
	_consume_one()
	Sfx.play("place", 0.6)
	place_cd = 0.11
	_swing_anim(0.14)


func _use_place_wall(k: int) -> void:
	if place_cd > 0.0:
		return
	var cell := Vector2i(floori(aim.x / 8.0), floori(aim.y / 8.0))
	if not in_reach(Vector2(cell.x * 8 + 4, cell.y * 8 + 4)):
		return
	if level.world.get_wall(cell.x, cell.y) != 0:
		return
	if level.world.set_wall(cell.x, cell.y, k):
		_consume_one()
		place_cd = 0.06
		_swing_anim(0.12)


func _use_plant(crop: int, _id: String) -> void:
	if place_cd > 0.0:
		return
	var cell := Vector2i(floori(aim.x / 8.0), floori(aim.y / 8.0))
	var w: WorldData = level.world
	if w.get_tile(cell.x, cell.y) == T.FARMLAND and w.get_tile(cell.x, cell.y - 1) == T.AIR:
		cell.y -= 1
	if w.get_tile(cell.x, cell.y) == T.AIR and w.get_tile(cell.x, cell.y + 1) == T.FARMLAND and in_reach(Vector2(cell.x * 8 + 4, cell.y * 8 + 4)):
		w.set_tile(cell.x, cell.y, crop)
		_consume_one()
		place_cd = 0.2
		_swing_anim(0.14)


func _consume_one() -> void:
	if not player.is_creative():
		player.inv.remove_at(sel, 1)
	level.hud_dirty = true


# ---------------------------------------------------------------------------------------------- melee

func mob_under_aim(p: Dictionary) -> Mob:
	if not aim_valid:
		return null
	var best: Mob = null
	var bd: float = 1e9
	for m in level.mobs_near(aim.x - 48.0, aim.x + 48.0):
		var mm: Mob = m
		if mm.hp <= 0.0 or mm.tame or mm.downed:
			continue
		if mm.hit_rect().grow(7.2).has_point(aim):
			var d: float = mm.box_distance(shoulder())
			if d <= float(p["reach"]) * 8.0 + 24.0 and d < bd:
				bd = d
				best = mm
	return best


func _use_melee_weapon(id: String) -> void:
	var p: Dictionary = DB.melee_of(id)
	if pressed or (use_cd <= 0.0 and strike_t <= 0.0):
		var m: Mob = mob_under_aim(p)
		start_melee(id, m)


## Starts a swing; heavy weapons wind up first and land a moment later
func start_melee(id: String, _target: Mob = null) -> bool:
	if use_cd > 0.0 or strike_t > 0.0:
		return false
	var p: Dictionary = DB.melee_of(id)
	use_cd = float(p["cooldown"])
	swing_dur = float(p["swingTime"])
	swing_t = swing_dur
	swing_style = String(p["style"])
	swing_angle = attack_angle()
	if absf(cos(swing_angle)) >= 0.25:
		player.facing = 1 if cos(swing_angle) >= 0.0 else -1
	strike_item = id
	strike_sel = sel
	var light: bool = float(p["swingTime"]) <= 0.18
	Sfx.play("swingHeavy" if bool(p["heavy"]) else ("thrust" if swing_style == "thrust" else ("swingLight" if light else "swing")), 0.6)
	if float(p["windup"]) > 0.0:
		strike_t = float(p["windup"])
	else:
		_resolve_melee(id)
	return true


## Whether a swing with profile p, aimed along dir from the shoulder, reaches m: its distance, or -1
func melee_reach(m: Mob, dir: Vector2, p: Dictionary) -> float:
	var o: Vector2 = shoulder()
	var r: Rect2 = m.hit_rect()
	var reach: float = float(p["reach"]) * 8.0
	var near := Vector2(clampf(o.x, r.position.x, r.end.x), clampf(o.y, r.position.y, r.end.y))
	var dist: float = o.distance_to(near)
	if dist > reach:
		return -1.0
	var c: Vector2 = r.get_center()
	var v: Vector2 = c - o
	var hw: float = r.size.x * 0.5
	var hh: float = r.size.y * 0.5
	if String(p["style"]) == "thrust":
		var along: float = v.dot(dir)
		var ext: float = hw * absf(dir.x) + hh * absf(dir.y)
		if along + ext < 0.0 or along - ext > reach:
			return -1.0
		var perp: float = absf(v.x * dir.y - v.y * dir.x)
		var pext: float = hw * absf(dir.y) + hh * absf(dir.x)
		if perp - pext > float(p["band"]) * 8.0:
			return -1.0
	elif dist > 3.6:
		var cd: float = maxf(1.6, v.length())
		var off: float = absf(angle_difference(v.angle(), dir.angle()))
		var ext2: float = hw * absf(v.y / cd) + hh * absf(v.x / cd)
		if off > float(p["halfArc"]) + atan(ext2 / cd):
			return -1.0
	elif v.x * dir.x < -2.4 and absf(dir.x) > 0.3:
		return -1.0
	if not level.line_clear(o, near.lerp(c, 0.25)) and not level.line_clear(o, c):
		return -1.0
	return dist


func melee_candidates(p: Dictionary) -> Array:
	var ang: float = attack_angle()
	var dir := Vector2(cos(ang), sin(ang))
	var o: Vector2 = shoulder()
	var reach: float = float(p["reach"]) * 8.0
	var out: Array = []
	for m in level.mobs_near(o.x - reach - 32.0, o.x + reach + 32.0):
		var mm: Mob = m
		if mm.hp <= 0.0 or mm.tame or mm.downed:
			continue
		var d: float = melee_reach(mm, dir, p)
		if d >= 0.0:
			out.append([mm, d])
	out.sort_custom(_by_distance)
	var max_hits: int = int(p["maxHits"])
	if out.size() > max_hits:
		out.resize(max_hits)
	return out


func _by_distance(a: Array, b: Array) -> bool:
	return float(a[1]) < float(b[1])


## The blow itself: everything inside the swing's shape is hit
func _resolve_melee(id: String) -> void:
	var p: Dictionary = DB.melee_of(id)
	var ang: float = attack_angle()
	level.effects.swing_trail(shoulder(), ang, float(p["reach"]) * 8.0, float(p["halfArc"]), String(p["style"]), int(p["trail"]))
	var hits: Array = melee_candidates(p)
	last_hits = hits.size()
	if bool(p["combo"]):
		combo_n += 1
		combo_t = 0.9
	var sigil: float = 1.2 if player.inv.wearing("gear:wardenSigil") else 1.0
	var any: bool = false
	for h in hits:
		var m: Mob = h[0]
		var dmg: float = float(p["damage"]) * sigil
		var crit: bool = randf() < float(p["critChance"])
		if crit:
			dmg *= 1.5
		if bool(p["combo"]) and combo_n % 3 == 0:
			dmg *= 2.0
			crit = true
		# a blow into a foe's back
		if float(p["backstab"]) > 1.0 and m.dir == (1 if m.global_position.x > player.global_position.x else -1):
			dmg *= float(p["backstab"])
		if m.is_undead():
			dmg *= float(p["undeadMult"])
			if player.inv.wearing("gear:silverCharm"):
				dmg *= 1.25
		var info := {"amount": dmg, "from": player.global_position, "knock": float(p["knock"]), "by_player": true,
			"heavy": bool(p["heavy"]), "crit": crit, "daze": float(p["daze"]), "burn": float(p["burn"])}
		if m.take_damage(info):
			any = true
	if bool(p["shockwave"]):
		level.quake(player.global_position, float(player.facing), float(p["damage"]) * 0.6)
	if any:
		Sfx.play("multiHit" if hits.size() > 1 else "hit", 0.8)
		if hits.size() > 1:
			level.float_text("x%d" % hits.size(), player.global_position + Vector2(0, -26), Color(1, 0.9, 0.5))
		level.hit_stop(0.05)
	elif id != "" and DB.kind_of(id) == "tool":
		pass


# ---------------------------------------------------------------------------------------------- ranged

func _handle_bow(delta: float) -> void:
	var has_arrow: bool = player.is_creative() or player.inv.total("ammo:arrow") > 0
	var charge_time: float = 0.9
	if use_held:
		if not has_arrow:
			if pressed:
				level.say("No arrows!", 1.2)
			bow_charge = 0.0
			return
		if use_cd > 0.0 and bow_charge == 0.0:
			return
		bow_charge = minf(1.0, maxf(bow_charge, 0.01) + delta / charge_time)
		player.facing = aim_facing()
		if bow_charge >= 1.0 and use_cd <= 0.0:
			_fire_arrow(1.0)
			bow_charge = 0.3
	elif released and bow_charge > 0.0 and has_arrow:
		_fire_arrow(maxf(0.45, bow_charge))
		bow_charge = 0.0
	else:
		bow_charge = 0.0


func _fire_arrow(charge: float) -> void:
	if not player.is_creative():
		player.inv.remove("ammo:arrow", 1)
	var o: Vector2 = player.global_position + Vector2(float(player.facing) * 2.8, -9.6)
	var dir: Vector2 = (aim - o).normalized()
	var speed: float = (18.0 + 18.0 * charge) * 8.0
	var dmg: float = 5.0 + 9.0 * charge
	if charge >= 0.99 and randf() < 0.15:
		dmg *= 1.5
	level.spawn_projectile({"kind": "arrow", "pos": o + dir * 3.2, "vel": dir * speed + player.velocity * Vector2(0.3, 0.2),
		"dmg": dmg, "gravity": 240.0, "from_player": true, "life": 6.0, "knock": 4.0})
	Sfx.play("bow", 0.7)
	use_cd = 0.35
	swing_t = 0.18
	swing_dur = 0.18
	level.hud_dirty = true


func _use_gun(id: String) -> void:
	var s = held_slot()
	var g: Dictionary = DB.gun_info(id)
	if s == null or g.is_empty():
		return
	if reload_t > 0.0:
		return
	var loaded: int = int(s.get("x", 0))
	if loaded <= 0:
		if id == "gun:stormRod":
			if pressed:
				level.say("The rod is still charging.", 1.0)
			return
		start_reload()
		return
	if use_cd > 0.0:
		return
	if bool(g["needsPress"]) and not pressed:
		return
	s["x"] = loaded - 1
	use_cd = float(g["cooldown"])
	swing_t = 0.12
	swing_dur = 0.12
	player.facing = aim_facing()
	var o: Vector2 = player.global_position + Vector2(float(player.facing) * 4.0, -9.6)
	var dir: Vector2 = (aim - o).normalized()
	var spd: float = float(g["speed"]) * 8.0
	var dmg: float = float(g["damage"]) * (1.2 if player.inv.wearing("gear:wardenSigil") else 1.0)
	match id:
		"gun:stormRod":
			level.storm_bolt(o, dir, dmg)
			Sfx.play("zap", 0.8)
		"gun:blunderbuss":
			for k in range(7):
				var a: float = dir.angle() + randf_range(-0.22, 0.22)
				level.spawn_projectile({"kind": "pellet", "pos": o, "vel": Vector2(cos(a), sin(a)) * spd * randf_range(0.85, 1.1),
					"dmg": dmg, "gravity": 0.0, "from_player": true, "life": 0.45, "knock": float(g["knock"])})
			Sfx.play("blunderbuss", 0.9)
			level.add_shake(0.25)
		_:
			var kind: String = "bolt" if bool(g["bolts"]) else "bullet"
			level.spawn_projectile({"kind": kind, "pos": o, "vel": dir * spd, "dmg": dmg, "gravity": float(g["gravity"]) * 8.0,
				"from_player": true, "life": float(g["life"]), "knock": float(g["knock"]), "pierce": int(g["pierce"])})
			Sfx.play("crossbow" if bool(g["bolts"]) else "gun", 0.8)
			if bool(g["firearm"]):
				level.effects.muzzle(o + dir * 6.0)
	if int(s["x"]) <= 0 and id != "gun:stormRod":
		start_reload()
	level.hud_dirty = true


func start_reload() -> void:
	var id: String = held_id()
	var g: Dictionary = DB.gun_info(id)
	if g.is_empty() or reload_t > 0.0 or id == "gun:stormRod":
		return
	var s = held_slot()
	if int(s.get("x", 0)) >= int(g["magazine"]):
		return
	var ammo: String = String(g.get("ammo", ""))
	if ammo != "" and not player.is_creative() and player.inv.total(ammo) <= 0:
		if pressed:
			level.say("Out of %ss." % DB.item_name(ammo).to_lower(), 1.4)
		return
	reload_t = float(g["reload"])
	reload_slot = sel
	level.hud_dirty = true


func _finish_reload() -> void:
	var id: String = held_id()
	var g: Dictionary = DB.gun_info(id)
	var s = held_slot()
	if g.is_empty() or s == null:
		return
	var need: int = int(g["magazine"]) - int(s.get("x", 0))
	var ammo: String = String(g.get("ammo", ""))
	var got: int = need
	if ammo != "" and not player.is_creative():
		got = player.inv.remove(ammo, need)
	s["x"] = int(s.get("x", 0)) + got
	Sfx.play("tap", 0.6)
	level.hud_dirty = true


## The storm rod charges itself back up over time
func recharge_rods(delta: float) -> void:
	for i in range(Inventory.SIZE):
		var s = player.inv.slots[i]
		if s != null and String(s["id"]) == "gun:stormRod" and int(s.get("x", 0)) < 5:
			s["rt"] = float(s.get("rt", 0.0)) + delta
			if float(s["rt"]) >= 3.0:
				s["rt"] = 0.0
				s["x"] = int(s.get("x", 0)) + 1


func _use_sling() -> void:
	if use_cd > 0.0:
		return
	var stone: String = ""
	for st in ["block:stone", "block:slate", "block:deepRock", "block:ashStone", "block:sandstone"]:
		if player.is_creative() or player.inv.total(st) > 0:
			stone = st
			break
	if stone == "":
		if pressed:
			level.say("The sling needs stones to throw.", 1.4)
		return
	if not player.is_creative():
		player.inv.remove(stone, 1)
	var o: Vector2 = player.global_position + Vector2(float(player.facing) * 3.0, -11.0)
	var vel: Vector2 = _lob(o, aim, 180.0, 22.0 * 8.0)
	level.spawn_projectile({"kind": "stone", "pos": o, "vel": vel, "dmg": 4.5, "gravity": 180.0, "from_player": true, "life": 4.0, "knock": 9.0})
	Sfx.play("sling", 0.7)
	use_cd = 0.55
	swing_t = 0.2
	swing_dur = 0.2
	player.facing = aim_facing()
	level.hud_dirty = true


## The velocity that lands a lobbed throw on the target (or as close as the arm allows)
func _lob(from: Vector2, to: Vector2, g: float, max_speed: float) -> Vector2:
	var d: Vector2 = to - from
	var t: float = clampf(d.length() / (max_speed * 0.7), 0.25, 1.4)
	var v := Vector2(d.x / t, (d.y - 0.5 * g * t * t) / t)
	if v.length() > max_speed:
		v = v.normalized() * max_speed
	return v


func _use_food(id: String, delta: float) -> void:
	var vals: Array = DB.food_values(id)
	if player.hunger >= 20.0 and player.hp >= player.max_hp:
		if pressed:
			level.say("You're full.", 1.0)
		return
	eat_t += delta
	if int(eat_t * 6.0) != int((eat_t - delta) * 6.0):
		level.effects.burst(player.global_position + Vector2(float(player.facing) * 3.0, -12.0), Color(0.85, 0.6, 0.4), 1, 16.0, 0.3)
	if eat_t >= 0.8:
		eat_t = 0.0
		player.hunger = minf(20.0, player.hunger + float(vals[0]))
		if float(vals[1]) > 0.0:
			player.heal(float(vals[1]))
		_consume_one()
		Sfx.play("eat", 0.8)
		if id == "food:rawMeat" or id == "food:rawFish":
			if randf() < 0.25:
				level.say("That didn't sit well...", 1.5)
				player.hunger = maxf(0.0, player.hunger - 1.0)


func _use_gadget(id: String) -> void:
	match id:
		"gadget:bomb", "gadget:fireFlask":
			if use_cd > 0.0:
				return
			if not pressed and not use_held:
				return
			var o: Vector2 = player.global_position + Vector2(float(player.facing) * 3.0, -11.0)
			var vel: Vector2 = _lob(o, aim, 200.0, 24.0 * 8.0)
			level.spawn_projectile({"kind": "bomb" if id == "gadget:bomb" else "flask", "pos": o, "vel": vel, "dmg": 26.0 if id == "gadget:bomb" else 6.0,
				"gravity": 200.0, "from_player": true, "life": 1.6 if id == "gadget:bomb" else 5.0, "knock": 8.0})
			_consume_one()
			use_cd = 0.6
			swing_t = 0.2
			swing_dur = 0.2
			player.facing = aim_facing()
			Sfx.play("swing", 0.5)
		"gadget:shears":
			if not pressed:
				return
			var m: Mob = mob_under_aim(DB.BARE_HANDS)
			if m != null and m.key == "sheep" and not m.sheared:
				m.shear()
				level.spawn_drop("mat:wool", 1 + randi() % 3, m.center())
				Sfx.play("tap", 0.7)
			else:
				_mine_step(Vector2i(floori(aim.x / 8.0), floori(aim.y / 8.0)), DB.TOOL_AXE, 2, get_physics_process_delta_time())
		"gadget:treasureMap":
			if pressed:
				level.open_panel("map")
		"gadget:barometer":
			if pressed:
				level.say(level.weather.barometer_text(), 3.0)
		"gadget:waterFlask":
			if pressed:
				level.water_crop(Vector2i(floori(aim.x / 8.0), floori(aim.y / 8.0)))
		"gadget:carKit", "gadget:boatKit", "gadget:motorboatKit":
			if pressed and in_reach(aim):
				if level.place_vehicle(id, aim):
					_consume_one()
		"gadget:portalKey":
			if pressed:
				interact(Vector2i(floori(aim.x / 8.0), floori(aim.y / 8.0)))
		_:
			if pressed:
				level.say("Sparkworks wiring is not part of this version yet.", 2.0)


# ---------------------------------------------------------------------------------------------- interacting

const INTERACTIVE := [T.CHEST, T.WORKBENCH, T.FURNACE, T.CAMPFIRE, T.PORTAL_OFF, T.DOOR_CLOSED, T.DOOR_OPEN, T.ANVIL,
	T.TINKER_BENCH, T.RIFT_FORGE, T.WEATHER_STATION, T.DOPPLER_STATION, T.STORM_SIREN, T.WEATHER_VANE, T.SHUTTER_CLOSED,
	T.SHUTTER_OPEN, T.LEVER, T.POWER_SWITCH, T.LAMP_OFF, T.LAMP_ON, T.GATE_CLOSED, T.GATE_OPEN, T.RAIN_BARREL, T.RAIN_CISTERN]


func is_interactive(cell: Vector2i) -> bool:
	var t: int = level.world.get_tile(cell.x, cell.y)
	if INTERACTIVE.has(t):
		return true
	if level.vehicle_at(Vector2(cell.x * 8 + 4, cell.y * 8 + 4)) != null:
		return true
	var m: Mob = level.mob_at(Vector2(cell.x * 8 + 4, cell.y * 8 + 4))
	return m != null and (m.tame or m.key == "wolf" or m.key == "cat")


func interact(cell: Vector2i) -> void:
	var w: WorldData = level.world
	var t: int = w.get_tile(cell.x, cell.y)
	var p := Vector2(cell.x * 8 + 4, cell.y * 8 + 4)
	if not in_reach(p) and t != T.AIR:
		level.say("Too far away.", 1.0)
		return
	var m: Mob = level.mob_at(p)
	if m != null:
		level.interact_mob(m, held_id(), sel)
		return
	var v: Vehicle = level.vehicle_at(p)
	if v != null:
		level.drive(v)
		return
	match t:
		T.DOOR_CLOSED, T.DOOR_OPEN:
			level.toggle_door(cell.x, cell.y)
		T.SHUTTER_CLOSED:
			w.set_tile(cell.x, cell.y, T.SHUTTER_OPEN)
			Sfx.play("door", 0.6)
		T.SHUTTER_OPEN:
			w.set_tile(cell.x, cell.y, T.SHUTTER_CLOSED)
			Sfx.play("door", 0.6)
		T.CHEST:
			level.open_chest(cell)
		T.WORKBENCH:
			level.open_crafting("bench")
		T.FURNACE:
			level.open_crafting("furnace")
		T.CAMPFIRE:
			level.open_crafting("campfire")
		T.ANVIL:
			level.open_crafting("anvil")
		T.TINKER_BENCH:
			level.open_crafting("tinker")
		T.RIFT_FORGE:
			level.open_crafting("forge")
		T.PORTAL_OFF:
			level.try_open_portal(cell)
		T.WEATHER_STATION, T.DOPPLER_STATION, T.STORM_SIREN, T.WEATHER_VANE:
			level.open_panel("weather")
		T.RAIN_BARREL, T.RAIN_CISTERN:
			level.collect_rainwater(cell)
		T.LEVER, T.POWER_SWITCH:
			Sfx.play("tap", 0.7)
			level.toggle_power(cell)
		T.LAMP_OFF:
			w.set_tile(cell.x, cell.y, T.LAMP_ON)
		T.LAMP_ON:
			w.set_tile(cell.x, cell.y, T.LAMP_OFF)
		T.GATE_CLOSED:
			w.set_tile(cell.x, cell.y, T.GATE_OPEN)
		T.GATE_OPEN:
			w.set_tile(cell.x, cell.y, T.GATE_CLOSED)


# ---------------------------------------------------------------------------------------------- the item in the hand

func _update_held_sprite() -> void:
	var held: Sprite2D = player.held
	var id: String = held_id()
	if id == "" or player.climbing or player.riding != null:
		held.visible = false
		return
	held.visible = true
	held.texture = Art.icon(id)
	held.flip_h = false
	var f: float = float(player.facing)
	var kind: String = DB.kind_of(id)
	var hand := Vector2(f * 3.0, -7.0)
	var rot: float = 0.0
	var ranged: bool = kind == "bow" or kind == "gun" or kind == "sling"
	if ranged and (use_held or swing_t > 0.0 or bow_charge > 0.0):
		var a: float = (aim - shoulder()).angle()
		hand = Vector2(cos(a), sin(a)) * 5.0 + Vector2(0, -8.0)
		rot = a + PI * 0.25
	elif swing_t > 0.0 and swing_dur > 0.0:
		var k: float = 1.0 - swing_t / swing_dur
		var a2: float = swing_angle
		if swing_style == "thrust" or swing_style == "stab":
			hand = Vector2(cos(a2), sin(a2)) * (3.0 + 6.0 * sin(k * PI)) + Vector2(0, -8.0)
			rot = a2 + PI * 0.25
		else:
			var spread: float = 1.6
			var start: float = a2 - spread * 0.5 * f
			var cur: float = start + spread * k * f
			hand = Vector2(cos(cur), sin(cur)) * 6.0 + Vector2(0, -8.0)
			rot = cur + PI * 0.25
	else:
		rot = (0.35 if player.facing > 0 else -0.35) - PI * 0.25 * f + (PI * 0.5 if player.facing < 0 else 0.0)
		if kind == "block" or kind == "food" or kind == "mat":
			rot = 0.0
	held.position = hand
	held.rotation = rot
	held.scale = Vector2(0.75, 0.75)
	held.z_index = 1 if (swing_t > 0.0 or use_held) else -1
