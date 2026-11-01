class_name Projectile
extends Node2D
## Anything flying: arrows, crossbow bolts, bullets, blunderbuss pellets, slung stones, bombs, fire
## flasks, and the monsters' arrows, fireballs, crystal shards and orbs. Each moves with its own
## gravity, is stopped by solid blocks, and hits the first creature (or the player) its path crosses.

@onready var spr: Sprite2D = $Sprite

var level: Level = null
var kind: String = "arrow"
var vel := Vector2.ZERO
var dmg: float = 5.0
var gravity_px: float = 0.0
var from_player: bool = true
var life: float = 5.0
var knock: float = 4.0
var pierce: int = 1
var glow: int = 0
var stuck: float = -1.0
var _hit := []

const TEX := {"arrow": "arrow", "bolt": "bolt", "bullet": "bullet", "pellet": "bullet", "stone": "stone", "bomb": "bomb",
	"flask": "flask", "fireball": "fireball", "shard": "shard", "orb": "orb"}


func setup(lv: Level, p: Dictionary) -> void:
	level = lv
	kind = String(p.get("kind", "arrow"))
	global_position = p.get("pos", Vector2.ZERO)
	vel = p.get("vel", Vector2.ZERO)
	dmg = float(p.get("dmg", 5.0))
	gravity_px = float(p.get("gravity", 0.0))
	from_player = bool(p.get("from_player", true))
	life = float(p.get("life", 5.0))
	knock = float(p.get("knock", 4.0))
	pierce = int(p.get("pierce", 1))
	if kind == "fireball" or kind == "flask":
		glow = 10
	elif kind == "shard" or kind == "orb":
		glow = 8


func _ready() -> void:
	spr.texture = Art.tex("res://assets/sprites/projectiles/%s.png" % String(TEX.get(kind, "arrow")))
	z_index = 2


func _physics_process(delta: float) -> void:
	if level == null:
		return
	life -= delta
	if stuck >= 0.0:
		stuck += delta
		modulate.a = clampf(1.0 - (stuck - 1.5) / 0.5, 0.0, 1.0)
		if stuck > 2.0:
			queue_free()
		return
	if life <= 0.0:
		if kind == "bomb":
			level.explode(global_position, 3.6, dmg, from_player, true)
		elif kind == "flask":
			level.fire_burst(global_position, from_player)
		queue_free()
		return
	vel.y += gravity_px * delta
	var from: Vector2 = global_position
	var to: Vector2 = from + vel * delta
	# blocks
	var steps: int = maxi(1, ceili(from.distance_to(to) / 3.0))
	for i in range(1, steps + 1):
		var p: Vector2 = from.lerp(to, float(i) / float(steps))
		var t: int = level.world.get_tile(floori(p.x / 8.0), floori(p.y / 8.0))
		if DB.solid[t] == 1 or (kind != "bullet" and kind != "pellet" and DB.leaf[t] == 1 and vel.y > 0.0 and randf() < 0.0):
			global_position = p
			_hit_block()
			return
		if _hit_things(p):
			return
	global_position = to
	rotation = vel.angle() if kind in ["arrow", "bolt", "bullet", "pellet"] else rotation + delta * 8.0
	var lt: float = level.lighting.level_at(global_position) if glow == 0 else 1.0
	modulate = Color(lt, lt, lt, modulate.a)


func _hit_block() -> void:
	match kind:
		"bomb":
			vel = Vector2(-vel.x * 0.3, -vel.y * 0.3)
			global_position -= vel.normalized() * 2.0
			return
		"flask":
			level.fire_burst(global_position, from_player)
			queue_free()
		"arrow", "bolt":
			Sfx.play("arrowHit", 0.4)
			stuck = 0.0
		_:
			level.effects.burst(global_position, Color(0.8, 0.8, 0.8), 3, 20.0, 0.3)
			queue_free()


func _hit_things(p: Vector2) -> bool:
	if from_player:
		for m in level.mobs_near(p.x - 40.0, p.x + 40.0):
			var mm: Mob = m
			if mm.hp <= 0.0 or mm.tame or _hit.has(mm):
				continue
			if mm.hit_rect().grow(1.0).has_point(p):
				_hit.append(mm)
				if kind == "flask":
					level.fire_burst(p, true)
					queue_free()
					return true
				if kind == "bomb":
					level.explode(p, 3.6, dmg, true, true)
					queue_free()
					return true
				var info := {"amount": dmg, "from": p - vel.normalized() * 8.0, "knock": knock, "by_player": true}
				if kind == "stone":
					info["daze"] = 0.0
				mm.take_damage(info)
				Sfx.play("arrowHit", 0.5)
				pierce -= 1
				if pierce <= 0:
					queue_free()
					return true
		return false
	var pl: Player = level.player
	if not pl.dead and pl.body_rect().grow(0.8).has_point(p):
		pl.hurt(dmg, p.x - vel.x, knock)
		if kind == "fireball":
			pl.burn = maxf(pl.burn, 1.5)
		queue_free()
		return true
	return false
