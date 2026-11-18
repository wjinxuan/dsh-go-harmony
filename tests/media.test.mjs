import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { loadMediaModules } from './media-loader.mjs';

const { parseMediaHeader, formatMediaHeader, formatMediaMessage, mediaCatalog, defaultMediaEntry,
  fitMediaParams, mediaUrlIssue, mediaMeta, mediaServiceWire, loadMediaCatalog, readMediaFile,
  mediaParamsFromMeta, regenerateMediaMessage, validateMediaReferences, parseBinaryRpcResponse } = await loadMediaModules();
const golden = JSON.parse(await readFile(new URL('./fixtures/media/header_grammar_v1.json', import.meta.url)));
const source = JSON.parse(await readFile(new URL('./fixtures/media/settings_describe_media_m0.json', import.meta.url)));
const keys = { DSH_MEDIA_SLOT_1_API_KEY: { configured: true, writable: true }, DSH_MEDIA_SLOT_2_API_KEY: { configured: true, writable: true } };
const fixture = () => structuredClone(source);
const catalogOf = data => Object.values(data.namespaces[0].schema.refs).find(node => node.meta?.extra?.['dsh-go/media/catalog']).meta.extra['dsh-go/media/catalog'];

test('matches every fixed v1.0.15 generation header golden in both directions', () => {
  for (const item of golden.valid) {
    assert.deepEqual(parseMediaHeader(item.text), item.expected, item.id);
    assert.deepEqual(parseMediaHeader(formatMediaHeader(item.expected)), item.expected, item.id);
    if (item.canonical !== false) assert.equal(formatMediaHeader(item.expected), item.text, item.id);
  }
  for (const item of golden.plain) assert.equal(parseMediaHeader(item.text), undefined, item.id);
  for (const item of golden.invalid) assert.throws(() => parseMediaHeader(item.text), { message: item.code }, item.id);
  for (const item of golden.format) {
    assert.equal(formatMediaHeader(item.value), item.text, item.id);
    assert.deepEqual(parseMediaHeader(item.text), item.value, item.id);
  }
  for (const item of golden.formatRejects) assert.throws(() => formatMediaHeader(item.value), { message: item.code }, item.id);
});

test('catalogue discovers schema metadata and only offers enabled credential-backed unambiguous service/model pairs', () => {
  const data = fixture(); const catalog = mediaCatalog(data, keys);
  assert.equal(catalog.status, 'ready');
  assert.deepEqual(catalog.entries.map(e => `${e.namespace}/${e.service.id}/${e.model.id}`), [
    'dsh-media/office/gpt-image-2', 'dsh-media/office/gpt-image-2.5-flare']);
  assert.equal(mediaCatalog(data).entries.length, 0);
  data.namespaces[0].ns = 'renamed-media';
  assert.equal(mediaCatalog(data, keys).entries[0].namespace, 'renamed-media');
  data.namespaces.push(structuredClone(data.namespaces[0]));
  assert.equal(mediaCatalog(data, keys).entries.length, 0);
});

