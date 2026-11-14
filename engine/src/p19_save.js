// Saving and loading (the Swift game's p19_save). A world is saved as the changes to its chunks (each
// changed chunk against the same chunk made fresh), the player, the bag, chests and the clock, packed
// and squeezed into text. The text goes to the viewer's own space in their account when the page can
// reach it, or to this browser, and can be exported as a file.

const SAVE_VERSION = 1;
const PART = 200000;          // characters a stored document holds (well under the 256 KB limit)
/** later phases save and load their own parts of a world through these */
const saveHooks = [], loadHooks = [];

const SettingsStore = {
	key: "pixelrealm.settings",
	load() {
		const s = defaultSettings();
		try { const t = localStorage.getItem(this.key); if (t) Object.assign(s, JSON.parse(t)); } catch (e) {}
		return s;
	},
	save(s) { try { localStorage.setItem(this.key, JSON.stringify(s)); } catch (e) {} },
};

function bytesToB64(u8) {
	let s = "";
	for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000));
	return btoa(s);
}
function b64ToBytes(s) {
	const bin = atob(s), out = new Uint8Array(bin.length);
	for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
	return out;
}
async function squeeze(u8, way) {
	const cs = new CompressionStream(way);
	const buf = await new Response(new Blob([u8]).stream().pipeThrough(cs)).arrayBuffer();
	return new Uint8Array(buf);
}
async function unsqueeze(u8, way) {
	const ds = new DecompressionStream(way);
	const buf = await new Response(new Blob([u8]).stream().pipeThrough(ds)).arrayBuffer();
	return new Uint8Array(buf);
}
/** an object as text: JSON, deflated where the browser can, in base64; the first letters say which */
async function packText(obj) {
	const raw = new TextEncoder().encode(JSON.stringify(obj));
	if (typeof CompressionStream !== "undefined") {
		try { return "PRD1:" + bytesToB64(await squeeze(raw, "deflate")); } catch (e) {}
	}
	return "PRJ1:" + bytesToB64(raw);
}
async function unpackText(text) {
	text = text.trim();
	const kind = text.slice(0, 5), body = text.slice(5);
	let raw;
	if (kind === "PRD1:") {
		if (typeof DecompressionStream === "undefined") throw new Error("this browser cannot read squeezed saves");
		raw = await unsqueeze(b64ToBytes(body), "deflate");
	} else if (kind === "PRJ1:") raw = b64ToBytes(body);
	else if (text.startsWith("{")) return JSON.parse(text);
	else throw new Error("this is not a PixelRealm world");
	return JSON.parse(new TextDecoder().decode(raw));
}

