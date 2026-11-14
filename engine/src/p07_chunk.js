// Chunks: 16 columns of the world, and how the Overworld's are made (the Swift game's p07_chunk).

const chunkW = 16;
let chunkSerial = 0;

class Chunk {
	constructor(cx, H) {
		this.serial = ++chunkSerial;
		this.cx = cx;
		this.H = H;
		this.x0 = cx * chunkW;
		/** tiles by column: tiles[lx * H + y] */
		this.tiles = new Uint8Array(chunkW * H);
		/** per column: the first row sky light does not reach */
		this.skyTop = new Int32Array(chunkW);
		this.surf = new Int32Array(chunkW);
		this.ceilY = new Int32Array(chunkW);
		this.dirty = false;
		this.hasSky = true;
		this.rev = 0;
		/** background walls the player or a structure put up (empty until the first) */
		this.walls = null;
		this.back = null;
		this.backRev = -1;
		/** which blocks were put there, not generated */
		this.built = null;
		this.stairs = -1;
		/** how full each part-full liquid cell is (1...254; 0: a whole block or no liquid) */
		this.level = null;
		this.partials = 0;
		this.wires = null;
		this.wireCount = 0;
		/** change counter per 16-row section (only changed sections are painted again) */
		this.secRev = new Int32Array(Math.floor(H / 16) + 1);
	}
	bumpRows(y0, y1) {
		const n = this.secRev.length;
		const e = Math.min(n - 1, Math.floor(Math.max(0, y1) / 16));
		for (let s = Math.floor(Math.max(0, y0) / 16); s <= e; s++) this.secRev[s]++;
	}
	get(lx, y) { return y < 0 ? T.air : y >= this.H ? T.bedrock : this.tiles[lx * this.H + y]; }
	setLocal(lx, y, t) { if (lx >= 0 && lx < chunkW && y >= 0 && y < this.H) this.tiles[lx * this.H + y] = t; }
	/** write by world column, used by the builders; anything outside this chunk is ignored */
	put(x, y, t) {
		const lx = x - this.x0;
		if (lx < 0 || lx >= chunkW || y < 1 || y >= this.H - 1) return;
		this.tiles[lx * this.H + y] = t;
	}
	putIfAir(x, y, t) {
		const lx = x - this.x0;
		if (lx < 0 || lx >= chunkW || y < 1 || y >= this.H - 1) return;
		if (this.tiles[lx * this.H + y] === T.air) this.tiles[lx * this.H + y] = t;
	}
	at(x, y) {
		const lx = x - this.x0;
		if (lx < 0 || lx >= chunkW || y < 0 || y >= this.H) return T.air;
		return this.tiles[lx * this.H + y];
	}
	fill(xa, ya, xb, yb, t) {
		for (let x = xa; x <= xb; x++) { if (x < this.x0 || x >= this.x0 + chunkW) continue; for (let y = ya; y <= yb; y++) this.put(x, y, t); }
	}
	putWall(x, y, k) {
		const lx = x - this.x0;
		if (lx < 0 || lx >= chunkW || y < 1 || y >= this.H - 1) return;
		if (!this.walls) this.walls = new Uint8Array(chunkW * this.H);
		this.walls[lx * this.H + y] = k;
	}
	fillWall(xa, ya, xb, yb, k) { for (let x = xa; x <= xb; x++) for (let y = ya; y <= yb; y++) this.putWall(x, y, k); }
	rebuildSky() { for (let lx = 0; lx < chunkW; lx++) this.recomputeSky(lx); }
	recomputeSky(lx) {
		if (!this.hasSky) { this.skyTop[lx] = this.H; return; }
		const base = lx * this.H;
		let y = 0;
		while (y < this.H && !OPAQUE[this.tiles[base + y]]) y++;
		this.skyTop[lx] = y;
	}
}

