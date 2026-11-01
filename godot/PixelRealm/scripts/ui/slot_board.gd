class_name SlotBoard
extends Control
## The bag (its top row is the hotbar), the armour and gear slots, an open chest and the DROP spot,
## drawn as one board so a stack can be moved anywhere on it, as in the Swift game:
##   tap: pick a stack up into your hand, tap again to put it down (merging or swapping)
##   hold: split a stack in half, put on armour or gear, or (with a chest open) store it in the chest;
##         in the chest: take it into your bag
##   drag: move, merge or swap in one go; drag onto DROP to throw it out
## It follows its own finger and also works with a mouse.

signal changed

const S := 40.0
const G := 3.0
const GRID_X := 94.0
const LEFT_W := 521.0
const CHEST_X := 537.0
const ARMOR_NAMES := ["Head", "Body", "Legs", "Gear", "Gear"]

var level: Level = null
var inv: Inventory = null
var chest_cell := Vector2i(-99999, -99999)
## the stack in your hand (a slot dictionary) or null
var carry = null
## the stack last touched, for the info line
var info_stack = null

var _font: Font
var _slot_tex: Texture2D
var _touch: int = -1
var _press_ref: Dictionary = {}
var _press_pos := Vector2.ZERO
var _press_t: float = 0.0
var _held_fired: bool = false
var _dragging: bool = false
var _drag_pos := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_slot_tex = Art.tex("res://assets/ui/slot.png")
	custom_minimum_size = board_size()


func setup(lv: Level, chest: Vector2i) -> void:
	level = lv
	inv = lv.player.inv
	chest_cell = chest
	custom_minimum_size = board_size()
	queue_redraw()


func has_chest() -> bool:
	return chest_cell.x != -99999


func board_size() -> Vector2:
	return Vector2(CHEST_X + 9.0 * (S + G) - G if has_chest() else LEFT_W, 318.0)


func chest() -> Array:
	return level.world.chest_items(chest_cell.x, chest_cell.y)


# ---------------------------------------------------------------------------------------------- where things are

func _slot_rect(area: String, i: int) -> Rect2:
	match area:
		"inv":
			return Rect2(GRID_X + float(i % 10) * (S + G), float(i / 10) * (S + G), S, S)
		"armor":
			if i < 3:
				return Rect2(0, float(i) * (S + 14.0), S, S)
			return Rect2(S + 4.0, float(i - 3) * (S + 14.0), S, S)
		"chest":
			return Rect2(CHEST_X + float(i % 9) * (S + G), 26.0 + float(i / 9) * (S + G), S, S)
		"drop":
			return Rect2(LEFT_W - 84.0, 188.0, 84.0, 36.0)
		"putback":
			return Rect2(LEFT_W - 84.0 - 8.0 - 96.0, 190.0, 96.0, 32.0)
	return Rect2()


func _hit(p: Vector2) -> Dictionary:
	for i in range(Inventory.SIZE):
		if _slot_rect("inv", i).grow(1.5).has_point(p):
			return {"area": "inv", "i": i}
	for i in range(Inventory.ARMOR_SLOTS):
		if _slot_rect("armor", i).grow(1.5).has_point(p):
			return {"area": "armor", "i": i}
	if has_chest():
		for i in range(WorldData.CHEST_SLOTS):
			if _slot_rect("chest", i).grow(1.5).has_point(p):
				return {"area": "chest", "i": i}
	if _slot_rect("drop", 0).has_point(p):
		return {"area": "drop", "i": 0}
	if carry != null and _slot_rect("putback", 0).has_point(p):
		return {"area": "putback", "i": 0}
	return {}


func stack_at(ref: Dictionary):
	if ref.is_empty():
		return null
	var i: int = int(ref["i"])
	match String(ref["area"]):
		"inv":
			return inv.slots[i]
		"armor":
			return inv.armor[i]
		"chest":
			return chest()[i] if has_chest() else null
	return null


func _set_at(ref: Dictionary, s) -> void:
	var i: int = int(ref["i"])
	match String(ref["area"]):
		"inv":
			inv.slots[i] = s
		"armor":
			inv.armor[i] = s
		"chest":
			chest()[i] = s


# ---------------------------------------------------------------------------------------------- moving stacks