// ---- a world as an object
function chunkDelta(gen, dim, ch) {
	const base = generateChunk(gen, dim, ch.cx).tiles, t = ch.tiles;
	const d = new Uint8Array(t.length);
	let any = false;
	for (let i = 0; i < t.length; i++) if (t[i] !== base[i]) { d[i] = t[i] + 1; any = true; }
	return any ? bytesToB64(rle(d)) : "";
}
function makeSave(g) {
	const w = g.world, chunks = [];
	const each = (dim, ch) => {
		if (!ch.dirty) return;
		chunks.push([dim, ch.cx, chunkDelta(g.gen, dim, ch), ch.walls ? bytesToB64(rle(ch.walls)) : "", ch.built ? bytesToB64(rle(ch.built)) : ""]);
	};
	for (const ch of w.chunks.values()) each(w.dim, ch);
	for (let d = 0; d < w.parked.length; d++) for (const ch of w.parked[d].values()) each(d, ch);
	const chests = [];
	for (const [k, items] of w.chests) chests.push([k, items]);
	const pb = g.pb;
	const o = {
		v: SAVE_VERSION, name: g.worldName, mode: g.mode, seed: g.seedValue, infinite: g.gen.infinite, genVersion: g.gen.genVersion,
		options: g.gen.options, rareChance: g.gen.rareChance, dim: w.dim,
		time: g.timeOfDay, day: g.dayCount, play: Math.floor(g.playSeconds), saved: new Date().toISOString(),
		player: { x: pb.x, y: pb.y, hp: g.hp, maxHP: g.maxHP, hunger: g.hunger, air: g.air, spawnX: g.spawnX, spawnY: g.spawnY, sel: g.sel, facing: g.facing, dead: g.dead, over: g.hardcoreOver },
		inv: g.inv.toJSON(), chunks, chests, journal: g.journal,
	};
	saveHooks.forEach((f) => f(g, o));
	return o;
}
/** makes the game a save describes; the land comes from the save, not made around the spawn first */
function loadSave(o, settings) {
	if (!o || typeof o.seed !== "number") throw new Error("the save has no world in it");
	if (o.v > SAVE_VERSION) throw new Error("this world was saved by a newer version");
	const g = new Game(o.mode | 0, !!o.infinite, o.seed >>> 0, settings, o.genVersion || GEN_VERSION, o.options || null, false);
	g.gen.rareChance = o.rareChance !== undefined ? o.rareChance : g.gen.rareChance;
	g.worldName = o.name || "World";
	g.timeOfDay = o.time || 0.06; g.dayCount = o.day || 0; g.playSeconds = o.play || 0;
	const w = g.world, H = w.H;
	for (const c of o.chunks || []) {
		const [dim, cx, delta, walls, built] = c;
		const ch = generateChunk(g.gen, dim, cx);
		if (delta) {
			const d = unrle(b64ToBytes(delta), chunkW * H);
			for (let i = 0; i < d.length; i++) if (d[i] !== 0) ch.tiles[i] = d[i] - 1;
		}
		if (walls) ch.walls = unrle(b64ToBytes(walls), chunkW * H);
		if (built) ch.built = unrle(b64ToBytes(built), chunkW * H);
		for (let lx = 0; lx < chunkW; lx++) ch.recomputeSky(lx);
		if (ch.stairs >= 0) { ch.stairs = 0; for (let i = 0; i < ch.tiles.length; i++) if (STAIR[ch.tiles[i]]) ch.stairs++; }
		ch.dirty = true;
		ch.bumpRows(0, H - 1);
		if (dim >= 0 && dim < w.parked.length) w.parked[dim].set(cx, ch);
	}
	w.chests.clear();
	for (const [k, items] of o.chests || []) w.chests.set(k, (items || []).map((s) => stack(s.id, s.n, s.extra || 0, s.inf || null)));
	w.dim = o.dim || Dimension.overworld;
	const p = o.player || {};
	g.inv = Inventory.from(o.inv);
	g.maxHP = p.maxHP || rule("health");
	g.hp = p.hp !== undefined ? p.hp : g.maxHP; g.hunger = p.hunger !== undefined ? p.hunger : 20; g.air = p.air !== undefined ? p.air : 10;
	g.spawnX = p.spawnX !== undefined ? p.spawnX : g.gen.spawnX + 0.5;
	g.sel = clampI(p.sel || 0, 0, HOTBAR_N - 1); g.facing = p.facing || 1;
	g.hardcoreOver = !!p.over;
	g.journal = Object.assign({ crafted: [], relics: 0 }, o.journal || {});
	const px = p.x !== undefined ? p.x : g.gen.spawnX + 0.5;
	w.loadAround(Math.floor(px), 5);
	g.spawnY = p.spawnY !== undefined ? p.spawnY : w.surfaceY(Math.floor(g.spawnX));
	g.pb.x = px; g.pb.y = p.y !== undefined ? p.y : w.surfaceY(Math.floor(px));
	g.pb.vx = 0; g.pb.vy = 0;
	if (p.dead || g.hp <= 0) { if (g.mode === GameMode.hardcore && g.hardcoreOver) g.dead = true; else { g.hp = 1; g.respawn(); } }
	g.camX = g.pb.x; g.camY = g.pb.y - 2; g.camTX = g.camX; g.camTY = g.camY;
	loadHooks.forEach((f) => f(g, o));
	g.bumpHUD();
	return g;
}

