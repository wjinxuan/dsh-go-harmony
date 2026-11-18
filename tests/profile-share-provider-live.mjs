// Isolated official host; no phone, existing host, credentials, model requests or global selection changes.
import './require-runtime-node.mjs';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdir, mkdtemp, realpath, rm } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { loadDshClient } from './dsh-client-node-fixture.mjs';
import { ProfileShareController } from './profile-share-fixture.mjs';
import { createShareHandler } from '../runtime/share-service.mjs';
import { startTransportControl } from '../runtime/transport-control.mjs';

assert.ok(process.argv[2], 'Usage: node tests/profile-share-provider-live.mjs /path/to/official/dsh/lib/bin.js');
process.umask(0o077);
const bin = resolve(process.argv[2]), project = fileURLToPath(new URL('../', import.meta.url));
const root = await realpath(await mkdtemp('/tmp/dsh-profile-provider-'));
const home = join(root, 'home'), workspace = join(root, 'workspace');
await mkdir(home); await mkdir(workspace);
let child, client, control, launchUrl;
try {
  // Explicit environment avoids inheriting any user provider keys or Node preload options.
  child = spawn(process.execPath, [bin, 'web', '--host', '127.0.0.1', '--port', '0', '--no-open'], {
    cwd: workspace, env: { PATH: process.env.PATH, HOME: home, DSH_HOME: join(root, 'data'),
      XDG_CONFIG_HOME: join(home, 'config'), XDG_CACHE_HOME: join(home, 'cache'),
      XDG_DATA_HOME: join(home, 'data'), TMPDIR: root, NO_COLOR: '1' },
    stdio: ['ignore', 'pipe', 'pipe']
  });
  let pending = '';
  child.stdout.on('data', bytes => {
    pending += bytes.toString(); const lines = pending.split('\n'); pending = lines.pop();
    for (const line of lines) { const match = line.match(/^dsh web: (http:\/\/127\.0\.0\.1:\d+\/\?token=\S+)\s*$/); if (match) launchUrl = match[1]; }
  });
  child.stderr.resume();
  for (let i = 0; !launchUrl && i < 400; i++) { assert.equal(child.exitCode, null, 'Official fixture host exited before ready'); await delay(50); }
  assert.ok(launchUrl, 'Official fixture host did not become ready');
  const Client = await loadDshClient(join(project, 'entry/src/main/ets/dsh/DshClient.ets'), bin, root);
  client = new Client(); await client.connect(launchUrl);
  control = await startTransportControl({ share: createShareHandler(root) });
  const service = { request: async (action, body) => {
    const response = await fetch(control.endpoint.url + '/share/' + action, { method: 'POST',
      headers: { authorization: control.endpoint.authorization, 'content-type': 'application/json' }, body: JSON.stringify(body) });
    assert.equal(response.status, 200); return response.json();
  }, cancel() {} };
  const mutations = [], host = { identity: () => client.connectionIdentity(), settings: () => client.describeSettings(),
    bundles: () => client.listPluginBundles(), presets: () => client.listAgentPresets(), request: (method, body, timeout) => {
      assert.equal(method, 'settings/mutate'); mutations.push(body); return client.request(method, body, timeout);
    } };
  const controller = new ProfileShareController(service, host, false, true);
  const before = await client.describeSettings(), initial = before.namespaces.find(v => v.ns === 'llm-pi-ai');
  assert.ok(initial); const catalog = await client.listModels();
  const name = 'profile-import-owned', model = { id: name, name: 'Isolated profile import', contextWindow: 8000, maxTokens: 1000, input: ['text'] };
  const own = { api: 'openai-completions', baseURL: 'https://example.invalid/v1', models: [model] };
  const payload = { v: 1, kind: 'profile', settings: { 'llm-pi-ai': { providers: { [name]: own } } } };
  assert.equal(initial.value.providers?.[name], undefined);
  await controller.preview(payload);
  const row = controller.plan.changes.find(v => v.id === 'settings:llm-pi-ai');
  assert.equal(row.defaultOn, false); assert.equal(row.sensitive, true); assert.equal(row.ops.length, 3);
  assert.equal(mutations.length, 0);
  await assert.rejects(controller.apply([row.id], false), /确认/);
  assert.equal(mutations.length, 0);
  await controller.apply([row.id], true);
  const after = (await client.describeSettings()).namespaces.find(v => v.ns === 'llm-pi-ai');
  assert.equal(mutations.length, 1);
  assert.deepEqual(after.user.providers[name], own, 'actual saved raw override is exactly the imported provider');
  assert.notDeepEqual(after.value.providers[name].models, own.models, 'official schema really expands the effective models array');
  const remaining = structuredClone(after.value); delete remaining.providers[name];
  assert.deepEqual(remaining, initial.value, 'all other effective provider fields are unchanged');
  assert.deepEqual((await client.listModels()).defaultSelection, catalog.defaultSelection, 'global model selection is unchanged');
  assert.equal(controller.statuses[row.id].state, 'done', controller.statuses[row.id].detail);
  controller.close();
  console.log('PASS official host real authenticated settings RPC: sensitive preview defaults off, cancel has zero mutations, one confirmed provider write, exact persisted override and expanded effective array, controller done, other providers/default unchanged. No model/key/network-provider request.');
} finally {
  client?.close(); await control?.close();
  if (child?.exitCode === null) { child.kill('SIGTERM'); await Promise.race([once(child, 'exit'), delay(5000)]); if (child.exitCode === null) { child.kill('SIGKILL'); await once(child, 'exit'); } }
  await rm(root, { recursive: true, force: true });
}
