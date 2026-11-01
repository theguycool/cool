class_name Mob
extends CharacterBody2D
## Every creature: animals that wander, graze and flee; predators; monsters with the Swift game's
## senses (sight with line of sight, hearing up close, memory of where the player was last seen) and
## plan (idle, alert, chase, search, go back, back off when stuck), and each kind's own attack with a
## wind-up you can step away from; ranged shooters; fliers and swimmers; tame pets; and the four
## bosses (Ursavor, Tyrannax, the Crystal Sentinel and the Hollow Warden).

const GRAVITY := 272.0
const TERMINAL := 208.0

## st: 0 standing, 1 walking, 3+ the stages of an attack (wind-up, blow, recovery)
## attacks: reach (blocks ahead), height, wind-up, recovery, cooldown, knockback, range to start it
const MELEE := {
	"zombie": [1.2, 1.8, 0.32, 0.25, 0.9, 6.5, 1.5],
	"skeleton": [2.2, 1.9, 0.38, 0.22, 1.2, 7.0, 2.0],
	"pirate": [2.2, 1.9, 0.3, 0.22, 1.2, 7.0, 2.0],
	"pirateCaptain": [2.4, 2.0, 0.3, 0.22, 0.9, 8.0, 2.2],
	"villager": [1.0, 1.6, 0.4, 0.2, 2.0, 3.0, 1.0],
	"scorpion": [1.4, 1.0, 0.25, 0.2, 1.0, 5.0, 1.5],
	"crawler": [1.6, 1.0, 0.45, 0.3, 1.4, 7.0, 4.6],
	"golem": [3.0, 2.6, 0.6, 0.4, 1.8, 11.0, 3.3],
	"grizzly": [1.8, 1.6, 0.35, 0.25, 1.1, 8.0, 2.0],
	"polarBear": [1.8, 1.6, 0.35, 0.25, 1.1, 8.0, 2.0],
	"bear": [1.6, 1.4, 0.35, 0.25, 1.2, 7.0, 1.8],
	"tiger": [1.6, 1.2, 0.25, 0.2, 0.9, 7.0, 1.8],
	"wolf": [1.2, 1.0, 0.22, 0.2, 0.8, 5.0, 1.4],
	"elephant": [2.2, 2.4, 0.5, 0.35, 1.6, 12.0, 2.4],
	"mimic": [1.3, 1.1, 0.2, 0.25, 0.8, 6.0, 1.5],
}
## ranged: what it shoots, range, cooldown, projectile speed (blocks/s), gravity
const RANGED := {
	"archer": ["arrow", 18.0, 1.6, 26.0, 18.0],
	"pirateGunner": ["bullet", 17.0, 1.9, 40.0, 0.0],
	"imp": ["fireball", 17.0, 2.2, 15.0, 0.0],
}
const UNDEAD := ["zombie", "skeleton", "archer", "wraith", "warden"]
const CONTACT := ["slime", "emberSlime", "bat", "cinderBat", "wraith", "crawler", "mimic", "fish"]

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var shape_node: CollisionShape2D = $Shape

var level: Level = null
var key: String = "pig"
var def: Dictionary = {}
var variant: int = 0
var hp: float = 10.0
var max_hp: float = 10.0
var dir: int = 1
var st: int = 0
var t1: float = 0.0
var t3: float = 0.0
var cd: float = 0.0
var knock_t: float = 0.0
var flash_t: float = 0.0
var daze_t: float = 0.0
var burn: float = 0.0
var burn_tick: float = 0.0
var angry: bool = false
var tame: bool = false
var stay: bool = false
var sheared: bool = false
var downed: bool = false
var persistent: bool = false
var ridden: bool = false
var boss_key: String = ""
var hunter: bool = false
var home := Vector2.ZERO
var ai: String = "idle"
var ai_t: float = 0.0
var sees: bool = false
var los_t: float = 0.0
var seen := Vector2.ZERO
var lost_t: float = 0.0
var aim_x: float = 0.0
var blocked_t: float = 0.0
var prog_x: float = 0.0
var leap_t: float = 0.0
var last_hit_t: float = 99.0
var anim_t: float = 0.0
var dying: float = -1.0
var shield_up: bool = false
var phase: int = 1
var special_t: float = 0.0
var in_water: bool = false
var why: String = ""
var mount_jump_prev: bool = false
var _w: float = 8.0
var _h: float = 8.0


## Must be called before the creature is added to the scene
func setup(lv: Level, k: String, v: int = -1) -> void:
	level = lv
	key = k
	def = DB.mob(k)
	if v < 0:
		v = randi() % 3 if k == "zombie" else 0
	variant = v
	max_hp = float(def["hp"])
	hp = max_hp
	_w = float(def["w"]) * 8.0
	_h = float(def["h"]) * 8.0
	dir = 1 if randf() < 0.5 else -1


