import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/ui/QuickPanel.ets', import.meta.url), 'utf8');
const navigation = readFileSync(new URL('../entry/src/main/ets/ui/ShellNavigationData.ets', import.meta.url), 'utf8');
function method(text, name) {
  const match = new RegExp('(?:private )?(?:async )?' + name + '\\(').exec(text);
  assert.ok(match, name);
  const start = match.index, open = text.indexOf('{', start);
  let depth = 1, quote = '', escape = false, end = open + 1;
  for (; end < text.length && depth; end++) {
    const c = text[end];
    if (quote) { if (escape) escape = false; else if (c === '\\') escape = true; else if (c === quote) quote = ''; continue; }
    if (c === '"' || c === "'" || c === '`') { quote = c; continue; }
    if (c === '{') depth++; else if (c === '}') depth--;
  }
  assert.equal(depth, 0); return text.slice(start, end);
}
const moveQuickDestination = Function(stripTypeScriptTypes('function ' + method(navigation, 'moveQuickDestination')) + '; return moveQuickDestination;')();
const base = () => ({ swipe: true, items: ['plugins', 'engine', 'settings'] });
const turn = () => new Promise(resolve => setImmediate(resolve));
function fixture(text, compiled) {
  const writes = [], pending = [], notifications = [];
  const save = async (_context, value) => { writes.push(structuredClone(value)); await new Promise((resolve, reject) => pending.push({ resolve, reject })); };
  const methods = ['save', 'toggleDestination', 'moveDestination', 'aboutToDisappear'].map(name => method(text, name)).join('\n');
  const Owner = Function('saveQuickPanelPreferences', 'moveQuickDestination',
    'return ' + stripTypeScriptTypes('(class Owner {' + methods + '})'))(save, moveQuickDestination);
  const owner = Object.assign(new Owner(), { active: true, generation: 0, saving: false, preferencesLoaded: true,
    preferences: base(), error: '', getUIContext: () => ({ getHostContext: () => ({}) }),
    t: value => value, onPreferencesChange: value => notifications.push(structuredClone(value)) });
  const controls = [];
  function control(name, destination = { id: 'features' }, index = 1) {
    const marker = compiled ? name + (name === 'Button' ? '.createWithLabel(' : '.create(') : name + '(';
    const section = text.slice(text.indexOf(compiled ? 'private configure(' : 'private configure()'));
    const begin = section.indexOf(marker);
    assert.ok(begin >= 0, name);
    const end = compiled ? section.indexOf('}, ' + name + ');', begin) :
      name === 'Checkbox' ? section.indexOf('\n        Text(', begin) :
      name === 'Toggle' ? section.indexOf('\n    }.width', begin) : section.indexOf('\n        Button(', begin + 1);
    assert.ok(end > begin);
    const code = section.slice(begin, end), state = {};
    const ui = new Proxy(() => ui, { get: (_target, key) => value => { state[key] = value; return ui; } });
    const render = () => Function(name, 'destination', 'index', 'id', 'ToggleType', stripTypeScriptTypes(code))
      .call(owner, ui, destination, index, destination.id, { Switch: 'switch' });
    render(); controls.push({ state, render }); return state;
  }
  return { owner, writes, pending, notifications, checkbox: control('Checkbox'), toggle: control('Toggle'),
    up: control('Button', { id: 'engine' }), paint() { controls.forEach(row => row.render()); },
    async settle(error) { assert.ok(pending.length); const work = pending.shift(); error ? work.reject(error) : work.resolve(); await turn(); },
    async drain() { for (let limit = 0; pending.length && limit < 20; limit++) { pending.shift().resolve(); await turn(); } } };
}
function cases(label, text, compiled) {
  test(label + ': checkbox consumes its requested selection; native select echoes do not reverse saved values', async () => {
    const f = fixture(text, compiled);
    try {
      f.checkbox.onChange(true);
      assert.equal(f.writes.length, 1); assert.equal(f.owner.saving, true);
      f.paint(); assert.equal(f.checkbox.enabled, false); assert.equal(f.toggle.enabled, false); assert.equal(f.up.enabled, false);
      await f.settle(); f.paint();
      assert.deepEqual(f.owner.preferences.items, [...base().items, 'features']);
      assert.equal(f.checkbox.select, true);
      f.checkbox.onChange(true); await turn(); f.paint();
      assert.equal(f.writes.length, 1, 'successful selection echo must not enqueue an inverse save');
      assert.equal(f.owner.saving, false); assert.equal(f.checkbox.enabled, true); assert.equal(f.toggle.enabled, true); assert.equal(f.up.enabled, true);
      assert.equal(f.notifications.length, 1);
      f.checkbox.onChange(false); await f.settle(); f.paint(); f.checkbox.onChange(false); await turn();
      assert.deepEqual(f.owner.preferences, base()); assert.equal(f.writes.length, 2); assert.equal(f.owner.saving, false);
    } finally { await f.drain(); }
  });
  test(label + ': initial deselected checkbox and unchanged swipe callbacks do not persist or disable controls', async () => {
    const f = fixture(text, compiled);
    try { f.checkbox.onChange(false); f.toggle.onChange(true); await turn(); assert.equal(f.writes.length, 0); assert.equal(f.owner.saving, false); }
    finally { await f.drain(); }
  });
  test(label + ': changing swipe persists once and an echoed value is ignored', async () => {
    const f = fixture(text, compiled);
    try { f.toggle.onChange(false); await f.settle(); f.paint(); f.toggle.onChange(false); await turn();
      assert.equal(f.writes.length, 1); assert.equal(f.owner.preferences.swipe, false); assert.equal(f.owner.saving, false); }
    finally { await f.drain(); }
  });
  test(label + ': failed flush preserves saved preferences, reports error and re-enables controls', async () => {
    const f = fixture(text, compiled);
    f.checkbox.onChange(true); await f.settle(Error('fixture flush rejected')); f.paint();
    assert.deepEqual(f.owner.preferences, base()); assert.equal(f.notifications.length, 0);
    assert.equal(f.owner.saving, false); assert.ok(f.owner.error); assert.equal(f.checkbox.enabled, true);
  });
  test(label + ': an in-flight save is not duplicated and a detached panel cannot issue new writes', async () => {
    const f = fixture(text, compiled);
    try { f.checkbox.onChange(true); f.checkbox.onChange(true); assert.equal(f.writes.length, 1);
      f.owner.aboutToDisappear(); await f.settle(); assert.equal(f.notifications.length, 0);
      const detached = fixture(text, compiled); detached.owner.aboutToDisappear(); detached.checkbox.onChange(true); await turn();
      try { assert.equal(detached.writes.length, 0); } finally { await detached.drain(); } }
    finally { await f.drain(); }
  });
  test(label + ': moves persist current order and no-op boundary moves do not save', async () => {
    const f = fixture(text, compiled);
    try { f.owner.moveDestination('plugins', -1); await turn(); assert.equal(f.writes.length, 0);
      f.owner.moveDestination('settings', -1); await f.settle(); assert.deepEqual(f.owner.preferences.items, ['plugins', 'settings', 'engine']);
      f.owner.moveDestination('settings', 1); await f.settle(); assert.deepEqual(f.owner.preferences, base()); }
    finally { await f.drain(); }
  });
}
cases('source bindings', source, false);
if (process.argv[2]) cases('actual CompileArkTS bindings', readFileSync(process.argv[2], 'utf8'), true);
