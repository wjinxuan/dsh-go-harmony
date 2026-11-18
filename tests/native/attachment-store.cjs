'use strict';

// Execute the actual packaged storage implementation with the embedded C++ hook.
// Only OS ancestor-open and hardlink denials are injected; publication is native.
const assert = require('node:assert/strict');
const io = require('node:fs/promises');
const { createHash } = require('node:crypto');
const { syncBuiltinESMExports } = require('node:module');
const { dirname, isAbsolute, join, resolve } = require('node:path');
const { pathToFileURL } = require('node:url');

(async () => {
  const home = process.argv[2];
  const runtime = process.env.DSH_NATIVE_TEST_RUNTIME;
  assert.ok(home && isAbsolute(home), 'runner must supply its private data directory');
  assert.ok(runtime && isAbsolute(runtime), 'DSH_NATIVE_TEST_RUNTIME must identify the actual unpacked runtime');
  const publish = globalThis.dshHarmonyPublishAttachmentFile;
  assert.equal(typeof publish, 'function', 'the actual embedded C++ attachment hook is required');
  const boundary = dirname(home), root = join(home, 'attachments', 'v1');
  const forbiddenAncestors = new Set();
  for (let path = dirname(boundary); ; path = dirname(path)) {
    forbiddenAncestors.add(path);
    if (dirname(path) === path) break;
  }
  const bytes = Buffer.from('<!doctype html><html><head><meta charset="utf-8"><title>Device artifact fixture</title></head><body><h1>DSH device artifact</h1><p>Isolated synthetic HTML generated through the real write tool.</p></body></html>');
  assert.equal(bytes.length, 211);
  const digest = createHash('sha256').update(bytes).digest('hex');
  assert.equal(digest, '8ec6ff8098887bdf5a4b70ad77c97dd9e84073e328ae5d32da26aa3e7d7334b9');
  await io.mkdir(home, { recursive: true });
  const staging = join(root, 'tmp');
  const beforeTemporary = await io.readdir(staging).catch(error => {
    if (error.code !== 'ENOENT') throw error;
    return [];
  });
  const originalOpen = io.open, originalLink = io.link, oldHome = process.env.DSH_HOME;
  const denied = [], synced = [], links = [];
  io.open = async (path, ...args) => {
    const absolute = resolve(String(path));
    if (forbiddenAncestors.has(absolute)) {
      denied.push(absolute);
      throw Object.assign(new Error('Fixture sandbox denied ancestor directory open'), {
        code: 'EACCES', syscall: 'open', path: absolute
      });
    }
    const handle = await originalOpen(path, ...args), sync = handle.sync.bind(handle);
    handle.sync = async () => { synced.push(absolute); return sync(); };
    return handle;
  };
  io.link = async (source, target) => {
    assert.ok(String(target).startsWith(root + '/'));
    links.push({ source, target });
    throw Object.assign(new Error('Fixture platform denied hardlink'), { code: 'EACCES', syscall: 'link' });
  };
  process.env.DSH_HOME = home;
  syncBuiltinESMExports();
  try {
    const { LocalAttachmentStore } = await import(pathToFileURL(join(runtime,
      'node_modules/@deepseek-ai/dsh-attachment-local/lib/index.js')).href);
    const store = { root };
    const save = () => LocalAttachmentStore.prototype.saveFileStream.call(store, {
      name: 'native-owned-211.html',
      data: (async function* () { yield bytes.subarray(0, 71); yield bytes.subarray(71); })()
    });
    const ref = await save();
    assert.deepEqual(ref, { attachmentId: 'sha256:' + digest, name: 'native-owned-211.html', bytes: 211 });
    const object = join(root, 'file-objects', digest.slice(0, 2), digest);
    const alias = join(root, 'files', digest.slice(0, 2), digest, ref.name);
    assert.deepEqual(await io.readFile(object), bytes);
    assert.deepEqual(await io.readFile(alias), bytes);
    const originalObject = await io.stat(object), originalAlias = await io.stat(alias);
    assert.equal(originalObject.mode & 0o777, 0o400);
    assert.equal(originalAlias.mode & 0o777, 0o400);
    const chunks = [];
    for await (const chunk of LocalAttachmentStore.prototype.readFileStream.call(store, ref)) chunks.push(chunk);
    assert.deepEqual(Buffer.concat(chunks), bytes);
    assert.deepEqual(await save(), ref, 'repeat upload must deduplicate through native EEXIST handling');
    assert.equal((await io.stat(object)).ino, originalObject.ino, 'canonical object must not be replaced');
    assert.equal((await io.stat(alias)).ino, originalAlias.ino, 'alias must not be replaced');
    assert.deepEqual(await io.readFile(object), bytes);
    assert.deepEqual(await io.readFile(alias), bytes);
    assert.ok(links.length >= 6, 'initial and repeated object/alias hardlink attempts must use native fallback');
    assert.equal(globalThis.dshHarmonyPublishAttachmentFile, publish, 'the production native hook was never replaced');
    assert.deepEqual(denied, [], 'the patched store must never open above the trusted private parent');
    for (const path of [boundary, home, join(home, 'attachments'), root,
      join(root, 'file-objects'), dirname(alias)]) {
      assert.ok(synced.includes(path), 'required directory fsync missing: ' + path);
    }
    assert.deepEqual((await io.readdir(staging)).sort(), beforeTemporary.sort(), 'this upload leaves no new staging file');
    console.log('Actual packaged attachment store + native C++ publication passed: 211-byte object/alias, exact readback, no-replace deduplication, trusted-parent fsync, and temporary cleanup.');
  } finally {
    io.open = originalOpen; io.link = originalLink;
    if (oldHome === undefined) delete process.env.DSH_HOME;
    else process.env.DSH_HOME = oldHome;
    syncBuiltinESMExports();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