func _ready() -> void:
	var sh := RectangleShape2D.new()
	sh.size = Vector2(maxf(2.0, _w - 0.6), maxf(2.0, _h - 0.4))
	shape_node.shape = sh
	shape_node.position = Vector2(0, -_h * 0.5)
	collision_layer = 8
	collision_mask = 1 if bool(def["flying"]) else 3
	home = global_position
	prog_x = global_position.x
	refresh_frames()


func refresh_frames() -> void:
	var v: int = variant
	if key == "sheep":
		v = 1 if sheared else 0
	elif key == "wolf":
		v = 1 if tame else 0
	sprite.sprite_frames = Art.creature_frames(key, v)
	sprite.centered = false
	sprite.play("idle")


func display_name() -> String:
	if tame and key == "wolf":
		return "Dog"
	return String(def["name"])


func is_hostile() -> bool:
	return bool(def["hostile"]) and not tame


func is_undead() -> bool:
	return UNDEAD.has(key)


func is_boss() -> bool:
	return String(def["behavior"]) == "boss"


func hit_rect() -> Rect2:
	return Rect2(global_position.x - _w * 0.5, global_position.y - _h, _w, _h)


func center() -> Vector2:
	return global_position + Vector2(0, -_h * 0.5)


func box_distance(p: Vector2) -> float:
	var r: Rect2 = hit_rect()
	var dx: float = maxf(0.0, maxf(r.position.x - p.x, p.x - r.end.x))
	var dy: float = maxf(0.0, maxf(r.position.y - p.y, p.y - r.end.y))
	return sqrt(dx * dx + dy * dy)


func shear() -> void:
	sheared = true
	refresh_frames()


# ---------------------------------------------------------------------------------------------- damage

## info: amount, from (Vector2), knock (blocks/s), by_player, heavy, crit, daze, burn, explosion, shock
func take_damage(info: Dictionary) -> bool:
	if hp <= 0.0 or dying >= 0.0:
		return false
	if tame and bool(info.get("by_player", false)):
		return false
	var amount: float = float(info.get("amount", 1.0))
	var from: Vector2 = info.get("from", global_position)
	var knock: float = float(info.get("knock", 4.0))
	var from_side: int = 1 if global_position.x >= from.x else -1
	# a skeleton's raised shield turns a blow from the front, unless it is a heavy one
	if shield_up and from_side != dir and not bool(info.get("explosion", false)):
		if bool(info.get("heavy", false)):
			shield_up = false
			cd = maxf(cd, 0.9)
			level.float_text("Guard broken", center() + Vector2(0, -10), Color(1.0, 0.94, 0.75))
		else:
			amount *= 0.1
			knock *= 0.25
			level.float_text("Blocked", center() + Vector2(0, -10), Color(0.63, 0.75, 1.0))
	if key == "golem" and not bool(info.get("heavy", false)) and not bool(info.get("explosion", false)):
		amount *= 0.5
	if is_boss():
		knock *= 0.15
	hp -= amount
	flash_t = 0.12
	last_hit_t = 0.0
	if bool(info.get("by_player", false)):
		angry = true
		if ai == "idle" or ai == "back" or ai == "search":
			ai = "chase"
			ai_t = 0.0
	if float(info.get("daze", 0.0)) > 0.0:
		daze_t = maxf(daze_t, float(info["daze"]))
		level.float_text("Dazed", center() + Vector2(0, -12), Color(1.0, 0.9, 0.45))
	if float(info.get("burn", 0.0)) > 0.0:
		burn = maxf(burn, float(info["burn"]))
	if knock > 0.0:
		velocity.x = float(from_side) * knock * 8.0
		if is_on_floor():
			velocity.y = -48.0
		knock_t = 0.25
	var col := Color(1.0, 0.85, 0.3) if bool(info.get("crit", false)) else Color(1.0, 1.0, 1.0)
	level.float_text(str(int(roundf(amount))), center() + Vector2(0, -_h * 0.5 - 2), col)
	level.effects.burst(center(), Color(0.85, 0.2, 0.2) if not is_undead() else Color(0.75, 0.75, 0.7), 4, 30.0, 0.4)
	if hp <= 0.0:
		_die(bool(info.get("by_player", false)))
	return true


func _die(by_player: bool) -> void:
	hp = 0.0
	dying = 0.0
	velocity = Vector2(velocity.x * 0.5, -40.0)
	collision_layer = 0
	if is_boss() or boss_key != "":
		level.on_boss_defeated(self)
		if tame:
			dying = -1.0
			hp = max_hp * 0.6
			collision_layer = 8
			return
	if by_player or randf() < 0.5:
		for s in Loot.mob_drops(key, sheared):
			level.spawn_drop(String(s["id"]), int(s["n"]), center())
	level.effects.burst(center(), Color(0.85, 0.85, 0.85), 10, 40.0, 0.6)
	Sfx.play("hit", 0.6)


# ---------------------------------------------------------------------------------------------- the frame

