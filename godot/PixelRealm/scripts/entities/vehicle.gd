class_name Vehicle
extends CharacterBody2D
## A car, rowboat or motorboat placed from its kit. Tap it to get in; the walking stick drives it and
## JUMP gets out (when it has stopped). Cars climb single blocks; boats float and only move on water.

@onready var spr: Sprite2D = $Sprite

var level: Level = null
var kind: String = "car"
var rider: bool = false
var exit_prev: bool = false


func setup(lv: Level, k: String) -> void:
	level = lv
	kind = k


func _ready() -> void:
	spr.texture = Art.tex("res://assets/sprites/%s.png" % kind)
	spr.centered = false
	spr.offset = Vector2(-16, -float(spr.texture.get_height()))
	collision_layer = 32
	collision_mask = 3


func is_boat() -> bool:
	return kind != "car"


func hit_rect() -> Rect2:
	return Rect2(global_position.x - 16.0, global_position.y - 16.0, 32.0, 16.0)


func _physics_process(delta: float) -> void:
	if level == null:
		return
	var w: WorldData = level.world
	var on_water: bool = w.get_tile(floori(global_position.x / 8.0), floori((global_position.y - 2.0) / 8.0)) == T.WATER
	var ix: float = 0.0
	if rider:
		ix = level.input.move_x
		var jp: bool = level.input.jump and not exit_prev
		exit_prev = level.input.jump
		if jp and absf(velocity.x) < 20.0:
			level.dismount()
	var top: float = 90.0 if kind == "car" else (70.0 if kind == "motorboat" else 40.0)
	if is_boat():
		if on_water:
			velocity.y = move_toward(velocity.y, -20.0, 400.0 * delta)
			velocity.x = move_toward(velocity.x, ix * top, 80.0 * delta)
		else:
			velocity.y = minf(velocity.y + 272.0 * delta, 208.0)
			velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
	else:
		velocity.y = minf(velocity.y + 272.0 * delta, 208.0)
		velocity.x = move_toward(velocity.x, ix * top, (120.0 if ix != 0.0 else 160.0) * delta)
		if is_on_floor() and is_on_wall() and ix != 0.0:
			global_position.y -= 8.2
	if ix != 0.0:
		spr.flip_h = ix < 0.0
	move_and_slide()
	if rider:
		level.player.global_position = global_position + Vector2(0, -10)
		Sfx.set_loop("engine", 0.5 if (kind != "boat" and absf(velocity.x) > 5.0) else 0.0)
	var lt: float = level.lighting.level_at(global_position + Vector2(0, -8))
	spr.modulate = Color(lt, lt, lt, 1.0)
