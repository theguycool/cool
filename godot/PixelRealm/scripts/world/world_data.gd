class_name WorldData
extends RefCounted
## The tiles of one dimension (the overworld or the Umbral Realm): chunks streamed in around the
## player (built on worker threads), tile and wall access, chest contents, and what goes into a save.

## a tile or wall changed (the view repaints it, the light updates)
signal tile_changed(x: int, y: int)
## a chunk finished loading
signal chunk_ready(cx: int)

var gen: WorldGen
var dim: int = 0
var h: int = 560
var chunks := {}
## changed chunks that are not loaded right now: cx -> {"t": tiles, "w": walls}
var stash := {}
## chest contents by Vector2i(x, y) (filled with loot the first time a chest is opened)
var chests := {}
var threaded: bool = true
## counts every change (the lighting uses it to know when to recompute)
var version: int = 0
var _tasks := {}
var _done := {}
var _mutex := Mutex.new()
var _last_cx: int = -2147483648
var _last: Chunk = null


func _init(g: WorldGen, dimension: int) -> void:
	gen = g
	dim = dimension
	h = g.height_of(dimension)


func is_overworld() -> bool:
	return dim == WorldGen.DIM_OVERWORLD


# ---------------------------------------------------------------------------------------------- access

func chunk(cx: int) -> Chunk:
	if cx == _last_cx and _last != null:
		return _last
	var c: Chunk = chunks.get(cx)
	if c != null:
		_last_cx = cx
		_last = c
	return c


func is_loaded_x(x: int) -> bool:
	return chunks.has(x >> 4)


## The tile at (x, y): bedrock below the world, air above it and in chunks not loaded yet
func get_tile(x: int, y: int) -> int:
	if y < 0:
		return T.AIR
	if y >= h:
		return T.BEDROCK
	var c: Chunk = chunk(x >> 4)
	if c == null:
		return T.AIR
	return c.tiles[(x & 15) * h + y]


func solid(x: int, y: int) -> bool:
	if y >= h:
		return true
	return DB.solid[get_tile(x, y)] == 1


func opaque(x: int, y: int) -> bool:
	return DB.opaque[get_tile(x, y)] == 1


func liquid(x: int, y: int) -> bool:
	return DB.liquid[get_tile(x, y)] == 1


## Writes a tile; returns what was there. Edge rows (the bedrock floor and the sky row) are kept.
func set_tile(x: int, y: int, t: int) -> int:
	if y < 1 or y >= h - 1:
		return T.AIR
	var c: Chunk = chunk(x >> 4)
	if c == null:
		return T.AIR
	var lx: int = x & 15
	var i: int = lx * h + y
	var old: int = c.tiles[i]
	if old == t:
		return old
	c.tiles[i] = t
	c.dirty = true
	version += 1
	if DB.opaque[old] != DB.opaque[t]:
		c.recompute_sky(lx, DB.opaque)
	tile_changed.emit(x, y)
	return old


## Background wall built by the player at (x, y) (0 = none)
func get_wall(x: int, y: int) -> int:
	if y < 0 or y >= h:
		return 0
	var c: Chunk = chunk(x >> 4)
	if c == null:
		return 0
	return c.walls[(x & 15) * h + y]


func set_wall(x: int, y: int, k: int) -> bool:
	if y < 1 or y >= h - 1:
		return false
	var c: Chunk = chunk(x >> 4)
	if c == null:
		return false
	var i: int = (x & 15) * h + y
	if c.walls[i] == k:
		return false
	c.walls[i] = k
	c.dirty = true
	version += 1
	tile_changed.emit(x, y)
	return true