func _physics_process(delta: float) -> void:
	if level == null:
		return
	if dying >= 0.0:
		dying += delta
		velocity.y = minf(velocity.y + GRAVITY * delta, TERMINAL)
		move_and_slide()
		modulate.a = clampf(1.0 - dying / 0.45, 0.0, 1.0)
		if dying > 0.45:
			level.remove_mob(self)
		return
	var p: Player = level.player
	var dx_p: float = p.global_position.x - global_position.x
	# far away: forget it (unless it matters), or wait for the ground to load
	if not persistent and not tame and boss_key == "" and absf(dx_p) > 110.0 * 8.0:
		level.remove_mob(self)
		return
	if not level.world.is_loaded_x(floori(global_position.x / 8.0)):
		return
	if level.hit_stop_t > 0.0 and absf(dx_p) < 80.0:
		return
	cd = maxf(0.0, cd - delta)
	flash_t = maxf(0.0, flash_t - delta)
	knock_t = maxf(0.0, knock_t - delta)
	last_hit_t += delta
	anim_t += delta
	_sense_water()
	_hazards(delta)
	if hp <= 0.0:
		return
	if daze_t > 0.0:
		daze_t -= delta
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
		_fall(delta)
		move_and_slide()
		_animate()
		return
	if ridden:
		_ridden(delta)
		_animate()
		return
	if tame:
		_pet(delta)
	elif is_boss():
		match key:
			"bearBoss":
				_boss_bear(delta)
			"rex":
				_boss_rex(delta)
			"sentinel":
				_boss_sentinel(delta)
			"warden":
				_boss_warden(delta)
	else:
		var beh: String = String(def["behavior"])
		if beh == "flyer":
			_flyer(delta)
		elif beh == "swimmer":
			_swimmer(delta)
		elif key == "slime" or key == "emberSlime":
			_slime(delta)
		elif RANGED.has(key):
			_ranged(delta)
		elif beh == "hostile" or (beh == "defensive" and angry):
			_melee_monster(delta)
		elif beh == "skittish":
			_skittish(delta)
		else:
			_animal(delta)
	_contact(delta)
	_animate()


func _fall(delta: float) -> void:
	if bool(def["flying"]):
		return
	if in_water:
		velocity.y += 96.0 * delta
		velocity.y = clampf(velocity.y, -40.0, 40.0)
		if String(def["behavior"]) != "swimmer":
			velocity.y -= 208.0 * delta
	else:
		velocity.y = minf(velocity.y + GRAVITY * delta, TERMINAL)


func _sense_water() -> void:
	var t: int = level.world.get_tile(floori(global_position.x / 8.0), floori((global_position.y - _h * 0.5) / 8.0))
	in_water = t == T.WATER
	if t == T.LAVA and key != "emberSlime" and key != "imp" and key != "cinderBat":
		burn = maxf(burn, 2.0)


func _hazards(delta: float) -> void:
	# the undead burn in full daylight under an open sky
	if is_undead() and level.dim == WorldGen.DIM_OVERWORLD and level.day_factor() > 0.7 and not in_water and boss_key == "":
		var cx: int = floori(global_position.x / 8.0)
		if floori((global_position.y - 8.0) / 8.0) < level.world.sky_top(cx) and level.weather.rain_here(level) < 0.5:
			burn = maxf(burn, 2.0)
	if burn > 0.0:
		burn -= delta
		if in_water:
			burn = 0.0
		burn_tick += delta
		if burn_tick > 0.6:
			burn_tick = 0.0
			take_damage({"amount": 2.0, "from": global_position, "knock": 0.0, "by_player": false})
			level.effects.burst(center(), Color(1.0, 0.55, 0.15), 3, 20.0, 0.4)


func _accel_x(target: float, rate: float, delta: float) -> void:
	if knock_t > 0.0:
		return
	velocity.x = move_toward(velocity.x, target, rate * 8.0 * delta)


func _speed() -> float:
	return float(def["speed"]) * 8.0


func _step() -> void:
	move_and_slide()


## A wall in front while walking: hop it
func _hop_walls() -> void:
	if is_on_wall() and is_on_floor():
		velocity.y = -float(def["jump"]) * 8.0


func _cliff_ahead(d: int) -> bool:
	var fx: int = floori((global_position.x + float(d) * (_w * 0.5 + 4.8)) / 8.0)
	var fy: int = floori((global_position.y + 1.6) / 8.0)
	for k in range(5):
		var t: int = level.world.get_tile(fx, fy + k)
		if DB.solid[t] == 1 or t == T.PLATFORM or DB.liquid[t] == 1:
			return false
	return true


func _wander(delta: float, speed_k: float) -> void:
	t1 -= delta
	if t1 <= 0.0:
		if st == 0:
			st = 1
			dir = 1 if randf() < 0.5 else -1
			if absf(global_position.x - home.x) > 24.0 * 8.0:
				dir = -1 if global_position.x > home.x else 1
			t1 = randf_range(1.5, 4.5)
		else:
			st = 0
			t1 = randf_range(1.0, 4.0)
	if st == 1:
		if _cliff_ahead(dir) or (is_on_wall() and not is_on_floor()):
			dir = -dir
		if is_on_wall() and is_on_floor():
			if randf() < 0.5:
				velocity.y = -float(def["jump"]) * 8.0
			else:
				dir = -dir
		_accel_x(float(dir) * _speed() * speed_k, 14.0, delta)
	else:
		_accel_x(0.0, 18.0, delta)


