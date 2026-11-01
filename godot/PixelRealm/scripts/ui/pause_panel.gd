class_name PausePanel
extends PanelBase
## The pause menu: resume, save, save and quit, and every setting (the game stays paused meanwhile).

var list: ScrollList
var _note: Label
var _rows: Array = []


func setup(lv: Level) -> void:
	level = lv
	setup_frame(Vector2(900, 600), false, Color(0, 0, 0, 0.6))
	var head: HBoxContainer = UIKit.title_row("PAUSED", 28)
	content.add_child(head)
	var kind: String = "Infinite" if lv.infinite else "Classic"
	var flat: String = " · Flat" if bool(lv.options.get("flat", false)) else ""
	content.add_child(UIKit.label("%s · %s · %s%s · Day %d" % [lv.world_name, lv.mode.capitalize(), kind, flat, lv.day_count], 14, Color(1, 1, 1, 0.8)))
	var body: HBoxContainer = UIKit.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	var left: VBoxContainer = UIKit.vbox(10)
	left.custom_minimum_size = Vector2(240, 0)
	left.add_child(UIKit.button("RESUME", Color(0.31, 0.54, 0.24), close, 240.0, 48.0))
	left.add_child(UIKit.button("SAVE GAME", Color(0.24, 0.44, 0.67), _save, 240.0, 48.0))
	left.add_child(UIKit.button("JOURNAL", Color(0.48, 0.35, 0.16), _journal, 240.0, 44.0))
	left.add_child(UIKit.button("SAVE & QUIT", Color(0.63, 0.19, 0.19), _quit, 240.0, 48.0))
	_note = UIKit.label("", 14)
	left.add_child(_note)
	body.add_child(left)
	list = ScrollList.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.row_tapped.connect(_on_row)
	body.add_child(list)
	_rows = UIKit.fresh_settings_rows()
	list.set_rows(_rows)


func _on_row(i: int, b: int) -> void:
	_rows = UIKit.settings_tap(_rows, i, b)
	list.set_rows(_rows, true)


func _save() -> void:
	if level.mode == "hardcore" and level.hardcore_over:
		_note.text = "This world is lost."
		return
	level.save_game()
	_note.text = "Saved!"


func _journal() -> void:
	level.open_panel("journal")


func _quit() -> void:
	Game.quit_to_menu()
