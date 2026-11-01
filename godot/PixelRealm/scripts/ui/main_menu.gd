class_name MainMenu
extends Control
## The title screen: continue the last world, start a new one (name, seed, survival, creative or
## hardcore, a classic 4096-wide world or an endless one, normal or flat terrain with its options),
## load or delete saved worlds, pick the hero's hair and scarf, change settings and read how to play.

const MiscData = preload("res://scripts/data/misc_data.gd")
const SPLASHES := ["Beware the Bear!", "Find the hidden gate!", "Ride a T-Rex!", "Build a car. Then a boat.",
	"Torches keep the dark away!", "Infinite worlds!", "Mind the hail!", "Now on Godot!"]

const HELP := [
	"Move with the stick on the left (or A/D). JUMP (W/Space) jumps; pull the stick down to drop through platforms and to climb down ladders.",
	"Touch the world to mine, attack, place or use what is in your hand where you touch. Tap a door, chest or crafting station to use it.",
	"The round attack stick on the right: touch and hold to attack and let go to stop. With your thumb in the middle it aims for you (the nearest foe in reach, or the block in front). Slide your thumb out to aim by hand in any direction: blades swing that way, bows and guns shoot that way, slings and flasks land further the further you push, pickaxes dig the first block that way and blocks go against it.",
	"The swap button above JUMP (or Q) switches to the next weapon in your hotbar; from a tool it goes back to the weapon you used last.",
	"Hotbar: tap a slot. BAG opens your inventory, armour and crafting. In the bag: tap to pick up and put down, hold to split a stack or put on armour, drag to move.",
	"Craft a workbench, then a furnace. Near the top you find coal, copper, saltpeter and tin; iron and silver lie deeper, gold, diamond and mythril deepest.",
	"Smelt copper and tin into bronze. Iron and better gear is forged on an anvil, machinery and vehicle kits at a tinker's bench, Umbral metals only at a rift forge.",
	"Weapons: swords sweep in front of you; spears reach far; hammers are slow and heavy; knives are quick and cut deep from behind; clubs daze.",
	"Ranged: the bow is drawn and loosed; the sling throws any stone you carry; crossbows and guns load and reload; the storm rod's lightning leaps between foes.",
	"Two gear slots hold a headlamp, swift boots, a diving mask, a silver charm and more.",
	"LOG (or J) opens your journal: places you have found, their stories and goals worth chasing.",
	"Torches, lanterns and campfires light the dark. Monsters keep away from light; undead burn at sunrise.",
	"Old mines (a timber headframe on the surface) run deep. Look for chests in rooms and at dead ends.",
	"Eat to stay fed. Cook meat at a campfire. Hunger at zero hurts you.",
	"Defeat Ursavor the giant bear for a Portal Key and a Treasure Map; the map hints where the hidden gate is.",
	"Beat Tyrannax the T-Rex and it becomes your companion. Tap it to ride.",
	"Vehicles: craft a Car Kit, Rowboat Kit or Motorboat Kit at a tinker's bench and tap the ground (or the water) to place it. Stand next to it and press DRIVE; PACK UP puts it back in your bag.",
	"Watch the ground in big fights: an attack's area glows just before it lands. Step out of it.",
	"Weather comes and goes: rain, thunderstorms, wind, hail, snow and blizzards, and rare tornadoes and hurricanes with a warning first. In a thunderstorm keep off high, open ground.",
	"Zoom with + and -. DBG opens the debug menu. II pauses and saves.",
	"Keyboard: A/D move, W jump, S down, 1-0 hotbar, Q next weapon, E bag, M map, J journal, F attack/use, R reload, F3 debug, Esc pause.",
]

var bg: MenuBackground
var holder: VBoxContainer
var box: PanelContainer
var screen: String = "main"
var name_edit: LineEdit
var seed_edit: LineEdit
var mode: String = "survival"
var infinite: bool = false
var flat: bool = false
var flat_trees: bool = true
var flat_structures: bool = true
var flat_caves: bool = true
var _list: ScrollList
var _rows: Array = []
var _slots: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	bg = MenuBackground.new()
	bg.hair = int(Game.setting("hair", 0))
	bg.scarf = int(Game.setting("scarf", 0))
	add_child(bg)
	holder = UIKit.vbox(10)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	resized.connect(_layout)
	Sfx.stop_loops()
	_show("main")


