class_name Structures
## Everything built into the world: the two boss lairs, ruins (houses, towers, forts, camps, overgrown
## temples and buried bunkers), the sealed rift chamber far below, crystal grottos with their passage
## to the surface, old mines, and in the Umbral Realm the rift platform, ruined halls and the
## Hollow Warden's citadel. Sites are worked out from the seed alone, so every chunk can build its own
## part of a structure that spans several chunks.

const RARE_CELL := 192
const GROTTO_CELL := 700
const MINE_CELL := 900
const URUIN_CELL := 260
const RARE_KINDS := ["house", "tower", "fort", "camp", "overgrown", "bunker"]


static func _cached(g: WorldGen, key: String, maker: Callable) -> Dictionary:
	g._mutex.lock()
	var v = g.sites.get(key)
	g._mutex.unlock()
	if v != null:
		return v
	var d: Dictionary = maker.call()
	g._mutex.lock()
	if g.sites.size() > 20000:
		g.sites.clear()
	g.sites[key] = d
	g._mutex.unlock()
	return d


# ---------------------------------------------------------------------------------------------- sites

static func rare_site(g: WorldGen, c: int) -> Dictionary:
	return _cached(g, "r%d" % c, func() -> Dictionary: return _compute_rare(g, c))


static func _compute_rare(g: WorldGen, c: int) -> Dictionary:
	if not g.has_structures():
		return {}
	if PRNG.hash2(c, 71, g.world_seed) > g.rare_chance:
		return {}
	var sx: int = c * RARE_CELL + 32 + int(PRNG.hash2(c, 72, g.world_seed) * float(RARE_CELL - 64))
	var base: Array = g.col(sx)
	if int(base[1]) == WorldGen.OCEAN or float(base[2]) < 0.45:
		return {}
	if not g.lair_at(sx, 260).is_empty() or absi(sx - g.portal_x) < 90:
		return {}
	if not g.infinite and (sx < 300 or sx > g.width - 300):
		return {}
	if g.flat and absi(sx - g.spawn_x) < 48:
		return {}
	var r: float = PRNG.hash2(c, 73, g.world_seed)
	var kind: String = "bunker"
	if r < 0.17:
		kind = "house"
	elif r < 0.34:
		kind = "tower"
	elif r < 0.51:
		kind = "fort"
	elif r < 0.68:
		kind = "camp"
	elif r < 0.84:
		kind = "overgrown"
	return {"cell": c, "x": sx, "kind": kind, "seed": PRNG.hash_u(c, 74, g.world_seed)}


static func rare_sites(g: WorldGen, xa: int, xb: int) -> Array:
	var out: Array = []
	for c in range(PRNG.fdiv(xa - 40, RARE_CELL), PRNG.fdiv(xb + 40, RARE_CELL) + 1):
		var s: Dictionary = rare_site(g, c)
		if not s.is_empty() and int(s["x"]) + 30 >= xa and int(s["x"]) - 30 <= xb:
			out.append(s)
	return out


static func has_grottos(g: WorldGen) -> bool:
	return g.has_structures() and (not g.flat or g.opt_caves)


static func grotto_site(g: WorldGen, c: int) -> Dictionary:
	return _cached(g, "g%d" % c, func() -> Dictionary: return _compute_grotto(g, c))


static func _cave_mouth_clear(g: WorldGen, x: int) -> bool:
	var c: Array = g.col(x)
	if int(c[1]) == WorldGen.OCEAN or int(c[0]) >= WorldGen.SEA - 1:
		return false
	if absi(x - g.spawn_x) < 30 or absi(x - g.portal_x) < 60:
		return false
	if not g.lair_at(x, 140).is_empty():
		return false
	for r in rare_sites(g, x - 40, x + 40):
		if absi(int(r["x"]) - x) < 40:
			return false
	return true


static func _compute_grotto(g: WorldGen, c: int) -> Dictionary:
	if not has_grottos(g):
		return {}
	if PRNG.hash2(c, 601, g.world_seed) > 0.6:
		return {}
	var x: int = c * GROTTO_CELL + 90 + int(PRNG.hash2(c, 602, g.world_seed) * float(GROTTO_CELL - 180))
	if not g.infinite and (x < 260 or x > g.width - 260):
		return {}
	if absi(x - g.portal_x) < 240:
		return {}
	var rx: int = 17 + int(PRNG.hash2(c, 604, g.world_seed) * 9.0)
	var ry: int = 8 + int(PRNG.hash2(c, 605, g.world_seed) * 4.0)
	var floor_y: int = 250 + int(PRNG.hash2(c, 603, g.world_seed) * 130.0)
	var first: int = -1 if PRNG.hash2(c, 606, g.world_seed) < 0.5 else 1
	var site := {"cell": c, "x": x, "floor": floor_y, "rx": rx, "ry": ry, "dir": first, "len": 0, "open": false,
		"seed": PRNG.hash_u(c, 607, g.world_seed)}
	# the passage climbs one row per column; it opens where it meets the ground on clear, dry land
	for d in [first, -first]:
		var sx: int = x + int(d) * (rx - 3)
		var k: int = 0
		while k < 420:
			var px: int = sx + int(d) * k
			if not g.infinite and (px < 40 or px > g.width - 40):
				break
			var fk: int = floor_y - k
			var h: int = int(g.col(px)[0])
			if g.flat and fk - 5 <= h + WorldGen.FLAT_CRUST:
				site["dir"] = d
				site["len"] = k
				return site
			if fk - 4 <= h + 1:
				if _cave_mouth_clear(g, px):
					site["dir"] = d
					site["len"] = k + 2
					site["open"] = true
					return site
				break
			k += 1
	return site


