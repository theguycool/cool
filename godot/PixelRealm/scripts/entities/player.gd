class_name Player
extends CharacterBody2D
## The hero: walking, jumping (with a moment of grace off ledges and a buffered press), climbing
## ladders, swimming, dropping through platforms, stepping up single blocks, fall damage, hazards,
## breath, hunger and healing, and the sprite with its armour layers. The numbers are the Swift
## game's (blocks per second there, times 8 pixels per block here). What the player does with the
## item in hand is in PlayerActions (the Actions child).

const BODY_W := 5.6
const BODY_H := 14.4
const GRAVITY := 272.0
const TERMINAL := 208.0
const JUMP_V := -127.2
const RUN := 59.2
const ACCEL_GROUND := 576.0
const ACCEL_AIR := 320.0
const FRICTION := 720.0
const AIR_FRICTION := 96.0
const CLIMB_V := 41.6

const MASK_SOLID := 1
const MASK_PLATFORM := 2

@onready var body: AnimatedSprite2D = $Body
@onready var armor_legs: AnimatedSprite2D = $ArmorLegs
@onready var armor_chest: AnimatedSprite2D = $ArmorChest
@onready var armor_head: AnimatedSprite2D = $ArmorHead
@onready var held: Sprite2D = $Held
@onready var pickup_area: Area2D = $Pickup
@onready var actions: PlayerActions = $Actions

var level: Level = null
var inv := Inventory.new()
var max_hp: float = 20.0
var hp: float = 20.0
var hunger: float = 20.0
var air: float = 10.0
var facing: int = 1
var dead: bool = false
var invuln: float = 0.0
var hurt_t: float = 0.0
var land_t: float = 0.0
var coyote: float = 0.0
var jump_buf: float = 0.0
var jump_prev: bool = false
var drop_t: float = 0.0
var fall_peak: float = 0.0
var regen_t: float = 0.0
var starve_t: float = 0.0
var drown_t: float = 0.0
var lava_t: float = 0.0
var burn: float = 0.0
var burn_t: float = 0.0
var vault_t: float = 0.0
var in_water: bool = false
var in_lava: bool = false
var climbing: bool = false
var flying: bool = false
var noclip: bool = false
var god_mode: bool = false
var walk_anim: float = 0.0
var spawn_point := Vector2.ZERO
var hair: int = 0
var scarf: int = 0
var riding: Node = null
var _armor_key: String = ""
var _pose: String = ""


func _ready() -> void:
	for s in [body, armor_legs, armor_chest, armor_head]:
		(s as AnimatedSprite2D).centered = false
	refresh_look()
	inv.changed.connect(_on_inventory_changed)
	pickup_area.area_entered.connect(_on_pickup)


## The world position of the middle of the body
func center() -> Vector2:
	return global_position + Vector2(0, -BODY_H * 0.5)


func feet_cell() -> Vector2i:
	return Vector2i(floori(global_position.x / 8.0), floori((global_position.y - 0.5) / 8.0))


func body_rect() -> Rect2:
	return Rect2(global_position.x - BODY_W * 0.5, global_position.y - BODY_H, BODY_W, BODY_H)


func is_creative() -> bool:
	return level != null and level.mode == "creative"


# ---------------------------------------------------------------------------------------------- look

## Rebuilds the sprite frames for the chosen hair, scarf and the armour worn
func refresh_look() -> void:
	body.sprite_frames = Art.player_frames(hair, scarf)
	var key: String = "%d:%d:%d" % [inv.armor_tier(0), inv.armor_tier(1), inv.armor_tier(2)]
	if key == _armor_key:
		return
	_armor_key = key
	var layers: Array = [[armor_head, 0, "head"], [armor_chest, 1, "chest"], [armor_legs, 2, "legs"]]
	for l in layers:
		var spr: AnimatedSprite2D = l[0]
		var t: int = inv.armor_tier(int(l[1]))
		if t > 0:
			spr.sprite_frames = Art.armor_frames(String(l[2]), t)
			spr.visible = true
		else:
			spr.visible = false
	_pose = ""


func _on_inventory_changed() -> void:
	refresh_look()
	if level != null:
		level.hud_dirty = true


