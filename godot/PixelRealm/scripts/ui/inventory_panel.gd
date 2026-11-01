class_name InventoryPanel
extends PanelBase
## The bag, armour and gear on the left (see SlotBoard), and on the right the crafting list: recipes by
## category, what each costs (red when you are short), which station it needs and a MAKE button; or,
## with a chest open, the chest beside the bag; or, in creative, every item in the game to take.

const CAT_ORDER := ["basic", "build", "tools", "weapons", "armor", "gear", "smelt", "food", "vehicle", "weather", "power"]
const STATION_CAT := {"furnace": "smelt", "campfire": "food", "anvil": "weapons", "tinker": "vehicle", "forge": "weapons"}

var board: SlotBoard
var right: VBoxContainer
var list: ScrollList
var cat: String = "basic"
var only_craftable: bool = false
var creative_tab: bool = false
var _shown: Array = []
var _title: Label
var _quick_btn: Button
var _take_btn: Button
var _creative_btn: Button
var _station_label: Label
var _toggle_btn: Button
var _cat_buttons := {}


func setup(lv: Level) -> void:
	level = lv
	setup_frame(Vector2(1010, 610))
	var head: HBoxContainer = UIKit.hbox(6)
	_title = UIKit.label("INVENTORY", 20)
	head.add_child(_title)
	head.add_child(UIKit.spacer())
	if lv.player.is_creative():
		_creative_btn = UIKit.button("ALL ITEMS", Color(0.24, 0.44, 0.67), _toggle_creative, 0.0, 36.0)
		head.add_child(_creative_btn)
	head.add_child(UIKit.button("SORT", Color(0.31, 0.42, 0.54), _sort, 0.0, 36.0))
	_quick_btn = UIKit.button("QUICK STACK", Color(0.31, 0.54, 0.24), _quick_stack, 0.0, 36.0)
	_quick_btn.visible = false
	head.add_child(_quick_btn)
	_take_btn = UIKit.button("TAKE ALL", Color(0.31, 0.54, 0.24), _take_all, 0.0, 36.0)
	_take_btn.visible = false
	head.add_child(_take_btn)
	head.add_child(UIKit.button("CLOSE", Color(0.63, 0.19, 0.19), close, 0.0, 36.0))
	content.add_child(head)
	var body: HBoxContainer = UIKit.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	board = SlotBoard.new()
	board.setup(lv, Vector2i(-99999, -99999))
	body.add_child(board)
	board.changed.connect(_on_board_changed)
	right = UIKit.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_build_right()


## Opened by tapping a chest: the chest shows beside the bag
func show_chest(cell: Vector2i) -> void:
	board.setup(level, cell)
	_title.text = "INVENTORY  ·  CHEST"
	_quick_btn.visible = true
	_take_btn.visible = true
	if _creative_btn != null:
		_creative_btn.visible = false
	_build_right()


## Opened by tapping a crafting station: start on the recipes it is for
func show_station(station: String) -> void:
	if STATION_CAT.has(station):
		cat = String(STATION_CAT[station])
	_build_right()


func _exit_tree() -> void:
	# a stack still in your hand goes back into the bag (or drops) when the panel goes
	if board != null and board.carry != null:
		board.return_carried()


func close() -> void:
	board.return_carried()
	super.close()


func _sort() -> void:
	board.return_carried()
	level.player.inv.sort_bag()
	level.say("Bag sorted.", 1.2)
	board.queue_redraw()


func _quick_stack() -> void:
	board.quick_stack()


func _take_all() -> void:
	board.take_all()


func _toggle_creative() -> void:
	creative_tab = not creative_tab
	_creative_btn.text = "CRAFTING" if creative_tab else "ALL ITEMS"
	_build_right()


func _on_board_changed() -> void:
	if list != null and not board.has_chest() and not creative_tab:
		_fill_recipes(true)


# ---------------------------------------------------------------------------------------------- the right column