static func grotto_sites(g: WorldGen, xa: int, xb: int) -> Array:
	var out: Array = []
	for c in range(PRNG.fdiv(xa - 450, GROTTO_CELL), PRNG.fdiv(xb + 450, GROTTO_CELL) + 1):
		var s: Dictionary = grotto_site(g, c)
		if s.is_empty():
			continue
		var x: int = s["x"]
		var px0: int = x + int(s["dir"]) * (int(s["rx"]) - 3)
		var px1: int = px0 + int(s["dir"]) * int(s["len"])
		var lo: int = mini(x - int(s["rx"]) - 3, mini(px0, px1) - 2)
		var hi: int = maxi(x + int(s["rx"]) + 3, maxi(px0, px1) + 2)
		if hi >= xa and lo <= xb:
			out.append(s)
	return out


## Where a grotto's passage comes out of the ground (open grottos only)
static func grotto_mouth(s: Dictionary) -> int:
	return int(s["x"]) + int(s["dir"]) * (int(s["rx"]) - 3) + int(s["dir"]) * int(s["len"])


static func mine_site(g: WorldGen, c: int) -> Dictionary:
	return _cached(g, "m%d" % c, func() -> Dictionary: return _compute_mine(g, c))


static func _compute_mine(g: WorldGen, c: int) -> Dictionary:
	if not g.has_structures():
		return {}
	if PRNG.hash2(c, 621, g.world_seed) > 0.62:
		return {}
	var ok_biomes: Array = [WorldGen.PLAINS, WorldGen.FOREST, WorldGen.MOUNTAIN, WorldGen.TUNDRA, WorldGen.SAVANNA, WorldGen.DESERT]
	var found_x: int = 0
	var found_h: int = -1
	for attempt in range(10):
		var x: int = c * MINE_CELL + 120 + int(PRNG.hash2(c, 622 + attempt * 3, g.world_seed) * float(MINE_CELL - 240))
		if not g.infinite and (x < 320 or x > g.width - 320):
			continue
		if absi(x - g.spawn_x) < 60 or absi(x - g.portal_x) < 80:
			continue
		var base: Array = g.col(x)
		if not ok_biomes.has(int(base[1])) or int(base[0]) >= WorldGen.SEA - 1:
			continue
		var level: bool = true
		for d in range(-4, 7):
			var cc: Array = g.col(x + d)
			if int(cc[1]) == WorldGen.OCEAN or absi(int(cc[0]) - int(base[0])) > 1:
				level = false
				break
		if not level or not g.lair_at(x, 200).is_empty():
			continue
		var near_ruin: bool = false
		for r in rare_sites(g, x - 70, x + 70):
			if absi(int(r["x"]) - x) < 70:
				near_ruin = true
		if near_ruin:
			continue
		found_x = x
		found_h = int(base[0])
		break
	if found_h < 0:
		return {}
	var depth: int = 60 + int(PRNG.hash2(c, 623, g.world_seed) * 110.0)
	var n: int = 3 if depth > 130 else (2 if depth > 90 else 1)
	var levels: Array = []
	var left: Array = []
	var right: Array = []
	for k in range(n):
		levels.append(found_h + depth * (k + 1) / n)
		left.append(16 + int(PRNG.hash2(c, 630 + k, g.world_seed) * 40.0))
		right.append(16 + int(PRNG.hash2(c, 640 + k, g.world_seed) * 40.0))
	return {"cell": c, "x": found_x, "ground": found_h, "levels": levels, "left": left, "right": right,
		"seed": PRNG.hash_u(c, 624, g.world_seed)}


static func mine_sites(g: WorldGen, xa: int, xb: int) -> Array:
	var out: Array = []
	for c in range(PRNG.fdiv(xa - 70, MINE_CELL), PRNG.fdiv(xb + 70, MINE_CELL) + 1):
		var s: Dictionary = mine_site(g, c)
		if s.is_empty():
			continue
		var lo: int = int(s["x"]) - _maxv(s["left"]) - 3
		var hi: int = int(s["x"]) + 2 + _maxv(s["right"]) + 3
		if hi >= xa and lo <= xb:
			out.append(s)
	return out


static func _maxv(a: Array) -> int:
	var m: int = 0
	for v in a:
		m = maxi(m, int(v))
	return m


## Trees and plants keep away from what is built on the surface
static func blocks_trees(g: WorldGen, x: int, _cache: Dictionary) -> bool:
	for r in rare_sites(g, x - 20, x + 20):
		if absi(x - int(r["x"])) < 16:
			return true
	for m in mine_sites(g, x - 12, x + 12):
		if x >= int(m["x"]) - 6 and x <= int(m["x"]) + 8:
			return true
	if not g.lair_at(x, 110).is_empty():
		return true
	if g.flat and (absi(x - g.spawn_x) < 5 or g.near_pond(x, 2)):
		return true
	for s in grotto_sites(g, x - 20, x + 20):
		if bool(s["open"]) and absi(x - grotto_mouth(s)) < 16:
			return true
	return false


# ---------------------------------------------------------------------------------------------- building

