// The panels (the Swift game's u04_panels): the bag with armour, the crafting book with live counts,
// chests, the creative item browser, the pause screen with settings, and the death screen.

const Panel = {
	tab: "bag", pick: -1, pickArmor: -1, info: null, cat: "all", canOnly: false, search: "", key: "",
	el() { return $("panel"); },
};

/** opens a panel over the game; the controls let go so nothing keeps walking or mining underneath */
function openPanel(name, tab) {
	const g = UI.game;
	if (!g) return;
	releaseAllInput();
	UI.panelOpen = name;
	if (tab) Panel.tab = tab;
	else if (g.openChest) Panel.tab = "bag";
	else if (Panel.tab === "items" && !g.isCreative) Panel.tab = "bag";
	Panel.pick = -1; Panel.pickArmor = -1; Panel.info = null;
	$("panel").classList.remove("hidden");
	HUD.show(false);
	renderPanel(true);
}
function closePanels() {
	const g = UI.game;
	UI.panelOpen = null;
	$("panel").classList.add("hidden");
	$("pause").classList.add("hidden");
	if (g) { g.openChest = null; g.craftStation = "hand"; g.paused = false; HUD.show(!g.dead); UI.hudKey = ""; }
}

function renderPanel(force = false) {
	const g = UI.game;
	if (!g || UI.panelOpen !== "inventory") return;
	const key = Panel.tab + "|" + g.hudRev + "|" + Panel.pick + "|" + Panel.pickArmor + "|" + Panel.cat + "|" + Panel.canOnly + "|" + Panel.search + "|" + (g.openChest ? g.openChest.x + "," + g.openChest.y : "");
	if (!force && key === Panel.key) return;
	if (!force && document.activeElement && document.activeElement.id === "isearch") return;
	Panel.key = key;
	const box = $("panel");
	const scrollEl = box.querySelector(".scroll");
	const keepScroll = scrollEl ? scrollEl.scrollTop : 0;
	const tabs = [["bag", g.openChest ? "CHEST" : "BAG"], ["craft", "CRAFT"]];
	if (g.isCreative) tabs.push(["items", "ITEMS"]);
	let top = '<div class="top"><span class="title">' + (Panel.tab === "craft" ? "Crafting" : Panel.tab === "items" ? "All items" : g.openChest ? "Chest" : "Inventory") + '</span><div class="tabs">';
	for (const [k, n] of tabs) top += '<button data-tab="' + k + '" class="' + (Panel.tab === k ? "on" : "") + '">' + n + "</button>";
	top += '</div><button data-act="close">✕</button></div>';
	let body = "";
	if (Panel.tab === "craft") body = craftHTML(g);
	else if (Panel.tab === "items") body = itemsHTML(g);
	else body = bagHTML(g);
	box.innerHTML = '<div class="box">' + top + '<div class="scroll">' + body + "</div></div>";
	const sc = box.querySelector(".scroll");
	if (sc) sc.scrollTop = keepScroll;
}

