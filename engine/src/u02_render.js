// Drawing the world (the Swift game's u02_render): the sky and clouds, the land a section at a time,
// things in the world, the player, the light, then overlays. Screen numbers are device pixels.

const fineScale = 1 / 16;

/** Four tones of a colour, as the drawings shade with: a warm light, the colour, two cool shadows */
function artRamp(c, light = 0xFFF0C8, dark = 0x241A38) {
	const s1 = mixRGB(mixRGB(c, 0, 0.22), dark, 0.18), s2 = mixRGB(mixRGB(c, 0, 0.42), dark, 0.30);
	return [mixRGB(c, light, 0.28), c, s1, s2];
}
const lookRamp = (c) => artRamp(c).map(artGrade);
const PLAYER_INK = {
	hair: [0xF00001, 0xF00002, 0xF00003, 0xF00004], shirt: [0x00F001, 0x00F002, 0x00F003, 0x00F004],
	pants: [0x0000F1, 0x0000F2, 0x0000F3, 0x0000F4], shoe: [0xF0F001, 0xF0F002, 0xF0F003, 0xF0F004],
	scarf: [0x00F0F1, 0x00F0F2, 0x00F0F3, 0x00F0F4], helm: [0xF000F1, 0xF000F2, 0xF000F3, 0xF000F4], shoeColor: 0x24242E,
};
const armorLookColor = (tierKey) => tierKey === "wood" ? 0x9A5A2A : tierByKey[tierKey].color;

/** The player's frames: the bare figure with the chosen clothes laid over it and every marker colour
 *  swapped for the chosen colour's tones; armour takes the place of the clothes */
const PlayerArt = {
	key: "", tex: null, meta: DATA.sheet.player, buf: null,
	choiceKey(g) {
		const s = g.settings, a = g.inv.armor;
		const at = (i) => (a[i] && a[i].id.startsWith("armor:")) ? a[i].id.split(":")[2] : "";
		return [s.hair, s.hairStyle, s.shirtColor, s.shirtStyle, s.pantsColor, s.pantsStyle, s.scarf, at(0), at(1), at(2)].join(",");
	},
	ensure(g) {
		const key = this.choiceKey(g) + "|" + Atlas.gen;
		if (key === this.key && this.tex) return;
		this.key = key;
		const m = this.meta, n = m.frames, fw = m.w, fh = m.h;
		const out = new Uint32Array(fw * n * fh);
		const s = g.settings, a = g.inv.armor;
		const tierOf = (i) => (a[i] && a[i].id.startsWith("armor:")) ? a[i].id.split(":")[2] : null;
		const head = tierOf(0), chest = tierOf(1), legs = tierOf(2);
		const lay = (name) => {
			const r = DATA.atlas.rects["sheet:" + name];
			if (!r) return;
			for (let f = 0; f < Math.min(n, r.length); f++) {
				const [ax, ay, w, h] = r[f];
				for (let y = 0; y < Math.min(h, fh); y++) for (let x = 0; x < Math.min(w, fw); x++) {
					const c = Atlas.px32[(ay + y) * Atlas.w + ax + x];
					if ((c >>> 24) !== 0) out[y * fw * n + f * fw + x] = c;
				}
			}
		};
		lay("player");
		let pantsStyle = s.pantsStyle, pantsCol = DATA.misc.pants[clampI(s.pantsColor, 0, DATA.misc.pants.length - 1)], shoeCol = PLAYER_INK.shoeColor;
		if (legs) { pantsStyle = 0; pantsCol = shadeRGB(armorLookColor(legs), 0.85); shoeCol = shadeRGB(armorLookColor(legs), 0.6); }
		let shirtStyle = s.shirtStyle, shirtCol = DATA.misc.shirt[clampI(s.shirtColor, 0, DATA.misc.shirt.length - 1)];
		if (chest) { shirtStyle = 1; shirtCol = armorLookColor(chest); }
		lay("player_pants_" + pantsStyle);
		lay("player_shirt_" + shirtStyle);
		if (s.scarf !== 0) lay("player_scarf");
		lay("player_hair_" + s.hairStyle);
		if (head) lay("player_helm");
		const map = new Map();
		const tone = (markers, col) => { const r = lookRamp(col); markers.forEach((mk, i) => map.set(mk, r[i])); };
		tone(PLAYER_INK.pants, pantsCol);
		tone(PLAYER_INK.shoe, shoeCol);
		tone(PLAYER_INK.shirt, shirtCol);
		tone(PLAYER_INK.hair, DATA.misc.hair[clampI(s.hair, 0, DATA.misc.hair.length - 1)]);
		if (s.scarf !== 0) tone(PLAYER_INK.scarf, DATA.misc.scarf[clampI(s.scarf, 0, DATA.misc.scarf.length - 1)]);
		if (head) tone(PLAYER_INK.helm, armorLookColor(head));
		for (let i = 0; i < out.length; i++) {
			const c = out[i];
			if ((c >>> 24) === 0) continue;
			const rgb = ((c & 255) << 16) | (c & 0xFF00) | ((c >>> 16) & 255);
			const to = map.get(rgb);
			if (to !== undefined) out[i] = (0xFF000000 | ((to & 255) << 16) | (to & 0xFF00) | ((to >> 16) & 255)) >>> 0;
		}
		this.buf = out;
		const bytes = new Uint8Array(out.buffer);
		if (this.tex) R.updateTex(this.tex, fw * n, fh, bytes); else this.tex = R.makeTex(fw * n, fh, bytes, false);
	},
	/** the frame for what the player is doing (0 standing, walking, wind-up, strike, block, shoot, front) */
	frame(g) {
		const p = this.meta.poses, pb = g.pb;
		const walk = p.walk || [1, 2, 3, 4];
		if (g.swingT > 0) {
			if (g.heldItem && isRangedItem(g.heldItem)) return (p.shoot || [8])[0];
			return g.swingT > g.swingDur * 0.5 ? (p.windup || [5])[0] : (p.strike || [6])[0];
		}
		if (g.bowCharge > 0) return (p.shoot || [8])[0];
		if (!pb.onGround && !pb.inWater) return walk[0];
		if (Math.abs(pb.vx) > 0.6) return walk[Math.floor(Math.abs(g.walkAnim) * walk.length) % walk.length];
		if (g.restT > 0.9 && p.front) return p.front[0];
		return 0;
	},
};

