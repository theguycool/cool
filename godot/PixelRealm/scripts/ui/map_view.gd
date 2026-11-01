class_name MapView
extends Control
## Draws the treasure map (see MapPanel.build_map) in ink and watercolour on parchment.

const BIOME_COLORS := [0x5C88B0, 0x8DB25A, 0x4E8A3E, 0xE0C878, 0xE8F0F4, 0x2F7A2A, 0xC8B058, 0x5E7048, 0x8C8478, 0x50306A]

var level: Level = null
var map := {}
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _mx(x: float) -> float:
	var span: float = float(maxi(1, int(map["x1"]) - int(map["x0"])))
	return (x - float(int(map["x0"]))) / span * size.x


func _my(y: float) -> float:
	var top: float = 20.0
	var bot: float = float(WorldGen.H) - 40.0
	return (y - top) / (bot - top) * size.y


func _label(s: String, x: float, y: float, fs: int, c: Color) -> void:
	var w: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(x - w * 0.5, y + float(fs) * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)


func _draw() -> void:
	if map.is_empty():
		return
	var w: float = size.x
	var h: float = size.y
	draw_rect(Rect2(0, 0, w, h), Color.hex(0xF0E0B4FF))
	var hs: Array = map["heights"]
	var bs: Array = map["biomes"]
	var n: int = hs.size()
	if n == 0:
		return
	var col_w: float = maxf(1.0, w / float(n) + 1.0)
	var sea_y: float = _my(float(WorldGen.SEA))
	var deep_y: float = _my(330.0)
	var paper := Color.hex(0xE8D4A0FF)
	for i in range(n):
		var x: float = float(i) / float(n) * w
		var hd: float = float(int(hs[i]))
		var b: int = int(bs[i])
		var top: float = _my(hd)
		var soil_end: float = _my(hd + 30.0)
		if b == WorldGen.OCEAN:
			draw_rect(Rect2(x, sea_y, col_w, maxf(0.0, top - sea_y)), Color.hex(0x7AA4C8FF))
		var bc := Color.hex((int(BIOME_COLORS[clampi(b, 0, BIOME_COLORS.size() - 1)]) << 8) | 0xFF)
		draw_rect(Rect2(x, top, col_w, 4.0), bc.lerp(paper, 0.25))
		draw_rect(Rect2(x, top + 4.0, col_w, maxf(0.0, soil_end - top - 4.0)), Color.hex(0xB89868FF))
		draw_rect(Rect2(x, soil_end, col_w, maxf(0.0, deep_y - soil_end)), Color.hex(0xA8906CFF))
		draw_rect(Rect2(x, deep_y, col_w, maxf(0.0, h - deep_y)), Color.hex(0x988060FF))
	# depth lines
	for d in [200.0, 330.0, 450.0]:
		var y: float = _my(float(d))
		draw_dashed_line(Vector2(0, y), Vector2(w, y), Color(0.48, 0.35, 0.23, 0.35), 1.0, 4.0)
	# markers
	var step: int = maxi(1, int(map["step"]))
	for mk in map["markers"]:
		var md: Dictionary = mk
		var mx: float = _mx(float(int(md["x"])))
		var idx: int = clampi((int(md["x"]) - int(map["x0"])) / step, 0, n - 1)
		var my: float = _my(float(int(hs[idx]))) - 10.0
		var kind: int = int(md["kind"])
		var col := Color.hex(0x5A5A5AFF)
		var sym: String = "^"
		match kind:
			0:
				col = Color.hex(0x2A6A2AFF)
				sym = "H"
			1:
				col = Color.hex(0x8A2A1AFF)
				sym = "X"
			2:
				col = Color.hex(0x5A3A8AFF)
				sym = "X"
			5:
				col = Color.hex(0x7A4A20FF)
				sym = "v"
		_label(sym, mx, my, 16, col)
		if kind <= 2:
			_label(String(md["label"]), mx, my - 14.0, 10, col)
	# the dashed ring the gate lies inside
	var span: float = float(maxi(1, int(map["x1"]) - int(map["x0"])))
	var rx: float = float(int(map["ring_rx"])) / span * w
	var ry: float = float(int(map["ring_ry"])) / (float(WorldGen.H) - 60.0) * h
	var cx: float = _mx(float(int(map["ring_x"])))
	var cy: float = _my(float(int(map["ring_y"])))
	var pts := PackedVector2Array()
	for i in range(49):
		var a: float = TAU * float(i) / 48.0
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	for i in range(0, 48, 2):
		draw_line(pts[i], pts[i + 1], Color.hex(0xC02020FF), 3.0)
	_label("?", cx, cy, 22, Color.hex(0xC02020FF))
	# you are here
	if level != null and level.dim == WorldGen.DIM_OVERWORLD:
		var pxb: float = level.player.global_position.x / 8.0
		if pxb >= float(int(map["x0"])) and pxb <= float(int(map["x1"])):
			var ux: float = _mx(pxb)
			var uy: float = _my(level.player.global_position.y / 8.0)
			draw_circle(Vector2(ux, uy), 5.0, Color.hex(0x2050D0FF))
			_label("YOU", ux, uy - 12.0, 10, Color.hex(0x2050D0FF))
	_label("W  <-  -> E", w - 60.0, 14.0, 11, Color.hex(0x5A3A1AFF))
	draw_rect(Rect2(0, 0, w, h), Color.hex(0x7A5A2AFF), false, 3.0)
