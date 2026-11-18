import { localizedSettingsText as t, localizedSettingsFormat as f } from './settings-locale-fixture.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const methods = (start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)));
const code = methods('  private async showModels(', '  private home(') +
  methods('  private showSettings(', '  private async showModels(') +
  methods('  private async newSession(', '  private async stop(');
const slash = readFileSync(new URL('../entry/src/main/ets/ui/SlashCommands.ets', import.meta.url), 'utf8')
  .replace(/^import .*\n/gm, '').replace(/^export /gm, '');
const composerDrafts = readFileSync(new URL('../entry/src/main/ets/ui/ComposerDrafts.ets', import.meta.url), 'utf8')
  .replace(/^export /gm, '');
const regeneration = readFileSync(new URL('../entry/src/main/ets/ui/MessageRegeneration.ets', import.meta.url), 'utf8')
  .replace(/^import .*\n/gm, '').replace(/^export /gm, '');
const newChatOptions = readFileSync(new URL('../entry/src/main/ets/ui/NewChatOptionsData.ets', import.meta.url), 'utf8')
  .replace(/^import .*\n/gm, '').replace(/^export /gm, '');
const deletedAttachments = [];
const Owner = vm.runInNewContext(stripTypeScriptTypes(`${slash}\n${composerDrafts}\n${regeneration}\n${newChatOptions}\n(class Owner {
    composerDrafts = new ComposerDrafts();
    ${code}
  })`), {
  object: value => value && typeof value === 'object' ? value : {},
  array: value => Array.isArray(value) ? value : [],
  string: value => typeof value === 'string' ? value : '',
  modelSelection: value => value?.provider && value?.model ? value : undefined,
  setTimeout, util: { generateRandomUUID: () => 'stable-fixture-request' },
  MAX_ATTACHMENTS: 9, MAX_ATTACHMENT_TOTAL: 400 * 1024 * 1024,
  resendImages: async (_client, _session, message) => message.testImages || [],
  deleteAttachments: files => deletedAttachments.push(...files.map(file => file.id)),
  loadNewChatSetup: async (context, scope, id) => context.setups.get(scope + '/' + id) || { preset: '', permission: '' },
  saveNewChatSetup: async (context, scope, id, modes) => { context.setups.set(scope + '/' + id, { ...modes }); }
});

function fixture() {
  const owner = new Owner();
  const calls = { created: 0, selected: 0, prompts: [] };
  const context = { cacheDir: '/fixture', setups: new Map() };
  Object.assign(owner, {
    t, f, recordUsage() {},
    newPreset: '', newPermission: '', owedNewChatModes: new Map(), cotTranslations: { clear() {} }, remoteHostScope: 'fixture',
    mode: 'remote', connected: true, busy: false, loadingChat: false, sending: false, running: false,
    connectionVersion: 1, chatVersion: 1, sessionId: '', sessionTitle: '', currentModel: undefined,
    pendingSessionModel: undefined, pendingModelSessionId: '', draft: 'keep my draft', errorText: '',
    submittedRecoveries: [], visualReplyRequests: new Map(), recoveryRequestIds: new Map(),
    turnNotices: [], queuedPrompts: [], workspaceId: '', sessions: [],
    hostCommands: [], sessionSkills: [],
    draftAttachments: [], attachmentDrafts: new Map(), attachmentRequestIds: new Map(),
    queuedAttachmentDrafts: [], withdrawingAttachmentSessions: [], messages: [], records: [], regenerating: false,
    regenerationVersion: 0, mentions: { reset() {}, pickHighlighted: () => false },
    client: {
      async listAgentPresets() { return []; },
      async permissionPresets() { return { options: [] }; },
      async createSession() { calls.created++; return 'new-session'; },
      async setModel(id, provider, model, reasoningEffort) {
        calls.selected++; return { selected: { provider, model, reasoningEffort } };
      },
      async prompt(id, text) { calls.prompts.push({ id, text }); },
      connectionIdentity: () => 1
    },
    async openSession(id) { owner.sessionId = id; owner.chatVersion++; },
    getUIContext: () => ({ getHostContext: () => context }),
    scrollToLatest() {}, errorMessage: (_error, fallback) => fallback
  });
  return { owner, calls };
}