const SectionCache = { map: new Map(), frame: 0, built: 0, owner: -1 };
function sectionKey(dim, cx, sy) { return ((cx * 64 + (sy & 63)) * 8 + (dim & 7)); }
function clearSectionCache() { for (const e of SectionCache.map.values()) R.freeTex(e.tex); SectionCache.map.clear(); }

const View = { tp: 24, left: 0, top: 0, wT: 0, hT: 0, sx(x) { return (x - this.left) * this.tp; }, sy(y) { return (y - this.top) * this.tp; } };

const CLOUD_LAYERS = [
	{ par: 0.30, speed: 0.45, cell: 7, rowTop: 0, rows: 9, pool: [0, 1, 2], groups: 0.14, lift: 0.05, haze: 0.30, opacity: 0.80 },
	{ par: 0.55, speed: 0.75, cell: 12, rowTop: 1, rows: 12, pool: [1, 2, 3], groups: 0.20, lift: 0.08, haze: 0.14, opacity: 0.90 },
	{ par: 0.80, speed: 1.00, cell: 22, rowTop: 3, rows: 12, pool: [1, 3, 4, 4], groups: 0.25, lift: 0.12, haze: 0, opacity: 0.96 },
	{ par: 0.70, speed: 1.35, cell: 16, rowTop: -2, rows: 7, pool: [2, 4, 4], groups: 0.30, lift: 0.10, haze: 0, opacity: 0.94 },
];
function cloudsOf(seed, layer, d, x0, x1, fill, out) {
	const L = CLOUD_LAYERS[layer];
	const shift = d * L.speed;
	const c0 = Math.floor((x0 - shift - 60) / L.cell), c1 = Math.floor((x1 - shift) / L.cell);
	const s = (seed + (layer + 1) * 7919) | 0;
	out.length = 0;
	for (let ci = c0; ci <= c1; ci++) {
		const presence = hash2(ci, 11, s) - (1 - fill);
		if (presence <= 0) continue;
		const alpha = clampD(presence / 0.1, 0, 1);
		const formation = hash2(ci, 21, s) < L.groups;
		const n = formation ? 3 + Math.floor(hash2(ci, 22, s) * 3) : 1;
		const bx = ci * L.cell + hash2(ci, 12, s) * L.cell * 0.8 + shift, by = L.rowTop + hash2(ci, 13, s) * L.rows;
		for (let k = 0; k < n; k++) {
			const cls = L.pool[Math.floor(hash2(ci, 30 + k, s) * L.pool.length) % L.pool.length];
			const ids = DATA.clouds[cls];
			const kind = ids[Math.floor(hash2(ci, 50 + k, s) * ids.length) % ids.length];
			out.push({ x: bx + (k === 0 ? 0 : (hash2(ci, 60 + k, s) - 0.35) * 26), y: by + (k === 0 ? 0 : (hash2(ci, 70 + k, s) - 0.5) * 7), kind, flip: hash2(ci, 80 + k, s) < 0.5, alpha });
		}
	}
	return out;
}
const cloudList = [];

