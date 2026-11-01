class_name WorldGen
extends RefCounted
## Deterministic world generation, one 16-column chunk at a time. The same seed always gives the
## same world. Terrain heights, biomes, oceans, mountain ranges and the boss lairs follow the Swift
## game's own rules (the same hash noise); caves use Godot's FastNoiseLite so a chunk is quick enough
## to build on an iPad; ores grow as veins. Chunks can be built on worker threads: everything here
## only reads its own fields once set up (the column cache is guarded by a mutex).

const H := 560
const SEA := 120
const UMBRAL_H := 320
const UMBRAL_LAVA := 240
const FINITE_WIDTH := 4096
const EDGE_OCEAN := 520
const FLAT_SURFACE := 110
const FLAT_CRUST := 16

const OCEAN := 0
const PLAINS := 1
const FOREST := 2
const DESERT := 3
const TUNDRA := 4
const JUNGLE := 5
const SAVANNA := 6
const SWAMP := 7
const MOUNTAIN := 8
const UMBRAL := 9

const DIM_OVERWORLD := 0
const DIM_UMBRAL := 1

## [tile, top row, bottom row, veins per chunk, smallest vein, largest vein, salt, region share]
const ORE_RULES := [
	[T.AMETHYST, 150, 330, 0.5, 3, 6, 41, 0.0],
	[T.SALTPETER, 112, 205, 2.0, 4, 8, 42, 0.0],
	[T.TIN, 122, 265, 6.0, 4, 9, 43, 0.47],
	[T.COAL, 120, 340, 11.0, 5, 13, 31, 0.0],
	[T.COPPER, 125, 345, 9.0, 4, 11, 32, 0.0],
	[T.SILVER, 200, 400, 2.5, 3, 7, 44, 0.0],
	[T.IRON, 205, 450, 6.0, 4, 9, 33, 0.0],
	[T.GOLD, 310, 530, 4.5, 3, 7, 34, 0.0],
	[T.DIAMOND, 390, 548, 1.8, 2, 4, 35, 0.0],
	[T.MYTHRIL, 455, 548, 0.7, 2, 4, 36, 0.0],
]

const ZONE_CLIMATE := [[0.14, 0.50], [0.50, 0.33], [0.50, 0.64], [0.88, 0.14], [0.88, 0.88], [0.88, 0.50], [0.50, 0.90]]

var world_seed: int = 0
var infinite: bool = true
var width: int = 2000000000
var spawn_x: int = 0
var flat: bool = false
var opt_trees: bool = true
var opt_structures: bool = true
var opt_caves: bool = false
var opt_ponds: bool = false
var rare_chance: float = 0.28
var zones: Array = []
var portal_x: int = 0
var portal_y: int = 380
var opq := PackedByteArray()
var sol := PackedByteArray()
var liq := PackedByteArray()
var trk := PackedByteArray()
var lea := PackedByteArray()
var _cols := {}
var _mutex := Mutex.new()
## structure sites worked out so far (see Structures), guarded by the same mutex
var sites := {}

var n_region := FastNoiseLite.new()
var n_tunnel := FastNoiseLite.new()
var n_width := FastNoiseLite.new()
var n_cham := FastNoiseLite.new()
var n_cham2 := FastNoiseLite.new()
var n_shaft := FastNoiseLite.new()
var n_isle := FastNoiseLite.new()
var n_ember := FastNoiseLite.new()
var n_void := FastNoiseLite.new()
var n_obs := FastNoiseLite.new()


## options: {"flat", "trees", "structures", "caves", "ponds"}
func _init(seed_in: int = 1, infinite_in: bool = true, options: Dictionary = {}, rare: float = 0.28) -> void:
	world_seed = seed_in
	infinite = infinite_in
	flat = bool(options.get("flat", false))
	opt_trees = bool(options.get("trees", true))
	opt_structures = bool(options.get("structures", true))
	opt_caves = bool(options.get("caves", false))
	opt_ponds = bool(options.get("ponds", false))
	rare_chance = rare
	width = 2000000000 if infinite else FINITE_WIDTH
	spawn_x = 0 if infinite else FINITE_WIDTH / 2
	# own copies of the tables, so chunks can be built on worker threads
	opq = DB.opaque.duplicate()
	sol = DB.solid.duplicate()
	liq = DB.liquid.duplicate()
	trk = DB.trunk.duplicate()
	lea = DB.leaf.duplicate()
	zones = _make_zones()
	var salt: int = 21
	for n in [n_region, n_tunnel, n_width, n_cham, n_cham2, n_shaft, n_isle, n_ember, n_void, n_obs]:
		n.noise_type = FastNoiseLite.TYPE_VALUE
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
		n.frequency = 1.0
		n.seed = int(PRNG.hash_u(salt, 900, world_seed) & 0x7FFFFFFF)
		salt += 1
	_find_portal()


func has_trees() -> bool:
	return not flat or opt_trees


func has_structures() -> bool:
	return not flat or opt_structures


func height_of(dim: int) -> int:
	return H if dim == DIM_OVERWORLD else UMBRAL_H


func h2(x: int, y: int, s: int) -> float:
	return PRNG.hash2(x, y, world_seed + s)


# ---------------------------------------------------------------------------------------------- layout

## Finite worlds lay biome zones out in a seeded order so every biome is always present.
## climate ids: 0 tundra, 1 plains, 2 forest, 3 desert, 4 jungle, 5 savanna, 6 swamp
func _make_zones() -> Array:
	if infinite:
		return []
	var pool: Array = [0, 3, 5, 6, 1, 2]
	var extra: Array = [0, 3, 5, 1, 2]
	pool[5] = extra[int(PRNG.hash2(7, 7, world_seed) * 5.0) % 5]
	var rng := SplitRNG.new(world_seed + 4242)
	var i: int = pool.size() - 1
	while i > 0:
		var j: int = rng.below(i + 1)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
		i -= 1
	var z: Array = [1, 1, 1, 1, 1, 1, 1, 1, 1]
	z[1] = 4
	z[4] = 1 if PRNG.hash2(8, 8, world_seed) < 0.5 else 2
	z[7] = 2
	var slots: Array = [0, 2, 3, 5, 6, 8]
	for k in range(6):
		z[slots[k]] = pool[k]
	return z