test('catalogue rejects broken/unsupported data and respects capabilities, limits and defaults', () => {
  for (const damage of [
    c => { delete c.v; }, c => { c.models = {}; }, c => { delete c.models[0].id; },
    c => { c.models[0].label = 1; }, c => { c.models.push(c.models[0]); },
    c => { c.models[0].ratios = [1, 2]; }, c => { c.models[0].maxN = 'four'; }, c => { c.capabilities = true; }
  ]) {
    const data = fixture(); damage(catalogOf(data));
    assert.equal(mediaCatalog(data, keys).status, 'broken');
    assert.equal(mediaCatalog(data, keys).entries.length, 0);
  }
  const data = fixture(); catalogOf(data).v = 2;
  assert.equal(mediaCatalog(data, keys).status, 'unsupported');
  catalogOf(data).v = 1; catalogOf(data).capabilities.image = false;
  assert.equal(mediaCatalog(data, keys).entries.length, 0);
  catalogOf(data).capabilities.image = true;
  data.namespaces[0].value.limits.maxImages = 2;
  data.namespaces[0].value.defaults.imageServiceId = 'office';
  data.namespaces[0].value.defaults.imageModelId = 'gpt-image-2.5-flare';
  const catalog = mediaCatalog(data, keys);
  assert.equal(defaultMediaEntry(catalog, 'image').model.id, 'gpt-image-2.5-flare');
  const params = fitMediaParams({ kind: 'image', count: 4, aspect: 'wrong', quality: 'unknown' }, catalog);
  assert.equal(params.count, 2); assert.equal(params.aspect, '1:1'); assert.equal(params.quality, undefined);
  assert.match(formatMediaMessage(params, '猫'), /〈office\/gpt-image-2.5-flare〉〕\n猫$/);
  assert.equal(typeof mediaServiceWire(params.model.service).models, 'string');
});

test('base URL checks and result metadata preserve host file paths without interpreting URLs as credentials', () => {
  assert.equal(mediaUrlIssue('https://api.example.test/v1', 'openai-compatible'), '');
  for (const target of ['http://api.example.test', 'https://key@example.test', 'https://example.test?key=x',
    'https://example.test:99999', 'https://example.test/v1/images/generations']) assert.ok(mediaUrlIssue(target, 'openai-compatible'));
  assert.ok(mediaUrlIssue('https://example.test/v1', 'ark-image'));
  assert.equal(mediaMeta({ 'dsh-go/media': { kind: 'image', items: [] } }), undefined);
  const meta = mediaMeta({ 'dsh-go/media': { v: 1, kind: 'video', status: 'running', rid: 'one', job: 'job-1', request: { seconds: 5 } } });
  assert.equal(meta.job, 'job-1'); assert.equal(meta.status, 'running');
  assert.equal(mediaMeta({ 'dsh-go/media': { items: [{ path: '/workspace/cat.png', mime: 'image/png' }] } }).items[0].name, 'cat.png');
});

test('regeneration pins only a unique live provider/model and reference constraints match upstream', () => {
  const data = fixture(); const catalog = mediaCatalog(data, keys);
  const meta = mediaMeta({ 'dsh-go/media': { kind: 'image', status: 'failed', prompt: 'Same request',
    request: { provider: 'openai', model: 'gpt-image-2', aspect: '3:2', n: 2, quality: 'high', refs: 1 } } });
  const params = mediaParamsFromMeta(meta, catalog);
  assert.equal(params.model.service.id, 'office'); assert.equal(params.count, 2);
  assert.match(regenerateMediaMessage(meta, catalog), /GPT Image 2〈office\/gpt-image-2〉/);
  assert.doesNotThrow(() => validateMediaReferences(params, catalog, 0));
  assert.throws(() => validateMediaReferences(params, catalog, 100), /参考图片/);
  catalog.entries.push({ ...catalog.entries[0], service: { ...catalog.entries[0].service, id: 'other' } });
  assert.equal(mediaParamsFromMeta(meta, catalog).model, undefined);
  assert.equal(mediaParamsFromMeta(meta, catalog).modelLabel, 'gpt-image-2');
  assert.equal(regenerateMediaMessage(meta, catalog), undefined);
  assert.throws(() => validateMediaReferences(mediaParamsFromMeta(meta, catalog), catalog, 0), /选择/);
});

test('catalogue fetch resolves credentials on the same connection and rejects late host replies', async () => {
  const client = { epoch: 1, connectionIdentity() { return this.epoch; }, describeSettings: async () => fixture(),
    describeCredentials: async refs => { assert.deepEqual(refs, ['DSH_MEDIA_SLOT_1_API_KEY']); return keys; } };
  assert.equal((await loadMediaCatalog(client)).entries.length, 2);
  client.describeCredentials = async () => { client.epoch++; return keys; };
  await assert.rejects(loadMediaCatalog(client), /主机已切换/);
});

