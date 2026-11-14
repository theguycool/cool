// Drawing creatures and fighting (the Swift game's drawMobs, mobFrame, drawProjectiles and the slash
// trails): every creature from its hand-drawn frames, turning, lunging, breathing, flashing when hit
// and toppling when it dies; shots in flight; the player's swings; telegraphed blows; health bars.

/** a creature's frames and how they are used (its variant's art) */
function mobLook(m) {
	const d = m.def, v = d.variants[Math.min(m.variant, d.variants.length - 1)] || d.variants[0];
	return v;
}
const pose = (an, name, fallback) => (an.poses && an.poses[name] !== undefined) ? an.poses[name] : fallback;
function walkFrame(an, t) {
	const w = an.walk;
	if (!w || !w.length) return 0;
	const rate = w.length > 2 ? w.length : 2;
	return w[Math.floor(Math.abs(t) * rate) % w.length];
}
function idleVariant(m, clock) { return ((clock * 0.22 + (m.id % 97) * 0.137) % 1) > 0.74; }
/** which frame a creature shows for what it is doing */
function mobFrame(m, an, clock) {
	const moving = Math.abs(m.b.vx) > 0.3;
	if (isHumanoid(m.kind)) {
		if (m.st === 3) return (m.kind === "pirateGunner" || m.kind === "imp" || m.kind === "archer") ? pose(an, "shoot", 6) : pose(an, "windup", 3);
		if (m.st === 4) return pose(an, "strike", 4);
		if (m.st === 6) return pose(an, "fire", pose(an, "shoot", 6));
		if (m.blocking) return pose(an, "block", 5);
		if (m.atkT > 0 && (m.kind === "zombie" || m.kind === "imp")) return pose(an, "strike", 4);
		return moving ? walkFrame(an, m.anim) : 0;
	}
	switch (m.kind) {
		case "golem":
			if (m.st === 3) return pose(an, "windup", 3);
			if (m.st === 4) return pose(an, "strike", 4);
			if (m.st === 5) return pose(an, "throw", 5);
			return moving ? walkFrame(an, m.anim) : 0;
		case "mimic":
			if (m.st === 3 || m.st === 4) return 3;
			if (!m.b.onGround) return 1 + Math.floor(m.anim * 6) % 2;
			return m.angry ? 1 : 0;
		case "sentinel": case "warden": case "bearBoss": case "rex":
			return moving ? walkFrame(an, m.anim) : Math.floor(m.anim * 1.2) % 2;
	}
	if (an.attack >= 0 && m.atkT > 0) return an.attack;
	if (an.hop) return m.b.onGround ? 0 : an.hopFrame;
	if (an.cycle && an.cycle.length) return an.cycle[Math.floor(m.anim * 1.5) % an.cycle.length];
	if (moving) return walkFrame(an, m.anim);
	if (an.idleAlt >= 0 && m.b.onGround && (m.poseT > 0 || idleVariant(m, clock))) return an.idleAlt;
	return 0;
}

