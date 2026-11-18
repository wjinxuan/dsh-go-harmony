import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, rm, symlink, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { createHash } from 'node:crypto';
import { Readable } from 'node:stream';
import { setTimeout as delay } from 'node:timers/promises';
import { downloadAsset, matchesAsset, senseVoiceAssets, senseVoiceTotalBytes, openModelUrl } from '../runtime/sensevoice-models.mjs';
import { SenseVoiceManager } from '../runtime/sensevoice-manager.mjs';

const bytes = Buffer.from('model fixture bytes');
const asset = { path: 'sensevoice-onnx/test.onnx', bytes: bytes.length,
  sha256: createHash('sha256').update(bytes).digest('hex'), urls: ['https://models.example/model'] };
const signal = () => new AbortController().signal;
function response(data, statusCode = 200, headers = {}) {
  return Object.assign(Readable.from([data]), { statusCode, headers });
}
async function directory(t) {
  const root = await mkdtemp(join(tmpdir(), 'sensevoice-test-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  return root;
}
async function partial(root, data) {
  const path = join(root, asset.path) + '.dsh-go.part';
  await mkdir(dirname(path), { recursive: true }); await writeFile(path, data); return path;
}
function nativeFixture(overrides = {}) {
  return { load: async () => {}, unload: async () => {}, cancel: () => {}, transcribe: async () => 'fixture', ...overrides };
}
function manager(root, native, options = {}) {
  return new SenseVoiceManager(root, native, { assets: [asset], space: async () => {},
    download: (root, asset, signal, progress) => downloadAsset(root, asset, signal, progress,
      async () => response(bytes)), ...options });
}

test('pinned assets match upstream INT8, tokens and Silero contract', () => {
  assert.equal(senseVoiceTotalBytes, 241357257);
  assert.deepEqual(senseVoiceAssets.map(a => a.bytes), [239233841, 315894, 1807522]);
  for (const a of senseVoiceAssets) { assert.match(a.sha256, /^[a-f0-9]{64}$/); assert.equal(a.urls.length, 2); }
});
test('verified complete asset is reused without a request', async t => {
  const root = await directory(t);
  await mkdir(dirname(join(root, asset.path)), { recursive: true }); await writeFile(join(root, asset.path), bytes);
  await downloadAsset(root, asset, signal(), () => {}, () => assert.fail('must not download'));
});
test('partial download requires an exact pinned content range', async t => {
  const root = await directory(t); await partial(root, bytes.subarray(0, 5));
  await downloadAsset(root, asset, signal(), () => {}, async (_, offset) => {
    assert.equal(offset, 5);
    return response(bytes.subarray(5), 206, { 'content-range': `bytes 5-${bytes.length - 1}/${bytes.length}` });
  });
  assert.equal(await matchesAsset(join(root, asset.path), asset, signal()), true);
});
test('server ignoring Range restarts the partial file safely', async t => {
  const root = await directory(t); await partial(root, bytes.subarray(0, 5));
  await downloadAsset(root, asset, signal(), () => {}, async () => response(bytes));
  assert.deepEqual(await readFile(join(root, asset.path)), bytes);
});
test('bad resume range never publishes the model', async t => {
  const root = await directory(t); const path = await partial(root, bytes.subarray(0, 5));
  await assert.rejects(downloadAsset(root, asset, signal(), () => {}, async () => response(bytes, 206,
    { 'content-range': `bytes 0-${bytes.length - 1}/${bytes.length}` })), /resume range/);
  assert.equal((await readFile(path)).length, 5);
  await assert.rejects(access(join(root, asset.path)));
});
test('wrong digest removes the bad partial, keeps previous complete file', async t => {
  const root = await directory(t); await mkdir(dirname(join(root, asset.path)), { recursive: true });
  await writeFile(join(root, asset.path), 'previous');
  await assert.rejects(downloadAsset(root, asset, signal(), () => {}, async () => response(Buffer.alloc(bytes.length))), /SHA-256/);
  assert.equal(await readFile(join(root, asset.path), 'utf8'), 'previous');
  await assert.rejects(access(join(root, asset.path) + '.dsh-go.part'));
});
test('oversized responses do not grow a partial past the pinned size', async t => {
  const root = await directory(t);
  await assert.rejects(downloadAsset(root, asset, signal(), () => {}, async () => response(Buffer.alloc(bytes.length + 1))), /pinned length/);
  assert.equal((await readFile(join(root, asset.path) + '.dsh-go.part')).length, 0);
});
test('download cancellation settles writers before allowing removal', async t => {
  const root = await directory(t); const controller = new AbortController();
  const stream = Object.assign(Readable.from((async function* () {
    yield bytes.subarray(0, 5); await delay(20); yield bytes.subarray(5);
  })()), { statusCode: 200, headers: {} });
  const run = downloadAsset(root, asset, controller.signal, done => { if (done === 5) controller.abort(); }, async () => stream);
  await assert.rejects(run, { name: 'AbortError' });
  const path = join(root, asset.path) + '.dsh-go.part';
  assert.equal((await readFile(path)).length, 5);
  await rm(path); await delay(25); await assert.rejects(access(path));
});
test('symlink files cannot redirect a model write', async t => {
  const root = await directory(t); const victim = join(root, 'victim'); await writeFile(victim, 'keep');
  const path = await partial(root, Buffer.alloc(0)); await rm(path); await symlink(victim, path);
  await assert.rejects(downloadAsset(root, asset, signal(), () => {}, async () => response(bytes)), /Unsafe model file/);
  assert.equal(await readFile(victim, 'utf8'), 'keep');
});
test('download URL rejects insecure transport and credentials', async () => {
  await assert.rejects(openModelUrl('http://example.com/model', 0, signal()), /Unsafe/);
  await assert.rejects(openModelUrl('https://secret@example.com/model', 0, signal()), /Unsafe/);
});
test('verified files never become ready when native loading fails', async t => {
  const worker = manager(await directory(t), nativeFixture({ load: async () => { throw new Error('native load failed'); } }));
  await assert.rejects(worker.start(), /native load failed/);
  assert.equal(worker.snapshot().phase, 'failed'); assert.equal(worker.snapshot().loaded, false);
  assert.equal(worker.snapshot().failure.reason, 'engine');
});
test('no native bridge cannot claim local SenseVoice readiness', async t => {
  const worker = manager(await directory(t), undefined);
  await assert.rejects(worker.start(), /no Harmony SenseVoice/);
  assert.equal(worker.snapshot().phase, 'failed'); assert.equal(worker.snapshot().nativeAvailable, false);
});
test('cancelling a native load joins completion and unloads before settling', async t => {
  let finish; const loading = Promise.withResolvers(); let unloaded = 0;
  const worker = manager(await directory(t), nativeFixture({ load: () => { loading.resolve(); return new Promise(r => { finish = r; }); },
    unload: async () => { unloaded++; } }));
  const running = worker.start(); await loading.promise;
  let settled = false; const cancelled = worker.cancel().then(() => { settled = true; });
  await delay(5); assert.equal(settled, false); assert.equal(worker.snapshot().phase, 'cancelling');
  await assert.rejects(worker.start(), /stopping/);
  finish(); await assert.rejects(running); await cancelled;
  assert.equal(unloaded, 1); assert.equal(worker.snapshot().phase, 'cancelled'); assert.equal(worker.loaded, false);
});
test('failed redownload retains loaded model and existing verified files', async t => {
  const root = await directory(t); const worker = manager(root, nativeFixture()); await worker.start();
  worker.download = async () => { throw Object.assign(new Error('offline'), { reason: 'network' }); };
  await assert.rejects(worker.start(true), /offline/);
  assert.equal(worker.snapshot().phase, 'ready'); assert.equal(worker.loaded, true);
  assert.deepEqual(await readFile(join(root, 'models', asset.path)), bytes);
  await assert.rejects(access(join(root, 'dsh-go-staging')));
});
test('delete waits for accepted inference and blocks a new download', async t => {
  let finish; const started = Promise.withResolvers(); let cancelled = 0;
  const worker = manager(await directory(t), nativeFixture({ transcribe: () => { started.resolve(); return new Promise(r => { finish = r; }); },
    cancel: () => { cancelled++; } }));
  await worker.start();
  const inference = worker.transcribe({ audio: Buffer.alloc(46), language: 'auto' }, signal()); await started.promise;
  let deleted = false; const removing = worker.remove().then(() => { deleted = true; });
  await delay(5); assert.equal(deleted, false); await assert.rejects(worker.start(), /stopping/);
  finish('fixture'); await inference; await removing;
  assert.ok(cancelled); assert.equal(worker.snapshot().phase, 'unprepared'); assert.equal(worker.loaded, false);
  assert.equal(worker.snapshot().completedBytes, 0);
});
