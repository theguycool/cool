const { chromium } = require('playwright');
(async () => {
	const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
	const ctx = await browser.newContext({ viewport: { width: 1180, height: 820 }, deviceScaleFactor: 1 });
	const page = await ctx.newPage();
	const errs = [];
	page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') errs.push(m.type() + ': ' + m.text()); });
	page.on('pageerror', (e) => errs.push('pageerror: ' + e.message + '\n' + e.stack));
	await page.goto('file://' + require('path').join(__dirname, '..', 'dist', 'test.html') + '');
	await page.waitForTimeout(2000);
	await page.click('text=NEW WORLD');
	await page.fill('input[data-f="seed"]', '12345');
	await page.click('text=CREATE');
	await page.waitForTimeout(2500);
	const log = (s, o) => console.log(s, JSON.stringify(o));
	// walk right with the keyboard
	const x0 = await page.evaluate(() => UI.game.pb.x);
	await page.keyboard.down('KeyD'); await page.waitForTimeout(1200); await page.keyboard.up('KeyD');
	const x1 = await page.evaluate(() => UI.game.pb.x);
	log('walked', { x0, x1 });
	// jump
	await page.keyboard.down('Space'); await page.waitForTimeout(150);
	const yJ = await page.evaluate(() => ({ vy: UI.game.pb.vy, onGround: UI.game.pb.onGround }));
	await page.keyboard.up('Space'); await page.waitForTimeout(800);
	log('jump', yJ);
	// find a tree log near and mine it with the mouse held
	const target = await page.evaluate(() => {
		const g = UI.game, px = Math.floor(g.pb.x);
		for (let d = 0; d < 12; d++) for (const s of [1, -1]) {
			const x = px + d * s;
			for (let y = Math.floor(g.pb.y) - 6; y < Math.floor(g.pb.y) + 2; y++) if (IS_LOG[g.world.tile(x, y)]) return { x, y, t: g.world.tile(x, y) };
		}
		return null;
	});
	log('log', target);
	const scr = async (wx, wy) => page.evaluate(([wx, wy]) => { const k = View.tp / R.dpr; return [(wx - View.left) * k, (wy - View.top) * k]; }, [wx, wy]);
	if (target) {
		// walk next to it
		await page.evaluate((t) => { const g = UI.game; g.pb.x = t.x - 2.5; g.pb.y = g.world.surfaceY(Math.floor(g.pb.x)); g.camX = g.pb.x; g.camTX = g.camX; }, target);
		await page.waitForTimeout(500);
		await page.keyboard.press('Digit2');
		const [sx, sy] = await scr(target.x + 0.5, target.y + 0.5);
		await page.mouse.move(sx, sy); await page.mouse.down();
		await page.waitForTimeout(4500);
		await page.mouse.up();
		await page.waitForTimeout(1500);
		await page.screenshot({ path: 'mined.png' });
		log('drop', await page.evaluate(() => ({ p: [UI.game.pb.x, UI.game.pb.y], d: UI.game.drops.map((d) => [d.stack.id, d.x, d.y, d.vx, d.vy, d.onGround, d.pickDelay, d.age, d.heldBack]) })));
		const r = await page.evaluate((t) => ({ tile: UI.game.world.tile(t.x, t.y), logs: UI.game.inv.total('block:log') + UI.game.inv.total('block:birchLog') + UI.game.inv.total('block:jungleLog'), drops: UI.game.drops.length, inv: UI.game.inv.slots.filter(Boolean).map((s) => s.id + 'x' + s.n) }), target);
		log('after mining', r);
	}
	// mine dirt under the player for blocks
	await page.evaluate(() => { const g = UI.game; for (let i = 0; i < 5; i++) g.inv.add('block:dirt', 1); g.inv.add('block:log', 3); g.bumpHUD(); });
	// open the bag and craft planks then a workbench
	await page.click('#bInv'); await page.waitForTimeout(300);
	await page.screenshot({ path: 'bag.png' });
	await page.click('button[data-tab="craft"]'); await page.waitForTimeout(300);
	await page.screenshot({ path: 'craft.png' });
	const planksId = await page.evaluate(() => RECIPES.find((r) => r.out === 'block:planks').id);
	for (let k = 0; k < 3; k++) { await page.click(`button[data-craft="${planksId}"]`); await page.waitForTimeout(150); }
	const benchId = await page.evaluate(() => RECIPES.find((r) => r.out === 'block:workbench').id);
	await page.click(`button[data-craft="${benchId}"]`); await page.waitForTimeout(200);
	log('crafted', await page.evaluate(() => ({ planks: UI.game.inv.total('block:planks'), bench: UI.game.inv.total('block:workbench') })));
	await page.click('button[data-act="close"]'); await page.waitForTimeout(200);
	// place the workbench beside the player: select its slot then tap the spot
	const slot = await page.evaluate(() => UI.game.inv.slots.findIndex((s) => s && s.id === 'block:workbench'));
	log('bench slot', slot);
	if (slot >= 0 && slot < 10) {
		await page.click(`#hotbar .slot[data-i="${slot}"]`);
		const spot = await page.evaluate(() => { const g = UI.game; const x = Math.floor(g.pb.x) + 2; let y = Math.floor(g.pb.y) - 1; while (g.world.tile(x, y + 1) === T.air) y++; while (g.world.tile(x, y) !== T.air) y--; return { x, y }; });
		const [sx, sy] = await scr(spot.x + 0.5, spot.y + 0.5);
		await page.mouse.move(sx, sy); await page.mouse.down(); await page.waitForTimeout(150); await page.mouse.up();
		await page.waitForTimeout(400);
		log('placed', await page.evaluate((s) => ({ tile: TILE[UI.game.world.tile(s.x, s.y)].key, left: UI.game.inv.total('block:workbench') }), spot));
		await page.screenshot({ path: 'placed.png' });
		// tap the bench: crafting opens at the bench
		await page.mouse.move(sx, sy); await page.mouse.down(); await page.waitForTimeout(80); await page.mouse.up();
		await page.waitForTimeout(400);
		log('bench tap', await page.evaluate(() => ({ panel: UI.panelOpen, station: UI.game.craftStation })));
		await page.screenshot({ path: 'benchcraft.png' });
		await page.keyboard.press('Escape');
	}
	// save, quit, load
	await page.keyboard.press('Escape'); await page.waitForTimeout(200);
	await page.click('button[data-act="save"]'); await page.waitForTimeout(800);
	log('save note', await page.evaluate(() => document.getElementById('pnote').textContent));
	const before = await page.evaluate(() => ({ x: UI.game.pb.x, inv: UI.game.inv.slots.filter(Boolean).map((s) => s.id + 'x' + s.n).join(','), time: UI.game.timeOfDay }));
	await page.click('button[data-act="quit"]'); await page.waitForTimeout(800);
	await page.screenshot({ path: 'menu2.png' });
	await page.click('text=PLAY A SAVED WORLD'); await page.waitForTimeout(400);
	await page.screenshot({ path: 'load.png' });
	await page.click('button[data-play]'); await page.waitForTimeout(2000);
	const after = await page.evaluate(() => ({ x: UI.game.pb.x, inv: UI.game.inv.slots.filter(Boolean).map((s) => s.id + 'x' + s.n).join(','), time: UI.game.timeOfDay }));
	log('before', before); log('after', after);
	await page.screenshot({ path: 'loaded.png' });
	console.log(errs.join('\n'));
	await browser.close();
})();
