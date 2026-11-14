// The world: loaded chunks, reading and changing tiles, background walls (the Swift game's p10_world,
// p21_backdrop).

class World {
	constructor(gen) {
		this.gen = gen;
		this.dim = Dimension.overworld;
		this.H = GEN_H;
		this.chunks = new Map();
		/** changed chunks that are not loaded now, per dimension */
		this.parked = [];
		for (let d = 0; d < dimCount; d++) this.parked.push(new Map());
		// bounding box of tile edits since the light last looked
		this.editAny = false; this.editX0 = 0; this.editX1 = 0; this.editY0 = 0; this.editY1 = 0;
		this.layoutVersion = 0;
		this.version = 0;
		this.chests = new Map();
		this.cacheCX = NaN; this.cacheChunk = null;
	}
	noteEdit(x, y) {
		if (!this.editAny) { this.editAny = true; this.editX0 = x; this.editX1 = x; this.editY0 = y; this.editY1 = y; return; }
		if (x < this.editX0) this.editX0 = x;
		if (x > this.editX1) this.editX1 = x;
		if (y < this.editY0) this.editY0 = y;
		if (y > this.editY1) this.editY1 = y;
	}
	inRange(cx) { return this.gen.infinite || (cx >= 0 && cx < this.gen.width / chunkW); }
	chunk(cx) {
		if (cx === this.cacheCX) return this.cacheChunk;
		const c = this.chunks.get(cx) || null;
		this.cacheCX = cx; this.cacheChunk = c;
		return c;
	}
	isLoaded(x) { return this.chunks.has(floorDiv(x, chunkW)); }
	loadChunk(cx) {
		let c = this.chunks.get(cx);
		if (c) return c;
		if (!this.inRange(cx)) return null;
		const p = this.parked[this.dim].get(cx);
		if (p) { c = p; this.parked[this.dim].delete(cx); }
		else {
			const t0 = performance.now();
			c = generateChunk(this.gen, this.dim, cx);
			PERF.genMs = PERF.genMs === 0 ? performance.now() - t0 : PERF.genMs * 0.8 + (performance.now() - t0) * 0.2;
			PERF.chunksGenerated++;
		}
		this.chunks.set(cx, c);
		this.cacheCX = NaN;
		this.version++;
		this.noteEdit(cx * chunkW, 0);
		this.noteEdit(cx * chunkW + chunkW - 1, this.H - 1);
		// the land next door is drawn again with its edge lines toward this chunk
		const l = this.chunks.get(cx - 1), r = this.chunks.get(cx + 1);
		if (l) l.bumpRows(0, this.H - 1);
		if (r) r.bumpRows(0, this.H - 1);
		return c;
	}
	unloadChunk(cx) {
		const c = this.chunks.get(cx);
		if (!c) return;
		if (c.dirty) this.parked[this.dim].set(cx, c);
		this.chunks.delete(cx);
		this.cacheCX = NaN;
		this.version++;
		this.noteEdit(cx * chunkW, 0);
		this.noteEdit(cx * chunkW + chunkW - 1, this.H - 1);
	}
	/** Loads chunks around a column, nearest first (`budget` limits the work a call), and unloads far ones */
	stream(centerX, radius, hysteresis, budget, keep) {
		const cc = floorDiv(centerX, chunkW);
		let loaded = 0;
		for (let d = 0; d <= radius && loaded < budget; d++) {
			const a = cc - d, b = cc + d;
			if (this.inRange(a) && !this.chunks.has(a)) { this.loadChunk(a); loaded++; }
			if (d > 0 && loaded < budget && this.inRange(b) && !this.chunks.has(b)) { this.loadChunk(b); loaded++; }
		}
		if (this.chunks.size > radius * 2 + 4) {
			for (const k of Array.from(this.chunks.keys())) if (Math.abs(k - cc) > radius + hysteresis && !(keep && keep.has(k))) this.unloadChunk(k);
		}
		return loaded;
	}
	loadAround(centerX, radius) {
		const cc = floorDiv(centerX, chunkW);
		for (let d = 0; d <= radius; d++) { this.loadChunk(cc - d); this.loadChunk(cc + d); }
	}