## What shows behind (x, y): a built wall, or the natural dirt, stone, deep rock or ash under the
## ground (0 = open sky)
func back_kind(x: int, y: int) -> int:
	if y < 0 or y >= h:
		return 0
	var c: Chunk = chunk(x >> 4)
	if c == null:
		return 0
	var lx: int = x & 15
	var w: int = c.walls[lx * h + y]
	if w != 0:
		return w
	var s: int = c.surf[lx]
	if dim == WorldGen.DIM_OVERWORLD:
		if y > s + 1:
			var depth: int = y - s
			if depth < 14:
				return 1
			return 2 if y < 330 else 3
		return 0
	if y > s + 1 or y < c.ceil_y[lx] - 1:
		return 4
	return 0


## The first row from the top that stops sunlight in column x
func sky_top(x: int) -> int:
	var c: Chunk = chunk(x >> 4)
	if c == null:
		return 0
	return c.sky_top[x & 15]


## The generated ground row of column x (from the chunk if loaded, else from the generator)
func surface(x: int) -> int:
	var c: Chunk = chunk(x >> 4)
	if c != null:
		return c.surf[x & 15]
	if dim == WorldGen.DIM_UMBRAL:
		return gen.u_floor(x)
	return gen.surface_at(x)


## The first row from the top in column x that is solid or liquid (where rain stops), or h
func top_solid(x: int) -> int:
	var c: Chunk = chunk(x >> 4)
	if c == null:
		return h
	var base: int = (x & 15) * h
	for y in range(h):
		var t: int = c.tiles[base + y]
		if DB.solid[t] == 1 or DB.liquid[t] == 1 or DB.platform[t] == 1:
			return y
	return h


# ---------------------------------------------------------------------------------------------- streaming

## Starts loading chunk cx (on a worker thread when allowed) unless it is loaded or on its way
func request(cx: int) -> void:
	if chunks.has(cx) or _tasks.has(cx):
		return
	if threaded:
		_tasks[cx] = WorkerThreadPool.add_task(_task.bind(cx), false, "chunk")
	else:
		_install(_build(cx))


## Loads chunk cx now (waiting for its worker if it is already being built)
func ensure(cx: int) -> Chunk:
	if chunks.has(cx):
		return chunks[cx]
	if _tasks.has(cx):
		WorkerThreadPool.wait_for_task_completion(int(_tasks[cx]))
		_tasks.erase(cx)
		_mutex.lock()
		var done: Chunk = _done.get(cx)
		_done.erase(cx)
		_mutex.unlock()
		if done != null:
			_install(done)
			return done
	var c: Chunk = _build(cx)
	_install(c)
	return c


## Installs the chunks the workers have finished (call once a frame)
func poll() -> void:
	if _tasks.is_empty():
		return
	for cx in _tasks.keys():
		var id: int = _tasks[cx]
		if not WorkerThreadPool.is_task_completed(id):
			continue
		WorkerThreadPool.wait_for_task_completion(id)
		_tasks.erase(cx)
		_mutex.lock()
		var c: Chunk = _done.get(cx)
		_done.erase(cx)
		_mutex.unlock()
		if c != null and not chunks.has(cx):
			_install(c)


## Waits for every chunk still being built (before a save, or when leaving)
func finish_tasks() -> void:
	for cx in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(int(_tasks[cx]))
	_tasks.clear()
	_mutex.lock()
	_done.clear()
	_mutex.unlock()


func pending_count() -> int:
	return _tasks.size()


func _task(cx: int) -> void:
	var c: Chunk = _build(cx)
	_mutex.lock()
	_done[cx] = c
	_mutex.unlock()


func _build(cx: int) -> Chunk:
	_mutex.lock()
	var saved = stash.get(cx)
	_mutex.unlock()
	if saved != null:
		return _restore(cx, saved)
	return gen.generate_chunk(cx, dim)


func _restore(cx: int, saved: Dictionary) -> Chunk:
	var c := Chunk.new(cx, h)
	var t: PackedByteArray = saved["t"]
	var w: PackedByteArray = saved["w"]
	if t.size() == c.tiles.size():
		c.tiles = t
	if w.size() == c.walls.size():
		c.walls = w
	c.has_sky = dim == WorldGen.DIM_OVERWORLD
	for lx in range(Chunk.W):
		var x: int = c.x0 + lx
		if dim == WorldGen.DIM_OVERWORLD:
			c.surf[lx] = gen.surface_at(x)
		else:
			c.surf[lx] = gen.u_floor(x)
			c.ceil_y[lx] = gen.u_ceil(x)
	c.dirty = true
	c.rebuild_sky(gen.opq)
	return c


