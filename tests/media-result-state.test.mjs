import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../entry/src/main/ets/ui/MediaResultCard.ets', import.meta.url), 'utf8');
const featureSource = readFileSync(new URL('../entry/src/main/ets/ui/EngineFeatureData.ets', import.meta.url), 'utf8');
const featureMethods = ['jobLive', 'jobStatus'].map(name => featureSource.match(new RegExp('export function ' + name + '\\([\\s\\S]*?^}', 'm'))[0].replace('export ', '')).join('\n');
const string = value => typeof value === 'string' ? value : '';
const { jobLive, jobStatus } = Function('string', stripTypeScriptTypes(featureMethods) + '; return { jobLive, jobStatus };')(string);
const methods = source.slice(source.indexOf('  private reset('), source.indexOf('\n  build()'));
const Owner = Function('string', 'jobLive', 'jobStatus', 'clearMediaFiles', 'return ' + stripTypeScriptTypes('(class Owner {' + methods + '})'))(string, jobLive, jobStatus, async () => {});
function fixture() {
  const callbacks = [], kills = [], stops = []; let connection = 'one';
  const owner = Object.assign(new Owner(), { active: true, visible: false, generation: 1, sessionId: 'session-a',
    meta: { status: 'running', job: 'job-a', items: [], request: {}, error: {} }, paths: [], progress: '', error: '', cancelling: false, jobState: '',
    t: text => text, client: { connectionIdentity: () => connection,
      async watchJobs(session, items) { callbacks.push({ session, items }); return () => stops.push(session); },
      async killJob(session, job) { kills.push({ session, job }); return true; }
    } });
  return { owner, callbacks, kills, stops, connection(value) { connection = value; } };
}
// Evaluate the actual source's visible-condition and label expressions. This is
// not a device layout emulator; the optional generated mode below uses compiled callbacks.
const runningView = source.slice(source.indexOf("if (this.meta.status === 'running')"), source.indexOf("} else if (this.meta.status === 'failed')"));
const loadingLine = runningView.match(/^\s*(?:if \((.*)\) )?LoadingProgress\(\)/m);
const cancelCondition = runningView.match(/if \(([^\n]+)\) Button\(this\.cancelling/)[1];
const labelExpression = runningView.match(/Text\((.*)\)\.fontSize\(14\)/)[1];
function view(owner) { return { loading: loadingLine[1] ? Function('return ' + loadingLine[1]).call(owner) : true,
  cancel: !!Function('return ' + cancelCondition).call(owner), label: Function('return ' + labelExpression).call(owner) }; }

for (const [status, label] of [['completed', '已完成'], ['killed', '已停止'], ['failed', '失败']]) {
  test(`known ${status} hides stale progress/spinner/cancel while preserving original tool media`, async () => {
    const f = fixture(), original = f.owner.meta; await f.owner.watchJob();
    f.callbacks[0].items([{ id: 'job-a', status: 'running', progress: '视频正在排队' }]);
    assert.equal(view(f.owner).cancel, true);
    f.callbacks[0].items([{ id: 'job-a', status, progress: 'stale queued line' }]);
    assert.deepEqual(view(f.owner), { loading: false, cancel: false, label });
    await f.owner.cancel(); assert.deepEqual(f.kills, []); assert.equal(f.owner.meta, original); assert.deepEqual(original.items, []);
    f.callbacks[0].items([{ id: 'job-a', status: 'running', progress: 'late stale progress' }]);
    assert.deepEqual(view(f.owner), { loading: false, cancel: false, label });
  });
}

test('absent/unknown jobs never invent completion and unrelated jobs cannot affect the card', async () => {
  const f = fixture(); await f.owner.watchJob();
  for (const jobs of [[], [{ id: 'job-other', status: 'completed' }], [{ id: 'job-a', status: 'future-status' }]]) {
    f.callbacks[0].items(jobs); assert.equal(view(f.owner).loading, true); assert.equal(view(f.owner).cancel, true);
    assert.notEqual(view(f.owner).label, '已完成');
  }
});

test('connection/session/job identity fences late stream data and releases late subscriptions', async () => {
  for (const change of [f => f.connection('two'), f => { f.owner.sessionId = 'session-b'; }, f => { f.owner.meta = { ...f.owner.meta, job: 'job-b' }; }]) {
    const f = fixture(); await f.owner.watchJob(); change(f);
    f.callbacks[0].items([{ id: 'job-a', status: 'completed', progress: 'wrong scope' }, { id: 'job-b', status: 'completed', progress: 'wrong job' }]);
    assert.equal(f.owner.progress, ''); assert.equal(view(f.owner).loading, true);
  }
  const f = fixture(); let resolve; f.owner.client.watchJobs = () => new Promise(r => { resolve = r; });
  const watching = f.owner.watchJob(); f.owner.active = false; resolve(() => f.stops.push('late')); await watching;
  assert.deepEqual(f.stops, ['late']);
});

test('cancel requests stopping, prevents duplicates, and a terminal stream wins the pending kill response', async () => {
  const f = fixture(); await f.owner.watchJob(); let resolve;
  f.owner.client.killJob = async (session, job) => { f.kills.push({ session, job }); return new Promise(r => { resolve = r; }); };
  const pending = f.owner.cancel(); await f.owner.cancel(); assert.equal(f.kills.length, 1);
  f.callbacks[0].items([{ id: 'job-a', status: 'killed' }]); resolve(true); await pending;
  assert.deepEqual(view(f.owner), { loading: false, cancel: false, label: '已停止' });
  const g = fixture(); await g.owner.watchJob(); await g.owner.cancel(); await g.owner.cancel();
  assert.equal(g.kills.length, 1); assert.equal(view(g.owner).label, '正在停止');
});

test('already-finished kill result hides actions without fabricating a successful media result', async () => {
  const f = fixture(); f.owner.client.killJob = async () => false; await f.owner.cancel();
  assert.deepEqual(view(f.owner), { loading: false, cancel: false, label: '任务已结束，等待结果更新' });
  assert.equal(f.owner.meta.status, 'running'); assert.deepEqual(f.owner.meta.items, []);
});

test('an older running stream snapshot cannot reverse an acknowledged stop request', async () => {
  const f = fixture(); await f.owner.watchJob(); await f.owner.cancel();
  f.callbacks[0].items([{ id: 'job-a', status: 'running', progress: 'delayed queued snapshot' }]);
  assert.equal(view(f.owner).label, '正在停止'); await f.owner.cancel(); assert.equal(f.kills.length, 1);
  f.callbacks[0].items([{ id: 'job-a', status: 'killed' }]);
  assert.deepEqual(view(f.owner), { loading: false, cancel: false, label: '已停止' });
});

test('late cancellation failure cannot write into a replacement connection or job', async () => {
  for (const change of [f => f.connection('two'), f => { f.owner.sessionId = 'session-b'; }, f => { f.owner.meta = { ...f.owner.meta, job: 'job-b' }; }]) {
    const f = fixture(); let reject; f.owner.client.killJob = () => new Promise((_r, r) => { reject = r; });
    const pending = f.owner.cancel(); change(f); reject(new Error('old failure')); await pending;
    assert.equal(f.owner.error, '');
  }
});

test('terminal initial snapshot disposes the subscription that resolves after its callback', async () => {
  const f = fixture();
  f.owner.client.watchJobs = async (_session, items) => { items([{ id: 'job-a', status: 'completed' }]); return () => f.stops.push('initial'); };
  await f.owner.watchJob(); assert.deepEqual(f.stops, ['initial']); assert.equal(f.owner.stop, undefined);
  assert.equal(view(f.owner).cancel, false);
});

test('reset clears terminal state for a new job and fences the old generation', async () => {
  const f = fixture(); await f.owner.watchJob(); const old = f.callbacks[0];
  old.items([{ id: 'job-a', status: 'completed' }]);
  f.owner.meta = { ...f.owner.meta, job: 'job-b' }; f.owner.reset(); await Promise.resolve();
  old.items([{ id: 'job-a', status: 'failed' }]);
  assert.equal(f.owner.jobState, ''); assert.equal(view(f.owner).loading, true);
  f.callbacks.at(-1).items([{ id: 'job-b', status: 'running', progress: 'new job' }]);
  assert.equal(view(f.owner).label, 'new job');
});

if (process.argv[2]) {
  const compiled = readFileSync(process.argv[2], 'utf8');
  const start = compiled.indexOf('    private reset('), end = compiled.indexOf('\n    rerender()', start);
  assert.ok(start >= 0 && end > start);
  const body = stripTypeScriptTypes('(class Generated {' + compiled.slice(start, end) + '})');
  let activeNode;
  const widget = kind => new Proxy({ create() { activeNode.kind = kind; }, createWithLabel(text) { activeNode.kind = kind; activeNode.text = text; },
    enabled(value) { activeNode.enabled = value; }, onClick(callback) { activeNode.click = callback; } }, { get: (target, key) => target[key] || (() => {}) });
  const Column = widget('Column'), If = widget('If'), LoadingProgress = widget('LoadingProgress'), Button = widget('Button');
  const Text = widget('Text'); Text.create = text => { activeNode.kind = 'Text'; activeNode.text = text; };
  const Generated = Function('string', 'jobLive', 'jobStatus', 'clearMediaFiles', 'Column', 'If', 'LoadingProgress', 'Button', 'Text', 'HorizontalAlign',
    'return ' + body)(string, jobLive, jobStatus, async () => {}, Column, If, LoadingProgress, Button, Text, { Start: 0 });
  function generatedFixture() {
    const f = fixture(), nodes = []; Object.setPrototypeOf(f.owner, Generated.prototype); f.owner.colors = {}; f.owner.meta.kind = 'video';
    f.owner.observeComponentCreation2 = callback => {
      const node = { callback, active: true, parent: activeNode }; nodes.push(node);
      const previous = activeNode; activeNode = node; callback(nodes.length, true); activeNode = previous;
    };
    f.owner.ifElseBranchUpdateFunction = (branch, build) => {
      if (activeNode.branch === branch) return;
      const parent = activeNode; parent.branch = branch;
      for (const node of nodes) { for (let ancestor = node.parent; ancestor; ancestor = ancestor.parent) { if (ancestor === parent) { node.active = false; break; } } }
      build();
    };
    activeNode = undefined; f.owner.initialRender();
    f.update = () => { for (const node of [...nodes]) { if (node.active) { activeNode = node; node.callback(1, false); } } activeNode = undefined; };
    f.nodes = () => nodes.filter(node => node.active); return f;
  }
  test('compiled retained card removes spinner/cancel and refreshes text on actual completed stream', async () => {
    const f = generatedFixture(); await f.owner.watchJob();
    f.callbacks[0].items([{ id: 'job-a', status: 'running', progress: '视频正在排队' }]); f.update();
    assert.equal(f.nodes().filter(node => node.kind === 'LoadingProgress').length, 1);
    assert.ok(f.nodes().some(node => node.kind === 'Button' && node.text === '取消生成'));
    f.callbacks[0].items([{ id: 'job-a', status: 'completed' }]); f.update();
    assert.equal(f.nodes().filter(node => node.kind === 'LoadingProgress').length, 0);
    assert.ok(!f.nodes().some(node => node.kind === 'Button' && node.text === '取消生成'));
    assert.ok(f.nodes().some(node => node.kind === 'Text' && node.text === '已完成'));
  });
  test('compiled stopped card hides cancellation and a previously captured click cannot kill again', async () => {
    const f = generatedFixture(); await f.owner.watchJob();
    const button = f.nodes().find(node => node.kind === 'Button' && node.text === '取消生成'); assert.ok(button?.click);
    f.callbacks[0].items([{ id: 'job-a', status: 'killed' }]); f.update(); button.click(); await Promise.resolve();
    assert.deepEqual(f.kills, []); assert.ok(f.nodes().some(node => node.kind === 'Text' && node.text === '已停止'));
    assert.ok(!f.nodes().some(node => node.kind === 'Button' && node.text === '取消生成'));
  });
}
