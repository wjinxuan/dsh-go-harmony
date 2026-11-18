import { localizedSettingsText as t, localizedSettingsFormat as f } from './settings-locale-fixture.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const method = (start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)));
// Exercise the actual owner methods without loading the ArkUI renderer.
const methods = method('  private async connect(', '  private async refreshSessions(') +
  method('  private async newSession(', '  private async openSession(') +
  method('  private switchHost(', '  @Builder\n  private iconButton(');
const Owner = vm.runInNewContext(stripTypeScriptTypes(`(class Owner { ${methods} })`), {
  object: value => value && typeof value === 'object' ? value : {},
  removeLocalApiKey: async () => {},
  loadWorkspaceView: async () => ({ selected: '' }), rememberStartupHost: async () => {},
  resolveNewChatModes: async () => ({ preset: '', permission: '' }),
  saveNewChatSetup: async () => {},
  ChatNotifications: class { async start() {} stop() {} }
});
function fixture() {
  const state = new Owner();
  const calls = { stop: 0, close: 0, connect: 0 };
  Object.assign(state, {
    t, f,
    mode: 'local', connected: true, page: 'chat', engineReady: true, localConfigured: true,
    localWorkspace: '/phone/workspace', localStage: '', busy: false, connectionVersion: 1, chatVersion: 1,
    remoteHostId: '', remoteHostScope: '', modelKey: '', hasSavedKey: false, errorText: '',
    visualReplyRequests: new Map(), recoveryRequestIds: new Map(), submittedRecoveries: [], newPreset: '', newPermission: '', owedNewChatModes: new Map(),
    mentions: { reset() {} }, cotTranslations: { clear() {} }, hostScope: () => state.mode === 'local' ? 'local' : state.remoteHostScope,
    errorMessage: (error, fallback) => error?.message || fallback, applyPendingModes: async () => {},
    getUIContext: () => ({ getHostContext: () => ({}) }),
    attachmentDrafts: new Map(), attachmentRequestIds: new Map(), attachmentPreviewVersion: 0,
    clearAttachments() {},
    client: { close() { calls.close++; }, onHostEvent() {} }, localEngine: { async stop() { calls.stop++; } },
    questionDrafts: new Map([['q', 'secret draft']]), composerDrafts: new Map([['s', 'old host draft']]),
    sessions: [{ id: 'old' }], workspaces: [{ id: 'old' }], sessionId: 'old', draft: 'old host draft',
    async connect() { calls.connect++; state.connected = true; state.page = 'chat'; return true; }
  });
  return { state, calls };
}
const remote = { id: 'mac', name: 'Test Mac', launchUrl: 'https://fixture.invalid/?token=fixture', authorization: 'fixture-auth' };

test('opening or cancelling host management keeps the current connection and engine alive', () => {
  const { state, calls } = fixture();
  state.showRemoteHosts();
  assert.equal(state.page, 'remoteHosts');
  state.closeRemoteHosts();
  assert.equal(state.page, 'chat');
  assert.equal(calls.close, 0);
  assert.equal(calls.stop, 0);
});

test('switching to remote clears host-specific drafts and never stops the local engine', async () => {
  const { state, calls } = fixture();
  assert.equal(await state.connectRemote(remote), true);
  assert.equal(calls.close, 1);
  assert.equal(calls.stop, 0);
  assert.equal(state.engineReady, true);
  assert.equal(state.localConfigured, true);
  assert.equal(state.questionDrafts.size + state.composerDrafts.size, 0);
  assert.equal(state.sessions.length + state.workspaces.length, 0);
  assert.equal(state.sessionId, '');
  assert.equal(state.draft, '');
  assert.equal(state.remoteHostId, 'mac');
  assert.equal(state.remoteHostScope, 'https://fixture.invalid/');
  assert.equal(state.address + state.authorization, '');
  assert.equal(state.mode, 'remote');
});

test('failed authentication stays retryable without retaining transient credentials or stopping local tasks', async () => {
  const { state, calls } = fixture();
  state.connect = async () => { state.errorText = '启动令牌无效'; return false; };
  assert.equal(await state.connectRemote(remote), false);
  assert.equal(state.page, 'remoteHosts');
  assert.equal(state.remoteHostId, '');
  assert.equal(state.address + state.authorization, '');
  assert.equal(state.errorText, '启动令牌无效');
  assert.equal(calls.stop, 0);
});

test('simultaneous connect actions do not overwrite the pending destination or credential', async () => {
  const { state, calls } = fixture();
  const first = state.connectRemote(remote);
  const duplicate = state.connectRemote({ ...remote, id: 'second', launchUrl: 'https://second.invalid/?token=other' });
  assert.equal(await duplicate, false);
  assert.equal(await first, true);
  assert.equal(calls.connect, 1);
  assert.equal(state.remoteHostId, 'mac');
  assert.equal(state.address + state.authorization, '');
});

