import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
const moduleUrl = source => 'data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(source));
const wire = moduleUrl(await readFile(new URL('../entry/src/main/ets/dsh/DshWire.ets', import.meta.url), 'utf8'));
const source = (await readFile(new URL('../entry/src/main/ets/ui/PluginSeatData.ets', import.meta.url), 'utf8')).replace(', WireObject }', ' }').replace("'../dsh/DshWire'", JSON.stringify(wire));
const { pluginSeats, seatConfig, seatWebTarget, cordisShown, cordisStatus } = await import(moduleUrl(source));
const recipes = JSON.parse(await readFile(new URL('../entry/src/main/resources/rawfile/islands/recipes.json', import.meta.url)));
test('seat inventory excludes host-owned replacement points and resolves multilingual sibling labels', () => {
  const seats = pluginSeats({ packages: [{ name: 'official', official: true }], slots: {
    root: [{ package: 'mine', cell: 'root' }], main: [{ package: 'mine', cell: 'custom' }, { package: 'mine', cell: 'custom' }, { package: 'official', cell: 'builtin' }],
    'sidebar.panellist': [{ package: 'mine', cell: 'custom', label: { zh: '我的面板', en: 'My panel' } }],
    'sidebar.right.pane.tab.title': [{ package: 'mine', cell: 'doc' }],
    unknown: [{ package: 'new', cell: 'future', order: -1 }]
  } });
  assert.equal(seats.length, 3); assert.equal(seats[0].pkg, 'new');
  const panel = seats.find(s => s.slot === 'main'); assert.deepEqual(panel.labels, ['我的面板', 'My panel']);
  assert.deepEqual(seatConfig(panel, '', recipes, true).target, { then: { panel: panel.labels } });
  assert.equal(seatConfig(panel, '', recipes, false), undefined);
  assert.deepEqual(seatWebTarget(panel, ''), { sidebar: true });
});
test('island forms require real session scope, recognized recipes and exact plugin row', () => {
  const seat = { slot: 'conversation.input.dock', pkg: 'mine', cell: 'x', title: 'X', labels: ['X'], order: 0 };
  assert.equal(seatConfig(seat, '', recipes, true), undefined);
  const config = seatConfig(seat, 'chat', recipes, true);
  assert.equal(config.mode, 'panel'); assert.equal(config.mask, true); assert.equal(config.cell, null);
  assert.equal(config.target.session, 'chat');
  assert.equal(seatConfig({ ...seat, slot: 'shell.overlay' }, '', recipes, true), undefined);
  assert.equal(seatConfig({ ...seat, slot: 'plugins.row.config' }, '', recipes, true), undefined);
  assert.deepEqual(seatConfig({ ...seat, slot: 'plugins.row.config', cell: 'mine#config' }, '', recipes, true).target,
    { web: { panel: 'plugins' }, then: { plugin: 'mine', row: 'config' } });
});
test('Cordis chooses staged package, current package then newest and distinguishes approval from stale failure', () => {
  const row = { packages: [{ packageId: 'a' }, { packageId: 'b' }], currentPackageId: 'a', nextPackageId: 'missing', latestRun: { packageId: 'b', status: 'failed' }, activeRun: { pluginRunId: 'live' } };
  assert.equal(cordisShown(row).packageId, 'a'); assert.equal(cordisStatus(row), '运行中');
  row.nextPackageId = 'b'; assert.equal(cordisStatus(row), '启动失败');
  row.latestRun.status = 'awaiting-approval'; assert.equal(cordisStatus(row), '等待批准');
});
test('Tier A reads boot JSON without executing script and infers only installed client configuration seats', async () => {
  const {parseWebBoot}=await import(moduleUrl(source));
  const boot=parseWebBoot('<script>globalThis["__DSH_BOOT__"] = {"rev":"new","entries":[{"id":"mine"},{"id":"uninstalled"},{"id":"@deepseek-ai/base"}],"note":"a}b"};throw new Error("never run")</script>');
  assert.equal(boot.rev,'new');
  const bundles=[{name:'mine',installed:true,rows:[{rowId:'ns',meta:{title:{en:'Settings'}}}]},{name:'server',installed:true},{name:'uninstalled',installed:false},{name:'@deepseek-ai/base',installed:true}];
  assert.deepEqual(pluginSeats({},bundles,boot).map(s=>[s.slot,s.pkg,s.cell]),[['plugins.bundle.config','mine','mine'],['plugins.row.config','mine','mine#ns']]);
  assert.equal(pluginSeats({slots:{},bootRev:'new'},bundles,boot).length,0);
  assert.equal(pluginSeats({slots:{},bootRev:'old'},bundles,boot).length,2);
  assert.deepEqual(parseWebBoot('<script>window.__DSH_BOOT__ = {"entries":[]</script>'),{});
  assert.deepEqual(parseWebBoot('self.__DSH_BOOT__ = { entries: eval("evil") }'),{});
  assert.deepEqual(parseWebBoot('window.__DSH_BOOT__ = '+JSON.stringify({entries:[],pad:'x'.repeat(4194304)})),{});
});