static func apply(g: WorldGen, ch: Chunk, dim: int) -> void:
	if dim == WorldGen.DIM_UMBRAL:
		_apply_umbral(g, ch)
		return
	var x0: int = ch.x0
	var mid: int = x0 + Chunk.W / 2
	for lair in g.lair_centers(mid):
		if absi(int(lair["cx"]) - mid) < 62:
			_build_lair(g, ch, lair)
	for r in rare_sites(g, x0 - 30, x0 + Chunk.W + 30):
		_build_rare(g, ch, r)
	if absi(g.portal_x - mid) < 24:
		_build_portal_chamber(g, ch)
	for s in grotto_sites(g, x0, x0 + Chunk.W - 1):
		_build_grotto(g, ch, s)
	for s in mine_sites(g, x0, x0 + Chunk.W - 1):
		_build_mine(g, ch, s)


static func _h(x: int, y: int, s: int) -> float:
	return PRNG.hash2(x, y, s)


static func _ground(g: WorldGen, x: int) -> int:
	return int(g.col(x)[0])


## Levels the ground between xa and xb to row gy and clears the air above it
static func _pad_ground(g: WorldGen, ch: Chunk, xa: int, xb: int, gy: int, clear_h: int) -> void:
	for x in range(xa, xb + 1):
		if x < ch.x0 or x >= ch.x0 + Chunk.W:
			continue
		var h: int = _ground(g, x)
		if h > gy:
			ch.fill(x, gy, x, h - 1, T.DIRT)
		if h < gy:
			ch.fill(x, h, x, gy - 1, T.AIR)
		ch.fill(x, gy - clear_h, x, gy - 1, T.AIR)
		ch.put(x, gy, T.DIRT)


## Knocks holes in old masonry and lets moss creep over the timber
static func _decay(g: WorldGen, ch: Chunk, xa: int, ya: int, xb: int, yb: int, p: float, s: int) -> void:
	for x in range(xa, xb + 1):
		if x < ch.x0 or x >= ch.x0 + Chunk.W:
			continue
		for y in range(ya, yb + 1):
			var t: int = ch.at(x, y)
			if t < 0 or g.sol[t] != 1:
				continue
			if _h(x, y, s) < p:
				ch.put(x, y, T.AIR)
			elif _h(x, y, s + 5) < 0.18 and (t == T.PLANKS or t == T.LOG):
				ch.put(x, y, T.MOSS_BRICK)


static func _cobwebs(ch: Chunk, xa: int, ya: int, xb: int, yb: int, p: float, s: int) -> void:
	for x in range(xa, xb + 1):
		for y in range(ya, yb + 1):
			if ch.at(x, y) == T.AIR and _h(x, y, s) < p:
				ch.put(x, y, T.COBWEB)


static func _build_house(ch: Chunk, x: int, gy: int, w: int, ht: int, s: int) -> void:
	ch.fill(x - 1, gy - ht - w / 2 - 3, x + w, gy - 1, T.AIR)
	ch.fill(x, gy, x + w - 1, gy, T.PLANKS)
	for yy in range(gy - ht, gy):
		ch.put(x, yy, T.PLANKS)
		ch.put(x + w - 1, yy, T.PLANKS)
	for px in [x, x + w - 1]:
		ch.put(px, gy - 1, T.LOG_BLOCK)
		ch.put(px, gy - ht, T.LOG_BLOCK)
	# a door in each end wall, so the way along the ground always goes through
	for dx in [x, x + w - 1]:
		ch.put(dx, gy - 1, T.DOOR_CLOSED)
		ch.put(dx, gy - 2, T.DOOR_CLOSED)
	ch.put(x + w - 1 if _h(x, 1, s) < 0.5 else x, gy - 3, T.GLASS)
	ch.fill_wall(x + 1, gy - ht, x + w - 2, gy - 1, 5)
	var k: int = 0
	while x - 1 + k <= x + w - k:
		for xx in range(x - 1 + k, x + w - k + 1):
			ch.put(xx, gy - ht - 1 - k, T.BRICK)
		k += 1
	ch.put(x + w / 2, gy - ht + 1, T.LANTERN)
	if _h(x, 2, s) < 0.5:
		ch.put(x + 2, gy - 1, T.WORKBENCH)
		ch.put(x + w - 3, gy - 1, T.CHEST)
	else:
		ch.put(x + 2, gy - 1, T.CHEST)
		ch.put(x + w - 3, gy - 1, T.FURNACE)


