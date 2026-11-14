const { chromium } = require('playwright');
(async () => {
	const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
	const ctx = await browser.newContext({ viewport: { width: 820, height: 1180 }, deviceScaleFactor: 2, hasTouch: true, isMobile: true });
	const page = await ctx.newPage();
	const errs = [];
	page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') errs.push(m.type() + ': ' + m.text()); });
	page.on('pageerror', (e) => errs.push('pageerror: ' + e.message + '\n' + e.stack));
	await page.goto('file://' + require('path').join(__dirname, '..', 'dist', 'test.html') + '');
	await page.waitForTimeout(2000);
	await page.screenshot({ path: 'ipad_menu.png' });
	await page.tap('text=NEW WORLD');
	await page.fill('input[data-f="seed"]', 'ipad');
	await page.tap('button[data-pick="mode"][data-v="1"]');
	await page.tap('text=CREATE');
	await page.waitForTimeout(2500);
	await page.tap('#bInv'); await page.waitForTimeout(300);
	await page.screenshot({ path: 'ipad_items.png' });
	await page.fill('#isearch', 'chest'); await page.waitForTimeout(300);
	await page.tap('[data-give="block:chest"]'); await page.waitForTimeout(200);
	await page.tap('button[data-act="close"]');
	// place a chest next to the player and open it
	const r = await page.evaluate(() => {
		const g = UI.game;
		const x = Math.floor(g.pb.x) + 2; let y = Math.floor(g.pb.y) - 1; while (g.world.tile(x, y + 1) === T.air) y++; while (g.world.tile(x, y) !== T.air) y--;
		const i = g.inv.slots.findIndex((s) => s && s.id === 'block:chest'); g.setSel(i);
		g.world.set(x, y, T.chest);
		g.world.setChestItems(x, y, [stack('mat:coal', 5), stack('food:bread', 2)]);
		g.interact(x + 0.5, y + 0.5);
		return { x, y, panel: UI.panelOpen, open: g.openChest };
	});
	console.log(JSON.stringify(r));
	await page.waitForTimeout(300);
	await page.screenshot({ path: 'ipad_chest.png' });
	await page.tap('[data-c="0"]'); await page.waitForTimeout(200);
	console.log('coal', await page.evaluate(() => UI.game.inv.total('mat:coal')));
	await page.tap('button[data-act="close"]');
	// night, in a cave with a torch
	await page.evaluate(() => { const g = UI.game; g.timeOfDay = 0.75; });
	await page.waitForTimeout(800);
	await page.screenshot({ path: 'ipad_night.png' });
	await page.evaluate(() => { const g = UI.game; g.pb.y = g.pb.y + 30; g.noclip = true; g.camY = g.pb.y; g.camTY = g.camY; g.inv.slots[0] = stack('block:torch', 10); g.setSel(0); });
	await page.waitForTimeout(1200);
	await page.screenshot({ path: 'ipad_cave.png' });
	// walking stick with touch
	await page.evaluate(() => { const g = UI.game; g.noclip = false; g.timeOfDay = 0.2; g.pb.y = g.world.surfaceY(Math.floor(g.pb.x)); g.camY = g.pb.y; });
	await page.waitForTimeout(500);
	const fps = await page.evaluate(() => ({ fps: Loop.fps, tick: UI.game.tickMs, draw: PERF.renderMs, light: PERF.lightMs }));
	console.log(JSON.stringify(fps));
	console.log(errs.join('\n'));
	await browser.close();
})();
