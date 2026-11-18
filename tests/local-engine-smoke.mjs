import './require-runtime-node.mjs';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdir, mkdtemp, readFile, realpath, rm, symlink, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { unlockTestCredentials } from './unlock-test-credentials.mjs';

const runtime = resolve(process.argv[2]);
const useDefaultProvider = process.argv.includes('--deepseek');
const denySessionLink = process.argv.includes('--deny-session-link');
const exerciseTools = process.argv.includes('--tools');
const exerciseFullPermission = process.argv.includes('--danger-full-access');
const exerciseCompaction = process.argv.includes('--compact');
// A compiled tests/native/runner.cpp starts the unchanged production embedder,
// including its POSIX flock and publication callbacks. The default host-Node
// path deliberately retains the isolated fixture for ordinary protocol checks.
const nativeRunner = process.env.DSH_LOCAL_ENGINE_TEST_RUNNER
  ? resolve(process.env.DSH_LOCAL_ENGINE_TEST_RUNNER) : undefined;
assert.ok(!exerciseTools || useDefaultProvider, '--tools requires the DeepSeek Messages fixture');
assert.ok(!exerciseFullPermission || exerciseTools, '--danger-full-access requires --tools');
assert.ok(!nativeRunner || !denySessionLink, '--deny-session-link is only available with the simulated publication fixture');
const { WebSocket } = createRequire(join(runtime, 'main.cjs'))('ws');
const data = await mkdtemp(join(tmpdir(), 'dsh-harmony-local-smoke-'));
const child = spawn(nativeRunner ?? process.execPath, nativeRunner
  ? [join(runtime, 'main.cjs'), data]
  : ['--jitless', '--no-addons', '--expose-internals',
  '--require', fileURLToPath(new URL('./local-flock-fixture.cjs', import.meta.url)),
  join(runtime, 'main.cjs'), data], {
  stdio: ['ignore', 'pipe', 'pipe'],
  env: { ...process.env, DSH_HARMONY_TEST_DENY_LINK: denySessionLink ? '1' : '0',
    DSH_HARMONY_TEST_WORKSPACE_LINK: exerciseTools ? '1' : '0' }
});
let diagnostics = '';
child.stderr.on('data', bytes => { diagnostics += bytes.toString(); });
let ws;
let server;
try {
  let ready;
  for (let attempt = 0; attempt < 200 && !ready; attempt++) {
    ready = await readFile(join(data, 'ready.json'), 'utf8').then(JSON.parse, () => undefined);
    if (!ready && child.exitCode !== null) throw new Error(`Local engine exited before ready: ${diagnostics}`);
    if (!ready) await delay(100);
  }
  assert.ok(ready, `Local engine never became ready: ${diagnostics}`);
  const address = new URL(ready.url);
  assert.equal(address.hostname, '127.0.0.1');
  assert.ok(address.searchParams.get('token'));
  assert.equal(ready.workspaceDir, join(data, 'workspace'));
  await unlockTestCredentials(ready);
  if (exerciseTools) {
    await writeFile(join(ready.workspaceDir, 'proof.txt'), 'workspace content');
    await writeFile(join(data, 'outside.txt'), 'forbidden fixture content');
    await symlink(join(data, 'outside.txt'), join(ready.workspaceDir, 'escape.txt'));
    await symlink(data, join(ready.workspaceDir, 'escape-dir'));
    const staging = join(ready.workspaceDir, '.secret.txt.123.8eca91a0-dead-beef-cafe-75832da6ce31.tmpdir');
    await mkdir(staging);
    await writeFile(join(staging, 'secret.txt.tmp'), 'forbidden fixture content');
    await mkdir(join(ready.workspaceDir, '.agents', 'skills', 'sample'), { recursive: true });
    await writeFile(join(ready.workspaceDir, '.agents', 'skills', 'sample', 'SKILL.md'),
      '---\nname: sample\ndescription: A fixture skill.\n---\nHello from the workspace skill.\n');
  }
  const login = await fetch(address, { redirect: 'manual' });
  assert.ok([302, 303].includes(login.status));
  const cookie = login.headers.getSetCookie().find(value => value.startsWith('dsh-auth-')).split(';', 1)[0];
  const rpc = async (method, args, expectedCode) => {
    const rpcId = randomUUID();
    const response = await fetch(`${address.origin}/api/${method}`, { method: 'POST',
      headers: { Cookie: cookie, 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'client-request', rpcId, method, payload: { args } }) });
    assert.equal(response.status, 200, method);
    const envelope = await response.json();
    assert.equal(envelope.rpcId, rpcId);
    if (expectedCode) {
      assert.equal(envelope.result.ok, false, method);
      assert.equal(envelope.result.error.code, expectedCode);
      return;
    }
    assert.equal(envelope.result.ok, true, `${method}: ${JSON.stringify(envelope.result.error)}`);
    return envelope.result.value;
  };
  const muxUrl = address.origin.replace('http', 'ws') + '/api/remote.mux';
  const badOrigin = new WebSocket(muxUrl, { headers: { Cookie: cookie, Origin: 'https://example.invalid' } });
  badOrigin.on('error', () => {});
  const [, refused] = await once(badOrigin, 'unexpected-response');
  assert.equal(refused.statusCode, 403);
  badOrigin.terminate();
  ws = new WebSocket(muxUrl, { headers: { Cookie: cookie, Origin: 'http://127.0.0.1' } });
  const frames = [];
  ws.on('message', data => frames.push(JSON.parse(data.toString())));
  await once(ws, 'open');
  async function next(id) {
    for (let attempt = 0; attempt < 180; attempt++) {
      const index = frames.findIndex(frame => frame.streamId === id);
      if (index >= 0) {
        const [frame] = frames.splice(index, 1);
        assert.equal(frame.type, 'item', JSON.stringify(frame));
        return frame.value;
      }
      await delay(100);
    }
    throw new Error(`Timed out waiting for ${id}`);
  }
  function follow(streamId, endpoint, args) {
    ws.send(JSON.stringify({ type: 'open', streamId, endpoint, payload: { args } }));
  }
  follow('events', '$events', {});
  assert.equal((await next('events')).type, 'ready');
  const reply = 'Harmony local fixture';
  const summary = 'Fixture compaction summary.';
  let providerRequests = 0;
  let parentRequests = 0;
  let summaryRequests = 0;
  const delegatedPrompts = new Set();
  server = createServer(async (request, response) => {
    if (request.method !== 'POST') {
      response.writeHead(404).end();
      return;
    }
    let body = '';
    for await (const part of request) body += part;
    const modelRequest = JSON.parse(body);
    assert.equal(modelRequest.model, useDefaultProvider ? 'deepseek-flash' : 'fixture');
    assert.equal(useDefaultProvider ? request.headers['x-api-key'] : request.headers.authorization,
      useDefaultProvider ? 'synthetic-local-key' : 'Bearer synthetic-local-key');
    const promptTexts = modelRequest.messages.filter(message => message.role === 'user').map(message =>
      Array.isArray(message.content) ? message.content.filter(part => part.type === 'text').map(part => part.text).join(' ')
        : String(message.content));
    const compacting = promptTexts.at(-1)?.includes('You are now acting as a compaction engine');
    const childPrompt = ['subagent fixture task', 'fork fixture task'].find(prompt =>
      promptTexts.some(text => text.includes(prompt)));
    if (compacting) summaryRequests++;
    else if (childPrompt) delegatedPrompts.add(childPrompt);
    else {
      assert.ok(modelRequest.messages.some(message => JSON.stringify(message.content).includes('First local turn')));
      parentRequests++;
    }
    const toolNames = (modelRequest.tools ?? []).map(tool => tool.function?.name ?? tool.name);
    assert.ok(!toolNames.includes('bash') && !toolNames.includes('pwsh'));
    if (exerciseTools) {
      for (const name of ['read', 'write', 'edit', 'skill', 'subagent', 'subagent_fork']) assert.ok(toolNames.includes(name), name);
    }
    providerRequests++;
    const responseText = compacting ? summary : reply;
    response.writeHead(200, { 'Content-Type': 'text/event-stream' });
    if (useDefaultProvider) {
      const calls = exerciseTools && !compacting && !childPrompt && parentRequests === 1 ? [
        ['read-in', 'read', { file_path: 'proof.txt' }],
        ['write-in', 'write', { file_path: 'created.txt', content: 'created' }],
        ['skill-load', 'skill', { name: 'sample' }],
        ['subagent-spawn', 'subagent', { description: 'Fixture child', prompt: 'subagent fixture task' }],
        ['subagent-fork', 'subagent_fork', { description: 'Fixture fork', prompt: 'fork fixture task' }],
        ['read-parent', 'read', { file_path: '../outside.txt' }],
        ['read-absolute', 'read', { file_path: join(data, 'outside.txt') }],
        ['read-symlink', 'read', { file_path: 'escape.txt' }],
        ['read-staging', 'read', { file_path: '.secret.txt.123.8eca91a0-dead-beef-cafe-75832da6ce31.tmpdir/secret.txt.tmp' }],
        ['write-parent', 'write', { file_path: '../outside-new.txt', content: 'must not write' }],
        ['write-absolute', 'write', { file_path: join(data, 'outside.txt'), content: 'must not write' }],
        ['write-staging', 'write', { file_path: 'missing/.secret.txt.123.8eca91a0-dead-beef-cafe-75832da6ce31.tmpdir/secret.txt.tmp', content: 'must not write' }],
        ['write-symlink', 'write', { file_path: 'escape.txt', content: 'must not write' }]
      ] : (exerciseTools && !compacting && !childPrompt && parentRequests === 2 ? [
        ['edit-in', 'edit', { file_path: 'created.txt', old_string: 'created', new_string: 'edited' }]
      ] : []);
      const blocks = calls.length ? calls.flatMap(([id, name, input], index) => [
        { type: 'content_block_start', index, content_block: { type: 'tool_use', id, name, input: {} } },
        { type: 'content_block_delta', index, delta: { type: 'input_json_delta', partial_json: JSON.stringify(input) } },
        { type: 'content_block_stop', index }
      ]) : [
        { type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } },
        { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: responseText } },
        { type: 'content_block_stop', index: 0 }
      ];
      for (const event of [
        { type: 'message_start', message: { id: `fixture-${providerRequests}`, type: 'message', role: 'assistant',
          model: 'deepseek-flash', content: [], usage: { input_tokens: 1, output_tokens: 0 } } },
        ...blocks,
        { type: 'message_delta', delta: { stop_reason: calls.length ? 'tool_use' : 'end_turn' }, usage: { output_tokens: 1 } },
        { type: 'message_stop' }
      ]) response.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
      response.end();
      return;
    }
    for (const [delta, finish_reason] of [[{ role: 'assistant', content: responseText }, null], [{}, 'stop']]) {
      response.write(`data: ${JSON.stringify({ id: 'fixture', object: 'chat.completion.chunk', created: 0,
        model: 'fixture', choices: [{ index: 0, delta, finish_reason }] })}\n\n`);
    }
    response.end('data: [DONE]\n\n');
  });
  await new Promise(done => server.listen(0, '127.0.0.1', done));
  const ref = useDefaultProvider ? 'DEEPSEEK_API_KEY' : 'LOCAL_FIXTURE_KEY';
  await rpc('credentials/set', { ref, value: 'synthetic-local-key' });
  const metadata = await rpc('credentials/describe', { refs: [ref] });
  assert.equal(metadata[ref].configured, true);
  assert.equal(JSON.stringify(metadata).includes('synthetic-local-key'), false);
  const baseURL = `http://127.0.0.1:${server.address().port}/v1`;
  if (useDefaultProvider) {
    await rpc('settings/mutate', { ns: 'llm-deepseek', ops: [{ op: 'set', path: ['baseURL'], value: baseURL }] });
  } else {
    await rpc('settings/mutate', { ns: 'llm-pi-ai', ops: [{ op: 'set', path: ['providers', 'fixture'], value: {
      api: 'openai-completions', baseURL, apiKeyEnv: ref,
      models: [{ id: 'fixture', name: 'Fixture', contextWindow: 8000, maxTokens: 1000, input: ['text'] }]
    } }] });
  }
  const { sessionId } = await rpc('session/create', { request: { cwd: ready.workspaceDir } });
  assert.ok((await rpc('session/list', { _request: {} })).items.some(item => item.sessionId === sessionId));
  if (exerciseCompaction) {
    const commands = await rpc('commands/list', { agentId: sessionId });
    assert.ok(commands.some(command => command.name === 'compact'), 'Local session must advertise /compact');
  }
  if (exerciseFullPermission) {
    const result = await rpc('commands/execute', { agentId: sessionId, line: '/permission danger-full-access', submittedAttachments: [] });
    assert.equal(result.result.kind, 'success');
    assert.equal((await rpc('session/projections', { request: { sessionId } })).values.permissions.currentValue, 'danger-full-access');
  }
  if (exerciseTools) {
    const workspace = await realpath(ready.workspaceDir);
    const skills = await rpc('skills/list', { request: { sessionId } });
    assert.ok(skills.skills.some(skill => skill.name === 'sample'));
    const picker = await rpc('directoryPicker/list', {});
    assert.equal(picker.path, workspace);
    assert.equal(picker.home, workspace);
    assert.deepEqual(picker.crumbs.map(item => item.path), [workspace]);
    assert.equal(picker.entries.some(item => item.name === 'escape-dir' || item.name.endsWith('.tmpdir')), false);
    assert.equal(await rpc('directoryPicker/createDirectory', { path: ready.workspaceDir, name: 'created-dir' }),
      join(workspace, 'created-dir'));
    for (const path of [data, join(ready.workspaceDir, 'escape-dir')]) {
      await rpc('directoryPicker/list', { path }, 'directory-picker/unreadable');
      await rpc('directoryPicker/createDirectory', { path, name: 'must-not-exist' }, 'directory-picker/create-failed');
      await rpc('workspace/create', { request: { path } }, 'workspace/invalid-path');
      await rpc('session/create', { request: { cwd: path } }, 'workspace/invalid-path');
    }
    assert.equal((await rpc('workspace/create', { request: { path: ready.workspaceDir } })).workspace.path, workspace);
    const fallback = await rpc('session/create', { request: {} });
    const sessions = await rpc('session/list', { _request: {} });
    assert.equal(sessions.items.find(item => item.sessionId === fallback.sessionId).cwd, workspace);
    const outside = await fetch(`${address.origin}/api/file?path=${encodeURIComponent(join(data, 'outside.txt'))}`,
      { headers: { Cookie: cookie }, redirect: 'manual' });
    assert.equal(outside.status, 403);
    assert.equal((await outside.text()).includes('forbidden fixture content'), false);
    follow('files', 'workspaceFiles/changes', { workspaceFileScopeId: sessionId, path: '.' });
    assert.equal((await next('files')).kind, 'ready');
    await writeFile(join(data, 'outside.txt'), 'forbidden fixture content updated');
    await delay(200);
    assert.equal(frames.some(frame => frame.streamId === 'files'), false, 'watch must ignore out-of-workspace changes');
    await writeFile(join(data, 'outside.txt'), 'forbidden fixture content');
    await writeFile(join(ready.workspaceDir, 'watch-test.txt'), 'in workspace');
    assert.equal((await next('files')).kind, 'change');
    ws.send(JSON.stringify({ type: 'cancel', streamId: 'files' }));
  }
  if (!useDefaultProvider) {
    await rpc('session/selectModel', { request: { sessionId, provider: 'fixture', model: 'fixture' } });
  }
  follow('chat', 'session/follow', { request: { address: { kind: 'session', sessionId }, assistantStream: true } });
  assert.equal((await next('chat')).type, 'snapshot');
  const historyText = exerciseCompaction ? ' Build a fixture with meaningful history.'.repeat(300) : '';
  await rpc('session/prompt', { request: { requestId: randomUUID(), sessionId, mode: 'queue',
    content: [{ type: 'text', text: 'First local turn' + historyText }] } });
  let streamed = false;
  let committed = false;
  const toolResults = new Map();
  while (true) {
    const item = await next('chat');
    streamed ||= item.type === 'assistant-stream' && item.frame.chunk?.type === 'text-delta' && item.frame.chunk.text === reply;
    if (item.event?.type === 'assistant/message') {
      committed = item.event.data.message.content.some(part => part.type === 'text' && part.text === reply);
    }
    if (item.event?.type === 'tool/result') {
      const message = item.event.data.message;
      toolResults.set(message.toolCallId, message);
    }
    if (item.event?.type === 'turn/end') {
      assert.equal(item.event.data.reason.kind, 'completed', JSON.stringify(item.event.data.reason));
      break;
    }
  }
  assert.equal(streamed && committed, true);
  if (exerciseTools) {
    for (let attempt = 0; attempt < 40 && delegatedPrompts.size < 2; attempt++) await delay(50);
    assert.deepEqual([...delegatedPrompts].sort(), ['fork fixture task', 'subagent fixture task']);
    assert.ok(parentRequests >= 3);
    assert.match(JSON.stringify(toolResults.get('read-in')), /workspace content/);
    assert.match(JSON.stringify(toolResults.get('skill-load')), /Hello from the workspace skill/);
    assert.equal(toolResults.get('subagent-spawn')?.isError, false);
    assert.equal(toolResults.get('subagent-fork')?.isError, false);
    assert.equal(toolResults.get('write-in')?.isError, false);
    assert.equal(toolResults.get('edit-in')?.isError, false);
    for (const id of ['read-parent', 'read-absolute', 'read-symlink', 'read-staging', 'write-parent', 'write-absolute',
      'write-staging', 'write-symlink']) {
      assert.equal(toolResults.get(id)?.isError, true, id);
      assert.equal(JSON.stringify(toolResults.get(id)).includes('forbidden fixture content'), false);
    }
    assert.equal(await readFile(join(ready.workspaceDir, 'created.txt'), 'utf8'), 'edited');
    assert.equal(await readFile(join(data, 'outside.txt'), 'utf8'), 'forbidden fixture content');
    await assert.rejects(readFile(join(data, 'outside-new.txt')), { code: 'ENOENT' });
  } else {
    assert.equal(providerRequests, 1);
  }
  if (exerciseCompaction) {
    const { commandId, result } = await rpc('commands/execute', { agentId: sessionId,
      line: '/compact', submittedAttachments: [] });
    assert.equal(result.kind, 'success', result.text);
    assert.match(result.text, /^Compacted [1-9]\d* history items/);
    assert.equal(summaryRequests, 1);
    const page = await rpc('session/page', { request: { address: { kind: 'session', sessionId }, maxMessages: 50 } });
    const events = page.records.map(record => record.event);
    assert.ok(events.some(event => event.type === 'compaction/summary' && event.data.sourceCommandId === commandId &&
      event.data.summary.some(part => part.type === 'text' && part.text === summary)));
    assert.ok(events.some(event => event.type === 'compaction/end' && event.data.sourceCommandId === commandId &&
      !event.data.error));
  }
  assert.equal(await readFile(join(data, '.credentials.yaml'), 'utf8').then(() => true, () => false), false);
  const encryptedKeys = await readFile(join(data, '.harmony-provider-credentials.json'), 'utf8').catch(error => {
    if (error.code === 'ENOENT') return undefined;
    throw error;
  });
  if (useDefaultProvider) assert.equal(encryptedKeys, undefined, 'Default DeepSeek remember preference remains native-owned');
  else {
    assert.equal(JSON.parse(encryptedKeys).version, 1);
    assert.equal(encryptedKeys.includes('synthetic-local-key'), false);
    assert.equal(encryptedKeys.includes(ref), false);
  }
  ws.close();
  await writeFile(join(data, 'stop'), '');
  const [exit] = await Promise.race([once(child, 'exit'), delay(8000, undefined, { ref: false }).then(() => { throw new Error('Engine did not stop'); })]);
  assert.equal(exit, 0, diagnostics);
  assert.equal(await readFile(join(data, 'ready.json'), 'utf8').then(() => true, () => false), false);
  console.log('DSH local engine verified under --jitless: boot, ' +
    (useDefaultProvider ? 'explicit session-only default key' : 'encrypted generic credentials') + ', one streamed turn, stop' +
    (useDefaultProvider ? ' (default DeepSeek route)' : ' (OpenAI-compatible route)') +
    (exerciseTools ? ', confined read/write/edit, skill load, spawn and fork' : '') +
    (exerciseFullPermission ? ', confinement under danger-full-access' : '') +
    (exerciseCompaction ? ', successful /compact with recorded summary' : '') +
    (nativeRunner ? ', production C++ embedder with real POSIX flock/publication hooks' : ', simulated host flock/publication hooks'));
} finally {
  ws?.terminate();
  server?.closeAllConnections();
  server?.close();
  if (child.exitCode === null) child.kill('SIGKILL');
  await rm(data, { recursive: true, force: true });
}
