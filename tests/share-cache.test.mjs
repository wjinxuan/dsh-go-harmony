import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
const name = 'dsh-share-12345678-1234-1234-1234-123456789abc.dshgo';
const source = (await readFile(new URL('../entry/src/main/ets/ui/ShareCache.ets', import.meta.url), 'utf8')).replace(/^import.*$/gm, '');
const files = new Map(), calls = [], fileIo = {
  OpenMode: { CREATE: 1, NOFOLLOW: 2, WRITE_ONLY: 4 },
  listFile: async () => [...files.keys()], lstat: async path => files.get(path.split('/').pop()),
  unlink: async path => { calls.push(['unlink', path]); files.delete(path.split('/').pop()); },
  access: async path => files.has(path.split('/').pop()),
  open: async (path, mode) => { calls.push(['open', mode]); files.set(path.split('/').pop(), {}); return { fd: 7 }; },
  write: async (_fd, buffer) => buffer.byteLength,
  fsync: async () => calls.push(['sync']), close: async () => calls.push(['close'])
};
globalThis.shareCacheFixture = { fileIo, util: { generateRandomUUID: () => name.slice(10, -6), TextEncoder: { create: () => ({ encodeInto: text => new TextEncoder().encode(text) }) } } };
const api = await import('data:text/javascript,' + encodeURIComponent('const { fileIo, util } = globalThis.shareCacheFixture;\n' + stripTypeScriptTypes(source)));
test('expiry only removes old ordinary share files and preserves fresh files, symlinks and unrelated data', async () => {
  const old = name, fresh = name.replace('12345678', '22345678'), link = name.replace('12345678', '32345678');
  files.set(old, { isFile: () => true, mtime: 1 }); files.set(fresh, { isFile: () => true, mtime: 99999 });
  files.set(link, { isFile: () => false, mtime: 1 }); files.set('private.txt', { isFile: () => true, mtime: 1 });
  await api.pruneShareCache('/cache', 100000);
  assert.equal(files.has(old), false); assert.deepEqual([...files.keys()], [fresh, link, 'private.txt']);
});
test('cache writes reject collisions and remove partial writes without publishing truncated files', async () => {
  files.clear(); calls.length = 0;
  const path = await api.writeShareCache('/cache', '分享内容'); assert.equal(path, '/cache/' + name);
  assert.deepEqual(calls, [['open', 7], ['sync'], ['close']]);
  await assert.rejects(api.writeShareCache('/cache', 'again'), /已存在/);
  files.clear(); calls.length = 0; fileIo.write = async () => 1;
  await assert.rejects(api.writeShareCache('/cache', 'not complete'), /不完整/);
  assert.equal(files.size, 0); assert.deepEqual(calls, [['open', 7], ['close'], ['unlink', path]]);
});