func _find_portal() -> void:
	var hs: float = PRNG.hash2(1, 2, world_seed)
	var dist: int = (1500 + int(hs * 1800.0)) if infinite else (300 + int(hs * 400.0))
	var side: int = -1 if PRNG.hash2(3, 4, world_seed) < 0.5 else 1
	var found: int = spawn_x + side * dist
	var ok: bool = false
	for attempt in range(4):
		var sd: int = side if attempt % 2 == 0 else -side
		var dd: int = dist if attempt < 2 else (2400 if infinite else 520)
		var step: int = 0
		while step < 400 and not ok:
			var off: int = (1 if step % 2 == 0 else -1) * ((step + 1) / 2) * 5
			var x: int = spawn_x + sd * dd + off
			var c: Array = col(x)
			if int(c[1]) != OCEAN and int(c[1]) != SWAMP and float(c[2]) > 0.5 and lair_at(x, 230).is_empty() \
					and absi(x - spawn_x) < 3800 and absi(x - spawn_x) > 200:
				found = x
				ok = true
			step += 1
		if ok:
			break
	portal_x = found
	portal_y = 350 + int(PRNG.hash2(5, 6, world_seed) * 60.0)


# ---------------------------------------------------------------------------------------------- lairs

## The boss lair whose centre is within `radius` of x: {"kind": "bear"/"rex", "cx", "k"}, or {}
func lair_at(x: int, radius: int = 150) -> Dictionary:
	if not has_structures():
		return {}
	var period: int = 4096
	var bases: Array = [spawn_x + 1000, spawn_x - 1100]
	for i in range(2):
		var base: int = bases[i]
		var k: int = roundi(float(x - base) / float(period)) if infinite else 0
		var cx: int = base + k * period
		if absi(x - cx) < radius:
			return {"kind": "bear" if i == 0 else "rex", "cx": cx, "k": k}
	return {}


func lair_centers(x: int) -> Array:
	var out: Array = []
	if not has_structures():
		return out
	var period: int = 4096
	var bases: Array = [spawn_x + 1000, spawn_x - 1100]
	for i in range(2):
		var base: int = bases[i]
		var kc: int = roundi(float(x - base) / float(period)) if infinite else 0
		var ks: Array = [kc - 1, kc, kc + 1] if infinite else [0]
		for k in ks:
			out.append({"kind": "bear" if i == 0 else "rex", "cx": base + int(k) * period, "k": int(k)})
	return out


func _lair_static(x: int, radius: int) -> Dictionary:
	var period: int = 4096
	var bases: Array = [spawn_x + 1000, spawn_x - 1100]
	for i in range(2):
		var base: int = bases[i]
		var k: int = roundi(float(x - base) / float(period)) if infinite else 0
		var cx: int = base + k * period
		if absi(x - cx) < radius:
			return {"kind": "bear" if i == 0 else "rex", "cx": cx, "k": k}
	return {}


# ---------------------------------------------------------------------------------------------- climate & terrain

func _zone_coord(count: int, x: int) -> float:
	var x0: float = float(EDGE_OCEAN)
	var zw: float = (float(width) - 2.0 * x0) / float(count)
	return (float(x) - x0) / zw - 0.5


func _climate(x: int) -> Vector2:
	var fx: float = float(x)
	var temp: float = PRNG.fbm1(fx / 700.0, world_seed + 11, 2)
	var humid: float = PRNG.fbm1(fx / 520.0, world_seed + 12, 2)
	if infinite or zones.size() < 2:
		return Vector2(0.5 + (temp - 0.5) * 1.3, 0.5 + (humid - 0.5) * 1.3)
	var t: float = clampf(_zone_coord(zones.size(), x), 0.0, float(zones.size() - 1) - 0.0001)
	var i: int = int(t)
	var f: float = t - float(i)
	var s: float = PRNG.smooth(clampf((f - 0.3) / 0.4, 0.0, 1.0))
	var a: Array = ZONE_CLIMATE[int(zones[i])]
	var b: Array = ZONE_CLIMATE[int(zones[i + 1])]
	temp = lerpf(float(a[0]), float(b[0]), s) + (temp - 0.5) * 0.30
	humid = lerpf(float(a[1]), float(b[1]), s) + (humid - 0.5) * 0.30
	return Vector2(temp, humid)


func _range_bump(x: int) -> float:
	var best: float = 0.0
	if infinite:
		var cell_w: int = 1100
		var c0: int = PRNG.fdiv(x, cell_w)
		for c in range(c0 - 1, c0 + 2):
			if PRNG.hash2(c, 302, world_seed) > 0.52:
				continue
			var cen: int = c * cell_w + 200 + int(PRNG.hash2(c, 303, world_seed) * 700.0)
			var hw: float = 130.0 + PRNG.hash2(c, 304, world_seed) * 110.0
			best = maxf(best, PRNG.smooth(clampf(1.0 - float(absi(x - cen)) / hw, 0.0, 1.0)))
	else:
		var zw: float = (float(width) - 2.0 * float(EDGE_OCEAN)) / 9.0
		var ka: int = 2 + int(PRNG.hash2(1, 305, world_seed) * 2.0)
		var kb: int = 6 + int(PRNG.hash2(2, 305, world_seed) * 2.0)
		var ca: float = float(EDGE_OCEAN) + zw * float(ka) + (PRNG.hash2(1, 307, world_seed) - 0.5) * 80.0
		var cb: float = float(EDGE_OCEAN) + zw * float(kb) + (PRNG.hash2(2, 307, world_seed) - 0.5) * 80.0
		var cs: Array = [ca, cb]
		for k in range(2):
			var hw: float = 160.0 + PRNG.hash2(k, 306, world_seed) * 70.0
			best = maxf(best, PRNG.smooth(clampf(1.0 - absf(float(x) - float(cs[k])) / hw, 0.0, 1.0)))
	return best