const MobDraw = {
	draw(g) {
		const tp = View.tp, dpr = R.dpr;
		if (g.dangerZones && g.dangerZones.length) this.dangerZones(g);
		for (const m of g.mobs) {
			const dying = m.hp <= 0 && !m.downed;
			if (dying && (m.deathT < 0 || m.removed)) continue;
			if (m.b.x < View.left - 8 - m.b.w || m.b.x > View.left + View.wT + 8 + m.b.w || m.b.y < View.top - 4 || m.b.y - m.b.h > View.top + View.hT + 4) continue;
			const an = mobLook(m);
			const rects = DATA.atlas.rects["mob:" + m.kind + ":" + Math.min(m.variant, m.def.variants.length - 1)];
			if (!rects) continue;
			let left = m.dir < 0, scaleX = 1;
			if (m.turnT > 0 && !dying) {
				const p = 1 - m.turnT / MOB_TURN;
				scaleX = Math.max(0.2, Math.abs(1 - 2 * p));
				if (p < 0.5) left = m.face < 0;
			}
			let drawX = m.b.x;
			if (m.atkT > 0 && !dying && !isBossMob(m)) drawX += m.dir * 0.18 * Math.sin((1 - m.atkT / MOB_ATK) * Math.PI);
			let alpha = m.kind === "wraith" ? 0.82 : 1;
			if (m.downed) alpha = 0.55;
			const shade = Renderer.openShade(g, m.b.x, mobCY(m));
			let rot = m.lean * 0.22, squash = 1;
			if (Math.abs(m.b.vx) < 0.3 && m.b.onGround && !dying) squash = 1 + 0.022 * Math.sin(g.clock * 2.6 + (m.id % 17));
			if (dying) {
				const t = m.deathT;
				if (m.kind === "slime" || m.kind === "emberSlime" || m.def.flying || m.kind === "fish") squash = Math.max(0.2, 1 - t * 1.1);
				else { const f = Math.min(1, t / 0.4); rot = (m.dir > 0 ? -1 : 1) * f * f * 1.45; }
				alpha *= clampD(1 - (t - 0.3) / 0.4, 0, 1);
			}
			const flash = m.flash > 0 || (dying && m.deathT < 0.08);
			const fr = Math.min(mobFrame(m, an, g.clock), rects.length - 1);
			const r = rects[Math.max(0, fr)];
			const scale = an.scale * (m.mutSize || 1);
			this.sprite(r, an.centerCol, an.footRow + 1, scale, drawX, m.b.y, left, Renderer.shadeCol(shade, alpha), flash ? 1 : 0, rot, squash, scaleX);
			if (dying) continue;
			if (m.burn > 0) R.rect(View.sx(bodyLeft(m.b)), View.sy(bodyTop(m.b) + m.b.h * 0.3), m.b.w * tp, m.b.h * 0.7 * tp, rgba(0xFF7020, 0.25 + 0.15 * Math.sin(g.clock * 20)));
			if (m.daze > 0) {
				for (let k = 0; k < 3; k++) {
					const a = g.clock * 6 + k * 2.094, sx = m.b.x + Math.cos(a) * Math.max(0.45, m.b.w * 0.45), sy = bodyTop(m.b) - 0.25 + Math.sin(a) * 0.12;
					const sz = Math.max(3 * dpr, tp * 0.14);
					R.rect(View.sx(sx) - sz * 0.5, View.sy(sy) - sz * 0.5, sz, sz, rgba(k === 1 ? 0xFFFFFF : 0xFFE060));
				}
			}
			if (m.tame) R.oval(View.sx(m.b.x) - 4 * dpr, View.sy(bodyTop(m.b)) - 14 * dpr, 8 * dpr, 8 * dpr, rgba(0xFF5A7A));
			if (!isBossMob(m) && m.hp < m.maxHP && m.hp > 0) {
				const w = Math.max(0.9, m.b.w), bx = m.b.x - w * 0.5, by = bodyTop(m.b) - 0.45;
				R.rect(View.sx(bx), View.sy(by), w * tp, Math.max(2 * dpr, 0.14 * tp), rgba(0, 0.7));
				R.rect(View.sx(bx), View.sy(by), w * tp * (m.hp / m.maxHP), Math.max(2 * dpr, 0.14 * tp), rgba(m.tame ? 0x50E070 : 0xE04040));
			}
		}
	},
	/** one frame from the atlas standing at (x, y) by its anchor column and foot row */
	sprite(r, cx, foot, scale, x, y, left, col, add, rot = 0, squash = 1, scaleX = 1) {
		const px = scale * View.tp;
		if (Math.abs(rot) < 0.01 && Math.abs(squash - 1) < 0.004 && scaleX > 0.999) {
			const cc = left ? r[2] - cx : cx, snap = Math.max(1, px);
			const dx = Math.round((View.sx(x) - cc * px) / snap) * snap, dy = Math.round((View.sy(y) - foot * px) / snap) * snap;
			R.sprite(r[0], r[1], r[2], r[3], dx, dy, r[2] * px, r[3] * px, col, left, add);
			return;
		}
		R.push();
		R.translate(View.sx(x), View.sy(y));
		if (rot) R.rotate(rot);
		R.scale((left ? -1 : 1) * scaleX * (1 + (1 - squash) * 0.5), squash);
		R.sprite(r[0], r[1], r[2], r[3], -cx * px, -foot * px, r[2] * px, r[3] * px, col, false, add);
		R.pop();
	},
	dangerZones(g) {
		for (const z of g.dangerZones) {
			const p = clampD(1 - z.t / z.dur, 0, 1), pulse = 0.5 + 0.5 * Math.sin(g.clock * (10 + 14 * p));
			const x = View.sx(z.x0), y = View.sy(z.y0), w = (z.x1 - z.x0) * View.tp, h = (z.y1 - z.y0) * View.tp;
			R.rect(x, y, w, h, rgba(z.color, 0.08 + 0.08 * pulse));
			R.rect(x, y + h * (1 - p), w, h * p, rgba(z.color, 0.2));
			R.frame(x, y, w, h, 2 * R.dpr, rgba(z.color, 0.5 + 0.3 * pulse));
		}
	},
	projectiles(g) {
		const tp = View.tp, dpr = R.dpr;
		for (const p of g.projectiles) {
			if (p.x < View.left - 2 || p.x > View.left + View.wT + 2 || p.y < View.top - 2 || p.y > View.top + View.hT + 2) continue;
			const x = View.sx(p.x), y = View.sy(p.y);
			const ang = p.stuck > 0 ? p.stuckAngle : Math.atan2(p.vy, p.vx), dx = Math.cos(ang), dy = Math.sin(ang);
			switch (p.kind) {
				case "arrow": case "quarrel": {
					const L = p.kind === "arrow" ? 0.42 : 0.32, hx = dx * tp * L, hy = dy * tp * L, lw = Math.max(2 * dpr, tp / (p.kind === "arrow" ? 11 : 9));
					if (p.stuck <= 0 && (p.trail > 0 || p.kind === "quarrel")) R.line(x - hx - dx * tp * 0.8, y - hy - dy * tp * 0.8, x - hx, y - hy, lw, rgba(0xFFFFFF, 0.18));
					R.line(x - hx, y - hy, x + hx, y + hy, lw, rgba(p.kind === "arrow" ? 0x8A5A2A : 0x6A4A26));
					R.line(x + hx * 0.6, y + hy * 0.6, x + hx * 1.08, y + hy * 1.08, lw + dpr, rgba(p.kind === "arrow" ? 0xD0D0D8 : 0xC89040));
					if (p.kind === "arrow") { const nx = -dy * tp * 0.12, ny = dx * tp * 0.12; R.line(x - hx, y - hy, x - hx * 0.6 + nx, y - hy * 0.6 + ny, lw, rgba(0xE8E0D0)); R.line(x - hx, y - hy, x - hx * 0.6 - nx, y - hy * 0.6 - ny, lw, rgba(0xE8E0D0)); }
					break;
				}
				case "bullet": R.line(x - dx * tp * 0.6, y - dy * tp * 0.6, x, y, 2 * dpr, rgba(0xFFE8A0, 0.4)); R.rect(x - 2 * dpr, y - 2 * dpr, 4 * dpr, 4 * dpr, rgba(0xFFF2C0)); break;
				case "pellet": R.line(x - dx * tp * 0.5, y - dy * tp * 0.5, x, y, 2 * dpr, rgba(0xFFE8A0, 0.35)); R.rect(x - 1.5 * dpr, y - 1.5 * dpr, 3 * dpr, 3 * dpr, rgba(0xFFF2C0)); break;
				case "pebble": case "rock": {
					const sz = Math.max(4 * dpr, p.w * tp), h = sz * 0.5;
					R.rect(x - h, y - h, sz, sz, rgba(0x8A8A8A)); R.rect(x - h, y - h, sz * 0.5, sz * 0.45, rgba(0xB0B0B0));
					break;
				}
				case "fireball": {
					const r = tp * 0.3 * (0.9 + 0.1 * Math.sin(g.clock * 30));
					R.oval(x - r * 1.6, y - r * 1.6, r * 3.2, r * 3.2, rgba(0xFF7020, 0.25));
					R.oval(x - r, y - r, r * 2, r * 2, rgba(0xFF9A30));
					R.oval(x - r * 0.5, y - r * 0.5, r, r, rgba(0xFFE8A0));
					break;
				}
				case "bomb": {
					const r = tp * 0.22;
					R.oval(x - r, y - r, r * 2, r * 2, rgba(0x2A2A30));
					R.oval(x - r * 0.5, y - r * 0.7, r * 0.6, r * 0.6, rgba(0x6A6A78));
					if (Math.floor(p.life * 12) % 2 === 0) R.rect(x + r * 0.2, y - r * 1.6, 3 * dpr, 3 * dpr, rgba(0xFFD040));
					break;
				}
				case "shock": R.rect(x - tp * 0.4, y - tp * 0.15, tp * 0.8, tp * 0.3, rgba(0xA08860, 0.5)); break;
			}
		}
	},
	slashes(g) {
		if (!g.slashes) return;
		const tp = View.tp, dpr = R.dpr;
		for (const s of g.slashes) {
			const a = clampD(s.life / s.maxLife, 0, 1), col = rgba(artGrade(s.color), 0.55 * a), x = View.sx(s.x), y = View.sy(s.y), r = s.reach * tp;
			if (s.style === "thrust" || s.style === "stab") {
				const dx = Math.cos(s.ang), dy = Math.sin(s.ang);
				R.line(x + dx * r * 0.3, y + dy * r * 0.3, x + dx * r, y + dy * r, Math.max(3 * dpr, tp * 0.14), col);
				continue;
			}
			const n = 9, a0 = s.ang - s.halfArc, a1 = s.ang + s.halfArc;
			const sweep = 1 - a;
			for (let i = 0; i < n; i++) {
				const t0 = i / n, t1 = (i + 1) / n;
				if (t1 > sweep + 0.6) break;
				const b0 = a0 + (a1 - a0) * t0, b1 = a0 + (a1 - a0) * t1, rr = r * 0.92;
				R.line(x + Math.cos(b0) * rr, y + Math.sin(b0) * rr, x + Math.cos(b1) * rr, y + Math.sin(b1) * rr, Math.max(2 * dpr, tp * 0.12 * (1 - Math.abs(t0 - 0.5))), col);
			}
		}
	},
	/** the dotted flight of a drawn bow (or a sling, a crossbow, a bomb) */
	aimArc(g) {
		const pts = g.arrowPreview();
		if (!pts) return;
		const s = Math.max(3, View.tp * 0.12);
		for (let i = 0; i < pts.length; i += 2) {
			const a = 0.75 * (1 - i / pts.length);
			R.rect(View.sx(pts[i]) - s * 0.5, View.sy(pts[i + 1]) - s * 0.5, s, s, rgba(0xFFFFFF, a));
		}
	},
	muzzle(g) {
		if (!(g.muzzleT > 0)) return;
		const x = View.sx(g.pb.x + g.facing * 0.9), y = View.sy(g.pb.y - 1.2), r = View.tp * 0.3;
		R.oval(x - r, y - r, r * 2, r * 2, rgba(0xFFE080, 0.8));
	},
};
drawHooksMid.push((g) => MobDraw.draw(g));
drawHooksFront.push((g) => { MobDraw.projectiles(g); MobDraw.slashes(g); MobDraw.muzzle(g); MobDraw.aimArc(g); });