func _flee(from_x: float, delta: float, speed_k: float) -> void:
	dir = 1 if global_position.x >= from_x else -1
	_accel_x(float(dir) * _speed() * speed_k, 30.0, delta)
	_hop_walls()


func _chase(tx: float, speed_k: float, delta: float) -> void:
	var dx: float = tx - global_position.x
	if absf(dx) > 2.8:
		dir = 1 if dx >= 0.0 else -1
		_accel_x(float(dir) * _speed() * speed_k, 26.0, delta)
	else:
		_accel_x(0.0, 30.0, delta)
	_hop_walls()
	if in_water:
		velocity.y -= 144.0 * delta


# ---------------------------------------------------------------------------------------------- senses

## The senses and the plan, the same for every monster (each kind has its own attacks). Returns
## whether it is after the player; `aim_x` is where it is heading.
func _think(delta: float, dist: float, dy: float) -> bool:
	ai_t += delta
	leap_t = maxf(0.0, leap_t - delta)
	var p: Player = level.player
	if p.dead:
		if ai != "idle" and ai != "back":
			ai = "back"
			ai_t = 0.0
		aim_x = home.x
		why = "player gone"
		return false
	los_t -= delta
	if los_t <= 0.0:
		los_t = 0.18 + float(get_instance_id() % 7) * 0.02
		var eye: Vector2 = global_position + Vector2(0, -_h * 0.8)
		sees = key == "wraith" or level.line_clear(eye, p.global_position + Vector2(0, -8.6)) or level.line_clear(eye, p.global_position + Vector2(0, -13.0))
	var base: float = maxf(float(def["aggro"]), 16.0) * 8.0
	var sight: float = base * (1.25 if hunter else 1.0) * (1.5 if ai == "chase" else 1.0)
	var sense: float = base * 0.7
	var hurt: bool = last_hit_t < 0.6
	var heard: bool = dist < 28.0 and absf(dy) < 24.0
	var detect: bool = hurt or heard or (dist < sight and absf(dy) < 96.0 and sees)
	var sensed: bool = dist < sense and absf(dy) < 80.0
	if detect or sensed:
		seen = p.global_position
		lost_t = 0.0
	else:
		lost_t += delta
	var hunting: bool = hunter and level.is_night() and level.dim == WorldGen.DIM_OVERWORLD and dist < 640.0
	match ai:
		"idle", "back":
			if detect:
				ai = "chase" if hurt else "alert"
				ai_t = 0.0
			elif sensed:
				ai = "search"
				ai_t = 0.0
			elif hunting:
				ai = "search"
				ai_t = 0.0
				seen = p.global_position + Vector2(randf_range(-48.0, 48.0), 0)
		"alert":
			if ai_t > 0.35:
				ai = "chase"
				ai_t = 0.0
		"chase":
			if lost_t > 2.5:
				ai = "search"
				ai_t = 0.0
		"search":
			if detect:
				ai = "chase"
				ai_t = 0.0
			elif sensed:
				ai_t = 0.0
			elif (absf(global_position.x - seen.x) < 9.6 and ai_t > 2.0) or ai_t > (14.0 if hunting else 8.0):
				if hunting:
					seen = p.global_position + Vector2(randf_range(-64.0, 64.0), 0)
					ai_t = 0.0
				else:
					ai = "back"
					ai_t = 0.0
		"retreat":
			if ai_t > 2.5:
				ai = "chase" if detect else "search"
				ai_t = 0.0
	match ai:
		"alert", "chase":
			aim_x = p.global_position.x
		"search":
			aim_x = seen.x
		"retreat":
			aim_x = global_position.x + (48.0 if global_position.x >= seen.x else -48.0)
		"back":
			aim_x = home.x
		_:
			aim_x = global_position.x
	if ai == "back" and absf(global_position.x - home.x) < 16.0:
		ai = "idle"
		ai_t = 0.0
	# getting nowhere: one harder leap, then back off and come again
	var pushing: bool = (ai == "chase" or ai == "search") and absf(aim_x - global_position.x) > 8.0 and st <= 1
	if pushing:
		if absf(global_position.x - prog_x) > 4.8:
			prog_x = global_position.x
			blocked_t = maxf(0.0, blocked_t - 0.5)
		else:
			blocked_t += delta
		if not bool(def["flying"]) and blocked_t > 0.9 and leap_t <= 0.0 and is_on_floor():
			velocity.y = -float(def["jump"]) * 8.0 * 1.22
			velocity.x = (1.0 if aim_x >= global_position.x else -1.0) * maxf(20.0, _speed())
			leap_t = 1.6
		if blocked_t > 3.2:
			ai = "retreat"
			ai_t = 0.0
			blocked_t = 0.0
	elif st <= 1:
		prog_x = global_position.x
		blocked_t = maxf(0.0, blocked_t - delta * 0.5)
	why = ai
	return ai != "idle" and ai != "back"


