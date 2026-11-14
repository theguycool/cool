const { chromium } = require('playwright');
(async () => {
	const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
	const page = await browser.newPage({ viewport: { width: 1024, height: 768 }, deviceScaleFactor: 1 });
	const errs = [];
	page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') errs.push(m.type() + ': ' + m.text()); });
	page.on('pageerror', (e) => errs.push('pageerror: ' + e.message + '\n' + e.stack));
	await page.addInitScript(() => {
		const store = new Map(); window.__store = store; window.__saved = [];
		const doc = (path) => ({
			async get() { const v = store.get(path); return { exists: v !== undefined, data: () => JSON.parse(v) }; },
			async set(o) { const t = JSON.stringify(o); if (t.length > 262144) throw new Error('too big'); store.set(path, t); },
			async delete() { store.delete(path); },
		});
		window.claude = { use: async (n) => n === 'db' ? { collection: (c) => ({ doc: (id) => doc(c + '/' + id) }) } : n === 'user' ? { id: async () => 'u123' } : n === 'downloads' ? { save: async (o) => { window.__saved.push(o); } } : null };
	});
	await page.goto('file://' + require('path').join(__dirname, '..', 'dist', 'test.html') + '');
	await page.waitForTimeout(1500);
	console.log('note', await page.evaluate(() => document.querySelector('#menu .note').textContent));
	await page.click('text=NEW WORLD');
	await page.fill('input[data-f="name"]', 'Cloud World');
	await page.click('text=CREATE');
	await page.waitForTimeout(1500);
	// dig a lot so the save has real changes, in several chunks
	await page.evaluate(() => { const g = UI.game; for (let x = -200; x < 200; x++) for (let y = 100; y < 130; y++) g.world.loadChunk(Math.floor(x / 16)), g.world.set(x, y, T.air); g.inv.add('block:stone', 50); });
	await page.keyboard.press('Escape');
	await page.click('button[data-act="save"]'); await page.waitForTimeout(1500);
	console.log('save', await page.evaluate(() => document.getElementById('pnote').textContent));
	await page.click('button[data-act="export"]'); await page.waitForTimeout(800);
	console.log('export', await page.evaluate(() => window.__saved.map((o) => o.filename + ' ' + o.data.length)));
	console.log('docs', await page.evaluate(() => [...window.__store.keys()].join(', ')));
	await page.click('button[data-act="quit"]'); await page.waitForTimeout(1500);
	await page.click('text=PLAY A SAVED WORLD'); await page.waitForTimeout(500);
	await page.click('button[data-play]'); await page.waitForTimeout(1500);
	console.log('loaded', await page.evaluate(() => { const g = UI.game; let air = 0; for (let x = -200; x < 200; x++) for (let y = 100; y < 130; y++) { g.world.loadChunk(Math.floor(x / 16)); if (g.world.tile(x, y) === T.air) air++; } return { name: g.worldName, air, stone: g.inv.total('block:stone') }; }));
	// import the exported text as a new world
	await page.keyboard.press('Escape');
	await page.click('button[data-act="quit"]'); await page.waitForTimeout(1000);
	await page.click('text=OPEN A WORLD FILE'); await page.waitForTimeout(300);
	await page.evaluate(() => { document.getElementById('mtext').value = window.__saved[0].data; });
	await page.click('button[data-act="doimport"]'); await page.waitForTimeout(1500);
	console.log('imported', await page.evaluate(() => UI.game && UI.game.worldName));
	await page.keyboard.press('Escape');
	await page.click('button[data-act="quit"]'); await page.waitForTimeout(1000);
	await page.click('text=PLAY A SAVED WORLD'); await page.waitForTimeout(500);
	console.log('list', await page.evaluate(() => [...document.querySelectorAll('.world b')].map((e) => e.textContent)));
	await page.click('button[data-del]'); await page.waitForTimeout(200);
	await page.click('button[data-del]'); await page.waitForTimeout(800);
	console.log('after delete', await page.evaluate(() => [...document.querySelectorAll('.world b')].map((e) => e.textContent)), await page.evaluate(() => [...window.__store.keys()].length));
	console.log(errs.join('\n'));
	await browser.close();
})();
