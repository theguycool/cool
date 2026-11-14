// The land painter: one 16x16-block section of a chunk as a 256x256 picture (the Swift game's
// p24_painter). Solid ground gets a lit top edge and dark lines where it meets open space, blocks are
// mirrored from place to place where their art allows it, and leaves grow tufts into the open air.
// Pixels are 32-bit little-endian RGBA: 0xAABBGGRR.

const TPX = 16;            // art pixels a block
const TT = TPX * TPX;
const SEC_PX = chunkW * TPX;

function shade32(c, f) {
	let r = (c & 255) * f, g = ((c >>> 8) & 255) * f, b = ((c >>> 16) & 255) * f;
	if (r > 255) r = 255; if (g > 255) g = 255; if (b > 255) b = 255;
	return (0xFF000000 | (b << 16) | (g << 8) | r) >>> 0;
}
function mix32(under, over, f) {
	const ch = (s) => { const a = (under >>> s) & 255, b = (over >>> s) & 255; return Math.floor(a + (b - a) * f); };
	return (0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0)) >>> 0;
}
const lum32 = (c) => (c & 255) * 0.299 + ((c >>> 8) & 255) * 0.587 + ((c >>> 16) & 255) * 0.114;

const LeafTufts = {
	up: ["....L........L..", "...LgL.....LLgL.", "..LgggL...Lgggs.", ".LggggsL.Lggggs."],
	down: [".sggggs..sgggs..", "..sggs....sgs...", "...ss......s....", "................"],
	left: ["....", "...L", "..Lg", ".Lgg", "..sg", "...s", "....", "....", "....", "..Lg", ".Lgg", ".sgg", "..ss", "....", "....", "...."],
	right: ["....", "L...", "gL..", "ggs.", "gs..", "s...", "....", "....", "....", "gL..", "ggL.", "ggs.", "ss..", "....", "....", "...."],
	/** the four tones of a leaf block's picture, light to dark */
	tones(px, base) {
		const seen = [];
		for (let i = 0; i < TT; i++) { const c = px[base + i]; if ((c >>> 24) !== 0) { const rgb = (c | 0xFF000000) >>> 0; if (!seen.includes(rgb)) seen.push(rgb); } }
		if (!seen.length) return [0xFF4A9A6A, 0xFF3A7A4C, 0xFF305E3A, 0xFF264428];
		seen.sort((a, b) => lum32(b) - lum32(a));
		const n = seen.length;
		return [seen[0], seen[Math.min(n - 1, Math.floor(n / 3))], seen[Math.min(n - 1, Math.floor(2 * n / 3))], seen[n - 1]];
	},
	/** a leaf block's tufts: for each side (0 up, 1 down, 2 left, 3 right) two versions, as flat lists
	 *  of (place in the cell, colour) */
	make(tn) {
		const ink = { L: tn[0], g: tn[1], s: tn[2], d: tn[3] };
		const cells = (rows, ox, oy, mirror, shift) => {
			const out = [];
			const w = rows[0].length;
			rows.forEach((row, y) => { for (let x = 0; x < row.length; x++) { const c = ink[row[x]]; if (c === undefined) continue; out.push(((oy + y + shift) % TPX) * TPX + ox + (mirror ? w - 1 - x : x), c); } });
			return out;
		};
		const top = TPX - this.up.length, side = TPX - 4;
		return [
			[cells(this.up, 0, top, false, 0), cells(this.up, 0, top, true, 0)],
			[cells(this.down, 0, 0, false, 0), cells(this.down, 0, 0, true, 0)],
			[cells(this.left, side, 0, false, 0), cells(this.left, side, 0, false, TPX / 2)],
			[cells(this.right, 0, 0, false, 0), cells(this.right, 0, 0, false, TPX / 2)],
		];
	},
};

