const { chromium } = require('playwright');
(async () => {
	const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
	const page = await browser.newPage({ viewport: { width: 1180, height: 820 }, deviceScaleFactor: 1 });
	const errs = [];
	page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') errs.push(m.type() + ': ' + m.text()); });
	page.on('pageerror', (e) => errs.push('pageerror: ' + e.message + '\n' + e.stack));
	await page.goto('file://' + require('path').join(__dirname, '..', 'dist', 'test.html') + '');
	await page.waitForTimeout(1500);
	await page.click('text=NEW WORLD');
	await page.fill('input[data-f="seed"]', '4242');
	await page.click('text=CREATE');
	await page.waitForTimeout(1500);
	const log = (s, o) => console.log(s, JSON.stringify(o));
	// daytime: animals come
	await page.evaluate(() => { UI.game.timeOfDay = 0.2; });
	await page.waitForTimeout(9000);
	log('day', await page.evaluate(() => ({ mobs: UI.game.mobs.map((m) => m.kind).join(','), log: [...(UI.game.spawnLog || new Map())].slice(0, 8) })));
	// a lineup of creatures beside the player
	await page.evaluate(() => {
		const g = UI.game; g.noSpawning = true; g.mobs = [];
		const kinds = ['pig', 'cow', 'sheep', 'chicken', 'wolf', 'bear', 'zombie', 'skeleton', 'archer', 'crawler', 'golem', 'slime', 'scorpion', 'tiger'];
		let x = g.pb.x - 20;
		for (const k of kinds) { const y = g.world.surfaceY(Math.floor(x)); const m = g.addMob(k, x + 0.5, y); m.persistent = true; x += 3; }
		g.settings.peaceful = true;
	});
	await page.waitForTimeout(1500);
	await page.screenshot({ path: 'mobs_day.png' });
	// night fight: a zombie and a sword
	await page.evaluate(() => {
		const g = UI.game; g.mobs = []; g.settings.peaceful = false; g.timeOfDay = 0.75;
		g.inv.slots[1] = stack('sword:iron', 1); g.setSel(1);
		const y = g.world.surfaceY(Math.floor(g.pb.x + 4));
		window.__z = g.addMob('zombie', g.pb.x + 4, y);
	});
	await page.waitForTimeout(2500);
	log('zombie came', await page.evaluate(() => ({ dist: Math.abs(window.__z.b.x - UI.game.pb.x).toFixed(2), ai: window.__z.ai, hp: UI.game.hp, zhp: window.__z.hp })));
	// hold the attack stick (auto aim)
	await page.evaluate(() => { ActStick.held = true; });
	await page.waitForTimeout(2500);
	await page.evaluate(() => { ActStick.release(); });
	await page.waitForTimeout(800);
	log('after fight', await page.evaluate(() => ({ zhp: window.__z.hp, removed: window.__z.removed, playerHP: UI.game.hp, drops: UI.game.drops.map((d) => d.stack.id), kills: UI.game.kills })));
	// bow at a skeleton
	await page.evaluate(() => {
		const g = UI.game; g.mobs = []; g.inv.slots[2] = stack('bow', 1); g.inv.add('ammo:arrow', 30); g.setSel(2);
		const x = g.pb.x + 9; window.__s = g.addMob('pig', x, g.world.surfaceY(Math.floor(x)));
		g.hp = g.maxHP;
	});
	await page.evaluate(() => { ActStick.held = true; });
	await page.waitForTimeout(700);
	await page.screenshot({ path: 'bow.png' });
	await page.evaluate(() => { ActStick.release(); });
	await page.waitForTimeout(1200);
	log('bow', await page.evaluate(() => ({ pigHP: window.__s.hp, arrows: UI.game.inv.total('ammo:arrow'), proj: UI.game.projectiles.length })));
	// rifle
	await page.evaluate(() => {
		const g = UI.game; g.mobs = []; const st = stack('gun:rifle', 1); st.extra = 4; g.inv.slots[3] = st; g.inv.add('ammo:bullet', 20); g.setSel(3);
		const x = g.pb.x - 8; window.__c = g.addMob('cow', x, g.world.surfaceY(Math.floor(x)));
	});
	await page.evaluate(() => { ActStick.held = true; });
	await page.waitForTimeout(1500);
	await page.evaluate(() => { ActStick.release(); });
	await page.waitForTimeout(300);
	log('rifle', await page.evaluate(() => ({ cowHP: window.__c.hp, loaded: UI.game.inv.slots[3].extra })));
	// night spawning
	await page.evaluate(() => { const g = UI.game; g.mobs = []; g.noSpawning = false; g.timeOfDay = 0.75; g.godMode = true; g.spawnLog = new Map(); });
	await page.waitForTimeout(15000);
	log('night', await page.evaluate(() => ({ mobs: UI.game.mobs.map((m) => m.kind + (m.hunter ? '*' : '')).join(','), log: [...UI.game.spawnLog] })));
	await page.screenshot({ path: 'night_mobs.png' });
	log('perf', await page.evaluate(() => ({ fps: Loop.fps, tick: UI.game.tickMs, ai: PERF.aiMs, draw: PERF.renderMs })));
	console.log(errs.join('\n'));
	await browser.close();
})();