	// ---- tiles
	virtualTile(x, y) { return (!this.gen.infinite && (x < 0 || x >= this.gen.width)) ? T.bedrock : T.stone; }
	tile(x, y) {
		if (y < 0) return T.air;
		if (y >= this.H) return T.bedrock;
		const cx = Math.floor(x / chunkW);
		const c = cx === this.cacheCX ? this.cacheChunk : this.chunk(cx);
		if (c) return c.tiles[(x - cx * chunkW) * this.H + y];
		return this.virtualTile(x, y);
	}
	solid(x, y) { return SOLID[this.tile(x, y)] === 1; }
	/** Changes a tile and gives back what was there */
	set(x, y, t) {
		if (y < 1 || y >= this.H - 1) return T.air;
		const cx = floorDiv(x, chunkW);
		const c = this.chunk(cx);
		if (!c) return T.air;
		const lx = x - cx * chunkW, i = lx * this.H + y;
		const old = c.tiles[i];
		if (old === t) return old;
		c.tiles[i] = t;
		c.dirty = true;
		c.rev++;
		this.version++;
		if (c.level && c.level[i] !== 0) { c.level[i] = 0; c.partials--; c.bumpRows(y, y); }
		if (c.built) c.built[i] = 0;
		if (c.stairs >= 0) { if (STAIR[old]) c.stairs--; if (STAIR[t]) c.stairs++; }
		// a roof can add or remove house walls up to 12 rows below it
		c.bumpRows(y - 1, y + 13);
		if ((lx === 0 || lx === chunkW - 1) && (OPAQUE[old] !== OPAQUE[t] || IS_LEAF[old] !== IS_LEAF[t])) {
			const n = this.chunks.get(lx === 0 ? cx - 1 : cx + 1);
			if (n) n.bumpRows(y - 1, y + 1);
		}
		if (OPAQUE[old] !== OPAQUE[t]) {
			const before = c.skyTop[lx];
			c.recomputeSky(lx);
			const after = c.skyTop[lx];
			if (before !== after) c.bumpRows(Math.min(before, after) - 1, Math.max(before, after) + 13);
		}
		this.noteEdit(x, y);
		return old;
	}
	/** marks a block as put there by the player (structural physics and the assembler care) */
	setBuilt(x, y, on) {
		const cx = floorDiv(x, chunkW), c = this.chunk(cx);
		if (!c || y < 0 || y >= this.H) return;
		if (!c.built) { if (!on) return; c.built = new Uint8Array(chunkW * this.H); }
		c.built[(x - cx * chunkW) * this.H + y] = on ? 1 : 0;
		c.dirty = true;
	}
	isBuilt(x, y) {
		const cx = floorDiv(x, chunkW), c = this.chunk(cx);
		return !!(c && c.built && y >= 0 && y < this.H && c.built[(x - cx * chunkW) * this.H + y]);
	}
	/** what stands on what: plants on ground, crops on farmland, saplings on soil */
	supports(below, t) {
		if (t === T.wheat1 || t === T.wheat2 || t === T.wheat3 || t === T.carrot1 || t === T.carrot2 || t === T.carrot3) return below === T.farmland;
		if (t === T.sapling) return this.isSoil(below);
		if (t === T.doorClosed || t === T.doorOpen) return SOLID[below] === 1 || below === T.doorClosed || below === T.doorOpen;
		return SUPPORTS[below] === 1 || below === T.platform;
	}
	isSoil(t) { return t === T.grass || t === T.dirt || t === T.farmland || t === T.jungleGrass || t === T.mossGrass || t === T.dryGrass || t === T.snow || t === T.mud; }
	skyTop(x) {
		const cx = floorDiv(x, chunkW), c = this.chunk(cx);
		return c ? c.skyTop[x - cx * chunkW] : 0;
	}
	isSkyExposed(x, y) { return dimHasSky(this.dim) && y < this.skyTop(x); }
	surfaceY(x) {
		for (let y = 0; y < this.H - 1; y++) { const t = this.tile(x, y); if (SOLID[t] || LIQUID[t]) return y; }
		return this.H - 1;
	}
	groundBelow(x, fromY) {
		for (let y = Math.max(0, fromY); y < this.H - 1; y++) if (SOLID[this.tile(x, y)]) return y;
		return this.H - 1;
	}

