// World generation: where the land is, how high, and which biome (the Swift game's p06_worldgen).
// Every answer depends only on the seed and the column, so chunks can be made in any order.

const Biome = { ocean: 0, plains: 1, forest: 2, desert: 3, tundra: 4, jungle: 5, savanna: 6, swamp: 7, mountain: 8, umbral: 9 };
const BIOME_NAMES = ["Ocean", "Plains", "Forest", "Desert", "Snowy Tundra", "Jungle", "Savanna", "Swamp", "Mountains", "Umbral Realm"];
const Dimension = { overworld: 0, umbral: 1, custom0: 2, custom1: 3, custom2: 4 };
const dimCount = 5;

const GEN_H = 560;          // rows in the Overworld
const GEN_SEA = 120;        // the sea's surface row
const GEN_VERSION = 6;
const FINITE_WIDTH = 4096;
const EDGE_OCEAN = 520;
const FLAT_SURFACE = GEN_SEA - 10;
const FLAT_CRUST = 16;
const RARE_CELL = 192;
const POND_CELL = 260;
const ZONE_CLIMATE = [[0.14, 0.50], [0.50, 0.33], [0.50, 0.64], [0.88, 0.14], [0.88, 0.88], [0.88, 0.50], [0.50, 0.90]];

class WorldGen {
	constructor(seed, infinite, rareChance = 0.35, genVersion = GEN_VERSION, options = null) {
		this.seed = seed >>> 0;
		this.infinite = infinite;
		this.genVersion = genVersion;
		this.options = Object.assign({ flat: false, trees: true, structures: true, caves: false, ponds: false }, options || {});
		this.width = infinite ? 2000000000 : FINITE_WIDTH;
		this.spawnX = infinite ? 0 : FINITE_WIDTH / 2;
		this.rareChance = rareChance;
		this.zones = WorldGen.makeZones(this.seed, infinite);
		this.cols = new Map();
		this.rares = new Map();
		this.ponds = new Map();
		this.portalX = 0;
		this.portalY = 0;
		const s = this.seed;
		const hs = hash2(1, 2, s);
		const dist = infinite ? 1500 + Math.floor(hs * 1800) : 300 + Math.floor(hs * 400);
		const side = hash2(3, 4, s) < 0.5 ? -1 : 1;
		let found = this.spawnX + side * dist, ok = false;
		for (let attempt = 0; attempt < 4 && !ok; attempt++) {
			const sd = attempt % 2 === 0 ? side : -side;
			const dd = attempt < 2 ? dist : (infinite ? 2400 : 520);
			for (let step = 0; step < 400 && !ok; step++) {
				const off = ((step % 2 === 0) ? 1 : -1) * Math.floor((step + 1) / 2) * 5;
				const x = this.spawnX + sd * dd + off;
				const c = this.rawCol(x, false);
				if (c.biome !== Biome.ocean && c.biome !== Biome.swamp && c.land > 0.5 && !WorldGen.lairStatic(this.spawnX, infinite, x, 230) && Math.abs(x - this.spawnX) < 3800 && Math.abs(x - this.spawnX) > 200) {
					found = x; ok = true;
				}
			}
		}
		this.portalX = found;
		this.portalY = 350 + Math.floor(hash2(5, 6, s) * 60);
	}

	get hasTrees() { return !this.options.flat || this.options.trees; }
	get hasStructures() { return !this.options.flat || this.options.structures; }
	get passableStructures() { return this.genVersion >= 3 || this.options.flat; }

	/** Finite worlds lay biome zones out in a seeded order so every biome is always there.
	 *  climate ids: 0 tundra, 1 plains, 2 forest, 3 desert, 4 jungle, 5 savanna, 6 swamp */
	static makeZones(seed, infinite) {
		if (infinite) return [];
		const pool = [0, 3, 5, 6, 1, 2];
		const extra = [0, 3, 5, 1, 2];
		pool[5] = extra[Math.floor(hash2(7, 7, seed) * 5) % 5];
		const rng = new RNG(seed + 4242);
		for (let i = pool.length - 1; i > 0; i--) { const j = rng.int(i + 1); const t = pool[i]; pool[i] = pool[j]; pool[j] = t; }
		const z = new Array(9).fill(1);
		z[1] = 4;
		z[4] = hash2(8, 8, seed) < 0.5 ? 1 : 2;
		z[7] = 2;
		const slots = [0, 2, 3, 5, 6, 8];
		for (let k = 0; k < 6; k++) z[slots[k]] = pool[k];
		return z;
	}