function gridHTML(slots, from, to, prefix, size, chosen) {
	let h = '<div class="grid">';
	for (let i = from; i < to; i++) h += '<div class="slot' + (chosen === i ? " pick" : "") + (prefix === "s" && i === UI.game.sel ? " sel" : "") + '" data-' + prefix + '="' + i + '">' + slotInner(slots[i], size) + "</div>";
	return h + "</div>";
}
function bagHTML(g) {
	const size = slotSizePx();
	let h = "";
	if (g.openChest) {
		const items = g.world.chestItems(g.openChest.x, g.openChest.y);
		const shown = items.slice(0, 27);
		while (shown.length < 30) shown.push(null);
		h += '<div class="label">Chest — tap to take</div>' + gridHTML(shown, 0, 30, "c", size, -1);
		h += '<div class="label">Your bag — tap to put in the chest</div>';
	} else {
		h += '<div class="label">Armour and gear</div><div class="armor">';
		const names = ["Head", "Chest", "Legs", "Gear", "Gear"];
		for (let i = 0; i < ARMOR_N; i++) {
			const s = g.inv.armor[i];
			h += '<div class="slot' + (Panel.pickArmor === i ? " pick" : "") + '" data-a="' + i + '">' + (s ? slotInner(s, size) : '<span class="k" style="position:static;font-size:10px">' + names[i] + "</span>") + "</div>";
		}
		h += '</div><div style="text-align:center;font-size:13px;color:var(--dim);margin-top:4px">Defence ' + g.inv.defense.toFixed(1) + " — blows " + Math.round(g.armorShare(g.inv.defense) * 100) + "% softer</div>";
		h += '<div class="label">Hotbar</div>';
	}
	h += gridHTML(g.inv.slots, 0, HOTBAR_N, "s", size, Panel.pick);
	if (!g.openChest) h += '<div class="label" style="display:flex;align-items:center;gap:8px">Bag <button data-act="sort" style="margin-left:auto;padding:4px 10px;font-size:13px">SORT</button></div>';
	else h += '<div style="height:6px"></div>';
	h += gridHTML(g.inv.slots, HOTBAR_N, BAG_N, "s", size, Panel.pick);
	h += infoHTML(g);
	return h;
}
function infoHTML(g) {
	let s = null, where = "";
	if (Panel.pick >= 0) { s = g.inv.slots[Panel.pick]; where = "bag"; }
	else if (Panel.pickArmor >= 0) { s = g.inv.armor[Panel.pickArmor]; where = "armor"; }
	if (!s) return '<div class="info"><div class="ln">Tap an item to see it. Tap another slot to move it there.</div></div>';
	const d = itemDef(s.id);
	let h = '<div class="info"><div class="nm">' + iconHTML(s.id, 22) + " " + escapeHTML(d.name) + (s.n > 1 ? " ×" + s.n : "") + "</div>";
	for (const ln of d.info || []) h += '<div class="ln">' + escapeHTML(ln) + "</div>";
	h += '<div class="acts">';
	if (where === "armor") h += '<button data-act="unequip">TAKE OFF</button>';
	else {
		if (s.id.startsWith("armor:") || s.id.startsWith("gear:")) h += '<button data-act="equip" class="primary">PUT ON</button>';
		if (s.id.startsWith("food:")) h += '<button data-act="eat" class="primary">EAT</button>';
		if (Panel.pick >= HOTBAR_N) h += '<button data-act="tohot">TO HOTBAR</button>';
		else h += '<button data-act="hold">HOLD</button>';
		h += '<button data-act="drop1">DROP 1</button><button data-act="dropall" class="warn">DROP ALL</button>';
		if (g.isCreative) h += '<button data-act="trash" class="warn">BIN</button>';
	}
	return h + "</div></div>";
}
function recipeList(g) {
	const q = Panel.search.trim().toLowerCase();
	return RECIPES.filter((r) => {
		if (Panel.cat !== "all" && r.cat !== Panel.cat) return false;
		if (q && !itemName(r.out).toLowerCase().includes(q)) return false;
		if (Panel.canOnly && !(g.stationAvailable(r.station) && g.craftableCount(r) > 0)) return false;
		return true;
	});
}
function craftHTML(g) {
	const st = g.craftStation;
	let h = '<div style="font-size:14px;color:var(--dim);margin-bottom:6px">' + (st !== "hand" ? "At the " + STATION_NAMES[st] + ". " : "") + "Stations within a few blocks count.</div>";
	h += '<div class="tabs" style="margin-bottom:8px"><button data-cat="all" class="' + (Panel.cat === "all" ? "on" : "") + '">ALL</button>';
	const cats = RECIPE_CATS.filter((c) => RECIPES.some((r) => r.cat === c));
	for (const c of cats) h += '<button data-cat="' + c + '" class="' + (Panel.cat === c ? "on" : "") + '">' + CAT_NAMES[c].toUpperCase() + "</button>";
	h += "</div>";
	h += '<div style="display:flex;gap:6px;margin-bottom:8px"><input id="isearch" placeholder="Search" value="' + escapeHTML(Panel.search) + '" style="flex:1"><button data-act="canonly" class="' + (Panel.canOnly ? "on" : "") + '">CAN MAKE</button></div>';
	return h + '<div id="plist">' + craftListHTML(g) + "</div>";
}
function craftListHTML(g) {
	let h = "";
	const list = recipeList(g);
	// what can be made now comes first
	const can = [], cannot = [];
	for (const r of list) { if (g.stationAvailable(r.station) && g.craftableCount(r) > 0) can.push(r); else cannot.push(r); }
	if (!list.length) h += '<div class="note">Nothing here.</div>';
	for (const r of can.concat(cannot)) {
		const stOK = g.stationAvailable(r.station), n = g.craftableCount(r);
		const ok = stOK && n > 0;
		h += '<div class="recipe' + (ok ? "" : " no") + '">' + iconHTML(r.out, 30) + '<div class="nm">' + escapeHTML(itemName(r.out)) + (r.n > 1 ? " ×" + r.n : "") + '<div class="cost">';
		for (const c of r.cost) {
			const have = g.inv.total(c[0]);
			h += '<span class="' + (have >= c[1] || g.isCreative ? "" : "miss") + '">' + iconHTML(c[0], 16) + " " + have + "/" + c[1] + "</span>";
		}
		if (r.station !== "hand") h += '<span class="' + (stOK ? "" : "miss") + '">' + STATION_NAMES[r.station] + "</span>";
		h += "</div></div>";
		h += '<button data-craft="' + r.id + '" ' + (ok ? "" : "disabled") + '>MAKE</button>';
		if (ok && n >= 5) h += '<button data-craft5="' + r.id + '">×5</button>';
		h += "</div>";
	}
	return h;
}
function itemsListHTML(g) {
	const size = slotSizePx(), q = Panel.search.trim().toLowerCase();
	let h = '<div class="grid">';
	for (const id of ITEM_LIST) {
		if (q && !itemName(id).toLowerCase().includes(q) && !id.toLowerCase().includes(q)) continue;
		h += '<div class="slot" data-give="' + escapeHTML(id) + '">' + iconHTML(id, size * 0.66) + "</div>";
	}
	return h + "</div>";
}
function itemsHTML(g) {
	const size = slotSizePx();
	let h = '<div style="display:flex;gap:6px;margin-bottom:8px"><input id="isearch" placeholder="Search all items" value="' + escapeHTML(Panel.search) + '" style="flex:1"></div>';
	h += '<div class="label">Tap to take a stack</div><div id="plist">' + itemsListHTML(g) + "</div>";
	h += '<div class="label">Hotbar</div>' + gridHTML(g.inv.slots, 0, HOTBAR_N, "s", size, Panel.pick);
	return h + infoHTML(g);
}