func _basin_weight(x: int, center: int, half_w: int, ramp: int) -> float:
	var d: float = float(absi(x - center))
	return 1.0 - PRNG.smooth(clampf((d - float(half_w)) / float(ramp), 0.0, 1.0))


## 0..1: how strongly x lies inside an ocean basin (1 = open sea)
func _ocean_basin(x: int) -> float:
	var side: int = -1 if PRNG.hash2(41, 42, world_seed) < 0.5 else 1
	var off: int = 560 + int(PRNG.hash2(43, 44, world_seed) * 120.0)
	var w: float = _basin_weight(x, spawn_x + side * off, 150 + int(PRNG.hash2(45, 46, world_seed) * 50.0), 110)
	if infinite:
		var c0: int = PRNG.fdiv(x, 1600)
		for c in range(c0 - 1, c0 + 2):
			if PRNG.hash2(c, 401, world_seed) > 0.26:
				continue
			var hw: int = 140 + int(PRNG.hash2(c, 402, world_seed) * 220.0)
			var cen: int = c * 1600 + hw + 140 + int(PRNG.hash2(c, 403, world_seed) * float(maxi(1, 1600 - 2 * hw - 280)))
			if absi(cen - spawn_x) < hw + 900:
				continue
			var near_lair: bool = false
			for lc in [spawn_x + 1000, spawn_x - 1100]:
				var k: int = roundi(float(cen - int(lc)) / 4096.0)
				for kk in range(k - 1, k + 2):
					if absi(cen - (int(lc) + kk * 4096)) < hw + 330:
						near_lair = true
			if near_lair:
				continue
			w = maxf(w, _basin_weight(x, cen, hw, 140))
	return w


## The ground row, biome and terrain factors of column x: [h, biome, land, mountain, swamp]
func col(x: int) -> Array:
	_mutex.lock()
	var c = _cols.get(x)
	_mutex.unlock()
	if c != null:
		return c
	var v: Array = _flat_col(x) if flat else _col_base(x)
	_mutex.lock()
	if _cols.size() > 30000:
		_cols.clear()
	_cols[x] = v
	_mutex.unlock()
	return v


func _biome_from(temp: float, humid: float) -> Array:
	var tundra: float = PRNG.smooth(clampf((0.31 - temp) / 0.06, 0.0, 1.0))
	var hot: float = PRNG.smooth(clampf((temp - 0.64) / 0.06, 0.0, 1.0))
	var desert: float = hot * PRNG.smooth(clampf((0.42 - humid) / 0.06, 0.0, 1.0))
	var jungle: float = hot * PRNG.smooth(clampf((humid - 0.58) / 0.06, 0.0, 1.0))
	var savanna: float = hot * (1.0 - desert) * (1.0 - jungle)
	var swamp: float = PRNG.smooth(clampf((humid - 0.68) / 0.06, 0.0, 1.0)) * (1.0 - tundra) * (1.0 - hot)
	var biome: int = FOREST if humid > 0.5 else PLAINS
	if tundra > 0.5:
		biome = TUNDRA
	elif desert > 0.5:
		biome = DESERT
	elif jungle > 0.5:
		biome = JUNGLE
	elif savanna > 0.5:
		biome = SAVANNA
	elif swamp > 0.5:
		biome = SWAMP
	return [biome, tundra, hot, desert, jungle, savanna, swamp]


func _flat_col(x: int) -> Array:
	var cl: Vector2 = _climate(x)
	var b: Array = _biome_from(cl.x, cl.y)
	var biome: int = int(b[0])
	if has_structures():
		var lair: Dictionary = _lair_static(x, 150)
		if not lair.is_empty() and absi(x - int(lair["cx"])) < 120:
			biome = FOREST if lair["kind"] == "bear" else JUNGLE
	return [FLAT_SURFACE, biome, 0.7, 0.0, 0.0]


