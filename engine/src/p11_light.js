// Lighting: sky light and block light flooded over the window on screen (the Swift game's p11_light).

/** Brightness per light level (gamma 0.85, so torchlight reaches further into caves) */
const lightLUT = [];
for (let i = 0; i <= 15; i++) lightLUT.push(Math.pow(i / 15, 0.85));

class LightMap {
	constructor() {
		this.ox = 0; this.oy = 0; this.w = 0; this.h = 0;
		this.sky = new Uint8Array(0); this.blk = new Uint8Array(0); this.blkBase = new Uint8Array(0);
		this.opq = new Uint8Array(0); this.drawn = new Uint8Array(0);
		this.valid = false; this.stamp = -1; this.skyUsed = -1; this.dynUsed = 0; this.dimUsed = -1; this.layoutUsed = -1;
		this.qCap = 0; this.queue = new Int32Array(0); this.skySeed = new Int32Array(0); this.lens = new Int32Array(16); this.skyN = 0;
	}
	covers(x0, y0, x1, y1) { return this.valid && x0 >= this.ox && y0 >= this.oy && x1 < this.ox + this.w && y1 < this.oy + this.h; }

	/** Lights the window. `dyn` is a flat list of moving lights: x, y, level, ... */
	compute(world, nox, noy, nw, nh, skyLevel, dyn, noteSeen = true) {
		this.ox = nox; this.oy = noy; this.w = nw; this.h = nh;
		const n = nw * nh;
		if (this.sky.length !== n) {
			this.sky = new Uint8Array(n); this.blk = new Uint8Array(n); this.blkBase = new Uint8Array(n);
			this.opq = new Uint8Array(n); this.drawn = new Uint8Array(n);
		}
		if (this.qCap < n) { this.qCap = n; this.queue = new Int32Array(n * 16); this.skySeed = new Int32Array(n); }
		const sky = this.sky, blk = this.blk, opq = this.opq, drawn = this.drawn, q = this.queue, ss = this.skySeed, ln = this.lens, cap = this.qCap;
		ln.fill(0); sky.fill(0); blk.fill(0);
		const H = world.H, hasSky = dimHasSky(world.dim), sl = clampI(skyLevel, 0, 15);
		let sn = 0;
		for (let ix = 0; ix < nw; ix++) {
			const x = nox + ix;
			const cx = floorDiv(x, chunkW), lx = x - cx * chunkW;
			const c = world.chunk(cx);
			if (c) {
				const skyTop = hasSky ? c.skyTop[lx] : -1;
				const back = world.backdrop(c), tiles = c.tiles, base = lx * H;
				for (let iy = 0, i = ix; iy < nh; iy++, i += nw) {
					const y = noy + iy;
					if (y < 0) {
						opq[i] = 0; drawn[i] = 0;
						if (hasSky && sl > 0) { sky[i] = sl; ss[sn++] = i; }
					} else if (y >= H) {
						opq[i] = 1; drawn[i] = 1;
					} else {
						const raw = tiles[base + y];
						const op = OPAQUE[raw];
						opq[i] = op;
						drawn[i] = (raw !== 0 || back[base + y] !== 0) ? 1 : 0;
						const emit = LIGHT[raw];
						if (emit > 0) { blk[i] = emit; q[emit * cap + ln[emit]++] = i; }
						if (hasSky && !op && y < skyTop && sl > 0) { sky[i] = sl; ss[sn++] = i; }
					}
				}
			} else {
				for (let iy = 0, i = ix; iy < nh; iy++, i += nw) {
					const y = noy + iy;
					opq[i] = y >= 0 ? 1 : 0; drawn[i] = y >= 0 ? 1 : 0;
					if (y < 0 && hasSky && sl > 0) { sky[i] = sl; ss[sn++] = i; }
				}
			}
		}
		this.skyN = sn;
		this.propagate(blk);
		ln.fill(0);
		if (sl > 0) { q.set(ss.subarray(0, sn), sl * cap); ln[sl] = sn; }
		this.propagate(sky);
		this.blkBase.set(blk);
		this.applyDynamic(dyn);
		this.valid = true;
		this.skyUsed = skyLevel; this.dimUsed = world.dim; this.stamp = world.version; this.layoutUsed = world.layoutVersion;
		if (noteSeen) { PERF.lightFull++; world.editAny = false; }
	}
	/** Lights only what moving lights touch, starting again from the tiles' own light */
	applyDynamic(dyn) {
		if (this.blkBase.length !== this.w * this.h || this.w === 0) return;
		const blk = this.blk, ln = this.lens, q = this.queue, cap = this.qCap;
		blk.set(this.blkBase);
		ln.fill(0);
		let any = false;
		for (let k = 0; k + 2 < dyn.length; k += 3) {
			const lx = dyn[k] - this.ox, ly = dyn[k + 1] - this.oy;
			if (lx < 0 || ly < 0 || lx >= this.w || ly >= this.h) continue;
			const i = ly * this.w + lx, v = clampI(dyn[k + 2], 0, 15);
			if (v > blk[i]) { blk[i] = v; q[v * cap + ln[v]++] = i; any = true; }
		}
		if (any) this.propagate(blk);
	}
	propagate(lv) {
		const q = this.queue, ln = this.lens, cap = this.qCap, ww = this.w, hh = this.h, op = this.opq;
		for (let l = 15; l >= 2; l--) {
			const nl = l - 1, ol = l - 2;
			const qa = l * cap, qn = nl * cap, qo = ol * cap;
			for (let k = 0; k < ln[l]; k++) {
				const ci = q[qa + k];
				if (lv[ci] !== l) continue;
				const cy = Math.floor(ci / ww), cx = ci - cy * ww;
				if (cx > 0) {
					const nb = ci - 1;
					if (!op[nb]) { if (lv[nb] < nl) { lv[nb] = nl; q[qn + ln[nl]++] = nb; } }
					else if (ol >= 1 && lv[nb] < ol) { lv[nb] = ol; q[qo + ln[ol]++] = nb; }
				}
				if (cx < ww - 1) {
					const nb = ci + 1;
					if (!op[nb]) { if (lv[nb] < nl) { lv[nb] = nl; q[qn + ln[nl]++] = nb; } }
					else if (ol >= 1 && lv[nb] < ol) { lv[nb] = ol; q[qo + ln[ol]++] = nb; }
				}
				if (cy > 0) {
					const nb = ci - ww;
					if (!op[nb]) { if (lv[nb] < nl) { lv[nb] = nl; q[qn + ln[nl]++] = nb; } }
					else if (ol >= 1 && lv[nb] < ol) { lv[nb] = ol; q[qo + ln[ol]++] = nb; }
				}
				if (cy < hh - 1) {
					const nb = ci + ww;
					if (!op[nb]) { if (lv[nb] < nl) { lv[nb] = nl; q[qn + ln[nl]++] = nb; } }
					else if (ol >= 1 && lv[nb] < ol) { lv[nb] = ol; q[qo + ln[ol]++] = nb; }
					// open air also lights the solid cells diagonally below it, so a block standing on the
					// ground does not leave a dark shaft down its column
					if (!op[ci] && ol >= 1) {
						if (cx > 0) { const dg = nb - 1; if (op[dg] && lv[dg] < ol) { lv[dg] = ol; q[qo + ln[ol]++] = dg; } }
						if (cx < ww - 1) { const dg = nb + 1; if (op[dg] && lv[dg] < ol) { lv[dg] = ol; q[qo + ln[ol]++] = dg; } }
					}
				}
			}
		}
	}
	/** Sky and block light seen at a cell (an opaque cell shows its brightest open neighbour's) */
	levelSky(x, y) { return this.levelOf(this.sky, x, y); }
	levelBlk(x, y) { return this.levelOf(this.blk, x, y); }
	levelOf(a, x, y) {
		const lx = x - this.ox, ly = y - this.oy, w = this.w;
		if (lx < 0 || ly < 0 || lx >= w || ly >= this.h) return 0;
		const i = ly * w + lx;
		let s = a[i];
		if (this.opq[i]) {
			if (lx > 0 && a[i - 1] > s) s = a[i - 1];
			if (lx < w - 1 && a[i + 1] > s) s = a[i + 1];
			if (ly > 0 && a[i - w] > s) s = a[i - w];
			if (ly < this.h - 1 && a[i + w] > s) s = a[i + w];
		}
		return s;
	}
	brightness(x, y) { return Math.max(this.levelSky(x, y), this.levelBlk(x, y)); }

