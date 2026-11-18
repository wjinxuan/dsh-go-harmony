// Local, synthetic device UI fixture. It appends only two owned Cordis rows;
// official host modules, credentials, sessions and terminal services stay intact.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomUUID, createHash } from 'node:crypto';
import { once } from 'node:events';
import { cp, mkdir, readFile, realpath, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { loadDshClient } from './dsh-client-node-fixture.mjs';
import { loadPluginConnection } from './native-plugin-loader.mjs';

process.umask(0o077);
const [binArg, metaArg, dirArg, flag] = process.argv.slice(2);
assert.ok(binArg && metaArg && dirArg && (!flag || ['--cleanup', '--probe'].includes(flag)),
  'node tests/native-plugin-device-fixture.mjs <official-bin> <owned-server-meta.json> <new-artifact-dir> [--cleanup|--probe]');
const bin = await realpath(resolve(binArg)), metaPath = await realpath(resolve(metaArg));
await mkdir(resolve(dirArg), { recursive: true });
const out = await realpath(resolve(dirArg)), project = fileURLToPath(new URL('../', import.meta.url));
const pkg = 'dsh-harmony-device-native-fixture', statePath = join(out, 'mount.json');
const hash = value => createHash('sha256').update(value).digest('hex');
const { withFileLock, writeFileAtomic } = await import(pathToFileURL(join(dirname(bin), '../../dsh-atomic-write/lib/index.js')));
const meta = JSON.parse(await readFile(metaPath, 'utf8'));
assert.equal(meta.state, 'running'); assert.equal(meta.host, '127.0.0.1');
assert.ok(meta.root.startsWith('/private/tmp/') || meta.root.startsWith('/tmp/'));
const profile = join(meta.root, 'dsh/profiles/web'), targetPatch = join(profile, 'cordis.patch.yml');
const clientDir = join(out, 'client'); await mkdir(clientDir, { recursive: true });
const Client = await loadDshClient(join(project, 'entry/src/main/ets/dsh/DshClient.ets'), bin, clientDir);
async function until(check, label, count = 240) {
  for (let i = 0; i < count; i++) { const result = await check(); if (result) return result; await delay(50); }
  throw new Error(label);
}
async function changePatch(path, before, after) {
  await withFileLock(join(dirname(path), 'package.json'), async () => {
    assert.equal(await readFile(path, 'utf8'), before, 'CAS: profile changed; do not overwrite it');
    await writeFileAtomic(path, after, { mode: 0o600 });
  });
}
function appendBlock(before, block) {
  const meaningful = before.split('\n').filter(line => line.trim() && !line.trim().startsWith('#')).join('\n').trim();
  // A fresh official profile is a commented YAML `[]`, not an empty file.
  const base = meaningful === '[]' ? before.replace(/^\[\][ \t]*\r?$/m, '') : before;
  assert.ok(!meaningful || meaningful === '[]' || meaningful.startsWith('-'), 'Expected a block YAML patch array');
  return base + block;
}
async function loaded(c, enabled) {
  await until(async () => {
    const rows = await c.listPlugins().catch(error => { if (error.code === 'gateway/internal') return []; throw error; });
    const item = rows.find(row => row.entryId === 'include:device-native-ui');
    return enabled ? item?.fiberPhase === 'active' : !item;
  }, `Fixture ${enabled ? 'load' : 'unload'} timed out`);
}
const caps = { v: '1', app: '1.0.15', locale: 'zh-CN', surfaces: 'panels,composer.actions',
  components: 'stack,text,form,textField,number,toggle,slider,select,actions,chart,image,metric,progress,callout' };
async function inspect(c) {
  const contributions = await c.bridgeJson('GET', '/dsh-go/v1/contributions', caps);
  const plugin = contributions?.plugins.find(row => row.pkg === pkg);
  assert.ok(plugin?.native); assert.equal(plugin.state, 'ok');
  const views = {};
  for (const id of ['controls', 'charts', 'images']) {
    views[id] = await c.bridgeJson('GET', `/dsh-go/v1/views/${pkg}/${id}`, caps);
    assert.ok(views[id].view);
  }
  assert.equal(views.controls.view.v, 2);
  assert.deepEqual(Buffer.from(await c.pluginAsset(pkg, 'fixture.png')), await readFile(join(out, 'plugin/assets/fixture.png')));
  return { contributions, views };
}
if (flag === '--probe') {
  const c = new Client(); let stream;
  try {
    await c.connect((await readFile(meta.urlFile, 'utf8')).trim());
    const result = await inspect(c);
    const Connection = await loadPluginConnection(resolve(dirname(bin), '../../../..'));
    stream = new Connection(c, 'zh'); let data;
    stream.onData = value => { data = value; };
    await stream.subscribe({ pkg, id: 'controls' }, {}, result.views.controls.data, result.views.controls.rev || '');
    const connection = await stream.open();
    const invoke = action => c.bridgeJson('POST', '/dsh-go/v1/invoke', {}, { v: 1, pkg, id: 'controls', surface: 'panel',
      scope: {}, locale: 'zh-CN', stream: connection, userGesture: true, ...action });
    const values = { 'data.name': 'HOST_PROTOCOL_PREFLIGHT', 'data.amount': 7, 'data.enabled': true, 'data.level': 60, 'data.choice': 'B' };
    const saved = await stream.result(await invoke({ action: 'save', value: { values } }));
    assert.ok(saved.effects.some(effect => effect.type === 'patch' && effect.data?.name === 'HOST_PROTOCOL_PREFLIGHT'));
    await until(() => data?.name === 'HOST_PROTOCOL_PREFLIGHT' && data?.amount === 7 && data?.enabled === true && data?.level === 60 && data?.choice === 'B', 'Real native stream did not echo the submitted controls');
    const count = data.count;
    await stream.result(await invoke({ action: 'increment' }));
    await until(() => data?.count === count + 1, 'Real native action increment missing');
    await stream.result(await invoke({ action: 'reset' }));
    await until(() => data?.count === 0 && data?.name === 'phone fixture', 'Fixture reset missing');
    const events = (await readFile(join(out, 'plugin/events.jsonl'), 'utf8')).trim().split('\n').length;
    await writeFile(join(out, 'protocol-preflight.json'), JSON.stringify({ success: true, realNativeStream: true, submittedValues: values, resetConfirmed: true, excludeEventsThroughLine: events, time: new Date().toISOString() }, null, 2));
    console.log('PASS: actual stream form submit + all five values + increment + reset; phone starts after recorded event boundary.');
  } finally { stream?.close(); c.close(); }
} else if (flag === '--cleanup') {
  const state = JSON.parse(await readFile(statePath, 'utf8'));
  assert.equal(state.metaPath, metaPath); assert.equal(state.pid, meta.dshPid);
  const current = await readFile(targetPatch, 'utf8');
  assert.equal(current.split(state.block).length, 2, 'Owned block must occur exactly once');
  const c = new Client();
  try {
    await c.connect((await readFile(meta.urlFile, 'utf8')).trim());
    const remaining = current.replace(state.block, '');
    await changePatch(targetPatch, current, remaining === state.mountedBase ? state.before : remaining);
    await loaded(c, false);
    const sessions = await c.listSessions();
    for (const id of state.sessionsBefore) assert.ok(sessions.some(row => row.id === id));
    await writeFile(join(out, 'cleanup.json'), JSON.stringify({ success: true, pid: meta.dshPid, retainedSessions: state.sessionsBefore, patchSha256: hash(await readFile(targetPatch)), time: new Date().toISOString() }, null, 2));
    console.log('PASS: only owned plugin rows removed; original host and sessions retained.');
  } finally { c.close(); }
} else {
  assert.equal(await readFile(statePath).then(() => true, () => false), false, 'Use a new artifact directory');
  const bridge = join(out, 'bridge'), plugin = join(out, 'plugin');
  await cp(join(project, 'runtime/vendor/dsh-go-bridge'), bridge, { recursive: true });
  await mkdir(join(plugin, 'assets'), { recursive: true });
  await cp(join(project, 'entry/src/main/resources/base/media/companion_widget_idle.png'), join(plugin, 'assets/fixture.png'));
  await writeFile(join(plugin, 'package.json'), JSON.stringify({ name: pkg, version: '1.0.0', type: 'module', main: 'index.js',
    dshGo: { v: 1, title: '合成 UI 验收', assets: 'assets', wants: ['draft'], contributes: {
      panels: ['controls', 'charts', 'images'].map((id, i) => ({ id, title: ['合成控件', '合成图表', '合成图片'][i], placement: ['features', 'quick'], live: id === 'controls' })),
      'composer.actions': [{ id: 'greet', label: '合成插入' }] } } }, null, 2));
  const controls = { v: 2, type: 'stack', title: '合成控件 · 本地测试', children: [
    { type: 'text', text: { $: 'data.status' } },
    { type: 'metric', label: '服务端事件', value: { $: 'data.count' } },
    { type: 'form', submitLabel: '提交合成表单', submit: { id: 'save' }, children: [
      { type: 'textField', label: '验收文字', bind: 'data.name', required: true, maxLength: 80 },
      { type: 'number', label: '数值 0–10', bind: 'data.amount', min: 0, max: 10 },
      { type: 'toggle', label: '合成开关', bind: 'data.enabled' },
      { type: 'slider', label: '滑动 0–100', bind: 'data.level', min: 0, max: 100, step: 10 },
      { type: 'select', label: '合成选项', bind: 'data.choice', options: ['A', 'B', 'C'] }
    ] },
    { type: 'actions', items: [{ label: '服务端加一', action: { id: 'increment' } }, { label: '重置表单', action: { id: 'reset' } }] }
  ] };
  const charts = { type: 'stack', title: '合成图表 · 固定数据', children: [
    { type: 'chart', title: '折线含空值', kind: 'line', categories: ['一', '二', '三', '四'], series: [{ name: '甲', values: [-2, 3, null, 5] }, { name: '乙', values: [1, 2, 4, 3] }] },
    { type: 'chart', title: '正负柱图', kind: 'bar', categories: ['甲', '乙', '丙'], series: [{ name: '值', values: [-4, 2, 6] }] },
    { type: 'chart', title: '环图 20/30/50', kind: 'donut', categories: ['甲', '乙', '丙'], series: [{ name: '份额', values: [20, 30, 50] }] }
  ] };
  const images = { type: 'stack', title: '合成图片 · 同源认证', children: [
    { type: 'text', text: '点击图片进入全屏；双击或捏合缩放，返回关闭。无外部图片请求。' },
    { type: 'image', src: 'asset:fixture.png', alt: '合成验收鲸鱼图片' }
  ] };
  await writeFile(join(plugin, 'views.json'), JSON.stringify({ controls, charts, images }));
  await writeFile(join(plugin, 'index.js'), `import {readFileSync,appendFileSync} from 'node:fs';
export const name=${JSON.stringify(pkg)};
const views=JSON.parse(readFileSync(new URL('./views.json',import.meta.url),'utf8'));
const initial={name:'phone fixture',amount:3,enabled:false,level:40,choice:'A',count:0,status:'等待真实手机提交'};
export function apply(ctx){ctx.inject(['dshGo'],ctx=>{
 let state={...initial};const sinks=new Set();
 const proof=(action,value)=>appendFileSync(new URL('./events.jsonl',import.meta.url),JSON.stringify({time:new Date().toISOString(),action,value})+'\\n',{mode:0o600});
 const publish=()=>{for(const emit of sinks)emit({...state})};
 ctx.dshGo.on('greet',(scope)=>{proof('greet',{draftLength:(scope.draft||'').length});return{insert:'[synthetic plugin insert]'}});
 ctx.dshGo.panel('controls',{view:views.controls,data(scope,emit){sinks.add(emit);emit({...state});return()=>sinks.delete(emit)},actions:{
 save:(_scope,event)=>{const values=event.value?.values||{};for(const key of ['name','amount','enabled','level','choice'])if(Object.hasOwn(values,'data.'+key))state[key]=values['data.'+key];state.count++;state.status='服务端已确认 '+state.count;proof('save',values);publish();return{patch:{...state},toast:'合成表单已确认'}},
 increment:()=>{state.count++;state.status='服务端已确认 '+state.count;proof('increment',{count:state.count});publish();return{patch:{...state}}},
 reset:()=>{state={...initial};proof('reset',{});publish();return{patch:{...state}}}
 }});
 for(const id of ['charts','images'])ctx.dshGo.panel(id,{view:views[id],data:()=>({})});
});}
`);
  const block = '\n# BEGIN owned-device-native-ui ' + pkg + '\n- insert:\n' +
    '    - id: device-native-bridge\n      name: ' + JSON.stringify(pathToFileURL(join(bridge, 'lib/index.js')).href) + '\n      config:\n        persist: false\n' +
    '    - id: device-native-ui\n      name: ' + JSON.stringify(pathToFileURL(join(plugin, 'index.js')).href) + '\n# END owned-device-native-ui\n';
  const rehearsal = join(out, 'rehearsal'); await mkdir(rehearsal); await mkdir(join(rehearsal, 'home')); await mkdir(join(rehearsal, 'workspace'));
  const child = spawn(process.execPath, [bin, 'web', '--host', '127.0.0.1', '--port', '0', '--no-open'], {
    cwd: join(rehearsal, 'workspace'), env: { PATH: dirname(process.execPath) + ':/usr/bin:/bin:/usr/sbin:/sbin', HOME: join(rehearsal, 'home'), DSH_HOME: join(rehearsal, 'dsh'), XDG_CONFIG_HOME: join(rehearsal, 'home/config'), XDG_CACHE_HOME: join(rehearsal, 'home/cache'), XDG_DATA_HOME: join(rehearsal, 'home/data'), NO_COLOR: '1' }, stdio: ['ignore', 'pipe', 'pipe']
  });
  let output = '', logs = '', rclient, attachment, terminal, release, session, terminalId;
  child.stdout.on('data', bytes => { output += bytes; }); child.stderr.on('data', bytes => { logs += bytes; });
  try {
    const launch = await until(() => { assert.equal(child.exitCode, null); return /^dsh web: (http:\/\/127\.0\.0\.1:\d+\/\?token=\S+)\s*$/m.exec(output)?.[1]; }, 'Rehearsal did not start', 400);
    rclient = new Client(); await rclient.connect(launch);
    session = await rclient.createSession(undefined, join(rehearsal, 'workspace'));
    const terminalSource = (await readFile(join(project, 'entry/src/main/ets/dsh/Terminal.ets'), 'utf8')).replace(/import type .* from '\.\/DshClient'.*\n/g, '').replaceAll("from './DshWire'", "from './DshWire.ts'");
    await writeFile(join(clientDir, 'Terminal.ts'), terminalSource);
    const { TerminalApi, TerminalAttachment } = await import(pathToFileURL(join(clientDir, 'Terminal.ts')));
    terminal = new TerminalApi(rclient, session); terminalId = randomUUID();
    await terminal.create(terminalId, 80, 24, '/bin/zsh'); release = await terminal.retain(terminalId);
    const frames = [], failures = [];
    attachment = new TerminalAttachment(rclient, session, terminalId, randomUUID(), await terminal.environment(), frame => frames.push(frame), error => failures.push(error));
    await attachment.open(); await until(() => frames.some(frame => frame.type === 'snapshot'), 'PTY snapshot missing');
    const probe = async suffix => {
      const filename = 'pty-pid-' + suffix + '.txt', marker = 'NATIVE_UI_' + suffix;
      assert.equal(attachment.write('printf "%s" "$$" > ' + filename + '; printf "%s%s\\n" "NATIVE_" "UI_' + suffix + '"\r'), true);
      await until(() => frames.map(frame => frame.data || '').join('').includes(marker), 'PTY output missing');
      return Number(await until(() => readFile(join(rehearsal, 'workspace', filename), 'utf8').catch(() => ''), 'PTY PID missing'));
    };
    const pid = await probe('BEFORE'); const patchPath = join(rehearsal, 'dsh/profiles/web/cordis.patch.yml'), before = await readFile(patchPath, 'utf8');
    const appended = appendBlock(before, block);
    await changePatch(patchPath, before, appended); await loaded(rclient, true); await inspect(rclient);
    assert.equal(await probe('MOUNTED'), pid); assert.ok((await rclient.listSessions()).some(row => row.id === session));
    await changePatch(patchPath, appended, before); await loaded(rclient, false);
    assert.equal(await probe('REMOVED'), pid); assert.equal(child.exitCode, null); assert.deepEqual(failures, []);
    await writeFile(join(out, 'rehearsal.json'), JSON.stringify({ success: true, dshPid: child.pid, ptyPid: pid, session, terminalId, samePtyAcrossMountAndRemoval: true, time: new Date().toISOString() }, null, 2));
    console.log('PASS: separate official host append/revert retained the same session and PTY PID.');
  } finally {
    attachment?.close(); release?.(); if (terminal && terminalId) await terminal.close(terminalId).catch(() => {});
    rclient?.close();
    if (child.exitCode === null && child.signalCode === null) { const exited = once(child, 'exit'); child.kill('SIGTERM'); if (!await Promise.race([exited.then(() => true), delay(3000, false, { ref: false })])) { child.kill('SIGKILL'); await exited; } }
    await writeFile(join(out, 'rehearsal-engine.log'), output.replace(/\?token=\S+/g, '?token=[REDACTED]') + '\n' + logs);
  }
  const c = new Client();
  try {
    await c.connect((await readFile(meta.urlFile, 'utf8')).trim());
    const before = await readFile(targetPatch, 'utf8'); assert.ok(!before.includes('device-native-ui'));
    const sessionsBefore = (await c.listSessions()).map(row => row.id);
    const appended = appendBlock(before, block);
    const state = { metaPath, pid: meta.dshPid, patchPath: targetPatch, beforeSha256: hash(before), before, mountedBase: appended.slice(0, -block.length), block, sessionsBefore, time: new Date().toISOString() };
    await writeFile(statePath, JSON.stringify(state, null, 2), { flag: 'wx' });
    await changePatch(targetPatch, before, appended);
    await loaded(c, true); const result = await inspect(c);
    const after = await c.listSessions(); for (const id of sessionsBefore) assert.ok(after.some(row => row.id === id));
    process.kill(meta.dshPid, 0);
    await writeFile(join(out, 'mounted.json'), JSON.stringify({ success: true, pid: meta.dshPid, port: meta.port, retainedSessions: sessionsBefore, plugin: pkg, pluginSha256: hash(await readFile(join(plugin, 'index.js'))), viewSha256: hash(await readFile(join(plugin, 'views.json'))), assetSha256: hash(await readFile(join(plugin, 'assets/fixture.png'))), bridgeSha256: hash(await readFile(join(bridge, 'lib/index.js'))), ...result, time: new Date().toISOString() }, null, 2));
    console.log('PASS: existing isolated host mounted authenticated synthetic controls/charts/image; original sessions retained.');
  } finally { c.close(); }
}