func _set_pose(anim: String, frame_index: int, playing: bool, speed: float = 1.0) -> void:
	var meta: Dictionary = Art.player_meta()
	var w: float = float(meta["w"])
	var cc: float = float(meta["center"])
	var foot: float = float(meta["foot"])
	var left: bool = facing < 0
	var off := Vector2(-(w - cc) if left else -cc, -(foot + 1.0))
	for s in [body, armor_legs, armor_chest, armor_head]:
		var spr: AnimatedSprite2D = s
		if spr.sprite_frames == null or not spr.visible:
			continue
		spr.flip_h = left
		spr.offset = off
		if spr.animation != anim:
			spr.animation = anim
		if playing:
			if not spr.is_playing():
				spr.play(anim)
			spr.speed_scale = speed
		else:
			spr.stop()
			spr.frame = frame_index


func _sync_armor_frames() -> void:
	for s in [armor_legs, armor_chest, armor_head]:
		var spr: AnimatedSprite2D = s
		if spr.visible and spr.animation == body.animation:
			spr.frame = body.frame


# ---------------------------------------------------------------------------------------------- movement

func _physics_process(delta: float) -> void:
	if level == null:
		return
	if dead:
		velocity = Vector2.ZERO
		return
	if riding != null:
		return
	var inp: InputState = level.input
	invuln = maxf(0.0, invuln - delta)
	hurt_t = maxf(0.0, hurt_t - delta)
	land_t = maxf(0.0, land_t - delta)
	var ix: float = clampf(inp.move_x, -1.0, 1.0)
	if absf(ix) < 0.08:
		ix = 0.0
	var jump_pressed: bool = inp.jump and not jump_prev
	jump_prev = inp.jump
	_sense_liquids()
	var run_max: float = RUN * (1.18 if inv.wearing("gear:swiftBoots") else 1.0) * level.weather_walk_scale()
	if actions.swing_t > 0.0:
		run_max *= actions.move_scale()
	if ix != 0.0:
		facing = 1 if ix > 0.0 else -1
	if actions.is_aiming():
		facing = actions.aim_facing()
	if flying or noclip:
		_fly(ix, inp, delta)
		return
	if (in_water or in_lava) and vault_t <= 0.0 and inp.jump and ix != 0.0 and is_on_wall() and _ledge_within_reach(1 if ix > 0.0 else -1):
		vault_t = 0.32
		velocity.y = -104.0
	vault_t = maxf(0.0, vault_t - delta)
	var swimming: bool = (in_water or in_lava) and vault_t <= 0.0
	var ladder_x: int = _ladder_column() if not swimming else -2147483648
	climbing = ladder_x != -2147483648
	if climbing:
		var up: bool = inp.jump or inp.move_y < -0.45
		var dn: bool = inp.down or inp.move_y > 0.45
		var vy_t: float = -CLIMB_V if up else (CLIMB_V if dn else 0.0)
		velocity.y += (vy_t - velocity.y) * minf(1.0, delta * 16.0)
		var tx: float = ix * run_max * 0.7
		if ix == 0.0 and (up or dn):
			tx = ((float(ladder_x) + 0.5) * 8.0 - global_position.x) * 8.0
		velocity.x += (tx - velocity.x) * minf(1.0, delta * 14.0)
		set_collision_mask_value(MASK_PLATFORM, not dn)
		coyote = 0.11
		jump_buf = 0.0
		fall_peak = 0.0
		move_and_slide()
		walk_anim += (absf(velocity.y) + absf(velocity.x)) * delta * 0.07
		_after_move(delta, ix, false)
		return
	# walking: accelerate toward the target speed, with friction when the stick is let go
	var wind: float = 0.0 if swimming else level.weather_push(is_on_floor())
	var target: float = ix * run_max * (0.55 if swimming else 1.0) + (wind if ix != 0.0 else 0.0)
	var grip: float = 1.0 - 0.6 * level.slipperiness(self) if is_on_floor() else 1.0
	var accel: float = (ACCEL_GROUND if is_on_floor() else ACCEL_AIR) * grip
	if ix != 0.0:
		velocity.x = move_toward(velocity.x, target, accel * delta)
	else:
		var rest: float = 0.0 if swimming else wind * 0.4
		var fr: float = (FRICTION * grip if is_on_floor() else AIR_FRICTION) * delta
		velocity.x = move_toward(velocity.x, rest, fr)
	if is_on_floor():
		coyote = 0.11
	else:
		coyote -= delta
	if jump_pressed:
		jump_buf = 0.13
	else:
		jump_buf -= delta
	if jump_buf > 0.0 and coyote > 0.0 and not swimming:
		velocity.y = JUMP_V
		coyote = 0.0
		jump_buf = 0.0
		level.effects.dust(global_position, 4)
	if swimming:
		velocity.y += (112.0 if in_lava else 88.0) * delta
		if inp.jump:
			velocity.y = maxf(velocity.y - 416.0 * delta, -52.0)
		velocity.y = clampf(velocity.y, -64.0, 24.0 if in_lava else 48.0)
	else:
		var g: float = GRAVITY
		if not inp.jump and velocity.y < -40.0:
			g *= 2.6
		velocity.y = minf(velocity.y + g * delta, TERMINAL)
	if inp.down or inp.move_y > 0.6:
		drop_t = 0.22
	drop_t = maxf(0.0, drop_t - delta)
	set_collision_mask_value(MASK_PLATFORM, drop_t <= 0.0)
	if ix != 0.0 and is_on_floor():
		_step_up(1 if ix > 0.0 else -1)
	var was_air: bool = not is_on_floor()
	move_and_slide()
	_door_touch(ix)
	if not is_on_floor() and velocity.y > 0.0:
		fall_peak = maxf(fall_peak, velocity.y / 8.0)
	if is_on_floor() and was_air:
		if fall_peak > 20.0 and not swimming and not is_creative() and not god_mode:
			var dmg: float = (fall_peak - 20.0) * 1.15
			hurt(dmg, global_position.x, 0.0, true, "fall")
			level.add_shake(0.3)
		if fall_peak > 9.0:
			level.effects.dust(global_position, 6)
		if fall_peak > 6.0:
			Sfx.play("land", clampf((fall_peak - 6.0) / 14.0, 0.2, 1.0))
			land_t = 0.12
		fall_peak = 0.0
	if is_on_floor() or swimming:
		fall_peak = 0.0
	walk_anim += absf(velocity.x) * delta * 0.07
	_after_move(delta, ix, swimming)