func _col_base(x: int) -> Array:
	var fx: float = float(x)
	var land: float = PRNG.fbm1(fx / 800.0, world_seed + 1, 3)
	if not infinite:
		var e: float = float(mini(x, width - 1 - x))
		var eo: float = float(EDGE_OCEAN)
		if e < eo:
			land *= PRNG.smooth(clampf(e / eo, 0.0, 1.0))
		if x < 0 or x >= width:
			land = 0.0
		if zones.size() > 1 and e > eo * 0.55:
			var zc: float = _zone_coord(zones.size(), x) + 0.5
			var fr: float = absf(zc - floorf(zc) - 0.5)
			var wgt: float = 1.0 - PRNG.smooth(clampf((fr - 0.2) / 0.2, 0.0, 1.0))
			land = lerpf(land, maxf(land, 0.62), wgt)
	var ds: float = float(absi(x - spawn_x))
	if ds < 320.0:
		land = lerpf(land, maxf(land, 0.64), minf(1.0, (1.0 - ds / 320.0) * 1.6))
	var lw: float = 0.0
	var forced: int = -1
	var lair: Dictionary = _lair_static(x, 150)
	if not lair.is_empty():
		var d: float = float(absi(x - int(lair["cx"])))
		lw = 1.0 - PRNG.smooth(clampf((d - 60.0) / 90.0, 0.0, 1.0))
		land = maxf(land, lerpf(land, 0.65, lw))
		if d < 120.0:
			forced = FOREST if lair["kind"] == "bear" else JUNGLE
	var basin: float = _ocean_basin(x)
	if basin > 0.0:
		land = minf(land, lerpf(land, 0.17, basin))
	var mraw: float = maxf(PRNG.fbm1(fx / 420.0, world_seed + 3, 2) - 0.08, 0.56 + 0.40 * _range_bump(x))
	var mtn: float = PRNG.smooth(clampf((mraw - 0.60) / 0.16, 0.0, 1.0)) * clampf((land - 0.45) / 0.1, 0.0, 1.0)
	mtn *= clampf((ds - 170.0) / 130.0, 0.0, 1.0)
	if lw > 0.0:
		mtn *= (1.0 - lw)
	var cl: Vector2 = _climate(x)
	var b: Array = _biome_from(cl.x, cl.y)
	var biome: int = int(b[0])
	var tundra: float = float(b[1])
	var desert: float = float(b[3])
	var jungle: float = float(b[4])
	var savanna: float = float(b[5])
	var swamp: float = float(b[6])
	if lw > 0.0:
		swamp *= (1.0 - lw)
		if biome == SWAMP and swamp <= 0.5:
			biome = FOREST if cl.y > 0.5 else PLAINS
	if mtn > 0.35:
		biome = MOUNTAIN
	if land < 0.40:
		biome = OCEAN
	if forced >= 0:
		biome = forced
	var amp: float = maxf(0.12, 1.0 - 0.4 * tundra - 0.3 * desert - 0.5 * savanna - 0.88 * swamp + 0.15 * jungle)
	var hgt: float
	if land >= 0.40:
		var t: float = clampf((land - 0.40) / 0.25, 0.0, 1.0)
		hgt = float(SEA) - 2.0 - t * 12.0
		var hills: float = (PRNG.fbm1(fx / 55.0, world_seed + 2, 3) - 0.5) * 2.0 * 15.0 * amp
		var bumps: float = (PRNG.noise1(fx / 9.0, world_seed + 8) - 0.5) * 3.0 * amp
		hgt -= hills + bumps
		var v: float = PRNG.fbm1(fx / 140.0, world_seed + 5, 2)
		if v < 0.36:
			hgt += (0.36 - v) / 0.36 * 16.0 * minf(1.0, amp)
		var cliff: float = PRNG.noise1(fx / 95.0, world_seed + 6)
		if cliff > 0.72:
			hgt -= 10.0 * PRNG.smooth(clampf((cliff - 0.72) / 0.015, 0.0, 1.0))
		var peak: float = PRNG.fbm1(fx / 70.0, world_seed + 4, 4)
		hgt -= mtn * (14.0 + peak * 70.0)
		if swamp > 0.0:
			var target: float = float(SEA) + (PRNG.noise1(fx / 14.0, world_seed + 9) - 0.55) * 5.0
			hgt = lerpf(hgt, target, swamp)
	else:
		var dd: float = clampf((0.40 - land) / 0.14, 0.0, 1.0)
		hgt = float(SEA) - 2.0 + dd * 48.0 + (PRNG.noise1(fx / 7.0, world_seed + 10) - 0.5) * 3.0 * dd
	if lw > 0.0:
		hgt = lerpf(hgt, float(SEA - 10), lw)
	var hi: int = clampi(roundi(hgt), 14, H - 80)
	return [hi, biome, land, mtn, swamp]


func surface_at(x: int) -> int:
	return int(col(x)[0])


func biome_at(x: int) -> int:
	return int(col(x)[1])


func tree_density(b: int, hgt: int) -> float:
	match b:
		FOREST: return 0.14
		PLAINS: return 0.04
		JUNGLE: return 0.22
		SAVANNA: return 0.04
		TUNDRA: return 0.08
		SWAMP: return 0.10
		MOUNTAIN: return 0.05 if hgt > 98 else 0.0
		DESERT: return 0.035
	return 0.0


# ---------------------------------------------------------------------------------------------- caves

func _v(n: FastNoiseLite, x: float, y: float) -> float:
	return (n.get_noise_2d(x, y) + 1.0) * 0.5


## Worm tunnels in cave regions, big chambers deeper down, and the odd vertical shaft near the top
func is_cave(x: int, y: int, depth: int, surface: int, shaft_n: float) -> bool:
	if depth < 5 or y < surface + 5:
		return false
	var fx: float = float(x)
	var fy: float = float(y)
	if _v(n_region, fx * 0.013, fy * 0.013) > 0.34:
		var a: float = _v(n_tunnel, fx * 0.045, fy * 0.06)
		var w: float = 0.030 + 0.05 * _v(n_width, fx * 0.02, fy * 0.02)
		if absf(a - 0.5) < w:
			return true
	if depth > 26 and y >= surface + 27:
		var bonus: float = minf(0.05, maxf(0.0, fy - 150.0) * 0.00015)
		var c1: float = _v(n_cham, fx * 0.03, fy * 0.045)
		if c1 * 0.65 + 0.35 > 0.715 - bonus:
			var c2: float = _v(n_cham2, fx * 0.085, fy * 0.1)
			if c1 * 0.65 + c2 * 0.35 > 0.715 - bonus:
				return true
	if depth < 40 and shaft_n > 0.90:
		if _v(n_shaft, fx * 0.2, fy * 0.2) > 0.35:
			return true
	return false


func _rock_at(x: int, y: int) -> int:
	var hoff: float = (PRNG.hash2(x, y / 3, world_seed + 5) - 0.5) * 12.0
	var by: int = y + int(hoff)
	if by < 300:
		return T.STONE
	if by < 430:
		return T.SLATE
	return T.DEEP_ROCK


# ---------------------------------------------------------------------------------------------- chunks

func generate_chunk(cx: int, dim: int) -> Chunk:
	if dim == DIM_UMBRAL:
		return _generate_umbral(cx)
	return _generate_overworld(cx)