/** Fills out[y - y0] with vnoise(fx, y * fyScale, seed) for y in y0...y1, hashing each lattice row once */
function columnNoise(seed, fx, fyScale, y0, y1, out) {
	if (y1 < y0) return;
	const fx0 = Math.floor(fx);
	const fu = fx - fx0;
	const u = fu * fu * (3 - 2 * fu);
	let rowI = -1e9, a = 0, b = 0, c = 0, d = 0, top = 0, bot = 0;
	for (let y = y0, k = 0; y <= y1; y++, k++) {
		const fy = y * fyScale;
		const yi = Math.floor(fy);
		if (yi !== rowI) {
			if (yi === rowI + 1) { a = c; b = d; } else { a = hash2(fx0, yi, seed); b = hash2(fx0 + 1, yi, seed); }
			c = hash2(fx0, yi + 1, seed); d = hash2(fx0 + 1, yi + 1, seed);
			top = a + (b - a) * u; bot = c + (d - c) * u;
			rowI = yi;
		}
		const f = fy - yi;
		out[k] = top + (bot - top) * (f * f * (3 - 2 * f));
	}
}

/** Cave, ore and rock sampling a column at a time: startColumn works out every noise field the column
 *  needs, and isCave, oreAt and rockAt then only read them (the same answers as WorldGen's own) */
class GenSampler {
	constructor(g) {
		this.g = g;
		this.seed = g.seed;
		this.H = GEN_H;
		this.rules = g.oreTable;
		const H = this.H, n = this.rules.length;
		this.region = new Float64Array(H); this.tunnel = new Float64Array(H); this.width = new Float64Array(H);
		this.cham = new Float64Array(H); this.shaft = new Float64Array(H); this.scratch = new Float64Array(H);
		this.ores = []; for (let k = 0; k < n; k++) this.ores.push(new Float64Array(H));
		this.oreLo = new Int32Array(n); this.oreHi = new Int32Array(n); this.oreThr = new Float64Array(n);
		this.top = 0; this.chamTop = 0; this.shaftN = 0; this.biasBiome = -1; this.rockY3 = -1e9; this.rockH = 0;
	}
	startColumn(cx, h, caves) {
		this.rockY3 = -1e9;
		const H = this.H, s = this.seed;
		if (caves) {
			this.shaftN = noise1(cx / 18, s + 26);
			this.top = h + 5; this.chamTop = h + 27;
			const y1 = H - 1;
			columnNoise(s + 25, cx * 0.013, 0.013, this.top, y1, this.region);
			columnNoise(s + 21, cx * 0.045, 0.06, this.top, y1, this.tunnel);
			columnNoise(s + 22, cx * 0.02, 0.02, this.top, y1, this.width);
			if (this.chamTop <= y1) {
				columnNoise(s + 23, cx * 0.03, 0.045, this.chamTop, y1, this.cham);
				columnNoise(s + 24, cx * 0.085, 0.1, this.chamTop, y1, this.scratch);
				for (let k = 0, n = y1 - this.chamTop + 1; k < n; k++) this.cham[k] = this.cham[k] * 0.65 + this.scratch[k] * 0.35;
			}
			if (this.shaftN > 0.90) columnNoise(s + 27, cx * 0.2, 0.2, this.top, Math.min(y1, h + 39), this.shaft);
		}
		for (let k = 0; k < this.rules.length; k++) {
			const r = this.rules[k];
			const lo = Math.max(r.minY, h + 9);
			let hi = Math.min(r.maxY, H - 6);
			if (r.region > 0 && oreRegion(cx, r.salt, s) < r.region) hi = lo - 1;
			this.oreLo[k] = lo; this.oreHi[k] = hi;
			if (hi >= lo) columnNoise(s + r.salt, cx * 0.22, 0.22, lo, hi, this.ores[k]);
		}
	}
	isCave(x, y, depth) {
		if (depth < 5 || y < this.top) return false;
		const i = y - this.top;
		if (this.region[i] > 0.34) {
			if (Math.abs(this.tunnel[i] - 0.5) < 0.030 + 0.05 * this.width[i]) return true;
		}
		if (depth > 26 && y >= this.chamTop) {
			const bonus = Math.min(0.05, Math.max(0, y - 150) * 0.00015);
			if (this.cham[y - this.chamTop] > 0.715 - bonus) return true;
		}
		if (depth < 40 && this.shaftN > 0.90 && this.shaft[i] > 0.35) return true;
		return false;
	}
	oreAt(x, y, biome) {
		const rules = this.rules;
		if (biome !== this.biasBiome) {
			this.biasBiome = biome;
			for (let k = 0; k < rules.length; k++) this.oreThr[k] = rules[k].thr - oreBias(biome, rules[k].tile);
		}
		for (let k = 0; k < rules.length; k++) {
			const lo = this.oreLo[k];
			if (y >= lo && y <= this.oreHi[k] && this.ores[k][y - lo] > this.oreThr[k]) {
				if (hash2(x, y, this.seed + 40 + rules[k].salt) < rules[k].p) return rules[k].tile;
			}
		}
		return -1;
	}
	rockAt(x, y) {
		const y3 = Math.trunc(y / 3);
		if (y3 !== this.rockY3) { this.rockY3 = y3; this.rockH = hash2(x, y3, this.seed + 5); }
		const by = y + Math.trunc((this.rockH - 0.5) * 12);
		return by < 300 ? T.stone : by < 430 ? T.slate : T.deepRock;
	}
}