test('send chooses a highlighted mention first and then sends its complete wire text', async () => {
  const { owner, calls } = fixture();
  owner.sessionId = 'reference-session'; owner.draft = '@ref';
  const canonical = '@[Referenced](dsh-session:InNlc3Npb24i) ';
  owner.mentions.pickHighlighted = () => { owner.draft = canonical; return true; };
  await owner.send();
  assert.equal(calls.prompts.length, 0);
  assert.equal(owner.draft, canonical);
  owner.mentions.pickHighlighted = () => false;
  await owner.send();
  assert.deepEqual(calls.prompts, [{ id: 'reference-session', text: canonical.trim() }]);
});

test('an active voice draft cannot send, pick files, or remove an attachment queue item', async () => {
  const { owner, calls } = fixture();
  owner.sessionId = 'dictating'; owner.voice = { active: true };
  owner.client.updateQueue = async () => { throw new Error('voice must block queue removal'); };
  await owner.send();
  await owner.chooseAttachments('files');
  await owner.withdrawAttachmentPrompt('dictating', 1, { id: 'queued' });
  assert.equal(calls.prompts.length, 0);
  assert.equal(owner.choosingAttachments, undefined);
  assert.equal(owner.withdrawingAttachmentSessions.length, 0);
});

test('an acknowledged attachment prompt can be withdrawn into its original conversation after switching', async () => {
  const { owner } = fixture();
  const file = { id: 'withdraw-file', name: 'report.txt' };
  Object.assign(owner, { sessionId: 'original', draft: '', draftAttachments: [file] });
  owner.attachmentDrafts.set('original', [file]);
  owner.client.promptWithAttachments = async () => false;
  await owner.send();
  assert.equal(deletedAttachments.includes(file.id), false);
  assert.equal(owner.draftAttachments.length, 0);
  owner.sessionId = 'new'; owner.chatVersion++;
  owner.draft = 'different conversation';
  const item = { requestId: 'stable-fixture-request', text: '', hasAttachments: true };
  owner.recoverQueueDrafts('original', 0, [item]);
  assert.equal(owner.attachmentDrafts.has('original'), false);
  owner.recoverQueueDrafts('original', 1, [item]);
  assert.equal(owner.draft, 'different conversation');
  assert.equal(owner.attachmentDrafts.get('original')[0], file);
  assert.equal(owner.queuedAttachmentDrafts.length, 0);
});

test('regeneration forks before the original prompt and sends there while retaining the original draft', async () => {
  const { owner, calls } = fixture();
  const prompt = { id: 'prompt', seq: 3, role: 'user', text: 'original question', content: [{ type: 'text', text: 'original question' }] };
  const reply = { id: 'reply', seq: 4, role: 'assistant', text: 'original reply' };
  owner.sessionId = 'source'; owner.sessionTitle = 'title'; owner.messages = [prompt, reply];
  owner.records = [{ seq: 0, type: 'session/title', data: {} }, { seq: 1, type: 'turn/start', data: {} },
    { seq: 2, type: 'step/start', data: {} }, { seq: 3, type: 'user/message', data: prompt },
    { seq: 4, type: 'assistant/message', data: { message: { content: [{ type: 'text', text: reply.text }] } } },
    { seq: 5, type: 'turn/end', data: { reason: { kind: 'completed' } } }];
  owner.client.forkSession = async (id, cut) => { assert.equal(id, 'source'); assert.equal(cut, 0); return 'fork'; };
  owner.client.sessionProjections = async () => ({ values: {} });
  owner.openSession = async id => {
    owner.composerDrafts.write(owner.sessionId, owner.draft);
    owner.sessionId = id; owner.chatVersion++; owner.draft = owner.composerDrafts.read(id);
  };
  await owner.regenerateReply(reply);
  assert.equal(calls.prompts.length, 1);
  assert.deepEqual(calls.prompts[0], { id: 'fork', text: 'original question' });
  assert.equal(owner.composerDrafts.read('source'), 'keep my draft');
  assert.equal(owner.regenerating, false);
});