// ---- where saves are kept
const Store = {
	db: null, uid: null, dl: null, ready: null,
	init() {
		if (this.ready) return this.ready;
		this.ready = (async () => {
			try {
				const c = window.claude;
				if (!c || !c.use) return;
				const got = await Promise.all([c.use("db").catch(() => null), c.use("user").catch(() => null), c.use("downloads").catch(() => null)]);
				this.dl = got[2] || null;
				if (got[0] && got[1]) { const id = await got[1].id(); if (id) { this.db = got[0]; this.uid = id; } }
			} catch (e) { this.db = null; }
		})();
		return this.ready;
	},
	get where() { return this.db ? "your account" : "this browser"; },
	col() { return this.db.collection("data/users/" + this.uid); },
	async list() {
		await this.init();
		let list = [];
		if (this.db) { try { const d = await this.col().doc("worlds").get(); if (d.exists) list = d.data().list || []; } catch (e) {} }
		try { const t = localStorage.getItem("pixelrealm.worlds"); if (t) for (const w of JSON.parse(t)) if (!list.some((o) => o.id === w.id)) { w.local = true; list.push(w); } } catch (e) {}
		list.sort((a, b) => (b.saved || "").localeCompare(a.saved || ""));
		return list;
	},
	async setIndex(entry, remove = false) {
		if (this.db && !entry.local) {
			const ref = this.col().doc("worlds");
			const d = await ref.get();
			let list = d.exists ? (d.data().list || []) : [];
			list = list.filter((o) => o.id !== entry.id);
			if (!remove) list.push(entry);
			await ref.set({ list });
			return;
		}
		let list = [];
		try { list = JSON.parse(localStorage.getItem("pixelrealm.worlds") || "[]"); } catch (e) {}
		list = list.filter((o) => o.id !== entry.id);
		if (!remove) list.push(entry);
		localStorage.setItem("pixelrealm.worlds", JSON.stringify(list));
	},
	/** writes the text into the slot not in use, then points the world's head at it, so a break half way keeps the old save whole */
	async write(id, text, entry) {
		await this.init();
		if (this.db) {
			try {
				const col = this.col(), head = col.doc("w_" + id);
				const m = await head.get();
				const old = m.exists ? m.data() : null;
				const slot = old && old.slot === 0 ? 1 : 0;
				const n = Math.ceil(text.length / PART);
				for (let i = 0; i < n; i++) await col.doc("w_" + id + "_" + slot + "_" + i).set({ s: text.slice(i * PART, (i + 1) * PART) });
				await head.set({ slot, parts: n, len: text.length, saved: entry.saved });
				if (old) for (let i = 0; i < old.parts; i++) { try { await col.doc("w_" + id + "_" + old.slot + "_" + i).delete(); } catch (e) { break; } }
				entry.local = false;
				await this.setIndex(entry);
				try { localStorage.removeItem("pixelrealm.w." + id); } catch (e) {}
				return "your account";
			} catch (e) { /* falls back to this browser */ }
		}
		localStorage.setItem("pixelrealm.w." + id, text);
		entry.local = true;
		await this.setIndex(entry);
		return "this browser";
	},
	async read(id) {
		await this.init();
		if (this.db) {
			try {
				const col = this.col(), m = await col.doc("w_" + id).get();
				if (m.exists) {
					const d = m.data();
					const docs = await Promise.all(Array.from({ length: d.parts }, (_, i) => col.doc("w_" + id + "_" + d.slot + "_" + i).get()));
					let text = "";
					for (const p of docs) { if (!p.exists) throw new Error("the saved world is incomplete"); text += p.data().s; }
					return text;
				}
			} catch (e) { if (e.message.includes("incomplete")) throw e; }
		}
		const t = localStorage.getItem("pixelrealm.w." + id);
		if (!t) throw new Error("that world could not be found");
		return t;
	},
	async remove(entry) {
		await this.init();
		if (this.db) {
			try {
				const col = this.col(), m = await col.doc("w_" + entry.id).get();
				if (m.exists) { const d = m.data(); for (let i = 0; i < d.parts; i++) { try { await col.doc("w_" + entry.id + "_" + d.slot + "_" + i).delete(); } catch (e) {} } await col.doc("w_" + entry.id).delete(); }
				await this.setIndex(entry, true);
			} catch (e) {}
		}
		try { localStorage.removeItem("pixelrealm.w." + entry.id); } catch (e) {}
		try { await this.setIndex(Object.assign({}, entry, { local: true }), true); } catch (e) {}
	},
};

let saving = null, saveAgain = false;
function newWorldID() { return Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36); }
async function saveGame(g) {
	if (g.isTest) return { where: "nowhere (test world)", size: 0 };
	if (!g.slot) g.slot = newWorldID();
	const o = makeSave(g);
	const text = await packText(o);
	const entry = { id: g.slot, name: g.worldName, mode: g.mode, seed: g.seedValue, saved: o.saved, day: g.dayCount + 1, size: text.length };
	const where = await Store.write(g.slot, text, entry);
	return { where, size: text.length };
}
/** saves in the background (autosave); a save asked for while one runs follows it */
function saveGameSoon(g) {
	if (saving) { saveAgain = true; return saving; }
	saving = saveGame(g).catch(() => { g.say("Autosave failed.", 2); }).finally(() => {
		saving = null;
		if (saveAgain) { saveAgain = false; saveGameSoon(g); }
	});
	return saving;
}
async function loadGameByID(id, settings) {
	const text = await Store.read(id);
	const o = await unpackText(text);
	const g = loadSave(o, settings);
	g.slot = id;
	return g;
}
async function exportWorld(g) {
	const text = await packText(makeSave(g));
	const name = (g.worldName || "world").replace(/[^A-Za-z0-9_-]+/g, "_") + ".pixelrealm.txt";
	await Store.init();
	if (Store.dl) { await Store.dl.save({ filename: name, data: text }); return; }
	const blob = new Blob([text], { type: "text/plain" });
	const a = document.createElement("a");
	a.href = URL.createObjectURL(blob); a.download = name; a.click();
	setTimeout(() => URL.revokeObjectURL(a.href), 4000);
}
/** a world from an exported file's text, kept as a new world */
async function importWorld(text, settings) {
	const o = await unpackText(text);
	const g = loadSave(o, settings);
	g.slot = newWorldID();
	await saveGame(g);
	return g;
}