	// ---- boss lairs: the bear's at spawn + 1000, the rex's at spawn - 1100 (every 4096 in endless worlds)
	static lairStatic(spawnX, infinite, x, radius) {
		const bases = [spawnX + 1000, spawnX - 1100];
		for (let i = 0; i < 2; i++) {
			const base = bases[i];
			let k = Math.round((x - base) / 4096);
			if (!infinite) k = 0;
			const cx = base + k * 4096;
			if (Math.abs(x - cx) < radius) return { kind: i, cx, k };
		}
		return null;
	}
	lairAt(x, radius = 150) { return this.hasStructures ? WorldGen.lairStatic(this.spawnX, this.infinite, x, radius) : null; }
	static lairCentersStatic(spawnX, infinite, x) {
		const out = [];
		for (const base of [spawnX + 1000, spawnX - 1100]) {
			if (!infinite) { out.push(base); continue; }
			const k = Math.round((x - base) / 4096);
			for (let kk = k - 1; kk <= k + 1; kk++) out.push(base + kk * 4096);
		}
		return out;
	}

	// ---- climate and terrain
	static zoneCoord(width, count, x) {
		const zw = (width - 2 * EDGE_OCEAN) / count;
		return (x - EDGE_OCEAN) / zw - 0.5;
	}
	climate(x) {
		const s = this.seed;
		let temp = fbm1(x / 700, s + 11, 2), humid = fbm1(x / 520, s + 12, 2);
		const zones = this.zones;
		if (this.infinite || zones.length < 2) return [0.5 + (temp - 0.5) * 1.3, 0.5 + (humid - 0.5) * 1.3];
		const t = clampD(WorldGen.zoneCoord(this.width, zones.length, x), 0, zones.length - 1 - 0.0001);
		const i = Math.floor(t), f = t - i;
		const sm = smooth(clampD((f - 0.3) / 0.4, 0, 1));
		const a = ZONE_CLIMATE[zones[i]], b = ZONE_CLIMATE[zones[i + 1]];
		return [lerpD(a[0], b[0], sm) + (temp - 0.5) * 0.30, lerpD(a[1], b[1], sm) + (humid - 0.5) * 0.30];
	}
	/** 0...1 bump marking a mountain range centred somewhere near x */
	rangeBump(x) {
		const s = this.seed;
		let best = 0;
		if (this.infinite) {
			const cellW = 1100, c0 = floorDiv(x, cellW);
			for (let c = c0 - 1; c <= c0 + 1; c++) {
				if (hash2(c, 302, s) > 0.52) continue;
				const cen = c * cellW + 200 + Math.floor(hash2(c, 303, s) * 700);
				const hw = 130 + hash2(c, 304, s) * 110;
				best = Math.max(best, smooth(clampD(1 - Math.abs(x - cen) / hw, 0, 1)));
			}
		} else {
			const zw = (this.width - 2 * EDGE_OCEAN) / 9;
			const ka = 2 + Math.floor(hash2(1, 305, s) * 2), kb = 6 + Math.floor(hash2(2, 305, s) * 2);
			const cs = [EDGE_OCEAN + zw * ka + (hash2(1, 307, s) - 0.5) * 80, EDGE_OCEAN + zw * kb + (hash2(2, 307, s) - 0.5) * 80];
			for (let k = 0; k < 2; k++) {
				const hw = 160 + hash2(k, 306, s) * 70;
				best = Math.max(best, smooth(clampD(1 - Math.abs(x - cs[k]) / hw, 0, 1)));
			}
		}
		return best;
	}
	/** The sea every world has near its spawn, on a seeded side */
	homeBasin(small) {
		const s = this.seed;
		const side = hash2(41, 42, s) < 0.5 ? -1 : 1;
		const off = 560 + Math.floor(hash2(43, 44, s) * 120);
		if (small) return { center: this.spawnX + side * off, halfW: 112 + Math.floor(hash2(45, 46, s) * 38), ramp: 90 };
		return { center: this.spawnX + side * off, halfW: 150 + Math.floor(hash2(45, 46, s) * 50), ramp: 110 };
	}
	cellBasin(c, small) {
		const s = this.seed;
		if (hash2(c, 401, s) > 0.26) return null;
		const cellW = 1600;
		let hw = 140 + Math.floor(hash2(c, 402, s) * 220);
		const cen = c * cellW + hw + 140 + Math.floor(hash2(c, 403, s) * Math.max(1, cellW - 2 * hw - 280));
		if (Math.abs(cen - this.spawnX) < hw + 900) return null;
		for (const lc of WorldGen.lairCentersStatic(this.spawnX, true, cen)) if (Math.abs(cen - lc) < hw + 330) return null;
		if (small) return { center: cen, halfW: Math.trunc(hw * 3 / 4), ramp: 105 };
		return { center: cen, halfW: hw, ramp: 140 };
	}
	/** 0...1: how strongly x lies inside an ocean basin */
	oceanBasin(x, small) {
		const weight = (b) => 1 - smooth(clampD((Math.abs(x - b.center) - b.halfW) / b.ramp, 0, 1));
		let w = weight(this.homeBasin(small));
		if (this.infinite) {
			const c0 = floorDiv(x, 1600);
			for (let c = c0 - 1; c <= c0 + 1; c++) { const b = this.cellBasin(c, small); if (b) w = Math.max(w, weight(b)); }
		}
		return w;
	}
	biomeFromClimate(temp, humid) {
		const tundra = smooth(clampD((0.31 - temp) / 0.06, 0, 1));
		const hot = smooth(clampD((temp - 0.64) / 0.06, 0, 1));
		const desert = hot * smooth(clampD((0.42 - humid) / 0.06, 0, 1));
		const jungle = hot * smooth(clampD((humid - 0.58) / 0.06, 0, 1));
		const savanna = hot * (1 - desert) * (1 - jungle);
		const swamp = smooth(clampD((humid - 0.68) / 0.06, 0, 1)) * (1 - tundra) * (1 - hot);
		let biome = humid > 0.5 ? Biome.forest : Biome.plains;
		if (tundra > 0.5) biome = Biome.tundra;
		else if (desert > 0.5) biome = Biome.desert;
		else if (jungle > 0.5) biome = Biome.jungle;
		else if (savanna > 0.5) biome = Biome.savanna;
		else if (swamp > 0.5) biome = Biome.swamp;
		return { biome, tundra, hot, desert, jungle, savanna, swamp };
	}
	/** One column, worked out afresh (see colBase for the remembered one) */
	rawCol(x, lairs = true) {
		if (this.options.flat) {
			const cl = this.climate(x);
			const b = this.biomeFromClimate(cl[0], cl[1]);
			let biome = b.biome;
			if (lairs && this.hasStructures) { const L = WorldGen.lairStatic(this.spawnX, this.infinite, x, 150); if (L && Math.abs(x - L.cx) < 120) biome = L.kind === 0 ? Biome.forest : Biome.jungle; }
			return { h: FLAT_SURFACE, biome, land: 0.7, mtn: 0, swamp: 0 };
		}
		const s = this.seed, sea = GEN_SEA, H = GEN_H, infinite = this.infinite, width = this.width;
		const smallSeas = this.genVersion >= 6;
		let land = fbm1(x / (smallSeas ? 700 : 800), s + 1, 3);
		if (!infinite) {
			const e = Math.min(x, width - 1 - x);
			if (e < EDGE_OCEAN) land *= smooth(clampD(e / EDGE_OCEAN, 0, 1));
			if (x < 0 || x >= width) land = 0;
			if (this.zones.length > 1 && e > EDGE_OCEAN * 0.55) {
				// some dry land in the middle of every biome zone
				const zc = WorldGen.zoneCoord(width, this.zones.length, x) + 0.5;
				const fr = Math.abs(zc - Math.floor(zc) - 0.5);
				const wgt = 1 - smooth(clampD((fr - 0.2) / 0.2, 0, 1));
				land = lerpD(land, Math.max(land, 0.62), wgt);
			}
		}
		const ds = Math.abs(x - this.spawnX);
		if (ds < 320) land = lerpD(land, Math.max(land, 0.64), Math.min(1, (1 - ds / 320) * 1.6));
		let lw = 0, forced = -1;
		const L = WorldGen.lairStatic(this.spawnX, infinite, x, 150);
		if (L) {
			const d = Math.abs(x - L.cx);
			lw = 1 - smooth(clampD((d - 60) / 90, 0, 1));
			land = Math.max(land, lerpD(land, 0.65, lw));
			if (d < 120) forced = L.kind === 0 ? Biome.forest : Biome.jungle;
		}
		if (smallSeas && land < 0.50 && land > 0.25) land += 0.06 * (1 - smooth(clampD(Math.abs(land - 0.40) / 0.09, 0, 1)));
		const basin = this.genVersion >= 2 ? this.oceanBasin(x, smallSeas) : 0;
		if (basin > 0) land = Math.min(land, lerpD(land, 0.17, basin));
		const mraw = Math.max(fbm1(x / 420, s + 3, 2) - 0.08, 0.56 + 0.40 * this.rangeBump(x));
		let mtn = smooth(clampD((mraw - 0.60) / 0.16, 0, 1)) * clampD((land - 0.45) / 0.1, 0, 1);
		mtn *= clampD((ds - 170) / 130, 0, 1);
		if (lw > 0) mtn *= (1 - lw);
		const cl = this.climate(x);
		const b = this.biomeFromClimate(cl[0], cl[1]);
		let swamp = b.swamp;
		if (lw > 0) swamp *= (1 - lw);
		let biome = b.biome;
		if (biome === Biome.swamp && swamp <= 0.5) biome = cl[1] > 0.5 ? Biome.forest : Biome.plains;
		if (mtn > 0.35) biome = Biome.mountain;
		if (land < 0.40) biome = Biome.ocean;
		if (forced >= 0) biome = forced;
		const amp = Math.max(0.12, 1 - 0.4 * b.tundra - 0.3 * b.desert - 0.5 * b.savanna - 0.88 * swamp + 0.15 * b.jungle);
		let h;
		if (land >= 0.40) {
			const t = clampD((land - 0.40) / 0.25, 0, 1);
			h = sea - 2 - t * 12;
			const hills = (fbm1(x / 55, s + 2, 3) - 0.5) * 2 * 15 * amp;
			const bumps = (noise1(x / 9, s + 8) - 0.5) * 3 * amp;
			h -= hills + bumps;
			const v = fbm1(x / 140, s + 5, 2);
			if (v < 0.36) h += (0.36 - v) / 0.36 * 16 * Math.min(1, amp);
			const cliff = noise1(x / 95, s + 6);
			if (cliff > 0.72) h -= 10 * smooth(clampD((cliff - 0.72) / 0.015, 0, 1));
			const peak = fbm1(x / 70, s + 4, 4);
			h -= mtn * (14 + peak * 70);
			if (swamp > 0) h = lerpD(h, sea + (noise1(x / 14, s + 9) - 0.55) * 5, swamp);
		} else {
			const d = clampD((0.40 - land) / 0.14, 0, 1);
			h = sea - 2 + d * 48 + (noise1(x / 7, s + 10) - 0.5) * 3 * d;
		}
		if (lw > 0) h = lerpD(h, sea - 10, lw);
		return { h: clampI(Math.round(h), 14, H - 80), biome, land, mtn, swamp };
	}
	colBase(x) {
		let c = this.cols.get(x);
		if (c) return c;
		c = this.rawCol(x, true);
		if (this.cols.size > 24000) this.cols.clear();
		this.cols.set(x, c);
		return c;
	}
	/** (generator 6 has no villages, so a column is its base) */
	col(x) { return this.colBase(x); }