static func _build_rare(g: WorldGen, ch: Chunk, site: Dictionary) -> void:
	var sx: int = site["x"]
	var s: int = site["seed"]
	var gy: int = _ground(g, sx)
	match String(site["kind"]):
		"house":
			var w: int = 11
			var x: int = sx - w / 2
			_pad_ground(g, ch, x - 2, x + w + 2, gy, 12)
			_build_house(ch, x, gy, w, 5, s)
			_decay(g, ch, x - 1, gy - 12, x + w, gy - 1, 0.28, s + 1)
			_cobwebs(ch, x + 1, gy - 5, x + w - 2, gy - 1, 0.18, s + 2)
			# a cellar under a hatch, with a spike trap and two chests
			var hx: int = x + w / 2
			ch.fill(x + 1, gy + 1, x + w - 2, gy + 7, T.MOSS_BRICK)
			ch.fill(x + 2, gy + 2, x + w - 3, gy + 6, T.AIR)
			ch.put(hx, gy, T.AIR)
			ch.put(hx, gy + 1, T.AIR)
			ch.fill(hx - 1, gy + 6, hx + 1, gy + 6, T.SPIKES)
			ch.put(x + 2, gy + 6, T.CHEST)
			ch.put(x + w - 3, gy + 6, T.CHEST)
			ch.put(x + 3, gy, T.PLATFORM)
			ch.fill(x + 3, gy + 1, x + 3, gy + 6, T.LADDER)
			ch.put(x + w / 2 + 2, gy + 2, T.LANTERN)
			ch.fill(x + 2, gy + 7, x + w - 3, gy + 7, T.MOSS_BRICK)
		"tower":
			var w: int = 9
			var x: int = sx - w / 2
			var ht: int = 14 + int(_h(1, 1, s) * 6.0)
			_pad_ground(g, ch, x - 3, x + w + 2, gy, ht + 4)
			ch.fill(x, gy - ht, x + w - 1, gy, T.MOSS_BRICK)
			ch.fill(x + 1, gy - ht + 1, x + w - 2, gy - 1, T.AIR)
			ch.fill(x, gy, x + w - 1, gy, T.BRICK)
			var yy: int = gy - 3
			var odd: bool = true
			while yy > gy - ht:
				if odd:
					ch.fill(x + 1, yy, x + w - 4, yy, T.PLATFORM)
				else:
					ch.fill(x + 3, yy, x + w - 2, yy, T.PLATFORM)
				odd = not odd
				yy -= 3
			for dx in [x, x + w - 1]:
				ch.fill(dx, gy - 3, dx, gy - 1, T.AIR)
			ch.put(x + w - 1, gy - ht + 4, T.GLASS)
			ch.put(x + w / 2, gy - 1, T.CHEST)
			ch.put(x + 2, gy - 1, T.TORCH)
			for k in range(ht):
				_decay(g, ch, x - 1, gy - k, x + w, gy - k, 0.04 + float(k) / float(ht) * 0.55, s + k)
			_cobwebs(ch, x + 1, gy - ht, x + w - 2, gy - 4, 0.08, s + 9)
		"fort":
			var x: int = sx - 17
			_pad_ground(g, ch, x - 2, x + 36, gy, 14)
			ch.fill(x, gy - 8, x + 9, gy, T.BRICK)
			ch.fill(x + 1, gy - 7, x + 8, gy - 1, T.AIR)
			ch.fill(x + 25, gy - 6, x + 34, gy, T.BRICK)
			ch.fill(x + 26, gy - 5, x + 33, gy - 1, T.AIR)
			var cx: int = x
			while cx <= x + 9:
				ch.put(cx, gy - 9, T.BRICK)
				cx += 2
			cx = x + 25
			while cx <= x + 34:
				ch.put(cx, gy - 7, T.BRICK)
				cx += 2
			ch.fill(x + 10, gy - 2, x + 24, gy, T.MOSS_BRICK)
			for dx in range(8, 15):
				var hh: int = mini(3, maxi(0, 4 - absi(dx - 11)))
				ch.fill(x + dx, gy - hh, x + dx, gy - 1, T.STONE)
			for wx in [x, x + 9, x + 25, x + 34]:
				ch.fill(wx, gy - 3, wx, gy - 1, T.AIR)
			ch.put(x + 17, gy - 1, T.CAMPFIRE)
			ch.put(x + 20, gy - 1, T.CHEST)
			ch.put(x + 4, gy - 1, T.CHEST)
			ch.put(x + 4, gy - 6, T.LANTERN)
			ch.put(x + 29, gy - 1, T.HAY)
			_decay(g, ch, x - 1, gy - 10, x + 35, gy - 2, 0.30, s)
			_cobwebs(ch, x + 1, gy - 7, x + 34, gy - 2, 0.05, s + 3)
		"camp":
			var x: int = sx - 8
			_pad_ground(g, ch, x - 2, x + 18, gy, 8)
			for k in range(5):
				ch.put(x + k, gy - 1 - k, T.PLANKS)
				ch.put(x + 9 - k, gy - 1 - k, T.PLANKS)
			ch.put(x + 4, gy - 5, T.PLANKS)
			ch.put(x + 5, gy - 5, T.PLANKS)
			ch.fill(x + 1, gy - 1, x + 8, gy - 1, T.AIR)
			ch.put(x + 9, gy - 1, T.AIR)
			ch.put(x + 8, gy - 2, T.AIR)
			ch.put(x + 3, gy - 1, T.HAY)
			ch.put(x + 7, gy - 1, T.CHEST)
			ch.put(x + 14, gy - 1, T.CAMPFIRE)
			ch.put(x + 12, gy - 1, T.LOG)
			ch.put(x + 16, gy - 1, T.LOG)
			ch.put(x + 17, gy - 1, T.DEAD_BUSH)
			_cobwebs(ch, x + 1, gy - 4, x + 8, gy - 2, 0.1, s)
		"overgrown":
			var x: int = sx - 12
			_pad_ground(g, ch, x - 2, x + 26, gy, 12)
			ch.fill(x, gy, x + 24, gy, T.MOSS_BRICK)
			for p in range(5):
				var px: int = x + 1 + p * 6
				var ph: int = 4 + int(_h(p, 1, s) * 6.0)
				ch.fill_wall(px, gy - ph + 1, px + 1, gy - 1, 6)
				ch.fill(px, gy - ph, px + 1, gy - ph, T.MOSS_BRICK)
				if _h(p, 2, s) < 0.6 and p < 4:
					ch.fill(px + 2, gy - ph, px + 6, gy - ph, T.MOSS_BRICK)
				for lv in range(6):
					var lx: int = px - 1 + int(_h(lv, p, s) * 4.0)
					ch.put_if_air(lx, gy - ph - 1 - int(_h(p, lv, s + 1) * 2.0), T.LEAVES)
			ch.put(x + 12, gy - 1, T.CHEST)
			ch.put(x + 11, gy - 1, T.FLOWER_R)
			ch.put(x + 13, gy - 1, T.FLOWER_Y)
			ch.put(x + 9, gy - 1, T.REED)
			_decay(g, ch, x, gy - 12, x + 24, gy - 2, 0.22, s + 7)
		"bunker":
			var y0: int = gy + 60 + int(_h(2, 2, s) * 90.0)
			var x: int = sx - 14
			ch.fill(x, y0 - 1, x + 28, y0 + 11, T.MOSS_BRICK)
			ch.fill(x + 1, y0, x + 27, y0 + 9, T.AIR)
			ch.fill(x, y0 + 10, x + 28, y0 + 10, T.BRICK)
			ch.fill(x + 18, y0, x + 18, y0 + 9, T.BRICK)
			ch.fill(x + 18, y0 + 7, x + 18, y0 + 9, T.CRACKED_BRICK)
			for k in range(5):
				ch.put(x + 4 + k * 3, y0 + 9, T.SPIKES)
			ch.put(x + 2, y0 + 9, T.CHEST)
			ch.put(x + 14, y0 + 8, T.TORCH)
			ch.put(x + 7, y0 + 1, T.LANTERN)
			ch.put(x + 21, y0 + 9, T.CHEST)
			ch.put(x + 25, y0 + 9, T.CHEST)
			ch.put(x + 23, y0 + 1, T.LANTERN)
			ch.put(x + 20, y0 + 9, T.TORCH)
			ch.put(x + 22, y0 + 9, T.GLOW_CRYSTAL)
			_cobwebs(ch, x + 1, y0, x + 17, y0 + 4, 0.1, s)


