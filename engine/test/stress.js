const { chromium } = require('playwright');
(async () => {
	const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
	const page = await browser.newPage({ viewport: { width: 1024, height: 768 }, deviceScaleFactor: 1 });
	const errs = [];
	page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') errs.push(m.type() + ': ' + m.text()); });
	page.on('pageerror', (e) => errs.push('pageerror: ' + e.message + '\n' + e.stack));
	await page.goto('file://' + require('path').join(__dirname, '..', 'dist', 'test.html') + '');
	await page.waitForTimeout(1500);
	await page.click('text=STRESS TEST');
	await page.waitForTimeout(9000);
	await page.screenshot({ path: 'stress_mid.png' });
	await page.waitForTimeout(13000);
	await page.screenshot({ path: 'stress_done.png' });
	console.log(await page.evaluate(() => Stress.report));
	console.log(errs.join('\n'));
	await browser.close();
})();
