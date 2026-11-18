import assert from 'node:assert/strict';
import test from 'node:test';
import * as fs from 'node:fs';
import fsPromises from 'node:fs/promises';
import { syncBuiltinESMExports } from 'node:module';
import { createHash, randomUUID } from 'node:crypto';
import { join, dirname, resolve, relative, sep } from 'node:path';
import { pathToFileURL } from 'node:url';

const runtime = resolve(process.argv[2] || '');
assert.ok(process.argv[2], 'node tests/attachment-durability.test.mjs <unpacked actual runtime>');
const modulePath = join(runtime, 'node_modules/@deepseek-ai/dsh-attachment-local/lib/index.js');
const originalOpen = fsPromises.open, originalLink = fsPromises.link;
const bytes = Buffer.from('<!doctype html><title>Owned attachment durability fixture</title>'.padEnd(211, ' '));
const digest = createHash('sha256').update(bytes).digest('hex');

async function fixture(options, run) {
  const scratch = await fsPromises.realpath(await fsPromises.mkdtemp('/tmp/dsh-attachment-durability-'));
  const filesDir = join(scratch, 'files'), home = join(filesDir, 'dsh-local-data'), root = join(home, 'attachments/v1');
  await fsPromises.mkdir(home, { recursive: true, mode: 0o700 });
  const opened = [], synced = [], denied = [], published = [];
  const priorHook = globalThis.dshHarmonyPublishAttachmentFile;
  const aboveFilesDir = path => path !== filesDir && !relative(path, filesDir).startsWith('..') && !relative(path, filesDir).startsWith(sep);
  fsPromises.open = async (path, ...args) => {
    const absolute = resolve(String(path)); opened.push(absolute);
    if (options.denyAbove && aboveFilesDir(absolute)) {
      denied.push(absolute);
      throw Object.assign(new Error('Fixture sandbox denied ancestor directory open'), { code: 'EACCES', syscall: 'open', path: absolute });
    }
    const handle = await originalOpen(path, ...args), sync = handle.sync.bind(handle);
    handle.sync = async () => {
      synced.push(absolute);
      if (absolute === (options.failSync === 'boundary' ? filesDir : options.failSync === 'inside' ? join(home, 'attachments') : '')) {
        throw Object.assign(new Error('Fixture directory fsync failed'), { code: 'EIO', syscall: 'fsync', path: absolute });
      }
      return sync();
    };
    return handle;
  };
  fsPromises.link = async (source, target) => {
    assert.ok(target.startsWith(root + sep));
    if (options.native) throw Object.assign(new Error('Fixture platform denied hardlink'), { code: 'EACCES', syscall: 'link' });
    return originalLink(source, target);
  };
  if (options.native) globalThis.dshHarmonyPublishAttachmentFile = (source, target) => {
    assert.ok(source.startsWith(join(root, 'tmp') + sep));
    assert.ok(target.startsWith(root + sep));
    published.push({ source, target });
    // Host-only no-replace seam. The C++ path/renameat2 contract is separately
    // covered by check-native-publish; this test executes real JS storage code.
    fs.linkSync(source, target); fs.unlinkSync(source);
  };
  else delete globalThis.dshHarmonyPublishAttachmentFile;
  syncBuiltinESMExports();
  try {
    const { LocalAttachmentStore } = await import(pathToFileURL(modulePath).href + '?durability=' + randomUUID());
    const store = { root };
    const save = () => LocalAttachmentStore.prototype.saveFileStream.call(store, {
      name: 'owned-211.html', data: (async function* () { yield bytes.subarray(0, 71); yield bytes.subarray(71); })()
    });
    const read = ref => LocalAttachmentStore.prototype.readFileStream.call(store, ref);
    await run({ filesDir, home, root, save, read, opened, synced, denied, published });
  } finally {
    fsPromises.open = originalOpen; fsPromises.link = originalLink;
    if (priorHook === undefined) delete globalThis.dshHarmonyPublishAttachmentFile;
    else globalThis.dshHarmonyPublishAttachmentFile = priorHook;
    syncBuiltinESMExports();
    await fsPromises.rm(scratch, { recursive: true, force: true });
  }
}

test('real store publishes file object and alias despite denied sandbox ancestors and hardlinks, then deduplicates', async () => {
  await fixture({ native: true, denyAbove: true }, async f => {
    const ref = await f.save();
    assert.equal(ref.attachmentId, 'sha256:' + digest); assert.equal(ref.bytes, 211); assert.equal(ref.name, 'owned-211.html');
    const objectPath = join(f.root, 'file-objects', digest.slice(0, 2), digest);
    const aliasPath = join(f.root, 'files', digest.slice(0, 2), digest, ref.name);
    assert.deepEqual(await fsPromises.readFile(objectPath), bytes); assert.deepEqual(await fsPromises.readFile(aliasPath), bytes);
    assert.equal((await fsPromises.stat(objectPath)).mode & 0o777, 0o400);
    assert.equal((await fsPromises.stat(aliasPath)).mode & 0o777, 0o400);
    const chunks = []; for await (const chunk of f.read(ref)) chunks.push(chunk); assert.deepEqual(Buffer.concat(chunks), bytes);
    assert.deepEqual(await f.save(), ref, 'existing objects are digest-verified, not overwritten');
    assert.ok(f.published.length >= 4, 'both canonical and alias paths use the no-replace fallback, including EEXIST');
    assert.deepEqual(f.denied, [], 'the app must not attempt to sync above its trusted files directory');
    for (const path of [f.filesDir, f.home, join(f.root, 'file-objects'), dirname(aliasPath)]) assert.ok(f.synced.includes(path), 'required directory fsync missing: ' + path);
    assert.deepEqual(await fsPromises.readdir(join(f.root, 'tmp')), []);
  });
});

for (const failSync of ['boundary', 'inside']) test('real store rejects ' + failSync + ' directory fsync failure without acknowledging an attachment', async () => {
  await fixture({ native: true, denyAbove: true, failSync }, async f => {
    await assert.rejects(f.save(), error => error.code === 'EIO' && error.syscall === 'fsync');
    assert.equal(f.published.length, 0); assert.deepEqual(f.denied, []);
  });
});

test('non-native hosts retain upstream durability walk to the filesystem root', async () => {
  await fixture({ native: false, denyAbove: false }, async f => {
    const ref = await f.save(); assert.equal(ref.bytes, 211); assert.ok(f.synced.includes('/')); assert.equal(f.published.length, 0);
  });
});

test('non-native ancestor access errors remain failures, never silently ignored', async () => {
  await fixture({ native: false, denyAbove: true }, async f => {
    await assert.rejects(f.save(), error => error.code === 'EACCES' && error.syscall === 'open');
    assert.equal(f.denied.length, 1); assert.equal(f.published.length, 0);
  });
});
