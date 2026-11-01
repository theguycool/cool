class_name ScrollList
extends Control
## A list that scrolls with a finger (with a flick it keeps gliding), the mouse wheel or a mouse drag,
## and reports taps on a row or on one of the buttons drawn at its right end. Rows are dictionaries:
##   "kind": "row" (default), "header" (a yellow section title) or "text" (wrapped text, no box)
##   "text", "sub": the main line and a smaller line under it (both wrap)
##   "icon": a Texture2D drawn at the left; "icons": [[Texture2D, label, Color], ...] drawn under the text
##   "buttons": [[label, Color], ...] drawn at the right; "toggle": true/false draws an ON/OFF switch
##   "color", "sub_color", "bg": colours; "selected": a white frame
## Built for touch: a press that moves more than a few pixels scrolls instead of tapping.

signal row_tapped(index: int, button: int)

var rows: Array = []
var scroll: float = 0.0
var font_size: int = 15
var sub_size: int = 12
var text_color := Color.WHITE
var sub_color := Color(1, 1, 1, 0.72)
var header_color := Color(1.0, 0.88, 0.4)
var row_bg := Color(0, 0, 0, 0.28)
var pad: float = 6.0
var spacing: float = 4.0
var icon_size: float = 32.0
var button_h: float = 34.0

var _font: Font
var _tops: Array = []
var _heights: Array = []
var _buttons: Array = []
var _content_h: float = 0.0
var _layout_w: float = -1.0
var _touch: int = -1
var _press_pos := Vector2.ZERO
var _press_scroll: float = 0.0
var _moved: bool = false
var _vel: float = 0.0
var _box: StyleBoxFlat


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_box = StyleBoxFlat.new()
	_box.set_border_width_all(2)
	_box.border_color = Color(0, 0, 0, 0.6)
	resized.connect(_on_resized)


func _on_resized() -> void:
	_layout_w = -1.0
	queue_redraw()


func set_rows(r: Array, keep_scroll: bool = false) -> void:
	rows = r
	_layout_w = -1.0
	if not keep_scroll:
		scroll = 0.0
		_vel = 0.0
	queue_redraw()


# ---------------------------------------------------------------------------------------------- layout

func _button_w(label: String) -> float:
	return maxf(60.0, _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 24.0)


