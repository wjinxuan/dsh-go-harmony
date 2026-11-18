import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { createServer } from 'node:http';
import { join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { loadDshClient } from './dsh-client-node-fixture.mjs';

const [clientPath, runtime, lockFixture] = process.argv.slice(2).map(path => resolve(path));
const DshClient = await loadDshClient(clientPath, join(runtime, 'main.cjs'), fileURLToPath(new URL('.', import.meta.url)));
const home = await mkdtemp('/tmp/dsh-speech-live-');
const child = spawn(process.execPath, ['--jitless', '--no-addons', '--expose-internals', '--require', lockFixture,
  join(runtime, 'main.cjs'), home], { stdio: 'ignore' });
const client = new DshClient();
const calls = [];
let responseStatus = 200;
let gatewayError;
let hold;
let held;
let selection = { providerId: 'fixture-speech', language: 'zh-CN' };
let phase = 'unprepared';
const speech = createServer(async (request, response) => {
  let text = '';
  for await (const bytes of request) text += bytes;
  const body = JSON.parse(text);
  calls.push(body);
  if (hold) { held(); return; }
  response.writeHead(responseStatus, { 'content-type': 'application/json' });
  if (responseStatus !== 200) { response.end('{}'); return; }
  let value = {};
  const args = body.payload.args;
  if (body.method === 'speech/catalog') value = { providers: [{ id: 'fixture-speech', name: 'Synthetic test recognizer',
    location: 'host-local', languages: ['zh-CN'], preparation: { phase }, downloadSources: ['fixture-mirror'] }],
    selection, maxAudioBytes: 1048576, maxDurationSeconds: 30 };
  else if (body.method === 'speech/configure') selection = { ...selection, ...args.patch };
  else if (body.method === 'speech/prepare') phase = 'ready';
  else if (body.method === 'speech/cancelPreparation') phase = 'cancelled';
  else if (body.method === 'speech/transcribe') {
    assert.equal(typeof args.request.audioBase64, 'string');
    const bytes = Buffer.from(args.request.audioBase64, 'base64');
    assert.equal(bytes.subarray(0, 4).toString(), 'RIFF');
    assert.equal(bytes.readUInt32LE(24), 16000);
    value = { text: '  合成服务转写结果  ', audioSeconds: 1 };
  }
  response.end(JSON.stringify({ type: 'server-response', rpcId: body.rpcId,
    result: gatewayError ? { ok: false, error: { code: gatewayError, message: 'private service message' } } : { ok: true, value } }));
});
await new Promise(resolve => speech.listen(0, '127.0.0.1', resolve));

function wav() {
  const bytes = Buffer.alloc(32044);
  bytes.write('RIFF'); bytes.writeUInt32LE(bytes.length - 8, 4); bytes.write('WAVEfmt ', 8);
  bytes.writeUInt32LE(16, 16); bytes.writeUInt16LE(1, 20); bytes.writeUInt16LE(1, 22);
  bytes.writeUInt32LE(16000, 24); bytes.writeUInt32LE(32000, 28); bytes.writeUInt16LE(2, 32);
  bytes.writeUInt16LE(16, 34); bytes.write('data', 36); bytes.writeUInt32LE(32000, 40);
  return new Uint8Array(bytes).buffer;
}

try {
  let ready;
  for (let attempt = 0; attempt < 200 && !ready; attempt++) {
    ready = await readFile(join(home, 'ready.json'), 'utf8').then(JSON.parse, () => undefined);
    if (!ready && child.exitCode !== null) throw new Error('Local engine exited before ready');
    if (!ready) await delay(100);
  }
  assert.ok(ready, 'packaged local engine becomes ready');
  await client.connect(ready.url, undefined, true);
  const localCatalog = await client.speechCatalog();
  assert.equal(localCatalog.providerId, 'sensevoice-local');
  assert.equal(localCatalog.providers[0].phase, 'unprepared', 'model is never ready before native loading');

  // Exercise the real client HTTP/RPC path against a deterministic speech service; no speech model is claimed here.
  client.base = `http://127.0.0.1:${speech.address().port}`;
  const catalog = await client.speechCatalog();
  assert.equal(catalog.providerId, 'fixture-speech');
  assert.equal(catalog.providers[0].phase, 'unprepared');
  await client.configureSpeech('fixture-speech', 'zh-CN');
  assert.deepEqual(calls.at(-1).payload.args, { patch: { providerId: 'fixture-speech', language: 'zh-CN' } });
  await client.prepareSpeech('fixture-speech', 'fixture-mirror');
  assert.deepEqual(calls.at(-1).payload.args, { providerId: 'fixture-speech', options: { downloadSource: 'fixture-mirror' } });
  assert.equal((await client.speechCatalog()).providers[0].phase, 'ready');
  await client.cancelSpeechPreparation('fixture-speech');
  assert.deepEqual(calls.at(-1).payload.args, { providerId: 'fixture-speech' });
  assert.equal((await client.speechCatalog()).providers[0].phase, 'cancelled');
  const result = await client.transcribeSpeech(wav(), 'fixture-speech', 'zh-CN');
  assert.deepEqual(result, { text: '合成服务转写结果', audioSeconds: 1 });
  assert.equal(calls.at(-1).payload.args.request.providerId, 'fixture-speech');
  const count = calls.length;
  await assert.rejects(client.transcribeSpeech(new ArrayBuffer(0)), /录音/);
  assert.equal(calls.length, count, 'bad audio is rejected before upload');

  responseStatus = 404;
  assert.equal(await client.speechCatalog(), undefined);
  responseStatus = 403;
  await assert.rejects(client.speechCatalog(), /拒绝请求/);
  responseStatus = 200;
  gatewayError = 'gateway/definition-unavailable';
  assert.equal(await client.speechCatalog(), undefined);
  for (gatewayError of ['gateway/internal', 'gateway/bad-request']) {
    await assert.rejects(client.speechCatalog(), /主机请求失败/);
  }
  gatewayError = undefined;
  const requested = new Promise(resolve => { held = resolve; });
  hold = true;
  let cancel;
  const transcribing = client.transcribeSpeech(wav(), undefined, undefined, stop => { cancel = stop; });
  const rejected = assert.rejects(transcribing, /通信失败/);
  await requested;
  assert.equal(typeof cancel, 'function');
  cancel();
  await rejected;
  console.log('Speech live: packaged engine reports SenseVoice unprepared until native loading; real HTTP catalog/configure/prepare/cancel/transcribe, WAV validation, 403/404 and cancellation passed with a synthetic speech service.');
} finally {
  client.close();
  speech.closeAllConnections();
  await new Promise(resolve => speech.close(resolve));
  if (child.exitCode === null) { child.kill('SIGTERM'); await once(child, 'exit'); }
  await rm(home, { recursive: true, force: true });
}
