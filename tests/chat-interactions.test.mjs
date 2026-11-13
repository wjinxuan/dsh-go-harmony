import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const methods = (start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)));
const code = methods('  private async showModels(', '  private home(') +
  methods('  private async newSession(', '  private async stop(');
const Owner = vm.runInNewContext(stripTypeScriptTypes(`(class Owner { ${code} })`), {
  object: value => value && typeof value === 'object' ? value : {},
  modelSelection: value => value?.provider && value?.model ? value : undefined,
  setTimeout, util: { generateRandomUUID: () => 'stable-fixture-request' }
});

function fixture() {
  const owner = new Owner();
  const calls = { created: 0, selected: 0, prompts: [] };
  Object.assign(owner, {
    mode: 'remote', connected: true, busy: false, loadingChat: false, sending: false, running: false,
    connectionVersion: 1, chatVersion: 1, sessionId: '', sessionTitle: '', currentModel: undefined,
    pendingSessionModel: undefined, pendingModelSessionId: '', draft: 'keep my draft', errorText: '',
    submittedRecoveries: [], recoveryRequestIds: new Map(),
    turnNotices: [], queuedPrompts: [], workspaceId: '', sessions: [],
    composerDrafts: { read: () => '', write() {} },
    client: {
      async createSession() { calls.created++; return 'new-session'; },
      async setModel(id, provider, model, reasoningEffort) {
        calls.selected++; return { selected: { provider, model, reasoningEffort } };
      },
      async prompt(id, text) { calls.prompts.push({ id, text }); }
    },
    async openSession(id) { owner.sessionId = id; owner.chatVersion++; },
    scrollToLatest() {}, errorMessage: (_error, fallback) => fallback
  });
  return { owner, calls };
}

test('browsing models does not create an empty session or discard the draft', async () => {
  const { owner, calls } = fixture();
  await owner.showModels();
  assert.equal(owner.page, 'models');
  assert.equal(calls.created, 0);
  assert.equal(owner.draft, 'keep my draft');
});

test('first send applies the pending model before submitting text', async () => {
  const { owner, calls } = fixture();
  owner.currentModel = { provider: 'account', model: 'chosen', reasoningEffort: 'high' };
  owner.client.prompt = async (id, text) => {
    assert.equal(calls.selected, 1);
    calls.prompts.push({ id, text });
  };
  await owner.send();
  assert.equal(calls.created, 1);
  assert.equal(calls.prompts[0].text, 'keep my draft');
  assert.equal(owner.pendingSessionModel, undefined);
});

test('failed pending selection keeps text and reuses the created session on retry', async () => {
  const { owner, calls } = fixture();
  owner.currentModel = { provider: 'account', model: 'chosen' };
  const select = owner.client.setModel;
  owner.client.setModel = async () => { throw new Error('private host detail'); };
  await owner.send();
  assert.equal(calls.created, 1);
  assert.equal(calls.prompts.length, 0);
  assert.equal(owner.draft, 'keep my draft');
  assert.doesNotMatch(owner.errorText, /private host detail/);
  owner.client.setModel = select;
  await owner.send();
  assert.equal(calls.created, 1);
  assert.equal(calls.prompts.length, 1);
});

test('explicit turn recovery submits captured input without touching a newer draft', async () => {
  const { owner, calls } = fixture();
  owner.sessionId = 'session';
  const notice = { seq: 10, kind: 'error', text: '服务暂不可用', actionable: true,
    recovery: 'retry', retryText: 'original failed question' };
  owner.turnNotices = [notice];
  await owner.recoverTurn(notice);
  assert.deepEqual(calls.prompts, [{ id: 'session', text: 'original failed question' }]);
  assert.equal(owner.draft, 'keep my draft');
});

test('stale or busy turn actions cannot submit to another turn', async () => {
  const { owner, calls } = fixture();
  owner.sessionId = 'session';
  const notice = { seq: 10, kind: 'error', actionable: true, recovery: 'continue' };
  owner.turnNotices = [notice];
  owner.running = true; await owner.recoverTurn(notice);
  owner.running = false; owner.queuedPrompts = [{}]; await owner.recoverTurn(notice);
  owner.queuedPrompts = []; owner.turnNotices = []; await owner.recoverTurn(notice);
  assert.equal(calls.prompts.length, 0);
});

test('late model selection cannot overwrite a new connection or send a message', async () => {
  const { owner, calls } = fixture();
  owner.currentModel = { provider: 'account', model: 'chosen' };
  let release;
  owner.client.setModel = () => new Promise(resolve => { release = resolve; });
  const sending = owner.send();
  await new Promise(resolve => setImmediate(resolve));
  owner.connectionVersion++; owner.chatVersion++; owner.sessionId = 'other';
  owner.currentModel = { provider: 'new-host', model: 'other' };
  release({ selected: { provider: 'account', model: 'chosen' } });
  await sending;
  assert.equal(owner.currentModel.provider, 'new-host');
  assert.equal(calls.prompts.length, 0);
});

test('switching conversations while creation is pending does not steal the active conversation', async () => {
  const { owner, calls } = fixture();
  let release;
  owner.client.createSession = () => new Promise(resolve => { release = resolve; });
  const sending = owner.send();
  owner.chatVersion++; owner.sessionId = 'selected-existing'; owner.draft = 'new draft';
  release('late-created');
  await sending;
  assert.equal(owner.sessionId, 'selected-existing');
  assert.equal(owner.draft, 'new draft');
  assert.equal(calls.prompts.length, 0);
});

test('switching away and back while model apply is pending cannot revive the old send', async () => {
  const { owner, calls } = fixture();
  owner.sessionId = 'existing'; owner.pendingModelSessionId = 'existing';
  owner.pendingSessionModel = { provider: 'account', model: 'chosen' };
  let release;
  owner.client.setModel = () => new Promise(resolve => { release = resolve; });
  const sending = owner.send();
  owner.chatVersion += 2; owner.currentModel = { provider: 'new-choice', model: 'kept' };
  release({ selected: { provider: 'account', model: 'chosen' } });
  await sending;
  assert.equal(owner.currentModel.model, 'kept');
  assert.equal(calls.prompts.length, 0);
});

test('successful recovery cannot be duplicated while the transcript is catching up', async () => {
  const { owner, calls } = fixture(); owner.sessionId = 'session';
  const notice = { seq: 10, kind: 'error', actionable: true, recovery: 'continue' };
  owner.turnNotices = [notice];
  await owner.recoverTurn(notice); await owner.recoverTurn(notice);
  assert.equal(calls.prompts.length, 1);
});

test('uncertain recovery retries use the same request identity and keep the draft', async () => {
  const { owner } = fixture(); owner.sessionId = 'session';
  const notice = { seq: 10, kind: 'error', actionable: true, recovery: 'continue' };
  owner.turnNotices = [notice]; const ids = [];
  owner.client.prompt = async (_session, _text, id) => { ids.push(id); throw new Error('timeout'); };
  await owner.recoverTurn(notice); await owner.recoverTurn(notice);
  assert.equal(ids.length, 2); assert.equal(ids[0], ids[1]); assert.ok(ids[0]);
  assert.equal(owner.draft, 'keep my draft');
});
