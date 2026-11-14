const { chromium } = require('playwright');
(async () => {
	const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
	const page = await browser.newPage({ viewport: { width: 1180, height: 820 }, deviceScaleFactor: 1 });
	const errs = [];
	page.on('pageerror', (e) => errs.push('pageerror: ' + e.message + '\n' + e.stack));
	await page.goto('file://' + require('path').join(__dirname, '..', 'dist', 'test.html') + '');
	await page.waitForTimeout(1500);
	await page.evaluate(() => { const g = new Game(0, true, 7, Menu.settings, GEN_VERSION, { flat: true, trees: false }, true); g.isTest = true; g.noSpawning = true; startGame(g); });
	await page.waitForTimeout(800);
	const r = await page.evaluate(async () => {
		const g = UI.game, out = {};
		for (const [id, kind, dx] of [['gun:rifle', 'cow', -8], ['gun:pistol', 'zombie', 7], ['gun:crossbow', 'skeleton', 9], ['gun:blunderbuss', 'pig', -5], ['sling', 'zombie', 8], ['spear:iron', 'zombie', 2], ['hammer:iron', 'skeleton', 2]]) {
			g.mobs = []; g.projectiles = [];
			const st = stack(id, 1); const gd = itemDef(id).gun; if (gd) st.extra = gd.magazine;
			g.inv.slots[1] = st; g.inv.add('ammo:bullet', 30); g.inv.add('ammo:bolt', 30); g.inv.add('block:stone', 30); g.setSel(1);
			const x = g.pb.x + dx; const m = g.addMob(kind, x, g.world.surfaceY(Math.floor(x))); m.persistent = true;
			const hp0 = m.hp;
			ActStick.held = true;
			await new Promise((res) => setTimeout(res, 1600));
			ActStick.release();
			await new Promise((res) => setTimeout(res, 300));
			out[id] = [kind, hp0, Math.round(m.hp), g.inv.slots[1] ? g.inv.slots[1].extra : -1];
			g.hp = g.maxHP;
		}
		return out;
	});
	console.log(JSON.stringify(r));
	console.log(errs.join('\n'));
	await browser.close();
})();
