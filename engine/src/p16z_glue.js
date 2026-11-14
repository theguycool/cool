// Creatures and fighting joined to the rest of the game: the order they run in each frame, tapping a
// creature (taming), what is saved, and the bosses' place (they come with their lairs in phase 3).

/** bosses run their own fights (phase 3, with their lairs); false: the creature's usual update runs */
function bossUpdate(g, m, dt) { return false; }

tickHooks.push((g, dt) => {
	g.updateMobs(dt);
	g.updateSpawning(dt);
	g.updateProjectiles(dt);
	g.updateCombatFX(dt);
});

// a tame-able creature under the finger, with what it likes in hand, is tapped rather than hit
function tameableAt(g, wx, wy) {
	const it = g.heldItem;
	if (!it) return null;
	for (const m of g.mobsNear(wx - 3, wx + 3)) {
		if (m.hp <= 0 || m.tame) continue;
		const ok = (m.kind === "wolf" && it === "mat:bone") || (m.kind === "cat" && (it === "food:rawFish" || it === "food:cookedFish"));
		if (ok && wx >= bodyLeft(m.b) - 0.4 && wx <= bodyRight(m.b) + 0.4 && wy >= bodyTop(m.b) - 0.4 && wy <= m.b.y + 0.4) return m;
	}
	return null;
}
function interactiveHook(g, wx, wy, t) { return !!tameableAt(g, wx, wy); }
function interactHook(g, tx, ty, t, wx, wy) {
	const m = tameableAt(g, wx, wy);
	if (m) g.tryTame(m);
}
function hostileAtHook(g, wx, wy) {
	for (const m of g.mobsNear(wx - 4, wx + 4)) {
		if (m.hp <= 0 || m.tame || !g.isThreat(m)) continue;
		if (wx >= bodyLeft(m.b) - 0.4 && wx <= bodyRight(m.b) + 0.4 && wy >= bodyTop(m.b) - 0.4 && wy <= m.b.y + 0.4) return true;
	}
	return false;
}
/** weapons and throwables in hand; true when the item was one of them */
function useItemHook(g, held, dt, pressed, released) {
	if (held === "bow") { g.handleBow(dt, pressed, released); return true; }
	if (!g.useHeld || !held) return false;
	const k = itemKind(held);
	if (k === "gun") { g.useGun(held, pressed); return true; }
	if (held === "sling") { g.useSling(pressed); return true; }
	if (held === "gadget:bomb") { if (pressed) g.throwBomb(); return true; }
	if (MELEE_KINDS.has(k)) { g.useMeleeWeapon(held, pressed); return true; }
	return false;
}
/** a tool or a fist aimed at a creature fights it */
function meleeHook(g, id, pressed) { return g.fightWith(id, pressed); }

// pets and creatures that keep their place (a mimic woken, later the bosses' kin) are saved
saveHooks.push((g, o) => {
	o.mobs = g.mobs.filter((m) => m.hp > 0 && !m.removed && (m.tame || m.persistent) && m.lair === 0).map((m) => ({ kind: m.def.id, x: m.b.x, y: m.b.y, hp: m.hp, maxHP: m.maxHP, tame: m.tame, variant: m.variant, loot: m.loot.length ? m.loot : undefined }));
	o.kills = g.kills || 0;
});
loadHooks.push((g, o) => {
	for (const s of o.mobs || []) {
		const d = MOB_BY_ID[s.kind];
		if (!d) continue;
		const m = g.addMob(d.key, s.x, s.y);
		m.hp = s.hp; m.maxHP = s.maxHP; m.tame = !!s.tame; m.persistent = true; m.variant = s.variant || 0;
		if (s.loot) m.loot = s.loot.map((x) => stack(x.id, x.n, x.extra || 0, x.inf || null));
	}
	g.kills = o.kills || 0;
});