func _generate_overworld(cx: int) -> Chunk:
	var ch := Chunk.new(cx, H)
	var x0: int = cx * Chunk.W
	var m: int = 12
	var cols: Array = []
	for x in range(x0 - m, x0 + Chunk.W + m):
		cols.append(col(x))
	var surf_biome: Array = []
	for lx in range(Chunk.W):
		var x: int = x0 + lx
		var c: Array = cols[lx + m]
		var jit: int = int((PRNG.hash2(x, 1, world_seed + 61) - 0.5) * 10.0)
		var sb: int = int(cols[clampi(lx + m + jit, 0, cols.size() - 1)][1])
		if int(c[1]) == OCEAN:
			sb = OCEAN
		elif sb == OCEAN:
			sb = int(c[1])
		surf_biome.append(sb)
		var base: int = lx * H
		if not infinite and (x < 0 or x >= width):
			for y in range(H):
				ch.tiles[base + y] = T.BEDROCK
			ch.surf[lx] = H - 1
			continue
		var hgt: int = int(c[0])
		ch.surf[lx] = hgt
		if flat:
			_fill_flat_column(ch, lx, x, hgt, sb)
		else:
			_fill_standard_column(ch, lx, x, hgt, sb)
		# mushrooms on cave floors, cobwebs under cave roofs
		var y: int = hgt + 8
		while y < H - 6:
			if ch.tiles[base + y] == T.AIR:
				var below: int = ch.tiles[base + y + 1]
				var above: int = ch.tiles[base + y - 1]
				if sol[below] == 1 and below != T.BEDROCK and y > 190 and y < 470 and PRNG.hash2(x, y, world_seed + 81) < 0.025:
					ch.tiles[base + y] = T.MUSHROOM
				elif sol[above] == 1 and PRNG.hash2(x, y, world_seed + 82) < 0.012:
					ch.tiles[base + y] = T.COBWEB
			y += 1
	_place_ores(ch, cols, m)
	if has_trees():
		_plants_and_trees(ch, cols, m, surf_biome)
	Structures.apply(self, ch, DIM_OVERWORLD)
	ch.rebuild_sky(opq)
	return ch


func _fill_standard_column(ch: Chunk, lx: int, x: int, hgt: int, sb: int) -> void:
	var base: int = lx * H
	var top_t: int = T.GRASS
	var fill_t: int = T.DIRT
	var fill_d: int = 5
	match sb:
		DESERT:
			top_t = T.SAND
			fill_t = T.SAND
			fill_d = 9
		TUNDRA:
			top_t = T.SNOW
			fill_t = T.SNOW
			fill_d = 3
		JUNGLE:
			top_t = T.JUNGLE_GRASS
			fill_t = T.MUD
			fill_d = 7
		SAVANNA:
			top_t = T.DRY_GRASS
			fill_d = 4
		SWAMP:
			top_t = T.MOSS_GRASS
			fill_t = T.MUD
			fill_d = 6
		OCEAN:
			top_t = T.SAND
			fill_t = T.SAND
			fill_d = 5
		MOUNTAIN:
			if hgt <= 72:
				top_t = T.SNOW
				fill_t = T.SNOW
				fill_d = 3
			elif hgt <= 100:
				top_t = T.STONE
				fill_t = T.STONE
				fill_d = 4
	if sb != OCEAN and sb != SWAMP and sb != DESERT and hgt >= SEA - 1 and hgt <= SEA + 2:
		top_t = T.SAND
		fill_t = T.SAND
		fill_d = 4
	if hgt > SEA:
		for y in range(SEA, hgt):
			ch.tiles[base + y] = T.ICE if (sb == TUNDRA and y == SEA) else T.WATER
	var shaft_n: float = PRNG.noise1(float(x) / 18.0, world_seed + 26)
	for y in range(hgt, H):
		var depth: int = y - hgt
		var t: int
		if y >= H - 1:
			t = T.BEDROCK
		elif y >= H - 5 and PRNG.hash2(x, y, world_seed + 3) < float(y - (H - 6)) * 0.22:
			t = T.BEDROCK
		elif depth == 0:
			t = top_t
		elif depth < fill_d:
			t = T.DIRT if (sb == TUNDRA and depth >= 3) else fill_t
		elif sb == DESERT and depth < 24:
			t = T.SANDSTONE
		else:
			t = _rock_at(x, y)
		if depth >= 4 and y < H - 5 and is_cave(x, y, depth, hgt, shaft_n):
			if y >= 500:
				t = T.LAVA
			elif y > 200 and y < 430 and PRNG.hash2(PRNG.fdiv(x, 60), y / 48, world_seed + 28) < 0.28 and (y % 48) > 28:
				t = T.WATER
			else:
				t = T.AIR
		ch.tiles[base + y] = t


func _fill_flat_column(ch: Chunk, lx: int, x: int, hgt: int, sb: int) -> void:
	var top_t: int = T.GRASS
	var fill_t: int = T.DIRT
	match sb:
		DESERT:
			top_t = T.SAND
			fill_t = T.SAND
		TUNDRA:
			top_t = T.SNOW
		JUNGLE:
			top_t = T.JUNGLE_GRASS
			fill_t = T.MUD
		SAVANNA:
			top_t = T.DRY_GRASS
		SWAMP:
			top_t = T.MOSS_GRASS
			fill_t = T.MUD
	var pond: int = pond_depth(x)
	if pond == 0 and near_pond(x, 1):
		top_t = T.SAND
	var base: int = lx * H
	for y in range(hgt, H):
		var depth: int = y - hgt
		var t: int
		if y >= H - 3:
			t = T.BEDROCK
		elif depth < pond:
			t = T.ICE if (sb == TUNDRA and depth == 0) else T.WATER
		elif depth == pond and pond > 0:
			t = T.SAND
		elif depth == 0:
			t = top_t
		elif depth <= 4:
			t = fill_t
		elif y < 300:
			t = T.STONE
		elif y < 430:
			t = T.SLATE
		else:
			t = T.DEEP_ROCK
		if y < H - 5 and depth >= FLAT_CRUST and opt_caves and is_cave(x, y, depth, hgt, 0.0):
			if y >= 500:
				t = T.LAVA
			elif y > 200 and y < 430 and PRNG.hash2(PRNG.fdiv(x, 60), y / 48, world_seed + 28) < 0.28 and (y % 48) > 28:
				t = T.WATER
			else:
				t = T.AIR
		ch.tiles[base + y] = t


# ---------------------------------------------------------------------------------------------- ponds (flat worlds)

const POND_CELL := 260


