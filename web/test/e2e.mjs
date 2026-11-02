// Full pairing in a real browser: page shows QR -> simulated phone seals a snapshot
// -> relay -> page decrypts with WebCrypto and renders the dashboard.
// Usage: node test/e2e.mjs [screenshot-dir]
import { createRequire } from 'node:module';
import { createServer } from '../server.mjs';
import { parseQr, seal, sampleSnapshot } from './phone.mjs';

const { chromium } = createRequire(import.meta.url)('playwright');   // pre-installed globally in CI images; else: npm i -D playwright

const out = process.argv[2];
const srv = createServer();
await new Promise((r) => srv.listen(0, '127.0.0.1', r));
const base = `http://localhost:${srv.address().port}`;
const browser = await chromium.launch();
let failed = false;
try {
  for (const [name, vp, scheme, locale] of [['desktop', { width: 1200, height: 900 }, 'light', 'hu-HU'], ['mobile', { width: 390, height: 844 }, 'dark', 'en-US']]) {
    const page = await browser.newPage({ viewport: vp, colorScheme: scheme, locale });
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    await page.goto(base + '/');
    await page.waitForFunction(() => document.getElementById('qr').src.startsWith('data:image'));
    if (out) await page.screenshot({ path: `${out}/web-pair-${name}.png`, fullPage: true });
    const qr = await page.evaluate(() => session.qr);
    const p = parseQr(qr);
    const body = seal(p.webPublic, p.sid, Buffer.from(JSON.stringify(sampleSnapshot())));
    const r = await fetch(`${p.base}/api/relay/${p.sid}`, { method: 'POST', body });
    if (r.status !== 204) throw new Error(`relay POST ${r.status}`);
    await page.waitForSelector('#dash:not([hidden])', { timeout: 10000 });
    const title = await page.textContent('#dash-title');
    const heading = await page.textContent('#profile .card h2');
    if (heading !== (locale === 'hu-HU' ? 'Fogmosási idő (napi átlag)' : 'Brushing time (daily average)')) { console.log('wrong language:', heading); failed = true; }
    const tiles = await page.$$eval('.tile .v', (els) => els.map((e) => e.textContent));
    const alerts = await page.$$eval('.insights li.alert', (els) => els.length);
    const bars = await page.$$eval('.chart .bar', (els) => els.length);
    const scrollW = await page.evaluate(() => document.documentElement.scrollWidth);
    console.log(name, { title, tiles, alerts, bars, overflow: scrollW > vp.width, errors });
    if (!title.includes('Anna') || bars !== 30 || alerts !== 1 || errors.length || scrollW > vp.width) failed = true;
    await page.click('.tab:nth-child(2)');
    if (!(await page.textContent('#dash-title')).includes('Bence')) failed = true;
    await page.click('.tab:nth-child(1)');
    await page.hover('.chart .bar-hit >> nth=25');
    if (out) await page.screenshot({ path: `${out}/web-dashboard-${name}.png`, fullPage: true });
    await page.close();
  }
} finally {
  await browser.close();
  srv.close();
  srv.closeAllConnections?.();
}
console.log(failed ? 'E2E FAILED' : 'E2E OK');
process.exit(failed ? 1 : 0);
