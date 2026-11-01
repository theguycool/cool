class_name WeatherPanel
extends PanelBase
## A weather station's screen: the weather now, the wind, the barometer and the coming spells.


func setup(lv: Level) -> void:
	level = lv
	setup_frame(Vector2(560, 470))
	var head: HBoxContainer = UIKit.title_row("WEATHER STATION", 20, Color(0.44, 0.94, 0.69))
	head.add_child(UIKit.button("CLOSE", Color(0.63, 0.19, 0.19), close, 0.0, 36.0))
	content.add_child(head)
	var w: Weather = lv.weather
	var list := ScrollList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(list)
	var rows: Array = []
	if lv.dim != WorldGen.DIM_OVERWORLD:
		rows.append({"kind": "text", "text": "The needles spin and settle nowhere. There is no weather here."})
	elif not bool(Game.setting("weather", true)):
		rows.append({"kind": "text", "text": "Weather is switched off in Settings."})
	else:
		rows.append({"kind": "header", "text": "NOW"})
		var wind_side: String = "from the west" if w.wind_dir > 0.0 else "from the east"
		rows.append({"text": w.name_of(w.kind), "sub": "Wind %d %s · rain %d%% · cloud %d%%" % [roundi(w.wind), wind_side, roundi(w.precip * 100.0), roundi(w.cloud * 100.0)]})
		rows.append({"text": "Barometer", "sub": w.barometer_text()})
		rows.append({"kind": "header", "text": "FORECAST"})
		var t: float = 0.0
		var fc: Array = w.forecast()
		for i in range(fc.size()):
			var e: Array = fc[i]
			var when: String = "now, for about %s" % _mins(float(e[1])) if i == 0 else "in about %s" % _mins(t)
			rows.append({"text": String(e[0]), "sub": when})
			t += float(e[1])
	list.set_rows(rows)


func _mins(secs: float) -> String:
	var m: int = maxi(1, roundi(secs / 60.0))
	return "%d minute%s" % [m, "" if m == 1 else "s"]
