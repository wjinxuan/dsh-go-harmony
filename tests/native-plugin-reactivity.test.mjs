import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const base = new URL('../entry/src/main/ets/ui/', import.meta.url);
const view = readFileSync(new URL('NativePluginView.ets', base), 'utf8');
const input = readFileSync(new URL('NativePluginInput.ets', base), 'utf8');
const array = value => Array.isArray(value) ? value : [];
const object = value => value && typeof value === 'object' && !Array.isArray(value) ? value : {};
const string = value => typeof value === 'string' ? value : '';
const number = (value, fallback = 0) => typeof value === 'number' && Number.isFinite(value) ? value : fallback;
function method(text, name) {
  const start = text.indexOf('private ' + name + '('); if (start < 0) return '';
  let open = text.indexOf('{', start), depth = 1, quote = '', escape = false, end = open + 1;
  for (; end < text.length && depth; end++) {
    const c = text[end];
    if (quote) { if (escape) escape = false; else if (c === '\\') escape = true; else if (c === quote) quote = ''; continue; }
    if (c === '"' || c === "'" || c === '`') { quote = c; continue; }
    if (c === '{') depth++; else if (c === '}') depth--;
  }
  assert.equal(depth, 0); return text.slice(start, end);
}
const children = () => [{ type: 'text', raw: { text: 'Waiting' }, children: [], key: 'root.0' },
  { type: 'metric', raw: { value: 0 }, children: [], key: 'root.1' },
  { type: 'select', raw: { value: 'A' }, children: [], key: 'root.2' }];
function nodeOwner(text) {
  const helpers = ['childKeys', 'child'].map(name => method(text, name)).join('\n');
  const Owner = Function('return ' + stripTypeScriptTypes('(class Owner {' + helpers + '})'))();
  return Object.assign(new Owner(), { node: { type: 'stack', raw: {}, children: children(), key: 'root' } });
}
function changeChildren(owner) {
  const next = children(); next[0].raw.text = 'Confirmed'; next[1].raw.value = 2; next[2].raw.value = 'B';
  owner.node = { ...owner.node, children: next };
}