const Painter = {
	/** art of every tile by number: 256 pixels each */
	tilePx: new Uint32Array(256 * TT),
	/** 0 fully clear, 1 fully solid, 2 partly see-through */
	tileKind: new Uint8Array(256),
	/** wall pictures by wall value - 1 (1-7 the old kinds, 8 + n a wall of tile n) */
	wallPx: new Uint32Array((blockWallBase - 1 + 256) * TT),
	wallCount: blockWallBase - 1 + NT,
	tufts: new Map(),
	leafTones: new Map(),
	buf: new Uint32Array(SEC_PX * SEC_PX),

	/** reads every tile's and wall's art out of the atlas (again after the art is edited) */
	init() {
		const a = Atlas.px32, W = Atlas.w;
		for (let t = 0; t < NT; t++) {
			const ax = (t % 64) * 16, ay = Math.floor(t / 64) * 16;
			let clear = true, solid = true;
			for (let y = 0; y < TPX; y++) for (let x = 0; x < TPX; x++) {
				const c = a[(ay + y) * W + ax + x];
				this.tilePx[t * TT + y * TPX + x] = c;
				const al = c >>> 24;
				if (al !== 0) clear = false;
				if (al !== 255) solid = false;
				this.wallPx[(blockWallBase - 1 + t) * TT + y * TPX + x] = al === 0 ? 0 : ((c & 0xFF000000) | (shade32(c, 0.5) & 0xFFFFFF)) >>> 0;
			}
			this.tileKind[t] = clear ? 0 : solid ? 1 : 2;
		}
		for (let k = 0; k < DATA.atlas.walls; k++) {
			for (let y = 0; y < TPX; y++) for (let x = 0; x < TPX; x++) this.wallPx[k * TT + y * TPX + x] = a[(DATA.atlas.wallY + y) * W + k * 16 + x];
		}
		this.tufts.clear(); this.leafTones.clear();
		for (let t = 0; t < NT; t++) if (IS_LEAF[t]) { const tn = LeafTufts.tones(this.tilePx, t * TT); this.leafTones.set(t, tn); this.tufts.set(t, LeafTufts.make(tn)); }
	},

	/** Paints section `sy` (rows sy*16 ... sy*16+15) of a chunk into this.buf */
	paint(world, ch, sy) {
		const out = this.buf, W = SEC_PX, H = ch.H, y0 = sy * 16;
		out.fill(0);
		const back = world.backdrop(ch), tiles = ch.tiles, art = this.tilePx, walls = this.wallPx, kinds = this.tileKind, wc = this.wallCount;
		const lev = ch.partials > 0 ? ch.level : null;
		const left = world.chunks.get(ch.cx - 1), right = world.chunks.get(ch.cx + 1);
		const wx0 = ch.cx * chunkW;
		for (let lx = 0; lx < chunkW; lx++) {
			const colBase = lx * H, ox = lx * TPX;
			for (let ly = 0; ly < 16; ly++) {
				const y = y0 + ly;
				if (y < 0 || y >= H) continue;
				const raw = tiles[colBase + y];
				const oy = ly * TPX;
				const opaque = OPAQUE[raw];
				const wall = back[colBase + y] - 1;
				if (wall >= 0 && wall < wc && !opaque) {
					const src = wall * TT;
					for (let yy = 0; yy < TPX; yy++) { const o = (oy + yy) * W + ox, s = src + yy * TPX; for (let xx = 0; xx < TPX; xx++) out[o + xx] = walls[s + xx]; }
				}
				if (raw === 0) continue;
				if (lev && lev[colBase + y] !== 0) continue;
				const kind = kinds[raw];
				// which of the block's four pictures goes here: always the same one for a place
				let pick = 0;
				const fm = TILE_FLIP[raw];
				if (fm !== 0) {
					let hsh = (Math.imul(wx0 + lx, 374761393) + Math.imul(y, 668265263)) | 0;
					hsh = Math.imul(hsh ^ (hsh >> 13), 1274126177);
					pick = (hsh >> 16) & fm;
				}
				const fx = pick & 1, fy = pick & 2;
				const src = raw * TT;
				if (kind === 1) {
					for (let yy = 0; yy < TPX; yy++) {
						const o = (oy + yy) * W + ox, s = src + (fy ? TPX - 1 - yy : yy) * TPX;
						if (fx) for (let xx = 0; xx < TPX; xx++) out[o + xx] = art[s + TPX - 1 - xx];
						else for (let xx = 0; xx < TPX; xx++) out[o + xx] = art[s + xx];
					}
				} else if (kind === 2) {
					for (let yy = 0; yy < TPX; yy++) {
						const o = (oy + yy) * W + ox, s = src + (fy ? TPX - 1 - yy : yy) * TPX;
						for (let xx = 0; xx < TPX; xx++) {
							const c = art[s + (fx ? TPX - 1 - xx : xx)];
							const al = c >>> 24;
							if (al === 255) out[o + xx] = c;
							else if (al !== 0) { const under = out[o + xx]; out[o + xx] = (under >>> 24) === 0 ? c : mix32(under, c, al / 255); }
						}
					}
				}
				// edges where solid ground meets open space
				if (SUPPORTS[raw] && opaque) {
					const upOpaque = y > 0 ? OPAQUE[tiles[colBase + y - 1]] : 0;
					if (!upOpaque) { const o = oy * W + ox; for (let xx = 0; xx < TPX; xx++) out[o + xx] = shade32(out[o + xx], 1.12); }
					const dnOpaque = y + 1 < H ? OPAQUE[tiles[colBase + y + 1]] : 1;
					if (!dnOpaque) { const o = (oy + TPX - 1) * W + ox; for (let xx = 0; xx < TPX; xx++) out[o + xx] = shade32(out[o + xx], 0.6); }
					let lf = 1;
					if (lx > 0) lf = OPAQUE[tiles[colBase - H + y]]; else if (left && y < left.H) lf = OPAQUE[left.tiles[(chunkW - 1) * left.H + y]];
					if (!lf) for (let yy = 0; yy < TPX; yy++) { const o = (oy + yy) * W + ox; out[o] = shade32(out[o], 0.72); }
					let rt = 1;
					if (lx + 1 < chunkW) rt = OPAQUE[tiles[colBase + H + y]]; else if (right && y < right.H) rt = OPAQUE[right.tiles[y]];
					if (!rt) for (let yy = 0; yy < TPX; yy++) { const o = (oy + yy) * W + ox + TPX - 1; out[o] = shade32(out[o], 0.66); }
				}
			}
		}
		this.paintTufts(out, ch, sy, left, right);
		return out;
	},
	/** Leaves sticking out of a canopy: every open cell with a leaf block beside it gets that block's tufts */
	paintTufts(buf, ch, sy, left, right) {
		if (this.tufts.size === 0) return;
		const W = SEC_PX, H = ch.H, y0 = sy * 16;
		const at = (lx, y) => {
			if (y < 0 || y >= H) return 0;
			if (lx < 0) return left && y < left.H ? left.tiles[(chunkW - 1) * left.H + y] : 0;
			if (lx >= chunkW) return right && y < right.H ? right.tiles[y] : 0;
			return ch.tiles[lx * H + y];
		};
		for (let lx = 0; lx < chunkW; lx++) for (let ly = 0; ly < 16; ly++) {
			const y = y0 + ly;
			if (y < 0 || y >= H) continue;
			const raw = at(lx, y);
			if (OPAQUE[raw] || IS_LEAF[raw]) continue;
			for (let side = 0; side < 4; side++) {
				const nraw = side === 0 ? at(lx, y + 1) : side === 1 ? at(lx, y - 1) : side === 2 ? at(lx + 1, y) : at(lx - 1, y);
				if (!IS_LEAF[nraw]) continue;
				const tf = this.tufts.get(nraw);
				if (!tf) continue;
				const list = tf[side][hashU(ch.x0 + lx, y, 7717 + side) & 1];
				const base = ly * TPX * W + lx * TPX;
				for (let k = 0; k < list.length; k += 2) { const p = list[k]; buf[base + Math.floor(p / TPX) * W + (p % TPX)] = list[k + 1]; }
			}
		}
	},
};