func _layout() -> void:
	var w: float = minf(size.x - 32.0, 960.0 if screen == "new" else 620.0)
	holder.custom_minimum_size = Vector2(w, 0)
	holder.size = Vector2(w, size.y - 24.0)
	holder.position = Vector2(floorf((size.x - w) * 0.5), 12.0)


func _clear() -> void:
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	_list = null


func _show(s: String) -> void:
	screen = s
	_clear()
	_title()
	match s:
		"main":
			_main()
		"new":
			_new_world()
		"load":
			_load_list()
		"character":
			_character()
		"settings":
			_settings()
		"help":
			_help()
	_layout()


func _title() -> void:
	var logo := TextureRect.new()
	logo.texture = Art.tex("res://assets/ui/logo.png")
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.custom_minimum_size = Vector2(0, 72 if screen == "main" else 44)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(logo)
	if screen == "main":
		var sp: Label = UIKit.label(String(SPLASHES[randi() % SPLASHES.size()]), 18, Color(1.0, 0.96, 0.54))
		sp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sp.rotation_degrees = -2.0
		holder.add_child(sp)


func _panel() -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UIKit.frame_box(false))
	pc.size_flags_vertical = Control.SIZE_EXPAND_FILL if (screen == "settings" or screen == "help" or screen == "load") else Control.SIZE_SHRINK_BEGIN
	holder.add_child(pc)
	var v: VBoxContainer = UIKit.vbox(8)
	pc.add_child(v)
	return v


# ---------------------------------------------------------------------------------------------- screens

func _main() -> void:
	_slots = _saved_worlds()
	var v: VBoxContainer = UIKit.vbox(10)
	holder.add_child(v)
	if not _slots.is_empty():
		var m: Dictionary = _slots[0]
		v.add_child(UIKit.button("CONTINUE: " + String(m.get("name", "World")).to_upper(), Color(0.31, 0.54, 0.24), _load_slot.bind(int(m["slot"])), 0.0, 52.0))
	v.add_child(UIKit.button("NEW WORLD", Color(0.24, 0.44, 0.67), _show.bind("new"), 0.0, 52.0))
	if not _slots.is_empty():
		v.add_child(UIKit.button("LOAD WORLD", Color(0.42, 0.42, 0.42), _show.bind("load"), 0.0, 48.0))
	var row: HBoxContainer = UIKit.hbox(10)
	var c: Button = UIKit.button("CHARACTER", Color(0.54, 0.35, 0.18), _show.bind("character"), 0.0, 48.0)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(c)
	var st: Button = UIKit.button("SETTINGS", Color(0.42, 0.42, 0.42), _show.bind("settings"), 0.0, 48.0)
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(st)
	v.add_child(row)
	v.add_child(UIKit.button("HOW TO PLAY", Color(0.42, 0.42, 0.42), _show.bind("help"), 0.0, 48.0))
	var ver: Label = UIKit.label("PixelRealm for Godot / Xogot · pixel art from the original game", 12, Color(1, 1, 1, 0.85))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ver)


func _choice(text: String, on: bool, col: Color, cb: Callable) -> Button:
	var b: Button = UIKit.button(text, col if on else Color(0.33, 0.33, 0.33), cb, 0.0, 42.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 14)
	return b


