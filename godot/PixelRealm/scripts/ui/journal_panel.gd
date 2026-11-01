class_name JournalPanel
extends PanelBase
## The journal, on parchment: goals worth chasing (ticked off as you go), the places you have found
## and when, the stories they told, and your notes on the weather.

const INK := Color(0.23, 0.14, 0.06)
const INK_SOFT := Color(0.42, 0.29, 0.16)

var list: ScrollList
var tab: int = 0
var _tabs: Array = []


func setup(lv: Level) -> void:
	level = lv
	setup_frame(Vector2(840, 580), true)
	var head: HBoxContainer = UIKit.hbox(6)
	head.add_child(UIKit.ink("JOURNAL", 22, Color(0.29, 0.16, 0.06)))
	head.add_child(UIKit.spacer())
	var names: Array = ["GOALS", "PLACES", "LORE", "WEATHER"]
	for i in range(names.size()):
		var b: Button = UIKit.button(String(names[i]), _tab_color(i), _pick.bind(i), 0.0, 36.0)
		head.add_child(b)
		_tabs.append(b)
	head.add_child(UIKit.button("CLOSE", Color(0.63, 0.19, 0.19), close, 0.0, 36.0))
	content.add_child(head)
	list = ScrollList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.text_color = INK
	list.sub_color = INK_SOFT
	list.header_color = Color(0.29, 0.16, 0.06)
	list.row_bg = Color(0.35, 0.23, 0.1, 0.08)
	content.add_child(list)
	_fill()


func _tab_color(i: int) -> Color:
	return Color(0.48, 0.35, 0.16) if i == tab else Color(0.66, 0.56, 0.42)


func _pick(i: int) -> void:
	tab = i
	for k in range(_tabs.size()):
		var b: Button = _tabs[k]
		b.add_theme_stylebox_override("normal", UIKit.button_box(_tab_color(k)))
		b.add_theme_stylebox_override("hover", UIKit.button_box(_tab_color(k).lightened(0.1)))
	_fill()


func _fill() -> void:
	var rows: Array = []
	var j: Journal = level.journal
	match tab:
		0:
			for g in j.goals(level):
				var ga: Array = g
				var done: bool = bool(ga[2])
				var row := {"text": ("[x] " if done else "[ ] ") + String(ga[0]), "color": Color(0.16, 0.42, 0.16) if done else INK}
				if not done:
					row["sub"] = String(ga[1])
				rows.append(row)
		1:
			if j.places.is_empty():
				rows.append({"kind": "text", "text": "Nothing yet. The world is wide: ruins, old mines and stranger places are out there."})
			for p in j.places:
				var pd: Dictionary = p
				rows.append({"text": String(pd["name"]), "sub": _where(pd)})
		2:
			var any: bool = false
			for k in j.lore:
				var key: String = String(k)
				if key.begins_with("wx.") or not Journal.LORE.has(key):
					continue
				any = true
				var e: Array = Journal.LORE[key]
				rows.append({"text": String(e[0]), "sub": String(e[1])})
			if not any:
				rows.append({"kind": "text", "text": "Places you find will tell you something. Their stories collect here."})
		_:
			var w: Weather = level.weather
			rows.append({"kind": "header", "text": "NOW"})
			rows.append({"text": w.name_of(w.kind), "sub": "Wind %d · %s" % [roundi(w.wind), w.barometer_text()]})
			var notes: bool = false
			for k in j.lore:
				var key2: String = String(k)
				if key2.begins_with("wx.") and Journal.LORE.has(key2):
					if not notes:
						rows.append({"kind": "header", "text": "NOTES"})
						notes = true
					var e2: Array = Journal.LORE[key2]
					rows.append({"text": String(e2[0]), "sub": String(e2[1])})
			if not notes:
				rows.append({"kind": "text", "text": "Live through a storm or two and your notes on the weather will collect here."})
	list.set_rows(rows)


## Where a place lies, in words: how far east or west of where you started, and the day it was found
func _where(p: Dictionary) -> String:
	var d: int = int(p["x"]) - level.gen.spawn_x
	var side: String = "by your first camp"
	if absi(d) >= 30:
		side = "%s %s of your start" % [MapPanel.rough_distance(absi(d)), "east" if d > 0 else "west"]
	return "%s%s, day %d" % ["Umbral, " if int(p.get("dim", 0)) == 1 else "", side, int(p["day"])]
