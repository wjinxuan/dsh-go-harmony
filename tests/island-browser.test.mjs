import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
test('original island runtime probes occupancy and isolates the intended live plugin slot', { skip: !process.env.DSH_RENDER_PLAYWRIGHT }, async () => {
  const { chromium } = createRequire(import.meta.url)(process.env.DSH_RENDER_PLAYWRIGHT);
  const root = new URL('../entry/src/main/resources/rawfile/islands/', import.meta.url);
  const [script, css] = await Promise.all(['island.js', 'island.css'].map(name => readFile(new URL(name, root), 'utf8')));
  const browser = await chromium.launch({ executablePath: process.env.DSH_RENDER_BROWSER || undefined, headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 360, height: 720 } });
    await page.setContent('<main><nav data-slot="sidebar">Host sidebar</nav><section data-slot="conversation.input.dock"><button id="plugin">Plugin action</button></section><aside>Outside slot</aside></main>');
    await page.evaluate(() => { window.messages = []; window.DshGoIsland = { postMessage: value => window.messages.push(JSON.parse(value)) }; window.__dshGoBridge = { mask: slots => { window.masked = slots; }, count: () => 1 }; });
    await page.addScriptTag({ content: script });
    await page.evaluate(css => window.__dshGoIsland.init({ mode: 'panel', slot: 'conversation.input.dock', mask: true, stretch: 'parent', pad: [12, 8], load: 7, css, target: {}, labels: {}, bootMs: 100, slotMs: 100 }), css);
    await page.waitForFunction(() => window.messages.some(m => m.t === 'ready'));
    assert.deepEqual(await page.evaluate(() => window.masked), ['conversation.input.dock']);
    assert.equal(await page.locator('#plugin').isVisible(), true);
    assert.equal(await page.locator('aside').isVisible(), false);
    assert.ok((await page.evaluate(() => window.messages)).some(m => m.t === 'ready' && m.load === 7 && m.found === 1));
    await page.evaluate(() => window.__dshGoIsland.init({ slot: 'conversation.input.dock', load: 8 }));
    await page.waitForFunction(() => window.messages.some(m => m.t === 'ready' && m.load === 8));
    const probe = await browser.newPage(); await probe.setContent('<body>Probe</body>');
    await probe.evaluate(() => { window.messages = []; window.DshGoIsland = { postMessage: value => window.messages.push(JSON.parse(value)) }; window.__dshGoBridge = { report: async () => { window.reported = true; } }; });
    await probe.addScriptTag({ content: script }); await probe.evaluate(() => window.__dshGoIsland.init({ mode: 'probe', slot: '', load: 1 }));
    await probe.waitForFunction(() => window.messages.some(m => m.t === 'ready' && m.probe));
    assert.equal(await probe.evaluate(() => window.reported), true);
  } finally { await browser.close(); }
});
