import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

const code = stripTypeScriptTypes(readFileSync(new URL('../entry/src/main/ets/ui/RegenerationAttachments.ets',
  import.meta.url), 'utf8').replace(/^import .*\n/gm, '').replace(/^export /gm, ''));
const prompt = { content: [
  { type: 'text', text: 'original' },
  { type: 'image', attachment: { name: 'one.png', attachmentId: 'one' } },
  { type: 'image', attachment: { name: 'two.png', attachmentId: 'two' } }
] };

function fixture() {
  const calls = [], deleted = [], closed = [];
  const fileIo = {
    OpenMode: { CREATE: 1, TRUNC: 2, WRITE_ONLY: 4 },
    async open(path) { calls.push(['open', path]); return { fd: path }; },
    async write(path, bytes) { calls.push(['write', path, [...new Uint8Array(bytes)]]); return bytes.byteLength; },
    async close(file) { closed.push(file.fd); }
  };
  let next = 0;
  const resendImages = vm.runInNewContext(`${code}\nresendImages`, {
    util: { generateRandomUUID: () => String(++next) }, fileIo,
    object: value => value || {},
    regenerationImageInfo: reference => ({ name: reference.name, mediaType: 'image/png' }),
    deleteAttachments: async files => deleted.push(...files.map(file => file.path))
  });
  const client = {
    async readSessionImage(id, reference, _cancel, current) {
      assert.equal(current(), true);
      calls.push(['read', id, reference.attachmentId]);
      return new Uint8Array(reference.attachmentId === 'one' ? [1, 2, 3] : [4, 5]).buffer;
    }
  };
  return { resendImages, client, fileIo, calls, deleted, closed };
}

test('image reconstruction reads the source in order and caches unchanged bytes before any fork', async () => {
  const { resendImages, client, calls, deleted, closed } = fixture();
  const files = await resendImages(client, 'source', prompt, '/cache', () => true);
  assert.deepEqual(JSON.parse(JSON.stringify(files)), [
    { id: '1', name: 'one.png', path: '/cache/dsh-attachment-1', size: 3, mediaType: 'image/png' },
    { id: '2', name: 'two.png', path: '/cache/dsh-attachment-2', size: 2, mediaType: 'image/png' }
  ]);
  assert.deepEqual(calls, [['read', 'source', 'one'], ['open', '/cache/dsh-attachment-1'],
    ['write', '/cache/dsh-attachment-1', [1, 2, 3]], ['read', 'source', 'two'],
    ['open', '/cache/dsh-attachment-2'], ['write', '/cache/dsh-attachment-2', [4, 5]]]);
  assert.deepEqual(deleted, []);
  assert.deepEqual(closed, ['/cache/dsh-attachment-1', '/cache/dsh-attachment-2']);
});

test('an image read failure removes earlier caches and keeps private host errors out of the UI', async () => {
  const { resendImages, client, deleted } = fixture();
  const read = client.readSessionImage;
  client.readSessionImage = async (...args) => {
    if (args[1].attachmentId === 'two') throw new Error('private provider credential');
    return read(...args);
  };
  await assert.rejects(resendImages(client, 'source', prompt, '/cache', () => true),
    error => error.message === '无法读取原消息中的图片。');
  assert.deepEqual(deleted, ['/cache/dsh-attachment-1']);
});

test('partial cache writes close and remove the affected file', async () => {
  const { resendImages, client, fileIo, deleted, closed } = fixture();
  fileIo.write = async () => 1;
  await assert.rejects(resendImages(client, 'source', prompt, '/cache', () => true), /图片/);
  assert.deepEqual(closed, ['/cache/dsh-attachment-1']);
  assert.deepEqual(deleted, ['/cache/dsh-attachment-1']);
});

test('connection or conversation changes retire downloads and clean every temporary file', async () => {
  for (const stage of ['read', 'open', 'write']) {
    const { resendImages, client, fileIo, calls, deleted, closed } = fixture();
    let current = true;
    const target = stage === 'read' ? client : fileIo;
    const method = stage === 'read' ? 'readSessionImage' : stage;
    const previous = target[method];
    target[method] = async (...args) => { const result = await previous(...args); current = false; return result; };
    await assert.rejects(resendImages(client, 'source', prompt, '/cache', () => current), /已切换/);
    assert.equal(calls.some(call => call[2] === 'two'), false);
    assert.deepEqual(deleted, stage === 'read' ? [] : ['/cache/dsh-attachment-1']);
    assert.deepEqual(closed, stage === 'read' ? [] : ['/cache/dsh-attachment-1']);
  }
});
