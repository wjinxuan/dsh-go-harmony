import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import test from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const host = readFileSync(new URL('../entry/src/main/ets/ui/PhoneTaskHost.ets', import.meta.url), 'utf8');
const pet = readFileSync(new URL('../entry/src/main/ets/pets/PetPerch.ets', import.meta.url), 'utf8');
const start = source.indexOf("if (this.page === 'chat' && !this.drawer && !this.quickOpen) PetPerch(");
const overlay = source.slice(start, source.indexOf("if (this.page === 'attachmentPreview')", start));

// Phone evidence 333: the empty foreground Stack covered the PasteButton even
// with HitTestMode.Transparent. Touch pass-through is not security-component
// authorization. Keep floating geometry bounded by its rendered content.
test('foreground content has no full-window transparent cover and the phone subscriber stays mounted', () => {
  assert.ok(start > 0);
  assert.doesNotMatch(overlay, /\.height\('100%'\)/);
  assert.doesNotMatch(overlay, /Stack\(/);
  assert.equal((overlay.match(/PhoneTaskHost\(/g) || []).length, 1);
  assert.match(overlay, /\}\)\s*\.position\(\{ x: 0, y: '100%' \}\)\.markAnchor\(\{ x: 0, y: '100%' \}\)\.hitTestBehavior\(HitTestMode\.Transparent\)\s*PhoneTaskHost\(/);
  assert.match(pet, /\.height\(this\.pack\?this\.pack\.height\*petArtScale\([^\n]+\+35:0\)/);
  assert.match(pet, /\.hitTestBehavior\(HitTestMode\.Transparent\)/);
});

test('phone confirmation and notification retain bottom/top placement using their own bounds', () => {
  assert.match(host, /if \(string\(this\.pending\['id'\]\)\)/);
  assert.match(host, /\.width\('92%'\)[^\n]+\.position\(\{ x: '4%', y: '100%' \}\)\.markAnchor\(\{ x: 0, y: '100%' \}\)/);
  assert.match(overlay, /\.width\('95%'\)\.position\(\{ x: '2\.5%', y: 8 \}\)/);
  assert.doesNotMatch(overlay, /\.zIndex\(|\.align\(Alignment\.(?:Top|Bottom)\)/);
});

if (process.argv[2]) {
  const indexPath = basename(process.argv[2]) === 'Index.ts' ? process.argv[2] : join(dirname(process.argv[2]), '../pages/Index.ts');
  const generated = readFileSync(indexPath, 'utf8');
  const phone = readFileSync(join(dirname(indexPath), '../ui/PhoneTaskHost.ts'), 'utf8');
  function attributes(text, kind, marker, lowerBound = 0) {
    const child = text.indexOf(marker, lowerBound); assert.ok(child >= 0, marker);
    const create = text.lastIndexOf(kind + '.create(', child);
    assert.ok(create >= lowerBound, kind + ' observer must belong to this floating content');
    const begin = text.lastIndexOf('=> {', create) + 4;
    const end = text.indexOf('}, ' + kind + ');', create);
    assert.ok(end > begin && end < child, 'complete geometry observer');
    const values = {};
    const component = new Proxy({}, { get: (_target, key) => (...args) => { values[key] = args[0]; } });
    Function(kind, 'HitTestMode', text.slice(begin, end)).call({ colors: { surface: '#fff', border: '#aaa' } }, component, { Transparent: 'transparent' });
    return values;
  }
  const resolve = (value, total) => typeof value === 'string' && value.endsWith('%') ? parseFloat(value) * total / 100 : value || 0;
  function bounds(shape, width, height, parentWidth = 360, parentHeight = 760) {
    return { x: resolve(shape.position?.x, parentWidth) - resolve(shape.markAnchor?.x, width),
      y: resolve(shape.position?.y, parentHeight) - resolve(shape.markAnchor?.y, height), width, height };
  }
  test('actual compiled pet and phone observers anchor content-sized bounds at the bottom', () => {
    const petBranch = generated.indexOf("if (this.page === 'chat' && !this.drawer && !this.quickOpen)");
    const perch = attributes(generated, '__Common__', 'new PetPerch(', petBranch);
    const confirmation = attributes(phone, 'Column', "Text.create(this.t('模型请求操作手机'))");
    assert.equal(perch.hitTestBehavior, 'transparent', 'the positioning wrapper must preserve empty pet-strip touch pass-through');
    assert.equal(perch.height, undefined); assert.equal(confirmation.height, undefined);
    assert.deepEqual(bounds(perch, 360, 100), { x: 0, y: 660, width: 360, height: 100 });
    assert.deepEqual(bounds(confirmation, 331.2, 180), { x: 14.4, y: 580, width: 331.2, height: 180 });
    assert.equal(confirmation.width, '92%');
  });
  test('actual compiled notification observer is bounded and retains its 8 vp top inset', () => {
    const notice = attributes(generated, 'Row', 'Text.create(this.t(this.notificationBanner.text))');
    assert.equal(notice.width, '95%'); assert.equal(notice.height, undefined);
    assert.deepEqual(bounds(notice, 342, 60), { x: 9, y: 8, width: 342, height: 60 });
  });
}
