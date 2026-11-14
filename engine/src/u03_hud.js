// The HUD and the controls (the Swift game's u03_hud and p14c_input): hearts, food and air, the hotbar,
// the walking stick and JUMP on touch screens, the keyboard and mouse, floating text and messages.
// The HUD is HTML laid over the world's canvas; icons come from the same art sheet as the world.

const $ = (id) => document.getElementById(id);
const UI = { game: null, hudKey: "", floatEls: [], panelOpen: null, aimPointer: -1, aimSX: 0, aimSY: 0, mouse: false };

/** the style that shows an atlas picture [x, y, w, h] fitted into a box `size` pixels high */
function iconStyle(r, size) {
	const k = size / Math.max(r[2], r[3]);
	return "width:" + (r[2] * k) + "px;height:" + (r[3] * k) + "px;background-size:" + (Atlas.w * k) + "px " + (Atlas.h * k) + "px;background-position:-" + (r[0] * k) + "px -" + (r[1] * k) + "px";
}
function iconHTML(id, size) { return '<span class="ic" style="' + iconStyle(iconRect(id), size) + '"></span>'; }
function slotSizePx() { return Math.min(54, (window.innerWidth - 36) / 10); }
function escapeHTML(s) { return String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]); }
/** a bag slot's inside: the icon and the count */
function slotInner(s, size, key = "") {
	if (!s) return key ? '<span class="k">' + key + "</span>" : "";
	const n = s.n > 1 ? '<span class="n">' + s.n + "</span>" : "";
	return (key ? '<span class="k">' + key + "</span>" : "") + iconHTML(s.id, size * 0.66) + n;
}

