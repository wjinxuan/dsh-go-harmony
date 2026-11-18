import './require-runtime-node.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as io from 'node:fs/promises';
import { createHash, randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createRecallMarkers } from '../runtime/vendor/dsh-go-bridge/lib/companion/recall-markers.js';

const unavailable = { code: 'companion/recall-tag-unavailable' };
const denied = (code = 'EACCES', syscall = 'link') => Object.assign(new Error('synthetic link denial'), { code, syscall });
const deniedIo = (error = denied()) => ({ ...io, link: async () => { throw error; } });
const markerPath = (directory, session) => join(directory, createHash('sha256').update(session).digest('hex') + '.json');

// This exercises the actual marker module with real private files. Only the
// Harmony link denial and native entry point are substituted; the C++ path/FD
// boundary has its own native harness. Host link+unlink models no-replace move.
async function fixture(run) {
  const directory = await io.mkdtemp(join(tmpdir(), 'dsh-recall-markers-'));
  const old = globalThis.dshHarmonyPublishRecallMarker;
  const calls = [];
  const publish = (source, target) => {
    calls.push({ source, target });
    fs.linkSync(source, target);
    fs.unlinkSync(source);
  };
  try { await run({ directory, calls, publish }); }
  finally {
    if (old === undefined) delete globalThis.dshHarmonyPublishRecallMarker;
    else globalThis.dshHarmonyPublishRecallMarker = old;
    await io.rm(directory, { recursive: true, force: true });
  }
}

for (const code of ['EACCES', 'EPERM']) {
  test(`${code} link denial uses the native publisher for both capability probe and durable marker`, async () => fixture(async ({ directory, calls, publish }) => {
    globalThis.dshHarmonyPublishRecallMarker = publish;
    const markers = createRecallMarkers({ directory, io: deniedIo(denied(code)) });
    assert.equal(await markers.available(), true);
    assert.equal(calls.length, 1);
    assert.match(calls[0].source, /\.recall-[0-9a-f-]{36}\.tmp$/);
    assert.match(calls[0].target, /\.probe-[0-9a-f-]{36}\.tmp$/);
    assert.deepEqual(await io.readdir(directory), []);
    const session = 'DSH-DEVICE-RECALL-' + randomUUID(), store = randomUUID();
    await markers.write(session, store);
    assert.equal(calls.length, 2);
    assert.equal(calls[1].target, markerPath(directory, session));
    assert.deepEqual(markers.readSync(session), {
      schema: 'dsh-go/companion-recall-session', v: 1, sessionId: session,
      storeId: store, protocol: 'confirmed-recency-v1'
    });
    assert.deepEqual(await io.readdir(directory), [createHash('sha256').update(session).digest('hex') + '.json']);
    await assert.rejects(markers.write(session, randomUUID()), { code: 'companion/recall-session-not-clean' });
    assert.equal(calls.length, 2);
  }));
}

test('a marker appearing at publication cannot be overwritten or reported successful', async () => fixture(async ({ directory, calls, publish }) => {
  const existing = 'concurrent marker must be preserved';
  globalThis.dshHarmonyPublishRecallMarker = (source, target) => {
    fs.writeFileSync(target, existing, { flag: 'wx', mode: 0o600 });
    publish(source, target);
  };
  const session = 'DSH-DEVICE-RECALL-' + randomUUID();
  const markers = createRecallMarkers({ directory, io: deniedIo() });
  await assert.rejects(markers.write(session, randomUUID()), unavailable);
  assert.equal(calls.length, 1);
  assert.equal(await io.readFile(markerPath(directory, session), 'utf8'), existing);
  assert.equal((await io.readdir(directory)).length, 1, 'failed stage is removed');
  assert.throws(() => markers.readSync(session), unavailable, 'malformed existing marker is not absence');
}));

test('unrelated permission and non-permission failures never call the native fallback', async () => fixture(async ({ directory, calls, publish }) => {
  globalThis.dshHarmonyPublishRecallMarker = publish;
  for (const error of [denied('EIO'), denied('ENOSPC'), denied('EEXIST'), denied('EACCES', 'open'), { code: 'EPERM' }]) {
    const markers = createRecallMarkers({ directory, io: deniedIo(error) });
    assert.equal(await markers.available(), false);
    await assert.rejects(markers.write('DSH-DEVICE-RECALL-' + randomUUID(), randomUUID()), unavailable);
    assert.equal(calls.length, 0);
    assert.deepEqual(await io.readdir(directory), []);
  }
}));

test('missing or rejecting native publisher stays unavailable and leaves no marker', async () => fixture(async ({ directory }) => {
  delete globalThis.dshHarmonyPublishRecallMarker;
  let markers = createRecallMarkers({ directory, io: deniedIo() });
  assert.equal(await markers.available(), false);
  globalThis.dshHarmonyPublishRecallMarker = () => { throw denied('EACCES', 'renameat2'); };
  markers = createRecallMarkers({ directory, io: deniedIo() });
  await assert.rejects(markers.write('DSH-DEVICE-RECALL-' + randomUUID(), randomUUID()), unavailable);
  assert.deepEqual(await io.readdir(directory), []);
}));

test('a failed capability probe can recover without caching false or bypassing publication', async () => fixture(async ({ directory, calls, publish }) => {
  globalThis.dshHarmonyPublishRecallMarker = () => { throw denied('ENOSPC', 'renameat2'); };
  const markers = createRecallMarkers({ directory, io: deniedIo() });
  assert.equal(await markers.available(), false);
  globalThis.dshHarmonyPublishRecallMarker = publish;
  assert.equal(await markers.available(), true);
  assert.equal(await markers.available(), true);
  assert.equal(calls.length, 1, 'only a successful probe is cached');
  assert.deepEqual(await io.readdir(directory), []);
}));

test('directory fsync failure after native publication remains fail-closed', async () => fixture(async ({ directory, publish }) => {
  globalThis.dshHarmonyPublishRecallMarker = publish;
  const brokenSync = { ...deniedIo(), open: async (path, ...args) => {
    const handle = await io.open(path, ...args);
    return path === directory ? { sync: async () => { throw denied('EIO', 'fsync'); }, close: () => handle.close() } : handle;
  } };
  const markers = createRecallMarkers({ directory, io: brokenSync });
  assert.equal(await markers.available(), false);
  const session = 'DSH-DEVICE-RECALL-' + randomUUID(), store = randomUUID();
  await assert.rejects(markers.write(session, store), unavailable);
  assert.equal(markers.readSync(session).storeId, store, 'published marker still fences the session');
  await assert.rejects(markers.write(session, randomUUID()), { code: 'companion/recall-session-not-clean' });
}));

test('hosts supporting hard links keep the original publication path', async () => fixture(async ({ directory, calls, publish }) => {
  globalThis.dshHarmonyPublishRecallMarker = publish;
  const markers = createRecallMarkers({ directory });
  assert.equal(await markers.available(), true);
  const session = 'DSH-DEVICE-RECALL-' + randomUUID(), store = randomUUID();
  await markers.write(session, store);
  assert.equal(markers.readSync(session).storeId, store);
  assert.equal(calls.length, 0);
}));
