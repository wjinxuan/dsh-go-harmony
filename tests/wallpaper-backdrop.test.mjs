import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/ui/WallpaperBackdrop.ets', import.meta.url), 'utf8');
const data = readFileSync(new URL('../entry/src/main/ets/ui/AdvancedPreferencesData.ets', import.meta.url), 'utf8');
const wallpaperFrame = Function(stripTypeScriptTypes(data.slice(data.indexOf('function clamp')).replace(/^export /gm, '')) + '\nreturn wallpaperFrame;')();

function method(text, name) {
  const start = text.indexOf(name + '(');
  assert.ok(start >= 0, name);
  const begin = text.indexOf('{', start);
  let depth = 1, end = begin + 1;
  for (; depth && end < text.length; end++) { if (text[end] === '{') depth++; if (text[end] === '}') depth--; }
  assert.equal(depth, 0, name + ' closing brace');
  return text.slice(begin + 1, end - 1);
}

function fixture(text, compiled) {
  const calls = [], frames = [];
  let current, areaChange;
  const fileUri = { getUriFromPath(path) {
    calls.push(path);
    return 'file://test.bundle' + path.split('/').map(encodeURIComponent).join('/');
  } };
  const attributes = new Proxy({}, { get: (_target, name) => value => { current[name] = value; return attributes; } });
  const Image = source => { current = { source }; frames.push(current); return attributes; };
  Object.assign(Image, { create: Image, width: value => attributes.width(value), height: value => attributes.height(value),
    position: value => attributes.position(value), objectFit: value => attributes.objectFit(value),
    blur: value => attributes.blur(value), onError: value => attributes.onError(value) });
  const component = new Proxy({}, { get: (_target, name) => name === 'onAreaChange' ? callback => { areaChange = callback; } : () => {} });
  const args = ['fileUri', 'Image', 'wallpaperFrame', 'ImageFit', 'Stack', 'Column', 'If', 'Alignment', 'HitTestMode'];
  const values = [fileUri, Image, wallpaperFrame, { Fill: 'fill' }, component, component, component, { TopStart: 'top-start' }, { None: 'none' }];
  let render;
  if (compiled) render = Function(...args, stripTypeScriptTypes(method(text, 'initialRender')));
  else {
    const guard = text.match(/if\s*\((this\.paper\.on[^\n]+)\)\s*\{/);
    const chain = text.match(/Image\(this\.paper\.path\)[^]*?\.onError\([^\n]+\)|Image\(fileUri\.getUriFromPath\(this\.paper\.path\)\)[^]*?\.onError\([^\n]+\)/);
    assert.ok(guard && chain, 'production wallpaper Image guard and attribute chain');
    render = Function(...args, `if (${guard[1]}) { ${chain[0]} }`);
  }
  const owner = { paper: { path: '/data/storage/el2/base/haps/entry/files/dsh-wallpaper-own.png', on: true,
    width: 320, height: 180, zoom: 1, alignX: 0, alignY: 0, blur: 0, lighten: .2, dim: .2 },
    colors: {}, dark: false, broken: false, frameWidth: 320, frameHeight: 180,
    observeComponentCreation2(callback) { callback(1, true); }, ifElseBranchUpdateFunction(_index, callback) { callback(); } };
  return { owner, calls, frames, render() { render.call(owner, ...values); },
    changed() { Function(stripTypeScriptTypes(method(text, 'paperChanged'))).call(owner); },
    resize(width, height) { if (compiled) { areaChange({}, { width, height }); } else { owner.frameWidth = width; owner.frameHeight = height; } } };
}

function cases(label, text, compiled) {
  test(label + ': sandbox path reaches Image only through platform file URI conversion', () => {
    const f = fixture(text, compiled), raw = f.owner.paper.path;
    f.render();
    assert.deepEqual(f.calls, [raw], 'raw filesystem path must be converted before Image loading');
    assert.equal(f.frames[0].source, 'file://test.bundle' + raw);
    assert.equal(f.owner.paper.path, raw, 'preference must retain the raw filesystem path');
    f.owner.paper.path = '/data/storage/el2/base/haps/entry/files/壁纸 #1.png'; f.render();
    assert.equal(f.frames.at(-1).source, 'file://test.bundle/data/storage/el2/base/haps/entry/files/%E5%A3%81%E7%BA%B8%20%231.png');
  });
  test(label + ': disabled, absent and failed wallpapers retain fallback; changing paper recovers', () => {
    const f = fixture(text, compiled), raw = f.owner.paper.path;
    f.owner.paper.on = false; f.render();
    f.owner.paper.on = true; f.owner.paper.path = ''; f.render();
    assert.equal(f.frames.length, 0); assert.equal(f.calls.length, 0);
    f.owner.paper.path = raw; f.render(); f.frames.at(-1).onError();
    assert.equal(f.owner.broken, true); f.render(); assert.equal(f.frames.length, 1);
    f.changed(); f.render(); assert.equal(f.frames.length, 2); assert.equal(f.owner.broken, false);
  });
  test(label + ': URI adaptation keeps crop, resize, zoom and blur geometry', () => {
    const f = fixture(text, compiled); f.render();
    assert.deepEqual({ width: f.frames[0].width, height: f.frames[0].height, position: f.frames[0].position },
      { width: 320, height: 180, position: { x: 0, y: 0 } });
    f.resize(180, 320); Object.assign(f.owner.paper, { zoom: 2, alignX: 1, alignY: -1, blur: .3 }); f.render();
    const expected = wallpaperFrame(f.owner.paper, 180, 320), result = f.frames.at(-1);
    assert.equal(result.width, expected.width); assert.equal(result.height, expected.height);
    assert.deepEqual(result.position, { x: expected.x, y: expected.y });
    assert.equal(result.objectFit, 'fill'); assert.equal(result.blur, .3 * 36);
  });
}

// Executes production Image expressions / real generated render callbacks with
// platform seams mocked. This does not claim native image decoding or phone paint.
cases('source', source, false);
if (process.argv[2]) cases('actual CompileArkTS output', readFileSync(process.argv[2], 'utf8'), true);
