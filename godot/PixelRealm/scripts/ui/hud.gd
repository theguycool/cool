class_name Hud
extends CanvasLayer
## The screen over the world, laid out as in the Swift game. Top left: hearts, hunger, air and armour
## (or CREATIVE). Top right: zoom, map, journal, debug and pause buttons, with the place, depth, day
## and weather under them. In the middle: messages, weather warnings and a boss's health. At the
## bottom: the walking stick, the hotbar with the bag at its end, the buttons that only show when
## they apply (drive, pack up, dismount, reload, down), the weapon swap, JUMP and the attack stick.
## Every control follows its own finger, so walking, jumping and attacking all work at once. With
## touch controls turned off (keyboard and mouse) the sticks and JUMP are hidden.

const SLOT := 44.0
const GAP := 3.0
const MARGIN := 14.0

var level: Level = null
## What the touch controls are doing; Level.merge_controls adds the keyboard to it
var stick_vec := Vector2.ZERO
var jump_down: bool = false
var down_down: bool = false
var attack_down: bool = false
## Extra lines drawn under the info block (the debug overlay)
var overlay: bool = false

var _root: Control
var _canvas: Control
var _touch: Control
var _walk: Stick
var _attack: Stick
var _jump: TouchButton
var _down: TouchButton
var _swap: TouchButton
var _bag: TouchButton
var _slots: Array = []
var _top_buttons: Array = []
var _zoom_out: TouchButton
var _zoom_in: TouchButton
var _map: TouchButton
var _log: TouchButton
var _dbg: TouchButton
var _pause: TouchButton
var _drive: TouchButton
var _pack: TouchButton
var _dismount: TouchButton
var _reload: TouchButton
var _msg: String = ""
var _msg_t: float = 0.0
var _sel_name: String = ""
var _ctx_note: String = ""
var _ctx_note_color := Color.WHITE
var _ctx_t: float = 0.0
var _near_vehicle: Vehicle = null
var _hotbar_pos := Vector2.ZERO
var _ctx_y: float = 0.0
var _font: Font
var _box: StyleBoxFlat
var _tex := {}


func _ready() -> void:
	layer = 10
	_font = ThemeDB.fallback_font
	_box = StyleBoxFlat.new()
	_box.bg_color = Color(0.18, 0.18, 0.18, 0.9)
	_box.border_color = Color(0.04, 0.04, 0.04, 0.95)
	_box.set_border_width_all(2)
	for n in ["heart_full", "heart_empty", "food_full", "food_empty", "bubble", "shield"]:
		_tex[n] = Art.tex("res://assets/ui/%s.png" % n)
	_root = _full_rect(Control.new())
	add_child(_root)
	_canvas = _full_rect(Control.new())
	_root.add_child(_canvas)
	_canvas.draw.connect(_draw_canvas)
	_touch = _full_rect(Control.new())
	_root.add_child(_touch)
	_build_controls()
	get_viewport().size_changed.connect(layout_controls)
	layout_controls()


func _full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _button(label: String, col: Color, w: float, h: float, parent: Control, fs: int = 15) -> TouchButton:
	var b := TouchButton.new()
	b.text = label
	b.color = col
	b.font_size = fs
	b.size = Vector2(w, h)
	parent.add_child(b)
	return b