/** One column of a standard world: the biome's surface and topsoil, sea water above low ground, rock
 *  layers, caves (with underground lakes and deep lava) and ores */
function fillStandardColumn(ch, g, samp, lx, x, h, sb, biome) {
	const H = GEN_H, sea = GEN_SEA, base = lx * H, B = Biome, tiles = ch.tiles, s = g.seed;
	let topT = T.grass, fillT = T.dirt, fillD = 5;
	switch (sb) {
		case B.desert: topT = T.sand; fillT = T.sand; fillD = 9; break;
		case B.tundra: topT = T.snow; fillT = T.snow; fillD = 3; break;
		case B.jungle: topT = T.jungleGrass; fillT = T.mud; fillD = 7; break;
		case B.savanna: topT = T.dryGrass; fillD = 4; break;
		case B.swamp: topT = T.mossGrass; fillT = T.mud; fillD = 6; break;
		case B.ocean: topT = T.sand; fillT = T.sand; fillD = 5; break;
		case B.mountain:
			if (h <= 72) { topT = T.snow; fillT = T.snow; fillD = 3; }
			else if (h <= 100) { topT = T.stone; fillT = T.stone; fillD = 4; }
			break;
	}
	if (sb !== B.ocean && sb !== B.swamp && sb !== B.desert && h >= sea - 1 && h <= sea + 2) { topT = T.sand; fillT = T.sand; fillD = 4; }
	if (h > sea) for (let y = sea; y < h; y++) tiles[base + y] = (sb === B.tundra && y === sea) ? T.ice : T.water;
	const lakeCol = Math.trunc(x / 60);
	for (let y = h; y < H; y++) {
		const depth = y - h;
		let t;
		if (y >= H - 1) t = T.bedrock;
		else if (y >= H - 5 && hash2(x, y, s + 3) < (y - (H - 6)) * 0.22) t = T.bedrock;
		else if (depth === 0) t = topT;
		else if (depth < fillD) t = (sb === B.tundra && depth >= 3) ? T.dirt : fillT;
		else if (sb === B.desert && depth < 24) t = T.sandstone;
		else t = samp.rockAt(x, y);
		if (depth >= 4 && y < H - 5) {
			if (samp.isCave(x, y, depth)) {
				if (y >= 500) t = T.lava;
				else if (y > 200 && y < 430 && hash2(lakeCol, Math.trunc(y / 48), s + 28) < 0.28 && (y % 48) > 28) t = T.water;
				else t = T.air;
			} else if (depth > 8 && t !== T.sand && t !== T.snow) {
				const o = samp.oreAt(x, y, biome);
				if (o >= 0) t = o;
			}
		}
		tiles[base + y] = t;
	}
}

