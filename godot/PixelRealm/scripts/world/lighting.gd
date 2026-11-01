class_name Lighting
extends Sprite2D
## Light over the window around the camera, as in the Swift game: sunlight falls straight down every
## open column, then both sunlight and the light of torches, lava, crystals and other glowing blocks
## spread outward a level at a time (one level per open block, two per solid one). The result is a
## small greyscale image, stretched over the world and multiplied onto everything under it. Open sky
## with nothing behind it is left alone; creatures standing there are tinted by the light level instead.

## brightness per light level (gamma 0.85, so torchlight reaches a little further)
var lut := PackedFloat32Array()
var ox: int = 0
var oy: int = 0
var lw: int = 0
var lh: int = 0
var sky := PackedByteArray()
var blk := PackedByteArray()
var opq := PackedByteArray()
var drawn := PackedByteArray()
var img_data := PackedByteArray()
var tex: ImageTexture = null
var valid: bool = false
var _stamp: int = -1
var _sky_used: int = -1
var _timer: float = 0.0
var _origin_used := Vector2i(-99999, -99999)
## moving lights: [Vector2i cell, level]
var dynamic: Array = []


func _ready() -> void:
	lut.resize(16)
	for i in range(16):
		lut[i] = pow(float(i) / 15.0, 0.85)
	centered = false
	scale = Vector2(8, 8)
	z_index = 50
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	material = mat
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func set_smooth(on: bool) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if on else CanvasItem.TEXTURE_FILTER_NEAREST


## Recomputes when the world changed, the camera moved a few blocks, or the daylight changed
func update_light(world: WorldData, view: Rect2i, sky_level: int, delta: float, force: bool = false) -> void:
	_timer -= delta
	var margin: int = 12
	var origin := Vector2i(view.position.x - margin, view.position.y - margin)
	var size := Vector2i(view.size.x + margin * 2, view.size.y + margin * 2)
	var moved: bool = absi(origin.x - _origin_used.x) >= 3 or absi(origin.y - _origin_used.y) >= 3 or size.x != lw or size.y != lh
	if not force and not moved and world.version == _stamp and sky_level == _sky_used and _timer > 0.0:
		return
	_timer = 0.15
	if not moved and size.x == lw and size.y == lh:
		origin = _origin_used
	_compute(world, origin, size, sky_level)
	_origin_used = origin
	_stamp = world.version
	_sky_used = sky_level


func _compute(world: WorldData, origin: Vector2i, size: Vector2i, sl: int) -> void:
	ox = origin.x
	oy = origin.y
	lw = size.x
	lh = size.y
	var n: int = lw * lh
	if sky.size() != n:
		sky.resize(n)
		blk.resize(n)
		opq.resize(n)
		drawn.resize(n)
		img_data.resize(n)
	sky.fill(0)
	blk.fill(0)
	var q_sky: Array = []
	var q_blk: Array = []
	for i in range(16):
		q_sky.append(PackedInt32Array())
		q_blk.append(PackedInt32Array())
	var has_sky: bool = world.dim == WorldGen.DIM_OVERWORLD
	var hh: int = world.h
	var dop: PackedByteArray = DB.opaque
	var dlight: PackedByteArray = DB.light
	for ix in range(lw):
		var x: int = ox + ix
		var c: Chunk = world.chunk(x >> 4)
		var top: int = 0
		var base: int = 0
		if c != null:
			top = c.sky_top[x & 15] if has_sky else -1
			base = (x & 15) * hh
		var i: int = ix
		for iy in range(lh):
			var y: int = oy + iy
			if y < 0:
				opq[i] = 0
				drawn[i] = 0
				if has_sky and sl > 0:
					sky[i] = sl
					(q_sky[sl] as PackedInt32Array).append(i)
			elif y >= hh or c == null:
				opq[i] = 1 if y >= 0 else 0
				drawn[i] = 1
			else:
				var t: int = c.tiles[base + y]
				var op: int = dop[t]
				opq[i] = op
				drawn[i] = 1 if (t != T.AIR or world.back_kind(x, y) != 0) else 0
				var e: int = dlight[t]
				if e > 0:
					blk[i] = e
					(q_blk[e] as PackedInt32Array).append(i)
				if has_sky and op == 0 and y < top and sl > 0:
					sky[i] = sl
					(q_sky[sl] as PackedInt32Array).append(i)
			i += lw
	for d in dynamic:
		var cell: Vector2i = d[0]
		var lv: int = clampi(int(d[1]), 0, 15)
		var lx: int = cell.x - ox
		var ly: int = cell.y - oy
		if lx < 0 or ly < 0 or lx >= lw or ly >= lh:
			continue
		var k: int = ly * lw + lx
		if lv > blk[k]:
			blk[k] = lv
			(q_blk[lv] as PackedInt32Array).append(k)
	_spread(blk, q_blk)
	_spread(sky, q_sky)
	for k in range(n):
		if drawn[k] == 0:
			img_data[k] = 255
		else:
			var v: int = maxi(sky[k], blk[k])
			img_data[k] = int(lut[v] * 255.0)
	var img: Image = Image.create_from_data(lw, lh, false, Image.FORMAT_L8, img_data)
	if tex == null or tex.get_width() != lw or tex.get_height() != lh:
		tex = ImageTexture.create_from_image(img)
		texture = tex
	else:
		tex.update(img)
	position = Vector2(ox * 8, oy * 8)
	valid = true


## Spreads light out from the queued cells, brightest first
func _spread(lv: PackedByteArray, q: Array) -> void:
	var w: int = lw
	var h: int = lh
	var l: int = 15
	while l >= 2:
		var cur: PackedInt32Array = q[l]
		var nl: int = l - 1
		var ol: int = l - 2
		var k: int = 0
		while k < cur.size():
			var ci: int = cur[k]
			k += 1
			if lv[ci] != l:
				continue
			var cy: int = ci / w
			var cx: int = ci - cy * w
			if cx > 0:
				_push(lv, q, ci - 1, nl, ol)
			if cx < w - 1:
				_push(lv, q, ci + 1, nl, ol)
			if cy > 0:
				_push(lv, q, ci - w, nl, ol)
			if cy < h - 1:
				_push(lv, q, ci + w, nl, ol)
		l -= 1


func _push(lv: PackedByteArray, q: Array, nb: int, nl: int, ol: int) -> void:
	if opq[nb] == 0:
		if lv[nb] < nl:
			lv[nb] = nl
			(q[nl] as PackedInt32Array).append(nb)
	elif ol >= 1 and lv[nb] < ol:
		lv[nb] = ol
		(q[ol] as PackedInt32Array).append(nb)


## The light level (0..1) where a creature or the player stands, for tinting their sprites
func level_at(px: Vector2) -> float:
	if not valid:
		return 1.0
	var cx: int = floori(px.x / 8.0) - ox
	var cy: int = floori(px.y / 8.0) - oy
	if cx < 0 or cy < 0 or cx >= lw or cy >= lh:
		return 1.0
	var k: int = cy * lw + cx
	return clampf(lut[maxi(sky[k], blk[k])], 0.18, 1.0)
