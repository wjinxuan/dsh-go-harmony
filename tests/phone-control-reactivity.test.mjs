import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { join } from 'node:path';

const source = readFileSync(new URL('../entry/src/main/ets/ui/PhoneControlPanel.ets', import.meta.url), 'utf8');
function keyOf(name, type) {
  const match = source.match(new RegExp('\\}, \\(' + name + ': ' + type + '\\) => ([^\\n]+)\\);'));
  assert.ok(match, type + ' ForEach key');
  return Function(name, 'return ' + match[1]);
}
function method(name) {
  const start = source.indexOf('  private async ' + name + '(');
  assert.ok(start >= 0);
  return source.slice(start, source.indexOf('\n  private ', start + 1) < 0 ? source.indexOf('\n  build()', start) : source.indexOf('\n  private ', start + 1));
}
const captureKey = keyOf('item', 'PhoneCheck');
const nodeKey = keyOf('node', 'PhoneNode');
const check = { stage: 'capture', state: 'not_run', observed: false, detail: '等待授权' };
const node = { id: 0, text: '旧按钮', type: 'Button', actions: ['click'], editable: false, password: false, parent: -1, bounds: [0, 0, 10, 10] };

test('actual capture replaces the immutable check with a new rendered identity after successful OCR', async () => {
  let released = 0;
  const Owner = Function('capturePhoneScreen', 'return ' + stripTypeScriptTypes('(class Owner {' + method('capture') + '})'))(
    async () => ({ pixels: {}, text: '已识别的文字', width: 1080, height: 1920 }));
  const owner = Object.assign(new Owner(), { busy: false, active: true, generation: 0, context() {},
    policy: { localOcrEnabled: true }, checks: [check], logs: [], pixels: { async release() { released++; } } });
  const before = captureKey(check);
  await owner.capture();
  assert.equal(owner.checks[0].state, 'pass'); assert.equal(owner.checks[0].observed, true);
  assert.equal(owner.screenText, '已识别的文字'); assert.equal(released, 1);
  assert.notEqual(captureKey(owner.checks[0]), before, 'retained row must not capture the previous not_run object');
  assert.equal(captureKey({ ...owner.checks[0] }), captureKey(owner.checks[0]), 'unchanged values keep stable identity');
});

test('node identity is scoped to the screen snapshot because node indices are reused by the accessibility service', () => {
  const owner = { tree: { id: 'screen-a' } };
  const previous = nodeKey.call(owner, node);
  assert.equal(nodeKey.call(owner, { ...node }), previous);
  owner.tree = { id: 'screen-b' };
  assert.notEqual(nodeKey.call(owner, { ...node, text: '密码输入框', actions: ['setText'], password: true }), previous,
    'a new tree must discard old node labels and action closures, even when numeric node IDs match');
});

// Explicit generated-output mode evaluates the actual compiled item builders. The
// small native boundary below models ArkUI ForEach retaining a subtree for a key;
// it does not claim to emulate layout, permissions, or the device renderer.
if (process.argv[2]) {
  const generated = readFileSync(join(process.argv[2], 'PhoneControlPanel.ts'), 'utf8');
  function compiledRows(collection) {
    const call = generated.indexOf('this.forEachUpdateFunction(elmtId, ' + collection + ',');
    assert.ok(call >= 0, collection);
    const start = generated.lastIndexOf('ForEach.create();', call) + 'ForEach.create();'.length;
    const end = generated.indexOf('\n', call);
    const body = stripTypeScriptTypes('const elmtId = 1;\n' + generated.slice(start, end));
    let activeRow;
    const noop = () => {};
    const widget = methods => new Proxy(methods, { get: (target, name) => target[name] || noop });
    const Text = widget({ create: text => activeRow.texts.push(text) });
    const Button = widget({ createWithLabel: label => activeRow.buttons.push({ label }),
      onClick: handler => { activeRow.buttons.at(-1).click = handler; } });
    const render = Function('Text', 'Button', 'Column', 'Row', 'If', body);
    const widgets = [Text, Button, widget({}), widget({}), widget({})];
    let retained = new Map();
    const owner = { t: text => text, colors: {}, busy: false, typeText: '填写内容', calls: [],
      accessible(action, id) { this.calls.push({ screen: this.tree.id, action, id }); },
      observeComponentCreation2(callback) { callback(1, true); },
      ifElseBranchUpdateFunction(_branch, callback) { callback(); },
      forEachUpdateFunction(_id, items, build, keyOf) {
        const next = new Map();
        for (const item of items) {
          const key = keyOf(item);
          let row = retained.get(key);
          if (!row) { row = { texts: [], buttons: [] }; activeRow = row; build(item); }
          next.set(key, row);
        }
        retained = next;
      }
    };
    return { owner, update() { render.call(owner, ...widgets); return [...retained.values()]; } };
  }
  test('generated capture row changes from not tested to observed after immutable state replacement', () => {
    const view = compiledRows('this.checks');
    view.owner.checks = [check];
    assert.match(view.update()[0].texts[0], /未测试/);
    view.owner.checks = [{ ...check, state: 'pass', observed: true, detail: '1080 × 1920' }];
    assert.equal(view.update()[0].texts[0], 'capture · 已实测\n1080 × 1920');
    view.owner.checks = [{ ...check, state: 'pass', observed: true, detail: '1920 × 1080' }];
    assert.match(view.update()[0].texts[0], /1920 × 1080/);
  });
  test('generated tree rows replace old labels and actions when a new snapshot reuses a node index', () => {
    const view = compiledRows('this.tree.nodes.filter((item: PhoneNode) => item.text.length > 0 || item.actions.length > 0)');
    view.owner.tree = { id: 'screen-a', nodes: [node] };
    let rows = view.update(); assert.match(rows[0].texts[0], /旧按钮/); assert.equal(rows[0].buttons[0].label, '点击');
    view.owner.tree = { id: 'screen-b', nodes: [{ ...node, text: '新输入框', type: 'TextInput', actions: ['setText'], editable: true }] };
    rows = view.update(); assert.match(rows[0].texts[0], /新输入框/); assert.deepEqual(rows[0].buttons.map(item => item.label), ['填写']);
    rows[0].buttons[0].click(); assert.deepEqual(view.owner.calls, [{ screen: 'screen-b', action: 'setText', id: 0 }]);
    view.owner.tree = { id: 'screen-c', nodes: [{ ...node, text: '密码输入框', actions: ['click', 'setText'], editable: true, password: true }] };
    rows = view.update(); assert.match(rows[0].texts[0], /密码输入框/); assert.equal(rows[0].buttons.length, 0);
  });
}