test('editing the active profile reconnects, and returning local can reuse its in-memory key', async () => {
  const { state, calls } = fixture();
  await state.connectRemote(remote);
  await state.connectRemote({ ...remote, launchUrl: 'https://second.invalid/?token=new' });
  assert.equal(calls.connect, 2);
  assert.equal(state.remoteHostScope, 'https://second.invalid/');
  state.switchHost('local');
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(state.mode, 'local');
  assert.equal(calls.connect, 3);
  assert.equal(calls.stop, 0);
});

test('explicit local stop works independently of an active remote connection', async () => {
  const { state, calls } = fixture();
  state.mode = 'remote';
  await state.stopLocalEngine();
  assert.equal(calls.stop, 1);
  assert.equal(calls.close, 0);
  assert.equal(state.connected, true);
  assert.equal(state.engineReady, false);
  assert.equal(state.localConfigured, false);
});

test('new remote sessions use the computer default directory, never the retained phone path', async () => {
  const { state } = fixture();
  const directories = [];
  state.client.createSession = async (workspace, cwd) => { directories.push(cwd); return 'new'; };
  state.openSession = async () => {};
  state.mode = 'remote';
  await state.newSession();
  state.mode = 'local';
  await state.newSession();
  assert.deepEqual(directories, [undefined, '/phone/workspace']);
});

test('a failed local stop reports failure and keeps the remote link', async () => {
  const { state, calls } = fixture();
  state.mode = 'remote';
  state.localEngine.stop = async () => { throw new Error('fixture'); };
  assert.equal(await state.stopLocalEngine(), false);
  assert.equal(calls.close, 0);
  assert.equal(state.connected, true);
  assert.equal(state.mode, 'remote');
});

test('reusing a running local engine verifies credential metadata without reading a secret', async () => {
  for (const configured of [false, true]) {
    const { state } = fixture();
    let checks = 0;
    state.connected = false;
    state.rememberKey = false;
    state.getUIContext = () => ({ getHostContext: () => ({}) });
    state.localEngine.start = async () => ({ url: 'http://127.0.0.1:1234/?token=fixture', workspaceDir: '/phone/workspace' });
    state.client.connect = async () => {};
    state.client.describeCredentials = async refs => {
      assert.equal(refs.join(), 'DEEPSEEK_API_KEY'); checks++;
      return { DEEPSEEK_API_KEY: { configured } };
    };
    state.client.watchWorkspaces = async () => {};
    state.finishOnboarding = async () => {};
    state.refreshSessions = async () => {};
    state.errorMessage = error => error.message;
    assert.equal(await Owner.prototype.connect.call(state), configured);
    assert.equal(checks, 1);
    assert.equal(state.connected, configured);
    assert.equal(state.localConfigured, configured);
    if (!configured) assert.match(state.errorText, /重新输入/);
  }
});

test('disconnect during post-login workspace loading cannot report a successful connection', async () => {
  const { state } = fixture();
  state.mode = 'remote'; state.connected = false; state.address = remote.launchUrl; state.authorization = '';
  state.client.connect = async () => {};
  state.finishOnboarding = async () => {};
  state.client.watchWorkspaces = async () => { await state.disconnect(false, 'remoteHosts'); };
  state.refreshSessions = async () => { throw new Error('stale connection must not refresh'); };
  assert.equal(await Owner.prototype.connect.call(state), false);
  assert.equal(state.page, 'remoteHosts');
});

test('the account entry can start the local engine without accessing API key storage', async () => {
  const { state } = fixture();
  state.connected = false; state.localConfigured = false; state.engineReady = false;
  state.hasSavedKey = true; state.rememberKey = true;
  state.getUIContext = () => ({ getHostContext: () => ({}) });
  state.localEngine.start = async () => ({ url: 'http://127.0.0.1:1234/?token=fixture', workspaceDir: '/phone/workspace' });
  state.client.connect = async (_url, _authorization, local) => assert.equal(local, true);
  state.client.watchWorkspaces = async () => {};
  state.finishOnboarding = async () => {};
  state.refreshSessions = async () => {};
  assert.equal(await Owner.prototype.connect.call(state, undefined, undefined, false, true), true);
  assert.equal(state.connected, true);
  assert.equal(state.localConfigured, false);
  assert.equal(state.hasSavedKey, true);
});

test('disconnect during onboarding save does not start streams on a stale connection', async () => {
  const { state } = fixture();
  state.mode = 'remote'; state.connected = false; state.address = remote.launchUrl; state.authorization = '';
  state.client.connect = async () => {};
  state.finishOnboarding = async () => { await state.disconnect(false, 'remoteHosts'); };
  state.client.watchWorkspaces = async () => { throw new Error('stale workspace stream'); };
  assert.equal(await Owner.prototype.connect.call(state), false);
  assert.equal(state.page, 'remoteHosts');
});