	// ---- rare sites (ruins): where they are; what they are built of comes in a later phase
	rareSite(c) {
		if (this.rares.has(c)) return this.rares.get(c);
		const r = this.computeRareSite(c);
		if (this.rares.size > 8000) this.rares.clear();
		this.rares.set(c, r);
		return r;
	}
	computeRareSite(c) {
		if (!this.hasStructures) return null;
		const s = this.seed;
		if (hash2(c, 71, s) > this.rareChance) return null;
		const sx = c * RARE_CELL + 32 + Math.floor(hash2(c, 72, s) * (RARE_CELL - 64));
		const base = this.colBase(sx);
		if (base.biome === Biome.ocean || base.land < 0.45) return null;
		if (this.lairAt(sx, 260)) return null;
		if (Math.abs(sx - this.portalX) < 90) return null;
		if (!this.infinite && (sx < 300 || sx > this.width - 300)) return null;
		if (this.options.flat && Math.abs(sx - this.spawnX) < 48) return null;
		const r = hash2(c, 73, s);
		const kind = r < 0.17 ? 0 : r < 0.34 ? 1 : r < 0.51 ? 2 : r < 0.68 ? 3 : r < 0.84 ? 4 : 5; // house, tower, fort, camp, overgrown, bunker
		return { cell: c, x: sx, kind, seed: hashU(c, 74, s) };
	}
	rareSites(x0, x1) {
		const out = [];
		for (let c = floorDiv(x0 - 40, RARE_CELL); c <= floorDiv(x1 + 40, RARE_CELL); c++) {
			const s = this.rareSite(c);
			if (s && s.x + 30 >= x0 && s.x - 30 <= x1) out.push(s);
		}
		return out;
	}

