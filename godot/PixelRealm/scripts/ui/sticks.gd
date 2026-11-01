class_name Stick
extends Control
## An on-screen stick that follows its own finger, so several can be held at once. As the walking
## stick it reports a direction (left/right with a small dead zone and most of the range at full
## speed, as in the Swift game; up and down for ladders and dropping through platforms). As the
## attack stick (Terraria-style): touch and hold attacks; with the thumb in the middle the game picks
## the target, and sliding it out past the dead zone aims by hand in any direction, shown by an arrow.
## Letting go stops.

signal moved(v: Vector2)
signal released

var attack: bool = false
var radius: float = 66.0
var label: String = ""
var thumb := Vector2.ZERO
var held: bool = false
var manual: bool = false
var _touch: int = -1
var _base: Texture2D
var _knob: Texture2D
var _arrow: Texture2D
var _font: Font


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	_base = Art.tex("res://assets/ui/stick_base_attack.png" if attack else "res://assets/ui/stick_base.png")
	_knob = Art.tex("res://assets/ui/stick_thumb_attack.png" if attack else "res://assets/ui/stick_thumb.png")
	_arrow = Art.tex("res://assets/ui/stick_arrow.png")
	_font = ThemeDB.fallback_font


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed and _touch == -1:
			_touch = st.index
			_move_to(st.position)
		elif not st.pressed and st.index == _touch:
			_release()
		accept_event()
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		if sd.index == _touch:
			_move_to(sd.position)
		accept_event()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.device != -1 and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_touch = -2
				_move_to(mb.position)
			elif _touch == -2:
				_release()
		accept_event()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if mm.device != -1 and _touch == -2:
			_move_to(mm.position)
		accept_event()


func _move_to(p: Vector2) -> void:
	var c: Vector2 = size * 0.5
	var v: Vector2 = p - c
	if v.length() > radius:
		v = v.normalized() * radius
	thumb = v
	held = true
	var out: Vector2 = v / radius
	if attack:
		var power: float = out.length()
		manual = power > (0.17 if manual else 0.26)
	moved.emit(out)
	queue_redraw()


func _release() -> void:
	_touch = -1
	thumb = Vector2.ZERO
	held = false
	manual = false
	released.emit()
	queue_redraw()


## Lets go without a finger lifting (a panel opened over the controls)
func release_now() -> void:
	if held or _touch != -1:
		_release()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release_now()


## The walking stick's output: snappy left/right (most of the range is full speed), raw up/down
static func walk_vector(v: Vector2) -> Vector2:
	var sx: float = v.x
	if absf(sx) < 0.18:
		sx = 0.0
	var mag: float = minf(1.0, absf(sx) * 1.35)
	return Vector2(mag if sx >= 0.0 else -mag, v.y)


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var d: float = radius * 2.0
	var ring := Color(1, 1, 1, 1.0 if held else 0.8)
	draw_texture_rect(_base, Rect2(c - Vector2(radius, radius), Vector2(d, d)), false, ring)
	if attack and manual and thumb.length() > 1.0:
		var u: Vector2 = thumb.normalized()
		var tip: Vector2 = c + u * radius * 0.86
		var col := Color(1.0, 0.88, 0.5, 0.9)
		draw_line(c + u * radius * 0.26, tip, col, 4.0)
		var n := Vector2(-u.y, u.x)
		draw_colored_polygon(PackedVector2Array([c + u * radius * 1.02, tip + n * 9.0, tip - n * 9.0]), col)
	var k: float = radius * 0.46
	var kc: Color = Color(1, 1, 1, 1.0 if held else 0.75)
	draw_texture_rect(_knob, Rect2(c + thumb - Vector2(k, k), Vector2(k * 2.0, k * 2.0)), false, kc)
	if attack and not held and label != "":
		var tw: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var p := Vector2(c.x - tw * 0.5, c.y + radius + 18.0)
		draw_string_outline(_font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.85))
		draw_string(_font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.92, 0.75))
