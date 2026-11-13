import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DshTranscript, localSessionError, approvalFromEvent, createMuxOpen, createRpcRequest, modelCatalog,
  modelSelectionResult, normalizeProviderKey, parseRpcResponse, workspaceListing, workspaceText,
  questionFromEvent, continuedQuestions, sessionPage, turnTraces, permissionCatalog } from './DshWire.ts';
import { ChatTimeline } from './ChatTimeline.ts';

assert.equal(localSessionError("EACCES: permission denied, link '/private/secret'"), '本机会话写入失败（EACCES/link）');
assert.equal(localSessionError('Session file lock failed (95)'), '无法锁定本机会话（95）');
assert.equal(localSessionError('arbitrary error containing a secret'), '本机会话运行失败');
assert.equal(localSessionError('AUTH: the service returned secret data'), 'DeepSeek 拒绝了 API Key');
const invalidKeyMessage = 'API Key 格式无效，请只粘贴原始密钥，去掉内部空格、换行或其他非 ASCII 字符。';
assert.equal(normalizeProviderKey('  \tsk-fixture!~\n'), 'sk-fixture!~');
assert.throws(() => normalizeProviderKey(' \n\t'), { message: '请输入 API Key' });
for (const illegal of [' ', '\n', '\t', '\u0000', '\u200b', '密']) {
  assert.throws(() => normalizeProviderKey(`sk-fixture${illegal}suffix`), { message: invalidKeyMessage });
}
assert.equal(localSessionError('fixture: the API key resolved from DEEPSEEK_API_KEY contains characters no HTTP header can carry'),
  invalidKeyMessage);

const queue = new DshTranscript('queue-session');
const queued = (id, text, kind = 'user') => ({ id, role: 'user', source: { kind, rpcId: `req-${id}` },
  content: [{ type: 'text', text }] });
const event = (seq, type, data, time = seq * 100) => ({ event: { seq, type, time, data }, type: 'event' });
queue.apply({ type: 'snapshot', cursor: 6, projections: { asOfSeq: 6, values: {
  agentPreset: 'standard', permissions: { currentValue: 'workspace-write' }, todos: [{ content: 'check', status: 'pending' }],
  inbox: { 'next-turn': [queued('a', 'old'), queued('b', 'next')], 'next-step': [queued('c', 'steer')] },
  goal: { goal: { id: 'g', revision: 1, objective: 'finish', phase: 'active' }, roundsStarted: 0 }
} }, records: [event(4, 'turn/start', { turn: 1 })] });
assert.deepEqual(queue.queuedPrompts().map(({ id, text, target }) => [id, text, target]),
  [['c', 'steer', 'next-step'], ['a', 'old', 'next-turn'], ['b', 'next', 'next-turn']]);
assert.equal(queue.projections().permissionPreset, 'workspace-write');
assert.equal(queue.goal()?.id, 'g');
assert.equal(queue.todos()[0].content, 'check');
queue.apply(event(7, 'agent/inbox/spliced', { target: 'next-turn', start: 0, removedCount: 1,
  inserted: [queued('a', 'edited'), queued('auto', 'engine', 'tool-jobs')] }));
assert.deepEqual(queue.queuedPrompts().map(({ text, automatic }) => [text, automatic]),
  [['steer', false], ['edited', false], ['engine', true], ['next', false]]);
queue.apply(event(8, 'turn/start', { turn: 2 }));
assert.equal(queue.todos(), undefined);
queue.apply(event(9, 'user/message', { source: { kind: 'goal', goalId: 'g', round: 3 } }));
assert.equal(queue.goal()?.roundsStarted, 3);
queue.apply(event(10, 'permission/preset', { preset: 'read-only' }));
assert.equal(queue.projections().permissionPreset, 'read-only');

const questions = [{ id: 'q', question: 'Choose?', header: 'Choice', multiSelect: true,
  options: [{ label: 'A', description: 'first' }], intent: { kind: 'plan-review', approve: 'A' } }];
