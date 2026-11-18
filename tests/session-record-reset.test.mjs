import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';

const source = await readFile(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
function method(name) {
  const start = source.search(new RegExp('  private (?:async )?' + name + '\\('));
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  private ', start + 1));
}
const uri = text => 'data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(text));
const wire = await import(uri(await readFile(new URL('../entry/src/main/ets/dsh/DshWire.ets', import.meta.url), 'utf8')));
const Owner = Function('object', 'modelSelection', 'turnTraces', 'return ' + stripTypeScriptTypes(
  '(class Owner {' + ['home', 'disconnect', 'openSession', 'showShare', 'retireRegeneration'].map(method).join('\n') + '})'))(
  wire.object, wire.modelSelection, wire.turnTraces);
const oldRecords = () => [{ seq: 1, type: 'turn/start', time: 1, data: { turn: 1 } },
  { seq: 2, type: 'deliverables/presented', time: 2, data: { turn: 1, callId: 'old-present', files: [{ path: '/old-host/private.pdf' }] } },
  { seq: 3, type: 'turn/end', time: 3, data: { turn: 1, reason: { kind: 'completed' } } }];
function fixture() {
  const state = new Owner();
  Object.assign(state, {
    t: value => value, errorMessage: error => error.message,
    mode: 'remote', localStage: '', connected: true, sessionId: 'old-session', sessionTitle: 'old title', records: oldRecords(),
    sessions: [], workspaces: [], messages: [], tools: [], draft: '', connectionVersion: 1, chatVersion: 1, regenerationVersion: 0,
    client: { close() {}, async unwatchSession() {}, async watchSession() {} }, localEngine: { async stop() {} },
    mentions: { reset() {} }, composerDrafts: { write() {}, read: () => '', clear() {} }, questionDrafts: new Map(),
    recoveryRequestIds: new Map(), visualReplyRequests: new Map(), cotTranslations: { clear() {} },
    changeAttachmentDraft() {}, clearAttachments() {}, releaseTransport() {}, settleVisualReply() {}, releaseCommittedAttachments() {},
    chatScroller: { isAtEnd: () => true }, scrollToLatest() {}, async loadCommandCatalog() {}
  });
  return state;
}

test('disconnect and home retire old durable records together with the old session title', async () => {
  for (const action of ['disconnect', 'home']) {
    const state = fixture(); await state[action](false);
    assert.equal(state.sessionId, ''); assert.equal(state.sessionTitle, '');
    assert.deepEqual(state.records, [], action + ' must remove old artifact/turn/share records');
  }
});

test('opening another session clears records before a delayed snapshot and accepts only that session snapshot', async () => {
  const state = fixture(); let emit, release;
  state.client.watchSession = async (_id, callback) => { emit = callback; await new Promise(done => { release = done; }); };
  const opening = state.openSession('new-session', 'New title');
  assert.equal(state.loadingChat, true); assert.deepEqual(state.records, []);
  emit({ sessionId: 'old-session', records: oldRecords(), messages: [] });
  assert.deepEqual(state.records, [], 'late old-session callback cannot repopulate records');
  const records = [{ seq: 10, type: 'turn/start', time: 10, data: { turn: 1 } }];
  emit({ sessionId: 'new-session', records, messages: [], running: false }); release(); await opening;
  assert.equal(state.records, records); assert.equal(state.loadingChat, false);
});

test('a failed new-session subscription cannot export the previous session records through sharing', async () => {
  const state = fixture(); state.client.watchSession = async () => { throw new Error('isolated subscription failure'); };
  await state.openSession('new-session', 'New title');
  assert.equal(state.loadingChat, false); assert.match(state.errorText, /subscription failure/);
  state.showShare();
  assert.deepEqual(state.shareSource.records, []); assert.deepEqual(state.shareSource.turns, []);
  assert.equal(state.shareSource.title, 'New title');
});

test('English local-stop state rejects reentry and releases its guard after failure for a later retry', async () => {
  const state = fixture(); state.mode = 'local';
  state.t = value => value === '正在停止本机引擎…' ? 'Stopping the local engine…' : value;
  let rejectStop, calls = 0;
  state.localEngine.stop = async () => { calls++; await new Promise((_resolve, reject) => { rejectStop = reject; }); };
  const first = state.disconnect(true);
  assert.equal(state.localStage, 'Stopping the local engine…');
  const duplicate = state.disconnect(true);
  assert.equal(calls, 1, 'locale must not disable the stop guard');
  rejectStop(new Error('native stop failed')); await Promise.all([first, duplicate]);
  state.localEngine.stop = async () => { calls++; };
  await state.disconnect(true);
  assert.equal(calls, 2, 'failed stop must release the guard'); assert.equal(state.localStage, '');
});