test('attachment cache is released only after the matching durable user echo, including an early echo', async () => {
  for (const early of [true, false]) {
    const { owner } = fixture();
    const file = { id: `echo-${early}`, name: 'report.txt' };
    Object.assign(owner, { sessionId: 'open', draftAttachments: [file] });
    owner.attachmentDrafts.set('open', [file]);
    const message = { role: 'user', requestId: 'stable-fixture-request' };
    owner.client.promptWithAttachments = async () => {
      if (early) owner.messages = [message];
      return false;
    };
    await owner.send();
    if (!early) {
      owner.releaseCommittedAttachments('other', [message]);
      owner.releaseCommittedAttachments('open', [{ ...message, role: 'assistant' }]);
      assert.equal(deletedAttachments.includes(file.id), false);
      owner.releaseCommittedAttachments('open', [message]);
    }
    assert.equal(deletedAttachments.filter(id => id === file.id).length, 1);
    assert.equal(owner.queuedAttachmentDrafts.length, 0);
  }
});

test('withdrawing an attachment message restores files beside text already in the composer', async () => {
  const { owner } = fixture();
  const file = { id: 'queued-image', name: 'photo.png' };
  owner.sessionId = 'open';
  owner.queuedAttachmentDrafts = [{ sessionId: 'open', requestId: 'queued', files: [file] }];
  owner.recoverQueueDrafts('open', 1, [{ requestId: 'queued', text: 'older prompt text', hasAttachments: true }]);
  assert.equal(owner.draft, 'keep my draft');
  assert.equal(owner.draftAttachments[0], file);
  assert.equal(owner.attachmentDrafts.get('open')[0], file);
});

test('a pending attachment withdrawal blocks sends and file selection until the host confirms', async () => {
  const { owner, calls } = fixture();
  const file = { id: 'queued-during-withdrawal', name: 'report.txt' };
  owner.sessionId = 'open';
  owner.queuedAttachmentDrafts = [{ sessionId: 'open', requestId: 'queued', files: [file] }];
  let release;
  owner.client.updateQueue = () => new Promise(resolve => { release = resolve; });
  const withdrawal = owner.withdrawAttachmentPrompt('open', 1, { id: 'inbox', requestId: 'queued',
    text: '', hasAttachments: true });
  await owner.send();
  await owner.chooseAttachments('photos');
  assert.equal(calls.prompts.length, 0);
  assert.equal(owner.errorText, '');
  release();
  await withdrawal;
  assert.equal(owner.draftAttachments[0], file);
  assert.equal(owner.withdrawingAttachmentSessions.length, 0);
});

test('failed immediate queue moves preserve all removed attachments and the newer draft', async () => {
  const { owner } = fixture();
  owner.sessionId = 'open';
  const existing = { id: 'newer', size: 1 };
  const first = { id: 'first', size: 1 };
  const second = { id: 'second', size: 1 };
  owner.attachmentDrafts.set('open', [existing]);
  owner.draftAttachments = [existing];
  owner.queuedAttachmentDrafts = [
    { sessionId: 'open', requestId: 'a', files: [first] },
    { sessionId: 'open', requestId: 'b', files: [second] }
  ];
  owner.client.sendQueuedNow = async (id, selected, files) => {
    assert.equal(id, 'open');
    assert.equal(files('a')[0], first);
    assert.equal(files('b')[0], second);
    return { sent: false, recoverable: [{ requestId: 'a', text: 'first text' }, { requestId: 'b', text: 'second text' }] };
  };
  const result = await owner.sendQueuedImmediately('open', 1, { id: 'inbox' });
  assert.equal(result.recoverable.length, 0);
  assert.equal(owner.draft, 'keep my draft\n\nfirst text\n\nsecond text');
  assert.deepEqual([...owner.draftAttachments], [existing, first, second]);
  assert.equal(owner.queuedAttachmentDrafts.length, 0);
  assert.equal(owner.withdrawingAttachmentSessions.length, 0);
});

test('restored oversized attachment groups stay editable and are not submitted together', async () => {
  const { owner, calls } = fixture();
  owner.sessionId = 'open';
  owner.draftAttachments = Array.from({ length: 10 }, (_, index) => ({ id: `${index}`, size: 1 }));
  await owner.send();
  assert.equal(calls.prompts.length, 0);
  assert.match(owner.errorText, /分批发送/);
  assert.equal(owner.draftAttachments.length, 10);
});

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
  await new Promise(resolve => setImmediate(resolve));
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
  await new Promise(resolve => setImmediate(resolve));
  owner.chatVersion += 2; owner.currentModel = { provider: 'new-choice', model: 'kept' };
  release({ selected: { provider: 'account', model: 'chosen' } });
  await sending;
  assert.equal(owner.currentModel.model, 'kept');
  assert.equal(calls.prompts.length, 0);
});

