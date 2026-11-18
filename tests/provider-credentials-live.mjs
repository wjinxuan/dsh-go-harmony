import './require-runtime-node.mjs';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import { stripTypeScriptTypes } from 'node:module';
import { setTimeout as delay } from 'node:timers/promises';
import { loadDshClient } from './dsh-client-node-fixture.mjs';
import { unlockTestCredentials } from './unlock-test-credentials.mjs';

const runtime = resolve(process.argv[2]), project = fileURLToPath(new URL('../', import.meta.url));
const providerDraftSource = await readFile(join(project, 'entry/src/main/ets/ui/settings/ProviderDraft.ets'), 'utf8');
const { providerDiscoveryArgs } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(
  providerDraftSource.replace(/^import .*\n/gm, '')
)).toString('base64'));
const root = await realpath(await mkdtemp(join(tmpdir(), 'dsh-provider-restart-live-'))), home = join(root, 'home');
const masterKey = randomBytes(32).toString('base64url'), secret = randomBytes(24).toString('hex'), ref = 'RESTART_FIXTURE_KEY';
let child, client, ready, log = '', listings = 0;
const server = createServer((request, response) => {
  if (request.url !== '/v1/models' || request.headers.authorization !== 'Bearer ' + secret) { response.writeHead(403).end(); return; }
  listings++; response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ object: 'list', data: [{ id: 'restart-fixture' }] }));
});
async function boot() {
  child = spawn(process.execPath, ['--jitless', '--no-addons', '--expose-internals', '--require', join(project, 'tests/local-flock-fixture.cjs'), join(runtime, 'main.cjs'), home], { stdio: ['ignore', 'ignore', 'pipe'] });
  child.stderr.on('data', value => { log += value; });
  ready = undefined;
  for (let i = 0; i < 300 && !ready; i++) {
    ready = await readFile(join(home, 'ready.json'), 'utf8').then(JSON.parse, () => undefined);
    if (child.exitCode !== null) throw Error('Runtime exited before ready'); if (!ready) await delay(50);
  }
  assert.ok(ready, 'Runtime ready'); await unlockTestCredentials(ready, masterKey);
  const Client = await loadDshClient(join(project, 'entry/src/main/ets/dsh/DshClient.ets'), join(runtime, 'main.cjs'), root);
  client = new Client(); await client.connect(ready.url, undefined, true);
}
async function stop() {
  client?.close(); client = undefined;
  if (child?.exitCode === null) { await writeFile(join(home, 'stop'), ''); await Promise.race([once(child, 'exit'), delay(5000)]); if (child.exitCode === null) { child.kill('SIGKILL'); throw Error('Runtime stop timeout'); } }
  assert.equal(child.exitCode, 0); await rm(join(home, 'ready.json'), { force: true });
}
const discovery = () => {
  const address = 'http://127.0.0.1:' + server.address().port + '/v1';
  return client.request('llm/discoverModels', providerDiscoveryArgs(address, 'openai-completions', '',
    'restart-fixture', address, 'openai-completions'));
};
try {
  await new Promise(done => server.listen(0, '127.0.0.1', done)); await boot();
  const baseline = (await client.listModels()).defaultSelection;
  await client.setProviderKey(secret, ref);
  await client.mutateSettings('llm-pi-ai', [{ op: 'set', path: ['providers', 'restart-fixture'], value: {
    api: 'openai-completions', baseURL: 'http://127.0.0.1:' + server.address().port + '/v1', apiKeyEnv: ref,
    models: [{ id: 'restart-fixture', name: 'Synthetic restart fixture', contextWindow: 8000, maxTokens: 1000, input: ['text'] }]
  } }]);
  for (let i = 0; i < 100; i++) { const catalog = await client.listModels(); if (catalog.groups.some(group => group.models.some(model => model.provider === 'restart-fixture'))) break; await delay(20); }
  assert.ok((await discovery()).some(model => model.id === 'restart-fixture')); assert.equal(listings, 1);
  await stop(); await boot();
  const metadata = await client.describeCredentials([ref]); assert.equal(metadata[ref].configured, true); assert.equal(metadata[ref].source, 'file');
  assert.ok((await discovery()).some(model => model.id === 'restart-fixture')); assert.equal(listings, 2, 'Restored key was consumed by the actual provider after process restart');
  assert.deepEqual((await client.listModels()).defaultSelection, baseline);
  const encrypted = await readFile(join(home, '.harmony-provider-credentials.json'), 'utf8'); for (const value of [secret, masterKey, ref]) assert.ok(!encrypted.includes(value));
  await client.clearProviderKey(ref); await stop(); await boot();
  assert.equal((await client.describeCredentials([ref]))[ref].configured, false); await assert.rejects(discovery()); assert.equal(listings, 2);
  assert.deepEqual((await client.listModels()).defaultSelection, baseline); await stop();
  console.log('PASS: real authenticated credentials/set -> encrypted file -> full engine restart -> native-control unlock -> provider discovers with restored synthetic key; unset -> second restart stays absent. No model selection, user sessions or external request.');
} finally {
  client?.close(); if (child?.exitCode === null) { await writeFile(join(home, 'stop'), '').catch(() => {}); await Promise.race([once(child, 'exit'), delay(3000)]); if (child.exitCode === null) child.kill('SIGKILL'); }
  server.closeAllConnections(); if (server.listening) await new Promise(done => server.close(done));
  if (log.includes(secret) || log.includes(masterKey)) throw Error('Credential leaked into runtime diagnostics');
  await rm(root, { recursive: true, force: true });
}
