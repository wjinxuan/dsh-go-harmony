import assert from 'node:assert/strict';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadDshClient } from './dsh-client-node-fixture.mjs';
const [clientPath, runtime] = process.argv.slice(2).map(value => resolve(value));
const Client = await loadDshClient(clientPath, join(runtime, 'main.cjs'), fileURLToPath(new URL('.', import.meta.url)));
const client = new Client();
const requests = [];
let status = 200;
let contentType = 'application/json; charset=utf-8';
let envelope = { ok: true, value: { language: 'zh', providers: [] } };
let late = false;
const http = { async fetch(request) {
  requests.push(request);
  if (late) client.http = {};
  return { statusCode: status, headers: { 'content-type': contentType },
    body: new TextEncoder().encode(JSON.stringify(envelope)).buffer };
} };
client.http = http;
client.clientId = 'fixture';
client.base = 'https://fixture.invalid/prefix';
client.headers = { cookie: 'dsh-auth-test=fixture', authorization: 'fixture-auth' };
client.proxy = 'system';
assert.deepEqual(await client.voiceScribeRequest({ action: 'get-settings' }), envelope.value);
const request = requests.at(-1);
assert.equal(request.uri, 'https://fixture.invalid/prefix/voice-input');
assert.equal(request.headers.cookie, 'dsh-auth-test=fixture');
assert.equal(request.headers.authorization, 'fixture-auth');
assert.equal(request.configuration.proxy, 'system');
assert.equal(request.configuration.transfer.autoRedirect, false);
assert.deepEqual(JSON.parse(request.body), { action: 'get-settings' });
envelope = { ok: true };
assert.deepEqual(await client.voiceScribeRequest({ action: 'set-settings', patch: { language: 'en' } }), {});
await assert.rejects(client.voiceScribeRequest({ action: 'get-settings' }), /无效设置/);
envelope = { ok: true, value: {} };
for (status of [302, 401, 403, 404, 500]) {
  await assert.rejects(client.voiceScribeRequest({ action: 'get-settings' }), /HTTP/);
}
status = 200;
for (contentType of ['text/html', 'application/jsonx', undefined]) {
  await assert.rejects(client.voiceScribeRequest({ action: 'get-settings' }), /无效响应/);
}
contentType = 'application/json';
envelope = { ok: true, value: { text: 'x'.repeat(262145) } };
await assert.rejects(client.voiceScribeRequest({ action: 'get-settings' }), /无效响应/);
envelope = { ok: false, error: { code: 'INVALID', message: 'private diagnostic' } };
await assert.rejects(client.voiceScribeRequest({ action: 'get-settings' }));
const before = requests.length;
await assert.rejects(client.voiceScribeRequest({ action: 'execute' }), /请求无效/);
await assert.rejects(client.voiceScribeRequest({ action: 'set-settings', patch: { text: 'x'.repeat(65537) } }), /过大/);
assert.equal(requests.length, before);
envelope = { ok: true, value: {} };
late = true;
await assert.rejects(client.voiceScribeRequest({ action: 'get-settings' }), /连接已变更/);
console.log('Voice scribe authenticated REST: 23 assertions passed');
