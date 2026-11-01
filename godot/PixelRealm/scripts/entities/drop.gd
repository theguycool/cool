class_name Drop
extends Area2D
## An item lying in the world: it falls, bounces a little, slides toward the player when they come
## near and is picked up when it touches them. Stacks of the same item lying together merge.

@onready var icon_sprite: Sprite2D = $Icon

var level: Level = null
var item_id: String = ""
var count: int = 1
var extra: int = 0
var vel := Vector2.ZERO
var age: float = 0.0
var pick_delay: float = 0.4
var on_ground: bool = false


func setup(lv: Level, id: String, n: int, ex: int = 0) -> void:
	level = lv
	item_id = id
	count = n
	extra = ex


func _ready() -> void:
	icon_sprite.texture = Art.icon(item_id)
	icon_sprite.scale = Vector2(0.6, 0.6)
	icon_sprite.position = Vector2(0, -5)


func _physics_process(delta: float) -> void:
	if level == null:
		return
	age += delta
	pick_delay = maxf(0.0, pick_delay - delta)
	if age > 300.0:
		queue_free()
		return
	var p: Player = level.player
	var to_p: Vector2 = p.center() - global_position
	if pick_delay <= 0.0 and not p.dead and to_p.length() < 24.0 and p.inv.can_fit(item_id, 1):
		vel = vel.lerp(to_p.normalized() * 120.0, minf(1.0, delta * 8.0))
		global_position += vel * delta
		if to_p.length() < 6.0:
			collect(p)
		return
	var w: WorldData = level.world
	vel.y = minf(vel.y + 272.0 * delta, 160.0)
	var nx: float = global_position.x + vel.x * delta
	if w.solid(floori(nx / 8.0), floori((global_position.y - 2.0) / 8.0)):
		vel.x = -vel.x * 0.3
		nx = global_position.x
	var ny: float = global_position.y + vel.y * delta
	var below: int = w.get_tile(floori(nx / 8.0), floori(ny / 8.0))
	on_ground = false
	if DB.solid[below] == 1 or (DB.platform[below] == 1 and vel.y > 0.0):
		ny = floorf(ny / 8.0) * 8.0
		vel.y = -vel.y * 0.25 if absf(vel.y) > 40.0 else 0.0
		vel.x *= 0.6
		on_ground = true
	elif DB.liquid[below] == 1:
		vel.y = minf(vel.y, 20.0)
		vel.x *= 0.95
	global_position = Vector2(nx, ny)
	icon_sprite.position.y = -5.0 + (sin(age * 3.0) * 1.0 if on_ground else 0.0)
	var lt: float = level.lighting.level_at(global_position)
	icon_sprite.modulate = Color(lt, lt, lt, 1.0)
	if int(age * 4.0) != int((age - delta) * 4.0):
		_merge()


func _merge() -> void:
	for e in get_parent().get_children():
		if e == self or not (e is Drop):
			continue
		var d: Drop = e
		if d.item_id == item_id and d.extra == extra and d.global_position.distance_to(global_position) < 10.0 and not d.is_queued_for_deletion():
			var ms: int = DB.max_stack(item_id)
			if count + d.count <= ms:
				count += d.count
				d.queue_free()


func collect(p: Player) -> void:
	if pick_delay > 0.0 or is_queued_for_deletion():
		return
	var left: int = p.inv.add(item_id, count, extra)
	if left < count:
		Sfx.play("pickup", 0.5)
		level.journal.note_item(item_id, count - left)
		level.hud_dirty = true
	if left <= 0:
		queue_free()
	else:
		count = left