const HUD = {
	init() {
		document.documentElement.style.setProperty("--atlas", 'url("' + ATLAS_PNG + '")');
		const hb = $("hotbar");
		let h = "";
		for (let i = 0; i < HOTBAR_N; i++) h += '<div class="slot" data-i="' + i + '"></div>';
		hb.innerHTML = h;
		hb.addEventListener("pointerdown", (e) => {
			const el = e.target.closest(".slot");
			if (!el || !UI.game) return;
			e.preventDefault();
			const i = +el.dataset.i;
			if (i === UI.game.sel && UI.game.heldItem) { UI.game.say(itemName(UI.game.heldItem), 1.2); }
			UI.game.setSel(i);
			sfx("tap", 0.3);
		});
		$("bInv").addEventListener("click", () => { if (UI.game) openPanel("inventory", UI.game.isCreative ? "items" : "bag"); });
		$("bPause").addEventListener("click", () => openPause());
		for (let i = 0; i < 16; i++) { const d = document.createElement("div"); d.className = "hidden"; $("floats").appendChild(d); UI.floatEls.push(d); }
		this.initStick();
		this.initJump();
		this.initWorldPointer();
		this.initKeys();
	},
	show(on) { $("hud").classList.toggle("hidden", !on); },
	initStick() {
		const st = $("stick"), knob = $("knob");
		let id = -1, cx = 0, cy = 0;
		const move = (e) => {
			const R0 = 46;
			let dx = e.clientX - cx, dy = e.clientY - cy;
			const d = Math.hypot(dx, dy);
			if (d > R0) { dx *= R0 / d; dy *= R0 / d; }
			knob.style.transform = "translate(" + dx + "px," + dy + "px)";
			if (UI.game) { UI.game.stick = Math.abs(dx) < 6 ? 0 : clampD(dx / 38, -1, 1); UI.game.stickY = clampD(dy / 38, -1, 1); }
		};
		st.addEventListener("pointerdown", (e) => {
			e.preventDefault(); Sound.unlock();
			id = e.pointerId; st.setPointerCapture(id);
			const r = st.getBoundingClientRect(); cx = r.left + r.width / 2; cy = r.top + r.height / 2;
			move(e);
		});
		st.addEventListener("pointermove", (e) => { if (e.pointerId === id) move(e); });
		const end = (e) => { if (e.pointerId !== id) return; id = -1; knob.style.transform = ""; if (UI.game) { UI.game.stick = 0; UI.game.stickY = 0; } };
		st.addEventListener("pointerup", end); st.addEventListener("pointercancel", end);
		this.stickReset = () => { id = -1; knob.style.transform = ""; };
	},
	initJump() {
		const b = $("bJump");
		let id = -1;
		b.addEventListener("pointerdown", (e) => { e.preventDefault(); Sound.unlock(); id = e.pointerId; b.setPointerCapture(id); b.classList.add("on"); if (UI.game) UI.game.jumpHeld = true; });
		const end = (e) => { if (e.pointerId !== id) return; id = -1; b.classList.remove("on"); if (UI.game) UI.game.jumpHeld = false; };
		b.addEventListener("pointerup", end); b.addEventListener("pointercancel", end);
	},
	toWorld(sx, sy) { const k = R.dpr / View.tp; return [View.left + sx * k, View.top + sy * k]; },
	initWorldPointer() {
		const cv = $("world");
		cv.addEventListener("pointerdown", (e) => {
			e.preventDefault(); Sound.unlock();
			const g = UI.game;
			if (!g || UI.panelOpen || g.paused || g.dead) return;
			if (UI.aimPointer !== -1) return;
			if (e.pointerType === "mouse" && e.button !== 0) return;
			UI.aimPointer = e.pointerId; UI.mouse = e.pointerType === "mouse";
			cv.setPointerCapture(e.pointerId);
			UI.aimSX = e.clientX; UI.aimSY = e.clientY;
			const [wx, wy] = this.toWorld(e.clientX, e.clientY);
			g.pointerDown(wx, wy);
		});
		cv.addEventListener("pointermove", (e) => {
			const g = UI.game;
			if (!g) return;
			if (e.pointerId === UI.aimPointer) {
				UI.aimSX = e.clientX; UI.aimSY = e.clientY;
				const [wx, wy] = this.toWorld(e.clientX, e.clientY);
				g.pointerMove(wx, wy);
			} else if (e.pointerType === "mouse" && UI.aimPointer === -1 && !UI.panelOpen) {
				// a mouse shows where a block would go before the click
				UI.mouse = true; UI.aimSX = e.clientX; UI.aimSY = e.clientY;
				const [wx, wy] = this.toWorld(e.clientX, e.clientY);
				g.aimX = wx; g.aimY = wy; g.aimValid = true;
			}
		});
		const end = (e) => {
			if (e.pointerId !== UI.aimPointer) return;
			UI.aimPointer = -1;
			if (UI.game) { UI.game.pointerUp(); if (!UI.mouse) UI.game.aimValid = false; }
		};
		cv.addEventListener("pointerup", end); cv.addEventListener("pointercancel", end);
		cv.addEventListener("contextmenu", (e) => e.preventDefault());
		cv.addEventListener("wheel", (e) => {
			const g = UI.game;
			if (!g || UI.panelOpen) return;
			e.preventDefault();
			if (e.ctrlKey) { setZoom(g.settings.tilePx * (e.deltaY < 0 ? 1.1 : 0.9)); return; }
			g.setSel((g.sel + (e.deltaY > 0 ? 1 : -1) + HOTBAR_N) % HOTBAR_N);
		}, { passive: false });
	},
	initKeys() {
		const set = (e, on) => {
			const g = UI.game;
			if (!g) return false;
			if (e.target && (e.target.tagName === "INPUT" || e.target.tagName === "SELECT")) return false;
			switch (e.code) {
				case "KeyA": case "ArrowLeft": g.keyL = on; return true;
				case "KeyD": case "ArrowRight": g.keyR = on; return true;
				case "KeyW": case "ArrowUp": case "Space": g.jumpHeld = on; return true;
				case "KeyS": case "ArrowDown": g.downHeld = on; return true;
			}
			return false;
		};
		window.addEventListener("keydown", (e) => {
			Sound.unlock();
			const g = UI.game;
			if (!g) return;
			if (e.target && (e.target.tagName === "INPUT" || e.target.tagName === "SELECT")) return;
			if (e.code === "Escape") { e.preventDefault(); if (UI.panelOpen) closePanels(); else openPause(); return; }
			if (e.code === "KeyE" || e.code === "Tab" || e.code === "KeyI") { e.preventDefault(); if (UI.panelOpen === "inventory") closePanels(); else if (!UI.panelOpen) openPanel("inventory", g.isCreative ? "items" : "bag"); return; }
			if (UI.panelOpen) return;
			if (set(e, true)) { e.preventDefault(); return; }
			if (/^Digit[0-9]$/.test(e.code)) { const d = +e.code.slice(5); g.setSel(d === 0 ? 9 : d - 1); return; }
			if (e.code === "KeyQ") { g.dropSlot(g.sel, e.shiftKey); return; }
			if (e.code === "KeyF" && e.shiftKey && g.isCreative) { g.flying = !g.flying; g.say(g.flying ? "Flying" : "Walking", 1); return; }
			if (e.code === "Equal" || e.code === "NumpadAdd") setZoom(g.settings.tilePx * 1.12);
			if (e.code === "Minus" || e.code === "NumpadSubtract") setZoom(g.settings.tilePx / 1.12);
		});
		window.addEventListener("keyup", (e) => { set(e, false); });
		window.addEventListener("blur", () => releaseAllInput());
	},
	/** every frame: the aim follows the finger as the view moves, the HUD shows what changed */
	update(g) {
		if (UI.aimPointer !== -1 || UI.mouse) {
			if (UI.aimPointer !== -1 || g.aimValid) { const [wx, wy] = this.toWorld(UI.aimSX, UI.aimSY); g.aimX = wx; g.aimY = wy; }
		}
		const key = g.hudRev + "|" + Math.ceil(g.hp * 2) + "|" + Math.ceil(g.hunger * 2) + "|" + Math.ceil(g.air) + "|" + g.sel + "|" + g.mode + "|" + g.maxHP;
		if (key !== UI.hudKey) { UI.hudKey = key; this.redraw(g); }
		this.drawFloats(g);
		const perf = $("perf");
		if (g.settings.showFPS) {
			perf.classList.remove("hidden");
			if ((Loop.frames & 15) === 0) perf.textContent = Math.round(Loop.fps) + " fps  tick " + g.tickMs.toFixed(1) + " ms  draw " + PERF.renderMs.toFixed(1) + " ms\nx " + Math.floor(g.pb.x) + "  y " + Math.floor(g.pb.y) + "  chunks " + g.world.chunks.size + "  light " + PERF.lightMs.toFixed(1) + " ms";
		} else perf.classList.add("hidden");
	},
	redraw(g) {
		const hb = $("hotbar").children, size = slotSizePx();
		for (let i = 0; i < HOTBAR_N; i++) {
			const el = hb[i];
			el.classList.toggle("sel", i === g.sel);
			el.innerHTML = slotInner(g.inv.slots[i], size, size > 44 ? String((i + 1) % 10) : "");
		}
		const creative = g.isCreative;
		const pips = (full, empty, value, count) => {
			let h = "";
			const rf = spriteRect(full), re = spriteRect(empty);
			for (let i = 0; i < count; i++) {
				const v = clampD(value - i * 2, 0, 2);
				h += '<span style="position:relative;display:inline-block;width:18px;height:18px"><span class="ic" style="position:absolute;' + iconStyle(re, 18) + '"></span>';
				if (v > 0) h += '<span style="position:absolute;left:0;top:0;width:' + (v >= 2 ? 18 : 9) + 'px;height:18px;overflow:hidden"><span class="ic" style="position:absolute;' + iconStyle(rf, 18) + '"></span></span>';
				h += "</span>";
			}
			return h;
		};
		$("hearts").innerHTML = creative ? "" : pips("misc:heart_full", "misc:heart_empty", Math.ceil(g.hp), Math.ceil(g.maxHP / 2));
		$("food").innerHTML = creative ? "" : pips("misc:food_full", "misc:food_empty", Math.ceil(g.hunger), 10);
		let air = "";
		if (g.air < 9.95 && !creative) { const rb = spriteRect("misc:bubble"); for (let i = 0; i < Math.ceil(g.air); i++) air += '<span class="ic" style="margin-right:2px;' + iconStyle(rb, 16) + '"></span>'; }
		$("air").innerHTML = air;
		const m = $("msg");
		if (g.message) { m.textContent = g.message; m.classList.remove("hidden"); } else m.classList.add("hidden");
	},
	drawFloats(g) {
		const els = UI.floatEls, k = View.tp / R.dpr;
		for (let i = 0; i < els.length; i++) {
			const el = els[i], f = g.floats[i];
			if (!f) { if (!el.classList.contains("hidden")) el.classList.add("hidden"); continue; }
			el.classList.remove("hidden");
			if (el.textContent !== f.text) el.textContent = f.text;
			el.style.left = ((f.x - View.left) * k) + "px";
			el.style.top = ((f.y - View.top) * k) + "px";
			el.style.opacity = clampD(f.life * 1.5, 0, 1);
			el.style.color = hexCss(f.color);
		}
	},
};
/** lets go of every control (a panel opened over them, the page lost focus) */
function releaseAllInput() {
	const g = UI.game;
	if (HUD.stickReset) HUD.stickReset();
	$("bJump").classList.remove("on");
	if (!g) return;
	g.stick = 0; g.stickY = 0; g.keyL = false; g.keyR = false; g.jumpHeld = false; g.downHeld = false;
	if (UI.aimPointer !== -1) { UI.aimPointer = -1; g.pointerUp(); }
	g.useHeld = false; g.pendingInteract = false; g.mining = false;
}
function setZoom(px) {
	const g = UI.game;
	if (!g) return;
	g.settings.tilePx = clampD(Math.round(px), 12, 64);
	g.tilePx = g.settings.tilePx;
	SettingsStore.save(g.settings);
}