func _new_world() -> void:
	var v: VBoxContainer = _panel()
	v.add_child(UIKit.label("NEW WORLD", 20))
	var cols: HBoxContainer = UIKit.hbox(16)
	v.add_child(cols)
	var left: VBoxContainer = UIKit.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right: VBoxContainer = UIKit.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var old_name: String = name_edit.text if name_edit != null and is_instance_valid(name_edit) else "My World"
	var old_seed: String = seed_edit.text if seed_edit != null and is_instance_valid(seed_edit) else ""
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "World name"
	name_edit.text = old_name
	name_edit.custom_minimum_size = Vector2(0, 44)
	left.add_child(name_edit)
	var modes: HBoxContainer = UIKit.hbox(6)
	modes.add_child(_choice("SURVIVAL", mode == "survival", Color(0.31, 0.54, 0.24), _set_mode.bind("survival")))
	modes.add_child(_choice("CREATIVE", mode == "creative", Color(0.24, 0.44, 0.67), _set_mode.bind("creative")))
	modes.add_child(_choice("HARDCORE", mode == "hardcore", Color(0.63, 0.19, 0.19), _set_mode.bind("hardcore")))
	left.add_child(modes)
	var size_row: HBoxContainer = UIKit.hbox(6)
	size_row.add_child(_choice("CLASSIC", not infinite, Color(0.54, 0.42, 0.18), _set_infinite.bind(false)))
	size_row.add_child(_choice("INFINITE", infinite, Color(0.54, 0.42, 0.18), _set_infinite.bind(true)))
	left.add_child(size_row)
	var blurb: String = "Endless world that streams in as you explore." if infinite else "A large world (4096 wide) with every biome and ocean edges."
	left.add_child(UIKit.label(blurb, 13, Color.WHITE, true))
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "Seed (optional)"
	seed_edit.text = old_seed
	seed_edit.custom_minimum_size = Vector2(0, 44)
	left.add_child(seed_edit)
	var terrain: HBoxContainer = UIKit.hbox(6)
	terrain.add_child(_choice("NORMAL", not flat, Color(0.31, 0.48, 0.23), _set_flat.bind(false)))
	terrain.add_child(_choice("FLAT", flat, Color(0.31, 0.48, 0.23), _set_flat.bind(true)))
	right.add_child(terrain)
	var tb: String = "Hills, mountains, caves and seas."
	if flat:
		tb = "Level ground everywhere with the same layers below (topsoil, stone, slate and deep rock with ores) on bedrock. The portal chamber is still buried deep below."
	right.add_child(UIKit.label(tb, 13, Color.WHITE, true))
	if flat:
		var opts: HBoxContainer = UIKit.hbox(6)
		opts.add_child(_choice("NATURE ON" if flat_trees else "NATURE OFF", flat_trees, Color(0.31, 0.48, 0.23), _flip.bind("trees")))
		opts.add_child(_choice("BUILDINGS ON" if flat_structures else "BUILDINGS OFF", flat_structures, Color(0.31, 0.48, 0.23), _flip.bind("structures")))
		opts.add_child(_choice("CAVES ON" if flat_caves else "CAVES OFF", flat_caves, Color(0.31, 0.48, 0.23), _flip.bind("caves")))
		right.add_child(opts)
		var parts: Array = []
		parts.append("Trees, plants and ponds." if flat_trees else "Bare ground: no trees, plants or ponds.")
		parts.append("Ruins, old mines and the two boss lairs (open arenas)." if flat_structures else "No ruins, mines or boss lairs.")
		parts.append("Caves open only deep below an unbroken crust." if flat_caves else "Solid underground: dig your own tunnels.")
		right.add_child(UIKit.label(" ".join(PackedStringArray(parts)), 12, Color(1, 1, 1, 0.85), true))
	var buttons: HBoxContainer = UIKit.hbox(10)
	var create: Button = UIKit.button("CREATE", Color(0.31, 0.54, 0.24), _create, 0.0, 50.0)
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(create)
	var back: Button = UIKit.button("BACK", Color(0.42, 0.42, 0.42), _show.bind("main"), 0.0, 50.0)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(back)
	v.add_child(buttons)


func _set_mode(m: String) -> void:
	mode = m
	_show("new")


func _set_infinite(on: bool) -> void:
	infinite = on
	_show("new")


func _set_flat(on: bool) -> void:
	flat = on
	_show("new")


func _flip(what: String) -> void:
	match what:
		"trees":
			flat_trees = not flat_trees
		"structures":
			flat_structures = not flat_structures
		"caves":
			flat_caves = not flat_caves
	_show("new")


func _create() -> void:
	var nm: String = name_edit.text.strip_edges()
	if nm == "":
		nm = "My World"
	var params := {"name": nm, "seed": seed_edit.text.strip_edges(), "mode": mode, "infinite": infinite,
		"flat": flat, "trees": flat_trees if flat else true, "ponds": flat_trees if flat else false,
		"structures": flat_structures if flat else true, "caves": flat_caves if flat else false,
		"slot": Game.first_free_slot()}
	Game.start_new_world(params)


func _saved_worlds() -> Array:
	var out: Array = []
	for m in Game.list_slots():
		var md: Dictionary = m
		if not md.is_empty():
			out.append(md)
	out.sort_custom(_newer)
	return out


func _newer(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("time", 0.0)) > float(b.get("time", 0.0))


