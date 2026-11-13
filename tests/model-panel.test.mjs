import assert from 'node:assert/strict';
import test from 'node:test';
import { ModelPanel } from './ui/ModelPanel.ts';
import { defaultModelEffort, filterModelGroups, projectedModelSelection } from './ui/ModelSelectionData.ts';

const rapid = { provider: 'edge', id: 'a', name: 'Rapid', efforts: [] };
const deep = { provider: 'core', id: 'a', name: 'Deliberate', defaultEffort: 'high',
  efforts: [{ id: 'off', name: 'Off' }, { id: 'high', name: 'High', description: 'Think harder' }] };
const accepted = { provider: 'core', model: 'a', reasoningEffort: 'high' };
const catalog = { groups: [{ id: 'edge', name: 'Edge Route', models: [rapid] },
  { id: 'core', name: 'Core Route', models: [deep] }, { id: 'empty', name: 'Unavailable', models: [] }],
  failures: [{ provider: 'unavailable', name: 'Unavailable' }],
  defaultSelection: { provider: 'edge', model: 'a' } };

function fixture(sessionId = 's1') {
  const panel = new ModelPanel();
  const client = {
    epoch: 10, reads: 0, writes: [],
    connectionIdentity() { return this.epoch; },
    async listModels() { this.reads++; return catalog; },
    async sessionProjections() { return null; },
    async setModel(...args) { this.writes.push(args); return { selected: accepted }; }
  };
  const selections = [];
  panel.sessionId = sessionId;
  panel.client = client;
  panel.onSelected = (...args) => selections.push(args);
  panel.active = true;
  return { panel, client, selections };
}

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((success, failure) => { resolve = success; reject = failure; });
  return { promise, resolve, reject };
}

test('search filters empty groups and matches both route and model terms', () => {
  assert.deepEqual(filterModelGroups(catalog.groups, '   ').map(group => group.id), ['edge', 'core']);
  assert.deepEqual(filterModelGroups(catalog.groups, '  CORE deliberate  ').map(group => group.id), ['core']);
  assert.deepEqual(filterModelGroups(catalog.groups, 'missing'), []);
  assert.deepEqual(filterModelGroups([{ id: 'empty', name: 'empty', models: [] }], ''), []);
});

test('uses session next over last used, provided and default models, retaining partial-failure labels', async () => {
  const { panel, client } = fixture();
  panel.currentSelection = { provider: 'cached', model: 'old' };
  const last = { provider: 'last', model: 'used', reasoningEffort: undefined };
  client.sessionProjections = async () => ({ values: { modelSelection: { next: accepted, lastUsed: last } } });
  await panel.load();
  assert.deepEqual(panel.selection, accepted);
  assert.deepEqual(panel.failures, ['Unavailable']);
  assert.equal(panel.isSelected(deep), true);
  assert.equal(panel.isSelected(rapid), false);
  assert.deepEqual(projectedModelSelection({ values: { modelSelection: { next: {}, lastUsed: last } } }), last);
  client.sessionProjections = async () => { throw Error('old host without projection'); };
  await panel.load();
  assert.deepEqual(panel.selection, panel.currentSelection);
  assert.equal(defaultModelEffort(deep), 'high');
  assert.equal(defaultModelEffort({ ...deep, defaultEffort: 'retired' }), 'high');
  assert.equal(defaultModelEffort(rapid), '');
});

test('new-chat model selection stays pending locally and never writes a host session', async () => {
  const { panel, client, selections } = fixture('');
  await panel.load();
  await panel.choose(deep.provider, deep.id, 'high');
  assert.deepEqual(client.writes, []);
  assert.deepEqual(selections, [['Deliberate', accepted]]);
});

test('retries a failed selection independently and uses the model accepted by the host', async () => {
  const { panel, client, selections } = fixture();
  await panel.load();
  client.setModel = async (...args) => {
    client.writes.push(args);
    throw Error('failed');
  };
  await panel.choose(rapid.provider, rapid.id, '');
  assert.equal(panel.loadError, false);
  assert.equal(panel.retrySelection.provider, 'edge');
  assert.deepEqual(selections, []);
  client.setModel = async (...args) => {
    client.writes.push(args);
    return { selected: accepted, defaultSave: { status: 'failed' } };
  };
  panel.retryChoice();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(client.reads, 1);
  assert.deepEqual(client.writes, [['s1', 'edge', 'a', undefined], ['s1', 'edge', 'a', undefined]]);
  assert.equal(selections[0][0], 'Deliberate');
  assert.deepEqual(selections[0][1], accepted);
  assert.match(selections[0][2], /默认模型/);
  assert.equal(panel.retrySelection, undefined);
});

test('catalog load errors remain distinct and can recover without a selection write', async () => {
  const { panel, client } = fixture();
  client.listModels = async () => { throw Error('offline'); };
  await panel.load();
  assert.equal(panel.loadError, true);
  assert.equal(panel.retrySelection, undefined);
  assert.equal(panel.loading, false);
  client.listModels = async () => catalog;
  await panel.load();
  assert.equal(panel.loadError, false);
  assert.equal(panel.groups.length, 2);
  assert.deepEqual(client.writes, []);
});

test('ignores delayed load and selection responses after connection, session or component changes', async () => {
  for (const change of [
    ({ client }) => client.epoch++,
    ({ panel }) => { panel.sessionId = 's2'; },
    ({ panel }) => panel.aboutToDisappear()
  ]) {
    const oldLoad = fixture();
    const catalogReply = deferred();
    oldLoad.client.listModels = () => catalogReply.promise;
    const loading = oldLoad.panel.load();
    change(oldLoad);
    catalogReply.resolve(catalog);
    await loading;
    assert.deepEqual(oldLoad.panel.groups, []);

    const oldWrite = fixture();
    await oldWrite.panel.load();
    const selectionReply = deferred();
    oldWrite.client.setModel = () => selectionReply.promise;
    const choosing = oldWrite.panel.choose(rapid.provider, rapid.id, '');
    change(oldWrite);
    selectionReply.resolve({ selected: accepted });
    await choosing;
    assert.deepEqual(oldWrite.selections, []);
    assert.deepEqual(oldWrite.panel.selection, catalog.defaultSelection);
    assert.equal(oldWrite.panel.retrySelection, undefined);
  }

  const changed = fixture();
  await changed.panel.load();
  changed.client.epoch++;
  await changed.panel.choose(rapid.provider, rapid.id, '');
  assert.deepEqual(changed.client.writes, []);
});

test('an old failed request cannot overwrite the same session after reconnect', async () => {
  const { panel, client, selections } = fixture();
  await panel.load();
  const oldReply = deferred();
  client.setModel = () => oldReply.promise;
  const oldWrite = panel.choose(rapid.provider, rapid.id, '');
  client.epoch += 2;
  client.setModel = async () => ({ selected: accepted });
  panel.sessionChanged();
  await new Promise(resolve => setImmediate(resolve));
  await panel.choose(deep.provider, deep.id, 'high');
  oldReply.reject(Error('old connection closed'));
  await oldWrite;
  assert.deepEqual(panel.selection, accepted);
  assert.equal(selections.length, 1);
  assert.equal(panel.retrySelection, undefined);
  assert.equal(panel.writing, false);
});
