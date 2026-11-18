import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';
import { localizedSettingsText, localizedSettingsFormat } from './settings-locale-fixture.mjs';
import { util } from './mention-fixture.mjs';

const read = name => readFileSync(new URL(`../entry/src/main/ets/ui/${name}.ets`, import.meta.url), 'utf8');
const removeImports = source => source.replace(/^import\b[\s\S]*?from ['"][^'"]+['"]\s*\n/gm, '');
const component = (name, boundary = '\n  build()') => removeImports(read(name).split(boundary)[0])
  .replace('@Component\nexport struct', 'class')
  .replace(/@StorageProp\('dshLanguage'\) /g, '')
  .replace(/@Prop\s*(?:@Watch\('[^']+'\)\s*)?/g, '')
  .replace(/  @Builder\n  private chip\([\s\S]*?\n  }\n/, '') + '\n}';

class NativeEditor {
  spans = [];
  selection = [0, 0];
  deleteSpans() { this.spans = []; }
  addTextSpan(value, options) { this.spans.push({ value, style: options.style }); }
  addBuilderSpan() { this.spans.push({ builder: true }); }
  setTypingStyle() {}
  setSelection(start, end) { this.selection = [start, end]; }
  getSelection() { return { selection: this.selection }; }
  getSpans({ start, end }) {
    const result = []; let offset = 0;
    for (const span of this.spans) {
      const length = typeof span.value === 'string' ? span.value.length : 1;
      if (start < offset + length && offset < end && !span.builder) {
        result.push({ ...span, offsetInSpan: [Math.max(0, start - offset), Math.min(length, end - offset)] });
      }
      offset += length;
    }
    return result;
  }
}
let writeClipboard = async () => {};
const { MentionEditor, MentionPickerPanel, formatSessionMention, mentionDisplayOffset } = vm.runInNewContext(
  stripTypeScriptTypes(removeImports(read('MentionData')).replace(/^export /gm, '') + '\n' + component('MentionEditor') + '\n' +
    component('MentionPickerPanel', '\n  @Builder') + '\n({ MentionEditor, MentionPickerPanel, formatSessionMention, mentionDisplayOffset })'), {
    localizedSettingsText, localizedSettingsFormat, util, RichEditorController: NativeEditor, themeColors: () => ({ text: '#000', muted: '#888' }),
    DshClient: class { connectionIdentity() { return 1; } async listSessions() { return []; } },
    pasteboard: { MIMETYPE_TEXT_PLAIN: 'text/plain', createData: (type, text) => ({ type, text }),
      getSystemPasteboard: () => ({ setData: data => writeClipboard(data) }) },
    KeyType: { Down: 0 }, KeyCode: { KEYCODE_ENTER: 13 }, setTimeout, clearTimeout
  });

function editor(text = '') {
  const view = new MentionEditor();
  view.active = true; view.ready = true;
  view.controller.composer.restore(text); view.paint();
  return view;
}
function deferred() {
  let resolve; const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

test('native mixed text/image paste removes untracked positions before the following edit', () => {
  const view = editor();
  view.editor.spans = [{ value: 'A' }, { image: true }, { value: 'BC' }];
  view.pasting = true;
  view.edited({ start: 0, end: 0 }, { start: 0, end: 4 });
  assert.equal(view.controller.composer.text, 'ABC');
  assert.deepEqual(view.editor.spans.map(span => span.value), ['ABC']);
  view.editor.spans = [{ value: 'AXBC' }];
  view.edited({ start: 1, end: 1 }, { start: 1, end: 2 });
  assert.equal(view.controller.composer.text, 'AXBC');
});

test('paste keeps literal plain text and reconstructs atomic references without copied styles', () => {
  const view = editor(), raw = formatSessionMention('s', 'Title');
  const pasted = `**literal**\n${raw} @README.md`;
  view.editor.spans = [{ value: pasted, style: { fontColor: 'red' } }]; view.pasting = true;
  view.edited({ start: 0, end: 0 }, { start: 0, end: pasted.length });
  assert.equal(view.controller.composer.text, pasted);
  assert.equal(view.editor.spans.filter(span => span.builder).length, 2);
  assert.equal(view.editor.spans[0].style.fontColor, '#000');
  const first = view.controller.composer.tokens[0];
  const display = mentionDisplayOffset(first.start, view.controller.composer.tokens);
  view.edited({ start: display, end: display + 1 }, { start: display, end: display });
  assert.equal(view.controller.composer.text, '**literal**\n @README.md');
});

test('preview text remains native while composing and the committed text is preserved', () => {
  const view = editor();
  view.pasting = true; // An empty clipboard does not emit onDidChange; its marker must not disrupt the next IME edit.
  assert.equal(view.willChange({ rangeBefore: { start: 0, end: 0 }, replacedSpans: [{ previewText: 'ni' }],
    replacedImageSpans: [], replacedSymbolSpans: [] }), true);
  view.editor.spans = [{ value: 'ni', previewText: 'ni' }];
  view.edited({ start: 0, end: 0 }, { start: 0, end: 2 });
  assert.equal(view.editor.spans[0].previewText, 'ni');
  view.composing = false; view.editor.spans = [{ value: '你' }];
  view.edited({ start: 0, end: 2 }, { start: 0, end: 1 });
  assert.equal(view.controller.composer.text, '你');
});

test('an image-only native paste leaves the current selection and text intact', () => {
  const view = editor('selected'); view.controller.composer.select(0, 8);
  assert.equal(view.willChange({ rangeBefore: { start: 0, end: 8 }, replacedSpans: [],
    replacedImageSpans: [{}], replacedSymbolSpans: [] }), false);
  assert.equal(view.controller.composer.text, 'selected');
  assert.equal(view.controller.composer.start, 0); assert.equal(view.controller.composer.end, 8);
});

test('copy preserves full wire text and a completed cut removes the entire selected chip', async () => {
  const raw = formatSessionMention('s', 'Title'), view = editor(`a ${raw} z`);
  view.controller.composer.select(2, 2 + raw.length);
  let copied; writeClipboard = async data => { copied = data; };
  await view.copy(false);
  assert.deepEqual(copied, { type: 'text/plain', text: raw });
  await view.copy(true);
  assert.equal(view.controller.composer.text, 'a  z');
});

test('delayed cuts cannot mutate another session, another host, a restored draft, or a read-only composer', async () => {
  for (const change of [
    view => { view.sessionId = 'new-session'; },
    view => { view.connectionId++; },
    view => { view.controller.composer.restore('same'); view.controller.composer.select(0, 4); },
    view => { view.readOnly = true; },
    view => { view.aboutToDisappear(); }
  ]) {
    const view = editor('same'), gate = deferred();
    view.controller.composer.select(0, 4); writeClipboard = () => gate.promise;
    const cutting = view.copy(true); change(view); gate.resolve(); await cutting;
    assert.equal(view.controller.composer.text, 'same');
  }
});

test('read-only blocks an already-open cut menu and hardware mention selection', async () => {
  const view = editor('same'); view.readOnly = true; view.controller.composer.select(0, 4);
  let writes = 0, keys = 0;
  writeClipboard = async () => { writes++; };
  view.controller.key = () => { keys++; return true; };
  await view.copy(true); view.handleKey({ type: 0, keyCode: 13 });
  assert.equal(writes, 0); assert.equal(keys, 0); assert.equal(view.controller.composer.text, 'same');
});

test('retained picker observers track revision and use current same-key results and highlight', () => {
  const panel = new MentionPickerPanel(), old = { key: 's:1', label: 'Old', detail: '' };
  let reads = 0;
  Object.defineProperty(panel, 'revision', { get() { reads++; return 1; } });
  panel.controller.sections = [{ title: '对话', items: [old] }];
  panel.controller.loading = true;
  assert.equal(panel.loading(), true); assert.equal(panel.items('对话')[0], old);
  const current = { ...old, label: 'Renamed', detail: 'New detail' };
  panel.controller.sections = [{ title: '对话', items: [current] }]; panel.controller.highlighted = 0;
  assert.equal(panel.current(old), current); assert.equal(panel.highlighted(old), true);
  panel.controller.loading = false; panel.controller.query = { pathOnly: true };
  assert.equal(panel.emptyText(), '没有匹配的文件');
  assert.equal(reads, 5, 'each relevant observer subscribes to revision independently');
});