func _build_controls() -> void:
	# the walking stick and the attack stick
	_walk = Stick.new()
	_walk.radius = 66.0
	_walk.size = Vector2(166, 166)
	_touch.add_child(_walk)
	_walk.moved.connect(_on_walk)
	_walk.released.connect(_on_walk_released)
	_attack = Stick.new()
	_attack.attack = true
	_attack.radius = 70.0
	_attack.size = Vector2(174, 174)
	_touch.add_child(_attack)
	_attack.moved.connect(_on_attack)
	_attack.released.connect(_on_attack_released)
	_jump = _button("JUMP", Color(0.31, 0.54, 0.24), 84, 84, _touch, 22)
	_jump.pressed_changed.connect(_on_jump)
	_swap = _button("", Color(0.35, 0.29, 0.48), 56, 56, _touch)
	_swap.slot_style = false
	_swap.tapped.connect(_on_swap)
	# the hotbar and the bag at its end
	for i in range(Inventory.HOTBAR):
		var s := TouchButton.new()
		s.slot_style = true
		s.color = Color(0.85, 0.85, 0.85)
		s.size = Vector2(SLOT, SLOT)
		_root.add_child(s)
		s.pressed_changed.connect(_on_slot.bind(i))
		_slots.append(s)
	_bag = TouchButton.new()
	_bag.text = "BAG"
	_bag.font_size = 11
	_bag.icon = Art.icon("block:chest")
	_bag.color = Color(0.3, 0.42, 0.58)
	_bag.size = Vector2(SLOT, SLOT)
	_root.add_child(_bag)
	_bag.tapped.connect(_on_bag)
	# the top-right row
	_zoom_out = _button("-", Color(0.42, 0.42, 0.42), 44, 36, _root, 20)
	_zoom_in = _button("+", Color(0.42, 0.42, 0.42), 44, 36, _root, 20)
	_map = _button("MAP", Color(0.6, 0.48, 0.23), 60, 36, _root)
	_log = _button("LOG", Color(0.48, 0.35, 0.16), 60, 36, _root)
	_dbg = _button("DBG", Color(0.42, 0.42, 0.42), 60, 36, _root)
	_pause = _button("II", Color(0.42, 0.42, 0.42), 44, 36, _root, 18)
	_top_buttons = [_pause, _dbg, _log, _map, _zoom_in, _zoom_out]
	_zoom_out.tapped.connect(_on_zoom.bind(-0.5))
	_zoom_in.tapped.connect(_on_zoom.bind(0.5))
	_map.tapped.connect(_open.bind("map"))
	_log.tapped.connect(_open.bind("journal"))
	_dbg.tapped.connect(_open.bind("debug"))
	_pause.tapped.connect(_open.bind("pause"))
	# buttons that show only when they apply
	_drive = _button("DRIVE", Color(0.31, 0.54, 0.24), 92, 36, _root)
	_pack = _button("PACK UP", Color(0.42, 0.35, 0.16), 100, 36, _root)
	_dismount = _button("DISMOUNT", Color(0.63, 0.19, 0.19), 110, 36, _root)
	_reload = _button("RELOAD", Color(0.42, 0.35, 0.16), 96, 36, _root)
	_down = _button("", Color(0.42, 0.42, 0.42), 44, 44, _touch)
	_down.icon = Art.tex("res://assets/ui/icon_down.png")
	_drive.tapped.connect(_on_drive)
	_pack.tapped.connect(_on_pack)
	_dismount.tapped.connect(_on_dismount)
	_reload.tapped.connect(_on_reload)
	_down.pressed_changed.connect(_on_down)
	for b in [_drive, _pack, _dismount, _reload, _down, _map, _swap]:
		(b as TouchButton).visible = false


func attach(lv: Level) -> void:
	level = lv
	layout_controls()
	refresh()


