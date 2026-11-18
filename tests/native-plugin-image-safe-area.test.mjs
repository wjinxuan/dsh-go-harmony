import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

const source = await readFile(new URL('../entry/src/main/ets/ui/NativePluginImage.ets', import.meta.url), 'utf8');
const component = source.slice(source.indexOf('export struct NativePluginImage'), source.indexOf('  @Builder private viewer()')) + '\n}';
const executable = stripTypeScriptTypes(component.replace('export struct', 'class')
  .replace(/@(?:Prop|State)\s*/g, '').replace(/@(?:StorageProp|Watch)\('[^']*'\)\s*/g, '') + '\nNativePluginImage');
const rect = (width = 0, height = 0) => ({ left: 0, top: 0, width, height });
const area = (top = 0, bottom = 0, left = 0, right = 0) => ({
  topRect: rect(1200, top), bottomRect: rect(1200, bottom), leftRect: rect(left, 2400), rightRect: rect(right, 2400)
});
// Drain both the Node and VM Promise queues; platform work in this fixture has no I/O.
const settle = () => new Promise(resolve => setImmediate(resolve));
function fixture({ findFailure = false, failedType = -1, sources = [] } = {}) {
  const areas = [area(127), area(111), area(0, 60)];
  const listeners = [], removed = [];
  const target = {
    getWindowAvoidArea(type) { if (type === failedType) throw Error('unsupported avoid category'); return areas[type]; },
    on(event, callback) { assert.equal(event, 'avoidAreaChange'); listeners.push(callback); },
    off(event, callback) { assert.equal(event, 'avoidAreaChange'); removed.push(callback); }
  };
  const pixels = { releases: 0, release() { this.releases++; } };
  const defaultSource = { releases: 0, async getImageInfo() { return { size: { width: 64, height: 48 } }; },
    async createPixelMap() { return pixels; }, release() { this.releases++; } };
  const Image = vm.runInNewContext(executable, {
    localizedSettingsText: value => value, themeColors: () => ({}),
    util: { Base64Helper: class { decodeSync() { return Uint8Array.of(1, 2, 3); } } },
    image: { createImageSource() { return sources.shift() ?? defaultSource; } },
    window: { AvoidAreaType: { TYPE_SYSTEM: 0, TYPE_CUTOUT: 1, TYPE_NAVIGATION_INDICATOR: 2 },
      findWindow(name) { assert.equal(name, 'plugin-image-window'); if (findFailure) throw Error('closing window'); return target; } }
  });
  const view = new Image();
  view.source = 'data:image/png;base64,AQID';
  view.getUIContext = () => ({ getWindowName: () => 'plugin-image-window', px2vp: value => value / 3 });
  return { view, areas, listeners, removed, pixels, defaultSource };
}

test('production fullscreen image insets avoid the observed 127px top, rotation cutout and navigation; dispose removes the same listener', async () => {
  const f = fixture(); f.view.aboutToAppear(); await settle();
  assert.equal(f.view.safeInsets?.top ?? 0, 127 / 3, 'fullscreen header must start below the actual status area, not under the capsule');
  assert.equal(f.view.safeInsets.bottom, 20);
  assert.equal(f.listeners.length, 1);
  f.areas[0] = area(); f.areas[1] = area(0, 0, 96, 30); f.areas[2] = area(0, 36);
  f.listeners[0]({ type: 1, area: f.areas[1] });
  assert.deepEqual(JSON.parse(JSON.stringify(f.view.safeInsets)), { top: 0, right: 10, bottom: 12, left: 32 });
  const lastInsets = f.view.safeInsets;
  f.view.fullscreen = true; f.view.aboutToDisappear();
  assert.equal(f.removed.length, 1); assert.equal(f.removed[0], f.listeners[0]);
  assert.equal(f.view.fullscreen, false); assert.equal(f.pixels.releases, 1); assert.equal(f.view.pixels, undefined);
  f.areas[0] = area(300); f.listeners[0]({ type: 0, area: f.areas[0] });
  assert.equal(f.view.safeInsets, lastInsets, 'late events cannot mutate the disposed modal');
});

test('production image still loads when a window/category is unavailable; supported insets remain in effect', async () => {
  const f = fixture({ failedType: 0 }); f.view.aboutToAppear(); await settle();
  assert.equal(f.view.safeInsets?.top ?? 0, 37, 'cutout remains available when system category is unsupported');
  assert.equal(f.view.safeInsets.bottom, 20); assert.equal(f.view.pixels, f.pixels); f.view.aboutToDisappear();
  const closing = fixture({ findFailure: true }); closing.view.aboutToAppear(); await settle();
  assert.equal(closing.view.pixels, closing.pixels); assert.equal(closing.view.failed, false);
  closing.view.aboutToDisappear(); assert.equal(closing.pixels.releases, 1);
});

test('production full-cover builder applies measured root insets and reserves the header before the weighted image viewport', () => {
  const viewer = source.slice(source.indexOf('  @Builder private viewer()'), source.indexOf('\n  build()'));
  assert.match(viewer, /\.safeAreaPadding\(this\.safeInsets\)/, 'full-window content cover must apply measured insets');
  const header = viewer.slice(viewer.indexOf('Row()'), viewer.indexOf('\n      Stack()'));
  assert.match(header, /\.height\(56\)/, 'buttons/title must retain a full header row above the image');
  assert.match(viewer, /\.layoutWeight\(1\)\.width\('100%'\)\.clip\(true\)/);
  assert.match(source, /\.bindContentCover\(\$\$this\.fullscreen, this\.viewer\(\)/);
});

test('unchanged production loader releases late pixels, resets view and preserves invalid-source errors', async () => {
  let resolvePixels;
  const late = { releases: 0, release() { this.releases++; } };
  const pending = { releases: 0, async getImageInfo() { return { size: { width: 64, height: 48 } }; },
    createPixelMap() { return new Promise(resolve => { resolvePixels = resolve; }); }, release() { this.releases++; } };
  const f = fixture({ sources: [pending] }); f.view.zoom = 4; f.view.offsetX = 18; f.view.offsetY = 20;
  const first = f.view.load(); await settle(); assert.equal(f.view.zoom, 1); assert.equal(f.view.offsetX, 0); assert.equal(f.view.offsetY, 0);
  f.view.source = 'file:///private/forbidden.png'; await f.view.load(); assert.equal(f.view.failed, true);
  resolvePixels(late); await first; assert.equal(late.releases, 1); assert.equal(f.view.pixels, undefined); assert.equal(pending.releases, 1);
});