/** One column of a flat world: the same layers everywhere */
function fillFlatColumn(ch, g, samp, lx, x, h, surfBiome, biome) {
	const H = GEN_H, B = Biome, base = lx * H, s = g.seed;
	let topT = T.grass, fillT = T.dirt;
	switch (surfBiome) {
		case B.desert: topT = T.sand; fillT = T.sand; break;
		case B.tundra: topT = T.snow; break;
		case B.jungle: topT = T.jungleGrass; fillT = T.mud; break;
		case B.savanna: topT = T.dryGrass; break;
		case B.swamp: topT = T.mossGrass; fillT = T.mud; break;
	}
	const pond = g.pondDepth(x);
	if (pond === 0 && g.nearPond(x, 1)) topT = T.sand;
	const caves = g.options.caves;
	for (let y = h; y < H; y++) {
		const depth = y - h;
		let t;
		if (y >= H - 3) t = T.bedrock;
		else if (depth < pond) t = (surfBiome === B.tundra && depth === 0) ? T.ice : T.water;
		else if (depth === pond && pond > 0) t = T.sand;
		else if (depth === 0) t = topT;
		else if (depth <= 4) t = fillT;
		else if (y < 300) t = T.stone;
		else if (y < 430) t = T.slate;
		else t = T.deepRock;
		if (y < H - 5 && depth >= FLAT_CRUST && caves && samp.isCave(x, y, depth)) {
			if (y >= 500) t = T.lava;
			else if (y > 200 && y < 430 && hash2(Math.trunc(x / 60), Math.trunc(y / 48), s + 28) < 0.28 && (y % 48) > 28) t = T.water;
			else t = T.air;
		} else if (depth > 8 && y < H - 5) {
			const o = samp.oreAt(x, y, biome);
			if (o >= 0) t = o;
		}
		ch.tiles[base + y] = t;
	}
}

