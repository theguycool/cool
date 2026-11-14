const { chromium } = require('playwright');
(async () => {
	const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
	const ctx = await browser.newContext({ viewport: { width: 820, height: 1180 }, deviceScaleFactor: 2, hasTouch: true, isMobile: true });
	const page = await ctx.newPage();
	const errs = [];
	page.on('console', (m) => errs.push(m.type() + ': ' + m.text()));
	page.on('pageerror', (e) => errs.push('pageerror: ' + e.message));
	await page.goto('file://' + require('path').join(__dirname, '..', 'dist', 'test.html') + '');
	await page.waitForTimeout(1500);
	await page.tap('text=NEW WORLD');
	await page.fill('input[data-f="seed"]', '777');
	await page.tap('text=CREATE');
	await page.waitForTimeout(2500);
	const cdp = await ctx.newCDPSession(page);
	await page.evaluate(() => { window.__ev = []; for (const t of ['pointerdown', 'pointermove', 'pointerup', 'pointercancel', 'touchstart', 'touchend', 'touchcancel']) document.getElementById('world').addEventListener(t, (e) => window.__ev.push(t + (e.pointerType ? ':' + e.pointerType : ''))); });
	const hold = async (wx, wy, ms) => {
		const [sx, sy] = await page.evaluate(([wx, wy]) => { const k = View.tp / R.dpr; return [(wx - View.left) * k, (wy - View.top) * k]; }, [wx, wy]);
		await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: sx, y: sy, id: 1 }] });
		for (let t = 0; t < ms; t += 100) { await page.waitForTimeout(100); if (false) console.log(JSON.stringify(await page.evaluate(() => { const g = UI.game; return { aim: [g.aimX.toFixed(2), g.aimY.toFixed(2), g.aimValid], useHeld: g.useHeld, pend: g.pendingInteract, mining: g.mining, mineP: g.mineP.toFixed(2), reach: g.inReach(g.aimX, g.aimY), ap: UI.aimPointer, p: [g.pb.x.toFixed(1), g.pb.y.toFixed(1)] }; }))); await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: sx + (t % 200 ? 1 : 0), y: sy, id: 1 }] }); }
		await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
	};
	// with the torch in hand, then with an empty hand
	for (const slot of [0, 1]) {
		await page.evaluate((s) => UI.game.setSel(s), slot);
		const spot = await page.evaluate(() => { const g = UI.game; const x = Math.floor(g.pb.x) + 1; const y = g.world.surfaceY(x); return { x, y, t: TILE[g.world.tile(x, y)].key, held: g.heldItem }; });
		await hold(spot.x + 0.5, spot.y + 0.5, 2000);
		await page.waitForTimeout(200);
		console.log('slot', slot, JSON.stringify(spot), '->', await page.evaluate((s) => TILE[UI.game.world.tile(s.x, s.y)].key, spot));
	}
	// a pinch outward zooms in
	const z0 = await page.evaluate(() => UI.game.settings.tilePx);
	await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 300, y: 500, id: 1 }, { x: 500, y: 500, id: 2 }] });
	for (let k = 1; k <= 5; k++) { await page.waitForTimeout(50); await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: 300 - k * 20, y: 500, id: 1 }, { x: 500 + k * 20, y: 500, id: 2 }] }); }
	await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
	await page.waitForTimeout(200);
	const z1 = await page.evaluate(() => UI.game.settings.tilePx);
	await page.tap('#bZoomOut'); await page.waitForTimeout(100);
	const z2 = await page.evaluate(() => UI.game.settings.tilePx);
	console.log('zoom', z0, '-> pinch', z1, '-> minus', z2);
	await page.screenshot({ path: 'zoomed.png' });
	console.log(errs.join('\n'));
	await browser.close();
})();
