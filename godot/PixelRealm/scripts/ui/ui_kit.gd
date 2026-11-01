class_name UIKit
## The shared look of the panels and menus (pixel-art boxes, buttons and text) and small helpers to
## build them in code: a dimmed backdrop, a framed box, a title row, buttons, labels and toggles.

static var _theme: Theme = null


## One theme for every panel: the button art from the game, white outlined text
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = ThemeDB.fallback_font
	t.default_font_size = 16
	t.set_stylebox("normal", "Button", button_box(Color(0.42, 0.42, 0.42)))
	t.set_stylebox("hover", "Button", button_box(Color(0.5, 0.5, 0.5)))
	t.set_stylebox("pressed", "Button", button_box(Color(0.27, 0.27, 0.27)))
	t.set_stylebox("disabled", "Button", button_box(Color(0.3, 0.3, 0.3, 0.6)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(0.9, 0.9, 0.9))
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.5))
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Button", 4)
	t.set_color("font_color", "Label", Color.WHITE)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 4)
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0, 0, 0, 0.75)
	le.set_border_width_all(2)
	le.border_color = Color(1, 1, 1, 0.35)
	le.set_content_margin_all(8)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le)
	t.set_color("font_color", "LineEdit", Color.WHITE)
	t.set_font_size("font_size", "LineEdit", 18)
	_theme = t
	return t


## The game's 9-slice button art tinted to a colour
static func button_box(c: Color) -> StyleBoxTexture:
	var b := StyleBoxTexture.new()
	b.texture = Art.tex("res://assets/ui/button.png")
	b.set_texture_margin_all(3)
	b.set_content_margin_all(6)
	b.content_margin_left = 12
	b.content_margin_right = 12
	b.modulate_color = c
	return b


## A framed box for a panel's body (dark, or parchment for the journal and the map)
static func frame_box(parchment: bool = false) -> StyleBox:
	if parchment:
		var p := StyleBoxFlat.new()
		p.bg_color = Color(0.91, 0.83, 0.63)
		p.set_border_width_all(4)
		p.border_color = Color(0.35, 0.23, 0.1)
		p.set_content_margin_all(16)
		return p
	var b := StyleBoxTexture.new()
	b.texture = Art.tex("res://assets/ui/panel.png")
	b.set_texture_margin_all(4)
	b.set_content_margin_all(14)
	b.modulate_color = Color(1, 1, 1, 0.98)
	return b