const pendingQuestion = questionFromEvent({ type: 'waterfall', event: 'user-questions/request', eventId: 'e',
  agentId: 'queue-session', request: { questions, wait: { timed: true, callId: 'call' } } });
assert.deepEqual([pendingQuestion.id, pendingQuestion.callId, pendingQuestion.timed, pendingQuestion.questions[0].options[0].label],
  ['e', 'call', true, 'A']);
assert.deepEqual(continuedQuestions('queue-session', { active: [
  { callId: 'open', state: 'open', questions }, { callId: 'closed', state: 'continued', questions }
] }).map(q => [q.id, q.continued]), [['closed', true]]);
assert.deepEqual(permissionCatalog({ options: [{ value: 'auto', name: 'Auto' }, { value: 'read-only', name: 'Read' }],
  defaultPreset: 'read-only' }).defaultOptions.map(option => option.value), ['read-only']);

const page = sessionPage({ cursor: 20, hasMore: true, records: [
  event(11, 'turn/start', { turn: 3 }), event(12, 'step/start', { step: 1 }),
  event(13, 'assistant/message', { step: 1, usage: { inputTokens: 5, outputTokens: 2 },
    message: { source: { provider: 'fixture', model: 'm' }, content: [{ type: 'text', text: 'response' }] },
    stream: [{ type: 'text-chunks', time0: 1210, dt: [50] }] }),
  event(14, 'tool/call', { callId: 'call', name: 'read', step: 1, arguments: '{}' }),
  event(15, 'approval/asked', { id: 'approval', callId: 'call', toolName: 'read' }),
  event(16, 'approval/decided', { id: 'approval', outcome: 'allowed-once' }),
  event(17, 'tool/result', { message: { toolCallId: 'call', isError: false } }),
  event(20, 'turn/end', { turn: 3, reason: { kind: 'completed' } })
] });
assert.equal(page.beforeSeq, 11);
const [trace] = turnTraces(page.records);
assert.deepEqual([trace.turn, trace.reason, trace.steps, trace.endSeq], [3, 'completed', 1, 20]);
assert.deepEqual(trace.spans.map(s => [s.kind, s.start, s.end]),
  [['model', 1200, 1300], ['approval', 1500, 1600], ['tool', 1600, 1700]]);
assert.deepEqual([trace.spans[0].firstToken, trace.spans[0].lastToken], [1210, 1260]);

const request = createRpcRequest('request-1', 'session/list', { _request: {} });
assert.deepEqual(request, {
  type: 'client-request', rpcId: 'request-1', method: 'session/list', payload: { args: { _request: {} } }
});
assert.deepEqual(parseRpcResponse(JSON.stringify({
  type: 'server-response', rpcId: 'request-1', result: { ok: true, value: { items: [] } }
}), 'request-1'), { items: [] });
assert.throws(() => parseRpcResponse('{"type":"server-response","rpcId":"wrong","result":{"ok":true}}', 'request-1'));
assert.throws(() => parseRpcResponse(JSON.stringify({
  type: 'server-response', rpcId: 'wrong', result: { ok: false, error: { code: 'gateway/bad-request' } }
}), 'request-1'), /DSH 返回的请求结果无效/);
assert.deepEqual(createMuxOpen('stream-1', '$events', {}), {
  type: 'open', streamId: 'stream-1', endpoint: '$events', payload: { args: {} }
});

const transcript = new DshTranscript('session-1');
transcript.apply({ type: 'snapshot', records: [
  { event: { type: 'user/message', seq: 1, data: { id: 'real', source: { kind: 'user' },
    content: [{ type: 'text', text: 'Hi' }] } } },
  { event: { type: 'user/message', seq: 2, data: { id: 'internal', source: { kind: 'runtime-context' },
    content: [{ type: 'text', text: 'private runtime context' }] } } }
] });
assert.deepEqual(transcript.messages().map(({ id, role, text }) => ({ id, role, text })),
  [{ id: 'real', role: 'user', text: 'Hi' }]);