func pond_site(c: int) -> Dictionary:
	if not flat or not opt_ponds:
		return {}
	if PRNG.hash2(c, 501, world_seed) > 0.5:
		return {}
	var cxp: int = c * POND_CELL + 50 + int(PRNG.hash2(c, 502, world_seed) * float(POND_CELL - 100))
	var hw: int = 4 + int(PRNG.hash2(c, 503, world_seed) * 6.0)
	var depth: int = 3 if PRNG.hash2(c, 504, world_seed) < 0.4 else 2
	if not infinite and (cxp - hw < 40 or cxp + hw > width - 40):
		return {}
	if absi(cxp - spawn_x) < hw + 24 or absi(cxp - portal_x) < hw + 16:
		return {}
	if not lair_at(cxp, hw + 60).is_empty():
		return {}
	return {"cx": cxp, "hw": hw, "depth": depth}


func pond_depth(x: int) -> int:
	if not flat or not opt_ponds:
		return 0
	var c: int = PRNG.fdiv(x, POND_CELL)
	for cc in range(c - 1, c + 2):
		var p: Dictionary = pond_site(cc)
		if p.is_empty():
			continue
		var dx: int = absi(x - int(p["cx"]))
		if dx > int(p["hw"]):
			continue
		var f: float = float(dx) / (float(p["hw"]) + 0.5)
		var d: int = ceili(float(p["depth"]) * sqrt(maxf(0.0, 1.0 - f * f)))
		return clampi(d, 1, int(p["depth"]))
	return 0


func near_pond(x: int, pad: int) -> bool:
	if not flat or not opt_ponds:
		return false
	var c: int = PRNG.fdiv(x, POND_CELL)
	for cc in range(c - 1, c + 2):
		var p: Dictionary = pond_site(cc)
		if not p.is_empty() and absi(x - int(p["cx"])) <= int(p["hw"]) + pad:
			return true
	return false


# ---------------------------------------------------------------------------------------------- ores

const ORE_HOSTS := [T.STONE, T.SLATE, T.DEEP_ROCK, T.SANDSTONE, T.DIRT, T.MUD]


func _ore_bias(biome: int, t: int) -> float:
	match t:
		T.GOLD:
			if biome == DESERT: return 0.045
			if biome == SAVANNA: return 0.03
		T.IRON:
			if biome == MOUNTAIN: return 0.035
		T.MYTHRIL:
			if biome == MOUNTAIN: return 0.03
		T.DIAMOND:
			if biome == TUNDRA: return 0.03
		T.COPPER:
			if biome == JUNGLE: return 0.04
		T.COAL:
			if biome == SWAMP: return 0.05
		T.SALTPETER:
			if biome == DESERT: return 0.05
			if biome == SAVANNA: return 0.04
			if biome == MOUNTAIN: return 0.02
			if biome == SWAMP or biome == JUNGLE or biome == OCEAN: return -0.2
		T.TIN:
			if biome == MOUNTAIN or biome == TUNDRA: return 0.03
		T.SILVER:
			if biome == MOUNTAIN or biome == TUNDRA: return 0.02
	return 0.0


## Ore veins: each chunk seeds its own, and the veins of both neighbours are drawn too (clipped), so
## a vein crossing a chunk edge is never cut off
func _place_ores(ch: Chunk, cols: Array, m: int) -> void:
	var x0: int = ch.x0
	for rule in ORE_RULES:
		var tile: int = rule[0]
		var y_lo: int = rule[1]
		var y_hi: int = rule[2]
		var per: float = rule[3]
		var region: float = rule[7]
		for scx in range(ch.cx - 1, ch.cx + 2):
			var rng := SplitRNG.new(PRNG.hash_u(scx, int(rule[6]), world_seed))
			var count: int = int(per)
			if rng.next_float() < per - float(count):
				count += 1
			for k in range(count):
				var sx: int = scx * Chunk.W + rng.below(Chunk.W)
				var sy: int = rng.range_i(y_lo, y_hi)
				var size: int = rng.range_i(int(rule[4]), int(rule[5]))
				var biome: int = int(col(sx)[1]) if absi(sx - x0) > m + Chunk.W else int(cols[clampi(sx - x0 + m, 0, cols.size() - 1)][1])
				var bias: float = _ore_bias(biome, tile)
				if bias < -0.1:
					continue
				if bias > 0.0 and rng.next_float() < bias * 18.0:
					size += 3
				if region > 0.0 and PRNG.noise1(float(sx) / 600.0, world_seed + int(rule[6]) * 7) < region:
					continue
				var vx: int = sx
				var vy: int = sy
				for step in range(size):
					var lx: int = vx - x0
					if lx >= 0 and lx < Chunk.W and vy > 0 and vy < H - 5:
						var surface: int = ch.surf[lx]
						if vy > surface + 8:
							var i: int = lx * H + vy
							if ORE_HOSTS.has(ch.tiles[i]):
								ch.tiles[i] = tile
					match rng.below(4):
						0: vx += 1
						1: vx -= 1
						2: vy += 1
						_: vy -= 1


# ---------------------------------------------------------------------------------------------- surface life