func _build_right() -> void:
	for c in right.get_children():
		right.remove_child(c)
		c.queue_free()
	list = null
	_cat_buttons.clear()
	right.visible = not board.has_chest()
	if board.has_chest():
		return
	if creative_tab and level.player.is_creative():
		right.add_child(UIKit.label("ALL ITEMS  ·  tap one to take a full stack", 15))
		list = _new_list()
		var rows: Array = []
		for id in DB.item_order:
			rows.append({"icon": Art.icon(String(id)), "text": DB.item_name(String(id)), "buttons": [["TAKE", Color(0.31, 0.54, 0.24)]]})
		_shown = DB.item_order.duplicate()
		list.set_rows(rows)
		return
	right.add_child(UIKit.label("CRAFTING", 15))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in CAT_ORDER:
		var b: Button = UIKit.button(String(DB.CATEGORY_NAMES.get(c, c)), Color(0.31, 0.54, 0.24) if c == cat else Color(0.33, 0.33, 0.33), _pick_cat.bind(String(c)), 0.0, 32.0)
		b.add_theme_font_size_override("font_size", 13)
		flow.add_child(b)
		_cat_buttons[c] = b
	right.add_child(flow)
	var row: HBoxContainer = UIKit.hbox(6)
	_station_label = UIKit.label(_station_text(), 12, Color(1, 1, 1, 0.75), true)
	row.add_child(_station_label)
	_toggle_btn = UIKit.button("CAN MAKE" if only_craftable else "SHOW ALL", Color(0.33, 0.33, 0.33), _toggle_only, 0.0, 30.0)
	_toggle_btn.add_theme_font_size_override("font_size", 13)
	row.add_child(_toggle_btn)
	right.add_child(row)
	list = _new_list()
	_fill_recipes(false)


func _new_list() -> ScrollList:
	var l := ScrollList.new()
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.font_size = 14
	l.row_tapped.connect(_on_row)
	right.add_child(l)
	return l


func _pick_cat(c: String) -> void:
	cat = c
	for k in _cat_buttons.keys():
		var b: Button = _cat_buttons[k]
		var col: Color = Color(0.31, 0.54, 0.24) if String(k) == cat else Color(0.33, 0.33, 0.33)
		b.add_theme_stylebox_override("normal", UIKit.button_box(col))
		b.add_theme_stylebox_override("hover", UIKit.button_box(col.lightened(0.12)))
	_fill_recipes(false)


func _toggle_only() -> void:
	only_craftable = not only_craftable
	_toggle_btn.text = "CAN MAKE" if only_craftable else "SHOW ALL"
	_fill_recipes(false)


func _fill_recipes(keep_scroll: bool) -> void:
	if list == null:
		return
	if _station_label != null:
		_station_label.text = _station_text()
	var rows: Array = []
	_shown = []
	var inv: Inventory = level.player.inv
	var creative: bool = level.player.is_creative()
	for r in DB.recipes:
		var rd: Dictionary = r
		if String(rd["cat"]) != cat:
			continue
		var ok: bool = can_craft(rd)
		if only_craftable and not ok:
			continue
		var out: String = String(rd["out"])
		var n: int = int(rd["count"])
		var costs: Array = []
		for c in rd["cost"]:
			var ca: Array = c
			var enough: bool = creative or inv.total(String(ca[0])) >= int(ca[1])
			costs.append([Art.icon(String(ca[0])), str(int(ca[1])), Color.WHITE if enough else Color(1.0, 0.38, 0.38)])
		var row := {"icon": Art.icon(out), "text": DB.item_name(out) + (" x%d" % n if n > 1 else ""), "icons": costs,
			"buttons": [["MAKE", Color(0.31, 0.54, 0.24) if ok else Color(0.27, 0.27, 0.27)]]}
		if not station_available(String(rd["station"])):
			row["sub"] = "Needs a %s" % String(DB.STATION_NAMES.get(String(rd["station"]), "station"))
			row["sub_color"] = Color(1.0, 0.54, 0.38)
		rows.append(row)
		_shown.append(rd)
	if rows.is_empty():
		rows.append({"kind": "text", "text": "Nothing you can make here yet." if only_craftable else "No recipes in this group."})
	list.set_rows(rows, keep_scroll)