## Places everything for the screen size and the settings (touch controls, sticks swapped)
func layout_controls() -> void:
	if _root == null:
		return
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var touch_on: bool = bool(Game.setting("touch_controls", true))
	var swap: bool = bool(Game.setting("swap_sticks", false))
	_touch.visible = touch_on
	if not touch_on:
		_release_touch()
	var wb: float = _walk.size.x
	var ab: float = _attack.size.x
	var jy: float = vs.y - _jump.size.y - MARGIN - 10.0
	if swap:
		_walk.position = Vector2(vs.x - MARGIN - wb, vs.y - wb - MARGIN)
		_attack.position = Vector2(MARGIN, vs.y - ab - MARGIN)
		_jump.position = Vector2(_attack.position.x + ab + 8.0, jy)
	else:
		_walk.position = Vector2(MARGIN, vs.y - wb - MARGIN)
		_attack.position = Vector2(vs.x - MARGIN - ab, vs.y - ab - MARGIN)
		_jump.position = Vector2(_attack.position.x - _jump.size.x - 8.0, jy)
	_swap.position = _jump.position + Vector2((_jump.size.x - _swap.size.x) * 0.5, -_swap.size.y - 12.0)
	var hw: float = float(Inventory.HOTBAR + 1) * SLOT + float(Inventory.HOTBAR) * GAP
	_hotbar_pos = Vector2(floorf((vs.x - hw) * 0.5), vs.y - SLOT - MARGIN)
	for i in range(_slots.size()):
		(_slots[i] as TouchButton).position = _hotbar_pos + Vector2(float(i) * (SLOT + GAP), 0)
	_bag.position = _hotbar_pos + Vector2(float(Inventory.HOTBAR) * (SLOT + GAP), 0)
	_ctx_y = _hotbar_pos.y - 26.0 - 40.0
	_layout_top()
	_layout_context()
	_canvas.queue_redraw()


func _layout_top() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var x: float = vs.x - MARGIN
	for b in _top_buttons:
		var tb: TouchButton = b
		if not tb.visible:
			continue
		x -= tb.size.x
		tb.position = Vector2(x, MARGIN)
		x -= 6.0


func _layout_context() -> void:
	var vis: Array = []
	for b in [_drive, _pack, _dismount, _reload, _down]:
		var tb: TouchButton = b
		if tb.visible and tb.is_visible_in_tree():
			vis.append(tb)
	var total: float = 0.0
	for b in vis:
		total += (b as TouchButton).size.x + 6.0
	var x: float = floorf(get_viewport().get_visible_rect().size.x * 0.5 - (total - 6.0) * 0.5)
	for b in vis:
		var tb2: TouchButton = b
		tb2.position = Vector2(x, _ctx_y + (36.0 - tb2.size.y) * 0.5)
		x += tb2.size.x + 6.0


## Panels cover the controls: hide them (which lets go of anything held)
func set_controls_visible(on: bool) -> void:
	if not on:
		_release_touch()
	_root.visible = on


func _release_touch() -> void:
	_walk.release_now()
	_attack.release_now()
	_jump.release()
	_down.release()
	stick_vec = Vector2.ZERO
	jump_down = false
	down_down = false
	if attack_down and level != null:
		level.input.attack_stick_released()
	attack_down = false
	_merge()


func show_message(msg: String, secs: float) -> void:
	_msg = msg
	_msg_t = secs
	_canvas.queue_redraw()


# ---------------------------------------------------------------------------------------------- controls

func _merge() -> void:
	if level != null:
		level.merge_controls()


func _on_walk(v: Vector2) -> void:
	stick_vec = Stick.walk_vector(v)
	_merge()


func _on_walk_released() -> void:
	stick_vec = Vector2.ZERO
	_merge()


func _on_attack(v: Vector2) -> void:
	attack_down = true
	if level != null:
		level.input.attack_stick_at(v)
	_merge()


func _on_attack_released() -> void:
	attack_down = false
	if level != null:
		level.input.attack_stick_released()
	_merge()


func _on_jump(down: bool) -> void:
	jump_down = down
	_merge()


func _on_down(down: bool) -> void:
	down_down = down
	_merge()


func _on_slot(down: bool, i: int) -> void:
	if down and level != null and level.player != null:
		level.player.actions.set_sel(i)
		Sfx.play("tap", 0.4)


func _on_bag() -> void:
	_open("inventory")


func _open(panel_name: String) -> void:
	if level != null:
		Sfx.play("tap", 0.5)
		level.open_panel(panel_name)


func _on_swap() -> void:
	if level != null and level.player != null:
		level.player.actions.cycle_weapon()


