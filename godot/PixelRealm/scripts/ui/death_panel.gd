class_name DeathPanel
extends PanelBase
## The death screen: respawn at your spawn point, or (hardcore) the world is gone.


func setup(lv: Level) -> void:
	level = lv
	setup_frame(Vector2(420, 330), false, Color(0.44, 0.0, 0.0, 0.45))
	var hard: bool = lv.mode == "hardcore"
	var t: Label = UIKit.label("GAME OVER" if hard else "YOU DIED", 36)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(t)
	var s: Label = UIKit.label("Kills: %d    Days: %d" % [lv.kills, lv.day_count], 16)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(s)
	if hard:
		var w: Label = UIKit.label("This hardcore world has been deleted.", 14)
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(w)
	else:
		content.add_child(UIKit.button("RESPAWN", Color(0.31, 0.54, 0.24), _respawn, 0.0, 50.0))
	content.add_child(UIKit.button("MAIN MENU", Color(0.63, 0.19, 0.19), _menu, 0.0, 50.0))


func _respawn() -> void:
	level.respawn()


func _menu() -> void:
	Game.quit_to_menu()


## Escape does not dismiss death
func close() -> void:
	pass