	// ---- ponds (flat worlds)
	pondSite(c) {
		if (this.ponds.has(c)) return this.ponds.get(c);
		let p = null;
		const o = this.options, s = this.seed;
		if (o.flat && o.ponds && hash2(c, 501, s) <= 0.5) {
			const cx = c * POND_CELL + 50 + Math.floor(hash2(c, 502, s) * (POND_CELL - 100));
			const hw = 4 + Math.floor(hash2(c, 503, s) * 6);
			const depth = hash2(c, 504, s) < 0.4 ? 3 : 2;
			let ok = true;
			if (!this.infinite && (cx - hw < 40 || cx + hw > this.width - 40)) ok = false;
			if (Math.abs(cx - this.spawnX) < hw + 24 || Math.abs(cx - this.portalX) < hw + 16) ok = false;
			if (this.lairAt(cx, hw + 60)) ok = false;
			for (const r of this.rareSites(cx - hw - 40, cx + hw + 40)) if (Math.abs(r.x - cx) < hw + 40) ok = false;
			if (ok) p = { cx, halfW: hw, depth };
		}
		this.ponds.set(c, p);
		return p;
	}
	pondDepth(x) {
		if (!this.options.flat || !this.options.ponds) return 0;
		const c = floorDiv(x, POND_CELL);
		for (let cc = c - 1; cc <= c + 1; cc++) {
			const p = this.pondSite(cc);
			if (!p) continue;
			const dx = Math.abs(x - p.cx);
			if (dx > p.halfW) continue;
			const f = dx / (p.halfW + 0.5);
			return clampI(Math.ceil(p.depth * Math.sqrt(Math.max(0, 1 - f * f))), 1, p.depth);
		}
		return 0;
	}
	nearPond(x, pad) {
		if (!this.options.flat || !this.options.ponds) return false;
		const c = floorDiv(x, POND_CELL);
		for (let cc = c - 1; cc <= c + 1; cc++) { const p = this.pondSite(cc); if (p && Math.abs(x - p.cx) <= p.halfW + pad) return true; }
		return false;
	}

