// The debug panel (the Swift game's DebugPanel): numbers about the game, cheats, time, teleports,
// creature tools, damage multipliers, hazard tests, the monsters' AI overlay and spawn log,
// performance, pausing systems, giving items and spawning creatures. It stays open beside the game
// (DBG on the HUD, or the ` key). Weather, power and portal tools join it in their phases.

const Debug = {
	open: false, selected: null, giveID: null, giveN: 1, giveSearch: "", confirmDelete: false, t: 0, aiEls: [],
	toggle() { this.open = !this.open; $("debug").classList.toggle("hidden", !this.open); if (this.open) this.render(); },
	render() {
		const g = UI.game;
		if (!g) return;
		const tog = (k, name) => '<label class="dbt"><input type="checkbox" data-dt="' + k + '"' + (g[k] ? " checked" : "") + "> " + name + "</label>";
		const btn = (act, name, cls = "") => '<button data-da="' + act + '" class="' + cls + '">' + name + "</button>";
		const sec = (s) => '<div class="dbs">' + s + "</div>";
		const slider = (k, name, lo, hi, step) => '<div class="dbl" id="dbv_' + k + '">' + name + " x" + (+g[k]).toFixed(2) + '</div><input type="range" data-ds="' + k + '" data-name="' + name + '" min="' + lo + '" max="' + hi + '" step="' + step + '" value="' + g[k] + '">';
		let h = '<div class="dbtop"><b>DEBUG</b><button data-da="close" class="warn">X</button></div>';
		h += '<div id="dbStats" class="dbl"></div>';
		h += tog("godMode", "God mode") + tog("flying", "Fly") + tog("noclip", "Noclip") + tog("monstersOff", "No monsters") + tog("freezeTime", "Freeze time") + tog("fullBright", "Full bright") + tog("infiniteReach", "Infinite reach") + tog("showHitboxes", "Hitboxes") + tog("showChunks", "Chunk borders");
		h += slider("speedMult", "Speed", 0.5, 4, 0.5);
		h += sec("TIME") + btn("dawn", "Dawn") + btn("noon", "Noon") + btn("dusk", "Dusk") + btn("night", "Night");
		h += sec("PLAYER") + btn("heal", "Heal") + btn("kit", "Give kit") + btn("killHostiles", "Kill hostiles");
		h += sec("TELEPORT") + btn("tpSpawn", "Spawn") + btn("tpSurface", "Surface") + btn("up20", "Up 20") + btn("down20", "Down 20") + btn("right200", "→ 200") + btn("left200", "← 200");
		h += '<div><input id="dbX" placeholder="X" style="width:70px"> <input id="dbY" placeholder="Y" style="width:70px"> ' + btn("tpGo", "Go") + "</div>";
		h += sec("ENTITIES") + '<div id="dbEnt" class="dbl"></div>' + btn("select", "Select at cursor") + '<div id="dbSel"></div>';
		h += this.confirmDelete ? btn("deleteAll", "CONFIRM DELETE ALL", "warn") + btn("cancelDelete", "Cancel") : btn("askDelete", "Delete all entities", "warn");
		h += sec("MULTIPLIERS") + slider("mobHealthMult", "Creature health (new spawns)", 0.25, 5, 0.25) + slider("dmgOutMult", "Damage dealt", 0, 10, 0.25) + slider("dmgInMult", "Damage taken", 0, 5, 0.25) + btn("resetMult", "Reset multipliers");
		h += sec("HAZARD TESTS") + btn("lava", "Lava pool") + btn("explode", "Explosion") + btn("spikes", "Spikes") + btn("fire", "Set on fire");
		h += sec("MONSTERS") + tog("showAI", "AI overlay (state, sight, why not attacking)") + '<div id="dbSpawn" class="dbl"></div>' + btn("spawnTest", "Night + spawn test") + btn("clearLog", "Clear log");
		h += sec("PERFORMANCE") + '<div id="dbPerf" class="dbl"></div>';
		h += sec("PAUSE SYSTEMS") + tog("pauseMobs", "Creatures") + tog("pauseSpawning", "Spawning") + tog("pauseProjectiles", "Projectiles") + tog("pauseWorldTicks", "World ticks (plants, leaves)") + tog("pauseParticles", "Particles") + btn("resetSystems", "Reset systems");
		h += sec("WORLD GENERATION") + '<div id="dbWorld" class="dbl"></div>';
		h += sec("GIVE ITEM") + '<input id="dbGiveSearch" placeholder="Search" value="' + escapeHTML(this.giveSearch) + '" style="width:100%"><div id="dbGiveList" class="dbgrid"></div>';
		h += '<div>' + [1, 10, 64, 100, 500].map((n) => '<button data-dn="' + n + '" class="' + (this.giveN === n ? "on" : "") + '">x' + n + "</button>").join("") + "</div>";
		h += btn("give", this.giveID ? "GIVE " + this.giveN + " " + escapeHTML(itemName(this.giveID)) : "Pick an item", "primary");
		h += sec("SPAWN MOB") + '<div class="dbgrid2">' + DATA.mobs.filter((d) => d.key !== "custom" && d.key !== "villager").map((d) => '<button data-dm="' + d.key + '">' + escapeHTML(d.name.split(",")[0]) + "</button>").join("") + "</div>";
		$("debug").innerHTML = h;
		this.renderGive();
		this.update(true);
	},
	renderGive() {
		const el = $("dbGiveList");
		if (!el) return;
		const q = this.giveSearch.trim().toLowerCase();
		let h = "", n = 0;
		for (const id of ITEM_LIST) {
			if (q && !itemName(id).toLowerCase().includes(q) && !id.toLowerCase().includes(q)) continue;
			if (++n > 160) break;
			h += '<div class="slot' + (this.giveID === id ? " pick" : "") + '" data-dg="' + escapeHTML(id) + '" style="width:40px;height:40px">' + iconHTML(id, 26) + "</div>";
		}
		el.innerHTML = h;
	},
	/** the numbers that change, a few times a second */
	update(force = false) {
		const g = UI.game;
		if (!this.open || !g) return;
		this.t -= 1 / 60;
		if (!force && this.t > 0) return;
		this.t = 0.25;
		const pb = g.pb, set = (id, lines) => { const el = $(id); if (el) el.innerHTML = lines.map(escapeHTML).join("<br>"); };
		set("dbStats", [
			"Tick " + g.tickMs.toFixed(2) + " ms  FPS " + Math.round(Loop.fps),
			"XY " + pb.x.toFixed(1) + ", " + pb.y.toFixed(1) + "  " + (g.world.dim === Dimension.overworld ? "Overworld" : "Umbral"),
			"Seed " + g.seedValue + "  " + (g.gen.infinite ? "Infinite" : "Classic") + (g.gen.options.flat ? " flat" : ""),
			"Chunks " + g.world.chunks.size + "  Dirty " + [...g.world.chunks.values()].filter((c) => c.dirty).length,
			"Mobs " + g.mobs.length + "  Time " + g.timeOfDay.toFixed(2) + "  Day " + g.dayCount + "  Sky " + g.skyLevel,
		]);
		let hostile = 0, passive = 0, dying = 0;
		for (const m of g.mobs) { if (m.hp <= 0) dying++; else if (m.def.hostile) hostile++; else passive++; }
		set("dbEnt", ["Hostile " + hostile + "  Passive " + passive + "  Dying " + dying, "Shots " + g.projectiles.length + "  Drops " + g.drops.length + "  FX " + g.particles.length]);
		const m = this.selected;
		const sel = $("dbSel");
		if (sel) {
			if (m && m.hp > 0 && !m.removed) sel.innerHTML = '<div class="dbl" style="color:#a0e0ff">' + escapeHTML(m.def.name) + " #" + m.id + "  HP " + Math.round(m.hp) + "/" + Math.round(m.maxHP) + "  x " + m.b.x.toFixed(1) + " y " + m.b.y.toFixed(1) + " · " + m.ai + "</div>" + '<button data-da="mHeal">Heal</button><button data-da="mDouble">HP x2</button><button data-da="mKill">Kill</button><button data-da="mRemove" class="warn">Remove</button>';
			else sel.innerHTML = "";
		}
		const log = g.spawnLog ? [...g.spawnLog].sort((a, b) => b[1] - a[1]).slice(0, 8).map(([k, n]) => n + " × " + k) : [];
		set("dbSpawn", ["Monster limit " + g.monsterCap("surface") + " (caves " + g.monsterCap("cave") + ")  last: " + (g.spawnLast || "-")].concat(log));
		set("dbPerf", [
			"Tick " + g.tickMs.toFixed(2) + " ms  Draw " + PERF.renderMs.toFixed(2) + " ms",
			"AI " + (PERF.aiMs || 0).toFixed(2) + "  Light " + PERF.lightMs.toFixed(2) + " ms",
			"Chunk gen " + PERF.genMs.toFixed(1) + " ms, " + PERF.chunksGenerated + " made",
			"Light full " + PERF.lightFull + "  Sections painted " + PERF.sections,
		]);
		const x = Math.floor(pb.x);
		let ocean = -1;
		for (let d = 0; d < 3000 && ocean < 0; d += 16) for (const sx of [x - d, x + d]) { if (!g.gen.infinite && (sx < 0 || sx >= g.gen.width)) continue; if (g.gen.colBase(sx).biome === Biome.ocean) { ocean = sx; break; } }
		set("dbWorld", ["Gen version " + g.gen.genVersion + "  sea " + GEN_SEA + (g.gen.options.flat ? "  flat" : ""), "Biome " + BIOME_NAMES[g.biomeHere] + "  surface y " + g.world.surfaceY(x), ocean >= 0 ? "Nearest ocean x " + ocean + " (" + Math.abs(ocean - x) + " away)" : "No ocean within 3000", "Portal " + g.gen.portalX + "," + g.gen.portalY, "Structures chance " + g.gen.rareChance.toFixed(2)]);
	},
	teleport(g, x, y) {
		g.world.loadAround(Math.floor(x), 3);
		const pb = g.pb;
		pb.x = x; pb.y = y; pb.vx = 0; pb.vy = 0; g.fallPeak = 0;
		if (g.world.boxSolid(x - pb.w * 0.5, y - pb.h, x + pb.w * 0.5, y - 0.05)) pb.y = g.world.surfaceY(Math.floor(x));
		g.camX = pb.x; g.camY = pb.y - 2; g.camTX = g.camX; g.camTY = g.camY;
		g.light.valid = false;
	},
	act(g, a) {
		const pb = g.pb;
		switch (a) {
			case "close": this.toggle(); return;
			case "dawn": g.timeOfDay = 0.96; break;
			case "noon": g.timeOfDay = 0.25; break;
			case "dusk": g.timeOfDay = 0.5; break;
			case "night": g.timeOfDay = 0.75; break;
			case "heal": g.hp = g.maxHP; g.hunger = 20; g.air = 10; g.bumpHUD(); break;
			case "kit":
				for (const [id, n] of [["tool:pickaxe:diamond", 1], ["tool:axe:diamond", 1], ["sword:diamond", 1], ["bow", 1], ["ammo:arrow", 99], ["gun:rifle", 1], ["gun:pistol", 1], ["ammo:bullet", 99], ["block:torch", 99], ["block:planks", 99], ["block:stone", 99], ["food:cookedMeat", 30], ["armor:head:diamond", 1], ["armor:chest:diamond", 1], ["armor:legs:diamond", 1], ["mat:coal", 40], ["knife:diamond", 1], ["club:mace", 1], ["sling", 1], ["gun:crossbow", 1], ["gun:blunderbuss", 1], ["ammo:bolt", 99], ["gadget:bomb", 20]]) {
					if (!ITEMS.has(id)) continue;
					const gd = itemDef(id).gun;
					g.giveItem(id, n, gd ? gd.magazine : 0);
				}
				g.say("Debug kit added.", 2);
				break;
			case "killHostiles": for (const m of g.mobs) if (m.def.hostile && !m.tame && m.hp > 0) g.killMob(m, true); break;
			case "tpSpawn": this.teleport(g, g.spawnX, g.spawnY); break;
			case "tpSurface": this.teleport(g, Math.floor(pb.x) + 0.5, g.world.surfaceY(Math.floor(pb.x))); break;
			case "up20": pb.y -= 20; pb.vy = 0; g.fallPeak = 0; break;
			case "down20": pb.y += 20; pb.vy = 0; g.fallPeak = 0; break;
			case "right200": this.teleport(g, pb.x + 200, pb.y); break;
			case "left200": this.teleport(g, pb.x - 200, pb.y); break;
			case "tpGo": { const x = parseFloat($("dbX").value), y = parseFloat($("dbY").value); if (isFinite(x)) this.teleport(g, x, isFinite(y) ? y : pb.y); break; }
			case "select": {
				let best = null, bd = 1e9;
				const ax = g.aimValid ? g.aimX : pb.x, ay = g.aimValid ? g.aimY : pb.y - 1;
				for (const m of g.mobs) { if (m.hp <= 0) continue; const d = Math.hypot(m.b.x - ax, mobCY(m) - ay); if (d < bd) { bd = d; best = m; } }
				this.selected = best;
				break;
			}
			case "mHeal": if (this.selected) this.selected.hp = this.selected.maxHP; break;
			case "mDouble": if (this.selected) { this.selected.maxHP *= 2; this.selected.hp = this.selected.maxHP; } break;
			case "mKill": if (this.selected && this.selected.hp > 0) g.killMob(this.selected, false); break;
			case "mRemove": if (this.selected) { this.selected.removed = true; this.selected = null; } break;
			case "askDelete": this.confirmDelete = true; break;
			case "cancelDelete": this.confirmDelete = false; break;
			case "deleteAll": g.mobs = []; g.projectiles = []; g.drops = []; g.particles = []; this.selected = null; this.confirmDelete = false; break;
			case "resetMult": g.speedMult = 1; g.dmgOutMult = 1; g.dmgInMult = 1; g.mobHealthMult = 1; break;
			case "lava": { const x0 = Math.floor(pb.x) + g.facing * 3, y = Math.floor(pb.y); for (let dx = 0; dx < 4; dx++) { const x = x0 + (g.facing > 0 ? dx : -dx); g.world.set(x, y, T.lava); g.world.set(x, y + 1, T.stone); } break; }
			case "explode": g.explode(g.aimValid ? g.aimX : pb.x + g.facing * 4, g.aimValid ? g.aimY : pb.y - 1, 3, 20, SRC_ENV, false); break;
			case "spikes": { const x = Math.floor(pb.x) + g.facing * 2, y = Math.floor(pb.y) - 1; if (!g.world.solid(x, y)) g.world.set(x, y, T.spikes); break; }
			case "fire": g.playerBurn = 3; break;
			case "spawnTest": g.timeOfDay = 0.75; g.monsterSpawnCD = 0; g.spawnTimer = 0; g.spawnLog = new Map(); g.monstersOff = false; break;
			case "clearLog": g.spawnLog = new Map(); break;
			case "resetSystems": g.pauseMobs = g.pauseSpawning = g.pauseProjectiles = g.pauseWorldTicks = g.pauseParticles = false; break;
			case "give": if (this.giveID) { const gd = itemDef(this.giveID).gun; g.giveItem(this.giveID, this.giveN, gd ? gd.magazine : 0); g.say("+" + this.giveN + " " + itemName(this.giveID), 1.2); } return;
		}
		g.bumpHUD();
		this.render();
	},
	init() {
		const el = $("debug");
		el.addEventListener("click", (e) => {
			const g = UI.game;
			if (!g) return;
			const t = e.target.closest("[data-da],[data-dn],[data-dg],[data-dm]");
			if (!t) return;
			const ds = t.dataset;
			if (ds.da) this.act(g, ds.da);
			else if (ds.dn) { this.giveN = +ds.dn; this.render(); }
			else if (ds.dg) { this.giveID = ds.dg; this.render(); }
			else if (ds.dm) {
				const d = MOBS[ds.dm], x = g.pb.x + g.facing * 4;
				const y = d.flying ? g.pb.y - 3 : g.world.groundBelow(Math.floor(x), Math.floor(g.pb.y) - 3);
				const m = g.addMob(ds.dm, x, y);
				if (BOSS_KINDS.has(ds.dm)) m.persistent = true;
				this.selected = m;
				this.update(true);
			}
		});
		el.addEventListener("change", (e) => {
			const g = UI.game, k = e.target.dataset.dt;
			if (g && k) { g[k] = e.target.checked; g.bumpHUD(); }
		});
		el.addEventListener("input", (e) => {
			const g = UI.game;
			if (!g) return;
			const k = e.target.dataset.ds;
			if (k) { g[k] = +e.target.value; const lab = $("dbv_" + k); if (lab) lab.textContent = e.target.dataset.name + " x" + (+g[k]).toFixed(2); return; }
			if (e.target.id === "dbGiveSearch") { this.giveSearch = e.target.value; this.renderGive(); }
		});
		for (let i = 0; i < 24; i++) { const d = document.createElement("div"); d.className = "hidden aiTag"; $("floats").appendChild(d); this.aiEls.push(d); }
	},
	/** the AI overlay: each monster's state and why it is not attacking, over its head */
	drawAI(g) {
		const els = this.aiEls, k = View.tp / R.dpr;
		let i = 0;
		if (g.showAI) {
			for (const m of g.mobs) {
				if (i >= els.length) break;
				if (m.hp <= 0 || !thinks(m.kind)) continue;
				if (m.b.x < View.left - 2 || m.b.x > View.left + View.wT + 2 || m.b.y < View.top || m.b.y - m.b.h > View.top + View.hT) continue;
				const el = els[i++];
				const txt = m.ai + (m.sees ? " · sees" : "") + (m.why ? " · " + m.why : "");
				if (el.textContent !== txt) el.textContent = txt;
				el.style.left = ((m.b.x - View.left) * k) + "px";
				el.style.top = ((bodyTop(m.b) - View.top) * k - 22) + "px";
				el.classList.remove("hidden");
			}
		}
		for (; i < els.length; i++) if (!els[i].classList.contains("hidden")) els[i].classList.add("hidden");
	},
	/** hitboxes and chunk borders */
	drawWorld(g) {
		const dpr = R.dpr;
		if (g.showChunks) {
			const c0 = Math.floor(View.left / chunkW), c1 = Math.ceil((View.left + View.wT) / chunkW);
			for (let c = c0; c <= c1; c++) R.rect(View.sx(c * chunkW), 0, Math.max(1, dpr), R.H, rgba(0xFFE066, 0.45));
		}
		if (g.showHitboxes) {
			const box = (b, col) => R.frame(View.sx(bodyLeft(b)), View.sy(bodyTop(b)), b.w * View.tp, b.h * View.tp, Math.max(1, dpr), col);
			box(g.pb, rgba(0x60FF60, 0.9));
			for (const m of g.mobs) if (m.hp > 0) box(m.b, rgba(m.def.hostile ? 0xFF5050 : 0x60C0FF, 0.9));
		}
	},
};
overlayHooks.push((g) => Debug.drawWorld(g));
