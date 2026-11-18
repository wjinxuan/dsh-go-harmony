import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const root = new URL('../entry/src/main/ets/', import.meta.url);
const url = (code, name) => 'data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(code) + `\n//# sourceURL=${name}.js`);
const wire = url(await readFile(new URL('dsh/DshWire.ets', root), 'utf8'), 'artifact-wire');
const timeline = url((await readFile(new URL('ui/ChatTimeline.ets', root), 'utf8')).replace(/^import type .*\n/gm, ''), 'artifact-timeline');
const artifacts = url((await readFile(new URL('ui/SessionArtifacts.ets', root), 'utf8'))
  .replace('array, DshSessionRecord, object, string, turnTraces, WireObject', 'array, object, string, turnTraces')
  .replace("'../dsh/DshWire'", JSON.stringify(wire)), 'session-artifacts');
const { ChatTimeline, groupToolRows } = await import(timeline);
const { artifactKind, resolveArtifactPath, sessionArtifacts } = await import(artifacts);
const { DshTranscript } = await import(wire);
const tool = (id, meta) => ({ callId: id, name: 'read', arguments: '{}', result: 'ok', seq: Number(id), meta });

test('groups consecutive three tools without hiding media/plugin cards or crossing messages', () => {
  const tools = [tool('1'), tool('2'), tool('3'), tool('4', { 'dsh-go/media': { kind: 'image' } }), tool('5'), tool('6'), tool('7')];
  const rows = new ChatTimeline().update('session', [], tools);
  assert.deepEqual(rows.map(row => row.tools?.length || row.tool?.callId), [3, '4', 3]);
  const separated = groupToolRows([{ key: 'one', position: 1, tool: tool('1') }, { key: 'two', position: 2, tool: tool('2') },
    { key: 'message', position: 3, message: { text: 'hello' } }, { key: 'three', position: 4, tool: tool('4') }]);
  assert.equal(separated.length, 4); assert.ok(separated.every(row => !row.tools));
  const owner = new ChatTimeline(); const first = owner.update('s', [], [tool('1', { 'dsh-go/media': { status: 'running' } })]);
  const next = owner.update('s', [], [tool('1', { 'dsh-go/media': { status: 'done' } })]);
  assert.notEqual(first[0].key, next[0].key, 'metadata-only updates must rebuild the media result card');
});

test('automatic turns without user echoes keep separate tool groups and fold boundaries', () => {
  const tools = [1, 2, 3, 6, 7, 8].map(id => tool(String(id)));
  const rows = new ChatTimeline().update('timer-session', [], tools, [], [], [],
    [{ startSeq: 0, endSeq: 4 }, { startSeq: 5, endSeq: 9 }]);
  assert.deepEqual(rows.map(row => row.tools.map(tool => tool.seq)), [[1, 2, 3], [6, 7, 8]]);
});

const event = (seq, type, data) => ({ seq, type, time: seq * 1000, data });
const start = turn => event(turn * 10, 'turn/start', { turn });
const end = turn => event(turn * 10 + 9, 'turn/end', { turn, reason: { kind: 'completed' } });
test('finished-turn durable deliveries win, repeated declarations update in place and unsafe links are excluded', () => {
  const events = [start(1), event(11, 'deliverables/presented', { turn: 1, callId: 'p', files: [
    { path: 'report.pdf', description: 'first' }, { path: 'readme.md' }, { path: 'https://external.example/private' },
    { path: '', description: 'empty' }, { path: 'invalid.pdf', description: 7 }] }),
    event(12, 'deliverables/presented', { turn: 1, callId: 'p2', files: [{ path: 'report.pdf', description: 'revised' }] }), end(1),
    start(2), event(21, 'deliverables/presented', { turn: 2, callId: 'pending', files: [{ path: 'not-yet.pdf' }] })];
  const result = sessionArtifacts(events, '/workspace');
  assert.deepEqual(result.map(item => [item.path, item.description, item.origin]), [
    ['/workspace/report.pdf', 'revised', 'delivered'], ['/workspace/readme.md', '', 'delivered']]);
  const rows = new ChatTimeline().update('s', [], [], [], [], result);
  assert.equal(rows.length, 1); assert.equal(rows[0].position, 19.5); assert.equal(rows[0].artifacts.length, 2);
});

test('fallback artifacts require a successful create or final linked path named by a tool', () => {
  const events = [start(1), event(11, 'tool/call', { turn: 1, callId: 'write', name: 'write', arguments: JSON.stringify({ file_path: 'created.pdf' }) }),
    event(12, 'tool/result', { turn: 1, message: { toolCallId: 'write' }, meta: { operation: 'create', path: '/workspace/created.pdf' } }),
    event(13, 'tool/call', { turn: 1, callId: 'shell', name: 'bash', arguments: JSON.stringify({ command: 'create linked.xlsx' }) }),
    event(14, 'assistant/message', { turn: 1, message: { content: [{ type: 'text', text: '[sheet](linked.xlsx) [unknown](unknown.pdf) [code](code.ts)' }] } }), end(1)];
  assert.deepEqual(sessionArtifacts(events, '/workspace').map(item => [item.name, item.origin]), [['created.pdf', 'written'], ['linked.xlsx', 'linked']]);
  assert.equal(resolveArtifactPath('../a/./b.pdf', '/workspace/folder'), '/workspace/a/b.pdf');
  assert.equal(resolveArtifactPath('file:///workspace/a%20b.pdf'), '/workspace/a b.pdf');
  assert.equal(resolveArtifactPath('https://outside.example/file.pdf'), '');
  assert.equal(resolveArtifactPath('', '/workspace'), '');
  assert.equal(artifactKind('REPORT.XLSX'), 'spreadsheet');
});

test('actual transcript records retain only artifact fields and never return host diagnostics', () => {
  const transcript = new DshTranscript('artifacts');
  const records = [start(1), event(11, 'tool/call', { turn: 1, callId: 'write', name: 'write', arguments: JSON.stringify({ file_path: 'created.pdf' }), diagnostic: 'private-call-diagnostic' }),
    event(12, 'tool/result', { turn: 1, message: { toolCallId: 'write', content: [{ type: 'text', text: 'private-result-diagnostic' }] },
      meta: { operation: 'create', path: '/workspace/created.pdf', privateToken: 'private-result-token' } }),
    event(13, 'deliverables/presented', { turn: 1, callId: 'present', files: [{ path: 'created.pdf', description: 'Ready', privateToken: 'private-file-token' }], privateToken: 'private-present-token' }),
    event(19, 'turn/end', { turn: 1, reason: { kind: 'completed', error: { message: 'private-native-error' } } })];
  transcript.apply({ type: 'snapshot', records: records.map(event => ({ event })), cursor: 19 });
  const safe = transcript.sessionRecords();
  assert.deepEqual(sessionArtifacts(safe, '/workspace').map(item => [item.path, item.description]), [['/workspace/created.pdf', 'Ready']]);
  assert.doesNotMatch(JSON.stringify(safe), /private-/);
});
