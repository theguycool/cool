class_name WeatherFX
extends Node2D
## Rain, snow and hail falling over the view (stopping at the first roof or ground in each column),
## slanting with the wind, and a tornado's funnel when one is about. Drawn over the world.

var level: Level = null
var _t: float = 0.0


func _ready() -> void:
	z_index = 65
	level = get_parent() as Level


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if level == null or level.player == null or level.dim != WorldGen.DIM_OVERWORLD:
		return
	var w: Weather = level.weather
	var vr: Rect2i = level.view_rect()
	var x0: float = vr.position.x * 8.0
	var y0: float = vr.position.y * 8.0
	var vw: float = vr.size.x * 8.0
	var vh: float = vr.size.y * 8.0
	var amount: float = w.rain_here(level)
	if amount > 0.02:
		var snow: bool = w.snowing(level)
		var hail: bool = w.hail > 0.3 and not snow
		var n: int = int(amount * (160.0 if snow else 260.0))
		var slant: float = w.wind * w.wind_dir * (2.2 if snow else 1.2)
		var fall: float = 40.0 if snow else (150.0 if hail else 210.0)
		var rain_col := Color(0.68, 0.78, 0.94, 0.55)
		var snow_col := Color(0.97, 0.98, 1.0, 0.9)
		for i in range(n):
			var hx: float = PRNG.hash2(i, 11, 77)
			var hy: float = PRNG.hash2(i, 12, 77)
			var sp: float = 0.8 + 0.4 * PRNG.hash2(i, 13, 77)
			var px: float = x0 + fposmod(hx * vw + (slant * _t * sp) + (sin(_t * 2.0 + float(i)) * 3.0 if snow else 0.0), vw)
			var py: float = y0 + fposmod(hy * vh + fall * _t * sp, vh)
			var col: int = floori(px / 8.0)
			if floori(py / 8.0) >= level.world.sky_top(col):
				continue
			if snow:
				draw_rect(Rect2(px, py, 1.0, 1.0), snow_col)
			elif hail:
				draw_rect(Rect2(px, py, 1.2, 1.2), Color(0.86, 0.92, 1.0, 0.9))
			else:
				draw_line(Vector2(px, py), Vector2(px - slant * 0.02, py - 3.5), rain_col, 0.6)
	if w.tornado_on:
		var tx: float = w.tornado_x
		var ground: float = level.world.sky_top(floori(tx / 8.0)) * 8.0
		for k in range(40):
			var f: float = float(k) / 40.0
			var yy: float = ground - f * 220.0
			var r: float = 3.0 + f * f * 40.0
			var a: float = _t * 6.0 + f * 9.0
			var px2: float = tx + sin(a) * r + sin(_t * 0.7 + f * 3.0) * 6.0
			draw_rect(Rect2(px2 - 2.0, yy - 2.0, 4.0, 4.0), Color(0.35, 0.37, 0.4, 0.55))
			draw_rect(Rect2(tx + sin(a + PI) * r - 1.5, yy - 1.5, 3.0, 3.0), Color(0.5, 0.48, 0.42, 0.45))