## Taps a slot with what is in your hand: put down, merge, swap, or pick up
func tap_ref(ref: Dictionary) -> void:
	if ref.is_empty():
		return
	var area: String = String(ref["area"])
	if area == "drop":
		drop_carried()
		return
	if area == "putback":
		return_carried()
		return
	if area == "armor":
		_tap_armor(int(ref["i"]))
		return
	var s = stack_at(ref)
	if carry != null:
		var h: Dictionary = carry
		if s != null:
			var sd: Dictionary = s
			var ms: int = DB.max_stack(String(h["id"]))
			if String(sd["id"]) == String(h["id"]) and ms > 1 and int(sd.get("x", 0)) == int(h.get("x", 0)):
				var put: int = mini(ms - int(sd["n"]), int(h["n"]))
				sd["n"] = int(sd["n"]) + put
				h["n"] = int(h["n"]) - put
				carry = h if int(h["n"]) > 0 else null
			else:
				_set_at(ref, h)
				carry = sd
		else:
			_set_at(ref, h)
			carry = null
	elif s != null:
		carry = s
		_set_at(ref, null)
	_changed()


func _fits_armor(id: String, i: int) -> bool:
	var e: int = Inventory.equip_slot(id)
	if e == 3:
		return i >= 3
	return e == i


func _tap_armor(i: int) -> void:
	if carry != null:
		var h: Dictionary = carry
		if _fits_armor(String(h["id"]), i):
			var old = inv.armor[i]
			inv.armor[i] = h
			carry = old
		else:
			level.say("That does not go there.", 1.0)
	elif inv.armor[i] != null:
		carry = inv.armor[i]
		inv.armor[i] = null
	_changed()


func split_slot(i: int) -> void:
	if carry != null:
		return
	var s = inv.slots[i]
	if s == null or int(s["n"]) < 2:
		return
	var half: int = int(s["n"]) / 2
	s["n"] = int(s["n"]) - half
	carry = Inventory.make(String(s["id"]), half, int(s.get("x", 0)))
	_changed()


func quick_equip(i: int) -> bool:
	var s = inv.slots[i]
	if s == null:
		return false
	var id: String = String(s["id"])
	var target: int = Inventory.equip_slot(id)
	if target < 0:
		return false
	if target == 3:
		# the same piece already worn is swapped out; otherwise the first free gear slot
		var free: int = -1
		for k in range(3, Inventory.ARMOR_SLOTS):
			var w = inv.armor[k]
			if w != null and String(w["id"]) == id:
				free = k
				break
			if w == null and free < 0:
				free = k
		target = free if free >= 0 else 3
	var old = inv.armor[target]
	inv.armor[target] = s
	inv.slots[i] = old
	Sfx.play("place", 0.5)
	_changed()
	return true


func _hold(ref: Dictionary) -> void:
	if ref.is_empty():
		return
	var area: String = String(ref["area"])
	var i: int = int(ref["i"])
	if area == "inv":
		if has_chest():
			chest_store(i)
			return
		if quick_equip(i):
			return
		split_slot(i)
	elif area == "chest":
		chest_quick_move(i)
	elif area == "armor":
		if inv.armor[i] != null and carry == null:
			inv.unequip(i)
			_changed()


## Drags the stack from one slot onto another (same rules as tapping); anything that cannot land
## goes back where it came from, or into the bag
func drag_stack(from: Dictionary, to: Dictionary) -> void:
	if carry != null:
		return_carried()
	if stack_at(from) == null:
		return
	tap_ref(from)
	if carry == null:
		return
	if not to.is_empty() and not (String(to["area"]) == String(from["area"]) and int(to["i"]) == int(from["i"])):
		tap_ref(to)
	if carry != null and stack_at(from) == null:
		tap_ref(from)
	if carry != null:
		return_carried()
	_changed()


func drop_carried() -> void:
	if carry == null:
		return
	var c: Dictionary = carry
	var p: Player = level.player
	level.spawn_drop(String(c["id"]), int(c["n"]), p.global_position + Vector2(float(p.facing) * 6.4, -9.6), Vector2(float(p.facing) * 32.0, -32.0), int(c.get("x", 0)))
	carry = null
	_changed()


func return_carried() -> void:
	if carry == null:
		return
	var c: Dictionary = carry
	carry = null
	var left: int = inv.add(String(c["id"]), int(c["n"]), int(c.get("x", 0)))
	if left > 0:
		level.spawn_drop(String(c["id"]), left, level.player.global_position + Vector2(0, -8), Vector2(16, -24), int(c.get("x", 0)))
	_changed()


func chest_quick_move(i: int) -> void:
	var items: Array = chest()
	var s = items[i]
	if s == null:
		return
	var left: int = inv.add(String(s["id"]), int(s["n"]), int(s.get("x", 0)))
	if left == 0:
		items[i] = null
	else:
		s["n"] = left
	_changed()


func chest_store(i: int) -> void:
	var s = inv.slots[i]
	if s == null:
		return
	var items: Array = chest()
	# top up matching stacks first, then the first free slot
	var ms: int = DB.max_stack(String(s["id"]))
	if ms > 1:
		for k in range(items.size()):
			var e = items[k]
			if e != null and String(e["id"]) == String(s["id"]) and int(e["n"]) < ms and int(s["n"]) > 0:
				var put: int = mini(ms - int(e["n"]), int(s["n"]))
				e["n"] = int(e["n"]) + put
				s["n"] = int(s["n"]) - put
	if int(s["n"]) > 0:
		var free: int = items.find(null)
		if free < 0:
			level.say("The chest is full.", 1.5)
		else:
			items[free] = s
			inv.slots[i] = null
	else:
		inv.slots[i] = null
	_changed()