let genSampler = null;
function generateOverworldChunk(g, cx) {
	const H = GEN_H, sea = GEN_SEA, B = Biome, s = g.seed;
	const ch = new Chunk(cx, H);
	const x0 = cx * chunkW, m = 12;
	const cols = [];
	for (let x = x0 - m; x < x0 + chunkW + m; x++) cols.push(g.col(x));
	const colAt = (x) => cols[x - (x0 - m)];
	const surfBiome = [];
	if (!genSampler || genSampler.g !== g) genSampler = new GenSampler(g);
	const samp = genSampler;
	const caves = !g.options.flat || g.options.caves;
	for (let lx = 0; lx < chunkW; lx++) {
		const x = x0 + lx, c = colAt(x);
		samp.startColumn(x, c.h, caves);
		const jit = Math.trunc((hash2(x, 1, s + 61) - 0.5) * 10);
		let sb = colAt(x + jit).biome;
		if (c.biome === B.ocean) sb = B.ocean; else if (sb === B.ocean) sb = c.biome;
		surfBiome.push(sb);
		const base = lx * H;
		if (!g.infinite && (x < 0 || x >= g.width)) { ch.tiles.fill(T.bedrock, base, base + H); continue; }
		const h = c.h;
		ch.surf[lx] = h;
		if (g.options.flat) fillFlatColumn(ch, g, samp, lx, x, h, sb, c.biome);
		else fillStandardColumn(ch, g, samp, lx, x, h, sb, c.biome);
		// mushrooms on cave floors, cobwebs under cave roofs
		for (let y = h + 8; y < H - 6; y++) {
			if (ch.tiles[base + y] !== T.air) continue;
			const below = ch.tiles[base + y + 1], above = ch.tiles[base + y - 1];
			if (SOLID[below] && below !== T.bedrock && y > 190 && y < 470 && hash2(x, y, s + 81) < 0.025) ch.tiles[base + y] = T.mushroom;
			else if (SOLID[above] && hash2(x, y, s + 82) < 0.012) ch.tiles[base + y] = T.cobweb;
		}
	}
	// surface plants and trees
	const rares = g.rareSites(x0 - 30, x0 + chunkW + 30);
	const blocked = (x) => {
		for (const r of rares) if (Math.abs(x - r.x) < 16) return true;
		if (g.lairAt(x, 110)) return true;
		if (g.options.flat && (Math.abs(x - g.spawnX) < 5 || g.nearPond(x, 2))) return true;
		return genBlockedExtra(g, x);
	};
	const isTree = (x) => {
		const c = colAt(x);
		const d = g.treeDensity(c.biome, c.h, x);
		if (d <= 0) return false;
		if (hash2(x, 3, s + 99) >= d) return false;
		if (c.h > sea - 1 && c.biome !== B.swamp) return false;
		return true;
	};
	for (let lx = -6; lx < chunkW + 6 && g.hasTrees; lx++) {
		const x = x0 + lx;
		if (!g.infinite && (x < 4 || x > g.width - 5)) continue;
		const c = colAt(x);
		if (c.biome === B.ocean || blocked(x)) continue;
		const inside = lx >= 0 && lx < chunkW;
		const sb = inside ? surfBiome[lx] : c.biome;
		if (inside) {
			const r = hash2(x, 5, s + 90);
			const gy = c.h - 1;
			const surf = ch.get(lx, c.h);
			if (gy > 0 && ch.get(lx, gy) === T.air && c.h <= sea) {
				if ((sb === B.plains || sb === B.forest) && surf === T.grass) {
					if (r < 0.20) ch.setLocal(lx, gy, T.tallGrass); else if (r < 0.235) ch.setLocal(lx, gy, T.flowerR); else if (r < 0.27) ch.setLocal(lx, gy, T.flowerY);
				} else if (sb === B.jungle && surf === T.jungleGrass) {
					if (r < 0.30) ch.setLocal(lx, gy, T.tallGrass); else if (r < 0.34) ch.setLocal(lx, gy, T.flowerR);
				} else if (sb === B.savanna && surf === T.dryGrass) {
					if (r < 0.14) ch.setLocal(lx, gy, T.tallGrass);
				} else if (sb === B.swamp && surf === T.mossGrass) {
					if (r < 0.14) ch.setLocal(lx, gy, T.reed); else if (r < 0.17) ch.setLocal(lx, gy, T.mushroom);
				} else if (sb === B.desert && surf === T.sand) {
					if (r < 0.03) ch.setLocal(lx, gy, T.deadBush);
				}
			}
		}
		// trees: rooted at x, drawn clipped into this chunk; three columns apart (jungle trees four)
		if (!isTree(x)) continue;
		if (isTree(x - 1) || isTree(x - 2)) continue;
		if ((g.genVersion < 6 || c.biome === B.jungle) && isTree(x - 3)) continue;
		if (Math.abs(colAt(x - 1).h - colAt(x + 1).h) > 1) continue;
		const tr = hash2(x, 4, s + 98);
		const gy = c.h, tb = c.biome;
		if (tb === B.desert) {
			const th = 2 + Math.floor(tr * 4);
			for (let k = 1; k <= th; k++) ch.put(x, gy - k, T.cactus);
			if (th >= 4) { ch.put(x - 1, gy - 3, T.cactus); ch.put(x + 1, gy - 2, T.cactus); }
		} else if (tb === B.jungle) {
			const th = 9 + Math.floor(tr * 9);
			for (let k = 1; k <= th; k++) ch.put(x, gy - k, T.jungleLog);
			for (let dy = -3; dy <= 1; dy++) for (let dx = -4; dx <= 4; dx++) {
				if (Math.abs(dx) === 4 && Math.abs(dy + 1) > 1) continue;
				if (Math.abs(dx) + Math.abs(dy + 1) > 6) continue;
				ch.putIfAir(x + dx, gy - th + dy, T.jungleLeaves);
			}
		} else if (tb === B.savanna) {
			const th = 5 + Math.floor(tr * 3);
			for (let k = 1; k <= th; k++) ch.put(x, gy - k, T.log);
			for (let dx = -4; dx <= 4; dx++) ch.putIfAir(x + dx, gy - th, T.leaves);
			for (let dx = -2; dx <= 2; dx++) ch.putIfAir(x + dx, gy - th - 1, T.leaves);
		} else if (tb === B.tundra || (tb === B.mountain && c.h > 98)) {
			const needles = g.genVersion >= 3 ? T.pineLeaves : T.leaves;
			const th = 6 + Math.floor(tr * 5);
			for (let k = 1; k <= th; k++) ch.put(x, gy - k, T.log);
			for (let layer = 0; layer < th - 1; layer++) {
				const wdt = Math.min(3, 1 + Math.floor(layer / 2));
				for (let dx = -wdt; dx <= wdt; dx++) ch.putIfAir(x + dx, gy - th - 1 + layer, needles);
			}
			ch.putIfAir(x, gy - th - 2, needles);
		} else if (tb === B.swamp) {
			const th = 4 + Math.floor(tr * 2);
			for (let k = 1; k <= th; k++) ch.put(x, gy - k, T.log);
			for (let dx = -3; dx <= 3; dx++) { ch.putIfAir(x + dx, gy - th, T.jungleLeaves); if (Math.abs(dx) < 3) ch.putIfAir(x + dx, gy - th - 1, T.jungleLeaves); }
		} else {
			// birches in forests and plains, tall pines in forests, oaks everywhere
			const variety = g.genVersion >= 3 ? hash2(x, 8, s + 96) : 1;
			if (variety < 0.3 && (tb === B.forest || tb === B.plains)) {
				const th = 6 + Math.floor(tr * 4);
				for (let k = 1; k <= th; k++) ch.put(x, gy - k, T.birchLog);
				for (let dy = -4; dy <= 0; dy++) {
					const w = (dy === -4 || dy === 0) ? 1 : 2;
					for (let dx = -w; dx <= w; dx++) {
						if (Math.abs(dx) === 2 && hash2(x + dx, gy + dy, s + 95) < 0.3) continue;
						ch.putIfAir(x + dx, gy - th + dy, T.birchLeaves);
					}
				}
				ch.putIfAir(x, gy - th - 5, T.birchLeaves);
			} else if (variety < 0.44 && tb === B.forest) {
				const th = 10 + Math.floor(tr * 5);
				for (let k = 1; k <= th; k++) ch.put(x, gy - k, T.log);
				for (let layer = 0; layer < th - 4; layer++) {
					let wdt = Math.min(3, 1 + Math.floor(layer / 3));
					if (layer % 3 === 0 && layer > 0) wdt -= 1;
					for (let dx = -wdt; dx <= wdt; dx++) ch.putIfAir(x + dx, gy - th - 1 + layer, T.pineLeaves);
				}
				ch.putIfAir(x, gy - th - 2, T.pineLeaves);
			} else {
				const th = 4 + Math.floor(tr * 4);
				for (let k = 1; k <= th; k++) ch.put(x, gy - k, T.log);
				for (let dy = -3; dy <= 1; dy++) for (let dx = -2; dx <= 2; dx++) {
					if (Math.abs(dx) === 2 && (dy === -3 || dy === 1)) continue;
					ch.putIfAir(x + dx, gy - th + dy, T.leaves);
				}
			}
		}
	}
	// palms on warm beaches
	for (let lx = 0; lx < chunkW && g.hasTrees; lx++) {
		const x = x0 + lx, c = colAt(x);
		if (c.biome === B.ocean || c.h < sea - 3 || c.h > sea + 1) continue;
		if (ch.get(lx, c.h) !== T.sand || ch.get(lx, c.h - 1) !== T.air) continue;
		if (hash2(x, 6, s + 97) > 0.035) continue;
		const th = 6 + Math.floor(hash2(x, 7, s + 97) * 4);
		for (let k = 1; k <= th; k++) ch.put(x + (k > th - 3 ? 1 : 0), c.h - k, T.palmLog);
		for (let dx = -3; dx <= 4; dx++) ch.putIfAir(x + 1 + dx, c.h - th - (Math.abs(dx) > 2 ? 0 : 1), T.jungleLeaves);
	}
	genStructures(g, ch, colAt, blocked);
	ch.rebuildSky();
	return ch;
}

// Landmarks, ruins, grottos, mines and the portal chamber are added by a later phase; until then these
// do nothing.
function genBlockedExtra(g, x) { return false; }
function genStructures(g, ch, colAt, blocked) {}

function generateChunk(g, dim, cx) {
	return generateOverworldChunk(g, cx);
}
const dimHeight = (dim) => GEN_H;
const dimHasSky = (dim) => dim === Dimension.overworld;