transcript.apply({ type: 'event', event: { type: 'turn/start', seq: 3 } });
assert.equal(transcript.running, true);
transcript.apply({ type: 'assistant-stream', frame: { type: 'start', attemptId: 'attempt-1' } });
transcript.apply({ type: 'assistant-stream', frame: { type: 'chunk', attemptId: 'attempt-1',
  chunk: { type: 'text-delta', index: 0, text: 'Hello' } } });
transcript.apply({ type: 'assistant-stream', frame: { type: 'chunk', attemptId: 'attempt-1',
  chunk: { type: 'reasoning-delta', index: 1, text: '思考中' } } });
transcript.apply({ type: 'assistant-stream', frame: { type: 'chunk', attemptId: 'attempt-1',
  chunk: { type: 'usage', usage: { inputTokens: 3, outputTokens: 2 } } } });
assert.equal(transcript.messages().at(-1).text, 'Hello');
assert.equal(transcript.messages().at(-1).reasoning, '思考中');
assert.equal(transcript.messages().at(-1).usage.outputTokens, 2);
transcript.apply({ type: 'event', event: { type: 'assistant/message', seq: 4, data: {
  message: { id: 'reply', content: [{ type: 'reasoning', text: 'hidden' }, { type: 'text', text: 'Hello!' }] },
  usage: { inputTokens: 3, outputTokens: 4, cacheReadTokens: 7 }
} } });
transcript.apply({ type: 'assistant-stream', frame: { type: 'end', attemptId: 'attempt-1' } });
transcript.apply({ type: 'event', event: { type: 'turn/end', seq: 5 } });
assert.deepEqual(transcript.messages().map(({ id, role, text }) => ({ id, role, text })), [
  { id: 'real', role: 'user', text: 'Hi' }, { id: 'reply', role: 'assistant', text: 'Hello!' }
]);
assert.equal(transcript.messages()[1].reasoning, 'hidden');
assert.equal(transcript.messages()[1].usage.cacheReadTokens, 7);
assert.equal(transcript.running, false);
assert.deepEqual(approvalFromEvent({
  type: 'waterfall', event: 'approval/request', eventId: 'event-1', agentId: 'session-1',
  request: { toolName: 'bash', displayReason: { zh: '运行命令？' } }
}), { id: 'event-1', sessionId: 'session-1', title: '运行命令？' });
assert.equal(approvalFromEvent({
  type: 'waterfall', event: 'user-questions/request', eventId: 'event-2', agentId: 'session-1'
}), undefined);
transcript.apply({ type: 'event', event: { type: 'tool/call', seq: 6, data: {
  callId: 'shell-1', name: 'bash', arguments: '{"command":"pwd","workdir":"/fixture","sandbox_permissions":"danger-full-access","run_in_background":true}'
} } });
const approvalRequest = { id: 'event-1', sessionId: transcript.sessionId, title: '确认操作' };
const review = (callId, name) => transcript.reviewApproval(approvalRequest, callId, name);
assert.equal(review('shell-1', 'bash').canAllow, true);
assert.match(review('shell-1', 'bash').title, /pwd\n工作目录 \/fixture\n沙箱权限 danger-full-access\n后台运行/);
assert.equal(review('another-shell', 'bash').canAllow, false);
assert.equal(review('shell-1', 'pwsh').canAllow, false);
assert.equal(transcript.reviewApproval({ ...approvalRequest, sessionId: 'another' }, 'shell-1', 'bash').canAllow, false);
transcript.apply({ type: 'event', event: { type: 'tool/result', seq: 7, data: {
  message: { toolCallId: 'shell-1', isError: false, content: [{ type: 'text', text: 'result' }] },
  meta: { exitCode: 0 }
} } });
assert.equal(transcript.tools().length, 1);
assert.equal(transcript.tools()[0].name, 'bash');
assert.equal(transcript.tools()[0].result, 'result');
assert.equal(transcript.tools()[0].meta.exitCode, 0);
assert.equal(review('shell-1', 'bash').canAllow, false);
for (const [seq, id, name, args] of [
  [8, 'pwsh', 'pwsh', '{"command":"Get-Location"}'],
  [9, 'code', 'run_code', '{"code":"print(1)","sandbox_permissions":"danger-full-access"}'],
  [10, 'code-no-source', 'run_code', '{"description":"Run program"}'],
  [11, 'partial', 'bash', '{"command":"pwd'],
  [12, 'generic', 'write', '{"file_path":"fixture.txt","content":"actual input"}'],
  [13, 'generic-empty', 'write', '{}'],
  [14, 'generic-long', 'write', JSON.stringify({ content: 'x'.repeat(20000) })],
  [15, 'hidden', 'bash', JSON.stringify({ command: 'pwd\u202E' })],
  [16, 'generic-missing-path', 'write', '{"content":"actual input"}'],
  [17, 'generic-missing-text', 'edit', '{"file_path":"fixture.txt","new_string":"x"}'],
  [18, 'generic-empty-write', 'write', '{"file_path":"fixture.txt","content":""}']
]) {
  transcript.apply(event(seq, 'tool/call', { callId: id, name, arguments: args }));
}
assert.match(review('pwsh', 'pwsh').title, /Get-Location/);
assert.match(review('code', 'run_code').title, /print\(1\)\n沙箱权限 danger-full-access/);
assert.match(review('generic', 'write').title, /"file_path":"fixture.txt","content":"actual input"/);
assert.equal(review('generic-empty-write', 'write').canAllow, true);
for (const [id, name] of [['code-no-source', 'run_code'], ['partial', 'bash'], ['generic-empty', 'write'],
  ['generic-long', 'write'], ['hidden', 'bash'], ['generic-missing-path', 'write'], ['generic-missing-text', 'edit']]) {
  assert.equal(review(id, name).canAllow, false);
}

