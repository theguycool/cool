class_name Chunk
extends RefCounted
## Sixteen columns of the world, top to bottom: the tiles, the background walls the player built,
## and per column the generated surface row and the first row that stops sunlight.

const W := 16

var cx: int = 0
var h: int = 560
var x0: int = 0
## tile ids, column after column: index = lx * h + y
var tiles := PackedByteArray()
## background walls built by the player (0 = none)
var walls := PackedByteArray()
## the generated ground row of each column (the Umbral Realm: its cavern floor)
var surf := PackedInt32Array()
## the Umbral Realm's ceiling row of each column
var ceil_y := PackedInt32Array()
## first opaque row from the top in each column (sunlight reaches every row above it)
var sky_top := PackedInt32Array()
var has_sky: bool = true
## changed since it was generated (saved with the world)
var dirty: bool = false


func _init(chunk_x: int = 0, height: int = 560) -> void:
	cx = chunk_x
	h = height
	x0 = chunk_x * W
	tiles.resize(W * h)
	walls.resize(W * h)
	surf.resize(W)
	ceil_y.resize(W)
	sky_top.resize(W)


func get_local(lx: int, y: int) -> int:
	if y < 0:
		return 0
	if y >= h:
		return T.BEDROCK
	return tiles[lx * h + y]


func set_local(lx: int, y: int, t: int) -> void:
	if y < 0 or y >= h or lx < 0 or lx >= W:
		return
	tiles[lx * h + y] = t


## The tile at world column x (inside this chunk), or -1 outside it
func at(x: int, y: int) -> int:
	var lx: int = x - x0
	if lx < 0 or lx >= W or y < 0 or y >= h:
		return -1
	return tiles[lx * h + y]


## Writes a tile at world column x if it falls inside this chunk (structures are drawn clipped)
func put(x: int, y: int, t: int) -> void:
	var lx: int = x - x0
	if lx < 0 or lx >= W or y < 1 or y >= h - 1:
		return
	tiles[lx * h + y] = t


func put_if_air(x: int, y: int, t: int) -> void:
	var lx: int = x - x0
	if lx < 0 or lx >= W or y < 1 or y >= h - 1:
		return
	if tiles[lx * h + y] == T.AIR:
		tiles[lx * h + y] = t


func fill(xa: int, ya: int, xb: int, yb: int, t: int) -> void:
	var lo_x: int = maxi(mini(xa, xb), x0)
	var hi_x: int = mini(maxi(xa, xb), x0 + W - 1)
	var lo_y: int = maxi(mini(ya, yb), 1)
	var hi_y: int = mini(maxi(ya, yb), h - 2)
	for x in range(lo_x, hi_x + 1):
		var base: int = (x - x0) * h
		for y in range(lo_y, hi_y + 1):
			tiles[base + y] = t


func put_wall(x: int, y: int, k: int) -> void:
	var lx: int = x - x0
	if lx < 0 or lx >= W or y < 0 or y >= h:
		return
	walls[lx * h + y] = k


func fill_wall(xa: int, ya: int, xb: int, yb: int, k: int) -> void:
	for x in range(maxi(mini(xa, xb), x0), mini(maxi(xa, xb), x0 + W - 1) + 1):
		for y in range(maxi(mini(ya, yb), 0), mini(maxi(ya, yb), h - 1) + 1):
			walls[(x - x0) * h + y] = k


## `opq` is the opaque-tile table (DB.opaque); passed in so chunks can be built on worker threads
func recompute_sky(lx: int, opq: PackedByteArray) -> void:
	if not has_sky:
		sky_top[lx] = h
		return
	var base: int = lx * h
	var y: int = 0
	while y < h:
		if opq[tiles[base + y]] == 1:
			break
		y += 1
	sky_top[lx] = y


func rebuild_sky(opq: PackedByteArray) -> void:
	for lx in range(W):
		recompute_sky(lx, opq)