test('a delayed initial transcript cannot send after the user leaves and reopens the created session', async () => {
  const { owner, calls } = fixture(); let release;
  owner.openSession = async id => {
    owner.sessionId = id; owner.chatVersion++;
    await new Promise(resolve => { release = resolve; });
  };
  const sending = owner.send();
  await new Promise(resolve => setImmediate(resolve));
  owner.chatVersion += 2;
  release(); await sending;
  assert.equal(calls.prompts.length, 0);
});

test('a newer home draft survives creation and is not removed after the captured message is sent', async () => {
  const { owner, calls } = fixture(); const drafts = new Map();
  owner.composerDrafts = { read: id => drafts.get(id) || '', write: (id, text) => drafts.set(id, text) };
  owner.openSession = async id => {
    drafts.set('', 'newer home draft'); owner.sessionId = id; owner.chatVersion++; owner.draft = '';
  };
  await owner.send();
  assert.equal(calls.prompts[0].text, 'keep my draft');
  assert.equal(drafts.get(''), 'newer home draft');
});

test('moving a padded draft into a new session leaves no home duplicate, including model failure then retry', async () => {
  for (const failSelection of [false, true]) {
    const { owner, calls } = fixture(); const drafts = new Map();
    owner.draft = '  original message\n';
    owner.currentModel = { provider: 'account', model: 'chosen' };
    owner.composerDrafts = { read: id => drafts.get(id) || '', write: (id, text) => drafts.set(id, text) };
    owner.openSession = async id => {
      drafts.set('', owner.draft); owner.sessionId = id; owner.chatVersion++; owner.draft = '';
    };
    const select = owner.client.setModel;
    if (failSelection) owner.client.setModel = async () => { throw new Error('fixture'); };
    await owner.send();
    assert.equal(drafts.get(''), '');
    if (failSelection) {
      assert.equal(owner.draft, '  original message\n');
      owner.client.setModel = select; await owner.send();
    }
    assert.equal(calls.created, 1);
    assert.equal(calls.prompts.length, 1);
    assert.equal(calls.prompts[0].text, 'original message');
    assert.equal(drafts.get(''), '');
  }
});

