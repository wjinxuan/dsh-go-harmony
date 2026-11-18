import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/ui/WorkspacesPanel.ets', import.meta.url), 'utf8');
const data = readFileSync(new URL('../entry/src/main/ets/ui/WorkspaceViewData.ets', import.meta.url), 'utf8');
function method(text, name) {
  const match = new RegExp('(?:private )?(?:function )?' + name + '\\(').exec(text);
  if (!match) return '';
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
const workspaceSections = Function(stripTypeScriptTypes(method(data, 'workspaceSections')) + ';return workspaceSections;')();
const makeWorkspaces = () => ['b', 'a', 'workspace'].map(id => ({ id, title: id, path: '/owned/' + id, sessionIds: [] }));
function fixture(text, compiled = false, view = { selected: '', pinned: [], groups: {} }) {
  const Owner = Function('workspaceSections', 'return ' + stripTypeScriptTypes('(class Owner {' +
    ['ordered', 'sectionItems'].map(name => method(text, name)).join('\n') + '})'))(workspaceSections);
  const owner = new Owner(), values = { workspaces: makeWorkspaces(), order: [], view }, reads = [];
  for (const key of Object.keys(values)) Object.defineProperty(owner, key, {
    get() { reads.push(key); return values[key]; }, set(value) { values[key] = value; }, configurable: true
  });
  const line = text.split('\n').find(row => compiled ? row.includes('this.forEachUpdateFunction(elmtId,') && row.includes('(item: DshWorkspace)') : row.includes('ForEach(') && row.includes('(item: DshWorkspace)'));
  assert.ok(line, 'extract the actual inner workspace ForEach binding');
  const expression = compiled ? line.slice(line.indexOf('elmtId, ') + 8, line.indexOf(', forEachItemGenFunction,')) :
    line.slice(line.indexOf('ForEach(') + 8, line.indexOf(', (item: DshWorkspace)'));
  // The outer kind/title key is stable: ArkUI retains the original section closure.
  const sectionKey = section => section.kind + '|' + section.title;
  const captured = workspaceSections(owner.ordered(), owner.view);
  const readers = new Map(captured.map(section => [sectionKey(section),
    Function('section', 'return () => (' + expression + ')').call(owner, section)]));
  return { owner, reads, captured, readers, read(key) { return readers.get(key)(); },
    currentKey(kind) { const section = workspaceSections(owner.ordered(), owner.view).find(row => row.kind === kind); return section && sectionKey(section); } };
}
function cases(label, text, compiled = false) {
  test(label + ': retained group actually reorders its rows after confirmed host order changes', () => {
    const f = fixture(text, compiled), key = f.currentKey('rest');
    assert.deepEqual(f.read(key).map(row => row.id), ['b', 'a', 'workspace']);
    f.owner.order = ['a', 'b', 'workspace'];
    assert.equal(f.currentKey('rest'), key, 'do not remount the group just to expose a new array');
    assert.deepEqual(f.read(key).map(row => row.id), ['a', 'b', 'workspace'], 'visual row order must agree with the move button state');
    f.owner.order = ['workspace', 'a', 'b'];
    assert.deepEqual(f.read(key).map(row => row.id), ['workspace', 'a', 'b']);
  });
  test(label + ': host rename and session counts replace captured row metadata in the same section', () => {
    const f = fixture(text, compiled), key = f.currentKey('rest');
    f.owner.workspaces = f.owner.workspaces.map(row => row.id === 'b' ? { ...row, title: 'Renamed B', sessionIds: ['own-session'] } : row);
    const row = f.read(key).find(row => row.id === 'b');
    assert.equal(row.title, 'Renamed B'); assert.equal(row.sessionIds.length, 1);
    // Existing row keys include title/path/count, so refreshed inputs rebuild callbacks using the real updated row.
    const keyBinding = text.includes('`${item.id}|${item.path}|${item.title}|${item.sessionIds.length}`');
    assert.equal(keyBinding, true);
  });
  test(label + ': an existing named group receives moved members without retaining the first array', () => {
    const f = fixture(text, compiled, { selected: '', pinned: [], groups: { a: 'Owned group' } });
    const key = f.currentKey('group'); assert.deepEqual(f.read(key).map(row => row.id), ['a']);
    f.owner.view = { selected: '', pinned: [], groups: { a: 'Owned group', b: 'Owned group' } };
    assert.equal(f.currentKey('group'), key); assert.deepEqual(f.read(key).map(row => row.id), ['b', 'a']);
  });
  test(label + ': existing pinned section tracks pin, unpin and order changes', () => {
    const f = fixture(text, compiled, { selected: '', pinned: ['b'], groups: {} });
    const key = f.currentKey('pinned'); assert.deepEqual(f.read(key).map(row => row.id), ['b']);
    f.owner.view = { selected: '', pinned: ['b', 'a'], groups: {} }; f.owner.order = ['a', 'b', 'workspace'];
    assert.deepEqual(f.read(key).map(row => row.id), ['a', 'b']);
    f.owner.view = { selected: '', pinned: ['a'], groups: {} }; assert.deepEqual(f.read(key).map(row => row.id), ['a']);
  });
  test(label + ': removed sections yield no stale rows to late retained observers', () => {
    const f = fixture(text, compiled), key = f.currentKey('rest');
    f.owner.workspaces = []; assert.deepEqual(f.read(key), []);
  });
  test(label + ': inner ForEach observer reads current ArkUI state to register update dependencies', () => {
    const f = fixture(text, compiled), key = f.currentKey('rest'); f.reads.length = 0; f.read(key);
    for (const dependency of ['workspaces', 'order', 'view']) assert.ok(f.reads.includes(dependency), 'inner observer must read current ' + dependency);
  });
}
cases('source binding', source);
if (process.argv[2]) cases('actual CompileArkTS binding', readFileSync(process.argv[2], 'utf8'), true);
