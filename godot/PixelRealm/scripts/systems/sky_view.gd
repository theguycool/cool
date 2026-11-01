class_name SkyView
extends Node2D
## The sky behind everything (on its own canvas layer): a gradient through the day, dusk and night,
## tinted by the biome; stars at night; the sun and the moon on their arcs; and the clouds of the
## Swift game in four layers (far, middle, near, and the low storm deck that only builds under a
## heavy sky), each drifting at its own speed and following the camera less the further away it is.
## The Umbral Realm has a dark red cavern sky with distant spires instead.

const LAYERS := [
	# parallax, drift speed, cell (blocks), row top, rows, size classes, formation share, lift, haze, opacity
	[0.30, 0.45, 7.0, 0.0, 9.0, [0, 1, 2], 0.14, 0.05, 0.30, 0.80],
	[0.55, 0.75, 12.0, 1.0, 12.0, [1, 2, 3], 0.20, 0.08, 0.14, 0.90],
	[0.80, 1.00, 22.0, 3.0, 12.0, [1, 3, 4, 4], 0.25, 0.12, 0.0, 0.96],
	[0.70, 1.35, 16.0, -2.0, 7.0, [2, 4, 4], 0.30, 0.10, 0.0, 0.94],
]
const MiscData = preload("res://scripts/data/misc_data.gd")

var level: Level = null
var _clouds: Array = []
var _sun: Texture2D
var _moon: Texture2D


func _ready() -> void:
	for i in range(MiscData.CLOUD_SIZES.size()):
		_clouds.append(Art.tex("res://assets/sky/cloud_%02d.png" % i))
	_sun = Art.tex("res://assets/sky/sun.png")
	_moon = Art.tex("res://assets/sky/moon.png")


func update_sky(lv: Level, _delta: float) -> void:
	level = lv
	queue_redraw()


func _mix(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, clampf(t, 0.0, 1.0))


func _draw() -> void:
	if level == null:
		return
	var size: Vector2 = get_viewport_rect().size
	if level.dim == WorldGen.DIM_UMBRAL:
		_draw_umbral(size)
		return
	var day: float = level.day_factor()
	var t: float = level.time_of_day
	var top := _mix(Color.hex(0x060A1EFF), Color.hex(0x3E86D8FF), day)
	var bot := _mix(Color.hex(0x18223EFF), Color.hex(0xB4DCFFFF), day)
	var dusk: float = 0.0
	if t > 0.46 and t < 0.62:
		dusk = 1.0 - absf(t - 0.54) / 0.08
	if t > 0.88 or t < 0.04:
		var tt: float = t - 1.0 if t > 0.5 else t
		dusk = maxf(dusk, 1.0 - absf(tt + 0.04) / 0.08)
	dusk = clampf(dusk, 0.0, 1.0)
	bot = _mix(bot, Color.hex(0xF08A4AFF), dusk * 0.7)
	var biome: int = level.gen.biome_at(floori(level.player.global_position.x / 8.0))
	match biome:
		WorldGen.DESERT, WorldGen.SAVANNA:
			bot = _mix(bot, Color.hex(0xF0D8A0FF), 0.25 * day)
		WorldGen.TUNDRA:
			top = _mix(top, Color.hex(0xA8C0D8FF), 0.25 * day)
			bot = _mix(bot, Color.hex(0xF0F4FAFF), 0.3 * day)
		WorldGen.SWAMP:
			bot = _mix(bot, Color.hex(0x9AB08AFF), 0.35 * day)
		WorldGen.JUNGLE:
			bot = _mix(bot, Color.hex(0xA8E0B0FF), 0.2 * day)
	var w: Weather = level.weather
	var storm: float = clampf((w.cloud - 0.65) * 2.5, 0.0, 1.0)
	top = _mix(top, Color.hex(0x2A2F38FF), storm * 0.6)
	bot = _mix(bot, Color.hex(0x4A505AFF), storm * 0.6)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y)]),
		PackedColorArray([top, top, bot, bot]))
	var cover: float = w.cloud if bool(Game.setting("weather", true)) else 0.0
	# stars, hidden behind cloud
	if day < 0.6 and cover < 0.95:
		var a: float = (0.6 - day) / 0.6 * (1.0 - cover)
		for i in range(70):
			var tw: float = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 500.0 + float(i % 3) * 2.1)
			var sx: float = PRNG.hash2(i, 1, 5) * size.x
			var sy: float = PRNG.hash2(i, 2, 5) * size.y * 0.6
			var s: float = 3.0 if i % 7 == 0 else 2.0
			draw_rect(Rect2(sx, sy, s, s), Color(1, 1, 1, a * tw))
	# the sun and the moon
	var ang: float = t / 0.5 if t < 0.5 else (t - 0.5) / 0.5
	var bx: float = (0.1 + 0.8 * ang) * size.x
	var by: float = size.y * (0.55 - 0.42 * sin(ang * PI))
	var vis: float = 1.0 - 0.9 * cover
	var body: Texture2D = _sun if t < 0.5 else _moon
	var bs: float = 72.0 if t < 0.5 else 48.0
	draw_texture_rect(body, Rect2(bx - bs * 0.5, by - bs * 0.5, bs, bs), false, Color(1, 1, 1, vis))
	_draw_clouds(size, day, dusk, cover)
	if w.sky_flash > 0.01:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.87, 0.91, 1.0, w.sky_flash * 0.5))
	if level.fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.16, 0.19, level.fade))


