class_name PanelBase
extends Control
## The frame every panel is built in: it dims the world behind (and catches touches that miss the
## panel), centres a framed box that always fits the screen, keeps working while the game is paused,
## and closes with Escape. Panels put their contents into `content`.

var level: Level = null
var box: PanelContainer = null
var content: VBoxContainer = null
var max_size := Vector2(1000, 640)


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UIKit.theme()


## Builds the backdrop and the box (parchment for the journal and the map)
func setup_frame(size_max: Vector2, parchment: bool = false, dim: Color = Color(0, 0, 0, 0.55)) -> void:
	max_size = size_max
	var bg := ColorRect.new()
	bg.color = dim
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	box = PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIKit.frame_box(parchment))
	add_child(box)
	content = UIKit.vbox(8)
	box.add_child(content)


func _ready() -> void:
	_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit()


func _fit() -> void:
	if box == null:
		return
	var s := Vector2(minf(max_size.x, size.x - 24.0), minf(max_size.y, size.y - 24.0))
	box.custom_minimum_size = s
	box.size = s
	box.position = ((size - box.size) * 0.5).floor()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()


func close() -> void:
	if level != null:
		level.close_panel()