# ---------------------------------------------------------------------------------------------- kinds

func _animal(delta: float) -> void:
	var p: Player = level.player
	if angry and String(def["behavior"]) == "passive":
		t3 -= delta
		_flee(p.global_position.x, delta, 1.9)
		if t3 <= -4.0:
			angry = false
			t3 = 0.0
	else:
		_wander(delta, 0.55)
	_fall(delta)
	_step()


func _skittish(delta: float) -> void:
	var p: Player = level.player
	var dist: float = global_position.distance_to(p.global_position)
	if (dist < 40.0 and absf(p.velocity.x) > 20.0) or angry:
		_flee(p.global_position.x, delta, 1.7)
		if dist > 120.0:
			angry = false
	else:
		_wander(delta, 0.5)
		if key == "frog" and is_on_floor() and randf() < delta * 0.6:
			velocity.y = -float(def["jump"]) * 8.0
			velocity.x = float(dir) * _speed()
	_fall(delta)
	_step()


func _melee_monster(delta: float) -> void:
	var p: Player = level.player
	var dist: float = absf(p.global_position.x - global_position.x)
	var dy: float = p.global_position.y - global_position.y
	var a: Array = MELEE.get(key, [1.2, 1.6, 0.35, 0.25, 1.0, 6.0, 1.5])
	var aggro: bool = _think(delta, dist, dy)
	if st == 3:
		t3 -= delta
		_accel_x(0.0, 40.0, delta)
		if key == "crawler" and t3 < 0.15 and is_on_floor():
			velocity = Vector2(float(dir) * 96.0, -72.0)
		if t3 <= 0.0:
			st = 4
			t3 = float(a[3])
			_strike(float(a[0]), float(a[1]), float(def["dmg"]), float(a[5]))
	elif st == 4:
		t3 -= delta
		_accel_x(0.0, 40.0, delta)
		if t3 <= 0.0:
			st = 0
			cd = float(a[4])
	elif aggro:
		var sp: float = 1.15 if dist > 64.0 else 0.95
		if key == "skeleton":
			shield_up = dist > 19.2 and dist < 88.0 and ai == "chase"
			if shield_up:
				sp = 0.7
		_chase(aim_x, sp, delta)
		if ai == "chase" and (sees or dist < 8.0) and cd <= 0.0 and dist < float(a[6]) * 8.0 + _w * 0.5 and absf(dy) < float(a[1]) * 8.0:
			st = 3
			t3 = float(a[2])
			shield_up = false
			dir = 1 if p.global_position.x >= global_position.x else -1
	else:
		shield_up = false
		_wander(delta, 0.45)
	_fall(delta)
	_step()


## A swing: hits the player (and pets) inside the reach box in front
func _strike(reach: float, height: float, dmg: float, knock: float) -> void:
	var x0: float = global_position.x - 2.4 if dir > 0 else global_position.x - reach * 8.0 - 2.4
	var x1: float = global_position.x + reach * 8.0 + 2.4 if dir > 0 else global_position.x + 2.4
	var box := Rect2(x0, global_position.y - height * 8.0, x1 - x0, height * 8.0 + 0.8)
	var p: Player = level.player
	if not p.dead and box.intersects(p.body_rect()):
		var mult: float = level.spawner.monster_damage_scale()
		if p.inv.wearing("gear:silverCharm") and is_undead():
			mult *= 0.75
		p.hurt(dmg * mult, global_position.x, knock)
	for m in level.mobs_near(x0 - 16.0, x1 + 16.0):
		var mm: Mob = m
		if mm.tame and mm != self and box.intersects(mm.hit_rect()):
			mm.take_damage({"amount": dmg, "from": global_position, "knock": knock, "by_player": false})
	Sfx.play("swing", 0.4)


func _contact(_delta: float) -> void:
	if not CONTACT.has(key) or not is_hostile() or cd > 0.0:
		return
	var p: Player = level.player
	if p.dead:
		return
	if hit_rect().grow(0.4).intersects(p.body_rect()):
		var dmg: float = float(def["dmg"]) * level.spawner.monster_damage_scale()
		if p.hurt(dmg, global_position.x, 6.5):
			cd = 0.9
			if key == "emberSlime" or key == "cinderBat":
				p.burn = maxf(p.burn, 1.5)


func _slime(delta: float) -> void:
	var p: Player = level.player
	var dist: float = absf(p.global_position.x - global_position.x)
	var dy: float = p.global_position.y - global_position.y
	var aggro: bool = _think(delta, dist, dy)
	if is_on_floor():
		_accel_x(0.0, 30.0, delta)
		t1 -= delta
		if t1 <= 0.0:
			t1 = randf_range(0.6, 1.4) if aggro else randf_range(1.5, 3.0)
			if aggro:
				dir = 1 if aim_x >= global_position.x else -1
			else:
				dir = 1 if randf() < 0.5 else -1
			velocity.y = -float(def["jump"]) * 8.0 * (1.0 if aggro else 0.7)
			velocity.x = float(dir) * _speed() * (1.3 if aggro else 0.7)
	_fall(delta)
	_step()


