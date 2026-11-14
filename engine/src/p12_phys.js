// Physics: bodies against the land (the Swift game's p12_phys).

/** A body: x is its middle, y its feet */
function makeBody(x, y, w, h) {
	return { x, y, vx: 0, vy: 0, w, h, onGround: false, hitWall: false, hitCeil: false, inWater: false, inLava: false, deck: -1, wasOnGround: false, ride: 0, rlx: 0, rly: 0 };
}
const bodyLeft = (b) => b.x - b.w * 0.5;
const bodyRight = (b) => b.x + b.w * 0.5;
const bodyTop = (b) => b.y - b.h;

/** How hard things fall (a mod's gravity rule scales it) */
const gravityG = () => 34.0 * rule("gravity");
const terminalV = 26.0;

Object.assign(World.prototype, {
	/** the first tile in the box whose flag in `table` is set: its number, or -1 */
	scanBox(tx0, ty0, tx1, ty1, table) {
		const hh = this.H;
		const ya = ty0 > 0 ? ty0 : 0, yb = ty1 < hh - 1 ? ty1 : hh - 1;
		for (let tx = tx0; tx <= tx1; tx++) {
			const cx = Math.floor(tx / chunkW);
			const c = cx === this.cacheCX ? this.cacheChunk : this.chunk(cx);
			if (c) {
				const arr = c.tiles;
				for (let y = ya, i = (tx - cx * chunkW) * hh + ya; y <= yb; y++, i++) { const r = arr[i]; if (table[r]) return r; }
				if (ty1 >= hh && table[T.bedrock]) return T.bedrock;
			} else {
				for (let y = ty0; y <= ty1; y++) { const r = this.tile(tx, y); if (table[r]) return r; }
			}
		}
		return -1;
	},
	boxSolid(x0, y0, x1, y1) {
		const tx0 = Math.floor(x0), tx1 = Math.floor(x1 - 0.0001), ty0 = Math.floor(y0), ty1 = Math.floor(y1 - 0.0001);
		if (tx1 < tx0 || ty1 < ty0) return false;
		return this.scanBox(tx0, ty0, tx1, ty1, SOLID) >= 0;
	},
	/** nothing in the box for a vehicle to meet: no solid block and no liquid */
	boxOpen(x0, y0, x1, y1) {
		const tx0 = Math.floor(x0), tx1 = Math.floor(x1 - 0.0001), ty0 = Math.floor(y0), ty1 = Math.floor(y1 - 0.0001);
		if (tx1 < tx0 || ty1 < ty0) return true;
		return this.scanBox(tx0, ty0, tx1, ty1, MEET) < 0;
	},
	/** the tile in the box that hurts to touch, or -1 */
	boxHurts(x0, y0, x1, y1) {
		const tx0 = Math.floor(x0), tx1 = Math.floor(x1 - 0.0001), ty0 = Math.floor(y0), ty1 = Math.floor(y1 - 0.0001);
		if (tx1 < tx0 || ty1 < ty0) return -1;
		return this.scanBox(tx0, ty0, tx1, ty1, HURTS);
	},
	/** how much of a cell is liquid: 0...1 (a part-full cell counts by its level) */
	liquidAmount(x, y) {
		const t = this.tile(x, y);
		if (!LIQUID[t]) return 0;
		const cx = floorDiv(x, chunkW), c = this.chunk(cx);
		if (!c || !c.level) return 1;
		const l = c.level[(x - cx * chunkW) * this.H + y];
		return l === 0 ? 1 : l / 255;
	},
	/** the shares of a box covered by water and by lava: [water, lava] */
	liquidFractions(x0, y0, x1, y1) {
		const tx0 = Math.floor(x0), tx1 = Math.floor(x1 - 0.0001), ty0 = Math.floor(y0), ty1 = Math.floor(y1 - 0.0001);
		if (tx1 < tx0 || ty1 < ty0) return LIQ0;
		let w = 0, l = 0;
		for (let tx = tx0; tx <= tx1; tx++) for (let ty = ty0; ty <= ty1; ty++) {
			const t = this.tile(tx, ty);
			if (!LIQUID[t]) continue;
			const a = this.liquidAmount(tx, ty);
			if (t === T.lava) l += a; else w += a;
		}
		const n = (tx1 - tx0 + 1) * (ty1 - ty0 + 1);
		LIQR[0] = w / n; LIQR[1] = l / n;
		return LIQR;
	},

	// ---- stairs: not solid; a full-width lower step (the bottom half) and an upper step on the high
	// side (the top half, the right half for R, the left for L)
	stairAt(x, y) { return (y < 0 || y >= this.H) ? 0 : STAIR[this.tile(x, y)]; },
	stairsNear(x0, x1) {
		for (let cx = floorDiv(Math.floor(x0), chunkW), c1 = floorDiv(Math.floor(x1), chunkW); cx <= c1; cx++) {
			const c = this.chunk(cx);
			if (!c) continue;
			if (c.stairs < 0) { let n = 0; const a = c.tiles; for (let i = 0; i < a.length; i++) if (STAIR[a[i]]) n++; c.stairs = n; }
			if (c.stairs > 0) return true;
		}
		return false;
	},
	stairHit(x0, y0, x1, y1) {
		const tx0 = Math.floor(x0), tx1 = Math.floor(x1 - 0.0001), ty0 = Math.floor(y0), ty1 = Math.floor(y1 - 0.0001);
		for (let tx = tx0; tx <= tx1; tx++) for (let ty = ty0; ty <= ty1; ty++) {
			const s = this.stairAt(tx, ty);
			if (s === 0) continue;
			if (y1 > ty + 0.5 && y0 < ty + 1.0) return true;
			const hx = s === 1 ? tx + 0.5 : tx;
			if (y1 > ty && y0 < ty + 0.5 && x1 > hx && x0 < hx + 0.5) return true;
		}
		return false;
	},
	boxBlocked(x0, y0, x1, y1, stairs) {
		if (this.boxSolid(x0, y0, x1, y1)) return true;
		return stairs && this.stairHit(x0, y0, x1, y1);
	},
	/** the first stair top a body's feet meet coming down from prevY to ny (NaN: none) */
	stairLanding(x0, x1, prevY, ny) {
		const tx0 = Math.floor(x0), tx1 = Math.floor(x1 - 0.0001), ty0 = Math.floor(prevY - 0.001), ty1 = Math.floor(ny + 0.0005);
		let best = NaN;
		for (let tx = tx0; tx <= tx1; tx++) for (let ty = ty0; ty <= ty1; ty++) {
			const s = this.stairAt(tx, ty);
			if (s === 0) continue;
			const low = ty + 0.5;
			if (low >= prevY - 0.001 && low <= ny + 0.0005 && !(best <= low)) best = low;
			const hx = s === 1 ? tx + 0.5 : tx;
			if (x1 > hx + 0.001 && x0 < hx + 0.499) {
				const up = ty;
				if (up >= prevY - 0.001 && up <= ny + 0.0005 && !(best <= up)) best = up;
			}
		}
		return best;
	},
	/** the first stair underside a body's head meets going up (NaN: none) */
	stairCeiling(x0, x1, prevTop, newTop) {
		const tx0 = Math.floor(x0), tx1 = Math.floor(x1 - 0.0001), ty0 = Math.floor(newTop) - 1, ty1 = Math.floor(prevTop);
		let best = NaN;
		for (let tx = tx0; tx <= tx1; tx++) for (let ty = ty0; ty <= ty1; ty++) {
			const s = this.stairAt(tx, ty);
			if (s === 0) continue;
			const low = ty + 1.0;
			if (low <= prevTop + 0.001 && low >= newTop - 0.0005 && !(best >= low)) best = low;
			const hx = s === 1 ? tx + 0.5 : tx;
			if (x1 > hx + 0.001 && x0 < hx + 0.499) {
				const up = ty + 0.5;
				if (up <= prevTop + 0.001 && up >= newTop - 0.0005 && !(best >= up)) best = up;
			}
		}
		return best;
	},

	/** Moves a body by its speed (the caller sets vx and vy). It collides with solid tiles, stairs,
	 *  one-way platforms and decks; stepUp is the ledge height climbed without a jump. */
	moveBody(b, dt, stepUp, dropThrough, decks) {
		b.wasOnGround = b.onGround;
		b.hitWall = false; b.hitCeil = false; b.onGround = false; b.deck = -1;
		const speed = Math.max(Math.abs(b.vx), Math.abs(b.vy));
		const steps = Math.max(1, Math.ceil(speed * dt / 0.3));
		const sdt = dt / steps;
		const hw = b.w * 0.5;
		const st = this.stairsNear(b.x - hw - 1.0, b.x + hw + 1.0);
		const liftStep = st ? 0.5 : 1.0;
		// unstick: inside solid ground, push upward
		for (let k = 0; k < (st ? 12 : 6) && this.boxBlocked(b.x - hw + 0.02, b.y - b.h + 0.02, b.x + hw - 0.02, b.y - 0.02, st); k++) b.y -= liftStep;
		for (let n = 0; n < steps; n++) {
			if (b.vx !== 0) {
				const nx = b.x + b.vx * sdt;
				if (!this.boxBlocked(nx - hw, b.y - b.h + 0.001, nx + hw, b.y - 0.001, st)) b.x = nx;
				else {
					let done = false;
					if ((b.wasOnGround || b.onGround) && stepUp > 0) {
						for (let lift = liftStep; lift <= stepUp + 0.001 && !done; lift += liftStep) {
							if (!this.boxBlocked(nx - hw, b.y - lift - b.h + 0.001, nx + hw, b.y - lift - 0.001, st)) { b.x = nx; b.y -= lift; done = true; }
						}
					}
					if (!done) { b.hitWall = true; b.vx = 0; }
				}
			}
			const prevY = b.y, ny = b.y + b.vy * sdt;
			if (b.vy >= 0) {
				let landed = false, landY = ny;
				if (this.boxSolid(b.x - hw, ny - b.h + 0.001, b.x + hw, ny + 0.0005)) {
					landY = Math.floor(ny + 0.0005);
					if (landY < prevY - 0.0001) landY = prevY;
					if (st) { const sl = this.stairLanding(b.x - hw, b.x + hw, prevY, ny); if (sl < landY) landY = Math.max(sl, prevY); }
					landed = true;
				} else {
					const sl = st ? this.stairLanding(b.x - hw, b.x + hw, prevY, ny) : NaN;
					if (sl === sl) { landed = true; landY = sl; }
					else {
						const rowF = Math.floor(ny + 0.0005);
						if (!dropThrough) {
							const tx0 = Math.floor(b.x - hw), tx1 = Math.floor(b.x + hw - 0.0001);
							for (let tx = tx0; tx <= tx1; tx++) {
								if (PLATFORM[this.tile(tx, rowF)] && prevY <= rowF + 0.001 && ny >= rowF - 0.0001) { landed = true; landY = rowF; }
							}
						}
						if (!landed && decks) {
							for (let i = 0; i < decks.length; i++) {
								const d = decks[i];
								if (b.x + hw > d.x0 && b.x - hw < d.x1 && prevY <= d.y + 0.06 && ny >= d.y - 0.0001 && !dropThrough) { landed = true; landY = d.y; b.deck = i; }
							}
						}
					}
				}
				if (landed) { b.y = landY; b.vy = 0; b.onGround = true; } else b.y = ny;
			} else {
				if (this.boxSolid(b.x - hw, ny - b.h, b.x + hw, ny - 0.001)) {
					b.y = Math.floor(ny - b.h) + 1.0 + b.h;
					b.vy = 0; b.hitCeil = true;
				} else {
					const sc = st ? this.stairCeiling(b.x - hw, b.x + hw, prevY - b.h, ny - b.h) : NaN;
					if (sc === sc) { b.y = sc + b.h; b.vy = 0; b.hitCeil = true; } else b.y = ny;
				}
			}
		}
		const lf = this.liquidFractions(b.x - hw, b.y - b.h, b.x + hw, b.y);
		b.inWater = lf[0] > 0.35;
		b.inLava = lf[1] > 0.2;
	},
});
const LIQ0 = [0, 0], LIQR = [0, 0];