## The row a lair's boss stands on
static func lair_floor_row(g: WorldGen) -> int:
	return WorldGen.FLAT_SURFACE if g.flat else WorldGen.SEA - 10 + 9


static func _build_lair(g: WorldGen, ch: Chunk, lair: Dictionary) -> void:
	var cx: int = lair["cx"]
	var is_rex: bool = lair["kind"] == "rex"
	var s: int = g.world_seed + (2 if is_rex else 1) * 7777
	if g.flat:
		var fy: int = WorldGen.FLAT_SURFACE
		for x in range(cx - 40, cx + 41):
			ch.fill(x, fy - 22, x, fy - 1, T.AIR)
			ch.put(x, fy, T.MUD if is_rex else T.STONE)
			if absi(x - cx) > 30 and _h(x, 3, s) < 0.3:
				ch.put(x, fy - 1, T.TALL_GRASS if is_rex else T.DEAD_BUSH)
		for side in [-1, 1]:
			ch.put(cx + side * 38, fy - 1, T.STONE)
			ch.put(cx + side * 38, fy - 2, T.TORCH)
		ch.put(cx + (-27 if is_rex else 27), fy - 1, T.CHEST)
		return
	var gy: int = WorldGen.SEA - 10
	for x in range(cx - 52, cx + 53):
		if x < ch.x0 or x >= ch.x0 + Chunk.W:
			continue
		var d: int = absi(x - cx)
		var depth: int = 0
		if d <= 30:
			depth = 9
		elif d <= 39:
			depth = 9 - (d - 30)
		ch.fill(x, gy - 22, x, gy - 1, T.AIR)
		if depth > 0:
			ch.fill(x, gy, x, gy + depth - 1, T.AIR)
			ch.put(x, gy + depth, T.MUD if is_rex else T.STONE)
			ch.put(x, gy + depth + 1, T.MUD if is_rex else T.STONE)
		else:
			ch.put(x, gy, T.JUNGLE_GRASS if is_rex else T.GRASS)
		var fy: int = gy + depth - 1
		if depth >= 8 and _h(x, 1, s) < 0.09:
			ch.put(x, fy, T.FOSSIL)
		if depth >= 8 and _h(x, 2, s) < 0.05:
			ch.put(x, fy - 1, T.COBWEB)
		if depth == 0 and _h(x, 3, s) < 0.12:
			ch.put(x, gy - 1, T.TALL_GRASS if is_rex else T.DEAD_BUSH)
	for side in [-1, 1]:
		var rx: int = cx + side * 44
		ch.fill(rx, gy - 2, rx, gy - 1, T.STONE)
		ch.put(rx, gy - 3, T.TORCH)
		ch.put(cx + side * 36, gy - 1, T.TORCH)
	if is_rex:
		for side in [-1, 1]:
			for rb in range(3):
				var bx: int = cx + side * (14 + rb * 8)
				ch.fill(bx, gy + 7, bx, gy + 8, T.FOSSIL)
				ch.put(bx - side, gy + 7, T.FOSSIL)
		for k in range(10):
			ch.put_if_air(cx - 24 + k * 5, gy + 7, T.JUNGLE_LEAVES)
	else:
		ch.fill(cx - 18, gy + 6, cx - 18, gy + 8, T.STONE)
		ch.fill(cx + 18, gy + 6, cx + 18, gy + 8, T.STONE)
		ch.put(cx - 18, gy + 5, T.TORCH)
		ch.put(cx + 18, gy + 5, T.TORCH)
	ch.put(cx + (-27 if is_rex else 27), gy + 8, T.CHEST)