## Moves every bag stack (not the hotbar) whose item the chest already holds into the chest
func quick_stack() -> void:
	if not has_chest():
		return
	var items: Array = chest()
	var moved: int = 0
	for i in range(Inventory.HOTBAR, Inventory.SIZE):
		var s = inv.slots[i]
		if s == null:
			continue
		var found: bool = false
		for e in items:
			if e != null and String(e["id"]) == String(s["id"]):
				found = true
				break
		if not found:
			continue
		var before: int = int(s["n"])
		chest_store(i)
		var after: int = Inventory.count_of(inv.slots[i])
		moved += before - after
	level.say("Stored %d items in the chest." % moved if moved > 0 else "Nothing here matches the chest.", 1.5)
	_changed()


func take_all() -> void:
	if not has_chest():
		return
	var items: Array = chest()
	for i in range(items.size()):
		if items[i] != null:
			chest_quick_move(i)
	_changed()


func _changed() -> void:
	inv.notify()
	level.hud_dirty = true
	changed.emit()
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
			_move(sd.position)
		accept_event()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.device != -1 and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _touch == -1:
				_touch = -2
				_press(mb.position)
			elif not mb.pressed and _touch == -2:
				_release(mb.position)
		accept_event()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if mm.device != -1 and _touch == -2:
			_move(mm.position)
		accept_event()


func _press(p: Vector2) -> void:
	_press_ref = _hit(p)
	_press_pos = p
	_press_t = 0.0
	_held_fired = false
	_dragging = false
	_drag_pos = p
	var s = stack_at(_press_ref)
	if s != null:
		info_stack = s
	queue_redraw()


func _move(p: Vector2) -> void:
	_drag_pos = p
	if not _dragging and not _held_fired and p.distance_to(_press_pos) > 8.0:
		var area: String = String(_press_ref.get("area", ""))
		if carry == null and (area == "inv" or area == "armor" or area == "chest") and stack_at(_press_ref) != null:
			_dragging = true
	if _dragging:
		queue_redraw()


func _release(p: Vector2) -> void:
	_touch = -1
	if _dragging:
		_dragging = false
		drag_stack(_press_ref, _hit(p))
	elif not _held_fired and p.distance_to(_press_pos) <= 14.0:
		tap_ref(_press_ref)
	_press_ref = {}
	queue_redraw()


func _process(delta: float) -> void:
	if _touch != -1 and not _dragging and not _held_fired and not _press_ref.is_empty():
		_press_t += delta
		if _press_t >= 0.35:
			_held_fired = true
			_hold(_press_ref)


# ---------------------------------------------------------------------------------------------- drawing

func _draw_slot(r: Rect2, s, ring: Color, faded: bool = false) -> void:
	draw_texture_rect(_slot_tex, r, false)
	if ring.a > 0.0:
		draw_rect(r.grow(-1.0), ring, false, 2.0)
	if s == null:
		return
	var sd: Dictionary = s
	var id: String = String(sd["id"])
	var isz: float = r.size.x * 0.72
	var ir := Rect2(r.position + (r.size - Vector2(isz, isz)) * 0.5, Vector2(isz, isz))
	draw_texture_rect(Art.icon(id), ir, false, Color(1, 1, 1, 0.35) if faded else Color.WHITE)
	var n: int = int(sd["n"])
	if n > 1:
		_text(str(n), Vector2(r.end.x - 2.0, r.end.y - 3.0), 12, Color.WHITE, 2)
	if DB.kind_of(id) == "gun":
		var g: Dictionary = DB.gun_info(id)
		_text("%d/%d" % [int(sd.get("x", 0)), int(g.get("magazine", 1))], Vector2(r.position.x + 2.0, r.end.y - 3.0), 10, Color(1.0, 0.88, 0.5), 0)


func _text(s: String, p: Vector2, fs: int, c: Color, align: int = 0) -> void:
	var w: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos: Vector2 = p
	if align == 1:
		pos.x -= w * 0.5
	elif align == 2:
		pos.x -= w
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.85))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)


func _is_drag_source(area: String, i: int) -> bool:
	return _dragging and String(_press_ref.get("area", "")) == area and int(_press_ref.get("i", -1)) == i