test('media file reader uses authenticated RPC windows, checks versions/size and discards switched-host bytes', async () => {
  const received = []; const calls = [];
  const client = { epoch: 1, connectionIdentity() { return this.epoch; }, async request(method, args) {
    calls.push([method, args]);
    if (method.endsWith('/stat')) return { bytes: 6, version: 'v1' };
    const offset = args.options.range.offset;
    return { data: Buffer.from(offset ? 'def' : 'abc').toString('base64'), version: 'v1', eof: offset > 0 };
  } };
  assert.equal(await readMediaFile(client, 'session-1', '/generated/test.png', 20, async chunk => received.push(Buffer.from(chunk)), () => true), 6);
  assert.equal(Buffer.concat(received).toString(), 'abcdef');
  assert.equal(calls[1][1].workspaceFileScopeId, 'session-1'); assert.equal(calls[2][1].options.range.offset, 3);
  await assert.rejects(readMediaFile(client, 'session-1', '/generated/test.png', 5, async () => {}, () => true), /大小限制/);
  const original = client.request;
  client.request = async function(method, args) { const result = await original.call(this, method, args); if (method.endsWith('/readBytes')) result.version = 'v2'; return result; };
  await assert.rejects(readMediaFile(client, 'session-1', '/a', 20, async () => assert.fail('must not deliver changed bytes'), () => true), /已变化/);
  client.request = async function(method, args) { const result = await original.call(this, method, args); if (method.endsWith('/readBytes')) this.epoch++; return result; };
  await assert.rejects(readMediaFile(client, 'session-1', '/a', 20, async () => assert.fail('must not deliver another host bytes'), () => true), /取消/);
  client.request = async method => method.endsWith('/stat') ? { bytes: 6, version: 'v1' } : { data: 'YQ==', version: 'v1', eof: true };
  await assert.rejects(readMediaFile(client, 'session-1', '/a', 20, async () => {}, () => true), /未完整/);
});

test('binary RPC decoder preserves bytes and rejects correlation, duplicate parts, invalid paths and placeholders', () => {
  const envelope = { type: 'server-response', rpcId: 'binary-1', result: { ok: true, value: { data: null, version: 'v1', eof: true } },
    attachments: [{ codec: 'bytes', part: 'bytes-1', path: ['data'] }] };
  function body(metadata, extras = []) {
    const fields = [['metadata', Buffer.from(JSON.stringify(metadata))], ['bytes-1', Buffer.from([0, 13, 10, 255])], ...extras];
    const data = Buffer.concat(fields.flatMap(([name, bytes]) => [Buffer.from(`--fixture\r\nContent-Disposition: form-data; name="${name}"\r\n\r\n`), bytes, Buffer.from('\r\n')]).concat(Buffer.from('--fixture--\r\n')));
    return data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
  }
  const read = value => parseBinaryRpcResponse(body(value), 'multipart/form-data; boundary="fixture"', 'binary-1', 'workspaceFiles/readBytes');
  assert.deepEqual(Array.from(read(envelope).data), [0, 13, 10, 255]);
  assert.throws(() => parseBinaryRpcResponse(body(envelope), 'multipart/form-data; boundary=fixture', 'wrong', 'workspaceFiles/readBytes'));
  assert.throws(() => parseBinaryRpcResponse(body(envelope, [['bytes-1', Buffer.from('duplicate')]]), 'multipart/form-data; boundary=fixture', 'binary-1', 'workspaceFiles/readBytes'));
  for (const path of [['missing'], ['__proto__'], ['constructor'], ['data', -1]]) {
    assert.throws(() => read({ ...envelope, attachments: [{ ...envelope.attachments[0], path }] }));
  }
  assert.throws(() => read({ ...envelope, result: { ok: true, value: { data: 'not-null' } } }));
  assert.throws(() => read({ ...envelope, attachments: [] }));
});