## The rift: an oval tear on a low plinth, held by two anchor crescents and a keystone
static func rift_shape(ch: Chunk, px: int, base: int, fill_t: int) -> void:
	for dx in range(-3, 4):
		ch.put(px + dx, base, T.PORTAL_FRAME)
	for dy in range(-7, 0):
		for dx in range(-2, 3):
			var ey: float = (float(dy) + 4.0) / 3.6
			var ex: float = float(dx) / 2.6
			ch.put(px + dx, base + dy, fill_t if ex * ex + ey * ey <= 1.0 else T.AIR)
	for side in [-3, 3]:
		for k in range(4, 7):
			ch.put(px + side, base - k, T.PORTAL_FRAME)
	ch.put(px, base - 9, T.PORTAL_FRAME)


static func _build_portal_chamber(g: WorldGen, ch: Chunk) -> void:
	var px: int = g.portal_x
	var py: int = g.portal_y
	ch.fill(px - 12, py - 10, px + 12, py + 7, T.BRICK)
	ch.fill(px - 10, py - 8, px + 10, py + 5, T.AIR)
	ch.fill(px - 12, py + 6, px + 12, py + 7, T.OBSIDIAN)
	ch.fill_wall(px - 10, py - 8, px + 10, py + 5, 6)
	rift_shape(ch, px, py + 5, T.PORTAL_OFF)
	ch.put(px - 9, py + 4, T.TORCH)
	ch.put(px + 9, py + 4, T.TORCH)
	ch.put(px - 9, py - 4, T.LANTERN)
	ch.put(px + 9, py - 4, T.LANTERN)
	for k in range(8):
		var rx: int = px - 10 + k * 3
		if absi(rx - px) <= 3:
			continue
		if _h(rx, 1, g.world_seed) < 0.6:
			ch.put(rx, py + 5, T.MOSS_BRICK)
		if _h(rx, 2, g.world_seed) < 0.3:
			ch.put(rx, py + 4, T.COBWEB)
	ch.put(px - 7, py + 5, T.GLOW_CRYSTAL)
	ch.put(px + 7, py + 5, T.GLOW_CRYSTAL)
	ch.put(px + 6, py + 4, T.CHEST)


static func _build_grotto(g: WorldGen, ch: Chunk, site: Dictionary) -> void:
	var cx0: int = ch.x0
	var cx1: int = ch.x0 + Chunk.W - 1
	var sx: int = site["x"]
	var rxd: float = float(site["rx"])
	var ryd: float = float(site["ry"])
	var fy: int = site["floor"]
	var s: int = site["seed"]
	var dir: int = site["dir"]
	var xa: int = maxi(cx0, sx - int(site["rx"]) - 3)
	var xb: int = mini(cx1, sx + int(site["rx"]) + 3)
	for x in range(xa, xb + 1):
		var u: float = float(x - sx) / rxd
		var wob: float = 1.0 + (PRNG.noise1(float(x) * 0.18, s) - 0.5) * 0.26
		var inner: float = wob * wob - u * u
		var vault: int = roundi(sqrt(inner) / wob * ryd) if inner > 0.0 else 0
		var ow: float = wob * 1.28
		var outer: float = ow * ow - u * u
		var shell: int = roundi(sqrt(outer) / ow * ryd * 1.2) + 1 if outer > 0.0 else 0
		var along: float = u * float(-dir)
		var pool: bool = along > 0.45 and along < 0.8
		if shell > 0:
			for y in range(fy - shell - 1, fy + 2):
				if y >= fy - vault and y < fy:
					continue
				var t: int = ch.at(x, y)
				if t < 0:
					continue
				if g.liq[t] == 1:
					ch.put(x, y, T.STONE)
					continue
				if g.sol[t] != 1 or t == T.BEDROCK:
					continue
				var r: float = _h(x, y, s + 3)
				if r < 0.22:
					ch.put(x, y, T.CRYSTAL_ORE)
				elif r < 0.27:
					ch.put(x, y, T.GLOW_CRYSTAL)
		if vault <= 0:
			continue
		for y in range(fy - vault, fy):
			ch.put(x, y, T.AIR)
		if pool:
			ch.put(x, fy, T.WATER)
			ch.put(x, fy + 1, T.WATER)
			var under: int = ch.at(x, fy + 2)
			if under >= 0 and g.sol[under] != 1:
				ch.put(x, fy + 2, T.STONE)
		else:
			var ft: int = ch.at(x, fy)
			if ft >= 0 and (g.sol[ft] != 1 or ft == T.GLOW_CRYSTAL):
				ch.put(x, fy, T.STONE)
		if vault > 4 and _h(x, 1, s + 5) < 0.14:
			ch.put(x, fy - vault, T.GLOW_CRYSTAL)
		if not pool and absi(x - sx) > 7 and _h(x, 2, s + 5) < 0.08:
			ch.put(x, fy - 1, T.GLOW_CRYSTAL)
	for dx in range(-2, 3):
		ch.put(sx + dx, fy - 1, T.MOSS_BRICK)
	ch.put(sx, fy - 2, T.CHEST)
	for side in [-1, 1]:
		ch.put(sx + side * 6, fy - 1, T.GLOW_CRYSTAL)
		ch.put(sx + side * 6, fy - 2, T.GLOW_CRYSTAL)
	# the passage: four rows tall, climbing one row per column, lit by crystals in its roof
	var plen: int = site["len"]
	if plen <= 0:
		return
	var psx: int = sx + dir * (int(site["rx"]) - 3)
	for k in range(plen + 1):
		var px: int = psx + dir * k
		if px < cx0 or px > cx1:
			continue
		var fk: int = fy - k
		for y in range(fk - 4, fk):
			if ch.at(px, y) != T.BEDROCK:
				ch.put(px, y, T.AIR)
		var ft: int = ch.at(px, fk)
		if ft >= 0 and g.sol[ft] != 1 and k < plen - 2:
			ch.put(px, fk, T.STONE)
		for yy in [fk, fk - 5]:
			var lt: int = ch.at(px, yy)
			if lt >= 0 and g.liq[lt] == 1:
				ch.put(px, yy, T.STONE)
		var roof: int = ch.at(px, fk - 5)
		if k % 7 == 3 and roof >= 0 and g.sol[roof] == 1 and roof != T.BEDROCK:
			ch.put(px, fk - 5, T.GLOW_CRYSTAL)
		if bool(site["open"]):
			var h: int = _ground(g, px)
			if fk - 5 <= h + 1:
				for y in range(maxi(1, h - 18), fk - 4):
					var t: int = ch.at(px, y)
					if t >= 0 and (g.trk[t] == 1 or g.lea[t] == 1):
						ch.put(px, y, T.AIR)