func _draw() -> void:
	if inv == null:
		return
	var sel: int = level.player.actions.sel
	# armour and gear
	for i in range(Inventory.ARMOR_SLOTS):
		var r: Rect2 = _slot_rect("armor", i)
		_draw_slot(r, inv.armor[i], Color(0, 0, 0, 0), _is_drag_source("armor", i))
		_text(String(ARMOR_NAMES[i]), Vector2(r.position.x + S * 0.5, r.end.y + 11.0), 10, Color(1, 1, 1, 0.7), 1)
	var def_y: float = 3.0 * (S + 14.0) + 2.0
	draw_texture_rect(Art.tex("res://assets/ui/shield.png"), Rect2(4, def_y, 14, 14), false)
	_text(str(roundi(inv.defense())), Vector2(22, def_y + 12.0), 12, Color.WHITE)
	# the bag (top row: the hotbar)
	for i in range(Inventory.SIZE):
		var r2: Rect2 = _slot_rect("inv", i)
		var ring := Color(0, 0, 0, 0)
		if i < Inventory.HOTBAR:
			ring = Color(1.0, 0.88, 0.44, 0.35)
		if i == sel:
			ring = Color(1, 1, 1, 0.95)
		_draw_slot(r2, inv.slots[i], ring, _is_drag_source("inv", i))
	# what is in your hand, PUT BACK and DROP
	var cy: float = 188.0
	if carry != null:
		_draw_slot(Rect2(GRID_X, cy, 36, 36), carry, Color(1, 1, 1, 0.8))
		_text("Holding " + DB.item_name(String(carry["id"])), Vector2(GRID_X + 44.0, cy + 23.0), 13, Color.WHITE)
		var pb: Rect2 = _slot_rect("putback", 0)
		draw_rect(pb, Color(0.42, 0.42, 0.42, 0.95))
		draw_rect(pb, Color(0, 0, 0, 0.7), false, 2.0)
		_text("PUT BACK", pb.get_center() + Vector2(0, 5), 12, Color.WHITE, 1)
	else:
		_text("Hand empty", Vector2(GRID_X, cy + 23.0), 12, Color(1, 1, 1, 0.6))
	var dr: Rect2 = _slot_rect("drop", 0)
	var active: bool = _dragging or carry != null
	draw_rect(dr, Color(0.48, 0.23, 0.16, 0.95) if active else Color(0.23, 0.18, 0.16, 0.9))
	draw_rect(dr, Color(0.63, 0.42, 0.16), false, 2.0 if active else 1.0)
	_text("DROP HERE" if _dragging else "DROP", dr.get_center() + Vector2(0, 5), 12, Color(1, 1, 1, 1.0 if active else 0.6), 1)
	# the info line
	var iy: float = 234.0
	draw_rect(Rect2(0, iy, LEFT_W, 40), Color(0, 0, 0, 0.25))
	var shown = carry if carry != null else info_stack
	if shown != null:
		var sid: String = String(shown["id"])
		var nm: String = DB.item_name(sid)
		if int(shown["n"]) > 1:
			nm += "  x%d" % int(shown["n"])
		_text(nm, Vector2(6, iy + 15.0), 13, Color.WHITE)
		var lines: Array = DB.item(sid).get("info", [])
		var info: String = " · ".join(PackedStringArray(lines))
		draw_string(_font, Vector2(6, iy + 32.0), info, HORIZONTAL_ALIGNMENT_LEFT, LEFT_W - 12.0, 11, Color(1, 1, 1, 0.75))
	else:
		draw_string(_font, Vector2(6, iy + 24.0), "Tap an item to see what it does.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55))
	var hint: String = "Drag to move, swap or stack (onto DROP to throw away). Tap: pick up / put down. Hold: "
	hint += "store in the chest." if has_chest() else "split a stack, put on armour."
	draw_multiline_string(_font, Vector2(0, 292.0), hint, HORIZONTAL_ALIGNMENT_LEFT, LEFT_W, 11, -1, Color(1, 1, 1, 0.7))
	# the chest
	if has_chest():
		_text("CHEST", Vector2(CHEST_X, 18.0), 15, Color.WHITE)
		var items: Array = chest()
		for i in range(WorldData.CHEST_SLOTS):
			_draw_slot(_slot_rect("chest", i), items[i] if i < items.size() else null, Color(0, 0, 0, 0), _is_drag_source("chest", i))
		draw_multiline_string(_font, Vector2(CHEST_X, 26.0 + 3.0 * (S + G) + 14.0), "Tap: take or put the held stack. Hold: move into your bag.", HORIZONTAL_ALIGNMENT_LEFT, 9.0 * (S + G), 11, -1, Color(1, 1, 1, 0.7))
	# the stack being dragged follows the finger
	if _dragging:
		var ds = stack_at(_press_ref)
		if ds != null:
			_draw_slot(Rect2(_drag_pos - Vector2(22, 22), Vector2(44, 44)), ds, Color(1, 1, 1, 0.9))