	// ---- background walls: 0 none (the sky shows), 1 dirt, 2 stone, 3 deep rock, 4 ash, 5 planks,
	// 6 brick, 7 sandstone, 8 + n a wall made of tile n
	wall(x, y) {
		const cx = floorDiv(x, chunkW), c = this.chunk(cx);
		if (!c || !c.walls || y < 0 || y >= this.H) return 0;
		return c.walls[(x - cx * chunkW) * this.H + y];
	}
	setWall(x, y, k) {
		const cx = floorDiv(x, chunkW), c = this.chunk(cx);
		if (!c || y < 1 || y >= this.H - 1) return;
		if (!c.walls) c.walls = new Uint8Array(chunkW * this.H);
		c.walls[(x - cx * chunkW) * this.H + y] = k;
		c.dirty = true; c.rev++; this.version++;
		c.bumpRows(y, y);
		this.noteEdit(x, y);
	}
	backdrop(ch) {
		if (ch.backRev === ch.rev && ch.back) return ch.back;
		const H = ch.H;
		const b = ch.back && ch.back.length === chunkW * H ? ch.back : new Uint8Array(chunkW * H);
		const over = this.dim === Dimension.overworld;
		const walls = ch.walls, tiles = ch.tiles;
		for (let lx = 0; lx < chunkW; lx++) {
			const x = ch.x0 + lx, s = ch.surf[lx], base = lx * H, top = ch.skyTop[lx];
			for (let y = 0; y < H; y++) {
				let k = 0;
				if (over) {
					if (y > s + 1) k = (y - s) < 14 ? 1 : (y < 330 ? 2 : 3);
				} else if (y > s + 1 || y < ch.ceilY[lx] - 1) k = 4;
				if (walls && walls[base + y] !== 0) k = walls[base + y];
				else if (k === 0 && y >= top && tiles[base + y] === 0) k = this.enclosedWall(x, y, ch, lx);
				b[base + y] = k;
			}
		}
		ch.back = b;
		ch.backRev = ch.rev;
		return b;
	}
	/** Air under a roof with walls on both sides (a house, a ruin) gets a wall behind it */
	enclosedWall(x, y, ch, lx) {
		let roof = T.air;
		for (let k = 1; k <= 12; k++) {
			const t = ch.get(lx, y - k);
			if (OPAQUE[t] && SOLID[t]) {
				if (t === T.planks || t === T.brick || t === T.crackedBrick || t === T.mossBrick || t === T.sandstone || t === T.hay) roof = t;
				else return 0;
				break;
			}
		}
		if (roof === T.air) return 0;
		let leftOK = false;
		for (let d = 1; d <= 12; d++) { const t = this.tile(x - d, y); if (SOLID[t] || t === T.glass) { leftOK = true; break; } }
		if (!leftOK) return 0;
		for (let d = 1; d <= 12; d++) { const t = this.tile(x + d, y); if (SOLID[t] || t === T.glass) return wallForRoof(roof); }
		return 0;
	}
}
function wallForRoof(t) {
	if (t === T.brick || t === T.crackedBrick || t === T.mossBrick || t === T.stone || t === T.obsidian || t === T.portalFrame) return 6;
	if (t === T.sandstone) return 7;
	if (t === T.ashStone) return 4;
	return 5;
}
const blockWallBase = 8;

/** run-length packing of a tile array for saves: pairs of (count, value) */
function rle(a) {
	const out = [];
	for (let i = 0; i < a.length;) {
		const v = a[i];
		let n = 1;
		while (i + n < a.length && a[i + n] === v && n < 255) n++;
		out.push(n, v);
		i += n;
	}
	return Uint8Array.from(out);
}
function unrle(a, count) {
	const out = new Uint8Array(count);
	let o = 0;
	for (let i = 0; i + 1 < a.length && o < count; i += 2) { const n = a[i], v = a[i + 1]; out.fill(v, o, Math.min(count, o + n)); o += n; }
	return out;
}

const PERF = { genMs: 0, chunksGenerated: 0, lightMs: 0, lightFull: 0, lightDyn: 0, renderMs: 0, tickMs: 0, sections: 0 };
