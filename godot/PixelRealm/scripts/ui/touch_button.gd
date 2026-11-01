class_name TouchButton
extends Control
## An on-screen button made for touch: it follows its own finger (so it works while other fingers hold
## the sticks), reports when it goes down and up, and a tap. It also works with a mouse. Drawn as a
## pixel-art box with an icon, a label, or an item and its count.

signal pressed_changed(down: bool)
signal tapped

var text: String = ""
var icon: Texture2D = null
var color := Color(0.42, 0.42, 0.42)
var font_size: int = 18
var down: bool = false
## an item shown inside (hotbar slots): id, count, shots loaded, magazine size
var item_id: String = ""
var item_count: int = 0
var item_ammo: String = ""
var selected: bool = false
var slot_style: bool = false
var _touch: int = -1
var _box: StyleBoxTexture
var _font: Font


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_box = StyleBoxTexture.new()
	_box.texture = Art.tex("res://assets/ui/slot.png" if slot_style else "res://assets/ui/button.png")
	_box.set_texture_margin_all(3)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed and _touch == -1:
			_touch = st.index
			_set_down(true)
		elif not st.pressed and st.index == _touch:
			_touch = -1
			_set_down(false)
			if Rect2(Vector2.ZERO, size).grow(24.0).has_point(st.position):
				tapped.emit()
		accept_event()
	elif event is InputEventScreenDrag:
		accept_event()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.device == -1 or mb.button_index != MOUSE_BUTTON_LEFT:
			accept_event()
			return
		if mb.pressed:
			_touch = -2
			_set_down(true)
		elif _touch == -2:
			_touch = -1
			_set_down(false)
			if Rect2(Vector2.ZERO, size).has_point(mb.position):
				tapped.emit()
		accept_event()


func _set_down(d: bool) -> void:
	if down == d:
		return
	down = d
	pressed_changed.emit(d)
	queue_redraw()


## Lets go without a finger lifting (a panel opened over the controls)
func release() -> void:
	_touch = -1
	if down:
		_set_down(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release()


func set_item(id: String, count: int, ammo: String = "") -> void:
	if id == item_id and count == item_count and ammo == item_ammo:
		return
	item_id = id
	item_count = count
	item_ammo = ammo
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var c: Color = color.darkened(0.35) if down else color
	_box.modulate_color = c
	draw_style_box(_box, r)
	if selected:
		draw_rect(r.grow(-1.0), Color(1, 1, 1, 0.95), false, 3.0)
	if icon != null:
		var s: float = minf(size.x, size.y) * (0.5 if text == "" else 0.4)
		var ip := Vector2((size.x - s) * 0.5, (size.y - s) * 0.5 - (8.0 if text != "" else 0.0))
		draw_texture_rect(icon, Rect2(ip, Vector2(s, s)), false)
	if item_id != "":
		var s2: float = minf(size.x, size.y) * 0.78
		draw_texture_rect(Art.icon(item_id), Rect2((size - Vector2(s2, s2)) * 0.5, Vector2(s2, s2)), false)
		if item_count > 1:
			_text_at(str(item_count), Vector2(size.x - 3.0, size.y - 3.0), 13, Color.WHITE, true)
		if item_ammo != "":
			_text_at(item_ammo, Vector2(3.0, size.y - 3.0), 11, Color(1.0, 0.88, 0.5), false)
	if text != "":
		var fs: int = font_size
		var tw: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var y: float = size.y * 0.5 + float(fs) * 0.35 + (10.0 if icon != null else 0.0)
		draw_string_outline(_font, Vector2((size.x - tw) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
		draw_string(_font, Vector2((size.x - tw) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _text_at(s: String, p: Vector2, fs: int, c: Color, right: bool) -> void:
	var tw: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(p.x - tw if right else p.x, p.y)
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.9))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
