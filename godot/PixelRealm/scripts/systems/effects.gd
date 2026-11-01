class_name Effects
extends Node2D
## Short-lived visuals in the world: pixel particles (dust, chips of broken blocks, blood, embers),
## floating numbers and words, the arc of a swing, the crack on a block being mined, muzzle flashes,
## explosion glows, lightning, and the glowing marks where the Hollow Warden is about to strike.
## Particles and the crack sit under the light (so they are dark in a dark cave); glows, words and
## lightning sit above it.

const MAX_PARTICLES := 600

var particles: Array = []
var texts: Array = []
var trails: Array = []
var flashes: Array = []
var bolts: Array = []
## [position, half width (px), seconds left, total seconds] (filled by the level)
var zones: Array = []
## where lightning is about to strike: [position, half width, seconds left, total]
var marks: Array = []
## the debug overlay: [[position, text], ...] and hit boxes
var debug_labels: Array = []
var debug_boxes: Array = []
## patches of fire on the ground: [x, ground y, half width, seconds left, ...] (filled by the level)
var fires: Array = []
var crack_cell := Vector2i(-99999, -99999)
var crack_stage: int = 0
var _crack_tex: Texture2D
var _glow_tex: Texture2D
var _glow: Node2D
var _top: Node2D
var _font: Font


func _ready() -> void:
	z_index = 5
	_crack_tex = Art.tex("res://assets/fx/crack.png")
	_glow_tex = Art.tex("res://assets/fx/glow.png")
	_font = ThemeDB.fallback_font
	_glow = Node2D.new()
	_glow.z_as_relative = false
	_glow.z_index = 60
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add_mat
	add_child(_glow)
	_glow.draw.connect(_draw_glow)
	_top = Node2D.new()
	_top.z_as_relative = false
	_top.z_index = 70
	add_child(_top)
	_top.draw.connect(_draw_top)


func _process(delta: float) -> void:
	var keep: Array = []
	for p in particles:
		p[2] = float(p[2]) - delta
		if float(p[2]) <= 0.0:
			continue
		var v: Vector2 = p[1]
		v.y += float(p[6]) * delta
		p[1] = v
		p[0] = (p[0] as Vector2) + v * delta
		keep.append(p)
	particles = keep
	texts = _age(texts, 2, delta)
	trails = _age(trails, 6, delta)
	flashes = _age(flashes, 2, delta)
	bolts = _age(bolts, 1, delta)
	for t in texts:
		t[1] = (t[1] as Vector2) + Vector2(0, -14.0 * delta)
	queue_redraw()
	_glow.queue_redraw()
	_top.queue_redraw()


func _age(list: Array, idx: int, delta: float) -> Array:
	var out: Array = []
	for e in list:
		e[idx] = float(e[idx]) - delta
		if float(e[idx]) > 0.0:
			out.append(e)
	return out


# ---------------------------------------------------------------------------------------------- making effects

func burst(pos: Vector2, color: Color, n: int, speed: float, life: float, grav: float = 160.0) -> void:
	for i in range(n):
		if particles.size() >= MAX_PARTICLES:
			return
		var a: float = randf() * TAU
		var v := Vector2(cos(a), sin(a)) * speed * randf_range(0.4, 1.0) + Vector2(0, -speed * 0.4)
		var c: Color = color.darkened(randf() * 0.25)
		particles.append([pos, v, life * randf_range(0.6, 1.0), life, c, randf_range(0.8, 1.6), grav])


func dust(pos: Vector2, n: int) -> void:
	for i in range(n):
		if particles.size() >= MAX_PARTICLES:
			return
		var v := Vector2(randf_range(-20.0, 20.0), randf_range(-14.0, -4.0))
		particles.append([pos + Vector2(randf_range(-3.0, 3.0), 0), v, 0.35, 0.35, Color(0.69, 0.66, 0.56, 0.9), 1.0, 30.0])


func float_text(text: String, pos: Vector2, color: Color) -> void:
	if texts.size() > 40:
		texts.pop_front()
	texts.append([text, pos, 1.0, color])


func swing_trail(origin: Vector2, angle: float, reach: float, half_arc: float, style: String, color_int: int) -> void:
	var c := Color.hex((color_int << 8) | 0xFF)
	trails.append([origin, angle, reach, half_arc, style, c, 0.16])