func _on_row(i: int, button_index: int) -> void:
	if i < 0 or i >= _shown.size():
		return
	if creative_tab:
		var id: String = String(_shown[i])
		var n: int = DB.max_stack(id)
		var extra: int = int(DB.gun_info(id).get("magazine", 0)) if DB.kind_of(id) == "gun" else 0
		var left: int = level.player.inv.add(id, n, extra)
		if left == n:
			level.say("Your bag is full.", 1.2)
		else:
			Sfx.play("pickup", 0.5)
		board.queue_redraw()
		return
	var rd: Dictionary = _shown[i]
	board.info_stack = Inventory.make(String(rd["out"]), int(rd["count"]))
	board.queue_redraw()
	if button_index == 0:
		craft(rd)


# ---------------------------------------------------------------------------------------------- crafting

## Whether a station is close enough to use (within 5 blocks; creative needs none)
func station_available(s: String) -> bool:
	if s == "hand" or level.player.is_creative():
		return true
	var w: WorldData = level.world
	var px: int = floori(level.player.global_position.x / 8.0)
	var py: int = floori((level.player.global_position.y - 8.0) / 8.0)
	for dy in range(-4, 4):
		for dx in range(-5, 6):
			var t: int = w.get_tile(px + dx, py + dy)
			match s:
				"bench":
					if t == T.WORKBENCH:
						return true
				"furnace":
					if t == T.FURNACE:
						return true
				"campfire":
					if t == T.FURNACE or t == T.CAMPFIRE:
						return true
				"anvil":
					if t == T.ANVIL:
						return true
				"tinker":
					if t == T.TINKER_BENCH:
						return true
				"forge":
					if t == T.RIFT_FORGE:
						return true
	return false


func can_craft(r: Dictionary) -> bool:
	if not station_available(String(r["station"])):
		return false
	var inv: Inventory = level.player.inv
	if not level.player.is_creative() and not inv.can_afford(r["cost"]):
		return false
	return inv.can_fit(String(r["out"]), int(r["count"]))


func craft(r: Dictionary) -> void:
	var p: Player = level.player
	var out: String = String(r["out"])
	var n: int = int(r["count"])
	if not can_craft(r):
		if not station_available(String(r["station"])):
			level.say("Needs a %s nearby." % String(DB.STATION_NAMES.get(String(r["station"]), "station")), 2.0)
		elif not p.inv.can_fit(out, n):
			level.say("No room in your bag.", 1.5)
		else:
			level.say("You need more materials.", 1.2)
		return
	if not p.is_creative():
		p.inv.pay(r["cost"])
	level.journal.note_crafted(DB.item_name(out))
	Sfx.play("craft", 0.6)
	# a new storm rod comes charged; firearms and crossbows still need loading
	var ex: int = int(DB.gun_info(out).get("magazine", 0)) if out == "gun:stormRod" else 0
	var left: int = p.inv.add(out, n, ex)
	if left > 0:
		level.spawn_drop(out, left, p.global_position + Vector2(0, -8), Vector2(16, -24), ex)
	level.float_text("+%d %s" % [n, DB.item_name(out)], p.global_position + Vector2(0, -18), Color(1.0, 0.88, 0.44))
	board.queue_redraw()
	_fill_recipes(true)


func _station_text() -> String:
	var s: Array = ["Hand"]
	if station_available("bench"):
		s.append("Workbench")
	if station_available("furnace"):
		s.append("Furnace")
	elif station_available("campfire"):
		s.append("Campfire")
	for st in ["anvil", "tinker", "forge"]:
		if station_available(String(st)):
			s.append(String(DB.STATION_NAMES[st]))
	return "Near: " + ", ".join(PackedStringArray(s))
