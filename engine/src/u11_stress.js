// The stress test (from the title screen): a throwaway creative world pushed step by step (standing, flying
// fast through new land, digging out a big hole, the widest view), measuring each step. Later phases add
// their own steps (creatures, liquids, machines, vehicles) to STRESS_STEPS.

const STRESS_STEPS = [
	{ name: "Standing still", secs: 3, start(g) {}, run(g, dt) {} },
	{ name: "Flying through new land (40 blocks a second)", secs: 6, start(g) { g.noclip = true; }, run(g, dt) { g.pb.x += 40 * dt; } },
	{ name: "Digging out 3,000 blocks", secs: 4, start(g) { g.noclip = true; Stress.dug = 0; }, run(g, dt) {
		const w = g.world, px = Math.floor(g.pb.x), py = Math.floor(g.pb.y);
		for (let k = 0; k < 40 && Stress.dug < 3000; k++, Stress.dug++) { const i = Stress.dug; w.set(px - 30 + (i % 60), py + 2 + Math.floor(i / 60), T.air); }
	} },
	{ name: "Torches everywhere (light)", secs: 3, start(g) {
		const w = g.world, px = Math.floor(g.pb.x), py = Math.floor(g.pb.y);
		for (let i = 0; i < 120; i++) w.set(px - 30 + (i % 30) * 2, py + 4 + Math.floor(i / 30) * 6, T.torch);
	}, run(g, dt) {} },
	{ name: "Widest view (12 pixels a block)", secs: 4, start(g) { g.tilePx = 12; }, run(g, dt) { g.pb.x += 10 * dt; } },
	{ name: "300 monsters after you", secs: 6, start(g) {
		g.tilePx = g.settings.tilePx; g.noclip = false; g.mobs = []; g.noSpawning = true;
		g.pb.y = g.world.surfaceY(Math.floor(g.pb.x));
		const kinds = ["zombie", "skeleton", "crawler", "slime", "archer", "bat"];
		for (let i = 0; i < 300; i++) { const x = g.pb.x + rand(-45, 45); const m = g.addMob(kinds[i % kinds.length], x, g.world.surfaceY(Math.floor(x)) - (kinds[i % kinds.length] === "bat" ? 3 : 0)); m.persistent = true; }
	}, run(g, dt) {} },
	{ name: "2,000 animals", secs: 6, start(g) {
		g.mobs = [];
		const kinds = ["pig", "cow", "sheep", "chicken", "wolf", "crow"];
		for (let i = 0; i < 2000; i++) { const x = g.pb.x + rand(-60, 60); const m = g.addMob(kinds[i % kinds.length], x, g.world.surfaceY(Math.floor(x)) - (kinds[i % kinds.length] === "crow" ? 4 : 0)); m.persistent = true; }
	}, run(g, dt) {} },
];

const Stress = {
	running: false, step: 0, t: 0, frames: 0, worst: 0, results: [], g: null, dug: 0, gen0: 0,
	start() {
		const s = Object.assign({}, Menu.settings, { autosave: false });
		const g = new Game(GameMode.creative, true, 20240611, s, GEN_VERSION, null, true);
		g.isTest = true; g.worldName = "Stress test";
		this.g = g; this.running = true; this.step = -1; this.results = [];
		startGame(g);
		this.next();
	},
	next() {
		const g = this.g;
		if (this.step >= 0) {
			const st = STRESS_STEPS[this.step];
			this.results.push({ name: st.name, fps: this.frames / Math.max(0.001, this.t), worst: this.worst * 1000, chunks: PERF.chunksGenerated - this.gen0, gen: PERF.genMs, light: PERF.lightMs, draw: PERF.renderMs, tick: g.tickMs });
		}
		this.step++;
		if (this.step >= STRESS_STEPS.length) { this.finish(); return; }
		this.t = 0; this.frames = 0; this.worst = 0; this.gen0 = PERF.chunksGenerated;
		STRESS_STEPS[this.step].start(g);
		g.say("Stress test " + (this.step + 1) + "/" + STRESS_STEPS.length + ": " + STRESS_STEPS[this.step].name, STRESS_STEPS[this.step].secs);
	},
	update(dt) {
		if (!this.running || UI.game !== this.g) { this.running = false; return; }
		this.t += dt; this.frames++;
		if (this.t > 0.3) this.worst = Math.max(this.worst, dt);
		STRESS_STEPS[this.step].run(this.g, dt);
		if (this.t >= STRESS_STEPS[this.step].secs) this.next();
	},
	finish() {
		this.running = false;
		const gl = R.gl;
		let gpu = "";
		try { const ext = gl.getExtension("WEBGL_debug_renderer_info"); gpu = ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER); } catch (e) {}
		const lines = ["PixelRealm web, phase 2 stress test"];
		for (const r of this.results) lines.push(r.name + ": " + Math.round(r.fps) + " fps (slowest frame " + Math.round(r.worst) + " ms)" + (r.chunks ? ", " + r.chunks + " chunks made at " + r.gen.toFixed(1) + " ms each" : "") + ", light " + r.light.toFixed(1) + " ms, game " + r.tick.toFixed(1) + " ms");
		lines.push("Screen " + window.innerWidth + "x" + window.innerHeight + " at " + R.dpr + "x, GPU " + gpu + ", largest texture " + gl.getParameter(gl.MAX_TEXTURE_SIZE));
		Stress.report = lines.join("\n");
		quitToMenu(false).then(() => { Menu.page = "stress"; Menu.render(); });
	},
};