func muzzle(pos: Vector2) -> void:
	flashes.append([pos, 10.0, 0.08, 0.08, Color(1.0, 0.85, 0.4)])
	burst(pos, Color(1.0, 0.8, 0.3), 3, 30.0, 0.15, 0.0)


func explosion(pos: Vector2, radius: float) -> void:
	flashes.append([pos, radius * 1.4, 0.75, 0.75, Color(1.0, 0.7, 0.3)])
	burst(pos, Color(1.0, 0.75, 0.3), 18, 64.0, 0.5, 40.0)
	burst(pos, Color(0.38, 0.38, 0.38), 12, 32.0, 1.0, -24.0)


func lightning(points: Array, life: float) -> void:
	if points.size() < 2:
		return
	var jag: Array = []
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		jag.append(a)
		var n: int = maxi(2, int(a.distance_to(b) / 10.0))
		for k in range(1, n):
			var p: Vector2 = a.lerp(b, float(k) / float(n))
			jag.append(p + Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0)))
	jag.append(points[points.size() - 1])
	bolts.append([jag, life])
	for p in points:
		flashes.append([p, 28.0, life * 2.0, life * 2.0, Color(0.7, 0.85, 1.0)])


## Lights the light map should add for the glows on screen: [[cell, level], ...]
func flash_lights() -> Array:
	var out: Array = []
	for f in flashes:
		var k: float = float(f[2]) / maxf(0.001, float(f[3]))
		var lv: int = int(15.0 * k)
		if lv >= 2 and float(f[1]) > 12.0:
			var p: Vector2 = f[0]
			out.append([Vector2i(floori(p.x / 8.0), floori(p.y / 8.0)), lv])
	return out


# ---------------------------------------------------------------------------------------------- drawing

func _draw() -> void:
	for p in particles:
		var k: float = clampf(float(p[2]) / maxf(0.001, float(p[3])), 0.0, 1.0)
		var c: Color = p[4]
		c.a *= k
		var s: float = float(p[5])
		var pos: Vector2 = p[0]
		draw_rect(Rect2(pos.x - s * 0.5, pos.y - s * 0.5, s, s), c)
	if crack_cell.x != -99999:
		draw_texture_rect_region(_crack_tex, Rect2(crack_cell.x * 8, crack_cell.y * 8, 8, 8), Rect2(crack_stage * 8, 0, 8, 8), Color(1, 1, 1, 0.85))
	for t in trails:
		_draw_trail(t)


func _draw_trail(t: Array) -> void:
	var o: Vector2 = t[0]
	var ang: float = float(t[1])
	var reach: float = float(t[2])
	var half: float = float(t[3])
	var style: String = String(t[4])
	var c: Color = t[5]
	var k: float = clampf(float(t[6]) / 0.16, 0.0, 1.0)
	c.a = 0.55 * k
	if style == "thrust" or style == "stab":
		var d := Vector2(cos(ang), sin(ang))
		var n := Vector2(-d.y, d.x)
		var pts := PackedVector2Array([o + n * 1.2, o + d * reach, o - n * 1.2])
		draw_colored_polygon(pts, c)
		return
	var steps: int = 10
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in range(steps + 1):
		var a: float = ang - half + 2.0 * half * float(i) / float(steps)
		outer.append(o + Vector2(cos(a), sin(a)) * reach)
		inner.append(o + Vector2(cos(a), sin(a)) * reach * 0.62)
	var poly := PackedVector2Array()
	for p in outer:
		poly.append(p)
	for i in range(inner.size() - 1, -1, -1):
		poly.append(inner[i])
	draw_colored_polygon(poly, c)