func _after_move(delta: float, ix: float, swimming: bool) -> void:
	_check_hazards(delta)
	_update_survival(delta, ix)
	_animate(swimming)


func _fly(ix: float, inp: InputState, delta: float) -> void:
	var tx: float = ix * 104.0
	var ty: float = 0.0
	if inp.jump:
		ty = -80.0
	if inp.down or inp.move_y > 0.55:
		ty = 80.0
	velocity.x += (tx - velocity.x) * minf(1.0, delta * 9.0)
	velocity.y += (ty - velocity.y) * minf(1.0, delta * 9.0)
	if noclip:
		global_position += velocity * delta
	else:
		set_collision_mask_value(MASK_PLATFORM, false)
		move_and_slide()
	walk_anim += absf(velocity.x) * delta * 0.07
	fall_peak = 0.0
	_animate(false)


func _sense_liquids() -> void:
	var w: WorldData = level.world
	var x: int = floori(global_position.x / 8.0)
	var mid: int = w.get_tile(x, floori((global_position.y - BODY_H * 0.5) / 8.0))
	var low: int = w.get_tile(x, floori((global_position.y - 2.0) / 8.0))
	in_water = mid == T.WATER or low == T.WATER
	in_lava = mid == T.LAVA or low == T.LAVA


## Walking into a single block steps up onto it (when there is room for the body above it)
func _step_up(dir: int) -> void:
	var w: WorldData = level.world
	var fx: int = floori((global_position.x + float(dir) * (BODY_W * 0.5 + 1.0)) / 8.0)
	var feet_row: int = floori((global_position.y - 1.0) / 8.0)
	if not w.solid(fx, feet_row):
		return
	if w.solid(fx, feet_row - 1) or w.solid(fx, feet_row - 2):
		return
	var own: int = floori(global_position.x / 8.0)
	if w.solid(own, feet_row - 2) or w.solid(own, feet_row - 1 - 2):
		return
	global_position.y = float(feet_row) * 8.0 - 0.05
	velocity.y = minf(velocity.y, 0.0)