static func _build_mine(g: WorldGen, ch: Chunk, site: Dictionary) -> void:
	var x: int = site["x"]
	var gy: int = site["ground"]
	var s: int = site["seed"]
	var levels: Array = site["levels"]
	var bottom: int = int(levels[levels.size() - 1])
	# the headframe over the shaft: two posts, a beam, a pulley wheel and a hatch
	for px in [x - 1, x + 3]:
		ch.fill(px, gy - 6, px, gy - 1, T.LOG)
	ch.fill(x - 2, gy - 7, x + 4, gy - 7, T.PLANKS)
	ch.put(x + 1, gy - 6, T.CRATE)
	ch.fill(x - 2, gy - 6, x + 4, gy - 1, T.AIR)
	for px in [x - 1, x + 3]:
		ch.fill(px, gy - 6, px, gy - 1, T.LOG)
	ch.fill(x, gy, x + 2, gy, T.PLATFORM)
	ch.put(x + 4, gy - 1, T.LANTERN)
	# the shaft: three wide, a ladder up the middle, timber walls
	ch.fill(x, gy + 1, x + 2, bottom - 1, T.AIR)
	ch.fill(x + 1, gy + 1, x + 1, bottom - 1, T.LADDER)
	for y in range(gy + 1, bottom):
		if (y - gy) % 5 == 0:
			ch.put(x - 1, y, T.PLANKS)
			ch.put(x + 3, y, T.PLANKS)
	ch.fill_wall(x, gy + 1, x + 2, bottom - 1, 5)
	# galleries off the shaft at each level: rails, props every six blocks, crates, carts and a chest at the end
	for li in range(levels.size()):
		var f: int = levels[li]
		var lens: Array = [int(site["left"][li]), int(site["right"][li])]
		for side_i in range(2):
			var side: int = -1 if side_i == 0 else 1
			var length: int = lens[side_i]
			var start: int = x - 1 if side < 0 else x + 3
			for k in range(length + 1):
				var gx: int = start + side * k
				ch.fill(gx, f - 4, gx, f - 1, T.AIR)
				var floor_t: int = ch.at(gx, f)
				if floor_t >= 0 and g.sol[floor_t] != 1:
					ch.put(gx, f, T.PLANKS)
				ch.put_wall(gx, f - 4, 0)
				ch.fill_wall(gx, f - 4, gx, f - 1, 2)
				if k % 6 == 3:
					ch.fill(gx, f - 4, gx, f - 1, T.LOG)
					ch.put(gx, f - 5, T.PLANKS)
					if _h(gx, f, s) < 0.45:
						ch.put(gx, f - 3, T.TORCH)
				elif k > 1 and k < length - 1 and _h(gx, f, s + 1) < 0.7:
					ch.put(gx, f - 1, T.RAIL)
				if k > 4 and k < length - 2:
					var r: float = _h(gx, f, s + 2)
					if r < 0.05:
						ch.put(gx, f - 1, T.CRATE)
					elif r < 0.08:
						ch.put(gx, f - 1, T.ORE_CART)
				if _h(gx, f, s + 3) < 0.1:
					ch.put_if_air(gx, f - 4, T.COBWEB)
			ch.put(start + side * length, f - 1, T.CHEST)
	ch.fill(x, bottom, x + 2, bottom, T.PLANKS)


# ---------------------------------------------------------------------------------------------- the Umbral Realm

static func _apply_umbral(g: WorldGen, ch: Chunk) -> void:
	var x0: int = ch.x0
	for c in range(PRNG.fdiv(x0 - 40, URUIN_CELL), PRNG.fdiv(x0 + Chunk.W + 40, URUIN_CELL) + 1):
		var sx: int = _u_ruin_site(g, c)
		if sx != -999999:
			_build_umbral_ruin(g, ch, sx, PRNG.hash_u(c, 513, g.world_seed))
	if absi(g.portal_x - (x0 + Chunk.W / 2)) < 30:
		_build_umbral_portal(g, ch)
	var cit: Dictionary = g.citadel()
	if absi(int(cit["x"]) - (x0 + Chunk.W / 2)) < 60:
		_build_citadel(g, ch, cit)


static func _u_ruin_site(g: WorldGen, c: int) -> int:
	if PRNG.hash2(c, 511, g.world_seed) > 0.55:
		return -999999
	var cit: Dictionary = g.citadel()
	if absi(c * URUIN_CELL + 140 - int(cit["x"])) < 200:
		return -999999
	var sx: int = c * URUIN_CELL + 40 + int(PRNG.hash2(c, 512, g.world_seed) * 180.0)
	if absi(sx - g.portal_x) < 60:
		return -999999
	if not g.infinite and (sx < 40 or sx > g.width - 40):
		return -999999
	return sx