static func button(text: String, col: Color, cb: Callable, min_w: float = 0.0, h: float = 40.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", button_box(col))
	b.add_theme_stylebox_override("hover", button_box(col.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", button_box(col.darkened(0.3)))
	b.custom_minimum_size = Vector2(min_w, h)
	b.pressed.connect(cb)
	b.pressed.connect(func() -> void: Sfx.play("tap", 0.5))
	return b


static func label(text: String, fs: int = 16, col: Color = Color.WHITE, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Ink-coloured text for parchment pages (no outline)
static func ink(text: String, fs: int = 16, col: Color = Color(0.23, 0.14, 0.06)) -> Label:
	var l: Label = label(text, fs, col)
	l.add_theme_constant_override("outline_size", 0)
	return l


static func hbox(sep: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A title with buttons on its right, as at the top of every panel
static func title_row(title: String, fs: int = 22, col: Color = Color.WHITE) -> HBoxContainer:
	var row: HBoxContainer = hbox(6)
	var l: Label = label(title, fs, col)
	row.add_child(l)
	row.add_child(spacer())
	return row


## Rows for the settings list (shared by the pause menu and the main menu): [row, key, kind, step...]
static func settings_rows() -> Array:
	var out: Array = []
	out.append({"kind": "header", "text": "CONTROLS"})
	out.append(_toggle("On-screen touch controls", "touch_controls"))
	out.append(_toggle("Swap the sticks (attack on the left)", "swap_sticks"))
	out.append(_toggle("Bow and throw trajectory preview", "trajectory"))
	out.append({"kind": "header", "text": "SCREEN"})
	out.append(_stepper("Zoom", "zoom", 0.5, 2.0, 7.0, "x%.1f"))
	out.append(_toggle("Smooth lighting", "smooth_light"))
	out.append(_toggle("Show coordinates, place and weather", "show_coords"))
	out.append(_toggle("Show FPS counter", "show_fps"))
	out.append(_toggle("60 FPS (off = 30, smoother on older iPads)", "fps60"))
	out.append(_stepper("Screen shake", "shake", 0.25, 0.0, 1.0, "%.0f%%", 100.0))
	out.append(_toggle("Gentler lightning flashes", "reduce_flashes"))
	out.append({"kind": "header", "text": "SOUND"})
	out.append(_toggle("Sound", "sound"))
	out.append(_stepper("Effects volume", "sfx_volume", 0.1, 0.0, 1.0, "%.0f%%", 100.0))
	out.append(_stepper("Ambience volume", "ambience_volume", 0.1, 0.0, 1.0, "%.0f%%", 100.0))
	out.append({"kind": "header", "text": "WEATHER AND NIGHTS"})
	out.append(_toggle("Weather (rain, storms, snow, wind)", "weather"))
	out.append(_toggle("Weather can hurt you (lightning, hail, cold)", "weather_hurts"))
	out.append(_toggle("Weather alerts and warnings", "weather_alerts"))
	out.append(_toggle("Rain and snow", "allow_rain"))
	out.append(_toggle("Thunderstorms and lightning", "allow_thunder"))
	out.append(_toggle("Wind and windstorms", "allow_wind"))
	out.append(_toggle("Hail", "allow_hail"))
	out.append(_toggle("Blizzards", "allow_blizzard"))
	out.append(_toggle("Tornadoes", "allow_tornado"))
	out.append(_toggle("Hurricanes", "allow_hurricane"))
	out.append(_toggle("Peaceful (no monsters)", "peaceful"))
	out.append({"kind": "row", "text": "Nights (tap to change)", "key": "night_danger", "choice": ["Calm", "Normal", "Deadly"]})
	out.append({"kind": "header", "text": "GAME"})
	out.append(_toggle("Autosave every minute", "autosave"))
	out.append(_stepper("Abandoned structures (new worlds)", "rare_chance", 0.04, 0.0, 0.8, "%.0f%% of sites", 100.0))
	out.append(_toggle("Build chunks on background threads", "threaded_gen"))
	return out


static func _toggle(text: String, key: String) -> Dictionary:
	return {"kind": "row", "text": text, "key": key, "toggle": bool(Game.setting(key, false))}


static func _stepper(text: String, key: String, step: float, lo: float, hi: float, fmt: String, mul: float = 1.0) -> Dictionary:
	var v: float = float(Game.setting(key, lo))
	return {"kind": "row", "text": text, "sub": fmt % (v * mul), "key": key, "step": step, "lo": lo, "hi": hi, "fmt": fmt,
		"mul": mul, "buttons": [["-", Color(0.42, 0.42, 0.42)], ["+", Color(0.42, 0.42, 0.42)]]}


## Applies a tap on a settings row; returns the refreshed rows
static func settings_tap(rows: Array, i: int, button_index: int) -> Array:
	var row: Dictionary = rows[i]
	if not row.has("key"):
		return rows
	var key: String = String(row["key"])
	if row.has("toggle"):
		Game.set_setting(key, not bool(Game.setting(key, false)))
	elif row.has("choice"):
		var n: int = (row["choice"] as Array).size()
		Game.set_setting(key, (int(Game.setting(key, 1)) + 1) % n)
	elif row.has("step"):
		if button_index < 0:
			return rows
		var v: float = float(Game.setting(key, 0.0))
		var step: float = float(row["step"])
		v += step if button_index == 1 else -step
		v = clampf(snappedf(v, step * 0.5), float(row["lo"]), float(row["hi"]))
		Game.set_setting(key, v)
	Sfx.play("tap", 0.5)
	return fresh_settings_rows()


## The settings list with the current values filled in
static func fresh_settings_rows() -> Array:
	var fresh: Array = settings_rows()
	for r in fresh:
		var d: Dictionary = r
		if d.has("choice"):
			var names: Array = d["choice"]
			d["sub"] = "%s · how many monsters come out after dark, and how hard they hit" % String(names[clampi(int(Game.setting(String(d["key"]), 1)), 0, names.size() - 1)])
	return fresh