// A sanitized session/follow snapshot and event sequence from the phone.
const deviceTools = new DshTranscript('device-tools');
const operations = ['write', 'read', 'edit', 'read'];
const records = operations.flatMap((name, index) => {
  const seq = 19 + index * 5;
  const callId = `fixture-call-${index}`;
  return [
    { event: { seq, type: 'tool/call', data: { turn: 2, step: index + 1, callId, name, arguments: '{}' } } },
    { event: { seq: seq + 1, type: 'tool/result', data: { turn: 2, step: index + 1,
      message: { id: `fixture-result-${index}`, role: 'tool', source: { kind: 'tool' }, toolCallId: callId,
        content: [{ type: 'text', text: `${name} result` }], isError: false }, meta: {} } } }
  ];
});
deviceTools.apply({ type: 'snapshot', cursor: 18, records: [] });
for (const record of records) deviceTools.apply({ type: 'event', event: record.event });
assert.deepEqual(deviceTools.tools().map(({ name, result, isError }) => [name, result, isError]),
  operations.map(name => [name, `${name} result`, false]));
deviceTools.apply({ type: 'snapshot', cursor: 40, records });
assert.deepEqual(deviceTools.tools().map(({ seq, result }) => [seq, result]),
  operations.map((name, index) => [19 + index * 5, `${name} result`]));

const timeline = new ChatTimeline();
const user = { id: 'first', role: 'user', text: 'prompt', seq: 1 };
const draft = { id: 'draft-one', role: 'assistant', text: 'first', reasoning: 'thought' };
const pending = { callId: 'file-edit', name: 'edit', arguments: '{"path":"test"}', seq: 2 };
const first = timeline.update('session-one', [draft, user], [pending]);
assert.deepEqual(first.map(row => row.message?.id ?? row.tool.callId), ['first', 'file-edit', 'draft-one']);
const done = { ...pending, result: 'updated', isError: false };
const streamed = { ...draft, text: 'first chunk', reasoning: 'new thought' };
const second = timeline.update('session-one', [{ ...user }, streamed], [done]);
assert.equal(second[0].key, first[0].key);
assert.notEqual(second[1].key, first[1].key);
assert.notEqual(second[2].key, first[2].key);
assert.ok(!second[1].key.includes(done.result));
assert.ok(!second[2].key.includes(streamed.text));
const stable = timeline.update('session-one', [{ ...user }, { ...streamed }], [{ ...done, meta: { hidden: true } }]);
assert.deepEqual(stable.map(row => row.key), second.map(row => row.key));
const changed = timeline.update('session-one', [user, { ...streamed, usage: { inputTokens: 3, outputTokens: 1 } }],
  [{ ...done, isError: true }]);
