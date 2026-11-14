// Starting up and the frame loop.

const Loop = {
	last: 0, fps: 60, frames: 0,
	frame(t) {
		requestAnimationFrame((tt) => Loop.frame(tt));
		const dt = Loop.last ? (t - Loop.last) / 1000 : 1 / 60;
		Loop.last = t;
		Loop.frames++;
		if (dt > 0) Loop.fps = Loop.fps * 0.95 + Math.min(240, 1 / dt) * 0.05;
		const g = UI.game;
		if (!g) { R.begin(0.04, 0.06, 0.1); R.end(); return; }
		g.viewW = window.innerWidth; g.viewH = window.innerHeight;
		try {
			if (Stress.running) Stress.update(dt);
			if (!UI.panelOpen && !g.paused) g.applyActButton();
			g.tick(dt);
			HUD.update(g);
			if (UI.panelOpen === "inventory") renderPanel();
			if (g.dead && !UI.panelOpen) showDeath(g);
			Renderer.draw(g);
		} catch (e) {
			Loop.fail(e);
		}
	},
	failed: false,
	fail(e) {
		if (this.failed) return;
		this.failed = true;
		console.error(e);
		const g = UI.game;
		if (g) g.say("Something went wrong: " + (e && e.message ? e.message : e), 8);
		setTimeout(() => { this.failed = false; }, 4000);
	},
};

async function boot() {
	const canvas = $("world");
	try {
		if (!R.init(canvas)) { $("loading").textContent = "This device cannot show WebGL 2, which the game needs."; return; }
	} catch (e) { $("loading").textContent = "The renderer could not start: " + e.message; return; }
	R.resize();
	window.addEventListener("resize", () => { R.resize(); UI.hudKey = ""; });
	try { await loadAtlas(); } catch (e) { $("loading").textContent = "The art could not be read: " + e.message; return; }
	Painter.init();
	Menu.settings = SettingsStore.load();
	applySettings(Menu.settings);
	HUD.init();
	initPanels();
	Menu.init();
	Store.init().then(() => { if (!UI.game && Menu.page === "main") Menu.refreshWorlds(); });
	$("loading").classList.add("hidden");
	Menu.show("main");
	requestAnimationFrame((t) => Loop.frame(t));
	// leaving the page saves the world
	document.addEventListener("visibilitychange", () => { if (document.hidden && UI.game && UI.game.settings.autosave) saveGameSoon(UI.game); });
}
boot();
