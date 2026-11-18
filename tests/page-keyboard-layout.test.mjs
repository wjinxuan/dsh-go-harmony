import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const terminalSource = readFileSync(new URL('../entry/src/main/ets/ui/TerminalPanel.ets', import.meta.url), 'utf8');
const KeyboardAvoidMode = { OFFSET: 0, RESIZE: 1, OFFSET_WITH_CARET: 2, RESIZE_WITH_CARET: 3, NONE: 4 };

// Execute actual page lifecycle/route methods against the UIContext boundary.
// Phone389 proved OFFSET exposes the editor but covers the action row below it.
// These tests do not simulate native keyboard geometry or claim phone acceptance.
function methods(text, names, indent, optional = []) {
  return names.concat(optional).map(name => {
    const found = text.match(new RegExp('^ {' + indent + '}(?:private )?' + name + '\\([^]*?^ {' + indent + '}\\}', 'm'));
    if (!optional.includes(name)) assert.ok(found, name);
    return found?.[0] || '';
  }).join('\n');
}
function classes(indexText, terminalText, indent) {
  const body = methods(indexText, ['aboutToAppear', 'aboutToDisappear', 'voicePageChanged'], indent,
    ['updateKeyboardAvoidance', 'restoreKeyboardAvoidance']);
  const noop = () => {};
  const Owner = Function('KeyboardAvoidMode', 'registerDshFonts', 'PerformanceMonitor', 'createUsageStats',
    'loadSpeechMode', 'loadAdvancedPreferences', 'loadQuickPanelPreferences', 'loadAppPreferences',
    'return ' + stripTypeScriptTypes('(class Owner {' + body + '})'))(
    KeyboardAvoidMode, noop, class { async start() {} stop() {} },
    () => ({ async foreground() {} }), async () => 'auto', async () => ({}), async () => ({}), async () => ({}));
  const Terminal = Function('KeyboardAvoidMode', 'TerminalApi', 'return ' + stripTypeScriptTypes('(class Terminal {' +
    methods(terminalText, ['aboutToAppear', 'aboutToDisappear'], indent) + '})'))(KeyboardAvoidMode, class {});
  return { Owner, Terminal };
}
function fixture(Classes, initialMode = 0, page = 'loading') {
  let mode = initialMode;
  const writes = [], voice = [];
  const context = { getKeyboardAvoidMode: () => mode, setKeyboardAvoidMode(value) { mode = value; writes.push(value); }, getHostContext: () => ({}) };
  const noop = () => {};
  const owner = Object.assign(new Classes.Owner(), {
    page, getUIContext: () => context, mentions: { reset: noop }, updateColors: noop, initializeVoice: noop,
    loadStartup: noop, pendingLaunchChanged: noop, retireRegeneration: noop, releaseTransport: noop,
    clearAttachments: noop, localEngine: { async stop() {} }, client: { close: noop }, composerDrafts: { clear: noop },
    questionDrafts: new Map(), sessionId: 'owned-chat',
    voice: { cancel() { voice.push('cancel'); }, setContext() { voice.push('context'); }, async refresh() { voice.push('refresh'); }, dispose: noop }
  });
  const terminal = Object.assign(new Classes.Terminal(), {
    getUIContext: () => context, client: { connectionIdentity: () => 1 }, sessionId: 'owned-terminal', bridge: {},
    reload: noop, revision: 0, retains: new Map(), retaining: new Set(), controller: { deleteJavaScriptRegister: noop }
  });
  return { owner, terminal, writes, voice, mode: () => mode, external(value) { mode = value; },
    route(value) { owner.page = value; owner.voicePageChanged(); } };
}
function cases(label, Classes) {
  test(label + ': initial chat resizes the full page so editor and send row share the visible viewport', () => {
    const f = fixture(Classes, 0, 'chat'); f.owner.aboutToAppear();
    assert.equal(f.mode(), KeyboardAvoidMode.RESIZE, 'phone389: OFFSET leaves the send/attachment row below the keyboard');
    assert.deepEqual(f.writes, [KeyboardAvoidMode.RESIZE]);
  });
  test(label + ': non-chat initial page preserves its original policy until entering chat or terminal', () => {
    const f = fixture(Classes, KeyboardAvoidMode.OFFSET_WITH_CARET, 'settings'); f.owner.aboutToAppear();
    assert.deepEqual(f.writes, []); assert.equal(f.mode(), KeyboardAvoidMode.OFFSET_WITH_CARET);
    f.route('terminal'); assert.equal(f.mode(), KeyboardAvoidMode.RESIZE);
    f.route('features'); assert.equal(f.mode(), KeyboardAvoidMode.OFFSET_WITH_CARET);
  });
  test(label + ': chat and terminal transitions have one owner even when old child disposal arrives late', () => {
    const f = fixture(Classes, 0, 'chat'); f.owner.aboutToAppear();
    f.route('terminal'); f.terminal.aboutToAppear();
    f.route('chat'); f.terminal.aboutToDisappear();
    assert.equal(f.mode(), KeyboardAvoidMode.RESIZE);
    assert.deepEqual(f.writes, [KeyboardAvoidMode.RESIZE], 'child lifecycle must not save/restore the shared page policy');
    f.route('settings'); assert.deepEqual(f.writes, [KeyboardAvoidMode.RESIZE, 0]);
    f.terminal.aboutToDisappear(); assert.equal(f.mode(), 0, 'late terminal callback cannot reclaim the page');
  });
  test(label + ': leaving either managed route restores every captured baseline including OFFSET zero', () => {
    for (const initial of Object.values(KeyboardAvoidMode)) {
      const f = fixture(Classes, initial, 'chat'); f.owner.aboutToAppear();
      f.route('terminal'); f.route('models'); assert.equal(f.mode(), initial);
      assert.deepEqual(f.writes, [KeyboardAvoidMode.RESIZE, initial]);
      f.external(KeyboardAvoidMode.NONE); f.route('chat'); f.route('settings');
      assert.equal(f.mode(), KeyboardAvoidMode.NONE, 'new ownership interval captures the current baseline');
    }
  });
  test(label + ': disposal restores once and late route callbacks cannot start a new ownership interval', () => {
    const f = fixture(Classes, 0, 'terminal'); f.owner.aboutToAppear(); f.owner.aboutToDisappear();
    assert.equal(f.mode(), 0); assert.deepEqual(f.writes, [KeyboardAvoidMode.RESIZE, 0]);
    f.owner.aboutToDisappear(); f.route('chat'); assert.deepEqual(f.writes, [KeyboardAvoidMode.RESIZE, 0]);
  });
  test(label + ': leaving preserves a newer external mode instead of overwriting it', () => {
    const f = fixture(Classes, 0, 'chat'); f.owner.aboutToAppear(); f.external(KeyboardAvoidMode.NONE);
    f.route('settings'); f.owner.aboutToDisappear();
    assert.equal(f.mode(), KeyboardAvoidMode.NONE); assert.deepEqual(f.writes, [KeyboardAvoidMode.RESIZE]);
  });
  test(label + ': the DS Bot route also resizes so its pinned composer stays above the keyboard', () => {
    const f = fixture(Classes, 0, 'chat'); f.owner.aboutToAppear();
    f.route('dsBot'); assert.equal(f.mode(), KeyboardAvoidMode.RESIZE, 'dsBot keeps the resize policy');
    assert.deepEqual(f.writes, [KeyboardAvoidMode.RESIZE]);
    f.route('settings'); assert.equal(f.mode(), 0, 'leaving dsBot restores the captured baseline');
  });
  test(label + ': route updates before initialization are safe and existing voice route behavior remains', () => {
    const f = fixture(Classes, 0, 'loading'); f.route('chat'); assert.deepEqual(f.writes, []);
    f.owner.aboutToAppear(); assert.equal(f.mode(), KeyboardAvoidMode.RESIZE);
    f.voice.length = 0; f.route('settings'); f.route('chat');
    assert.deepEqual(f.voice, ['cancel', 'context', 'refresh']);
  });
}
cases('source', classes(source, terminalSource, 2));
if (process.argv[2]) {
  const index = process.argv[2];
  cases('actual CompileArkTS output', classes(readFileSync(index, 'utf8'),
    readFileSync(join(dirname(index), '../ui/TerminalPanel.ts'), 'utf8'), 4));
}
