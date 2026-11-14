// Utilities: numbers, hashing, noise and colours (the Swift game's p01_util).
// Hashes are 32-bit here (the Swift game's are 64-bit), so the same seed gives a different but
// equally made world.

const clampD = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
const clampI = clampD;
const lerpD = (a, b, t) => a + (b - a) * t;
const floorDiv = (a, b) => Math.floor(a / b);
const smooth = (f) => f * f * (3 - 2 * f);
const perfNow = () => performance.now() / 1000;

function hashU(x, y, s) {
	let h = Math.imul(x | 0, 0x9E3779B1) ^ Math.imul(y | 0, 0x85EBCA77) ^ Math.imul(s | 0, 0xC2B2AE3D);
	h ^= h >>> 15; h = Math.imul(h, 0x2C1B3C6D);
	h ^= h >>> 12; h = Math.imul(h, 0x297A2D39);
	h ^= h >>> 15;
	return h >>> 0;
}
function hash2(x, y, s) { return hashU(x, y, s) / 4294967296; }

/** a small seeded random number generator (the Swift game's RNG) */
class RNG {
	constructor(seed) { this.s = (seed + 0x9E3779B9) >>> 0; }
	next() {
		this.s = (this.s + 0x6D2B79F5) >>> 0;
		let z = this.s;
		z = Math.imul(z ^ (z >>> 15), z | 1);
		z ^= z + Math.imul(z ^ (z >>> 7), z | 61);
		return (z ^ (z >>> 14)) >>> 0;
	}
	double() { return this.next() / 4294967296; }
	int(n) { return this.next() % Math.max(1, n); }
}
const rand = (lo = 0, hi = 1) => lo + Math.random() * (hi - lo);
const randInt = (lo, hi) => lo + Math.floor(Math.random() * (hi - lo + 1));

function noise1(x, s) {
	const fl = Math.floor(x);
	const u = smooth(x - fl);
	const a = hash2(fl, 7, s), b = hash2(fl + 1, 7, s);
	return a + (b - a) * u;
}
function fbm1(x, s, oct) {
	let sum = 0, amp = 1, freq = 1, norm = 0;
	for (let i = 0; i < oct; i++) { sum += noise1(x * freq, s + i * 101) * amp; norm += amp; amp *= 0.5; freq *= 2; }
	return sum / norm;
}
function vnoise(x, y, s) {
	const fx0 = Math.floor(x), fy0 = Math.floor(y);
	const u = smooth(x - fx0), v = smooth(y - fy0);
	const a = hash2(fx0, fy0, s), b = hash2(fx0 + 1, fy0, s), c = hash2(fx0, fy0 + 1, s), d = hash2(fx0 + 1, fy0 + 1, s);
	const top = a + (b - a) * u, bot = c + (d - c) * u;
	return top + (bot - top) * v;
}

// colours are 0xRRGGBB numbers, as in the Swift game
function mixRGB(a, b, t) {
	const tt = clampD(t, 0, 1);
	const ch = (s) => { const ca = (a >> s) & 255, cb = (b >> s) & 255; return Math.floor(ca + (cb - ca) * tt); };
	return (ch(16) << 16) | (ch(8) << 8) | ch(0);
}
function shadeRGB(c, f) {
	const ch = (s) => Math.floor(clampD(((c >> s) & 255) * f, 0, 255));
	return (ch(16) << 16) | (ch(8) << 8) | ch(0);
}
const gradeSat = 0.42, gradeVal = 0.20;
/** the game's colour grade: strong colours lose some saturation and brightness */
function artGrade(c) {
	const r = ((c >> 16) & 255) / 255, g = ((c >> 8) & 255) / 255, b = (c & 255) / 255;
	const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
	if (mx <= 0 || mx === mn) return c & 0xFFFFFF;
	const s = (mx - mn) / mx;
	const s2 = s * (1 - gradeSat * s);
	const v2 = mx * (1 - gradeVal * mx * s);
	const lo2 = v2 * (1 - s2);
	const ch = (x) => { const t = (x - mn) / (mx - mn); return Math.floor(clampD(Math.round((lo2 + (v2 - lo2) * t) * 255), 0, 255)); };
	return (ch(r) << 16) | (ch(g) << 8) | ch(b);
}
const hexCss = (c, a = 1) => "rgba(" + ((c >> 16) & 255) + "," + ((c >> 8) & 255) + "," + (c & 255) + "," + a + ")";

/** a mod's rules of the game; the defaults until mods are ported */
const RULES = { day: 12, gravity: 1, health: 20, hunger: 1, healing: 1, hurt: 1, hit: 1, mining: 1, monsters: 1, animals: 1, falls: 1, walk: 1, jump: 1, nights: 1, deathDrop: 0 };
const rule = (k) => RULES[k];
