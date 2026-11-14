// The title screen (the Swift game's u05_menu): new worlds, saved worlds, importing a world file, and
// settings.

const Menu = {
	page: "main", worlds: [], sure: null, form: null, busy: false, note: "",
	init() {
		const el = $("menu");
		el.addEventListener("click", (e) => this.click(e));
		el.addEventListener("input", (e) => this.input(e));
		el.addEventListener("change", (e) => this.change(e));
	},
	show(page = "main") {
		this.page = page; this.sure = null;
		$("menu").classList.remove("hidden");
		HUD.show(false);
		if (page === "main" || page === "load") this.refreshWorlds();
		this.render();
	},
	hide() { $("menu").classList.add("hidden"); },
	async refreshWorlds() {
		try { this.worlds = await Store.list(); } catch (e) { this.worlds = []; }
		this.render();
	},
	newForm() { return { name: "My World", seed: "", mode: GameMode.survival, infinite: true, flat: false, trees: true, structures: true }; },
	render() {
		const el = $("menu");
		let h = "";
		if (this.page === "main") {
			h = '<div class="box"><div class="scroll"><div class="logo">PixelRealm</div><div class="sub">Dig, build and survive</div><div class="col">' +
				'<button data-act="new" class="primary">NEW WORLD</button>' +
				'<button data-act="load"' + (this.worlds.length ? "" : " disabled") + '>PLAY A SAVED WORLD' + (this.worlds.length ? " (" + this.worlds.length + ")" : "") + "</button>" +
				'<button data-act="import">OPEN A WORLD FILE</button><button data-act="settings">SETTINGS</button><button data-act="stress">STRESS TEST</button></div>' +
				'<div class="note">Worlds are saved to ' + Store.where + ".<br>Version 2 · phase 2 of the web edition</div></div></div>";
		} else if (this.page === "new") {
			const f = this.form || (this.form = this.newForm());
			const pick = (k, opts) => '<div class="choice">' + opts.map(([v, n]) => '<button data-pick="' + k + '" data-v="' + v + '" class="' + (String(f[k]) === String(v) ? "on" : "") + '">' + n + "</button>").join("") + "</div>";
			h = '<div class="box"><div class="top"><span class="title">New world</span><button data-act="back">BACK</button></div><div class="scroll">' +
				'<div class="field"><label>Name</label><input data-f="name" value="' + escapeHTML(f.name) + '" maxlength="40"></div>' +
				'<div class="field"><label>Seed (empty for a random one)</label><input data-f="seed" value="' + escapeHTML(f.seed) + '" maxlength="30"></div>' +
				'<div class="field"><label>Mode</label>' + pick("mode", [[0, "SURVIVAL"], [1, "CREATIVE"], [2, "HARDCORE"]]) + "</div>" +
				'<div class="field"><label>Size</label>' + pick("infinite", [[true, "ENDLESS"], [false, "SMALL (" + FINITE_WIDTH + " WIDE)"]]) + "</div>" +
				'<div class="field"><label>Land</label>' + pick("flat", [[false, "NORMAL"], [true, "FLAT"]]) + "</div>" +
				(f.flat ? '<div class="field"><label>Flat world</label>' + pick("trees", [[true, "TREES"], [false, "NO TREES"]]) + "</div>" : "") +
				'<div class="note">' + ["You gather, build and get hungry.", "Every block is yours, nothing hurts.", "One life: the world is lost if you die."][f.mode] + "</div>" +
				'<div class="col"><button data-act="create" class="primary">CREATE</button></div><div class="note" id="mnote">' + escapeHTML(this.note) + "</div></div></div>";
		} else if (this.page === "load") {
			h = '<div class="box"><div class="top"><span class="title">Saved worlds</span><button data-act="back">BACK</button></div><div class="scroll">';
			if (!this.worlds.length) h += '<div class="note">No saved worlds yet.</div>';
			for (const w of this.worlds) {
				const when = w.saved ? new Date(w.saved).toLocaleString() : "";
				h += '<div class="world"><div class="nm"><b>' + escapeHTML(w.name) + "</b><div>" + MODE_NAMES[w.mode || 0] + " · day " + (w.day || 1) + " · " + Math.ceil((w.size || 0) / 1024) + " KB · " + when + (w.local ? " · this browser" : "") + "</div></div>" +
					'<button data-play="' + w.id + '" class="primary">PLAY</button><button data-del="' + w.id + '" class="warn">' + (this.sure === w.id ? "SURE?" : "DELETE") + "</button></div>";
			}
			h += '<div class="note" id="mnote">' + escapeHTML(this.note) + "</div></div></div>";
		} else if (this.page === "import") {
			h = '<div class="box"><div class="top"><span class="title">Open a world file</span><button data-act="back">BACK</button></div><div class="scroll">' +
				'<div class="field"><label>A world file you exported (.txt)</label><input type="file" id="mfile" accept=".txt,.json,text/plain"></div>' +
				'<div class="field"><label>Or paste its text</label><textarea id="mtext" rows="5" style="font-family:var(--font);font-size:13px;background:#10141f;color:var(--text);border:2px solid var(--edge);border-radius:6px;padding:8px"></textarea></div>' +
				'<div class="col"><button data-act="doimport" class="primary">OPEN</button></div><div class="note" id="mnote">' + escapeHTML(this.note) + "</div></div></div>";
		} else if (this.page === "stress") {
			h = '<div class="box"><div class="top"><span class="title">Stress test results</span><button data-act="back">BACK</button></div><div class="scroll">' +
				'<pre style="white-space:pre-wrap;font-family:var(--font);font-size:14px;line-height:1.5;margin:0;user-select:text;-webkit-user-select:text">' + escapeHTML(Stress.report || "") + "</pre>" +
				'<div class="note">Select the text to copy it, or run it again.</div><div class="col"><button data-act="stress">RUN AGAIN</button></div></div></div>';
		} else if (this.page === "settings") {
			h = '<div class="box">' + settingsTop("back") + '<div class="scroll">' + settingsHTML(Menu.settings) + "</div></div>";
		}
		el.innerHTML = h;
	},
	say(s) { this.note = s; const n = $("mnote"); if (n) n.textContent = s; },
	async click(e) {
		const t = e.target.closest("[data-act],[data-pick],[data-play],[data-del],[data-toggle]");
		if (!t || this.busy) return;
		Sound.unlock();
		const ds = t.dataset;
		if (ds.toggle) { onSettingsToggle(Menu.settings, ds.toggle); this.render(); return; }
		if (ds.pick) {
			const f = this.form, v = ds.v;
			f[ds.pick] = v === "true" ? true : v === "false" ? false : +v;
			this.render();
			return;
		}
		if (ds.play) {
			this.busy = true; this.say("Loading…");
			try { const g = await loadGameByID(ds.play, Menu.settings); startGame(g); }
			catch (err) { this.say("Could not open it: " + err.message); }
			this.busy = false;
			return;
		}
		if (ds.del) {
			if (this.sure !== ds.del) { this.sure = ds.del; this.render(); return; }
			const w = this.worlds.find((o) => o.id === ds.del);
			this.sure = null;
			if (w) { this.busy = true; await Store.remove(w); this.busy = false; }
			await this.refreshWorlds();
			if (!this.worlds.length) this.show("main");
			return;
		}
		switch (ds.act) {
			case "new": this.form = this.newForm(); this.note = ""; this.page = "new"; this.render(); break;
			case "load": this.note = ""; this.show("load"); break;
			case "import": this.note = ""; this.page = "import"; this.render(); break;
			case "settings": this.page = "settings"; this.render(); break;
			case "back": this.show("main"); break;
			case "create": this.create(); break;
			case "doimport": this.doImport(); break;
			case "stress": Stress.start(); break;
		}
	},
	input(e) {
		const k = e.target.dataset.f;
		if (k && this.form) { this.form[k] = e.target.value; return; }
		if (e.target.dataset.set) {
			const s = Menu.settings, key = e.target.dataset.set;
			s[key] = +e.target.value;
			const lab = document.getElementById("sv_" + key);
			const row = SETTING_ROWS.find((r) => r[0] === key);
			if (lab) lab.textContent = (+s[key]).toFixed(row && row[5] >= 1 ? 0 : 2);
			SettingsStore.save(s); applySettings(s);
		}
	},
	async change(e) {
		if (e.target.id !== "mfile" || !e.target.files || !e.target.files[0]) return;
		try { $("mtext").value = (await e.target.files[0].text()).trim(); this.say("Read " + e.target.files[0].name + ". Tap OPEN."); }
		catch (err) { this.say("Could not read that file."); }
	},
	async create() {
		const f = this.form;
		let seed = f.seed.trim();
		let sv;
		if (!seed) sv = Math.floor(Math.random() * 4294967295) >>> 0;
		else if (/^-?\d+$/.test(seed)) sv = (+seed) >>> 0;
		else { sv = 2166136261; for (let i = 0; i < seed.length; i++) sv = Math.imul(sv ^ seed.charCodeAt(i), 16777619) >>> 0; }
		this.busy = true; this.say("Making the world…");
		await new Promise((r) => setTimeout(r, 30));
		try {
			const opts = f.flat ? { flat: true, trees: f.trees, structures: f.structures } : null;
			const g = new Game(f.mode, f.infinite, sv, Menu.settings, GEN_VERSION, opts, true);
			g.worldName = (f.name || "My World").trim().slice(0, 40) || "My World";
			g.slot = newWorldID();
			startGame(g);
			saveGameSoon(g);
		} catch (err) { this.say("Could not make it: " + err.message); }
		this.busy = false;
	},
	async doImport() {
		const text = ($("mtext") || {}).value || "";
		if (!text.trim()) { this.say("Choose a file or paste its text first."); return; }
		this.busy = true; this.say("Opening…");
		try { const g = await importWorld(text, Menu.settings); startGame(g); }
		catch (err) { this.say("Could not open it: " + err.message); }
		this.busy = false;
	},
};

function startGame(g) {
	UI.game = g;
	UI.hudKey = ""; UI.panelOpen = null;
	g.settings = Menu.settings;
	applySettings(g.settings);
	Menu.hide();
	$("death").classList.add("hidden");
	$("pause").classList.add("hidden");
	$("panel").classList.add("hidden");
	HUD.show(true);
	Loop.last = 0;
	if (g.dead) showDeath(g);
}
async function quitToMenu(save) {
	const g = UI.game;
	releaseAllInput();
	if (g && save && !(g.mode === GameMode.hardcore && g.hardcoreOver)) {
		const n = $("pnote");
		if (n) n.textContent = "Saving…";
		try { await saveGame(g); } catch (e) { if (n) n.textContent = "Could not save: " + e.message; return; }
	}
	if (g && g.mode === GameMode.hardcore && g.hardcoreOver && g.slot) { try { await Store.remove({ id: g.slot }); } catch (e) {} }
	UI.game = null;
	UI.panelOpen = null;
	if (Debug.open) Debug.toggle();
	Debug.selected = null;
	clearSectionCache();
	$("pause").classList.add("hidden"); $("panel").classList.add("hidden"); $("death").classList.add("hidden");
	Menu.show("main");
}
