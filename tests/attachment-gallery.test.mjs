import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/ui/AttachmentGalleryData.ets', import.meta.url), 'utf8');
const { boundedPan, fittedSize, GalleryLoadQueue } = await import(
  'data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(source.replace(/^import type .*\n/m, ''))));

test('gallery preserves aspect ratio and rejects oversized source images', () => {
  assert.deepEqual(fittedSize(4000, 2000, 420), [420, 210]);
  assert.deepEqual(fittedSize(800, 1600, 2048), [800, 1600]);
  assert.deepEqual(fittedSize(1, 4000, 420), [1, 420]);
  assert.throws(() => fittedSize(7000, 6000, 420), /像素/);
  assert.throws(() => fittedSize(0, 1, 420), /格式/);
  assert.equal(boundedPan(500, 200, 2), 100);
  assert.equal(boundedPan(-500, 200, 2), -100);
  assert.equal(boundedPan(-500, 200, 1), 0);
});

test('thumbnail queue limits active decodes and skips requests scrolled out of view', async () => {
  const queue = new GalleryLoadQueue();
  const release = Promise.withResolvers();
  const active = [];
  const load = (id, current = () => true) => queue.run(current, async () => {
    active.push(id);
    await release.promise;
    return id;
  });
  let visible = true;
  const first = load(1);
  const second = load(2);
  const stale = assert.rejects(load(3, () => visible), /取消/);
  const next = load(4);
  await Promise.resolve();
  assert.deepEqual(active, [1, 2]);
  visible = false;
  release.resolve();
  assert.deepEqual(await Promise.all([first, second, next]), [1, 2, 4]);
  await stale;
  assert.deepEqual(active, [1, 2, 4]);
});