	// ---- caves, ores and trees (the Swift game's p07_chunk rules)
	get oreTable() { return this.genVersion >= 6 ? ORE_RULES_6 : ORE_RULES; }
	rockAt(x, y) {
		const hy = hash2(x, Math.trunc(y / 3), this.seed + 5);
		const by = y + Math.trunc((hy - 0.5) * 12);
		return by < 300 ? T.stone : by < 430 ? T.slate : T.deepRock;
	}
	isCave(x, y, depth) {
		if (depth < 5) return false;
		const s = this.seed;
		// winding tunnels follow the 0.5 contour of a smooth noise field
		if (vnoise(x * 0.013, y * 0.013, s + 25) > 0.34) {
			const a = vnoise(x * 0.045, y * 0.06, s + 21);
			const w = 0.030 + 0.05 * vnoise(x * 0.02, y * 0.02, s + 22);
			if (Math.abs(a - 0.5) < w) return true;
		}
		// big chambers
		if (depth > 26) {
			const c = vnoise(x * 0.03, y * 0.045, s + 23) * 0.65 + vnoise(x * 0.085, y * 0.1, s + 24) * 0.35;
			const bonus = Math.min(0.05, Math.max(0, y - 150) * 0.00015);
			if (c > 0.715 - bonus) return true;
		}
		// surface shafts: a few cave mouths
		if (depth < 40) {
			if (noise1(x / 18, s + 26) > 0.90 && vnoise(x * 0.2, y * 0.2, s + 27) > 0.35) return true;
		}
		return false;
	}
	oreAt(x, y, biome, regionOK) {
		const s = this.seed, rules = this.oreTable;
		for (let k = 0; k < rules.length; k++) {
			const r = rules[k];
			if (y < r.minY || y > r.maxY) continue;
			if (r.region > 0 && !regionOK[k]) continue;
			if (vnoise(x * 0.22, y * 0.22, s + r.salt) + oreBias(biome, r.tile) > r.thr) {
				if (hash2(x, y, s + 40 + r.salt) < r.p) return r.tile;
			}
		}
		return -1;
	}
	/** The chance a column starts a tree */
	treeDensity(b, h, x) {
		if (this.genVersion >= 6) {
			let d = 0;
			switch (b) {
				case Biome.forest: d = 0.22; break;
				case Biome.plains: d = 0.10; break;
				case Biome.jungle: d = 0.24; break;
				case Biome.savanna: d = 0.065; break;
				case Biome.tundra: d = 0.12; break;
				case Biome.swamp: d = 0.13; break;
				case Biome.mountain: d = h > 98 ? 0.08 : 0; break;
				case Biome.desert: return 0.035;
				default: return 0;
			}
			if (Math.abs(x - this.spawnX) < 110 && b !== Biome.mountain) d = Math.max(d, 0.22);
			return d;
		}
		switch (b) {
			case Biome.forest: return 0.14;
			case Biome.plains: return 0.04;
			case Biome.jungle: return 0.22;
			case Biome.savanna: return 0.04;
			case Biome.tundra: return 0.08;
			case Biome.swamp: return 0.10;
			case Biome.mountain: return h > 98 ? 0.05 : 0;
			case Biome.desert: return 0.035;
			default: return 0;
		}
	}
}