func _ledge_within_reach(dir: int) -> bool:
	var w: WorldData = level.world
	var fx: int = floori((global_position.x + float(dir) * (BODY_W * 0.5 + 1.2)) / 8.0)
	var feet: int = floori((global_position.y - 0.4) / 8.0)
	for k in range(4):
		var row: int = feet - k
		if not w.solid(fx, row) and not w.solid(fx, row - 1) and w.solid(fx, row + 1):
			return global_position.y / 8.0 - float(row + 1) <= 2.6
	return false


## The column of a ladder the body is on, or the lowest int when there is none
func _ladder_column() -> int:
	var w: WorldData = level.world
	var cx: int = floori(global_position.x / 8.0)
	var frac: float = global_position.x / 8.0 - float(cx)
	var cols: Array = [cx]
	if frac < 0.34:
		cols.append(cx - 1)
	elif frac > 0.66:
		cols.append(cx + 1)
	var y0: int = floori((global_position.y - BODY_H + 0.8) / 8.0)
	var y1: int = floori((global_position.y + 0.4) / 8.0)
	for tx in cols:
		for y in range(y0, y1 + 1):
			var t: int = w.get_tile(int(tx), y)
			if t == T.LADDER:
				return int(tx)
			if t == T.PLATFORM and w.get_tile(int(tx), y + 1) == T.LADDER:
				return int(tx)
	return -2147483648


## Walking into a closed door opens it
func _door_touch(ix: float) -> void:
	if ix == 0.0 or not is_on_wall():
		return
	var w: WorldData = level.world
	var fx: int = floori((global_position.x + signf(ix) * (BODY_W * 0.5 + 1.5)) / 8.0)
	for dy in [1, 2]:
		var y: int = floori((global_position.y - 0.5) / 8.0) - int(dy) + 1
		if w.get_tile(fx, y) == T.DOOR_CLOSED:
			level.toggle_door(fx, y)
			return


# ---------------------------------------------------------------------------------------------- hazards & survival

func _check_hazards(delta: float) -> void:
	if is_creative() or god_mode:
		return
	var w: WorldData = level.world
	var r: Rect2 = body_rect().grow(0.6)
	var x0: int = floori(r.position.x / 8.0)
	var x1: int = floori(r.end.x / 8.0)
	var y0: int = floori(r.position.y / 8.0)
	var y1: int = floori((r.end.y + 0.4) / 8.0)
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var t: int = w.get_tile(x, y)
			if t == T.SPIKES or t == T.CACTUS:
				hurt(6.0 if t == T.SPIKES else 3.0, global_position.x - float(facing) * 8.0, 5.0, false, "hazard")
			elif t == T.CAMPFIRE:
				burn = maxf(burn, 1.2)
	if in_lava:
		var charm: bool = inv.wearing("gear:emberCharm")
		burn = maxf(burn, 1.0 if charm else 2.5)
		lava_t += delta
		if lava_t > 0.35:
			lava_t = 0.0
			hurt(2.0 if charm else 5.0, global_position.x, 0.0, false, "lava")
	else:
		lava_t = 0.0
	if burn > 0.0:
		burn -= delta
		if in_water:
			burn = 0.0
		burn_t += delta
		if burn_t > 0.6:
			burn_t = 0.0
			hurt(1.0, global_position.x, 0.0, true, "fire")
			level.effects.burst(center(), Color(1.0, 0.55, 0.15), 4, 20.0, 0.4)