func _load_list() -> void:
	var v: VBoxContainer = _panel()
	var head: HBoxContainer = UIKit.title_row("LOAD WORLD", 20)
	head.add_child(UIKit.button("BACK", Color(0.42, 0.42, 0.42), _show.bind("main"), 0.0, 40.0))
	v.add_child(head)
	_list = ScrollList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.row_tapped.connect(_on_load_row)
	v.add_child(_list)
	_fill_saves()


func _fill_saves() -> void:
	_slots = _saved_worlds()
	_rows = []
	for m in _slots:
		var md: Dictionary = m
		var kind: String = ("Infinite" if bool(md.get("infinite", true)) else "Classic") + (" Flat" if bool(md.get("flat", false)) else "")
		var mins: int = int(float(md.get("play_seconds", 0.0)) / 60.0)
		_rows.append({"text": String(md.get("name", "World")),
			"sub": "%s · %s · Day %d · %d min" % [String(md.get("mode", "survival")).capitalize(), kind, int(md.get("day", 1)), mins],
			"buttons": [["PLAY", Color(0.31, 0.54, 0.24)], ["DEL", Color(0.63, 0.19, 0.19)]]})
	if _rows.is_empty():
		_rows.append({"kind": "text", "text": "No saved worlds."})
	_list.set_rows(_rows)


func _on_load_row(i: int, b: int) -> void:
	if i >= _slots.size():
		return
	var slot: int = int((_slots[i] as Dictionary)["slot"])
	if b == 1:
		Game.delete_slot(slot)
		Sfx.play("tap", 0.5)
		_fill_saves()
	elif b == 0 or b == -1:
		_load_slot(slot)


func _load_slot(slot: int) -> void:
	Game.load_world(slot)


func _character() -> void:
	var v: VBoxContainer = _panel()
	v.add_child(UIKit.label("CHARACTER", 20))
	v.add_child(UIKit.label("Brown-shirted adventurer. Pick a hair and a scarf colour: your hero stands in the meadow behind this box.", 13, Color.WHITE, true))
	v.add_child(_swatches("HAIR", MiscData.HAIR, int(Game.setting("hair", 0)), "hair"))
	v.add_child(_swatches("SCARF", MiscData.SCARF, int(Game.setting("scarf", 0)), "scarf"))
	v.add_child(UIKit.button("DONE", Color(0.31, 0.54, 0.24), _show.bind("main"), 0.0, 48.0))


func _swatches(label_text: String, colors: Array, sel: int, key: String) -> HBoxContainer:
	var row: HBoxContainer = UIKit.hbox(6)
	var l: Label = UIKit.label(label_text, 15)
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	for i in range(colors.size()):
		var col := Color.hex((int(colors[i]) << 8) | 0xFF)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(48, 48)
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_border_width_all(4 if i == sel else 2)
		sb.border_color = Color.WHITE if i == sel else Color.BLACK
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.pressed.connect(_pick_color.bind(key, i))
		row.add_child(b)
	return row


func _pick_color(key: String, i: int) -> void:
	Game.set_setting(key, i)
	Sfx.play("tap", 0.5)
	bg.hair = int(Game.setting("hair", 0))
	bg.scarf = int(Game.setting("scarf", 0))
	bg.refresh_hero()
	_show("character")


func _settings() -> void:
	var v: VBoxContainer = _panel()
	var head: HBoxContainer = UIKit.title_row("SETTINGS", 20)
	head.add_child(UIKit.button("DONE", Color(0.31, 0.54, 0.24), _show.bind("main"), 0.0, 40.0))
	v.add_child(head)
	_list = ScrollList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.row_tapped.connect(_on_setting)
	v.add_child(_list)
	_rows = UIKit.fresh_settings_rows()
	_list.set_rows(_rows)


func _on_setting(i: int, b: int) -> void:
	_rows = UIKit.settings_tap(_rows, i, b)
	_list.set_rows(_rows, true)


func _help() -> void:
	var v: VBoxContainer = _panel()
	var head: HBoxContainer = UIKit.title_row("HOW TO PLAY", 20)
	head.add_child(UIKit.button("GOT IT", Color(0.31, 0.54, 0.24), _show.bind("main"), 0.0, 40.0))
	v.add_child(head)
	var list := ScrollList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.font_size = 14
	v.add_child(list)
	var rows: Array = []
	for line in HELP:
		rows.append({"text": "• " + String(line)})
	list.set_rows(rows)
