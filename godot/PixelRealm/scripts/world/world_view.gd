class_name WorldView
extends Node2D
## Shows the world with two TileMapLayers: Terrain (the tiles, with collision for solid blocks and
## one-way platforms) and Back (background walls). Only a window around the camera is filled in;
## as the camera moves, the strips entering the window are painted and those leaving it are erased,
## so the layers stay small however far the world goes. Solid blocks that meet open space get the
## lit top rim and shaded bottom rim the Swift renderer drew (atlas columns 1-3).

const MARGIN_X := 26
const MARGIN_Y := 18

@onready var back: TileMapLayer = $Back
@onready var terrain: TileMapLayer = $Terrain

var world: WorldData = null
var rect := Rect2i()


func _ready() -> void:
	back.tile_set = Art.tileset
	terrain.tile_set = Art.tileset
	back.z_index = -20
	terrain.z_index = -10


func attach(w: WorldData) -> void:
	if world != null:
		if world.tile_changed.is_connected(_on_tile_changed):
			world.tile_changed.disconnect(_on_tile_changed)
		if world.chunk_ready.is_connected(_on_chunk_ready):
			world.chunk_ready.disconnect(_on_chunk_ready)
	world = w
	world.tile_changed.connect(_on_tile_changed)
	world.chunk_ready.connect(_on_chunk_ready)
	terrain.clear()
	back.clear()
	rect = Rect2i()


## Keeps the painted window around the view (cells). Call every frame; it only works when needed.
func follow(view: Rect2i) -> void:
	if world == null:
		return
	var inner: Rect2i = view.grow_individual(6, 4, 6, 4)
	if rect.size != Vector2i.ZERO and rect.encloses(inner):
		return
	var want := Rect2i(view.position - Vector2i(MARGIN_X, MARGIN_Y), view.size + Vector2i(MARGIN_X * 2, MARGIN_Y * 2))
	want.position.y = maxi(want.position.y, -2)
	want.end = Vector2i(want.end.x, mini(want.end.y, world.h + 1))
	if rect.size == Vector2i.ZERO or not rect.intersects(want) or absi(want.position.x - rect.position.x) > want.size.x / 2:
		terrain.clear()
		back.clear()
		rect = want
		_paint_rect(want)
		return
	_move_to(want)


func _move_to(n: Rect2i) -> void:
	var o: Rect2i = rect
	# erase what leaves
	for y in range(o.position.y, o.end.y):
		if y < n.position.y or y >= n.end.y:
			for x in range(o.position.x, o.end.x):
				_erase(x, y)
		else:
			for x in range(o.position.x, mini(o.end.x, n.position.x)):
				_erase(x, y)
			for x in range(maxi(o.position.x, n.end.x), o.end.x):
				_erase(x, y)
	# paint what enters
	for y in range(n.position.y, n.end.y):
		if y < o.position.y or y >= o.end.y:
			for x in range(n.position.x, n.end.x):
				paint_cell(x, y)
		else:
			for x in range(n.position.x, mini(n.end.x, o.position.x)):
				paint_cell(x, y)
			for x in range(maxi(n.position.x, o.end.x), n.end.x):
				paint_cell(x, y)
	rect = n


func _paint_rect(r: Rect2i) -> void:
	for x in range(r.position.x, r.end.x):
		if not world.is_loaded_x(x):
			continue
		for y in range(r.position.y, r.end.y):
			paint_cell(x, y)


func _erase(x: int, y: int) -> void:
	var c := Vector2i(x, y)
	terrain.erase_cell(c)
	back.erase_cell(c)


## Paints one cell from the world data (the tile, its edge rims, and the wall behind it)
func paint_cell(x: int, y: int) -> void:
	var c := Vector2i(x, y)
	if y < 0 or y >= world.h or not world.is_loaded_x(x):
		terrain.erase_cell(c)
		back.erase_cell(c)
		return
	var t: int = world.get_tile(x, y)
	if t == T.AIR:
		terrain.erase_cell(c)
	else:
		var v: int = 0
		if DB.edge[t] == 1:
			if DB.opaque[world.get_tile(x, y - 1)] == 0:
				v |= 1
			if y + 1 < world.h and DB.opaque[world.get_tile(x, y + 1)] == 0:
				v |= 2
		terrain.set_cell(c, Art.SRC_TERRAIN, Vector2i(v, t))
	var k: int = world.back_kind(x, y)
	if k > 0 and DB.opaque[t] == 0:
		back.set_cell(c, Art.SRC_WALLS, Vector2i(k - 1, 0))
	else:
		back.erase_cell(c)


func _on_tile_changed(x: int, y: int) -> void:
	if not rect.has_point(Vector2i(x, y)):
		return
	paint_cell(x, y)
	if y > 0:
		paint_cell(x, y - 1)
	if y + 1 < world.h:
		paint_cell(x, y + 1)


func _on_chunk_ready(cx: int) -> void:
	if rect.size == Vector2i.ZERO:
		return
	var x0: int = maxi(cx * Chunk.W, rect.position.x)
	var x1: int = mini(cx * Chunk.W + Chunk.W, rect.end.x)
	for x in range(x0, x1):
		for y in range(rect.position.y, rect.end.y):
			paint_cell(x, y)
	# the columns either side get their edge rims right
	for x in [x0 - 1, x1]:
		if x >= rect.position.x and x < rect.end.x and world.is_loaded_x(x):
			for y in range(rect.position.y, rect.end.y):
				paint_cell(x, y)