func _flyer(delta: float) -> void:
	var p: Player = level.player
	var dist: float = global_position.distance_to(p.global_position)
	var hostile: bool = is_hostile()
	var target: Vector2
	if hostile and dist < float(def["aggro"]) * 8.0 * 1.5 and not p.dead:
		target = p.global_position + Vector2(0, -10.0 + sin(anim_t * 3.0) * 6.0)
		if cd > 0.0:
			target += Vector2(-float(dir) * 40.0, -24.0)
	else:
		t1 -= delta
		if t1 <= 0.0:
			t1 = randf_range(1.5, 3.5)
			seen = global_position + Vector2(randf_range(-64.0, 64.0), randf_range(-32.0, 24.0))
		target = seen
	var v: Vector2 = (target - global_position)
	var sp: float = _speed() * (1.0 if hostile else 0.6)
	if v.length() > 2.0:
		v = v.normalized() * sp
	velocity = velocity.lerp(v, minf(1.0, delta * 3.0))
	if absf(velocity.x) > 2.0:
		dir = 1 if velocity.x > 0.0 else -1
	_step()


func _swimmer(delta: float) -> void:
	if not in_water:
		velocity.y = minf(velocity.y + GRAVITY * delta, TERMINAL)
		velocity.x = move_toward(velocity.x, 0.0, 100.0 * delta)
		if is_on_floor() and randf() < delta * 3.0:
			velocity = Vector2(randf_range(-40.0, 40.0), -60.0)
		_step()
		return
	t1 -= delta
	if t1 <= 0.0:
		t1 = randf_range(1.0, 3.0)
		seen = Vector2(randf_range(-1.0, 1.0), randf_range(-0.4, 0.4))
	velocity = velocity.lerp(seen * _speed(), minf(1.0, delta * 2.0))
	var ahead: int = level.world.get_tile(floori((global_position.x + velocity.x * 0.3) / 8.0), floori((global_position.y - 2.0 + velocity.y * 0.3) / 8.0))
	if ahead != T.WATER:
		seen = -seen
	if absf(velocity.x) > 1.0:
		dir = 1 if velocity.x > 0.0 else -1
	_step()


func _ranged(delta: float) -> void:
	var p: Player = level.player
	var dist: float = absf(p.global_position.x - global_position.x)
	var dy: float = p.global_position.y - global_position.y
	var r: Array = RANGED[key]
	var aggro: bool = _think(delta, dist, dy)
	if st == 3:
		t3 -= delta
		_accel_x(0.0, 40.0, delta)
		if t3 <= 0.0:
			st = 0
			cd = float(r[2])
			_shoot(String(r[0]), float(r[3]) * 8.0, float(r[4]) * 8.0)
	elif aggro:
		var range_px: float = float(r[1]) * 8.0
		# keep a little distance: back off when too close, close in when too far
		if dist < 48.0:
			_accel_x(-float(signi(int(p.global_position.x - global_position.x))) * _speed(), 24.0, delta)
		elif dist > range_px * 0.7:
			_chase(aim_x, 1.0, delta)
		else:
			_accel_x(0.0, 30.0, delta)
		dir = 1 if p.global_position.x >= global_position.x else -1
		if ai == "chase" and sees and cd <= 0.0 and dist < range_px and absf(dy) < 80.0:
			st = 3
			t3 = 0.45
	else:
		_wander(delta, 0.45)
	_fall(delta)
	_step()


func _shoot(kind: String, speed: float, grav: float) -> void:
	var p: Player = level.player
	var o: Vector2 = global_position + Vector2(float(dir) * 3.0, -_h * 0.65)
	var t: Vector2 = p.center()
	var dist: float = o.distance_to(t)
	var flight: float = dist / maxf(1.0, speed)
	t.y -= 0.5 * grav * flight * flight
	var v: Vector2 = (t - o).normalized() * speed
	var dmg: float = float(def["dmg"]) * level.spawner.monster_damage_scale()
	level.spawn_projectile({"kind": kind, "pos": o, "vel": v, "dmg": dmg, "gravity": grav, "from_player": false, "life": 5.0, "knock": 5.0})
	Sfx.play("bow" if kind == "arrow" else ("gun" if kind == "bullet" else "flask"), 0.5)


## Pets follow the player, and a dog fights what the player fights
func _pet(delta: float) -> void:
	var p: Player = level.player
	var dist: float = absf(p.global_position.x - global_position.x)
	if stay:
		_accel_x(0.0, 30.0, delta)
	else:
		var target: Mob = null
		if key == "wolf":
			var best: float = 96.0
			for m in level.mobs_near(global_position.x - 96.0, global_position.x + 96.0):
				var mm: Mob = m
				if mm != self and mm.is_hostile() and mm.hp > 0.0 and global_position.distance_to(mm.global_position) < best:
					best = global_position.distance_to(mm.global_position)
					target = mm
		if target != null:
			_chase(target.global_position.x, 1.2, delta)
			if cd <= 0.0 and hit_rect().grow(4.0).intersects(target.hit_rect()):
				target.take_damage({"amount": float(def["dmg"]) + 3.0, "from": global_position, "knock": 5.0, "by_player": false})
				cd = 0.8
		elif dist > 40.0:
			_chase(p.global_position.x, 1.3 if dist > 120.0 else 1.0, delta)
			if dist > 400.0:
				global_position = p.global_position + Vector2(-float(p.facing) * 16.0, -4.0)
		else:
			_accel_x(0.0, 20.0, delta)
	_fall(delta)
	_step()