/** a tap on a slot: pick it, or move the picked stack there (merging, or swapping) */
function slotTap(g, i) {
	if (g.openChest) { g.chestStore(g.openChest.x, g.openChest.y, i); sfx("tap", 0.3); return; }
	if (Panel.pickArmor >= 0) {
		const a = Panel.pickArmor, s = g.inv.slots[i];
		Panel.pickArmor = -1;
		if (!s) { g.inv.slots[i] = g.inv.armor[a]; g.inv.armor[a] = null; }
		else if (fitsArmor(s.id, a)) { const old = g.inv.armor[a]; g.inv.armor[a] = s; g.inv.slots[i] = old; }
		g.bumpHUD();
		return;
	}
	if (Panel.pick < 0 || Panel.pick === i) { Panel.pick = Panel.pick === i ? -1 : i; return; }
	const a = g.inv.slots[Panel.pick], b = g.inv.slots[i];
	if (a && b && a.id === b.id && sameInf(a.inf, b.inf) && b.n < maxStack(b.id)) {
		const put = Math.min(maxStack(b.id) - b.n, a.n);
		b.n += put; a.n -= put;
		if (a.n <= 0) g.inv.slots[Panel.pick] = null;
	} else g.inv.swap(Panel.pick, i);
	Panel.pick = -1;
	sfx("tap", 0.3);
	g.bumpHUD();
}
function fitsArmor(id, slot) {
	if (slot < FIRST_GEAR) return id.startsWith("armor:" + ARMOR_SLOTS[slot] + ":");
	return id.startsWith("gear:");
}
function armorTap(g, a) {
	if (Panel.pick >= 0) {
		const s = g.inv.slots[Panel.pick];
		if (s && fitsArmor(s.id, a)) { const old = g.inv.armor[a]; g.inv.armor[a] = s; g.inv.slots[Panel.pick] = old; sfx("equip", 0.5); g.bumpHUD(); }
		else g.say("That doesn't go there.", 1.2);
		Panel.pick = -1;
		return;
	}
	Panel.pickArmor = Panel.pickArmor === a ? -1 : (g.inv.armor[a] ? a : -1);
}
function panelAct(g, act) {
	const i = Panel.pick;
	switch (act) {
		case "close": closePanels(); return;
		case "sort": g.inv.sortBag(); sfx("tap", 0.3); break;
		case "equip": if (i >= 0) { g.quickEquip(i); Panel.pick = -1; } break;
		case "unequip": if (Panel.pickArmor >= 0) { g.unequip(Panel.pickArmor); Panel.pickArmor = -1; } break;
		case "eat": if (i >= 0) { const old = g.sel; g.sel = i; g.useFood(g.inv.slots[i].id, true); g.sel = old; } break;
		case "tohot": if (i >= 0) { for (let k = 0; k < HOTBAR_N; k++) if (!g.inv.slots[k]) { g.inv.swap(i, k); Panel.pick = k; break; } if (Panel.pick === i) { g.inv.swap(i, g.sel); Panel.pick = g.sel; } } break;
		case "hold": if (i >= 0 && i < HOTBAR_N) g.setSel(i); break;
		case "drop1": if (i >= 0) g.dropSlot(i, false); break;
		case "dropall": if (i >= 0) { g.dropSlot(i, true); Panel.pick = -1; } break;
		case "trash": if (i >= 0) { g.inv.slots[i] = null; Panel.pick = -1; } break;
		case "canonly": Panel.canOnly = !Panel.canOnly; break;
	}
	g.bumpHUD();
}
function initPanels() {
	const box = $("panel");
	box.addEventListener("click", (e) => {
		const g = UI.game;
		if (!g) return;
		const t = e.target.closest("[data-tab],[data-act],[data-s],[data-a],[data-c],[data-cat],[data-craft],[data-craft5],[data-give]");
		if (!t) { if (e.target === box) closePanels(); return; }
		const ds = t.dataset;
		if (ds.tab) { Panel.tab = ds.tab; Panel.pick = -1; Panel.pickArmor = -1; Panel.search = ""; }
		else if (ds.act) { panelAct(g, ds.act); if (!UI.panelOpen) return; }
		else if (ds.s !== undefined) slotTap(g, +ds.s);
		else if (ds.a !== undefined) armorTap(g, +ds.a);
		else if (ds.c !== undefined) { if (g.openChest) { g.chestTake(g.openChest.x, g.openChest.y, +ds.c); sfx("tap", 0.3); } }
		else if (ds.cat) Panel.cat = ds.cat;
		else if (ds.craft !== undefined) g.craft(RECIPES[+ds.craft]);
		else if (ds.craft5 !== undefined) { for (let k = 0; k < 5; k++) if (!g.craft(RECIPES[+ds.craft5])) break; }
		else if (ds.give) { const left = g.inv.add(ds.give, maxStack(ds.give)); if (left > 0) g.say("Your bag is full.", 1.2); else sfx("pickup", 0.4); g.bumpHUD(); }
		renderPanel(true);
	});
	box.addEventListener("input", (e) => {
		if (e.target.id !== "isearch") return;
		Panel.search = e.target.value;
		const g = UI.game, pl = $("plist");
		if (!g || !pl) return;
		pl.innerHTML = Panel.tab === "craft" ? craftListHTML(g) : itemsListHTML(g);
		Panel.key = "";
		Panel.searchHeld = true;
	});
	$("pause").addEventListener("click", onPauseClick);
	$("pause").addEventListener("input", onPauseInput);
	$("death").addEventListener("click", (e) => {
		const t = e.target.closest("[data-act]");
		if (!t || !UI.game) return;
		if (t.dataset.act === "respawn") { UI.game.respawn(); $("death").classList.add("hidden"); HUD.show(true); UI.hudKey = ""; }
		else if (t.dataset.act === "quit") quitToMenu(false);
	});
}