assert.notEqual(changed[1].key, stable[1].key);
assert.notEqual(changed[2].key, stable[2].key);
const removed = timeline.update('session-one', [user], []);
assert.deepEqual(removed.map(row => row.key), [changed[0].key]);
const readded = timeline.update('session-one', [user, streamed], [done]);
assert.notEqual(readded[1].key, second[1].key);
assert.notEqual(readded[2].key, second[2].key);
assert.notEqual(timeline.update('session-two', [user], [])[0].key, readded[0].key);

const catalog = modelCatalog({ default: { provider: 'deepseek-official', model: 'deepseek-flash' },
  routableProviders: ['deepseek-official'], groups: [{ id: 'deepseek-official', name: 'DeepSeek', models: [
    { id: 'deepseek-flash', reasoning: { defaultEffort: 'high', efforts: [{ id: 'high', name: '高' }] } }
  ] }], failures: [{ id: 'provider-failure', name: 'Failure', message: 'secret payload' }] });
assert.equal(catalog.groups[0].models[0].name, 'deepseek-flash');
assert.equal(catalog.groups[0].models[0].efforts[0].name, '高');
assert.equal(catalog.defaultSelection.provider, 'deepseek-official');
assert.equal(JSON.stringify(catalog).includes('secret payload'), false);
assert.equal(modelSelectionResult({ selected: catalog.defaultSelection, defaultSave: { status: 'failed' } },
  { provider: 'fallback', model: 'fallback' }).selected.model, 'deepseek-flash');
assert.equal(modelSelectionResult({}, { provider: 'fallback', model: 'fallback' }).selected.model, 'fallback');
assert.deepEqual(workspaceListing({ path: '', entries: [{ name: 'notes', type: 'directory' },
  { name: 'test.txt', type: 'file', size: 4 }, { name: 'special', type: 'fifo' }, {}] }, 'fallback').entries.map(
  ({ name, type, size }) => [name, type, size]), [
  ['notes', 'directory', undefined], ['test.txt', 'file', 4], ['special', 'other', undefined]
]);
assert.equal(workspaceText({ text: 'text', lines: 1, eof: true, offset: 17, version: 'file-v1' }, 1).offset, 17);

const compact = new DshTranscript('compact-session');
compact.apply({ type: 'snapshot', records: [], assistantStream: { activeAttempt: { attemptId: 'running', stream: [
  { type: 'reasoning-chunks', index: 0, texts: ['one', ' two'] },
  { type: 'text-chunks', index: 1, texts: ['result'] },
  { type: 'chunk', chunk: { type: 'usage', usage: { inputTokens: 5, outputTokens: 1 } } }
] } } });
assert.equal(compact.messages()[0].reasoning, 'one two');
assert.equal(compact.messages()[0].usage.inputTokens, 5);
compact.apply({ type: 'event', event: { type: 'turn/end', seq: 1, data: { reason: { kind: 'error',
  error: { code: 'RATE_LIMIT', message: 'secret payload' } } } } });
assert.equal(compact.turnFailureCode, 'RATE_LIMIT');
assert.equal(compact.messages().length, 0);
compact.apply({ type: 'event', event: { type: 'turn/end', seq: 2, data: { reason: { kind: 'error',
  error: { code: 'INVALID_CREDENTIAL', message: 'secret fixture data' } } } } });
assert.equal(localSessionError('', compact.turnFailureCode), invalidKeyMessage);
assert.throws(() => parseRpcResponse(JSON.stringify({
  type: 'server-response', rpcId: 'request-1', result: { ok: false,
    error: { code: 'gateway/bad-request', message: 'secret-token' } }
}), 'request-1'), /^(?!.*secret-token).*gateway\/bad-request/);