func _update_survival(delta: float, ix: float) -> void:
	if is_creative():
		return
	var head_y: int = floori((global_position.y - BODY_H * 0.92) / 8.0)
	if level.world.get_tile(floori(global_position.x / 8.0), head_y) == T.WATER:
		air -= delta * (1.0 / 3.0 if inv.wearing("gear:divingMask") else 1.0)
		if air <= 0.0:
			air = 0.0
			drown_t += delta
			if drown_t >= 1.0:
				drown_t = 0.0
				hurt(2.0, global_position.x, 0.0, true, "drown")
	else:
		air = minf(10.0, air + delta * 5.0)
		drown_t = 0.0
	var rate: float = (0.030 if ix != 0.0 else 0.016) * (1.3 if in_water else 1.0)
	hunger = maxf(0.0, hunger - rate * delta)
	if hunger <= 0.0:
		starve_t += delta
		if starve_t >= 3.0:
			starve_t = 0.0
			if hp > 1.0 or level.mode == "hardcore":
				hurt(1.0, global_position.x, 0.0, true, "hunger")
	else:
		starve_t = 0.0
	if hunger >= 14.0 and hp < max_hp:
		regen_t += delta
		if regen_t >= (0.9 if hunger >= 18.0 else 1.6):
			regen_t = 0.0
			hp = minf(max_hp, hp + 1.0)
			hunger = maxf(0.0, hunger - 0.12)
			level.hud_dirty = true
	else:
		regen_t = 0.0


## Takes damage (armour softens it unless `ignore_armor`); returns true if it landed
func hurt(amount: float, from_x: float, knock: float = 6.0, ignore_armor: bool = false, _source: String = "") -> bool:
	if dead or god_mode or is_creative():
		return false
	if invuln > 0.0 and not ignore_armor:
		return false
	var d: float = amount
	if not ignore_armor:
		d *= 1.0 - minf(0.75, inv.defense() * 0.045)
	if inv.wearing("gear:wardenSigil"):
		d *= 0.85
	d = maxf(1.0, roundf(d))
	hp -= d
	Sfx.play("hurt", 0.8)
	invuln = 0.55
	hurt_t = 0.35
	if knock > 0.0:
		var dirk: float = 1.0 if global_position.x >= from_x else -1.0
		velocity.x = dirk * knock * 8.0
		velocity.y = -48.0
	level.float_text("-" + str(int(d)), global_position + Vector2(0, -BODY_H - 3), Color(1.0, 0.31, 0.31))
	level.add_shake(0.2)
	level.hud_dirty = true
	if hp <= 0.0:
		die()
	return true


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)
	level.hud_dirty = true


func die() -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	velocity = Vector2.ZERO
	visible = false
	level.effects.burst(center(), Color(0.75, 0.19, 0.19), 24, 48.0, 0.9)
	level.on_player_died()


func respawn_at(p: Vector2) -> void:
	dead = false
	visible = true
	hp = max_hp
	hunger = maxf(hunger, 14.0)
	air = 10.0
	burn = 0.0
	velocity = Vector2.ZERO
	global_position = p
	invuln = 3.0
	fall_peak = 0.0


func _on_pickup(area: Area2D) -> void:
	if area is Drop and not dead:
		(area as Drop).collect(self)


# ---------------------------------------------------------------------------------------------- animation

func _animate(swimming: bool) -> void:
	var anim: String = "idle"
	var playing: bool = true
	var frame_index: int = 0
	var speed: float = 1.0
	if actions.swing_t > 0.0:
		if actions.held_is_ranged():
			anim = "aim"
		else:
			anim = "swing"
			playing = false
			frame_index = 0 if actions.swing_t > actions.swing_dur * 0.5 else 1
	elif actions.bow_charge > 0.0:
		anim = "aim"
	elif climbing:
		anim = "climb"
		speed = clampf((absf(velocity.y) + absf(velocity.x)) / 40.0, 0.0, 1.5)
		if speed < 0.05:
			playing = false
			frame_index = 0
	elif not is_on_floor() and not swimming:
		anim = "air"
	elif absf(velocity.x) > 4.8:
		anim = "walk"
		speed = clampf(absf(velocity.x) / RUN, 0.5, 1.6)
	_set_pose(anim, frame_index, playing, speed)
	_sync_armor_frames()
	# the light where the player stands, a white flash when hit, a blink while protected
	var lt: float = level.lighting.level_at(center())
	var c := Color(lt, lt, lt, 1.0)
	if hurt_t > 0.0:
		c = Color(2.6, 2.6, 2.6, 1.0)
	elif invuln > 0.0 and int(Time.get_ticks_msec() / 80) % 2 == 0:
		c.a = 0.55
	modulate = c
	if land_t > 0.0:
		scale = Vector2(1.0, 1.0 - 0.1 * land_t / 0.12)
	else:
		scale = Vector2.ONE
