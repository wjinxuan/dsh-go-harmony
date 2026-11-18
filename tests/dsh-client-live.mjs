import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { createRequire, stripTypeScriptTypes } from 'node:module';
import { join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { loadDshClient } from './dsh-client-node-fixture.mjs';

const [clientPath, runtime, lockFixture] = process.argv.slice(2).map(path => resolve(path));
const runtimeRequire = createRequire(join(runtime, 'main.cjs'));
const { unzipSync, strFromU8 } = runtimeRequire('fflate');
const { PNG } = createRequire(join(runtime, 'harmony-deps/package.json'))('pngjs');
const testDir = new URL('.', import.meta.url);
const deviceInfo = { sdkApiVersion: 26 };
const socketOptions = [];
const proxyOptions = [];
const fixtures = { deviceInfo, socketOptions, proxyOptions };
const DshClient = await loadDshClient(clientPath, join(runtime, 'main.cjs'), fileURLToPath(testDir), fixtures);
const regenerationCode = (await readFile(resolve(clientPath, '../../ui/MessageRegeneration.ets'), 'utf8'))
  .replace(/^import type .*\n/gm, '').replace("'../dsh/DshWire'", JSON.stringify(new URL('./DshWire.ts', testDir).href));
const { forkBeforePrompt, regenerablePrompt } = await import('data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(regenerationCode)));

const home = await mkdtemp('/tmp/dsh-client-live-');
const child = spawn(process.execPath, ['--jitless', '--no-addons', '--expose-internals', '--require', lockFixture,
  join(runtime, 'main.cjs'), home],
  { stdio: 'ignore', env: { ...process.env, DSH_HARMONY_TEST_ATTACHMENT_LINK: '1' } });
const client = new DshClient();
let heldRequest = Promise.withResolvers();
let releaseRequest = Promise.withResolvers();
const releaseCompaction = Promise.withResolvers();
const toolAttempts = new Set();
let toolNames = new Set();
let timedAsk = false;
let imageReachedProvider = false;
let attachmentHostPath = '';
const privateProviderError = 'fixture-private-provider-error with a local path';
const provider = createServer(async (request, response) => {
  if (request.url === '/models') {
    response.setHeader('content-type', 'application/json');
    response.end(JSON.stringify({ data: [{ id: 'deepseek-flash', name: 'Fixture model' },
      { id: 'deepseek-v4-pro', name: 'Fixture text model' }] }));
    return;
  }
  let body = '';
  for await (const chunk of request) body += chunk;
  if (request.url === '/v1/files' && request.method === 'POST') {
    response.writeHead(404, { 'content-type': 'application/json' });
    response.end(JSON.stringify({ error: { code: 'not_found', message: 'No Files API in this fixture' } }));
    return;
  }
  const payload = JSON.parse(body);
  toolNames = new Set(payload.tools?.map(tool => tool.name));
  timedAsk = !!payload.tools?.find(tool => tool.name === 'ask_user_question')?.input_schema.properties.timeout;
  if (body.includes('hold-first-turn') && heldRequest) {
    heldRequest.resolve();
    heldRequest = undefined;
    await releaseRequest.promise;
  }
  const lastUser = payload.messages.findLast(message => message.role === 'user');
  const prompt = typeof lastUser?.content === 'string' ? lastUser.content :
    lastUser?.content.find(part => part.type === 'text')?.text;
  if (Array.isArray(lastUser?.content) && lastUser.content.some(part => part.type === 'image')) imageReachedProvider = true;
  if (body.includes('You are now acting as a compaction engine')) {
    await releaseCompaction.promise;
  }
  const failurePrompt = payload.messages.filter(message => message.role === 'user').flatMap(message =>
    typeof message.content === 'string' ? [message.content] :
      message.content.filter(part => part.type === 'text').map(part => part.text))
    .findLast(text => /^fixture-(?:auth-failure|request-failure|success-after-failure)$/.test(text));
  if (failurePrompt === 'fixture-auth-failure' || failurePrompt === 'fixture-request-failure') {
    const isAuth = failurePrompt === 'fixture-auth-failure';
    response.writeHead(isAuth ? 401 : 400, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify({ type: 'error', error: {
      type: isAuth ? 'authentication_error' : 'invalid_request_error', message: privateProviderError
    } }));
    return;
  }
  let tool;
  if (prompt === 'fixture-read-attachment') {
    const match = body.replaceAll('\\\\', '/').match(/\/[^"\\\s]*\/attachments\/v1\/files\/[a-f0-9]{2}\/[a-f0-9]{64}\/fixture-attachment\.txt/);
    if (match) attachmentHostPath = match[0];
    if (attachmentHostPath) {
      tool = { name: 'read', args: { file_path: attachmentHostPath } };
    }
  } else if (prompt === 'fixture-read-other-session' && attachmentHostPath) {
    tool = { name: 'read', args: { file_path: attachmentHostPath } };
  } else if (prompt === 'fixture-todo' && toolNames.has('todo_write')) {
    tool = { name: 'todo_write', args: { todos: [{ content: 'fixture todo item', status: 'in_progress' }] } };
  } else if (['fixture-ask-answer', 'fixture-ask-reject', 'fixture-ask-timeout'].includes(prompt) &&
    toolNames.has('ask_user_question')) {
    tool = { name: 'ask_user_question', args: { questions: [{ id: 'choice', question: 'Which fixture?',
      options: [{ label: 'A' }, { label: 'B' }] }], ...(timedAsk ? { timeout: prompt === 'fixture-ask-timeout' ? 1 : 20 } : {}) } };
  }
  if (toolAttempts.has(prompt)) tool = undefined;
  if (tool) toolAttempts.add(prompt);
  const blocks = tool ? [
    { type: 'content_block_start', index: 0, content_block: { type: 'tool_use', id: `call-${prompt}`, name: tool.name, input: {} } },
    { type: 'content_block_delta', index: 0, delta: { type: 'input_json_delta', partial_json: JSON.stringify(tool.args) } }
  ] : [
    { type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } },
    { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: 'fixture reply' } }
  ];
  response.writeHead(200, { 'Content-Type': 'text/event-stream' });
  for (const event of [
    { type: 'message_start', message: { id: 'fixture', type: 'message', role: 'assistant', model: 'deepseek-flash',
      content: [], usage: { input_tokens: 1, output_tokens: 0 } } },
    ...blocks,
    { type: 'content_block_stop', index: 0 },
    { type: 'message_delta', delta: { stop_reason: tool ? 'tool_use' : 'end_turn' }, usage: { output_tokens: 1 } },
    { type: 'message_stop' }
  ]) response.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
  response.end();
});
await new Promise(resolve => provider.listen(0, '127.0.0.1', resolve));
const baseURL = `http://127.0.0.1:${provider.address().port}/v1`;
let checks = 0;
const equal = (actual, expected) => { assert.deepEqual(actual, expected); checks++; };
const ok = value => { assert.ok(value); checks++; };
const eventually = async (predicate, name) => {
  for (let attempt = 0; attempt < 150; attempt++) {
    if (predicate()) return;
    await delay(40);
  }
  throw new Error(`No host update: ${name}`);
};

try {
  let ready;
  for (let attempt = 0; attempt < 150 && !ready; attempt++) {
    ready = await readFile(join(home, 'ready.json'), 'utf8').then(JSON.parse, () => undefined);
    if (!ready && child.exitCode !== null) throw new Error('Fixture engine exited before ready');
    if (!ready) await delay(50);
  }
  ok(ready);
  const workspacePath = await realpath(ready.workspaceDir);
  const remoteLoopback = new DshClient();
  try {
    await remoteLoopback.connect(ready.url);
    ok(Array.isArray(await remoteLoopback.listSessions()));
    equal(socketOptions.at(-1).supportOriginPort, true);
    equal(socketOptions.at(-1).proxy, 'no-proxy');
    equal(proxyOptions.slice(-2), ['no-proxy', 'no-proxy']);
  } finally {
    remoteLoopback.close();
  }
  deviceInfo.sdkApiVersion = 25;
  await client.connect(ready.url, undefined, true);
  ok(/^http:\/\/127\.0\.0\.1:\d+$/.test(client.localAccountCallbackOrigin()));
  equal(socketOptions.at(-1).supportOriginPort, undefined);
  equal(socketOptions.at(-1).proxy, 'no-proxy');
  deviceInfo.sdkApiVersion = 26;
  ok(client.connectionIdentity() > 0);
  equal(await client.sessionDeletionAvailable(), true);
  await assert.rejects(client.deleteSessionPermanently('isolated-nonexistent-session'), /not-found/);
  checks++;
  await client.watchWorkspaces(() => {});
  await writeFile(join(workspacePath, 'proof.txt'), 'hello\nworld\n');
  equal((await client.listDirectory(workspacePath)).path, workspacePath);
  const workspace = await client.createWorkspace(workspacePath);
  ok(workspace.id);
  equal((await client.renameWorkspace(workspace.id, 'Fixture workspace')).title, 'Fixture workspace');
  const session = await client.createSession(workspace.id);
  await client.watchSession(session, () => {});
  equal(await client.renameSession(session, 'Fixture session'), 'Fixture session');
  ok((await client.pinSession(session)).includes(session));
  ok((await client.listSessions()).some(item => item.id === session && item.pinned));
  ok(!(await client.pinSession(session, false)).includes(session));
  ok((await client.archiveSession(session)).includes(session));
  ok(!(await client.listSessions()).some(item => item.id === session));
  ok((await client.listSessions(true)).some(item => item.id === session && item.archived));
  ok(!(await client.restoreSession(session)).includes(session));
  ok((await client.listWorkspace(session)).entries.some(entry => entry.name === 'proof.txt' && entry.type === 'file'));
  equal((await client.readWorkspaceText(session, 'proof.txt', 2, 1)).text, 'world');

  const ref = 'DEEPSEEK_API_KEY';
  await client.setProviderKey('synthetic-local-key');
  equal((await client.describeCredentials([ref]))[ref].configured, true);
  ok((await client.listProviders()).some(item => item.id === 'deepseek-official'));
  await client.mutateSettings('llm-deepseek', [{ op: 'set', path: ['baseURL'], value: baseURL }]);
  const catalog = await client.listModels();
  const model = catalog.groups.find(group => group.id === 'deepseek-official')?.models.find(item => item.id === 'deepseek-flash');
  ok(model);
  equal((await client.setModel(session, model.provider, model.id, model.defaultEffort)).selected.model, model.id);
  let completed = false;
  let chat;
  await client.watchSession(session, update => {
    chat = update;
    completed = !update.running && update.messages.some(message => message.role === 'assistant' && message.text === 'fixture reply');
  });
  await client.prompt(session, 'Fixture turn');
  for (let attempt = 0; attempt < 100 && !completed; attempt++) await delay(50);
  ok(completed);
  const archivePath = join(home, 'session-export.zip');
  await client.exportSessionLog(session, archivePath);
  const archive = await readFile(archivePath);
  equal(archive.subarray(0, 4).toString('hex'), '504b0304');
  const archiveEntries = unzipSync(archive);
  ok(strFromU8(archiveEntries['session.v4.jsonl']).includes('Fixture turn'));
  await assert.rejects(client.exportSessionLog(session, archivePath), /已存在/);
  equal(await readFile(archivePath), archive);

  const badPath = join(home, 'invalid-export.zip');
  fixtures.exportRequest = async request => {
    assert.equal(request.method, 'GET');
    assert.equal(new URL(request.uri).searchParams.get('sessionId'), 'fixture+encoded & session');
    assert.equal(new URL(request.uri).searchParams.get('includeDescendants'), 'true');
    assert.ok(request.headers.cookie?.startsWith('dsh-auth-'));
    assert.equal(request.configuration.transfer.autoRedirect, false);
    assert.equal(request.configuration.transfer.timeout.transferMs, 300000);
    await writeFile(request.destination.file, 'not a zip');
    return { statusCode: 200, headers: { 'content-type': 'application/zip' } };
  };
  await assert.rejects(client.exportSessionLog('fixture+encoded & session', badPath), /ZIP/);
  await assert.rejects(readFile(badPath), { code: 'ENOENT' });
  fixtures.exportRequest = async request => {
    await writeFile(request.destination.file, archive);
    return { statusCode: 200, headers: { 'content-type': 'text/html' } };
  };
  await assert.rejects(client.exportSessionLog(session, badPath), /ZIP/);
  await assert.rejects(readFile(badPath), { code: 'ENOENT' });
  fixtures.exportRequest = async request => {
    await writeFile(request.destination.file, 'private error text');
    return { statusCode: 500, headers: { 'content-type': 'text/plain' } };
  };
  await assert.rejects(client.exportSessionLog(session, badPath), /^(?!.*private error text).*HTTP 500/);
  await assert.rejects(readFile(badPath), { code: 'ENOENT' });
  const started = Promise.withResolvers();
  let cancelExport;
  fixtures.exportRequest = async request => {
    await writeFile(request.destination.file, archive.subarray(0, 16));
    const cancelled = once(request.cancelled.signal, 'abort');
    started.resolve();
    await cancelled;
    throw new Error('fixture cancelled');
  };
  const cancelledExport = client.exportSessionLog(session, badPath, cancel => { cancelExport = cancel; });
  await started.promise;
  cancelExport();
  await assert.rejects(cancelledExport, /取消/);
  await assert.rejects(readFile(badPath), { code: 'ENOENT' });
  fixtures.exportRequest = undefined;
  checks += 4;
  try {
    const hits = await client.searchSessions('Fixture');
    ok(hits.items.some(item => item.sessionId === session && item.snippet.includes('Fixture')));
  } catch (error) {
    equal(error.message, '这台主机仅支持按标题搜索');
  }
  const detail = await client.sessionDetail(session);
  ok(detail.projections && detail.history.records.some(event => event.type === 'assistant/message'));
  ok(detail.turns.some(turn => turn.reason === 'completed' && turn.spans.some(span => span.kind === 'model')));
  equal(detail.projections.agentPreset, 'standard');
  if (detail.projections.permissionPreset) {
    const permissions = await client.permissionPresets();
    for (const preset of ['read-only', 'danger-full-access', 'workspace-write']) {
      ok(permissions.options.some(option => option.value === preset));
      await client.setPermissionPreset(session, preset);
      equal((await client.sessionProjections(session)).permissionPreset, preset);
      await eventually(() => chat?.projections?.permissionPreset === preset, 'live permission');
    }
    const { default: WorkspaceShellPolicy } = await import(pathToFileURL(join(runtime, 'workspace-shell-policy.mjs')));
    assert.throws(() => WorkspaceShellPolicy.prototype.resolve(), /Shell execution is unavailable/);
    assert.throws(() => WorkspaceShellPolicy.prototype.execute(), /Shell execution is unavailable/);
    ok(!toolNames.has('bash') && !toolNames.has('pwsh'));
  } else {
    await assert.rejects(client.permissionPresets(), /不支持/);
    checks++;
  }
  if (detail.goalSupported) {
    equal(await client.readGoal(session), null);
    const ref = await client.createGoal(session, 'Fixture goal');
    const paused = await client.pauseGoal(session, ref);
    equal(paused.phase, 'paused');
    const edited = await client.editGoal(session, paused, 'Updated fixture goal');
    equal(edited.objective, 'Updated fixture goal');
    const resumed = await client.resumeGoal(session, edited);
    equal(resumed.phase, 'active');
    const done = await client.completeGoal(session, resumed);
    equal(done.phase, 'complete');
    ok((await client.clearGoal(session, done)).revision > done.revision);
  } else {
    await assert.rejects(client.readGoal(session), /不支持/);
    checks++;
  }
  const held = heldRequest.promise;
  await client.prompt(session, 'hold-first-turn');
  await Promise.race([held, delay(6000, undefined, { ref: false }).then(() => { throw new Error('Provider not held'); })]);
  await client.prompt(session, 'first queued');
  await client.prompt(session, 'second queued');
  await client.prompt(session, 'withdraw this');
  await eventually(() => chat?.queue?.length === 3, 'queued prompts');
  const [first, second, withdrawn] = chat.queue;
  equal(first.hasAttachments, false);
  await client.updateQueue(session, withdrawn.id, 'remove');
  await client.updateQueue(session, first.id, 'edit', 'edited queued');
  await eventually(() => chat?.queue?.some(item => item.text === 'edited queued') && chat.queue.length === 2, 'edit and remove');
  const move = await client.sendQueuedNow(session, first.id);
  equal(move, { sent: true, recoverable: [] });
  releaseRequest.resolve();
  await eventually(() => !chat.running && chat.messages.some(item => item.text === second.text), 'ordered queue replay');
  const delivered = chat.messages.filter(item => item.role === 'user').map(item => item.text);
  ok(delivered.indexOf('edited queued') >= 0 && delivered.indexOf('edited queued') < delivered.indexOf(second.text));
  ok(!delivered.includes(withdrawn.text));
  if (toolNames.has('todo_write')) {
    await client.prompt(session, 'fixture-todo');
    await eventually(() => !chat.running && chat.todos?.[0]?.content === 'fixture todo item', 'todo write');
    equal((await client.sessionDetail(session)).todos?.[0]?.status, 'in_progress');
  }
  if (toolNames.has('ask_user_question')) {
    const answers = [{ id: 'choice', selected: ['A'] }];
    await client.prompt(session, 'fixture-ask-answer');
    await eventually(() => chat.questions?.[0]?.questions[0]?.id === 'choice' &&
      (!timedAsk || chat.questions[0].remainingMs >= 0), 'open question');
    await client.answerQuestion(chat.questions[0], answers);
    await eventually(() => !chat.running && chat.tools?.some(item =>
      item.callId === 'call-fixture-ask-answer' && item.result?.includes('"selected":["A"]')), 'answered tool');
    equal(chat.questions?.length, 0);
    await client.prompt(session, 'fixture-ask-reject');
    await eventually(() => chat.questions?.[0]?.questions[0]?.id === 'choice', 'question to reject');
    await client.rejectQuestion(chat.questions[0]);
    await eventually(() => !chat.running && chat.tools?.some(item =>
      item.callId === 'call-fixture-ask-reject' && item.isError === true), 'rejected tool');
    equal(chat.questions?.length, 0);
    if (timedAsk) {
      await client.prompt(session, 'fixture-ask-timeout');
      await eventually(() => chat.questions?.[0]?.continued === true, 'continued timed question');
      await client.answerQuestion(chat.questions[0], answers);
      await eventually(() => !chat.running && chat.questions?.length === 0, 'continued question answered');
      ok((await client.sessionPage(session)).records.some(event => event.type === 'user/message' &&
        event.data.source?.kind === 'user-question-reply'));
    }
  }
  const failedSession = await client.createSession(workspace.id);
  await client.setModel(failedSession, model.provider, model.id, model.defaultEffort);
  const failureUpdates = [];
  let failedChat;
  await client.watchSession(failedSession, update => { failedChat = update; failureUpdates.push(update); });
  await client.prompt(failedSession, 'fixture-auth-failure');
  await eventually(() => !failedChat.running && failedChat.notices.at(-1)?.actionable, 'failed authentication turn');
  equal(failedChat.notices.at(-1).code, 'AUTH');
  equal(failedChat.notices.at(-1).text, 'API Key 无效或已过期');
  equal(failedChat.notices.at(-1).recovery, undefined);
  equal(failedChat.sessionError, undefined);
  await client.prompt(failedSession, 'fixture-request-failure');
  await eventually(() => !failedChat.running && failedChat.notices.at(-1)?.retryText === 'fixture-request-failure',
    'failed request retained its own prompt');
  equal(failedChat.notices.at(-1).text, '本轮出错了');
  equal(failedChat.notices.at(-1).recovery, 'retry');
  equal(failedChat.notices.at(-2).actionable, undefined);
  ok(!failureUpdates.some(update => JSON.stringify(update).includes(privateProviderError)));
  await client.watchSession(failedSession, update => { failedChat = update; });
  equal(failedChat.notices.length, 2);
  equal(failedChat.notices.at(-1).retryText, 'fixture-request-failure');
  equal(failedChat.sessionError, undefined);
  await client.prompt(failedSession, 'fixture-success-after-failure');
  await eventually(() => !failedChat.running && failedChat.messages.at(-1)?.text === 'fixture reply',
    'successful turn after prior failure');
  equal(failedChat.notices.length, 2);
  ok(failedChat.notices.every(item => !item.actionable));
  equal(failedChat.sessionError, undefined);

  const compactSession = await client.createSession(workspace.id);
  await client.setModel(compactSession, model.provider, model.id, model.defaultEffort);
  const commands = await client.listCommands(compactSession);
  equal(commands.find(command => command.name === 'compact')?.label, '压缩');
  let commandChat;
  await client.watchSession(compactSession, update => { commandChat = update; });
  equal((await client.executeCommand(compactSession, '/compact')).text, '暂无可压缩的对话内容');
  equal((await client.executeCommand(compactSession, '/compact extra')).success, false);
  equal((await client.executeCommand(compactSession, '/missing-fixture-command')).id, undefined);
  ok(commandChat.commands.some(command => command.name === 'missing-fixture-command' && command.seq === undefined));
  await client.prompt(compactSession, 'Build a fixture with meaningful history. '.repeat(300));
  await eventually(() => !commandChat.running && commandChat.messages.at(-1)?.role === 'assistant', 'history for compaction');
  const compaction = client.executeCommand(compactSession, '/compact');
  try {
    await Promise.race([eventually(() => commandChat.compacting && commandChat.commands.some(command =>
      command.name === 'compact' && !command.done), 'live compaction'), compaction.then(result => {
      throw new Error(`Compaction completed before streaming: ${result.text}`);
    })]);
  } finally {
    releaseCompaction.resolve();
  }
  const compactResult = await compaction;
  ok(compactResult.success && /^已压缩 \d+ 条历史记录/.test(compactResult.text));
  await eventually(() => !commandChat.compacting && commandChat.commands.some(command =>
    command.id === compactResult.id && command.done && command.seq !== undefined), 'durable command result');
  equal(commandChat.commands.filter(command => command.id === compactResult.id).length, 1);
  const commandPage = await client.sessionPage(compactSession);
  ok(commandPage.records.some(event => event.type === 'compaction/summary' &&
    event.data.sourceCommandId === compactResult.id && event.data.shadowedSeqs.length > 0));
  await client.watchSession(compactSession, update => { commandChat = update; });
  ok(commandChat.commands.some(command => command.id === compactResult.id && command.done && command.success));

  const attachmentSession = await client.createSession(workspace.id);
  await client.setModel(attachmentSession, model.provider, model.id, model.defaultEffort);
  let attachmentChat;
  await client.watchSession(attachmentSession, update => { attachmentChat = update; });
  const attachmentText = 'document line verified by the model tool';
  const documentPath = join(home, 'selected-document');
  await writeFile(documentPath, attachmentText);
  const document = { id: 'document', path: documentPath, name: 'fixture-attachment.txt', size: Buffer.byteLength(attachmentText) };
  const documentPrompt = 'fixture-read-attachment';
  const documentRequest = 'fixture-attachment-1';
  heldRequest = Promise.withResolvers();
  releaseRequest = Promise.withResolvers();
  await client.prompt(attachmentSession, 'hold-first-turn');
  await eventually(() => !heldRequest && attachmentChat.running, 'attachment session turn held');
  equal(await client.promptWithAttachments(attachmentSession, documentPrompt, [document], documentRequest, () => true, true), false);
  await eventually(() => attachmentChat.queue?.some(item => item.text === documentPrompt), 'attachment enters queue');
  const queuedDocument = attachmentChat.queue.find(item => item.text === documentPrompt);
  equal(queuedDocument.requestId, documentRequest);
  equal(queuedDocument.hasAttachments, true);
  await client.updateQueue(attachmentSession, queuedDocument.id, 'remove');
  await eventually(() => !attachmentChat.queue.some(item => item.id === queuedDocument.id), 'attachment leaves queue');
  ok(!attachmentChat.messages.some(item => item.text === documentPrompt));
  equal(await client.promptWithAttachments(attachmentSession, documentPrompt, [document], documentRequest, () => true, true), false);
  await eventually(() => attachmentChat.queue?.some(item => item.requestId === documentRequest && item.id !== queuedDocument.id),
    'restaged attachment enters queue');
  releaseRequest.resolve();
  await eventually(() => !attachmentChat.running && attachmentChat.tools.some(tool => tool.result?.includes(attachmentText)),
    'model reads the restaged document and completes its turn');
  const committedDocuments = attachmentChat.messages.filter(message => message.role === 'user' && message.text === documentPrompt);
  equal(committedDocuments.map(message => message.requestId), [documentRequest]);
  const documentPart = committedDocuments[0].content.find(part => part.type === 'file');
  equal(documentPart.attachment.name, document.name);
  equal(documentPart.attachment.bytes, document.size);
  equal(documentPart.attachment.attachmentId, `sha256:${createHash('sha256').update(attachmentText).digest('hex')}`);
  equal(await readFile(attachmentHostPath, 'utf8'), attachmentText);
  heldRequest = Promise.withResolvers();
  releaseRequest = Promise.withResolvers();
  await client.prompt(attachmentSession, 'hold-first-turn');
  await eventually(() => !heldRequest && attachmentChat.running, 'hold for immediate attachment send');
  const immediateRequest = 'fixture-attachment-now';
  await client.promptWithAttachments(attachmentSession, documentPrompt, [document], immediateRequest, () => true, true);
  await client.prompt(attachmentSession, 'after immediate attachment');
  await eventually(() => attachmentChat.queue?.length === 2, 'attachment followed by text queued');
  const immediate = attachmentChat.queue.find(item => item.requestId === immediateRequest);
  const immediateResult = await client.sendQueuedNow(attachmentSession, immediate.id,
    requestId => requestId === immediateRequest ? [document] : []);
  equal(immediateResult, { sent: true, recoverable: [] });
  releaseRequest.resolve();
  await eventually(() => !attachmentChat.running && attachmentChat.messages.some(message =>
    message.role === 'user' && message.text === 'after immediate attachment'), 'immediate attachment and follower complete');
  const immediateMessages = attachmentChat.messages.filter(message => message.role === 'user');
  equal(immediateMessages.filter(message => message.requestId === immediateRequest).length, 1);
  const immediateIndex = immediateMessages.findIndex(message => message.requestId === immediateRequest);
  ok(immediateIndex < immediateMessages.findIndex(message => message.text === 'after immediate attachment'));
  equal(immediateMessages[immediateIndex].content.find(part => part.type === 'file').attachment.attachmentId,
    documentPart.attachment.attachmentId);
  const imagePath = join(home, 'selected-image');
  const pixel = PNG.sync.write({ width: 1, height: 1, data: Buffer.from([237, 42, 39, 220]) });
  await writeFile(imagePath, pixel);
  const picture = { id: 'image', path: imagePath, name: 'fixture-image.png', size: pixel.length, mediaType: 'image/png' };
  equal(await client.promptWithAttachments(attachmentSession, '', [picture], 'fixture-attachment-2', () => true, true), false);
  await eventually(() => !attachmentChat.running && imageReachedProvider, 'vision provider receives attachment-only prompt');
  await client.watchSession(attachmentSession, update => { attachmentChat = update; });
  equal(attachmentChat.messages.find(message => message.text === documentPrompt)?.requestId, documentRequest);
  const imagePart = attachmentChat.messages.find(message => message.content?.some(part => part.type === 'image'))?.content
    .find(part => part.type === 'image');
  equal([...PNG.sync.read(Buffer.from(await client.readSessionImage(attachmentSession, imagePart.attachment))).data], [237, 42, 39, 220]);
  await assert.rejects(client.readSessionImage(attachmentSession, imagePart.attachment, cancel => cancel()), /通信失败/);
  checks++;
  let requestedWhileHidden = false;
  await assert.rejects(client.readSessionImage(attachmentSession, imagePart.attachment,
    () => { requestedWhileHidden = true; }, () => false), /取消/);
  equal(requestedWhileHidden, false);

  const originalReply = attachmentChat.messages.at(-1);
  const originalImagePrompt = regenerablePrompt(attachmentChat.messages, attachmentChat.records, originalReply, false, 0);
  ok(originalImagePrompt?.content.some(part => part.type === 'image'));
  const regenerated = await forkBeforePrompt(client, attachmentSession, originalImagePrompt.seq,
    attachmentChat.records, 'fixture attachment', () => true);
  ok(regenerated?.sessionId && regenerated.sessionId !== attachmentSession);
  let regeneratedChat;
  await client.watchSession(regenerated.sessionId, update => { regeneratedChat = update; });
  ok(!regeneratedChat.messages.some(message => message.id === originalImagePrompt.id || message.id === originalReply.id));
  ok(regeneratedChat.messages.some(message => message.text === documentPrompt));
  equal(regeneratedChat.queue.length, 0);
  imageReachedProvider = false;
  equal(await client.promptWithAttachments(regenerated.sessionId, originalImagePrompt.text,
    [picture], 'fixture-regenerated-image', () => true, true), false);
  await eventually(() => !regeneratedChat.running && imageReachedProvider && regeneratedChat.messages.some(message =>
    message.role === 'assistant'), 'regenerated branch receives original image-only prompt');
  equal(regeneratedChat.messages.filter(message => message.requestId === 'fixture-regenerated-image').length, 1);
  await client.watchSession(attachmentSession, update => { attachmentChat = update; });
  equal(attachmentChat.messages.at(-1).id, originalReply.id);

  const otherAttachmentSession = await client.createSession(workspace.id);
  await assert.rejects(client.readSessionImage(otherAttachmentSession, imagePart.attachment), /session\/attachment-invalid/);
  checks++;
  await client.setModel(otherAttachmentSession, model.provider, model.id, model.defaultEffort);
  await client.watchSession(otherAttachmentSession, update => { attachmentChat = update; });
  await client.prompt(otherAttachmentSession, 'fixture-read-other-session');
  await eventually(() => !attachmentChat.running && attachmentChat.tools.some(tool => tool.isError), 'unowned attachment denied');
  ok(!attachmentChat.tools.some(tool => tool.result?.includes(attachmentText)));
  const textModel = catalog.groups.find(group => group.id === 'deepseek-official')?.models.find(item => item.id === 'deepseek-v4-pro');
  ok(textModel);
  await client.setModel(otherAttachmentSession, textModel.provider, textModel.id, textModel.defaultEffort);
  equal(await client.promptWithAttachments(otherAttachmentSession, '', [picture], 'fixture-image-fallback', () => true, true), true);
  await eventually(() => attachmentChat.messages.some(message => message.content?.some(part =>
    part.type === 'file' && part.attachment?.name === picture.name)), 'image fallback becomes a durable file attachment');

  const fork = await client.forkSession(session);
  ok(fork !== session);
  ok((await client.listSessions(true)).some(item => item.id === fork));
  await client.clearProviderKey();
  equal((await client.describeCredentials([ref]))[ref].configured, false);

  const settings = (await client.describeSettings()).namespaces.find(item => item.ns === 'llm-deepseek');
  ok(settings);
  const mutated = await client.mutateSettings(settings.ns, [{ op: 'set', path: ['baseURL'], value: `${baseURL}/mutate` }], settings.revision);
  equal(mutated.value.baseURL, `${baseURL}/mutate`);
  const updated = await client.updateSettings(settings.ns, { baseURL: `${baseURL}/update` }, mutated.revision);
  equal(updated.value.baseURL, `${baseURL}/update`);
  ok((await client.listAgentPresets()).some(item => item.id === 'standard'));
  equal((await client.readAgentPreset('standard')).agentPreset, 'standard');
  equal(await client.selectAgentPreset(await client.createSession(workspace.id), 'standard'), 'standard');
  ok(Array.isArray(await client.listSkills(session)));
  ok(Array.isArray(await client.scheduleCatalog()));
  const job = Promise.withResolvers();
  const cancelJobs = await client.watchJobs(session, job.resolve, reason => job.reject(new Error(reason)));
  try {
    const jobs = await Promise.race([job.promise, delay(3000, undefined, { ref: false }).then(() => { throw new Error('Job stream timed out'); })]);
    ok(Array.isArray(jobs));
  } finally {
    cancelJobs();
  }
  const inventory = await client.pluginInventory();
  ok(Array.isArray(inventory.entries));
  equal((await client.engineCapabilities()).pluginManagement, inventory.managementAvailable === true);
  await client.deleteWorkspace(workspace.id);
  const staleExportReady = Promise.withResolvers();
  const staleExportResponse = Promise.withResolvers();
  fixtures.exportRequest = async request => {
    await writeFile(request.destination.file, archive);
    staleExportReady.resolve();
    await staleExportResponse.promise;
    return { statusCode: 200, headers: { 'content-type': 'application/zip' } };
  };
  const staleExport = client.exportSessionLog(session, badPath);
  await staleExportReady.promise;
  client.close();
  staleExportResponse.resolve();
  await assert.rejects(staleExport, /连接已变更/);
  await assert.rejects(readFile(badPath), { code: 'ENOENT' });
  checks++;
  console.log(`${checks} native client assertions passed against local DSH`);
} finally {
  releaseRequest.resolve();
  releaseCompaction.resolve();
  client.close();
  provider.closeAllConnections();
  provider.close();
  await writeFile(join(home, 'stop'), '');
  if (child.exitCode === null) {
    await Promise.race([once(child, 'exit'), delay(5000, undefined, { ref: false }).then(() => child.kill('SIGKILL'))]);
  }
  await rm(home, { recursive: true, force: true });
}