func _on_zoom(d: float) -> void:
	var z: float = clampf(float(Game.setting("zoom", 4.0)) + d, 2.0, 7.0)
	Game.set_setting("zoom", z)


func _on_drive() -> void:
	if level != null and _near_vehicle != null and is_instance_valid(_near_vehicle):
		level.drive(_near_vehicle)


func _on_pack() -> void:
	if level != null and _near_vehicle != null and is_instance_valid(_near_vehicle):
		level.pack_up(_near_vehicle)


func _on_dismount() -> void:
	if level != null:
		level.dismount()


func _on_reload() -> void:
	if level != null and level.player != null:
		level.player.actions.start_reload()


# ---------------------------------------------------------------------------------------------- keeping it up to date

## Redraws the hotbar, the labels and which buttons show (when something changed)
func refresh() -> void:
	if level == null or level.player == null:
		return
	var p: Player = level.player
	var inv: Inventory = p.inv
	var sel: int = p.actions.sel
	for i in range(_slots.size()):
		var b: TouchButton = _slots[i]
		var s = inv.slots[i]
		if s == null:
			b.set_item("", 0)
		else:
			b.set_item(String(s["id"]), int(s["n"]), _ammo_text(s))
		if b.selected != (i == sel):
			b.selected = i == sel
			b.queue_redraw()
	_sel_name = _selected_name()
	_attack.label = _use_label()
	_attack.queue_redraw()
	var nxt: int = p.actions.next_weapon_slot()
	if nxt >= 0 and bool(Game.setting("touch_controls", true)):
		var ns = inv.slots[nxt]
		_swap.visible = true
		_swap.set_item(String(ns["id"]), 1)
	else:
		_swap.visible = false
	_map.visible = inv.total("gadget:treasureMap") > 0
	_layout_top()
	_update_context()
	_canvas.queue_redraw()


func _ammo_text(s: Dictionary) -> String:
	var id: String = String(s["id"])
	if DB.kind_of(id) != "gun":
		return ""
	var g: Dictionary = DB.gun_info(id)
	return "%d/%d" % [int(s.get("x", 0)), int(g.get("magazine", 1))]


## What the attack stick does with the item in hand
func _use_label() -> String:
	var id: String = level.player.actions.held_id()
	if id == "":
		return "PUNCH"
	if DB.is_weapon(id):
		return "ATTACK"
	match DB.kind_of(id):
		"tool":
			return "MINE"
		"block", "wall":
			return "BUILD"
		"food":
			return "EAT"
	return "USE"


func _selected_name() -> String:
	var p: Player = level.player
	var s = p.inv.slots[p.actions.sel]
	if s == null:
		return "Empty hand"
	var id: String = String(s["id"])
	var nm: String = DB.item_name(id)
	match DB.kind_of(id):
		"gun":
			var g: Dictionary = DB.gun_info(id)
			var ex: int = int(s.get("x", 0))
			var mg: int = int(g.get("magazine", 1))
			var ammo: String = String(g.get("ammo", ""))
			if ammo != "":
				return "%s  %d/%d · %d left" % [nm, ex, mg, p.inv.total(ammo)]
			return "%s  %d/%d charges" % [nm, ex, mg]
		"bow":
			return "%s · %d arrows" % [nm, p.inv.total("ammo:arrow")]
		"sling":
			var n: int = 0
			for st in ["block:stone", "block:slate", "block:deepRock", "block:ashStone", "block:sandstone"]:
				n += p.inv.total(st)
			return "%s · %d stones" % [nm, n]
	return nm


