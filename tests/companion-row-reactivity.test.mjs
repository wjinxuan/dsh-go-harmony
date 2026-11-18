import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { join } from 'node:path';

const base = new URL('../entry/src/main/ets/', import.meta.url);
const read = name => readFileSync(new URL(name, base), 'utf8');
const source = read('companion/CompanionPanel.ets');
const url = text => 'data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(text));
const wire = url(read('dsh/DshWire.ets'));
const persona = url(read('companion/CompanionPersona.ets'));
const { parseCompanionReply } = await import(url(read('companion/CompanionData.ets')
  .replace(', WireObject', '').replace("'../dsh/DshWire'", JSON.stringify(wire)).replace("'./CompanionPersona'", JSON.stringify(persona))));
const methods = ['memoryFields', 'editMemory', 'updateFull'].map(name => {
  const start = source.indexOf(' private ' + name + '('); assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n', start));
}).join('\n');
const Owner = Function('return ' + stripTypeScriptTypes('(class Owner {' + methods + '})'))();
const memoryKeyExpression = source.match(/\},\(memory:CompanionMemory\)=>([^\n]+)\)\n/);
const lineKeyExpression = source.match(/\},\((_?line):CompanionLine,index:number\)=>(.*?)\);if\(this.streaming\)/);
assert.ok(memoryKeyExpression); assert.ok(lineKeyExpression);
const memoryKey = Function('memory', 'return ' + memoryKeyExpression[1]);
const lineKey = Function(lineKeyExpression[1], 'index', 'return ' + lineKeyExpression[2]);
const first = { id: '7a92541a-3eaa-4cb3-b3c1-21229519f189', kind: 'fact', text: 'DSH-DEVICE-MEMORY-1117 A',
  keywords: ['first'], pinned: false, source: { kind: 'manual' }, expiresAt: null };
const second = { ...first, text: first.text + 'DSH-DEVICE-MEMORY-1117 B', keywords: ['latest'], pinned: true, kind: 'preference' };
function owner() { return Object.assign(new Owner(), { t: text => text, colors: {}, expressions: {}, motions: {},
  replyActive: false, sending: false, stage: { command() {} }, removed: [], removeMemory(memory) { this.removed.push(memory); } }); }

test('edited memory identity includes current display and editor fields, while unchanged values retain identity', () => {
  assert.notEqual(memoryKey(first), memoryKey(second));
  assert.notEqual(memoryKey(first), memoryKey({ ...first, keywords: ['new-keyword'] }), 'unchanged visible text still needs a current edit closure');
  assert.equal(memoryKey({ ...second }), memoryKey(second));
});
test('full-mode streaming snapshots update the same line position and keep duplicate text rows distinct', () => {
  const state = owner();
  state.updateFull({ messages: [{ role: 'user', text: 'question' }, { role: 'assistant', text: 'A' }], running: true });
  const before = lineKey(state.lines[1], 1);
  state.updateFull({ messages: [{ role: 'user', text: 'question' }, { role: 'assistant', text: 'AB' }], running: false });
  assert.notEqual(lineKey(state.lines[1], 1), before, 'full mode replaces the assistant object on each streamed snapshot');
  assert.equal(state.busy, false); assert.equal(state.fullRunning, false);
  assert.notEqual(lineKey(state.lines[1], 1), lineKey(state.lines[1], 2), 'equal content at different positions is not one row');
});

// Generated mode executes actual compiled row builders with a keyed-retention
// boundary. It tests captured values and handlers, not physical ArkUI rendering.
if (process.argv[2]) {
  const generated = readFileSync(join(process.argv[2], 'CompanionPanel.ts'), 'utf8');
  function rows(collection) {
    const at = generated.indexOf('this.forEachUpdateFunction(elmtId, this.' + collection + ','); assert.ok(at >= 0);
    const start = generated.lastIndexOf('ForEach.create();', at) + 'ForEach.create();'.length;
    const body = stripTypeScriptTypes('const elmtId=1;\n' + generated.slice(start, generated.indexOf('\n', at)));
    let current, retained = new Map();
    const widget = value => new Proxy(value, { get: (target, key) => target[key] || (() => {}) });
    const Text = widget({ create: text => current.texts.push(text) });
    const Button = widget({ createWithLabel: label => current.buttons.push({ label }), onClick: click => { current.buttons.at(-1).click = click; } });
    const state = owner();
    state.observeComponentCreation2 = callback => callback(1, true);
    state.forEachUpdateFunction = (_id, items, build, keyOf) => {
      const next = new Map();
      items.forEach((item, index) => {
        const key = keyOf(item, index); let row = retained.get(key);
        if (!row) { row = { texts: [], buttons: [] }; current = row; build(item, index); }
        next.set(key, row);
      }); retained = next;
    };
    const render = Function('Text', 'Button', 'Column', 'Row', 'CopyOptions', 'parseCompanionReply', body);
    return { state, update() { render.call(state, Text, Button, widget({}), widget({}), { LocalDevice: 0 }, parseCompanionReply); return [...retained.values()]; } };
  }
  test('compiled retained memory row displays A+B and edit/delete receive the replacement object immediately', () => {
    const view = rows('memories'); view.state.memories = [first];
    assert.equal(view.update()[0].texts[0], first.text);
    view.state.memories = [second]; const row = view.update()[0];
    assert.equal(row.texts[0], second.text); assert.match(row.texts[1], /preference.*置顶/);
    row.buttons.find(button => button.label === '编辑').click();
    assert.equal(view.state.memoryDraft, second.text); assert.equal(view.state.memoryKeywords, 'latest');
    assert.equal(view.state.memoryPinned, true); assert.equal(view.state.memoryKind, 'preference');
    row.buttons.find(button => button.label === '删除').click(); assert.equal(view.state.removed[0], second);
  });
  test('compiled memory edit handler refreshes when only hidden keywords change', () => {
    const view = rows('memories'); view.state.memories = [first]; view.update();
    view.state.memories = [{ ...first, keywords: ['current', '1117'] }];
    view.update()[0].buttons.find(button => button.label === '编辑').click();
    assert.equal(view.state.memoryKeywords, 'current, 1117');
  });
  test('compiled full-mode reply follows streamed snapshots at the same index through completion', () => {
    const view = rows('lines');
    for (const [text, running] of [['A', true], ['AB', true], ['ABC', false]]) {
      view.state.updateFull({ messages: [{ role: 'user', text: 'question' }, { role: 'assistant', text }], running });
      assert.deepEqual(view.update().map(row => row.texts[0]), ['question', text]);
    }
  });
}