## Tyrannax under the player: it goes where the stick says
func _ridden(delta: float) -> void:
	var inp: InputState = level.input
	var ix: float = inp.move_x
	if absf(ix) > 0.1:
		dir = 1 if ix > 0.0 else -1
	_accel_x(ix * 9.0 * 8.0, 40.0, delta)
	var jp: bool = inp.jump and not mount_jump_prev
	mount_jump_prev = inp.jump
	if jp and is_on_floor():
		velocity.y = -150.0
	_fall(delta)
	_step()
	level.player.global_position = global_position + Vector2(0, -_h + 4.0)
	# its bite is the attack button
	if inp.attack_held and cd <= 0.0:
		cd = 0.7
		_strike_mobs(3.5, 3.0, 30.0, 9.0)
		Sfx.play("roar", 0.5)


func _strike_mobs(reach: float, height: float, dmg: float, knock: float) -> void:
	var x0: float = global_position.x if dir > 0 else global_position.x - reach * 8.0 - _w * 0.5
	var x1: float = global_position.x + reach * 8.0 + _w * 0.5 if dir > 0 else global_position.x
	var box := Rect2(x0, global_position.y - height * 8.0, x1 - x0, height * 8.0)
	for m in level.mobs_near(x0 - 16.0, x1 + 16.0):
		var mm: Mob = m
		if mm != self and not mm.tame and box.intersects(mm.hit_rect()):
			mm.take_damage({"amount": dmg, "from": global_position, "knock": knock, "by_player": true})


# ---------------------------------------------------------------------------------------------- bosses

## Ursavor: lumbers after the player, rears up and slams the ground, and charges across the den
func _boss_bear(delta: float) -> void:
	var p: Player = level.player
	var dx: float = p.global_position.x - global_position.x
	special_t -= delta
	if hp < max_hp * 0.5 and phase == 1:
		phase = 2
		level.say("Ursavor is enraged!", 2.0)
		Sfx.play("roar", 1.0)
	match st:
		3:
			t3 -= delta
			_accel_x(0.0, 60.0, delta)
			if t3 <= 0.0:
				st = 4
				t3 = 0.4
				level.add_shake(0.5)
				_strike(3.2, 3.0, float(def["dmg"]), 10.0)
				level.quake_from(global_position, 7, float(def["dmg"]) * 0.5)
		4:
			t3 -= delta
			if t3 <= 0.0:
				st = 0
				cd = 1.4 if phase == 1 else 0.9
		5:
			t3 -= delta
			_accel_x(float(dir) * _speed() * 2.4, 80.0, delta)
			if hit_rect().grow(2.0).intersects(p.body_rect()):
				p.hurt(float(def["dmg"]) * 1.2, global_position.x, 14.0)
			if t3 <= 0.0 or is_on_wall():
				st = 0
				cd = 1.0
		_:
			dir = 1 if dx >= 0.0 else -1
			_chase(p.global_position.x, 1.0, delta)
			if cd <= 0.0 and absf(dx) < _w * 0.5 + 24.0:
				st = 3
				t3 = 0.6
				Sfx.play("roar", 0.6)
			elif cd <= 0.0 and special_t <= 0.0 and absf(dx) > 80.0:
				st = 5
				t3 = 1.3
				special_t = 6.0 if phase == 1 else 4.0
				Sfx.play("roar", 0.8)
	_fall(delta)
	_step()


## Tyrannax: stalks, bites with a long reach, and when hurt roars and charges
func _boss_rex(delta: float) -> void:
	var p: Player = level.player
	var dx: float = p.global_position.x - global_position.x
	special_t -= delta
	if hp < max_hp * 0.5 and phase == 1:
		phase = 2
		Sfx.play("roar", 1.0)
		level.add_shake(0.6)
	match st:
		3:
			t3 -= delta
			_accel_x(0.0, 60.0, delta)
			if t3 <= 0.0:
				st = 4
				t3 = 0.35
				_strike(4.0, 3.5, float(def["dmg"]), 12.0)
		4:
			t3 -= delta
			if t3 <= 0.0:
				st = 0
				cd = 1.2 if phase == 1 else 0.8
		5:
			t3 -= delta
			_accel_x(float(dir) * _speed() * 2.6, 90.0, delta)
			if hit_rect().grow(2.0).intersects(p.body_rect()):
				p.hurt(float(def["dmg"]) * 1.3, global_position.x, 16.0)
			if t3 <= 0.0 or is_on_wall():
				st = 0
				cd = 1.0
		_:
			dir = 1 if dx >= 0.0 else -1
			_chase(p.global_position.x, 1.0, delta)
			if cd <= 0.0 and absf(dx) < _w * 0.5 + 30.0:
				st = 3
				t3 = 0.5
			elif cd <= 0.0 and special_t <= 0.0 and absf(dx) > 96.0:
				st = 5
				t3 = 1.5
				special_t = 5.0
				Sfx.play("roar", 0.9)
	_fall(delta)
	_step()