test('model management returns to the picker only on its original connection and session', () => {
  const { owner } = fixture(); owner.page = 'models'; owner.settingsRequestVersion = 0;
  owner.showSettings('models'); owner.closeSettings();
  assert.equal(owner.page, 'models');
  owner.showSettings('models'); owner.connectionVersion++; owner.closeSettings();
  assert.equal(owner.page, 'chat');
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

test('slash palette ranks names and aliases, and application entries shadow host commands', async () => {
  const { owner, calls } = fixture();
  owner.hostCommands = [{ name: 'model', label: 'override' }, { name: 'compact', label: '压缩' }];
  owner.sessionSkills = [{ name: 'compact', description: 'shadow' }, { name: 'lint', description: 'Lint' }];
  owner.draft = '/压';
  assert.equal(owner.slashChoices()[0].name, 'compact');
  owner.draft = '/mdl';
  assert.equal(owner.slashChoices()[0].kind, 'app');
  owner.draft = '/'; await owner.send();
  assert.equal(owner.slashChoices().filter(item => item.name === 'compact').length, 1);
  assert.equal(calls.created, 0);
  owner.draft = '/模型'; await owner.send();
  assert.equal(owner.page, 'models');
  assert.equal(owner.draft, '');
  assert.equal(calls.prompts.length, 0);
});

test('active host commands execute through RPC and preserve a newer draft', async () => {
  const { owner, calls } = fixture();
  owner.sessionId = 'open';
  owner.hostCommands = [{ name: 'compact', label: '压缩' }];
  owner.draft = '/压缩';
  let release;
  owner.client.executeCommand = (id, line) => {
    assert.equal(id, 'open'); assert.equal(line, '/compact');
    return new Promise(resolve => { release = resolve; });
  };
  const sent = owner.send();
  await new Promise(resolve => setImmediate(resolve));
  owner.draft = 'next message';
  release({ success: true }); await sent;
  assert.equal(owner.draft, 'next message');
  assert.equal(calls.prompts.length, 0);
});

test('editing a command while model selection is pending prevents execution', async () => {
  const { owner } = fixture();
  owner.sessionId = 'open'; owner.pendingModelSessionId = 'open';
  owner.pendingSessionModel = { provider: 'p', model: 'm' };
  owner.hostCommands = [{ name: 'permission', label: '权限', hint: '预设名' }];
  owner.draft = '/permission read-only';
  let release; let executed = false;
  owner.client.setModel = () => new Promise(resolve => { release = resolve; });
  owner.client.executeCommand = async () => { executed = true; };
  const sent = owner.send();
  await new Promise(resolve => setImmediate(resolve));
  owner.draft = 'new text'; release({ selected: { provider: 'p', model: 'm' } });
  await sent;
  assert.equal(executed, false);
  assert.equal(owner.draft, 'new text');
});

test('a stale host command catalog cannot populate a different session', async () => {
  const { owner } = fixture();
  owner.sessionId = 'old'; owner.catalogVersion = 0;
  owner.client.listSkills = async () => [];
  let release;
  owner.client.listCommands = () => new Promise(resolve => { release = resolve; });
  const loading = owner.loadCommandCatalog();
  owner.sessionId = 'new'; owner.chatVersion++;
  release([{ name: 'compact', label: '压缩' }]); await loading;
  assert.equal(owner.hostCommands.length, 0);
});

test('the recovery shortcut rejects a plugin that shadows the built-in compact command', () => {
  const { owner } = fixture();
  owner.hostCommands = [{ name: 'compact', label: 'compact', definitionId: 'plugin/custom-compact' }];
  assert.equal(owner.compactCommand(), undefined);
  owner.hostCommands[0].definitionId = '@deepseek-ai/dsh-command-compact';
  assert.equal(owner.compactCommand()?.name, 'compact');
});

test('skill prompts and slash-prefixed paths still use the message route', async () => {
  const { owner, calls } = fixture();
  owner.sessionId = 'open'; owner.sessionSkills = [{ name: 'lint' }];
  owner.draft = '/lint src'; await owner.send();
  owner.draft = '/tmp/example'; await owner.send();
  owner.draft = '/compact'; await owner.send();
  assert.deepEqual(calls.prompts.map(prompt => prompt.text), ['/lint src', '/tmp/example']);
  assert.match(owner.errorText, /没有提供压缩/);
});

test('an attachment-only draft moves to a new session and survives an upload failure', async () => {
  const { owner, calls } = fixture();
  const attachment = { id: 'picked', path: '/cache/fixture', name: 'fixture.txt', size: 10 };
  owner.draft = '';
  owner.draftAttachments = [attachment];
  owner.attachmentDrafts.set('', [{ ...attachment }]);
  owner.openSession = async id => {
    owner.sessionId = id;
    owner.chatVersion++;
    owner.draftAttachments = [];
  };
  const requests = [];
  owner.client.promptWithAttachments = async (id, text, files, request) => {
    requests.push(request);
    assert.equal(id, 'new-session');
    assert.equal(text, '');
    assert.equal(files[0].id, attachment.id);
    throw new Error('fixture upload failure');
  };
  await owner.send();
  await owner.send();
  assert.equal(calls.created, 1);
  assert.equal(requests.length, 2);
  assert.equal(requests[0], requests[1]);
  assert.equal(owner.draftAttachments[0].id, attachment.id);
  assert.equal(owner.attachmentDrafts.has(''), false);
});

function regenerationFixture(images = []) {
  const { owner, calls } = fixture();
  owner.regenerationVersion = 0;
  const prompt = { id: 'prompt', seq: 3, role: 'user', text: 'original question',
    content: [{ type: 'text', text: 'original question' }], testImages: images };
  const reply = { id: 'reply', seq: 4, role: 'assistant', text: 'original reply' };
  owner.sessionId = 'source'; owner.sessionTitle = 'title'; owner.messages = [prompt, reply];
  owner.records = [{ seq: 0, type: 'session/title', data: {} }, { seq: 1, type: 'turn/start', data: {} },
    { seq: 2, type: 'step/start', data: {} }, { seq: 3, type: 'user/message', data: prompt },
    { seq: 4, type: 'assistant/message', data: { message: { content: [{ type: 'text', text: reply.text }] } } },
    { seq: 5, type: 'turn/end', data: { reason: { kind: 'completed' } } }];
  calls.forks = []; calls.opens = [];
  owner.client.forkSession = async (id, cut) => { calls.forks.push({ id, cut }); return 'fork'; };
  owner.client.sessionProjections = async () => ({ values: {} });
  owner.client.promptWithAttachments = async (id, text, files) => {
    calls.prompts.push({ id, text, files }); return false;
  };
  owner.openSession = async id => {
    calls.opens.push(id);
    owner.composerDrafts.write(owner.sessionId, owner.draft);
    owner.sessionId = id; owner.chatVersion++;
    owner.draft = owner.composerDrafts.read(id);
    owner.draftAttachments = owner.attachmentDrafts.get(id) || [];
  };
  return { owner, calls, prompt, reply };
}

test('regeneration does not automatically send a child draft edited while the conversation opens', async () => {
  const { owner, calls, reply } = regenerationFixture();
  const opening = Promise.withResolvers();
  const open = owner.openSession;
  owner.openSession = async id => { await open(id); await opening.promise; };
  const regenerating = owner.regenerateReply(reply);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(owner.sessionId, 'fork');
  owner.draft = 'my corrected question';
  opening.resolve(); await regenerating;
  assert.equal(calls.prompts.length, 0);
  assert.equal(owner.draft, 'my corrected question');
  assert.match(owner.errorText, /草稿已修改/);
  assert.equal(owner.composerDrafts.read('source'), 'keep my draft');
});

test('regeneration does not reattach or send an image removed while the child opens', async () => {
  const file = { id: 'regeneration-removed', path: '/cache/removed', size: 3, mediaType: 'image/png' };
  const { owner, calls, reply } = regenerationFixture([file]);
  const opening = Promise.withResolvers();
  const open = owner.openSession;
  owner.openSession = async id => { await open(id); await opening.promise; };
  const regenerating = owner.regenerateReply(reply);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(owner.draftAttachments[0], file);
  owner.removeAttachment(file);
  opening.resolve(); await regenerating;
  assert.equal(calls.prompts.length, 0);
  assert.equal(owner.draft, 'original question');
  assert.equal(owner.draftAttachments.length, 0);
  assert.equal(owner.attachmentDrafts.get('fork').length, 0);
  assert.equal(deletedAttachments.filter(id => id === file.id).length, 1);
  assert.match(owner.errorText, /草稿已修改/);
});

test('regeneration waits for review when the opened child already has a turn or queue', async () => {
  for (const state of ['running', 'queued']) {
    const { owner, calls, reply } = regenerationFixture();
    const open = owner.openSession;
    owner.openSession = async id => {
      await open(id);
      if (state === 'running') owner.running = true;
      else owner.queuedPrompts = [{ id: 'inherited' }];
    };
    await owner.regenerateReply(reply);
    assert.equal(calls.prompts.length, 0);
    assert.equal(owner.draft, 'original question');
    assert.match(owner.errorText, /检查后再发送/);
    assert.equal(owner.regenerationSourceId, 'source');
  }
});

test('switching host or conversation during original-image preparation cancels regeneration cleanly', async () => {
  for (const changed of ['host', 'conversation']) {
    const images = Promise.withResolvers();
    const file = { id: `regeneration-image-switch-${changed}`, path: '/cache/stale', size: 3, mediaType: 'image/png' };
    const { owner, calls, reply } = regenerationFixture(images.promise);
    const regenerating = owner.regenerateReply(reply);
    if (changed === 'host') owner.connectionVersion++;
    else { owner.sessionId = 'other'; owner.chatVersion++; }
    owner.draft = 'newer draft'; owner.errorText = 'newer status';
    images.resolve([file]); await regenerating;
    assert.deepEqual(calls.forks, []);
    assert.deepEqual(calls.opens, []);
    assert.equal(calls.prompts.length, 0);
    assert.equal(owner.draft, 'newer draft');
    assert.equal(owner.errorText, 'newer status');
    assert.equal(owner.composerDrafts.read('fork'), '');
    assert.equal(owner.attachmentDrafts.has('fork'), false);
    assert.equal(deletedAttachments.filter(id => id === file.id).length, 1);
  }
});

test('a late fork result cannot open or populate a conversation after a host or session switch', async () => {
  for (const changed of ['host', 'conversation']) {
    const file = { id: `regeneration-fork-switch-${changed}`, path: '/cache/stale', size: 3, mediaType: 'image/png' };
    const { owner, calls, reply } = regenerationFixture([file]);
    const forking = Promise.withResolvers();
    let projections = 0;
    owner.client.forkSession = () => forking.promise;
    owner.client.sessionProjections = async () => { projections++; return { values: {} }; };
    const regenerating = owner.regenerateReply(reply);
    await new Promise(resolve => setImmediate(resolve));
    if (changed === 'host') owner.connectionVersion++;
    else { owner.sessionId = 'other'; owner.chatVersion++; }
    owner.draft = 'newer draft'; owner.errorText = 'newer status';
    forking.resolve('late-fork'); await regenerating;
    assert.equal(projections, 0);
    assert.deepEqual(calls.opens, []);
    assert.equal(calls.prompts.length, 0);
    assert.equal(owner.draft, 'newer draft');
    assert.equal(owner.errorText, 'newer status');
    assert.equal(owner.composerDrafts.read('late-fork'), '');
    assert.equal(owner.attachmentDrafts.has('late-fork'), false);
    assert.equal(deletedAttachments.filter(id => id === file.id).length, 1);
  }
});

test('regeneration retires on a new generation of the same connected client', async () => {
  for (const stage of ['images', 'fork']) {
    const delayed = Promise.withResolvers();
    const { owner, calls, reply } = regenerationFixture(stage === 'images' ? delayed.promise : []);
    let generation = 1;
    owner.client.connectionIdentity = () => generation;
    if (stage === 'fork') owner.client.forkSession = () => delayed.promise;
    const regenerating = owner.regenerateReply(reply);
    await new Promise(resolve => setImmediate(resolve));
    generation++;
    owner.draft = 'newer draft'; owner.errorText = 'reconnected';
    delayed.resolve(stage === 'images' ? [] : 'old-generation-fork');
    await regenerating;
    assert.deepEqual(calls.opens, []);
    assert.equal(calls.prompts.length, 0);
    assert.equal(owner.draft, 'newer draft');
    assert.equal(owner.errorText, 'reconnected');
    assert.equal(owner.composerDrafts.read('old-generation-fork'), '');
  }
});

test('regeneration submits a captured slash-prefixed prompt as model text', async () => {
  const { owner, calls, prompt, reply } = regenerationFixture();
  prompt.text = '/model'; prompt.content = [{ type: 'text', text: '/model' }];
  await owner.regenerateReply(reply);
  assert.deepEqual(calls.prompts, [{ id: 'fork', text: '/model' }]);
  assert.notEqual(owner.page, 'models');
});

test('navigating away from a pending regeneration permits sending in the newly opened conversation', async () => {
  const images = Promise.withResolvers();
  const { owner, calls, reply } = regenerationFixture(images.promise);
  owner.client.listCommands = async () => [];
  owner.client.listSkills = async () => [];
  owner.client.watchSession = async (id, publish) => {
    publish({ sessionId: id, messages: [], records: [], notices: [], running: false });
  };
  const regenerating = owner.regenerateReply(reply);
  await Owner.prototype.openSession.call(owner, 'other', 'Other conversation');
  owner.draft = 'send in the new conversation';
  await owner.send();
  assert.deepEqual(calls.prompts, [{ id: 'other', text: 'send in the new conversation' }]);
  images.resolve([]); await regenerating;
  assert.deepEqual(calls.forks, []);
});

test('an old regeneration finally cannot release the busy state owned by a newer regeneration', async () => {
  const firstImages = Promise.withResolvers();
  const secondImages = Promise.withResolvers();
  const { owner, calls, reply } = regenerationFixture(firstImages.promise);
  owner.client.listCommands = async () => [];
  owner.client.listSkills = async () => [];
  owner.client.watchSession = async (id, publish) => {
    publish({ sessionId: id, messages: [], records: [], notices: [], running: false });
  };
  const first = owner.regenerateReply(reply);
  await Owner.prototype.openSession.call(owner, 'other', 'Other conversation');
  const next = regenerationFixture(secondImages.promise);
  owner.messages = next.owner.messages; owner.records = next.owner.records;
  const second = owner.regenerateReply(next.reply);
  assert.equal(owner.regenerating, true);
  firstImages.resolve([]); await first;
  assert.equal(owner.regenerating, true);
  assert.equal(calls.prompts.length, 0);
  secondImages.resolve([]); await second;
  assert.equal(owner.regenerating, false);
  assert.deepEqual(calls.prompts, [{ id: 'fork', text: 'original question' }]);
});

test('new-chat picks are confirmed before first prompt and failed permission remains owed on retry', async () => {
  const { owner, calls } = fixture();
  const events = [];
  owner.newPreset = 'chosen'; owner.newPermission = 'ask';
  owner.client.listAgentPresets = async () => [{ id: 'chosen', isDefault: true }];
  owner.client.permissionPresets = async () => ({ options: [{ value: 'ask' }] });
  let preset = '', permission = '', reject = true;
  owner.client.selectAgentPreset = async (id, value) => { events.push('preset'); preset = value; };
  owner.client.setPermissionPreset = async (id, value) => { events.push('permission'); if (reject) throw Error('failed'); permission = value; };
  owner.client.sessionProjections = async () => ({ agentPreset: preset, permissionPreset: permission });
  owner.client.prompt = async (id, text) => { events.push('prompt'); calls.prompts.push({ id, text }); };
  await owner.send();
  assert.equal(calls.created, 1); assert.equal(calls.prompts.length, 0); assert.equal(owner.draft, 'keep my draft');
  assert.deepEqual(events, ['preset', 'permission']);
  reject = false;
  await owner.send();
  assert.equal(calls.created, 1);
  assert.deepEqual(events, ['preset', 'permission', 'permission', 'prompt']);
  assert.equal(owner.draft, '');
});

test('restored unconfirmed permission is applied before a later send and read failure prevents sending', async () => {
  const { owner, calls } = fixture();
  owner.sessionId = 'restored';
  const context = owner.getUIContext().getHostContext();
  context.setups.set('fixture/restored', { preset: '', permission: 'ask' });
  let accepted = false;
  owner.client.setPermissionPreset = async () => { accepted = true; };
  owner.client.sessionProjections = async () => ({ permissionPreset: accepted ? 'ask' : '' });
  await owner.send();
  assert.equal(accepted, true); assert.equal(calls.prompts.length, 1);
  owner.draft = 'keep'; context.setups.get = () => { throw Error('storage locked'); };
  await owner.send();
  assert.equal(owner.draft, 'keep'); assert.equal(calls.prompts.length, 1);
});

test('invalid explicit new-chat pick refuses creation and retains the draft', async () => {
  const { owner, calls } = fixture();
  owner.newPermission = 'removed-option';
  await owner.send();
  assert.equal(calls.created, 0); assert.equal(calls.prompts.length, 0); assert.equal(owner.draft, 'keep my draft');
});

test('new chat persists owed settings before opening a view and does not open after a storage failure', async () => {
 const {owner}=fixture();owner.newPreset='chosen';owner.client.listAgentPresets=async()=>[{id:'chosen'}];const context=owner.getUIContext().getHostContext();let opened=false;
 owner.openSession=async id=>{opened=true;assert.ok(context.setups.has('fixture/'+id),'settings must already be durable before opening');throw new Error('simulated view failure');};
 assert.equal(await owner.newSession(),false);assert.equal(opened,true);assert.ok(context.setups.has('fixture/new-session'));
 const failed=fixture();failed.owner.getUIContext=()=>({getHostContext:()=>({setups:{set(){throw new Error('storage full');}}})});
 let failedOpened=false;failed.owner.openSession=async()=>{failedOpened=true;};assert.equal(await failed.owner.newSession(),false);assert.equal(failedOpened,false);
 assert.equal(failed.owner.draft,'keep my draft');assert.ok(failed.owner.owedNewChatModes.has(JSON.stringify(['fixture','new-session'])));assert.deepEqual(failed.calls.prompts,[]);
});