const failedTurn = new DshTranscript('notice-session');
const noticeTimeline = new ChatTimeline();
const secretFailure = 'MODEL_SECRET_IN_RELAY /Users/example/private.txt';
const noticeEvent = (seq, type, data) => ({ type: 'event', event: { seq, type, data } });
const noticePrompt = (seq, text, content = [{ type: 'text', text }], source = { kind: 'user' }) =>
  noticeEvent(seq, 'user/message', { id: 'msg-' + seq, source, content });
const noticeEnd = (seq, turn, kind, code, message = secretFailure) =>
  noticeEvent(seq, 'turn/end', { turn, reason: { kind, error: { code, message } } });
const noticeStart = (seq, turn) => noticeEvent(seq, 'turn/start', { turn });
const retry = noticeEvent(3, 'llm/retry', { turn: 1, retry: 2, maxRetries: 5,
  retryId: 'model-retry-2', failure: { code: 'RATE_LIMIT', message: secretFailure } });
failedTurn.apply(noticeStart(1, 1));
failedTurn.apply(noticePrompt(2, 'first prompt'));
failedTurn.apply(retry);
assert.equal(failedTurn.running, true);
assert.equal(failedTurn.turnNotices()[0].text, '请求失败，正在重试（2/5）');
assert.equal(failedTurn.turnNotices()[0].retrying, true);
assert.equal(failedTurn.turnNotices()[0].actionable, undefined);
failedTurn.applySessionError('安全的旧版错误');
assert.equal(failedTurn.sessionError, 'DSH 主机报告错误，请在主机上查看详情');
failedTurn.apply(noticeEnd(4, 1, 'error', 'RATE_LIMIT'));
assert.equal(failedTurn.sessionError, undefined);
failedTurn.applySessionError('来自较晚通道的旧版错误');
assert.equal(failedTurn.sessionError, undefined);
assert.equal(failedTurn.turnNotices()[1].text, '请求太频繁，稍后再试');
assert.equal(failedTurn.turnNotices()[1].recovery, 'retry');
assert.equal(failedTurn.turnNotices()[1].retryText, 'first prompt');
assert.equal(failedTurn.turnNotices()[0].text, '请求重试（2/5）');
assert.equal(failedTurn.turnNotices()[0].retrying, undefined);
assert.ok(!JSON.stringify(failedTurn.turnNotices()).includes('MODEL_SECRET_IN_RELAY'));
const firstNoticeRows = noticeTimeline.update('notice-session', failedTurn.messages(), failedTurn.tools(), failedTurn.turnNotices());
assert.deepEqual(firstNoticeRows.map(row => [row.position, row.notice?.kind]), [[2, undefined], [3, 'retry'], [4, 'error']]);
const retryRowKey = firstNoticeRows[1].key;
const endRowKey = firstNoticeRows[2].key;
failedTurn.apply(noticeStart(5, 2));
const activeNoticeRows = noticeTimeline.update('notice-session', failedTurn.messages(), failedTurn.tools(), failedTurn.turnNotices());
assert.equal(activeNoticeRows[1].key, retryRowKey);
assert.notEqual(activeNoticeRows[2].key, endRowKey, 'old row must rerender when recovery disappears');
assert.equal(activeNoticeRows[2].notice.recovery, undefined);
failedTurn.apply(noticePrompt(6, 'internal job', undefined, { kind: 'job' }));
failedTurn.apply(noticeEnd(7, 2, 'error', 'TIMEOUT'));
assert.equal(failedTurn.turnNotices()[1].actionable, undefined);
assert.equal(failedTurn.turnNotices()[2].recovery, undefined, 'no prior or synthetic prompt reuse');
failedTurn.apply(noticeStart(8, 3));
failedTurn.apply(noticePrompt(9, 'work on this'));
failedTurn.apply(noticeEvent(10, 'tool/call', { callId: 'seen', name: 'write', arguments: '{}' }));
failedTurn.apply(noticeEnd(11, 3, 'error', 'TRANSPORT'));
assert.equal(failedTurn.turnNotices().at(-1).recovery, 'continue');
assert.equal(failedTurn.turnNotices().at(-1).retryText, undefined);
failedTurn.apply(noticeStart(12, 4));
failedTurn.applySessionError('本机临时错误');
assert.equal(failedTurn.sessionError, 'DSH 主机报告错误，请在主机上查看详情');
failedTurn.apply(noticeStart(13, 5));
failedTurn.apply(noticeEnd(14, 5, 'completed'));
assert.equal(failedTurn.sessionError, undefined);
assert.equal(failedTurn.turnNotices().at(-1).actionable, undefined);