// ---- pause and settings
const SETTING_ROWS = [
	["tilePx", "Zoom", "How big the blocks are", 12, 64, 1],
	["volume", "Volume", "", 0, 1, 0.05],
	["camFollow", "Camera follow", "How quickly the view catches up", 0, 1, 0.05],
	["camDeadZone", "Camera slack", "How far you can move before the view does", 0, 4, 0.1],
	["shakeScale", "Screen shake", "", 0, 1.5, 0.05],
];
const SETTING_SWITCHES = [
	["sound", "Sound"], ["smoothLight", "Smooth light"], ["camSmoothOn", "Smooth camera"], ["camDirect", "Direct camera", "The view stays on you"],
	["camLookAhead", "Look ahead"], ["showFPS", "Show speed (FPS)"], ["autosave", "Save every minute"], ["leftHanded", "Left-handed controls"],
];
let pausePage = "main";
function openPause(page = "main") {
	const g = UI.game;
	if (!g) return;
	releaseAllInput();
	if (UI.panelOpen === "inventory") { $("panel").classList.add("hidden"); g.openChest = null; }
	UI.panelOpen = "pause";
	g.paused = true;
	pausePage = page;
	HUD.show(false);
	$("pause").classList.remove("hidden");
	renderPause();
}
function renderPause() {
	const g = UI.game, el = $("pause");
	if (pausePage === "settings") { el.innerHTML = '<div class="box" style="width:min(560px,100%)">' + settingsTop("back") + '<div class="scroll">' + settingsHTML(g.settings) + "</div></div>"; return; }
	const where = g.slot ? "Saved worlds keep to your account." : "";
	el.innerHTML = '<div class="box" style="width:min(420px,100%)"><div class="top"><span class="title">Paused — ' + escapeHTML(g.worldName) + '</span></div><div class="scroll"><div class="col">' +
		'<button data-act="resume" class="primary">RESUME</button><button data-act="save">SAVE NOW</button><button data-act="settings">SETTINGS</button>' +
		'<button data-act="export">EXPORT WORLD (FILE)</button><button data-act="quit" class="warn">SAVE AND QUIT</button></div>' +
		'<div class="note" id="pnote">' + MODE_NAMES[g.mode] + " · day " + (g.dayCount + 1) + " · seed " + g.seedValue + "<br>" + where + "</div></div></div>";
}
function settingsTop(back) { return '<div class="top"><span class="title">Settings</span><button data-act="' + back + '">DONE</button></div>'; }
function settingsHTML(s) {
	let h = "";
	for (const [k, name, help, lo, hi, step] of SETTING_ROWS) {
		h += '<div class="setrow"><div class="nm">' + name + (help ? "<div>" + help + "</div>" : "") + '</div><input type="range" data-set="' + k + '" min="' + lo + '" max="' + hi + '" step="' + step + '" value="' + s[k] + '"><span style="width:40px;text-align:right" id="sv_' + k + '">' + (+s[k]).toFixed(step < 1 ? 2 : 0) + "</span></div>";
	}
	for (const [k, name, help] of SETTING_SWITCHES) h += '<div class="setrow"><div class="nm">' + name + (help ? "<div>" + help + "</div>" : "") + '</div><button data-toggle="' + k + '" class="' + (s[k] ? "on" : "") + '">' + (s[k] ? "ON" : "OFF") + "</button></div>";
	return h;
}
function applySettings(s) {
	Sound.on = s.sound; Sound.setVolume(s.volume);
	document.body.classList.toggle("lefty", !!s.leftHanded);
	if (UI.game) { UI.game.tilePx = s.tilePx; }
}
function onSettingsToggle(s, k) { s[k] = !s[k]; SettingsStore.save(s); applySettings(s); }
function onPauseInput(e) {
	const k = e.target.dataset.set;
	if (!k || !UI.game) return;
	const s = UI.game.settings;
	s[k] = +e.target.value;
	const lab = document.getElementById("sv_" + k);
	if (lab) lab.textContent = (+s[k]).toFixed(k === "tilePx" ? 0 : 2);
	SettingsStore.save(s); applySettings(s);
}
async function onPauseClick(e) {
	const g = UI.game;
	const t = e.target.closest("[data-act],[data-toggle]");
	if (!t || !g) return;
	if (t.dataset.toggle) { onSettingsToggle(g.settings, t.dataset.toggle); renderPause(); return; }
	const note = (s) => { const n = $("pnote"); if (n) n.textContent = s; };
	switch (t.dataset.act) {
		case "resume": closePanels(); break;
		case "settings": pausePage = "settings"; renderPause(); break;
		case "back": pausePage = "main"; renderPause(); break;
		case "save": note("Saving…"); try { const r = await saveGame(g); note("Saved (" + r.where + ", " + Math.ceil(r.size / 1024) + " KB)."); } catch (err) { note("Could not save: " + err.message); } break;
		case "export": try { await exportWorld(g); note("The world file is ready to save."); } catch (err) { note("Could not export: " + err.message); } break;
		case "quit": quitToMenu(true); break;
	}
}

function showDeath(g) {
	const el = $("death");
	if (!el.classList.contains("hidden")) return;
	releaseAllInput();
	HUD.show(false);
	const over = g.mode === GameMode.hardcore;
	el.innerHTML = '<div class="box"><h2>' + (over ? "Your hardcore world is lost" : "You died") + "</h2>" +
		'<div class="note">' + (rule("deathDrop") > 0 && !over ? "Your things are where you fell." : "") + '</div><div class="col">' +
		(over ? "" : '<button data-act="respawn" class="primary">RESPAWN</button>') + '<button data-act="quit">' + (over ? "BACK TO THE TITLE" : "QUIT TO TITLE") + "</button></div></div>";
	el.classList.remove("hidden");
}
