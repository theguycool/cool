class_name PRNG
## Deterministic hashing and noise for world generation. These are the Swift game's own functions
## (64-bit integer hashing, smoothed value noise along a line, fractal sums), written for GDScript's
## signed 64-bit integers: multiplications wrap, and right shifts are masked to act as unsigned ones.

const K1 := -7046029254386353131
const K2 := -4417276706812531889
const K3 := 1609587929392839161
const K4 := -4658895280553007687
const K5 := -7723592293110705685


static func hash_u(x: int, y: int, s: int) -> int:
	var h: int = x * K1
	h ^= y * K2
	h ^= s * K3
	h ^= (h >> 29) & 0x7FFFFFFFF
	h *= K4
	h ^= (h >> 32) & 0xFFFFFFFF
	h *= K5
	h ^= (h >> 29) & 0x7FFFFFFFF
	return h


## A number in [0, 1) fixed by (x, y, s)
static func hash2(x: int, y: int, s: int) -> float:
	return float((hash_u(x, y, s) >> 40) & 0xFFFFFF) / 16777216.0


static func smooth(f: float) -> float:
	return f * f * (3.0 - 2.0 * f)


## Smooth value noise along a line, in [0, 1)
static func noise1(x: float, s: int) -> float:
	var fl: float = floorf(x)
	var xi: int = int(fl)
	var u: float = smooth(x - fl)
	var a: float = hash2(xi, 7, s)
	var b: float = hash2(xi + 1, 7, s)
	return a + (b - a) * u


## Several octaves of noise1, normalised to [0, 1)
static func fbm1(x: float, s: int, oct: int) -> float:
	var total: float = 0.0
	var amp: float = 1.0
	var freq: float = 1.0
	var norm: float = 0.0
	for i in range(oct):
		total += noise1(x * freq, s + i * 101) * amp
		norm += amp
		amp *= 0.5
		freq *= 2.0
	return total / norm


## Floor division for negative coordinates (GDScript's / truncates toward zero)
static func fdiv(a: int, b: int) -> int:
	return (a - posmod(a, b)) / b