const recovered = new DshTranscript('history');
recovered.apply({ type: 'snapshot', records: [
  noticeStart(1, 1), noticePrompt(2, 'first prompt'), retry,
  noticeEnd(4, 1, 'error', 'RATE_LIMIT'), noticeStart(5, 2), noticePrompt(6, 'image', [
    { type: 'text', text: 'image' }, { type: 'image' }
  ]), noticeEnd(7, 2, 'max-tokens')
] });
assert.deepEqual(recovered.turnNotices().map(row => row.kind), ['retry', 'error', 'max-tokens']);
assert.equal(recovered.turnNotices().at(-1).recovery, 'continue');
assert.equal(recovered.turnNotices()[1].actionable, undefined);
recovered.applySessionError(secretFailure);
assert.equal(recovered.sessionError, 'DSH 主机报告错误，请在主机上查看详情');
recovered.apply({ type: 'snapshot', records: [noticeEnd(7, 2, 'max-tokens')] });
assert.equal(recovered.turnNotices().at(-1).recovery, undefined, 'truncated history lacks a turn start');

const localFailure = new DshTranscript('local-legacy', true);
localFailure.applySessionStatus(true);
localFailure.applySessionError("EACCES: permission denied, link '/private/secret'");
localFailure.apply({ type: 'snapshot', records: [] });
assert.equal(localFailure.sessionError, '本机会话写入失败（EACCES/link）');
localFailure.applySessionStatus(false);
localFailure.applySessionStatus(true);
assert.equal(localFailure.sessionError, undefined);
localFailure.apply(noticeStart(1, 1));
localFailure.apply(noticeEnd(2, 1, 'error', 'INVALID_CREDENTIAL'));
assert.equal(localFailure.turnNotices()[0].text, invalidKeyMessage);
assert.equal(localFailure.turnNotices()[0].actionable, undefined, 'status stream still reports an active turn');
localFailure.applySessionStatus(false);
assert.equal(localFailure.turnNotices()[0].actionable, true);
localFailure.apply({ type: 'snapshot', records: [noticeStart(1, 1), noticeEnd(2, 1, 'error', 'INVALID_CREDENTIAL')] });
localFailure.applySessionError(secretFailure);
assert.equal(localFailure.sessionError, undefined, 'a late relay cannot duplicate a terminal error already in the snapshot');

const retryStart = new DshTranscript('retry-start');
retryStart.apply(noticeStart(1, 1));
retryStart.apply(retry);
retryStart.apply(noticeEvent(4, 'llm/retry-started', { turn: 1, retryId: 'different-attempt' }));
assert.equal(retryStart.turnNotices()[0].retrying, true);
retryStart.apply(noticeEvent(5, 'llm/retry-started', { turn: 1, retryId: 'model-retry-2' }));
assert.equal(retryStart.turnNotices().length, 1);
assert.equal(retryStart.turnNotices()[0].text, '请求重试（2/5）');