test('all four source container bindings use current child values with stable identity', () => {
  const owner = nodeOwner(view), readers = [];
  const pattern = /ForEach\((this\.node\.children|this\.childKeys\(\)), \((child: PluginNode|key: string)(?:, index: number)?\) => \{/g;
  for (const match of view.matchAll(pattern)) {
    const expression = view.slice(match.index).match(/node: (child|this\.child\(key\))/)?.[1];
    assert.ok(expression);
    const argument = match[2].startsWith('child') ? owner.node.children[0] : owner.node.children[0].key;
    readers.push(Function(match[2].split(':')[0], 'return () => ' + expression).call(owner, argument));
  }
  assert.equal(readers.length, 4);
  for (const read of readers) assert.equal(read().raw.text, 'Waiting');
  changeChildren(owner);
  for (const read of readers) assert.equal(read().raw.text, 'Confirmed', 'retained child observer must not capture its first raw object');
  const keys = owner.childKeys();
  owner.node = { ...owner.node, children: [{ type: 'textField', raw: { value: 'fresh type' }, children: [], key: 'root.0' }] };
  for (const read of readers) assert.equal(read().type, 'textField', 'type changes reach the retained component render branch');
  assert.equal(owner.childKeys()[0], keys[0], 'a value change must not force input remount');
  owner.node = { ...owner.node, children: [] };
  for (const read of readers) assert.deepEqual(read(), { type: 'invalid', raw: {}, children: [], key: 'root.0' }, 'removed nodes never fall back to stale data');
  assert.deepEqual(owner.childKeys(), []);
});

function inputOwner(text) {
  const names = ['editable', 'min', 'max', 'value', 'change', 'pick', 'selected'];
  const Owner = Function('array', 'object', 'string', 'number', 'pluginInputIssue', 'pluginInputPath',
    'return ' + stripTypeScriptTypes('(class Owner {' + names.map(name => method(text, name)).join('\n') + '})'))
    (array, object, string, number, () => '', () => ['value']);
  const owner = Object.assign(new Owner(), { raw: {}, colors: { primary: 'selected', onPrimary: 'on-selected', surfaceAlt: 'plain', text: 'ink' } });
  owner.onValue = (_bind, value) => { owner.raw = { ...owner.raw, value }; };
  return owner;
}
function button(text, owner, option, generated = false) {
  // CompileArkTS places the item-generator body before the options expression.
  const branch = text.search(/\['select',\s*'segmented',\s*'chips'\]/);
  assert.ok(branch >= 0);
  const start = text.indexOf(generated ? 'Button.createWithLabel(' : 'Button(', branch);
  assert.ok(start >= 0);
  const end = generated ? text.indexOf('}, Button);', start) : text.indexOf('\n        })', start);
  const code = text.slice(start, end);
  const state = {}, ui = new Proxy((label) => { state.label = label; return ui; }, {
    get(_target, key) { return value => { state[key === 'createWithLabel' ? 'label' : key] = value; return ui; }; }
  });
  Function('Button', 'option', 'string', 'object', stripTypeScriptTypes(code)).call(owner, ui, option, string, object);
  return state;
}
function inputCases(label, text, compiled = false) {
  for (const kind of ['select', 'segmented', 'chips']) test(label + ': ' + kind + ' single choice exposes the current value visually and to accessibility', () => {
    const owner = inputOwner(text); owner.raw = { type: kind, bind: 'data.choice', value: 'A' };
    const a = () => button(text, owner, 'A', compiled), b = () => button(text, owner, { label: 'Bee', value: 'B' }, compiled);
    assert.equal(a().accessibilitySelected, true); assert.equal(b().accessibilitySelected, false);
    assert.equal(a().backgroundColor, 'selected'); assert.equal(b().backgroundColor, 'plain');
    assert.match(a().label, /✓/); assert.equal(b().label, 'Bee');
    b().onClick(); assert.equal(owner.raw.value, 'B');
    assert.equal(a().accessibilitySelected, false); assert.equal(b().accessibilitySelected, true);
    assert.equal(b().fontColor, 'on-selected'); assert.equal(a().fontColor, 'ink');
    b().onClick(); assert.equal(owner.raw.value, 'B', 'single choice retains the existing pick rule');
  });
  test(label + ': multi chips toggle independently, including label-only option fallback', () => {
    const owner = inputOwner(text); owner.raw = { type: 'chips', multi: true, bind: 'data.choice', value: ['A', 'C'] };
    const a = () => button(text, owner, 'A', compiled), b = () => button(text, owner, { label: 'B' }, compiled), c = () => button(text, owner, 'C', compiled);
    assert.equal(a().accessibilitySelected, true); assert.equal(b().accessibilitySelected, false); assert.equal(c().accessibilitySelected, true);
    b().onClick(); assert.deepEqual(owner.raw.value, ['A', 'C', 'B']);
    a().onClick(); assert.deepEqual(owner.raw.value, ['C', 'B']);
    assert.equal(a().accessibilitySelected, false); assert.equal(b().accessibilitySelected, true); assert.equal(c().accessibilitySelected, true);
  });
}
inputCases('source', input);

if (process.argv[2]) {
  const compiled = readFileSync(process.argv[2], 'utf8');
  const inputCompiled = readFileSync(join(dirname(process.argv[2]), 'NativePluginInput.ts'), 'utf8');
  inputCases('actual CompileArkTS', inputCompiled, true);
  for (const kind of ['stack', 'row', 'form', 'tabs']) test('actual CompileArkTS retained ' + kind + ' child observers receive live values without remount', () => {
    const owner = nodeOwner(compiled); owner.node.type = kind; owner.sectionIndex = 0; owner.expanded = true;
    const observers = [], updated = new Map(), created = new Map(); let nextId = 0;
    owner.observeComponentCreation2 = (callback, type) => { const id = nextId++; observers.push({ id, callback, type }); callback(id, true); };
    owner.ifElseBranchUpdateFunction = (_branch, build) => build();
    owner.forEachUpdateFunction = (_id, items, generate) => items.forEach(generate);
    owner.updateStateVarsOfChildByElmtId = (id, props) => updated.set(id, props);
    owner.t = value => value;
    class NativePluginNodeView { constructor(_owner, props, _local, id) { created.set(id, props); } }
    const ui = new Proxy({}, { get: () => () => {} });
    const names = ['If', 'Column', 'Row', 'Text', 'Button', 'Flex', 'ForEach', '__Common__', 'Divider', 'Blank'];
    const values = names.map(() => ui);
    const render = Function(...names, 'NativePluginNodeView', 'ViewPU', 'PLUGIN_INPUTS', 'pluginAction', 'string', 'VerticalAlign',
      'return ' + stripTypeScriptTypes('(class Render {' + method(compiled.slice(compiled.indexOf('class NativePluginNodeView')), 'render') + '})'))
      (...values, NativePluginNodeView, { create() {} }, [], () => undefined, string, { Top: 0 });
    render.prototype.render.call(owner);
    const childObservers = observers.filter(row => row.type?.name === 'NativePluginNodeView');
    assert.ok(childObservers.length > 0);
    const count = created.size; changeChildren(owner);
    let reads = 0, currentNode = owner.node;
    Object.defineProperty(owner, 'node', { get() { reads++; return currentNode; }, set(value) { currentNode = value; } });
    childObservers.forEach(row => { reads = 0; row.callback(row.id, false); assert.ok(reads > 0, 'retained observer reads @Prop node, registering its ArkUI dependency'); });
    assert.equal(created.size, count, 'retain component identity and focus');
    for (const [id, props] of updated) {
      const key = created.get(id).node.key, expected = owner.node.children.find(child => child.key === key);
      assert.deepEqual(props.node, expected);
    }
    assert.equal(updated.size, childObservers.length);
    owner.node = { ...owner.node, children: [] };
    childObservers.forEach(row => row.callback(row.id, false));
    for (const props of updated.values()) assert.deepEqual(props.node.raw, {}, 'late removed-node observer must not expose its original data');
    for (const props of updated.values()) assert.equal(props.node.type, 'invalid');
  });
}