## The buttons that only show when they apply
func _update_context() -> void:
	var p: Player = level.player
	var riding: bool = p.riding != null
	_near_vehicle = null if riding else level.vehicle_near(p.global_position, 24.0)
	_drive.visible = _near_vehicle != null and not p.dead
	_pack.visible = _drive.visible
	_dismount.visible = riding
	_ctx_note = ""
	_reload.visible = false
	var s = p.inv.slots[p.actions.sel]
	if s != null and DB.kind_of(String(s["id"])) == "gun":
		var id: String = String(s["id"])
		var g: Dictionary = DB.gun_info(id)
		var mag: int = int(g.get("magazine", 1))
		if p.actions.reload_t > 0.0:
			_ctx_note = "COCKING" if (bool(g.get("bolts", false)) and mag == 1) else "RELOADING"
			_ctx_note_color = Color(1.0, 0.88, 0.5)
		elif id == "gun:stormRod":
			if int(s.get("x", 0)) < mag:
				_ctx_note = "CHARGING"
				_ctx_note_color = Color(0.72, 0.88, 1.0)
		elif int(s.get("x", 0)) < mag:
			_reload.visible = true
	_down.visible = p.flying or p.noclip
	_layout_context()


func tick(delta: float) -> void:
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			_msg = ""
	_ctx_t -= delta
	if _ctx_t <= 0.0 and level != null and level.player != null:
		_ctx_t = 0.25
		_update_context()
		_sel_name = _selected_name()
	_canvas.queue_redraw()


# ---------------------------------------------------------------------------------------------- drawing