const noticeCodes = {
  AUTH: 'API Key 无效或已过期', INVALID_CREDENTIAL: 'API Key 无效或已过期',
  QUOTA: '余额不足', ACCOUNT_QUOTA: '账号额度已用完',
  ACCOUNT_SIGN_IN_REQUIRED: '请在主机上登录 DeepSeek 账号',
  ACCOUNT_TOKEN_INVALID: 'DeepSeek 账号登录已失效，请在主机上重新登录',
  CONTEXT_WINDOW_EXCEEDED: '对话太长，发送 /compact 压缩后再试',
  SERVER: '模型服务暂时不可用', HTTP_503: '模型服务暂时不可用', HTTP_599: '模型服务暂时不可用',
  TIMEOUT: '模型响应超时', TRANSPORT: '没能连上模型服务', EMPTY_RESPONSE: '模型没有返回内容',
  CLIENT_UPGRADE_REQUIRED: '这个模型需要新版引擎', MODEL_UNSUPPORTED: '当前模型不可用',
  UNSUPPORTED_REASONING_EFFORT: '当前模型不支持此推理档位，请调整档位或换模型',
  STRANGE_SECRET_CODE: '本轮出错了', HTTP_600: '本轮出错了'
};
for (const [code, text] of Object.entries(noticeCodes)) {
  const sample = new DshTranscript(code);
  sample.apply(noticeEnd(1, 1, 'error', code));
  assert.equal(sample.turnNotices()[0].text, text);
  assert.ok(!JSON.stringify(sample.turnNotices()).includes(secretFailure));
  if (text === '本轮出错了') assert.equal(sample.turnNotices()[0].code, undefined);
  if (code.startsWith('ACCOUNT_')) {
    assert.equal(sample.turnNotices()[0].code, code);
    assert.equal(sample.turnNotices()[0].recovery, undefined);
  }
}
const credential = new DshTranscript('credential');
credential.apply(noticeEnd(1, 1, 'error', 'MISSING_CREDENTIAL', 'llm-pi-ai private-name'));
assert.equal(credential.turnNotices()[0].credentialTarget, 'provider');
assert.equal(credential.turnNotices()[0].text, '这个模型渠道还没有密钥');
credential.apply(noticeEnd(2, 2, 'error', 'AUTH', 'OAuth refresh failed for openai-codex ' + secretFailure));
assert.equal(credential.turnNotices()[1].subscription, 'openai-codex');
assert.equal(credential.turnNotices()[1].text, 'ChatGPT 登录已失效');
credential.apply(noticeEnd(3, 3, 'error', 'AUTH', 'OAuth refresh failed for secret-route ' + secretFailure));
assert.equal(credential.turnNotices()[2].subscription, undefined);
assert.ok(!JSON.stringify(credential.turnNotices()).includes('secret-route'));

if (process.argv[2]) {
  const capture = JSON.parse(readFileSync(process.argv[2], 'utf8'));
  const actual = new DshTranscript('live-session');
  const expectedUser = process.argv[3];
  const expectedAssistant = process.argv[4];
  let streamed = false;
  for (const item of capture) {
    actual.apply(item);
    streamed ||= actual.messages().some(message => message.id.startsWith('draft-') && message.text.length > 0);
  }
  assert.equal(streamed, true, 'The captured stream showed an assistant draft');
  assert.deepEqual(actual.messages().map(({ role, text }) => ({ role, text })), [
    { role: 'user', text: expectedUser }, { role: 'assistant', text: expectedAssistant }
  ]);
  assert.equal(actual.running, false);
}
if (process.argv[5] && process.argv[6]) {
  const approvalCapture = JSON.parse(readFileSync(process.argv[5], 'utf8'));
  const followCapture = JSON.parse(readFileSync(process.argv[6], 'utf8'));
  const approval = approvalFromEvent(approvalCapture);
  assert.equal(approval.title.includes('danger-full-access'), true);
  const actual = new DshTranscript(approval.sessionId);
  for (const item of followCapture) {
    if (item.event?.type === 'tool/result' && item.event.data.message.toolCallId === approvalCapture.request.callId) break;
    actual.apply(item);
  }
  const review = actual.reviewApproval(approval, approvalCapture.request.callId, approvalCapture.request.toolName);
  assert.equal(review.canAllow, true);
  assert.match(review.title, /printf harmony_fixture\n沙箱权限 danger-full-access/);
}
console.log('DSH Web 协议检查通过');
