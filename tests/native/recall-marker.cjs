'use strict';
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { mkdirSync, readFileSync, writeFileSync, existsSync, symlinkSync, unlinkSync } = require('node:fs');
const { join } = require('node:path');
const publish = globalThis.dshHarmonyPublishRecallMarker;
assert.equal(typeof publish, 'function', 'real embedded Node must expose the bounded Recall publisher');
const root = join(process.argv[2], 'companion', 'recall-sessions');
mkdirSync(root, { recursive: true });
const stage = join(root, `.recall-${randomUUID()}.tmp`);
const target = join(root, 'a'.repeat(64) + '.json');
writeFileSync(stage, 'marker');
assert.equal(publish(stage, target), undefined);
assert.equal(readFileSync(target, 'utf8'), 'marker');
assert.equal(existsSync(stage), false);
writeFileSync(stage, 'replacement');
assert.throws(() => publish(stage, target), { code: 'EEXIST' });
assert.equal(readFileSync(target, 'utf8'), 'marker');
assert.equal(readFileSync(stage, 'utf8'), 'replacement');
assert.throws(() => publish(stage), TypeError);
assert.throws(() => publish(1, target), TypeError);
assert.throws(() => publish(stage, join(root, 'other.json')), { code: 'EINVAL' });
assert.throws(() => publish(stage, join(process.argv[2], 'a'.repeat(64) + '.json')), { code: 'EINVAL' });
const probe = join(root, `.probe-${randomUUID()}.tmp`);
assert.equal(publish(stage, probe), undefined);
assert.throws(() => publish(stage, probe), { code: 'ENOENT' });
symlinkSync(target, stage);
assert.throws(() => publish(stage, probe), { code: 'EINVAL' });
unlinkSync(stage);
unlinkSync(probe);
console.log('Native Recall V8 publication and errno contract passed.');

if (process.env.DSH_NATIVE_RECALL_MARKERS) {
  (async () => {
    const io = await import('node:fs/promises');
    const { pathToFileURL } = require('node:url');
    const { createRecallMarkers } = await import(pathToFileURL(process.env.DSH_NATIVE_RECALL_MARKERS).href);
    const markers = createRecallMarkers({ directory: root, io: { ...io, async link() {
      throw Object.assign(new Error('Fixture hardlink denial'), { code: 'EPERM', syscall: 'link' });
    } } });
    assert.equal(await markers.available(), true);
    const session = 'DSH-NATIVE-RECALL-' + randomUUID(), store = randomUUID();
    await markers.write(session, store);
    assert.equal(markers.readSync(session).storeId, store);
    await assert.rejects(markers.write(session, randomUUID()), { code: 'companion/recall-session-not-clean' });
    assert.equal(markers.readSync(session).storeId, store);
    assert.equal((await io.readdir(root)).some(name => name.startsWith('.recall-') || name.startsWith('.probe-')), false,
      'capability probe and marker publication clean up temporary files');
    console.log('Packaged Recall capability probe and immutable marker passed with real native fallback and synthetic EPERM link denial.');
  })().catch(error => { console.error(error); process.exitCode = 1; });
}
