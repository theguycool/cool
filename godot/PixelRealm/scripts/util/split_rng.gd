class_name SplitRNG
extends RefCounted
## A small seeded random sequence (SplitMix64), so chest loot and structures come out the same for
## the same seed and place.

var state: int = 0


func _init(seed_value: int = 0) -> void:
	state = seed_value + PRNG.K1


func next_int() -> int:
	state += PRNG.K1
	var z: int = state
	z = (z ^ ((z >> 30) & 0x3FFFFFFFF)) * PRNG.K4
	z = (z ^ ((z >> 27) & 0x1FFFFFFFFF)) * PRNG.K5
	return z ^ ((z >> 31) & 0x1FFFFFFFF)


## A number in [0, 1)
func next_float() -> float:
	return float((next_int() >> 11) & 0x1FFFFFFFFFFFFF) / 9007199254740992.0


## A whole number in [0, n)
func below(n: int) -> int:
	return ((next_int() >> 1) & 0x3FFFFFFFFFFFFFFF) % maxi(1, n)


## A whole number in [lo, hi]
func range_i(lo: int, hi: int) -> int:
	return lo + below(hi - lo + 1)


func chance(p: float) -> bool:
	return next_float() < p