// Ores by depth (rows count down from the sky; the sea is at 120). The first rule that matches wins,
// so the rare ones come first.
const oreRule = (tile, minY, maxY, thr, p, salt, region = 0) => ({ tile, minY, maxY, thr, p, salt, region });
const ORE_RULES = [
	oreRule(T.amethyst, 150, 330, 0.967, 0.9, 41), oreRule(T.saltpeter, 112, 205, 0.865, 0.55, 42),
	oreRule(T.tin, 122, 265, 0.845, 0.62, 43, 0.47), oreRule(T.coal, 120, 340, 0.81, 0.66, 31),
	oreRule(T.copper, 125, 345, 0.84, 0.65, 32), oreRule(T.silver, 200, 400, 0.913, 0.6, 44),
	oreRule(T.iron, 205, 450, 0.86, 0.56, 33), oreRule(T.gold, 310, 530, 0.885, 0.58, 34),
	oreRule(T.diamond, 390, 548, 0.925, 0.55, 35), oreRule(T.mythril, 455, 548, 0.945, 0.55, 36),
];
/** Generator 6: iron from row 150, and a little more coal, copper and tin */
const ORE_RULES_6 = [
	oreRule(T.amethyst, 150, 330, 0.967, 0.9, 41), oreRule(T.saltpeter, 112, 205, 0.865, 0.55, 42),
	oreRule(T.tin, 122, 265, 0.832, 0.62, 43, 0.47), oreRule(T.coal, 120, 340, 0.79, 0.66, 31),
	oreRule(T.copper, 125, 345, 0.82, 0.65, 32), oreRule(T.silver, 200, 400, 0.913, 0.6, 44),
	oreRule(T.iron, 150, 450, 0.86, 0.56, 33), oreRule(T.gold, 310, 530, 0.885, 0.58, 34),
	oreRule(T.diamond, 390, 548, 0.925, 0.55, 35), oreRule(T.mythril, 455, 548, 0.945, 0.55, 36),
];
function oreBias(b, t) {
	const B = Biome;
	if (b === B.desert && t === T.gold) return 0.045;
	if (b === B.mountain && t === T.iron) return 0.035;
	if (b === B.mountain && t === T.mythril) return 0.03;
	if (b === B.tundra && t === T.diamond) return 0.03;
	if (b === B.jungle && t === T.copper) return 0.04;
	if (b === B.savanna && t === T.gold) return 0.03;
	if (b === B.swamp && t === T.coal) return 0.05;
	if (t === T.saltpeter) {
		if (b === B.desert) return 0.05;
		if (b === B.savanna) return 0.04;
		if (b === B.mountain) return 0.02;
		if (b === B.swamp || b === B.jungle || b === B.ocean) return -0.2;
	}
	if ((b === B.mountain || b === B.tundra) && t === T.tin) return 0.03;
	if ((b === B.mountain || b === B.tundra) && t === T.silver) return 0.02;
	return 0;
}
/** the broad field that decides where regional ores (tin) form */
const oreRegion = (x, salt, seed) => vnoise(x * 0.006, 0.37, seed + salt + 900);