func _draw_glow() -> void:
	for f in flashes:
		var k: float = clampf(float(f[2]) / maxf(0.001, float(f[3])), 0.0, 1.0)
		var r: float = float(f[1]) * (0.85 + 0.15 * k)
		var c: Color = f[4]
		c.a = 0.55 * k
		var p: Vector2 = f[0]
		_glow.draw_texture_rect(_glow_tex, Rect2(p.x - r, p.y - r, r * 2.0, r * 2.0), false, c)
	var tm: float = float(Time.get_ticks_msec()) / 1000.0
	for f in fires:
		var fx: float = float(f[0])
		var fy: float = float(f[1])
		var hw: float = float(f[2])
		var fade: float = clampf(float(f[3]) / 0.5, 0.0, 1.0)
		var n: int = maxi(3, int(hw / 3.0))
		for i in range(n):
			var x: float = fx - hw + (2.0 * hw) * (float(i) + 0.5) / float(n)
			var h: float = (5.0 + 4.0 * sin(tm * 11.0 + float(i) * 1.7) + 3.0 * sin(tm * 7.3 + float(i) * 2.9)) * fade
			_glow.draw_colored_polygon(PackedVector2Array([Vector2(x - 2.2, fy), Vector2(x + 2.2, fy), Vector2(x, fy - h)]), Color(1.0, 0.45, 0.1, 0.8 * fade))
			_glow.draw_colored_polygon(PackedVector2Array([Vector2(x - 1.1, fy), Vector2(x + 1.1, fy), Vector2(x, fy - h * 0.6)]), Color(1.0, 0.85, 0.35, 0.9 * fade))
	for mk in marks:
		var mp: Vector2 = mk[0]
		var mw: float = float(mk[1])
		var mk2: float = 1.0 - clampf(float(mk[2]) / maxf(0.01, float(mk[3])), 0.0, 1.0)
		var flick: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 35.0)
		_glow.draw_rect(Rect2(mp.x - mw, mp.y - 3.0, mw * 2.0, 3.0), Color(0.75, 0.88, 1.0, 0.3 + 0.6 * mk2 * flick))
		_glow.draw_rect(Rect2(mp.x - mw * 0.5, mp.y - 48.0 * mk2, mw, 48.0 * mk2), Color(0.6, 0.8, 1.0, 0.1 * mk2))
		if randf() < 0.3:
			burst(mp + Vector2(randf_range(-mw, mw), -2.0), Color(0.8, 0.92, 1.0), 1, 18.0, 0.3, -60.0)
	for z in zones:
		var zp: Vector2 = z[0]
		var hw: float = float(z[1])
		var k2: float = 1.0 - clampf(float(z[2]) / maxf(0.01, float(z[3])), 0.0, 1.0)
		var pulse: float = 0.35 + 0.35 * sin(Time.get_ticks_msec() / 60.0)
		_glow.draw_rect(Rect2(zp.x - hw, zp.y - 3.0, hw * 2.0, 3.0), Color(0.75, 0.35, 1.0, 0.3 + 0.5 * k2 * pulse))
		_glow.draw_rect(Rect2(zp.x - hw, zp.y - 40.0 * k2, hw * 2.0, 40.0 * k2), Color(0.6, 0.25, 0.9, 0.12 * k2))


func _draw_top() -> void:
	for r in debug_boxes:
		_top.draw_rect(r, Color(1.0, 0.25, 0.25, 0.9), false, 0.5)
	for d in debug_labels:
		var dl: Array = d
		var ts: String = String(dl[1])
		var dp: Vector2 = dl[0]
		var tw: float = _font.get_string_size(ts, HORIZONTAL_ALIGNMENT_LEFT, -1, 5).x
		_top.draw_string_outline(_font, dp - Vector2(tw * 0.5, 0), ts, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, 2, Color(0, 0, 0, 0.9))
		_top.draw_string(_font, dp - Vector2(tw * 0.5, 0), ts, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Color(0.6, 1.0, 0.9))
	for b in bolts:
		var pts := PackedVector2Array()
		for p in (b[0] as Array):
			pts.append(p)
		var a: float = clampf(float(b[1]) / 0.25, 0.0, 1.0)
		_top.draw_polyline(pts, Color(0.42, 0.69, 1.0, 0.55 * a), 3.0)
		_top.draw_polyline(pts, Color(0.94, 0.97, 1.0, a), 1.2)
	for t in texts:
		var a2: float = clampf(float(t[2]), 0.0, 1.0)
		var c: Color = t[3]
		c.a = a2
		var pos: Vector2 = t[1]
		var s: String = String(t[0])
		var w: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x
		_top.draw_string_outline(_font, pos - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, 2, Color(0, 0, 0, a2))
		_top.draw_string(_font, pos - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, c)
