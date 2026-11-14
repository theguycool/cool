// Sound effects, made as they play with Web Audio (the Swift game makes its own the same way). The
// sound starts on the first touch or key, as browsers ask.

const Sound = {
	ctx: null, out: null, noiseBuf: null, last: new Map(), on: true, volume: 0.8,
	unlock() {
		if (this.ctx) { if (this.ctx.state === "suspended") this.ctx.resume().catch(() => {}); return; }
		const AC = window.AudioContext || window.webkitAudioContext;
		if (!AC) return;
		try {
			this.ctx = new AC();
			this.out = this.ctx.createGain();
			this.out.gain.value = this.volume;
			this.out.connect(this.ctx.destination);
			const n = this.ctx.sampleRate;
			this.noiseBuf = this.ctx.createBuffer(1, n, n);
			const d = this.noiseBuf.getChannelData(0);
			for (let i = 0; i < n; i++) d[i] = Math.random() * 2 - 1;
		} catch (e) { this.ctx = null; }
	},
	setVolume(v) { this.volume = v; if (this.out) this.out.gain.value = v; },
	/** a burst of filtered noise */
	noise(t0, dur, type, freq, q, vol, freqTo = 0) {
		const c = this.ctx, src = c.createBufferSource(), f = c.createBiquadFilter(), g = c.createGain();
		src.buffer = this.noiseBuf;
		f.type = type; f.frequency.setValueAtTime(freq, t0); f.Q.value = q;
		if (freqTo > 0) f.frequency.exponentialRampToValueAtTime(freqTo, t0 + dur);
		g.gain.setValueAtTime(vol, t0);
		g.gain.exponentialRampToValueAtTime(0.001, t0 + dur);
		src.connect(f); f.connect(g); g.connect(this.out);
		src.start(t0, Math.random() * 0.5, dur + 0.05);
	},
	/** a tone that slides from one pitch to another and fades */
	tone(t0, dur, type, f0, f1, vol, attack = 0.004) {
		const c = this.ctx, o = c.createOscillator(), g = c.createGain();
		o.type = type;
		o.frequency.setValueAtTime(f0, t0);
		if (f1 !== f0) o.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t0 + dur);
		g.gain.setValueAtTime(0.0001, t0);
		g.gain.exponentialRampToValueAtTime(vol, t0 + attack);
		g.gain.exponentialRampToValueAtTime(0.001, t0 + dur);
		o.connect(g); g.connect(this.out);
		o.start(t0); o.stop(t0 + dur + 0.05);
	},
	play(name, vol) {
		if (!this.on || !this.ctx || this.ctx.state !== "running") return;
		const now = this.ctx.currentTime;
		const prev = this.last.get(name) || 0;
		if (now - prev < 0.045) return;
		this.last.set(name, now);
		const v = clampD(vol, 0, 1.5), t = now + 0.005, r = 0.92 + Math.random() * 0.16;
		const N = (d, ty, f, q, vv, f2) => this.noise(t, d, ty, f * r, q, vv * v, f2 ? f2 * r : 0);
		const S = (d, ty, a, b, vv, at, dt = 0) => this.tone(t + dt, d, ty, a * r, b * r, vv * v, at);
		switch (name) {
			case "digStone": N(0.07, "bandpass", 2400, 1.2, 0.5); S(0.04, "square", 900, 500, 0.06); break;
			case "digDirt": N(0.09, "lowpass", 700, 0.8, 0.6); break;
			case "digSand": N(0.1, "highpass", 2500, 0.6, 0.25); break;
			case "digWood": N(0.06, "bandpass", 500, 2, 0.5); S(0.07, "triangle", 260, 180, 0.25); break;
			case "digLeaves": N(0.08, "highpass", 3800, 0.5, 0.18); break;
			case "digCrystal": S(0.16, "sine", 1800, 1700, 0.18); S(0.12, "sine", 2700, 2600, 0.1, 0.004, 0.02); break;
			case "breakStone": N(0.22, "bandpass", 1500, 0.9, 0.6, 500); S(0.08, "square", 300, 120, 0.08); break;
			case "breakDirt": N(0.2, "lowpass", 900, 0.7, 0.7, 250); break;
			case "breakWood": N(0.16, "bandpass", 420, 1.5, 0.6, 200); S(0.14, "triangle", 200, 90, 0.3); break;
			case "breakCrystal": for (let i = 0; i < 3; i++) S(0.2, "sine", 1500 + i * 520, 1400 + i * 500, 0.12, 0.004, i * 0.04); break;
			case "place": S(0.08, "sine", 170, 90, 0.5); N(0.05, "lowpass", 1200, 0.7, 0.3); break;
			case "pickup": S(0.07, "square", 660, 660, 0.07); S(0.09, "square", 990, 990, 0.07, 0.004, 0.06); break;
			case "craft": S(0.06, "triangle", 520, 300, 0.3); N(0.05, "bandpass", 1600, 2, 0.3); S(0.06, "triangle", 620, 360, 0.3, 0.004, 0.11); break;
			case "chestOpen": S(0.25, "sawtooth", 110, 160, 0.07, 0.03); N(0.12, "lowpass", 600, 1, 0.3); break;
			case "door": S(0.09, "triangle", 160, 110, 0.4); N(0.07, "bandpass", 700, 1.5, 0.3); break;
			case "swing": case "swingLight": N(0.14, "bandpass", 900, 1.6, 0.25, 2600); break;
			case "swingHeavy": N(0.22, "bandpass", 500, 1.4, 0.35, 1600); break;
			case "hit": N(0.08, "lowpass", 1400, 1, 0.6); S(0.08, "sine", 180, 80, 0.45); break;
			case "hurt": S(0.18, "square", 420, 160, 0.12); N(0.1, "lowpass", 900, 1, 0.3); break;
			case "land": S(0.1, "sine", 120, 50, 0.6); N(0.08, "lowpass", 500, 0.8, 0.4); break;
			case "eat": for (let i = 0; i < 3; i++) this.noise(t + i * 0.09, 0.05, "bandpass", 2000 * r, 1.4, 0.35 * v); break;
			case "splash": N(0.35, "lowpass", 2200, 0.8, 0.5, 300); break;
			case "equip": S(0.06, "square", 300, 300, 0.08); N(0.06, "bandpass", 3000, 2, 0.2); break;
			case "discovery": [523, 659, 784].forEach((f, i) => S(0.3, "triangle", f, f, 0.18, 0.01, i * 0.09)); break;
			case "warn": S(0.3, "square", 220, 220, 0.08, 0.01); break;
			default: S(0.04, "square", 700, 600, 0.06); break;
		}
	},
};
function sfx(name, vol = 1) { Sound.play(name, vol); }
/** the sound of mining a block, by what it is made of */
function digSound(t, broke) {
	const d = TILE[t];
	let m = "Dirt";
	if (IS_LEAF[t] || PLANT[t]) m = "Leaves";
	else if (d.key.includes("crystal") || d.key === "amethyst" || d.key === "glass" || d.key === "ice") m = "Crystal";
	else if (d.toolClass === "pickaxe") m = "Stone";
	else if (d.toolClass === "axe") m = "Wood";
	else if (d.key.includes("sand") || d.key === "gravel" || d.key === "snow") m = "Sand";
	if (broke) sfx(m === "Leaves" ? "digLeaves" : m === "Sand" ? "breakDirt" : "break" + m, 0.7);
	else sfx("dig" + m, 0.45);
}
