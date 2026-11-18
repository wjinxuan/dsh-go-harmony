import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { createRequire } from 'node:module';
import { assetId, conversationFile, conversationHtml } from '../runtime/share-codec.mjs';

test('exported file interoperates with original offline replay, timing controls and inert content', { skip: !process.env.DSH_RENDER_PLAYWRIGHT }, async () => {
  const { chromium } = createRequire(import.meta.url)(process.env.DSH_RENDER_PLAYWRIGHT);
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7L8AAAAASUVORK5CYII=', 'base64');
  const id = assetId(png);
  const file = conversationFile({ v: 2, kind: 'conversation', schema: 1, title: '</title><img src=x onerror="window.pwned=1">',
    start: '2026-11-16T00:00:00Z', entries: [
      { type: 'turn', t: 0, d: 30000, end: 'completed', steps: 1 },
      { type: 'user', t: 0, text: 'Read this image', images: [{ id, w: 1, h: 1, name: 'fixture.png' }] },
      { type: 'reply', t: 1000, d: 25000, text: '**Offline answer**\n<script>window.pwned=2</script>\n![external](https://invalid.example/tracker.png)', think: 'Reasoning text' },
      { type: 'tool', t: 2000, d: 3000, name: 'read', args: { path: 'report.txt' }, summary: 'Read report', result: 'tool contents' }
    ] }, { [id]: { type: 'image/png', data: png.toString('base64'), w: 1, h: 1 } });
  const html = conversationHtml(file.file, file.body.title, await readFile(new URL('../runtime/vendor/replay/viewer.html', import.meta.url), 'utf8'));
  const server = createServer((req, res) => { res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }).end(html); }).listen(0, '127.0.0.1');
  await once(server, 'listening'); let browser;
  try {
    browser = await chromium.launch({ executablePath: process.env.DSH_RENDER_BROWSER || undefined, headless: true });
    const page = await browser.newPage({ viewport: { width: 360, height: 720 } });
    const errors = [], external = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('**/*', route => { if (new URL(route.request().url()).hostname !== '127.0.0.1') { external.push(route.request().url()); return route.abort(); } return route.continue(); });
    await page.goto(`http://127.0.0.1:${server.address().port}/replay`);
    await page.locator('.dv-seek').waitFor();
    assert.equal(await page.evaluate(() => window.pwned), undefined);
    const decoded = await page.evaluate(file => window.DshgoViewer.openFile(file), file.file);
    assert.ok(JSON.stringify(decoded).includes('Offline answer'));
    await page.locator('.dv-speed').click(); assert.equal(await page.locator('.dv-speed').textContent(), '2×');
    await page.locator('.dv-pill').first().click();
    assert.match(await page.locator('body').textContent(), /Offline answer/);
    assert.match(await page.locator('body').textContent(), /Read report/);
    assert.equal(await page.locator('script:not([type="application/json"])').count(), 1);
    assert.equal(await page.locator('img[src^="http"]').count(), 0);
    assert.equal(await page.evaluate(() => window.pwned), undefined);
    await page.locator('.dv-seek').evaluate(input => { input.value = '0'; input.dispatchEvent(new Event('input', { bubbles: true })); });
    assert.equal(await page.locator('.dv-seek').inputValue(), '0');
    await page.locator('.dv-key').click();
    await page.waitForFunction(() => Number(document.querySelector('.dv-seek').value) > 0);
    await page.locator('.dv-key').click();
    assert.deepEqual(external, []); assert.deepEqual(errors, []);
  } finally { await browser?.close(); await new Promise(done => server.close(done)); }
});