func _draw_clouds(size: Vector2, day: float, dusk: float, cover: float) -> void:
	var cam: Camera2D = level.camera
	var zoom: float = cam.zoom.x
	var center: Vector2 = cam.get_screen_center_position()
	var view_w: float = size.x / zoom / 8.0
	var left_blocks: float = center.x / 8.0 - view_w * 0.5
	var cam_mid: float = center.y / 8.0
	var px: float = zoom
	var w: Weather = level.weather
	var tint := _mix(Color.hex(0x58628AFF), Color.WHITE, day)
	tint = _mix(tint, Color.hex(0xFFC4A0FF), dusk * 0.5)
	var storm: float = clampf((cover - 0.4) * 1.7, 0.0, 0.85) * (0.75 + 0.25 * w.precip)
	if storm > 0.0:
		tint = _mix(tint, _mix(Color.hex(0x262B33FF), Color.hex(0x6C727EFF), day), storm)
	var sky := _mix(Color.hex(0x18223EFF), Color.hex(0xB4DCFFFF), day)
	var fills: Array = [0.46 + 0.45 * cover, 0.40 + 0.52 * cover, 0.26 + 0.60 * cover, clampf((cover - 0.35) / 0.5, 0.0, 1.0) * 0.95]
	var seed_v: int = level.gen.world_seed
	for li in range(LAYERS.size()):
		var L: Array = LAYERS[li]
		var fill: float = float(fills[li])
		if fill <= 0.02:
			continue
		var par: float = float(L[0])
		var shift: float = w.cloud_drift * float(L[1])
		var cell: float = float(L[2])
		var left: float = left_blocks * par
		var c0: int = floori((left - shift - 60.0) / cell)
		var c1: int = floori((left + view_w - shift) / cell)
		var layer_tint: Color = _mix(tint, sky, float(L[8]))
		if li == 3:
			layer_tint = _mix(layer_tint, Color.hex(0x30363EFF), 0.4)
		var rise: float = clampf((112.0 - cam_mid) * float(L[7]), -3.0, 9.0)
		var s: int = seed_v + (li + 1) * 7919
		var pool: Array = L[5]
		for ci in range(c0, c1 + 1):
			var presence: float = PRNG.hash2(ci, 11, s) - (1.0 - fill)
			if presence <= 0.0:
				continue
			var alpha: float = clampf(presence / 0.1, 0.0, 1.0) * float(L[9])
			var formation: bool = PRNG.hash2(ci, 21, s) < float(L[6])
			var n: int = 3 + int(PRNG.hash2(ci, 22, s) * 3.0) if formation else 1
			var bxc: float = float(ci) * cell + PRNG.hash2(ci, 12, s) * cell * 0.8 + shift
			var byc: float = float(L[3]) + PRNG.hash2(ci, 13, s) * float(L[4])
			for k in range(n):
				var cls: int = int(pool[int(PRNG.hash2(ci, 30 + k, s) * float(pool.size())) % pool.size()])
				var ids: Array = MiscData.CLOUD_CLASSES[cls]
				var kind: int = int(ids[int(PRNG.hash2(ci, 50 + k, s) * float(ids.size())) % ids.size()])
				var dx: float = 0.0 if k == 0 else (PRNG.hash2(ci, 60 + k, s) - 0.35) * 26.0
				var dy: float = 0.0 if k == 0 else (PRNG.hash2(ci, 70 + k, s) - 0.5) * 7.0
				var flip: bool = PRNG.hash2(ci, 80 + k, s) < 0.5
				var cs: Array = MiscData.CLOUD_SIZES[kind]
				var cw: float = float(cs[0]) * px
				var chh: float = float(cs[1]) * px
				var sx: float = roundf(((bxc + dx - left) * 8.0 * zoom) / px) * px
				var sy: float = roundf(((byc + dy + rise) * 8.0 * zoom) / px) * px
				if sx > size.x or sx + cw < 0.0 or sy > size.y:
					continue
				var c: Color = layer_tint
				c.a = alpha
				var tex: Texture2D = _clouds[kind]
				if flip:
					draw_texture_rect(tex, Rect2(sx + cw, sy, -cw, chh), false, c)
				else:
					draw_texture_rect(tex, Rect2(sx, sy, cw, chh), false, c)


func _draw_umbral(size: Vector2) -> void:
	var top := Color.hex(0x0C0614FF)
	var mid := Color.hex(0x241030FF)
	var bot := Color.hex(0x5A1A12FF)
	var h2: float = size.y * 0.6
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, h2), Vector2(0, h2)]), PackedColorArray([top, top, mid, mid]))
	draw_polygon(PackedVector2Array([Vector2(0, h2), Vector2(size.x, h2), Vector2(size.x, size.y), Vector2(0, size.y)]), PackedColorArray([mid, mid, bot, bot]))
	var cam: Camera2D = level.camera
	var left: float = cam.get_screen_center_position().x * 0.35
	var step: float = 12.0
	var x: float = 0.0
	var col := Color.hex(0x1A0C22FF)
	while x < size.x:
		var n: float = PRNG.fbm1((left + x) / 160.0, 9091, 3)
		var hh: float = size.y * (0.25 + n * 0.45)
		draw_rect(Rect2(x, size.y - hh, step + 1.0, hh), col)
		x += step
	if level.fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.16, 0.19, level.fade))