func _plants_and_trees(ch: Chunk, cols: Array, m: int, surf_biome: Array) -> void:
	var x0: int = ch.x0
	var blocked_cache := {}
	for lx in range(-6, Chunk.W + 6):
		var x: int = x0 + lx
		if not infinite and (x < 4 or x > width - 5):
			continue
		var c: Array = cols[lx + m]
		var cb: int = int(c[1])
		if cb == OCEAN or Structures.blocks_trees(self, x, blocked_cache):
			continue
		var in_chunk: bool = lx >= 0 and lx < Chunk.W
		var sb: int = int(surf_biome[lx]) if in_chunk else cb
		var hgt: int = int(c[0])
		if in_chunk:
			var r: float = PRNG.hash2(x, 5, world_seed + 90)
			var gy: int = hgt - 1
			var surf: int = ch.get_local(lx, hgt)
			if gy > 0 and ch.get_local(lx, gy) == T.AIR and hgt <= SEA:
				if (sb == PLAINS or sb == FOREST) and surf == T.GRASS:
					if r < 0.20:
						ch.set_local(lx, gy, T.TALL_GRASS)
					elif r < 0.235:
						ch.set_local(lx, gy, T.FLOWER_R)
					elif r < 0.27:
						ch.set_local(lx, gy, T.FLOWER_Y)
				elif sb == JUNGLE and surf == T.JUNGLE_GRASS:
					if r < 0.30:
						ch.set_local(lx, gy, T.TALL_GRASS)
					elif r < 0.34:
						ch.set_local(lx, gy, T.FLOWER_R)
				elif sb == SAVANNA and surf == T.DRY_GRASS:
					if r < 0.14:
						ch.set_local(lx, gy, T.TALL_GRASS)
				elif sb == SWAMP and surf == T.MOSS_GRASS:
					if r < 0.14:
						ch.set_local(lx, gy, T.REED)
					elif r < 0.17:
						ch.set_local(lx, gy, T.MUSHROOM)
				elif sb == DESERT and surf == T.SAND:
					if r < 0.03:
						ch.set_local(lx, gy, T.DEAD_BUSH)
		if not _is_tree(x, cols, m, x0):
			continue
		if _is_tree(x - 1, cols, m, x0) or _is_tree(x - 2, cols, m, x0) or _is_tree(x - 3, cols, m, x0):
			continue
		if absi(int(_col_from(x - 1, cols, m, x0)[0]) - int(_col_from(x + 1, cols, m, x0)[0])) > 1:
			continue
		_grow_tree(ch, x, hgt, cb)
	# palms on warm beaches
	for lx in range(Chunk.W):
		var x: int = x0 + lx
		var c: Array = cols[lx + m]
		var hgt: int = int(c[0])
		if int(c[1]) == OCEAN or hgt < SEA - 3 or hgt > SEA + 1:
			continue
		if ch.get_local(lx, hgt) != T.SAND or ch.get_local(lx, hgt - 1) != T.AIR:
			continue
		if PRNG.hash2(x, 6, world_seed + 97) > 0.035:
			continue
		var th: int = 6 + int(PRNG.hash2(x, 7, world_seed + 97) * 4.0)
		for k in range(1, th + 1):
			ch.put(x + (1 if k > th - 3 else 0), hgt - k, T.PALM_LOG)
		for dx in range(-3, 5):
			ch.put_if_air(x + 1 + dx, hgt - th - (0 if absi(dx) > 2 else 1), T.JUNGLE_LEAVES)


func _col_from(x: int, cols: Array, m: int, x0: int) -> Array:
	var i: int = x - (x0 - m)
	if i >= 0 and i < cols.size():
		return cols[i]
	return col(x)


func _is_tree(x: int, cols: Array, m: int, x0: int) -> bool:
	var c: Array = _col_from(x, cols, m, x0)
	var d: float = tree_density(int(c[1]), int(c[0]))
	if d <= 0.0:
		return false
	if PRNG.hash2(x, 3, world_seed + 99) >= d:
		return false
	if int(c[0]) > SEA - 1 and int(c[1]) != SWAMP:
		return false
	return true


func _grow_tree(ch: Chunk, x: int, gy: int, tb: int) -> void:
	var tr: float = PRNG.hash2(x, 4, world_seed + 98)
	if tb == DESERT:
		var th: int = 2 + int(tr * 4.0)
		for k in range(1, th + 1):
			ch.put(x, gy - k, T.CACTUS)
		if th >= 4:
			ch.put(x - 1, gy - 3, T.CACTUS)
			ch.put(x + 1, gy - 2, T.CACTUS)
	elif tb == JUNGLE:
		var th: int = 9 + int(tr * 9.0)
		for k in range(1, th + 1):
			ch.put(x, gy - k, T.JUNGLE_LOG)
		for dy in range(-3, 2):
			for dx in range(-4, 5):
				if absi(dx) == 4 and absi(dy + 1) > 1:
					continue
				if absi(dx) + absi(dy + 1) > 6:
					continue
				ch.put_if_air(x + dx, gy - th + dy, T.JUNGLE_LEAVES)
	elif tb == SAVANNA:
		var th: int = 5 + int(tr * 3.0)
		for k in range(1, th + 1):
			ch.put(x, gy - k, T.LOG)
		for dx in range(-4, 5):
			ch.put_if_air(x + dx, gy - th, T.LEAVES)
		for dx in range(-2, 3):
			ch.put_if_air(x + dx, gy - th - 1, T.LEAVES)
	elif tb == TUNDRA or (tb == MOUNTAIN and gy > 98):
		var th: int = 6 + int(tr * 5.0)
		for k in range(1, th + 1):
			ch.put(x, gy - k, T.LOG)
		var layer: int = 0
		while layer < th - 1:
			var wdt: int = mini(3, 1 + layer / 2)
			for dx in range(-wdt, wdt + 1):
				ch.put_if_air(x + dx, gy - th - 1 + layer, T.PINE_LEAVES)
			layer += 1
		ch.put_if_air(x, gy - th - 2, T.PINE_LEAVES)
	elif tb == SWAMP:
		var th: int = 4 + int(tr * 2.0)
		for k in range(1, th + 1):
			ch.put(x, gy - k, T.LOG)
		for dx in range(-3, 4):
			ch.put_if_air(x + dx, gy - th, T.JUNGLE_LEAVES)
			if absi(dx) < 3:
				ch.put_if_air(x + dx, gy - th - 1, T.JUNGLE_LEAVES)
	else:
		var variety: float = PRNG.hash2(x, 8, world_seed + 96)
		if variety < 0.3 and (tb == FOREST or tb == PLAINS):
			var th: int = 6 + int(tr * 4.0)
			for k in range(1, th + 1):
				ch.put(x, gy - k, T.BIRCH_LOG)
			for dy in range(-4, 1):
				var w: int = 1 if (dy == -4 or dy == 0) else 2
				for dx in range(-w, w + 1):
					if absi(dx) == 2 and PRNG.hash2(x + dx, gy + dy, world_seed + 95) < 0.3:
						continue
					ch.put_if_air(x + dx, gy - th + dy, T.BIRCH_LEAVES)
			ch.put_if_air(x, gy - th - 5, T.BIRCH_LEAVES)
		elif variety < 0.44 and tb == FOREST:
			var th: int = 10 + int(tr * 5.0)
			for k in range(1, th + 1):
				ch.put(x, gy - k, T.LOG)
			var layer: int = 0
			while layer < th - 4:
				var wdt: int = mini(3, 1 + layer / 3)
				if layer % 3 == 0 and layer > 0:
					wdt -= 1
				for dx in range(-wdt, wdt + 1):
					ch.put_if_air(x + dx, gy - th - 1 + layer, T.PINE_LEAVES)
				layer += 1
			ch.put_if_air(x, gy - th - 2, T.PINE_LEAVES)
		else:
			var th: int = 4 + int(tr * 4.0)
			for k in range(1, th + 1):
				ch.put(x, gy - k, T.LOG)
			for dy in range(-3, 2):
				for dx in range(-2, 3):
					if absi(dx) == 2 and (dy == -3 or dy == 1):
						continue
					ch.put_if_air(x + dx, gy - th + dy, T.LEAVES)


