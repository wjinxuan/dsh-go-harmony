import assert from 'node:assert/strict';
import { createReadStream } from 'node:fs';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { resolve, extname } from 'node:path';
import test from 'node:test';
import { createRequire } from 'node:module';

test('bundled formula/diagram renderers render offline and keep content inert', { skip: !process.env.DSH_RENDER_PLAYWRIGHT }, async () => {
  const { chromium } = createRequire(import.meta.url)(process.env.DSH_RENDER_PLAYWRIGHT);
  const root = resolve('entry/src/main/resources/rawfile/render');
  const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf' };
  const server = createServer((req, res) => {
    const path = resolve(root, '.' + req.url.split('?')[0]);
    if (!path.startsWith(root + '/')) { res.writeHead(403).end(); return; }
    res.setHeader('content-type', mime[extname(path)] || 'application/octet-stream');
    createReadStream(path).on('error', () => res.end()).pipe(res);
  }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  let browser;
  try {
    browser = await chromium.launch({ headless: true, executablePath: process.env.DSH_RENDER_BROWSER || undefined });
    const page = await browser.newPage({ viewport: { width: 360, height: 640 } });
    const errors = [], external = [];
    page.on('pageerror', err => errors.push(err.message));
    await page.route('**/*', route => { if (new URL(route.request().url()).hostname !== '127.0.0.1') {
      external.push(route.request().url()); return route.abort();
    } return route.continue(); });
    await page.addInitScript(() => { window.results = []; window.renderBridge = {
      height: (height, revision) => window.results.push(['height', height, revision]),
      status: (state, revision) => window.results.push(['status', state, revision]),
      link: (url, revision) => window.results.push(['link', url, revision])
    }; });
    const base = `http://127.0.0.1:${server.address().port}`;
    await page.goto(base + '/math.html');
    await page.evaluate(() => window.renderMath([{ kind: 'text', text: '<img src=x onerror="window.pwned=1">' },
      { kind: 'math', text: '\\frac{a}{b}+x^2' }, { kind: 'link', text: 'safe', url: 'https://example.com' }],
      { size: 16, color: '#111111', accent: '#336699', code: '#eeeeee', bold: false, display: false }, 1));
    assert.equal(await page.locator('.katex').count(), 1);
    assert.equal(await page.locator('img').count(), 0);
    await page.getByRole('link').click();
    assert.deepEqual(await page.evaluate(() => window.results.filter(x => x[0] === 'link')), [['link', 'https://example.com', 1]]);
    await page.evaluate(async () => {
      window.renderMath([{ kind: 'math', text: '\\int_0^1 x^2\\,dx=\\frac{1}{3}' }],
        { size: 16, color: '#111111', accent: '#336699', code: '#eeeeee', display: true }, 5);
      await document.fonts.ready;
      await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    });
    const displayBounds = await page.evaluate(() => {
      const box = document.querySelector('.katex-display').getBoundingClientRect();
      return { top: box.top, bottom: box.bottom,
        reported: window.results.filter(value => value[0] === 'height' && value[2] === 5).at(-1)[1] };
    });
    assert.ok(displayBounds.top >= 0 && displayBounds.bottom <= displayBounds.reported,
      `The native Web viewport must contain the complete display formula: ${JSON.stringify(displayBounds)}`);
    // Apply exactly the height consumed by MessageRender, then ensure neither limit nor denominator is clipped.
    await page.setViewportSize({ width: 360, height: displayBounds.reported });
    assert.equal(await page.evaluate(() => document.querySelector('.katex-display').getBoundingClientRect().bottom <= innerHeight), true);
    await page.setViewportSize({ width: 360, height: 640 });
    await page.evaluate(() => window.renderMath([{ kind: 'math', text: '\\includegraphics{https://evil.invalid/image}' }],
      { size: 16, color: '#111111', accent: '#336699', code: '#eeeeee', display: true }, 2));
    assert.equal(await page.locator('img').count(), 0);
    await page.goto(base + '/mermaid.html');
    await page.evaluate(() => window.renderDiagram('graph TD\n A[Start] --> B[Done]', false, '#ffffff', '#111111', 3));
    await page.waitForFunction(() => window.results.some(x => x[0] === 'status' && x[1] === 'ready' && x[2] === 3));
    assert.equal(await page.locator('#chart svg').count(), 1);
    assert.match(await page.locator('#chart').textContent(), /Start/);
    await page.evaluate(() => window.renderDiagram('bad\nsyntax', true, '#111111', '#ffffff', 4));
    await page.waitForFunction(() => window.results.some(x => x[0] === 'status' && x[1] === 'syntax' && x[2] === 4));
    assert.equal(await page.locator('#chart svg').count(), 0);
    assert.deepEqual(external, []);
    assert.deepEqual(errors, []);
  } finally { await browser?.close(); await new Promise(done => server.close(done)); }
});
