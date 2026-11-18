import assert from 'node:assert/strict';
import { createReadStream } from 'node:fs';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

test('bundled xterm displays ANSI cursor edits and forwards accessible keyboard input', {
  skip: !process.env.DSH_TERMINAL_PLAYWRIGHT
}, async () => {
  const { chromium } = createRequire(import.meta.url)(process.env.DSH_TERMINAL_PLAYWRIGHT);
  const assets = new URL('../entry/src/main/resources/rawfile/terminal/', import.meta.url);
  const mime = new Map([['index.html', 'text/html'], ['terminal.css', 'text/css'], ['xterm.css', 'text/css'],
    ['terminal.js', 'text/javascript'], ['xterm.js', 'text/javascript'], ['xterm-addon-fit.js', 'text/javascript']]);
  const server = createServer((request, response) => {
    const file = request.url.slice(1);
    if (!mime.has(file)) { response.writeHead(404).end(); return; }
    response.writeHead(200, { 'content-type': mime.get(file) });
    createReadStream(fileURLToPath(new URL(file, assets))).pipe(response);
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  let browser;
  try {
    browser = await chromium.launch({ executablePath: process.env.DSH_TERMINAL_BROWSER || undefined });
    const page = await browser.newPage({ viewport: { width: 360, height: 640 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(() => {
      window.events = [];
      window.terminalBridge = {
        input: (value, revision) => window.events.push(['input', value, revision]), size: (...size) => window.events.push(['size', ...size]),
        modifierUsed: () => window.events.push(['modifierUsed']), displayOverflow: () => window.events.push(['overflow'])
      };
    });
    await page.goto(`http://127.0.0.1:${server.address().port}/index.html`);
    await page.waitForFunction(() => window.events.some(([type]) => type === 'size'));
    await page.evaluate(() => {
      window.terminalDisplay.snapshot(42, 20, '\x1b[31mABCDE\x1b[0m\r\n', true, 7);
      window.terminalDisplay.output('\x1b[1A\rXY\x1b[?1h');
    });
    await page.waitForFunction(() => document.querySelector('.xterm-rows').textContent.includes('XYCDE'));
    assert.equal((await page.locator('.xterm-fg-1').allTextContents()).join(''), 'CDE');
    const input = page.getByRole('textbox', { name: '终端输入' });
    await input.focus();
    await page.keyboard.type('z');
    await page.evaluate(() => {
      window.terminalDisplay.key('up');
      window.terminalDisplay.modifier('ctrl');
    });
    await page.keyboard.type('c');
    assert.deepEqual(await page.evaluate(() => window.events.filter(([type]) => type !== 'size')),
      [['input', 'z', 7], ['input', '\x1bOA', 7], ['modifierUsed'], ['input', '\x03', 7]]);
    await page.evaluate(() => window.terminalDisplay.state(42, 20, false));
    await page.keyboard.type('a');
    assert.equal(await page.evaluate(() => window.events.some(([type, data]) => type === 'input' && data === 'a')), false);
    assert.deepEqual(errors, []);
  } finally {
    await browser?.close();
    server.close();
  }
});