# ---------------------------------------------------------------------------------------------- the Umbral Realm

func u_ceil(x: int) -> int:
	return 12 + int(PRNG.fbm1(float(x) / 55.0, world_seed + 501, 3) * 30.0)


func u_floor_raw(x: int) -> int:
	return 176 + int(PRNG.fbm1(float(x) / 75.0, world_seed + 502, 3) * 86.0)


func umbral_portal_floor() -> int:
	return clampi(u_floor_raw(portal_x), 192, 226)


## Where the Hollow Warden keeps its hall: {"x", "floor", "gate"}
func citadel() -> Dictionary:
	var side: int = -1 if PRNG.hash2(77, 78, world_seed) < 0.5 else 1
	var dist: int = 380 + int(PRNG.hash2(79, 80, world_seed) * 160.0)
	var x: int = portal_x + side * dist
	if not infinite and (x < 200 or x > width - 200):
		x = portal_x - side * dist
	var fl: int = clampi(u_floor_raw(x), 190, 226)
	return {"x": x, "floor": fl, "gate": 1 if portal_x >= x else -1}


func u_floor(x: int) -> int:
	var raw: int = u_floor_raw(x)
	var c: Dictionary = citadel()
	var dc: int = absi(x - int(c["x"]))
	if dc <= 110:
		var t: float = PRNG.smooth(clampf(float(dc - 50) / 60.0, 0.0, 1.0))
		raw = roundi(lerpf(float(c["floor"]), float(raw), t))
	var d: int = absi(x - portal_x)
	if d > 44:
		return raw
	var t2: float = PRNG.smooth(clampf((float(d) - 16.0) / 28.0, 0.0, 1.0))
	return roundi(lerpf(float(umbral_portal_floor()), float(raw), t2))


func _generate_umbral(cx: int) -> Chunk:
	var hh: int = UMBRAL_H
	var ch := Chunk.new(cx, hh)
	ch.has_sky = false
	var x0: int = cx * Chunk.W
	for lx in range(Chunk.W):
		var x: int = x0 + lx
		var base: int = lx * hh
		if not infinite and (x < 0 or x >= width):
			for y in range(hh):
				ch.tiles[base + y] = T.BEDROCK
			continue
		var ceil_row: int = u_ceil(x)
		var floor_y: int = u_floor(x)
		ch.surf[lx] = floor_y
		ch.ceil_y[lx] = ceil_row
		var fx: float = float(x)
		for y in range(hh):
			var t: int = T.AIR
			var fy: float = float(y)
			if y <= 2 or y >= hh - 3:
				t = T.BEDROCK
			elif y < ceil_row:
				t = T.ASH_STONE
			elif y >= floor_y:
				var depth: int = y - floor_y
				t = T.ASH_STONE
				if depth >= 5 and is_cave(x, y, depth, floor_y, 0.0):
					t = T.LAVA if y >= UMBRAL_LAVA - 10 else T.AIR
				elif depth >= 3:
					if _v(n_ember, fx * 0.2, fy * 0.2) > 0.80 and PRNG.hash2(x, y, world_seed + 524) < 0.7:
						t = T.EMBER_ORE
					elif y > 235 and _v(n_void, fx * 0.2, fy * 0.2) > 0.895 and PRNG.hash2(x, y, world_seed + 525) < 0.7:
						t = T.VOID_ORE
					elif _v(n_obs, fx * 0.12, fy * 0.12) > 0.86:
						t = T.OBSIDIAN
					elif depth > 30 and PRNG.hash2(x, y / 4, world_seed + 526) < 0.02:
						t = T.DEEP_ROCK
			else:
				# the open cavern: floating islands, and the lava sea
				if y > ceil_row + 14 and y < floor_y - 26:
					var mid: float = float(ceil_row + floor_y) * 0.5
					var pen: float = absf(fy - mid) * 0.0035
					if _v(n_isle, fx * 0.045, fy * 0.085) > 0.735 + pen:
						t = T.ASH_STONE
				if y >= UMBRAL_LAVA and t == T.AIR:
					t = T.LAVA
			ch.tiles[base + y] = t
		# stalactites hanging from the ceiling
		var sn: float = PRNG.hash2(x, 3, world_seed + 541)
		if sn < 0.16:
			var length: int = 1 + int(PRNG.hash2(x, 4, world_seed + 541) * 7.0)
			for k in range(length):
				ch.set_local(lx, ceil_row + k, T.ASH_STONE)
			if sn < 0.012:
				ch.set_local(lx, ceil_row + length, T.GLOW_CRYSTAL)
		if floor_y > 3 and floor_y < hh - 6 and ch.get_local(lx, floor_y - 1) == T.AIR:
			var r: float = PRNG.hash2(x, 5, world_seed + 551)
			if r < 0.03:
				ch.set_local(lx, floor_y - 1, T.GLOW_CRYSTAL)
			elif r < 0.08 and absi(x - portal_x) > 20:
				ch.set_local(lx, floor_y - 1, T.SPIKES)
			elif r < 0.11:
				ch.set_local(lx, floor_y - 1, T.MUSHROOM)
	Structures.apply(self, ch, DIM_UMBRAL)
	ch.rebuild_sky(opq)
	return ch