	/** Builds the two overlay layers as RGBA bytes (not premultiplied): darkness and warm glow */
	buildPixels(dark, glow, ambient, nightMix) {
		// tables by sky * 16 + block
		const dT = LightMap.darkT, gT = LightMap.glowT;
		for (let s = 0; s < 16; s++) for (let b = 0; b < 16; b++) {
			const sb = lightLUT[s], bb = lightLUT[b];
			const bright = Math.max(sb, bb, ambient);
			const a = Math.max(0, Math.floor((1 - bright) * 238));
			const tint = (sb > bb ? 1 : 0) * nightMix;
			const k = (s * 16 + b) * 4;
			dT[k] = Math.floor(3 + 9 * tint); dT[k + 1] = Math.floor(4 + 14 * tint); dT[k + 2] = Math.floor(9 + 44 * tint); dT[k + 3] = a;
			gT[k] = 255; gT[k + 1] = 0x96; gT[k + 2] = 0x3C; gT[k + 3] = Math.floor(bb * (1 - sb * 0.9) * 0.34 * 255);
		}
		const ww = this.w, hh = this.h, sky = this.sky, blk = this.blk, opq = this.opq, drawn = this.drawn;
		for (let iy = 0; iy < hh; iy++) {
			for (let ix = 0; ix < ww; ix++) {
				const i = iy * ww + ix, o = i * 4;
				if (!drawn[i]) { dark[o + 3] = 0; glow[o + 3] = 0; dark[o] = 3; dark[o + 1] = 4; dark[o + 2] = 9; glow[o] = 255; glow[o + 1] = 0x96; glow[o + 2] = 0x3C; continue; }
				let s = sky[i], b = blk[i];
				if (opq[i]) {
					if (ix > 0) { if (sky[i - 1] > s) s = sky[i - 1]; if (blk[i - 1] > b) b = blk[i - 1]; }
					if (ix < ww - 1) { if (sky[i + 1] > s) s = sky[i + 1]; if (blk[i + 1] > b) b = blk[i + 1]; }
					if (iy > 0) { if (sky[i - ww] > s) s = sky[i - ww]; if (blk[i - ww] > b) b = blk[i - ww]; }
					if (iy < hh - 1) { if (sky[i + ww] > s) s = sky[i + ww]; if (blk[i + ww] > b) b = blk[i + ww]; }
				}
				const k = (s * 16 + b) * 4;
				dark[o] = dT[k]; dark[o + 1] = dT[k + 1]; dark[o + 2] = dT[k + 2]; dark[o + 3] = dT[k + 3];
				glow[o] = gT[k]; glow[o + 1] = gT[k + 1]; glow[o + 2] = gT[k + 2]; glow[o + 3] = gT[k + 3];
			}
		}
	}
}
LightMap.darkT = new Uint8Array(1024);
LightMap.glowT = new Uint8Array(1024);
