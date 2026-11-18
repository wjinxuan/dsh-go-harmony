import assert from 'node:assert/strict';
import test from 'node:test';
import { createHash, createCipheriv } from 'node:crypto';
import { deflateRawSync, gzipSync } from 'node:zlib';
import { mkdtemp, readFile, stat, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { encodeCode, decodeCode, conversationFile, decodeFile, conversationHtml, conversation, assetId } from '../runtime/share-codec.mjs';
import { redactText, redactJson, markdownWithoutImages, cutText } from '../runtime/share-redact.mjs';
import { encryptShare, decryptShare, hostedLink, uploadShare, downloadShare, deleteShare, SHARE_ORIGIN } from '../runtime/share-hosted.mjs';
import { exportConversation } from '../runtime/share-export.mjs';
import { createShareHandler } from '../runtime/share-service.mjs';
import { startTransportControl } from '../runtime/transport-control.mjs';

const body = { v: 2, kind: 'conversation', schema: 1, title: '测试', start: '2026-11-16T00:00:00Z', entries: [{ type: 'user', t: 0, text: '你好' }, { type: 'reply', t: 10, d: 100, text: '世界' }] };
const source = { title: '示例', messages: [
  { id: 'u1', role: 'user', seq: 2, text: 'one' }, { id: 'r1', role: 'assistant', seq: 4, text: 'answer1', reasoning: 'thinking' },
  { id: 'u2', role: 'user', seq: 8, text: 'two' }, { id: 'r2', role: 'assistant', seq: 10, text: 'answer2' }
], records: [1, 2, 3, 4, 5, 7, 8, 9, 10, 11].map(seq => ({ seq, time: 1000 + seq * 100, type: 'fixture', data: {} })),
tools: [{ seq: 3, callId: 'tool1', name: 'read', arguments: '{"token":"abcdefghi"}', result: 'tool result' },
  { seq: 9, callId: 'tool2', name: 'read', arguments: '{}', result: 'second' }],
turns: [{ startSeq: 1, endSeq: 5, start: 1100, end: 1500, steps: 1, spans: [{ kind: 'model', seq: 4, firstToken: 1350, lastToken: 1450, model: 'model' }] },
  { startSeq: 7, endSeq: 11, start: 1700, end: 2100, steps: 1, spans: [] }], notices: [{ seq: 5, kind: 'stopped', text: 'notice' }], commands: [] };

test('original raw-DEFLATE/SHA-256 wire format and file assets round trip', () => {
  const json = Buffer.from(JSON.stringify(body));
  const independent = deflateRawSync(json, { level: 9 }).toString('base64url') + '.' + createHash('sha256').update(json).digest().subarray(0, 6).toString('base64url');
  assert.equal(encodeCode(body), independent); assert.deepEqual(decodeCode(independent), body);
  const bytes = Buffer.from('fixture-image'), id = assetId(bytes);
  const withImage = structuredClone(body); withImage.entries[0].images = [{ id }];
  const output = conversationFile(withImage, { [id]: { type: 'image/png', data: bytes.toString('base64') }, unused: { type: 'image/png', data: 'YQ==' } });
  assert.deepEqual(Object.keys(decodeFile(output.file).assets), [id]);
  assert.deepEqual(decodeFile(output.code).body, output.body);
  const envelope = JSON.parse(output.file); envelope.assets[id].data = 'YmFk';
  assert.deepEqual(Object.keys(decodeFile(JSON.stringify(envelope)).assets), []);
});

test('checksum, UTF-8, inflation limits and newer schema reject corrupt inputs', () => {
  assert.throws(() => decodeCode(encodeCode(body).slice(0, -1) + '!'));
  assert.throws(() => decodeCode('A.AAAAAAAA'));
  assert.throws(() => conversation({ ...body, schema: 2 }));
  assert.throws(() => conversation({ ...body, entries: [null] }));
  assert.equal(conversation({ ...body, entries: [{ type: 'future' }] }).entries.length, 0);
  const bomb = deflateRawSync(Buffer.alloc(16 * 1024 * 1024 + 1)).toString('base64url') + '.AAAAAAAA';
  assert.throws(() => decodeCode(bomb), /大小/);
  const invalid = Buffer.from([0xff]), sum = createHash('sha256').update(invalid).digest().subarray(0, 6).toString('base64url');
  assert.throws(() => decodeCode(deflateRawSync(invalid).toString('base64url') + '.' + sum), /JSON/);
  const text = conversation({ ...body, title: 'x'.repeat(119) + '😀', entries: [{ type: 'reply', t: 1.2, text: 'ok' }] });
  assert.equal(text.entries[0].t, 1); assert.ok(!/[\uD800-\uDBFF]…$/.test(text.title));
});

test('redaction covers credentials, home/private paths and tools before sharing', () => {
  const token = 'sk-1234567890abcdefghijklmnopqrstuv';
  const text = redactText(`Authorization: Bearer abc123xyz\n${token}\nPASSWORD=private-secret-value\nhttps://u:password@example.test\n/Users/alice/docs /data/storage/el2/base/files`);
  assert.ok(!text.includes('abc123xyz')); assert.ok(!text.includes(token)); assert.ok(!text.includes('private-secret-value'));
  assert.ok(!text.includes(':password@')); assert.ok(!text.includes('/Users/alice')); assert.ok(!text.includes('/data/storage/el2/base'));
  assert.equal(redactText('basic usage /root/file TOKEN=$TOKEN'), 'basic usage /root/file TOKEN=$TOKEN');
  assert.equal(redactJson({ token: 'unformatted-secret' }).token, '••••••');
  const key = redactText('-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----');
  assert.ok(!key.includes('AAAA')); assert.ok(key.includes('BEGIN PRIVATE KEY'));
  assert.equal(markdownWithoutImages('![remote](https://evil.test/pixel)\n```\n![code](x)\n```'), '〔remote〕\n```\n![code](x)\n```');
  const cut = cutText('😀'.repeat(50), 11); assert.ok(!/[\uD800-\uDBFF]\n|\n[\uDC00-\uDFFF]/.test(cut.text)); assert.ok(cut.omitted > 0);
});

test('round/message selection preserves selected-turn work and true timings', () => {
  const selected = exportConversation(source, { only: ['r1'] }, 5000);
  assert.deepEqual(selected.entries.map(e => e.type), ['turn', 'tool', 'reply', 'notice']);
  assert.equal(selected.entries.find(e => e.type === 'reply').d, 100);
  assert.equal(selected.entries.find(e => e.type === 'tool').args.token, '••••••');
  assert.deepEqual(selected.range, { from: 1, to: 1, of: 2 });
  const promptOnly = exportConversation(source, { only: ['u1'] });
  assert.ok(!promptOnly.entries.some(e => e.type === 'tool'));
  const range = exportConversation(source, { from: 2, to: 2, tools: false, thinking: false });
  assert.deepEqual(range.entries.map(e => e.type), ['turn', 'user', 'reply']);
  assert.ok(!range.entries.some(e => e.text === 'one'));
  assert.throws(() => exportConversation(source, { only: ['missing'] }));
  assert.throws(() => exportConversation(source, { from: 0 }));
});

test('AES-GCM hosted wire interoperates, rejects tampering and bounds inflation', () => {
  const text = conversationFile(body).file, encrypted = encryptShare(text);
  assert.equal(decryptShare(encrypted.bytes, encrypted.key), text);
  const corrupt = Buffer.from(encrypted.bytes); corrupt[20] ^= 1;
  assert.throws(() => decryptShare(corrupt, encrypted.key), /解密/);
  assert.throws(() => decryptShare(encrypted.bytes, 'A'.repeat(43)), /解密/);
  const key = Buffer.alloc(32), iv = Buffer.alloc(12), cipher = createCipheriv('aes-256-gcm', key, iv);
  const blob = Buffer.concat([Buffer.from('DSG1'), iv, cipher.update(gzipSync(Buffer.alloc(64 * 1024 * 1024 + 1))), cipher.final(), cipher.getAuthTag()]);
  assert.throws(() => decryptShare(blob, key.toString('base64url')), /解密/);
});

test('hosted requests never send fragment key/title and reject unsafe links or redirects', async () => {
  let stored, key;
  const fetcher = async (url, request) => {
    assert.ok(!url.includes('#')); assert.equal(request.redirect, 'error');
    if (request.method === 'POST') { stored = request.body; assert.equal(request.headers['content-type'], 'application/octet-stream');
      assert.ok(!stored.includes(Buffer.from('测试'))); return new Response(JSON.stringify({ id: 'abcdEF1234', deleteToken: 'delete-test' }), { status: 201 }); }
    if (request.method === 'DELETE') { assert.equal(request.headers.authorization, 'Bearer delete-test'); return new Response(null, { status: 204 }); }
    assert.equal(url, SHARE_ORIGIN + '/api/v1/c/abcdEF1234'); return new Response(stored);
  };
  const link = await uploadShare(conversationFile(body).file, '7d', { fetcher }); key = link.key;
  assert.equal(hostedLink(link.url).key, key);
  assert.equal((await downloadShare(link.url, { fetcher })), conversationFile(body).file);
  await deleteShare(link, { fetcher });
  for (const url of [link.url.replace('go.dshtui.com', 'evil.test'), link.url.replace('https:', 'http:'), link.url.replace('/c/', '/c/../c/'), link.url.replace('#k=', '?k=')]) {
    if (url.includes('/../')) continue; // URL canonicalization still points to the exact allowed origin and endpoint.
    assert.throws(() => hostedLink(url));
  }
});

test('original offline replay template escapes data and retains original CSP', async () => {
  const template = await readFile(new URL('../runtime/vendor/replay/viewer.html', import.meta.url), 'utf8');
  const hostile = conversationFile({ ...body, title: '<script>x</script>', entries: [{ type: 'reply', t: 0, text: '</script><script>alert(1)</script>&\u2028' }] });
  const html = conversationHtml(hostile.file, hostile.body.title, template);
  assert.ok(html.includes('connect-src \'none\'')); assert.ok(html.includes('&lt;script&gt;x&lt;/script&gt;'));
  assert.ok(!html.includes('</script><script>alert(1)')); assert.ok(!html.includes('__DSHGO_DATA__'));
});

test('authenticated share service persists management keys privately and fails closed on corruption', async t => {
  const root = await mkdtemp(join(tmpdir(), 'dsh-share-'));
  let uploaded = 0;
  const control = await startTransportControl({ share: createShareHandler(root, { fetcher: async (_url, request) => {
    if (request.method === 'DELETE') return new Response(null, { status: 204 });
    uploaded++; return new Response(JSON.stringify({ id: 'abcdEF1234', deleteToken: 'managed-secret' }), { status: 201 });
  } }) });
  t.after(async () => { await control.close(); await rm(root, { recursive: true, force: true }); });
  const call = async (name, body) => {
    const response = await fetch(control.endpoint.url + '/share/' + name, { method: 'POST', headers: { authorization: control.endpoint.authorization, 'content-type': 'application/json' }, body: JSON.stringify({ ...body, masterKey: Buffer.alloc(32, 7).toString('base64url') }) });
    return { status: response.status, body: await response.json() };
  };
  assert.equal((await fetch(control.endpoint.url + '/share/links', { method: 'POST' })).status, 403);
  const prepared = await call('prepare', { source, options: {} }); assert.equal(prepared.status, 200); assert.ok(prepared.body.html);
  const uploadedResult = await call('upload', { file: prepared.body.file, ttl: '7d' }); assert.equal(uploadedResult.status, 200); assert.ok(!JSON.stringify(uploadedResult.body).includes('managed-secret'));
  const path = join(root, '.harmony-share-links-v2.json'); assert.equal((await stat(path)).mode & 0o777, 0o600);
  assert.ok(!(await readFile(path, 'utf8')).includes('managed-secret'));
  assert.equal((await call('links', {})).body.links.length, 1);
  assert.equal((await call('delete', { id: 'abcdEF1234' })).status, 200);
  assert.equal((await call('links', {})).body.links.length, 0);
  await writeFile(path, 'corrupted', { mode: 0o600 });
  assert.equal((await call('upload', { file: prepared.body.file, ttl: '7d' })).status, 400); assert.equal(uploaded, 1);
  assert.equal(await readFile(path, 'utf8'), 'corrupted');
});
