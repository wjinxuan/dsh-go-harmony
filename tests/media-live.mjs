import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdir, readFile, realpath, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { loadDshClient } from './dsh-client-node-fixture.mjs';
import { loadMediaModules } from './media-loader.mjs';

const temp = await realpath(resolve(process.argv[2])); const runtime = join(temp, 'runtime'); const home = join(temp, 'home');
const root = fileURLToPath(new URL('../', import.meta.url));
await mkdir(home, { recursive: true });
const { formatMediaHeader, readMediaFile, mediaMeta } = await loadMediaModules();
const DshClient = await loadDshClient(join(root, 'entry/src/main/ets/dsh/DshClient.ets'), join(runtime, 'main.cjs'), temp);
const child = spawn(process.execPath, ['--jitless', '--no-addons', '--expose-internals', '--require',
  join(root, 'tests/local-flock-fixture.cjs'), join(runtime, 'main.cjs'), home], { stdio: 'ignore' });
const client = new DshClient(); let receivedPrompt = ''; let completed = false;
const provider = createServer(async (request, response) => {
  if (request.url === '/models') { response.setHeader('content-type', 'application/json'); response.end(JSON.stringify({ data: [{ id: 'deepseek-flash' }] })); return; }
  let body = ''; for await (const chunk of request) body += chunk;
  const payload = JSON.parse(body); const latest = payload.messages.findLast(m => m.role === 'user');
  receivedPrompt = typeof latest.content === 'string' ? latest.content : latest.content.find(p => p.type === 'text')?.text;
  response.setHeader('content-type', 'text/event-stream');
  const text = 'Synthetic media fixture acknowledged; no provider generation was performed.';
  for (const event of [
    { type: 'message_start', message: { id: 'media-fixture', type: 'message', role: 'assistant', model: 'deepseek-flash', content: [], usage: { input_tokens: 1, output_tokens: 0 } } },
    { type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } },
    { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text } },
    { type: 'content_block_stop', index: 0 },
    { type: 'message_delta', delta: { stop_reason: 'end_turn' }, usage: { output_tokens: 1 } }, { type: 'message_stop' }
  ]) response.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
  response.end();
});
await new Promise(ok => provider.listen(0, '127.0.0.1', ok));
try {
  let ready;
  for (let attempt = 0; attempt < 200 && !ready; attempt++) {
    ready = await readFile(join(home, 'ready.json'), 'utf8').then(JSON.parse, () => undefined);
    if (child.exitCode !== null) throw Error('Media fixture engine exited before ready');
    if (!ready) await delay(50);
  }
  assert.ok(ready, 'packed DSH engine started'); await client.connect(ready.url, undefined, true);
  const session = await client.createSession(undefined, ready.workspaceDir);
  const picture = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jMioAAAAASUVORK5CYII=', 'base64');
  const path = join(ready.workspaceDir, 'synthetic-generated-fixture.png'); await writeFile(path, picture);
  const chunks = []; const count = await readMediaFile(client, session, path, 20 * 1024 * 1024, async bytes => chunks.push(Buffer.from(bytes)), () => true);
  assert.equal(count, picture.length); assert.deepEqual(Buffer.concat(chunks), picture);
  await assert.rejects(readMediaFile(client, session, path, 1, async () => assert.fail('oversized bytes delivered'), () => true), /大小限制/);
  const outside = join(home, 'outside-workspace.png'); await writeFile(outside, picture);
  await assert.rejects(readMediaFile(client, session, outside, 1024, async () => assert.fail('private bytes delivered'), () => true));
  const settings = (await client.describeSettings()).namespaces.find(ns => ns.ns === 'llm-deepseek');
  await client.setProviderKey('synthetic-media-fixture-key', 'DEEPSEEK_API_KEY');
  await client.updateSettings(settings.ns, { baseURL: `http://127.0.0.1:${provider.address().port}/v1` }, settings.revision);
  const model = (await client.listModels()).groups.flatMap(group => group.models).find(model => model.id === 'deepseek-flash');
  assert.ok(model); await client.setModel(session, model.provider, model.id, model.defaultEffort);
  await client.watchSession(session, update => { completed = !update.running && update.messages.some(m => m.role === 'assistant' && m.text.includes('Synthetic media fixture')); });
  const prompt = formatMediaHeader({ kind: 'image', prompt: 'Synthetic fixture only', n: 2, aspect: '1:1', model: { label: 'Fixture Image', serviceId: 'fixture', id: 'fixture-image' } });
  await client.prompt(session, prompt, 'media-fixture-request');
  for (let attempt = 0; attempt < 200 && !completed; attempt++) await delay(50);
  assert.equal(receivedPrompt, prompt); assert.equal(completed, true);
  const result = mediaMeta({ 'dsh-go/media': { v: 1, kind: 'image', status: 'done', prompt: 'Synthetic fixture only', items: [{ path, mime: 'image/png', bytes: picture.length }] } });
  assert.equal(result.items[0].path, path);
  console.log('PASS: packaged DSH authenticated media bytes, size limit, private-path denial and generation-header prompt round-trip (synthetic provider; no paid media generation).');
} finally {
  client.close(); provider.closeAllConnections(); await new Promise(ok => provider.close(ok));
  await writeFile(join(home, 'stop'), '');
  await Promise.race([once(child, 'exit'), delay(5000)]); if (child.exitCode === null) child.kill('SIGKILL');
}