func _ensure_layout() -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	if is_equal_approx(_layout_w, size.x) and _tops.size() == rows.size():
		return
	_layout_w = size.x
	_tops.clear()
	_heights.clear()
	_buttons.clear()
	var y: float = 0.0
	var w: float = size.x - 8.0
	for r in rows:
		var row: Dictionary = r
		var kind: String = String(row.get("kind", "row"))
		var h: float = 0.0
		var btns: Array = []
		if kind == "header":
			h = float(font_size) + 14.0
		else:
			var tw: float = w - pad * 2.0
			if row.has("icon"):
				tw -= icon_size + 8.0
			var bx: float = w - pad
			var labels: Array = []
			if row.has("toggle"):
				labels.append("OFF")
			for b in row.get("buttons", []):
				labels.append(String((b as Array)[0]))
			for lb in labels:
				var bw: float = _button_w(String(lb))
				bx -= bw
				btns.append(Rect2(bx, 0.0, bw, button_h))
				bx -= 6.0
			if not labels.is_empty():
				tw = bx - pad - (icon_size + 8.0 if row.has("icon") else 0.0)
			tw = maxf(60.0, tw)
			var th: float = _font.get_multiline_string_size(String(row.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, tw, font_size).y
			if String(row.get("sub", "")) != "":
				th += 2.0 + _font.get_multiline_string_size(String(row["sub"]), HORIZONTAL_ALIGNMENT_LEFT, tw, sub_size).y
			if row.has("icons"):
				th += 20.0
			h = maxf(th, icon_size if row.has("icon") else 0.0)
			if not labels.is_empty():
				h = maxf(h, button_h)
			h += pad * 2.0
			# centre the buttons in the row
			for k in range(btns.size()):
				var br: Rect2 = btns[k]
				br.position.y = (h - button_h) * 0.5
				btns[k] = br
		_tops.append(y)
		_heights.append(h)
		_buttons.append(btns)
		y += h + (0.0 if kind == "text" else spacing)
	_content_h = y
	_clamp_scroll()


func _max_scroll() -> float:
	return maxf(0.0, _content_h - size.y)


func _clamp_scroll() -> void:
	scroll = clampf(scroll, 0.0, _max_scroll())


func scroll_to_end() -> void:
	_ensure_layout()
	scroll = _max_scroll()
	queue_redraw()


# ---------------------------------------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed and _touch == -1:
			_touch = st.index
			_press(st.position)
		elif not st.pressed and st.index == _touch:
			_release(st.position)
		accept_event()
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		if sd.index == _touch:
			_drag(sd.position, -sd.velocity.y)
		accept_event()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.device == -1:
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			scroll -= 48.0
			_clamp_scroll()
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			scroll += 48.0
			_clamp_scroll()
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _touch == -1:
				_touch = -2
				_press(mb.position)
			elif not mb.pressed and _touch == -2:
				_release(mb.position)
		accept_event()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if mm.device != -1 and _touch == -2:
			_drag(mm.position, -mm.velocity.y)
		accept_event()


func _press(p: Vector2) -> void:
	_press_pos = p
	_press_scroll = scroll
	_moved = false
	_vel = 0.0


func _drag(p: Vector2, vel: float) -> void:
	var dy: float = p.y - _press_pos.y
	if not _moved and absf(dy) > 9.0:
		_moved = true
		_press_pos = p
		_press_scroll = scroll
		dy = 0.0
	if _moved:
		scroll = _press_scroll - dy
		_clamp_scroll()
		_vel = vel
		queue_redraw()


func _release(p: Vector2) -> void:
	_touch = -1
	if not _moved:
		_vel = 0.0
		_tap(p)


## Lets go of a finger that will never lift here (the list is being hidden)
func cancel_touch() -> void:
	_touch = -1
	_vel = 0.0


func _tap(p: Vector2) -> void:
	_ensure_layout()
	var y: float = p.y + scroll
	for i in range(rows.size()):
		var top: float = _tops[i]
		if y >= top and y < top + float(_heights[i]):
			var local := Vector2(p.x, y - top)
			var btns: Array = _buttons[i]
			for k in range(btns.size()):
				if (btns[k] as Rect2).grow(4.0).has_point(local):
					row_tapped.emit(i, k)
					return
			row_tapped.emit(i, -1)
			return


func _process(delta: float) -> void:
	if _touch == -1 and absf(_vel) > 8.0:
		scroll += _vel * delta
		_vel *= exp(-5.0 * delta)
		var before: float = scroll
		_clamp_scroll()
		if not is_equal_approx(before, scroll):
			_vel = 0.0
		queue_redraw()


# ---------------------------------------------------------------------------------------------- drawing

func _draw() -> void:
	_ensure_layout()
	var w: float = size.x - 8.0
	for i in range(rows.size()):
		var top: float = float(_tops[i]) - scroll
		var h: float = float(_heights[i])
		if top + h < 0.0 or top > size.y:
			continue
		_draw_row(i, rows[i], top, h, w)
	if _content_h > size.y + 1.0:
		var bh: float = maxf(24.0, size.y * size.y / _content_h)
		var by: float = (size.y - bh) * (scroll / maxf(1.0, _max_scroll()))
		draw_rect(Rect2(size.x - 5.0, by, 4.0, bh), Color(1, 1, 1, 0.35))


func _draw_row(i: int, row: Dictionary, top: float, h: float, w: float) -> void:
	var kind: String = String(row.get("kind", "row"))
	var col: Color = row.get("color", text_color)
	if kind == "header":
		var hc: Color = row.get("color", header_color)
		draw_string(_font, Vector2(pad, top + h - 9.0), String(row.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, hc)
		return
	if kind != "text":
		var bg: Color = row.get("bg", row_bg)
		draw_rect(Rect2(0, top, w, h), bg)
		if bool(row.get("selected", false)):
			draw_rect(Rect2(1, top + 1, w - 2, h - 2), Color(1, 1, 1, 0.9), false, 2.0)
	var x: float = pad
	if row.has("icon") and row["icon"] != null:
		var ic: Texture2D = row["icon"]
		draw_texture_rect(ic, Rect2(x, top + (h - icon_size) * 0.5, icon_size, icon_size), false, Color(1, 1, 1, 0.5) if bool(row.get("dim", false)) else Color.WHITE)
		x += icon_size + 8.0
	var btns: Array = _buttons[i]
	var right: float = w - pad
	if not btns.is_empty():
		right = (btns[btns.size() - 1] as Rect2).position.x - 6.0
	var tw: float = maxf(60.0, right - x)
	var ty: float = top + pad
	var text: String = String(row.get("text", ""))
	if text != "":
		draw_multiline_string(_font, Vector2(x, ty + _font.get_ascent(font_size)), text, HORIZONTAL_ALIGNMENT_LEFT, tw, font_size, -1, col)
		ty += _font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, tw, font_size).y
	var sub: String = String(row.get("sub", ""))
	if sub != "":
		ty += 2.0
		var sc: Color = row.get("sub_color", sub_color)
		draw_multiline_string(_font, Vector2(x, ty + _font.get_ascent(sub_size)), sub, HORIZONTAL_ALIGNMENT_LEFT, tw, sub_size, -1, sc)
		ty += _font.get_multiline_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, tw, sub_size).y
	if row.has("icons"):
		var ix: float = x
		for e in row["icons"]:
			var a: Array = e
			var t: Texture2D = a[0]
			draw_texture_rect(t, Rect2(ix, ty + 2.0, 16, 16), false)
			ix += 18.0
			var lc: Color = a[2]
			var label: String = String(a[1])
			draw_string(_font, Vector2(ix, ty + 15.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, lc)
			ix += _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 8.0
	# buttons (the toggle switch is the first one)
	var labels: Array = []
	var colors: Array = []
	if row.has("toggle"):
		var on: bool = bool(row["toggle"])
		labels.append("ON" if on else "OFF")
		colors.append(Color(0.31, 0.54, 0.24) if on else Color(0.33, 0.33, 0.33))
	for b in row.get("buttons", []):
		var ba: Array = b
		labels.append(String(ba[0]))
		colors.append(ba[1])
	for k in range(mini(labels.size(), btns.size())):
		var br: Rect2 = btns[k]
		var r := Rect2(br.position + Vector2(0, top), br.size)
		_box.bg_color = colors[k]
		draw_style_box(_box, r)
		var lw: float = _font.get_string_size(String(labels[k]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string_outline(_font, Vector2(r.position.x + (r.size.x - lw) * 0.5, r.position.y + r.size.y * 0.5 + 5.0), String(labels[k]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color(0, 0, 0, 0.8))
		draw_string(_font, Vector2(r.position.x + (r.size.x - lw) * 0.5, r.position.y + r.size.y * 0.5 + 5.0), String(labels[k]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