static func _build_umbral_ruin(g: WorldGen, ch: Chunk, sx: int, s: int) -> void:
	var gy: int = g.u_floor(sx)
	var w: int = 15
	var x: int = sx - w / 2
	for xx in range(x - 3, x + w + 3):
		if xx < ch.x0 or xx >= ch.x0 + Chunk.W:
			continue
		var f: int = g.u_floor(xx)
		if f > gy:
			ch.fill(xx, gy, xx, f, T.ASH_STONE)
		ch.fill(xx, gy - 10, xx, gy - 1, T.AIR)
		ch.put(xx, gy, T.ASH_STONE)
	ch.fill(x, gy - 7, x + w - 1, gy - 1, T.BRICK)
	ch.fill(x + 1, gy - 6, x + w - 2, gy - 2, T.AIR)
	ch.fill(x + 1, gy - 1, x + w - 2, gy - 1, T.AIR)
	ch.fill(x, gy - 3, x, gy - 2, T.AIR)
	ch.fill(x + w - 1, gy - 3, x + w - 1, gy - 2, T.AIR)
	for k in range(5):
		if _h(k, 1, s) < 0.6:
			ch.put(x + 3 + k * 2, gy - 7, T.AIR)
	ch.put(x + 2, gy - 2, T.TORCH)
	ch.put(x + w - 3, gy - 2, T.TORCH)
	ch.put(x + w / 2, gy - 2, T.CHEST)
	ch.put(x + w / 2 - 3, gy - 2, T.SPIKES)
	ch.put(x + w / 2 + 3, gy - 2, T.SPIKES)
	if _h(1, 2, s) < 0.6:
		ch.put(x + w / 2 + 5, gy - 2, T.CHEST)
	ch.put(x + 1, gy - 5, T.GLOW_CRYSTAL)
	for xx in range(x, x + w):
		for yy in range(gy - 7, gy - 1):
			if ch.at(xx, yy) == T.BRICK and _h(xx, yy, s) < 0.12:
				ch.put(xx, yy, T.CRACKED_BRICK)


static func _build_umbral_portal(g: WorldGen, ch: Chunk) -> void:
	var px: int = g.portal_x
	var gy: int = g.umbral_portal_floor()
	ch.fill(px - 14, gy - 14, px + 14, gy - 1, T.AIR)
	ch.fill(px - 14, gy, px + 14, gy + 3, T.OBSIDIAN)
	for dx in range(-14, 15):
		if absi(dx) > 11:
			ch.put(px + dx, gy, T.ASH_STONE)
	rift_shape(ch, px, gy - 1, T.PORTAL_ON)
	ch.put(px - 9, gy - 1, T.LANTERN)
	ch.put(px + 9, gy - 1, T.LANTERN)
	ch.put(px - 12, gy - 1, T.GLOW_CRYSTAL)
	ch.put(px + 12, gy - 1, T.GLOW_CRYSTAL)
	ch.put(px + 7, gy - 1, T.CHEST)


static func throne_x(cit: Dictionary) -> int:
	return int(cit["x"]) - int(cit["gate"]) * 33


static func hoard_x(cit: Dictionary) -> int:
	return int(cit["x"]) - int(cit["gate"]) * 37


static func _build_citadel(g: WorldGen, ch: Chunk, c: Dictionary) -> void:
	var f: int = c["floor"]
	var cxx: int = c["x"]
	var s: int = g.world_seed + 9191
	var tx: int = throne_x(c)
	var hx: int = hoard_x(c)
	for x in range(cxx - 50, cxx + 51):
		if x < ch.x0 or x >= ch.x0 + Chunk.W:
			continue
		var dx: int = x - cxx
		ch.fill(x, f - 22, x, f - 1, T.AIR)
		ch.fill(x, f + 1, x, f + 3, T.OBSIDIAN)
		ch.put(x, f, T.CRACKED_BRICK if absi(dx) % 6 == 0 else T.BRICK)
		if absi(dx) <= 40:
			ch.fill_wall(x, f - 14, x, f - 1, 4)
		if absi(dx) == 12 or absi(dx) == 26:
			ch.fill_wall(x, f - 14, x, f - 1, 6)
		if absi(dx) == 41 or absi(dx) == 42:
			ch.fill(x, f - 15, x, f - 6, T.BRICK)
			if _h(x, 3, s) < 0.3:
				ch.put(x, f - 10, T.CRACKED_BRICK)
		if absi(dx) <= 42 and _h(x, 4, s) > 0.2:
			ch.put(x, f - 16, T.CRACKED_BRICK if _h(x, 5, s) < 0.25 else T.BRICK)
			if absi(dx) % 9 == 4:
				ch.put(x, f - 15, T.GLOW_CRYSTAL)
		if (absi(dx) == 6 or absi(dx) == 19 or absi(dx) == 33) and x != tx and x != hx:
			ch.put(x, f - 1, T.BRICK)
			ch.put(x, f - 2, T.LANTERN)
	for dx in range(-3, 4):
		ch.put(tx + dx, f - 1, T.BRICK)
	ch.fill(tx - int(c["gate"]), f - 4, tx - int(c["gate"]), f - 2, T.OBSIDIAN)
	ch.put(tx + 1, f - 2, T.CRACKED_BRICK)
	ch.put(tx - 1, f - 2, T.CRACKED_BRICK)
	ch.put(hx, f - 1, T.CHEST)