func _install(c: Chunk) -> void:
	chunks[c.cx] = c
	_mutex.lock()
	stash.erase(c.cx)
	_mutex.unlock()
	version += 1
	chunk_ready.emit(c.cx)


## Drops chunks far from the player; the changed ones are kept in the stash
func unload_far(center_cx: int, keep: int) -> void:
	for cx in chunks.keys():
		if absi(int(cx) - center_cx) <= keep:
			continue
		var c: Chunk = chunks[cx]
		if c.dirty:
			_mutex.lock()
			stash[cx] = {"t": c.tiles, "w": c.walls}
			_mutex.unlock()
		chunks.erase(cx)
		if _last_cx == int(cx):
			_last = null
			_last_cx = -2147483648


# ---------------------------------------------------------------------------------------------- chests

const CHEST_SLOTS := 27


## A chest's contents, rolled from the loot tables the first time it is opened
func chest_items(x: int, y: int) -> Array:
	var k := Vector2i(x, y)
	if not chests.has(k):
		var loot: Array = Loot.chest_loot(gen, dim, x, y)
		var slots: Array = []
		slots.resize(CHEST_SLOTS)
		for i in range(mini(loot.size(), CHEST_SLOTS)):
			slots[i] = loot[i]
		chests[k] = slots
	var arr: Array = chests[k]
	if arr.size() < CHEST_SLOTS:
		arr.resize(CHEST_SLOTS)
	return arr


## Removes a chest's record and returns what was in it (it spills out when the chest is broken)
func take_chest(x: int, y: int) -> Array:
	var k := Vector2i(x, y)
	var items: Array = chest_items(x, y)
	chests.erase(k)
	var out: Array = []
	for s in items:
		if s != null:
			out.append(s)
	return out


# ---------------------------------------------------------------------------------------------- saving

func to_save() -> Dictionary:
	finish_tasks()
	var out_chunks := {}
	for cx in stash.keys():
		var s: Dictionary = stash[cx]
		out_chunks[str(cx)] = _pack(s["t"], s["w"])
	for cx in chunks.keys():
		var c: Chunk = chunks[cx]
		if c.dirty:
			out_chunks[str(cx)] = _pack(c.tiles, c.walls)
	var out_chests := {}
	for k in chests.keys():
		var v: Vector2i = k
		out_chests["%d,%d" % [v.x, v.y]] = chests[k]
	return {"chunks": out_chunks, "chests": out_chests}


func from_save(d: Dictionary) -> void:
	var cs: Dictionary = d.get("chunks", {})
	for key in cs.keys():
		var e: Dictionary = cs[key]
		var raw_t: PackedByteArray = Marshalls.base64_to_raw(String(e["t"])).decompress(Chunk.W * h, FileAccess.COMPRESSION_DEFLATE)
		var raw_w: PackedByteArray = Marshalls.base64_to_raw(String(e["w"])).decompress(Chunk.W * h, FileAccess.COMPRESSION_DEFLATE)
		stash[int(key)] = {"t": raw_t, "w": raw_w}
	var ch: Dictionary = d.get("chests", {})
	for key in ch.keys():
		var parts: PackedStringArray = String(key).split(",")
		if parts.size() == 2:
			chests[Vector2i(int(parts[0]), int(parts[1]))] = ch[key]


func _pack(t: PackedByteArray, w: PackedByteArray) -> Dictionary:
	return {"t": Marshalls.raw_to_base64(t.compress(FileAccess.COMPRESSION_DEFLATE)),
		"w": Marshalls.raw_to_base64(w.compress(FileAccess.COMPRESSION_DEFLATE))}