## The Crystal Sentinel: floats over its altar, throws volleys of crystal shards, and slams down
func _boss_sentinel(delta: float) -> void:
	var p: Player = level.player
	special_t -= delta
	var target: Vector2 = home + Vector2(sin(anim_t * 0.7) * 48.0, -24.0 + sin(anim_t * 1.9) * 6.0)
	velocity = velocity.lerp((target - global_position) * 2.0, minf(1.0, delta * 2.0))
	dir = 1 if p.global_position.x >= global_position.x else -1
	if special_t <= 0.0 and not p.dead and global_position.distance_to(p.global_position) < 240.0:
		special_t = 2.2 if hp > max_hp * 0.5 else 1.4
		var n: int = 3 if hp > max_hp * 0.5 else 5
		var base: float = (p.center() - center()).angle()
		for k in range(n):
			var a: float = base + (float(k) - float(n - 1) * 0.5) * 0.22
			level.spawn_projectile({"kind": "shard", "pos": center(), "vel": Vector2(cos(a), sin(a)) * 150.0, "dmg": float(def["dmg"]) * 0.6,
				"gravity": 0.0, "from_player": false, "life": 3.0, "knock": 5.0})
		Sfx.play("digCrystal", 0.8)
	_step()


## The Hollow Warden: hovers, marks the ground where it will strike (step out of the glow), and
## sweeps its scythe when close; half beaten, it strikes in rows
func _boss_warden(delta: float) -> void:
	var p: Player = level.player
	special_t -= delta
	if hp < max_hp * 0.5 and phase == 1:
		phase = 2
		level.say("The Warden's hollow grows cold...", 2.5)
	var dx: float = p.global_position.x - global_position.x
	dir = 1 if dx >= 0.0 else -1
	var target := Vector2(p.global_position.x - float(dir) * 40.0, p.global_position.y - 30.0 + sin(anim_t * 1.3) * 8.0)
	velocity = velocity.lerp((target - global_position).limit_length(_speed()), minf(1.0, delta * 1.5))
	if special_t <= 0.0 and not p.dead:
		special_t = 3.2 if phase == 1 else 2.2
		var marks: Array = [p.global_position.x]
		if phase == 2:
			marks = [p.global_position.x - 32.0, p.global_position.x, p.global_position.x + 32.0]
		for mx in marks:
			level.danger_zone(Vector2(float(mx), p.global_position.y), 16.0, 0.9, float(def["dmg"]))
		Sfx.play("strikeWarn", 0.8)
	if cd <= 0.0 and global_position.distance_to(p.global_position) < 48.0:
		cd = 1.6
		_strike(3.0, 4.6, float(def["dmg"]) * 0.8, 9.0)
		level.effects.swing_trail(center(), 0.0 if dir > 0 else PI, 32.0, 1.2, "slash", 0x9A5AE0)
	_step()


# ---------------------------------------------------------------------------------------------- the sprite

func _animate() -> void:
	var meta: Dictionary = Art.creature_meta(key, (1 if sheared else 0) if key == "sheep" else ((1 if tame else 0) if key == "wolf" else variant))
	var w: float = float(meta["w"])
	var cc: float = float(meta["center"])
	var foot: float = float(meta["foot"])
	var left: bool = dir < 0
	sprite.flip_h = left
	sprite.offset = Vector2(-(w - cc) if left else -cc, -(foot + 1.0))
	var sf: SpriteFrames = sprite.sprite_frames
	var anim: String = "idle"
	if st >= 3 and sf.has_animation("attack"):
		anim = "attack"
	elif sf.has_animation("move") and (bool(def["flying"]) or in_water):
		anim = "move"
	elif not is_on_floor() and not bool(def["flying"]) and sf.has_animation("air"):
		anim = "air"
	elif absf(velocity.x) > 4.0:
		anim = "walk"
	elif sf.has_animation("alt") and int(anim_t * 0.5) % 4 == 3:
		anim = "alt"
	if sprite.animation != anim:
		sprite.play(anim)
	sprite.speed_scale = clampf(absf(velocity.x) / maxf(8.0, _speed()), 0.6, 1.6) if anim == "walk" else 1.0
	var lt: float = level.lighting.level_at(center())
	var c := Color(lt, lt, lt, 1.0)
	if flash_t > 0.0:
		c = Color(2.6, 2.6, 2.6, 1.0)
	elif burn > 0.0:
		c = Color(lt * 1.3, lt * 0.8, lt * 0.6, 1.0)
	modulate = c