const Renderer = {
	lightTex: null, glowTex: null, lightRev: -1, lo: null,
	draw(g) {
		const t0 = performance.now();
		const W = R.W, H = R.H, dpr = R.dpr;
		if (SectionCache.owner !== g.serial) { clearSectionCache(); SectionCache.owner = g.serial; this.lightRev = -1; }
		SectionCache.frame++;
		SectionCache.built = 0;
		const tp = g.tilePx * dpr;
		const wT = W / tp, hT = H / tp;
		let left = g.camX - wT * 0.5, top = g.camY - hT * 0.5;
		if (g.shake > 0) { const s = g.shake * 0.3; left += rand(-1, 1) * s; top += rand(-1, 1) * s; }
		left = Math.round(left * tp) / tp; top = Math.round(top * tp) / tp;
		View.tp = tp; View.left = left; View.top = top; View.wT = wT; View.hT = hT;
		// the sky
		const sky = this.skyColors(g);
		R.begin(((sky[1] >> 16) & 255) / 255, ((sky[1] >> 8) & 255) / 255, (sky[1] & 255) / 255);
		if (!this.skyHidden(g)) this.drawSky(g, W, H, sky);
		else R.rect(0, 0, W, H, rgba(0));
		this.drawSections(g);
		drawHooksBack.forEach((f) => f(g));
		this.drawDrops(g);
		drawHooksMid.forEach((f) => f(g));
		this.drawPlayer(g);
		drawHooksFront.forEach((f) => f(g));
		this.drawLeafFall(g);
		this.drawParticles(g);
		this.drawLight(g);
		this.drawOverlays(g, W, H);
		R.end();
		PERF.renderMs = PERF.renderMs * 0.9 + (performance.now() - t0) * 0.1;
	},
	skyHidden(g) {
		const x0 = Math.floor(View.left), x1 = Math.ceil(View.left + View.wT), top = Math.floor(View.top);
		for (let x = x0; x <= x1; x++) {
			const cx = floorDiv(x, chunkW), ch = g.world.chunk(cx);
			if (!ch) return false;
			if (top <= ch.surf[x - cx * chunkW] + 2) return false;
		}
		return true;
	},
	skyColors(g) {
		if (g.world.dim === Dimension.umbral) return [0x0C0614, 0x241030, 0];
		const day = g.dayFactor, t = g.timeOfDay;
		let topC = mixRGB(0x060A1E, 0x3E86D8, day), botC = mixRGB(0x18223E, 0xB4DCFF, day);
		let dusk = 0;
		if (t > 0.46 && t < 0.62) dusk = 1 - Math.abs(t - 0.54) / 0.08;
		if (t > 0.88 || t < 0.04) { const tt = t > 0.5 ? t - 1 : t; dusk = Math.max(dusk, 1 - Math.abs(tt + 0.04) / 0.08); }
		dusk = clampD(dusk, 0, 1);
		botC = mixRGB(botC, 0xF08A4A, dusk * 0.7);
		switch (g.biomeHere) {
			case Biome.desert: case Biome.savanna: botC = mixRGB(botC, 0xF0D8A0, 0.25 * day); break;
			case Biome.tundra: topC = mixRGB(topC, 0xA8C0D8, 0.25 * day); botC = mixRGB(botC, 0xF0F4FA, 0.3 * day); break;
			case Biome.swamp: botC = mixRGB(botC, 0x9AB08A, 0.35 * day); break;
			case Biome.jungle: botC = mixRGB(botC, 0xA8E0B0, 0.2 * day); break;
		}
		return [artGrade(topC), artGrade(botC), dusk];
	},
	drawSky(g, W, H, sky) {
		R.grad(0, 0, W, H, rgba(sky[0]), rgba(sky[1]));
		if (g.world.dim !== Dimension.overworld) return;
		const day = g.dayFactor, t = g.timeOfDay, dpr = R.dpr;
		const cover = g.cloudCover ? g.cloudCover() : 0;
		// stars
		if (day < 0.6 && cover < 0.95) {
			const a = (0.6 - day) / 0.6 * (1 - cover);
			for (let i = 0; i < 70; i++) {
				const tw = 0.6 + 0.4 * Math.sin(g.clock * 2 + (i % 3) * 2.1);
				const s = (i % 7 === 0 ? 3 : 2) * dpr;
				R.rect(hash2(i, 1, 5) * W, hash2(i, 2, 5) * H * 0.6, s, s, rgba(0xFFFFFF, a * tw));
			}
		}
		// the sun and the moon
		const ang = t < 0.5 ? t / 0.5 : (t - 0.5) / 0.5;
		const bx = (0.1 + 0.8 * ang) * W, by = H * (0.55 - 0.42 * Math.sin(ang * Math.PI));
		const op = 1 - 0.9 * cover, k = dpr;
		if (t < 0.5) {
			R.oval(bx - 46 * k, by - 46 * k, 92 * k, 92 * k, rgba(artGrade(0xFFE680), 0.16 * op));
			R.oval(bx - 34 * k, by - 34 * k, 68 * k, 68 * k, rgba(artGrade(0xFFE680), 0.25 * op));
			R.oval(bx - 26 * k, by - 26 * k, 52 * k, 52 * k, rgba(artGrade(0xFFD84A), op));
			R.oval(bx - 17 * k, by - 19 * k, 32 * k, 32 * k, rgba(artGrade(0xFFF2A0), op));
		} else {
			R.oval(bx - 34 * k, by - 34 * k, 68 * k, 68 * k, rgba(0xC8D4F0, 0.12 * op));
			R.oval(bx - 22 * k, by - 22 * k, 44 * k, 44 * k, rgba(0xE8ECF4, op));
			R.oval(bx - 10 * k, by - 12 * k, 11 * k, 11 * k, rgba(0xC4CAD6, op));
			R.oval(bx + 5 * k, by + 3 * k, 8 * k, 8 * k, rgba(0xC4CAD6, op));
			R.oval(bx - 3 * k, by + 9 * k, 5 * k, 5 * k, rgba(0xC4CAD6, op));
		}
		this.drawClouds(g, W, H, day, sky[2], cover);
		skyHooks.forEach((f) => f(g, W, H));
	},
	drawClouds(g, W, H, day, dusk, cover) {
		const drift = g.clock * 0.25 + (g.cloudDrift || 0);
		let tint = mixRGB(0x58628A, 0xFFFFFF, day);
		tint = mixRGB(tint, 0xFFC4A0, dusk * 0.5);
		const wet = g.precipHere ? g.precipHere() : 0;
		const storm = clampD((cover - 0.4) * 1.7, 0, 0.85) * (0.75 + 0.25 * wet);
		if (storm > 0) tint = mixRGB(tint, mixRGB(0x262B33, 0x6C727E, day), storm);
		const skyC = mixRGB(0x18223E, 0xB4DCFF, day);
		const camMid = View.top + View.hT * 0.5;
		const ctp = Math.min(View.tp, 24 * R.dpr);
		const px = ctp / 8;
		const fills = [0.46 + 0.45 * cover, 0.40 + 0.52 * cover, 0.26 + 0.60 * cover, clampD((cover - 0.35) / 0.5, 0, 1) * 0.95];
		for (let li = 0; li < CLOUD_LAYERS.length; li++) {
			const L = CLOUD_LAYERS[li];
			if (fills[li] <= 0.02) continue;
			const left = View.left * (View.tp / ctp) * L.par;
			const list = cloudsOf(g.gen.seed, li, drift, left, left + W / ctp, fills[li], cloudList);
			let lt = mixRGB(tint, skyC, L.haze);
			if (li === 3) lt = mixRGB(lt, 0x30363E, 0.4);
			const rise = clampD((112 - camMid) * L.lift, -3, 9);
			for (const cl of list) {
				const r = spriteRect("cloud:" + cl.kind);
				if (!r) continue;
				const sx = Math.round((cl.x - left) * ctp / px) * px, sy = Math.round((cl.y + rise) * ctp / px) * px;
				const cw = r[2] * px, chh = r[3] * px;
				if (sx > W || sx + cw < 0 || sy > H || sy + chh < 0) continue;
				R.sprite(r[0], r[1], r[2], r[3], sx, sy, cw, chh, rgba(lt, L.opacity * cl.alpha), cl.flip);
			}
		}
	},
	drawSections(g) {
		const world = g.world, H = world.H, tp = View.tp;
		const tx0 = Math.floor(View.left), tx1 = Math.ceil(View.left + View.wT);
		const ty0 = Math.max(0, Math.floor(View.top)), ty1 = Math.min(H - 1, Math.ceil(View.top + View.hT));
		if (ty1 < ty0) return;
		const c0 = floorDiv(tx0, chunkW), c1 = floorDiv(tx1, chunkW), s0 = Math.floor(ty0 / 16), s1 = Math.floor(ty1 / 16);
		const cache = SectionCache.map, secPx = 16 * tp;
		const cap = cache.size === 0 ? 10000 : 4;
		for (let cx = c0; cx <= c1; cx++) {
			const ch = world.chunks.get(cx);
			if (!ch) continue;
			for (let sy = s0; sy <= s1; sy++) {
				const k = sectionKey(world.dim, cx, sy);
				const srev = sy < ch.secRev.length ? ch.secRev[sy] : ch.rev;
				let e = cache.get(k);
				if (e && e.chunk !== ch.serial) { R.freeTex(e.tex); cache.delete(k); e = null; }
				if (!e || (e.rev !== srev && SectionCache.built < cap)) {
					const px = Painter.paint(world, ch, sy);
					const bytes = new Uint8Array(px.buffer);
					if (e) { R.updateTex(e.tex, SEC_PX, SEC_PX, bytes); e.rev = srev; }
					else { e = { tex: R.makeTex(SEC_PX, SEC_PX, bytes, false), rev: srev, used: 0, chunk: ch.serial }; cache.set(k, e); }
					SectionCache.built++;
					PERF.sections++;
				}
				e.used = SectionCache.frame;
				R.img(e.tex, View.sx(cx * chunkW), View.sy(sy * 16), secPx, secPx, 0, 0, 1, 1);
			}
		}
		if (cache.size > 220) {
			for (const [k, e] of cache) if (SectionCache.frame - e.used > 240) { R.freeTex(e.tex); cache.delete(k); }
		}
	},
	/** things standing in front of open sky are not under the dark overlay: they are shaded by the light */
	openShade(g, x, y) {
		if (g.fullBright || !g.light.valid) return 1;
		const L = g.light, tx = Math.floor(x), ty = Math.floor(y);
		if (!L.covers(tx, ty, tx, ty)) return 1;
		if (L.drawn[(ty - L.oy) * L.w + (tx - L.ox)]) return 1;
		return clampD(Math.max(lightLUT[L.levelSky(tx, ty)], lightLUT[L.levelBlk(tx, ty)]), 0.32, 1);
	},
	shadeCol(shade, alpha = 1, hurt = false) {
		if (hurt) return rgba(0xFF8080, alpha);
		if (shade >= 0.98) return rgba(0xFFFFFF, alpha);
		const r = Math.floor(shade * 0.92 * 255), gg = Math.floor(shade * 0.96 * 255), b = Math.floor(Math.min(1, shade * 1.2) * 255);
		return rgba((r << 16) | (gg << 8) | b, alpha);
	},
	/** a sprite set's frame standing at (x, y) (its feet), mirrored when facing left */
	drawFrame(tex, fx, fy, fw, fh, texW, texH, foot, cxCol, scale, x, y, left, col, rot = 0, squash = 1) {
		const px = scale * View.tp;
		const cc = left ? fw - cxCol : cxCol;
		let u0 = fx / texW, u1 = (fx + fw) / texW;
		if (left) { const t = u0; u0 = u1; u1 = t; }
		const v0 = fy / texH, v1 = (fy + fh) / texH;
		if (rot === 0 && squash === 1) {
			const snap = Math.max(1, px);
			const dx = Math.round((View.sx(x) - cc * px) / snap) * snap, dy = Math.round((View.sy(y) - foot * px) / snap) * snap;
			R.img(tex, dx, dy, fw * px, fh * px, u0, v0, u1, v1, col);
		} else {
			R.push();
			R.translate(View.sx(x), View.sy(y));
			if (rot) R.rotate(rot);
			R.scale(1 + (1 - squash) * 0.5, squash);
			R.img(tex, -cc * px, -foot * px, fw * px, fh * px, u0, v0, u1, v1, col);
			R.pop();
		}
	},
	drawPlayer(g) {
		if (g.dead || g.hidePlayer) return;
		PlayerArt.ensure(g);
		const m = PlayerArt.meta, pb = g.pb;
		let alpha = 1;
		if (g.invuln > 0 && g.hurtT <= 0 && Math.floor(g.clock * 12) % 2 === 0) alpha = 0.55;
		const f = PlayerArt.frame(g);
		const shade = this.openShade(g, pb.x, pb.y - pb.h * 0.5);
		const col = this.shadeCol(shade, alpha, g.hurtT > 0);
		const left = g.facing < 0;
		const pose = f >= 5 && f <= 8;
		if (g.heldItem && !pose) this.drawHeldItem(g, shade);
		const squash = g.landT > 0 ? 1 - 0.1 * (g.landT / 0.12) : (g.seated ? 0.74 : 1);
		this.drawFrame(PlayerArt.tex, f * m.w, 0, m.w, m.h, m.w * m.frames, m.h, m.foot + 1, m.cx, fineScale, pb.x, pb.y - (g.seated ? 0.12 : 0), left, col, 0, squash);
		if (g.heldItem && pose) this.drawHeldItem(g, shade);
		if (pb.inWater && g.air < 10 && g.headUnderWater()) {
			const headY = pb.y - pb.h * 0.92, rise = (g.clock * 0.8) % 0.6;
			for (let i = 0; i < 3; i++) {
				const bx = View.sx(pb.x + 0.2 * i) + Math.sin(g.clock * 3 + i) * 3 * R.dpr, by = View.sy(headY - 0.3 - i * 0.35 - rise);
				R.oval(bx, by, 5 * R.dpr, 5 * R.dpr, rgba(0xFFFFFF, 0.5));
			}
		}
	},
	/** the item in hand, swung while mining and fighting */
	drawHeldItem(g, shade) {
		const id = g.heldItem, r = iconRect(id), pb = g.pb;
		const dir = g.facing;
		const s = 0.62 * View.tp;
		let ang = -0.5;
		if (g.swingT > 0) { const p = 1 - g.swingT / Math.max(0.01, g.swingDur); ang = -1.6 + p * 2.4; }
		R.push();
		R.translate(View.sx(pb.x + dir * 0.28), View.sy(pb.y - pb.h * 0.52));
		R.scale(dir, 1);
		R.rotate(ang);
		R.sprite(r[0], r[1], r[2], r[3], -s * 0.15, -s * 0.85, s, s, this.shadeCol(shade));
		R.pop();
	},
	drawDrops(g) {
		const s = 0.62;
		for (const d of g.drops) {
			if (d.x < View.left - 2 || d.x > View.left + View.wT + 2 || d.y < View.top - 2 || d.y > View.top + View.hT + 2) continue;
			const bob = d.onGround ? Math.sin(d.age * 3) * 0.08 : 0;
			const r = iconRect(d.stack.id);
			const shade = this.openShade(g, d.x, d.y - 0.3);
			R.sprite(r[0], r[1], r[2], r[3], View.sx(d.x - s * 0.5), View.sy(d.y - s - 0.04 + bob), s * View.tp, s * View.tp, this.shadeCol(shade));
		}
	},
	drawLeafFall(g) {
		const p = Math.max(1, Math.round(View.tp / 16));
		for (const f of g.leafFlakes) {
			if (f.x < View.left - 1 || f.x > View.left + View.wT + 1) continue;
			const a = f.landed ? clampD(f.life / 2.5, 0, 1) : 1;
			const x = Math.round(View.sx(f.x) / p) * p, y = Math.round(View.sy(f.y) / p) * p;
			const toRgb = (c) => ((c & 255) << 16) | (c & 0xFF00) | ((c >>> 16) & 255);
			const lc = rgba(toRgb(f.light), a), dc = rgba(toRgb(f.dark), a);
			const turn = f.landed ? 0 : Math.floor(f.phase * 1.3) & 3;
			if (turn === 0) { R.rect(x - p, y, p * 2, p, lc); R.rect(x + p, y, p, p, dc); }
			else if (turn === 1) { R.rect(x - p, y - p, p, p, lc); R.rect(x, y, p, p, lc); R.rect(x + p, y + p, p, p, dc); }
			else if (turn === 2) { R.rect(x, y - p, p, p, lc); R.rect(x, y, p, p, dc); }
			else { R.rect(x + p, y - p, p, p, lc); R.rect(x, y, p, p, lc); R.rect(x - p, y + p, p, p, dc); }
		}
	},
	drawParticles(g) {
		for (const p of g.particles) {
			const a = clampD(p.life / Math.max(0.01, p.maxLife), 0, 1);
			const s = Math.max(2 * R.dpr, p.size * View.tp);
			R.rect(View.sx(p.x) - s * 0.5, View.sy(p.y) - s * 0.5, s, s, rgba(p.color, a));
		}
	},
	drawLight(g) {
		if (g.fullBright || !g.light.valid) return;
		const L = g.light;
		if (this.lightRev !== g.lightRev) {
			this.lightRev = g.lightRev;
			const smoothL = g.settings.smoothLight;
			if (!this.lightTex || this.lo !== smoothL) {
				if (this.lightTex) { R.freeTex(this.lightTex); R.freeTex(this.glowTex); }
				this.lightTex = R.makeTex(L.w, L.h, g.lightDark, smoothL);
				this.glowTex = R.makeTex(L.w, L.h, g.lightGlow, smoothL);
				this.lo = smoothL;
			} else {
				R.updateTex(this.lightTex, L.w, L.h, g.lightDark);
				R.updateTex(this.glowTex, L.w, L.h, g.lightGlow);
			}
			this.lx = L.ox; this.ly = L.oy; this.lw = L.w; this.lh = L.h;
		}
		const x = View.sx(this.lx), y = View.sy(this.ly), w = this.lw * View.tp, h = this.lh * View.tp;
		// half a texel in, so a smoothed light lines up with the blocks
		const hu = 0.5 / this.lw, hv = 0.5 / this.lh;
		const sx = this.lo ? x + View.tp * 0.5 : x, sy = this.lo ? y + View.tp * 0.5 : y, sw = this.lo ? w - View.tp : w, sh = this.lo ? h - View.tp : h;
		const u0 = this.lo ? hu : 0, v0 = this.lo ? hv : 0, u1 = this.lo ? 1 - hu : 1, v1 = this.lo ? 1 - hv : 1;
		R.blend(1);
		R.img(this.glowTex, sx, sy, sw, sh, u0, v0, u1, v1);
		R.blend(0);
		R.img(this.lightTex, sx, sy, sw, sh, u0, v0, u1, v1);
	},
	drawOverlays(g, W, H) {
		const tp = View.tp, dpr = R.dpr;
		if (g.mining && g.mineP > 0) {
			const f = clampD(g.mineP / Math.max(0.01, g.mineNeed), 0, 0.999);
			const x = View.sx(g.mineX), y = View.sy(g.mineY);
			R.rect(x, y, tp, tp, rgba(0, 0.12 + f * 0.25));
			// cracks spreading from the middle as the block gives
			const c = rgba(0x140E0A, 0.85), u = tp / 16;
			const n = 1 + Math.floor(f * 5);
			const lines = [[8, 8, 3, 2], [8, 8, 13, 4], [8, 8, 5, 13], [8, 8, 14, 12], [3, 2, 1, 7], [13, 4, 15, 1]];
			for (let i = 0; i < Math.min(n, lines.length); i++) { const l = lines[i]; R.line(x + l[0] * u, y + l[1] * u, x + l[2] * u, y + l[3] * u, Math.max(1, u), c); }
		}
		const aiming = g.useHeld || g.pendingInteract;
		const held = g.heldItem;
		const ht = held ? itemTile(held) : -1;
		if (g.aimValid && !g.dead && ht >= 0 && ht !== T.doorClosed) {
			const tx = Math.floor(g.aimX), ty = Math.floor(g.aimY);
			const ok = g.canPlaceAt(tx, ty, placedForm(ht));
			const r = iconRect(held);
			R.sprite(r[0], r[1], r[2], r[3], View.sx(tx), View.sy(ty), tp, tp, rgba(0xFFFFFF, ok ? 0.5 : 0.28));
			R.frame(View.sx(tx), View.sy(ty), tp, tp, 2 * dpr, ok ? rgba(0x70E080, 0.9) : rgba(0xFF5050, 0.75));
		} else if (g.aimValid && !g.dead && aiming && !(held && isWeaponItem(held))) {
			const tx = Math.floor(g.aimX), ty = Math.floor(g.aimY);
			R.frame(View.sx(tx), View.sy(ty), tp, tp, 2 * dpr, g.inReach(g.aimX, g.aimY) ? rgba(0xFFFFFF, 0.8) : rgba(0xFF5050, 0.6));
		}
		overlayHooks.forEach((f) => f(g, W, H));
		const pb = g.pb;
		if (g.world.tile(Math.floor(pb.x), Math.floor(pb.y - pb.h * 0.9)) === T.water) R.rect(0, 0, W, H, rgba(0x1A4AA0, 0.28));
		if (pb.inLava) this.vignette(W, H, 0xFF5010, 0.55);
		if (g.hurtT > 0) this.vignette(W, H, 0xC01818, Math.min(0.6, g.hurtT * 0.9));
		if (!g.dead && g.hp < g.maxHP * 0.25 && g.mode !== GameMode.creative) this.vignette(W, H, 0x900E0E, 0.18 + 0.14 * (0.5 + 0.5 * Math.sin(g.clock * 2.4)));
		if (g.fadeT > 0) R.rect(0, 0, W, H, rgba(0x0A2A30, Math.min(1, g.fadeT)));
	},
	/** darkens or tints the screen edges, fading to nothing toward the middle */
	vignette(W, H, c, a) {
		const band = Math.min(W, H) * 0.24, on = rgba(c, a), off = rgba(c, 0);
		R.grad(0, 0, W, band, on, off);
		R.grad(0, H - band, W, band, off, on);
		R.gradH(0, 0, band, H, on, off);
		R.gradH(W - band, 0, band, H, off, on);
	},
};
// later phases draw creatures, vehicles, weather and the rest through these
const drawHooksBack = [], drawHooksMid = [], drawHooksFront = [], overlayHooks = [], skyHooks = [];