func _text(c: Control, s: String, pos: Vector2, fs: int, col: Color, align: int = 0) -> void:
	var w: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p: Vector2 = pos
	if align == 1:
		p.x -= w * 0.5
	elif align == 2:
		p.x -= w
	c.draw_string_outline(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
	c.draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _icon_row(c: Control, pos: Vector2, value: float, per: float, count: int, full: Texture2D, empty: Texture2D, sz: float) -> void:
	for i in range(count):
		var r := Rect2(pos.x + float(i) * (sz + 1.0), pos.y, sz, sz)
		c.draw_texture_rect(empty, r, false)
		var f: float = clampf((value - float(i) * per) / per, 0.0, 1.0)
		var q: float = floorf(f * 2.0) / 2.0
		if q > 0.0:
			var tw: float = float(full.get_width())
			var th: float = float(full.get_height())
			c.draw_texture_rect_region(full, Rect2(r.position, Vector2(sz * q, sz)), Rect2(0, 0, tw * q, th))


func _draw_canvas() -> void:
	if level == null or level.player == null:
		return
	var c: Control = _canvas
	var vs: Vector2 = c.size
	var p: Player = level.player
	# frost creeping in from the edges of the screen as the player gets cold
	if p.body_cold > 0.3:
		var fa: float = clampf((p.body_cold - 0.3) * 0.7, 0.0, 0.5)
		var frost := Color(0.81, 0.94, 1.0, fa)
		var edge: float = 26.0
		for k in range(4):
			var e: float = edge * float(4 - k) / 4.0
			var col := Color(frost.r, frost.g, frost.b, fa * 0.35)
			c.draw_rect(Rect2(0, 0, vs.x, e), col)
			c.draw_rect(Rect2(0, vs.y - e, vs.x, e), col)
			c.draw_rect(Rect2(0, 0, e, vs.y), col)
			c.draw_rect(Rect2(vs.x - e, 0, e, vs.y), col)
	# status, top left
	var y: float = MARGIN
	if p.is_creative():
		_text(c, "CREATIVE", Vector2(MARGIN, y + 16.0), 18, Color.WHITE)
		y += 24.0
	else:
		_icon_row(c, Vector2(MARGIN, y), p.hp, p.max_hp / 10.0, 10, _tex["heart_full"], _tex["heart_empty"], 18.0)
		y += 21.0
		_icon_row(c, Vector2(MARGIN, y), p.hunger, 2.0, 10, _tex["food_full"], _tex["food_empty"], 18.0)
		y += 21.0
		if p.air < 9.99:
			_icon_row(c, Vector2(MARGIN, y), p.air, 1.0, 10, _tex["bubble"], _tex["heart_empty"], 14.0)
			y += 17.0
		var def: float = p.inv.defense()
		if def > 0.0:
			c.draw_texture_rect(_tex["shield"], Rect2(MARGIN, y, 16, 16), false)
			_text(c, str(roundi(def)), Vector2(MARGIN + 21.0, y + 13.0), 14, Color.WHITE)
			y += 20.0
	if level.mode == "hardcore":
		_text(c, "HARDCORE", Vector2(MARGIN, y + 13.0), 13, Color(1.0, 0.38, 0.38))
	# place, day and weather, top right under the buttons
	if bool(Game.setting("show_coords", true)):
		_draw_info(c, Vector2(vs.x - MARGIN, MARGIN + 36.0 + 18.0))
	# the middle: weather warning, boss bar, message
	var my: float = MARGIN + 6.0
	var banner: Array = _banner()
	if String(banner[0]) != "":
		my = _boxed_text(c, String(banner[0]), vs.x * 0.5, my, 620.0, 15, Color(0.63, 0.13, 0.13, 0.92) if int(banner[1]) >= 2 else Color(0.54, 0.42, 0.1, 0.92)) + 6.0
	if level.boss != null and is_instance_valid(level.boss):
		my = _draw_boss_bar(c, vs.x * 0.5, my + 4.0) + 6.0
	if _msg != "":
		var a: float = clampf(_msg_t * 2.0, 0.0, 1.0)
		_boxed_text(c, _msg, vs.x * 0.5, my + 4.0, 560.0, 16, Color(0.18, 0.18, 0.18, 0.9 * a))
	# the held item's name over the hotbar, and the reload note
	_text(c, _sel_name, Vector2(vs.x * 0.5, _hotbar_pos.y - 8.0), 14, Color.WHITE, 1)
	if _ctx_note != "":
		_text(c, _ctx_note, Vector2(vs.x * 0.5, _ctx_y + 24.0), 14, _ctx_note_color, 1)
	# the hint for kits in hand
	var held: String = p.actions.held_id()
	if p.riding == null and (held == "gadget:carKit" or held == "gadget:boatKit" or held == "gadget:motorboatKit"):
		_boxed_text(c, "Tap open, flat ground near you to place it. Boats go on water.", 170.0, 150.0, 300.0, 13, Color(0.18, 0.18, 0.18, 0.85))
	if bool(Game.setting("show_fps", false)) or overlay:
		_text(c, "%d FPS" % Engine.get_frames_per_second(), Vector2(MARGIN, vs.y - 196.0), 13, Color(0.7, 1.0, 0.7))


func _draw_info(c: Control, top_right: Vector2) -> void:
	var p: Player = level.player
	var x: int = floori(p.global_position.x / 8.0)
	var yy: int = floori(p.global_position.y / 8.0)
	var lines: Array = []
	lines.append(["X %d  Y %d" % [x, yy], Color.WHITE])
	lines.append(["%s · %s" % [DB.biome_name(level.gen.biome_at(x)) if level.dim == WorldGen.DIM_OVERWORLD else "Umbral Realm", _depth_text(yy)], Color.WHITE])
	if level.dim == WorldGen.DIM_OVERWORLD:
		lines.append(["Day %d%s" % [level.day_count, " · Night" if level.is_night() else ""], Color.WHITE])
		if bool(Game.setting("weather", true)):
			var wtxt: String = level.weather.name_of(level.weather.kind)
			if level.weather.snowing(level) and level.weather.precip > 0.05:
				wtxt = "Snow" if level.weather.kind != "blizzard" else "Blizzard"
			var wv: float = level.weather.wind
			if wv >= 3.0:
				wtxt += " · wind %d %s" % [roundi(wv), ">" if level.weather.wind_dir > 0.0 else "<"]
			lines.append([wtxt, Color.WHITE])
			if level.player.actions.held_id() == "gadget:barometer":
				lines.append([level.weather.barometer_text(), Color(0.91, 0.82, 0.56)])
	else:
		lines.append(["Umbral Realm", Color.WHITE])
	if overlay:
		lines.append(["mobs %d · chunks %d · gen %d" % [level.mobs.size(), level.world.chunks.size(), level.world.pending_count()], Color(0.6, 0.94, 0.88)])
	var ly: float = top_right.y
	for l in lines:
		_text(c, String(l[0]), Vector2(top_right.x, ly), 13, l[1], 2)
		ly += 16.0


func _depth_text(y: int) -> String:
	if level.dim == WorldGen.DIM_UMBRAL:
		return "Umbral depth %d" % y
	var d: int = y - WorldGen.SEA
	if d < -2:
		return "%d above sea" % -d
	if d <= 2:
		return "Sea level"
	if d < 60:
		return "%d deep" % d
	if d < 220:
		return "%d deep (caverns)" % d
	if d < 360:
		return "%d deep (deep caves)" % d
	return "%d deep (the abyss)" % d


## The weather warning for where the player is: [text, level] (2 is a red warning)
func _banner() -> Array:
	if level.dim != WorldGen.DIM_OVERWORLD or not bool(Game.setting("weather", true)):
		return ["", 0]
	var w: Weather = level.weather
	if not bool(Game.setting("weather_alerts", true)):
		return ["", 0]
	if not w.pending_strike.is_empty():
		return ["LIGHTNING IS ABOUT TO STRIKE NEAR YOU · move or take cover", 2]
	if w.tornado_on:
		var dist: int = roundi(absf(w.tornado_x - level.player.global_position.x) / 8.0)
		var side: String = "east" if w.tornado_x > level.player.global_position.x else "west"
		return ["TORNADO ON THE GROUND · %d blocks %s · get underground" % [dist, side], 2]
	match w.kind:
		"hurricane":
			return ["HURRICANE · stay indoors, away from the shore", 2]
		"blizzard":
			return ["BLIZZARD · stay sheltered and keep warm", 1]
		"hailstorm":
			if w.hail > 0.3:
				return ["LARGE HAIL · get under a roof", 1]
		"thunderstorm":
			if w.thunder > 0.5:
				return ["Thunderstorm · keep off high, open ground", 1]
		"windstorm":
			return ["Windstorm · hold your footing near edges", 1]
	if level.player.body_cold > 0.45:
		return ["Freezing · find a fire, shelter or warm clothes", 1]
	return ["", 0]


## A dark box with wrapped, centred text; returns the bottom of the box
func _boxed_text(c: Control, s: String, cx: float, top: float, max_w: float, fs: int, bg: Color) -> float:
	var inner_w: float = max_w - 16.0
	var sz: Vector2 = _font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_CENTER, inner_w, fs)
	var w: float = minf(max_w, sz.x + 18.0)
	var r := Rect2(cx - w * 0.5, top, w, sz.y + 12.0)
	_box.bg_color = bg
	c.draw_style_box(_box, r)
	var asc: float = _font.get_ascent(fs)
	c.draw_multiline_string(_font, Vector2(r.position.x + 9.0, top + 6.0 + asc), s, HORIZONTAL_ALIGNMENT_CENTER, w - 18.0, fs, -1, Color(1, 1, 1, bg.a / 0.9 if bg.a < 0.9 else 1.0))
	return r.end.y


func _draw_boss_bar(c: Control, cx: float, top: float) -> float:
	var b: Mob = level.boss
	_text(c, b.display_name(), Vector2(cx, top + 15.0), 16, Color(1.0, 0.82, 0.38), 1)
	var r := Rect2(cx - 180.0, top + 22.0, 360.0, 14.0)
	c.draw_rect(r, Color(0, 0, 0, 0.75))
	var frac: float = clampf(b.hp / maxf(1.0, b.max_hp), 0.0, 1.0)
	c.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(356.0 * frac, 10.0)), Color(0.75, 0.16, 0.16))
	c.draw_rect(r, Color(1, 1, 1, 0.7), false, 2.0)
	return r.end.y
