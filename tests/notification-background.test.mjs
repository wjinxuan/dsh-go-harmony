// Executes production EntryAbility lifecycle methods and ChatNotifications with an OS adapter.
// This verifies the transient-task contract; actual device freezing/publishing remains a phone test.
import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync, existsSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import { ChatNotifications } from './ui/ChatNotifications.ts';
import { backgroundRequests, backgroundCancels, backgroundLogs, resetBackground, holdPublish, rejectBackground, rejectBackgroundCancel, grantBackground, allow, notices, hilog } from './notification-fixture.mjs';
const helperPath = new URL('./ui/BackgroundCompletion.ts', import.meta.url);
const completion = existsSync(helperPath) ? (await import(helperPath.href)).backgroundCompletion : undefined;
const state = new Map();
globalThis.AppStorage = { get: key => state.get(key), setOrCreate: (key, value) => state.set(key, value) };
const tick = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve; const promise = new Promise(r => resolve = r); return { promise, resolve }; };
const ended = { records: [{type:'event',event:{seq:9,type:'turn/end',data:{reason:{kind:'completed'}}}}] };
function ability() {
  const source = readFileSync(process.argv[2]+'/entry/src/main/ets/entryability/EntryAbility.ets','utf8')
    .replace(/^import .*$/gm,'').replace('export default class','class');
  const Entry = vm.runInNewContext(stripTypeScriptTypes(source)+'\nEntryAbility',
    { UIAbility: class {}, AppStorage, backgroundCompletion: completion, hilog });
  return new Entry();
}
function setup(page = async () => ended) {
  completion?.destroy(); resetBackground(); state.set('dshForeground', true); state.set('dshLanguage', 'zh');
  let listener, identity=1;
  const client = { connectionIdentity:()=>identity, onHostEvent:fn=>{listener=fn;return()=>listener=undefined}, request:page };
  const monitor = new ChatNotifications(client,{},'owned-test',()=>'',()=>AppStorage.get('dshForeground'),()=>{});
  return { monitor, entry:ability(), emit:running=>listener?.({type:'emit',event:'api-session/status',args:['owned-session',running]}), switch:()=>identity++ };
}
test('an already running conversation requests one real SDK lease synchronously inside EntryAbility.onBackground', async () => {
  const h=setup(); await h.monitor.start();
  try { h.emit(true); assert.equal(backgroundRequests.length,0); h.entry.onBackground(); assert.equal(backgroundRequests.length,1,'active completion work must request transient time before onBackground returns'); h.entry.onBackground(); assert.equal(backgroundRequests.length,1); }
  finally { h.monitor.stop(); completion?.destroy(); }
});
test('completion retains the lease through page lookup and notification publish, then cancels it', async () => {
  const page=deferred(), publish=deferred(); const h=setup(()=>page.promise); holdPublish(()=>publish.promise); await h.monitor.start();
  try { h.emit(true); h.entry.onBackground(); assert.equal(backgroundRequests.length,1); h.emit(false); await tick(); assert.deepEqual(backgroundCancels,[]); page.resolve(ended); await tick(); assert.deepEqual(backgroundCancels,[],'do not release before native publish resolves'); publish.resolve(); await tick(); assert.deepEqual(backgroundCancels,[backgroundRequests[0].requestId]); }
  finally { page.resolve(ended); publish.resolve(); h.monitor.stop(); completion?.destroy(); }
});
test('EntryAbility foreground and destroy release the owned lease without canceling model work', async () => {
  const h=setup(); await h.monitor.start();
  try { h.emit(true); h.entry.onBackground(); assert.equal(backgroundRequests.length,1); h.entry.onForeground(); assert.deepEqual(backgroundCancels,[1]); h.entry.onBackground(); assert.equal(backgroundRequests.length,2); h.entry.onDestroy(); assert.deepEqual(backgroundCancels,[1,2]); }
  finally { h.monitor.stop(); completion?.destroy(); }
});
test('idle background and tasks observed only after background do not request time outside the lifecycle callback', async () => {
  const h=setup(); await h.monitor.start();
  try { h.entry.onBackground(); h.emit(true); await tick(); assert.equal(backgroundRequests.length,0); h.entry.onBackground(); assert.equal(backgroundRequests.length,0); h.entry.onForeground(); h.entry.onBackground(); assert.equal(backgroundRequests.length,1); }
  finally { h.monitor.stop(); completion.destroy(); }
});
test('one shared lease remains until every observed session and all completion deliveries are finished', async () => {
  const pages=[deferred(),deferred()]; let calls=0, listener;
  const h=setup(); h.monitor.stop();
  const client={connectionIdentity:()=>1,onHostEvent:fn=>{listener=fn;return()=>listener=undefined},request:()=>pages[calls++].promise};
  const monitor=new ChatNotifications(client,{},'owned-test',()=>'',()=>AppStorage.get('dshForeground'),()=>{});
  const emit=(id,running)=>listener({type:'emit',event:'api-session/status',args:[id,running]});
  await monitor.start();
  try { emit('first',true); emit('second',true); h.entry.onBackground(); assert.equal(backgroundRequests.length,1); emit('first',false); pages[0].resolve(ended); await tick(); assert.deepEqual(backgroundCancels,[]); emit('second',false); await tick(); assert.deepEqual(backgroundCancels,[]); pages[1].resolve(ended); await tick(); assert.deepEqual(backgroundCancels,[1]); }
  finally { pages.forEach(p=>p.resolve(ended)); monitor.stop(); completion.destroy(); }
});
test('expiry cancels once, never renews in background, and an old expiry cannot cancel a later lease', async () => {
  const h=setup(); await h.monitor.start();
  try { grantBackground(60000); h.emit(true); h.entry.onBackground(); const old=backgroundRequests[0]; assert.ok(backgroundLogs.some(row=>row.includes('granted')&&row.includes(60000))); h.entry.onForeground(); h.entry.onBackground(); old.expire(); assert.deepEqual(backgroundCancels,[1]); const current=backgroundRequests[1]; current.expire(); current.expire(); assert.deepEqual(backgroundCancels,[1,2]); h.emit(true); h.entry.onBackground(); await tick(); assert.equal(backgroundRequests.length,2); }
  finally { h.monitor.stop(); completion.destroy(); }
});
test('a stopped or replaced host cannot release the new host lease through a late page reply or expiry', async () => {
  const page=deferred(); const old=setup(()=>page.promise); await old.monitor.start(); let next;
  try { old.emit(true); old.entry.onBackground(); const expiry=backgroundRequests[0].expire; old.emit(false); old.monitor.stop(); assert.deepEqual(backgroundCancels,[1]);
    let listener; const client={connectionIdentity:()=>2,onHostEvent:fn=>{listener=fn;return()=>listener=undefined},request:async()=>ended};
    next=new ChatNotifications(client,{},'new-owned-host',()=>'',()=>AppStorage.get('dshForeground'),()=>{}); await next.start(); listener({type:'emit',event:'api-session/status',args:['new-owned-session',true]});
    assert.equal(backgroundRequests.length,1,'host replacement in background must not request'); old.entry.onForeground(); old.entry.onBackground(); assert.equal(backgroundRequests.length,2);
    page.resolve(ended); await tick(); expiry(); old.monitor.stop(); assert.deepEqual(backgroundCancels,[1]); next.stop(); assert.deepEqual(backgroundCancels,[1,2]);
  } finally { page.resolve(ended); old.monitor.stop(); next?.stop(); completion.destroy(); }
});
test('request denial logs only a safe error code and never retries during the same background interval', async () => {
  const h=setup(); await h.monitor.start();
  try { rejectBackground(9900002); h.emit(true); h.entry.onBackground(); assert.equal(backgroundRequests.length,0); h.emit(false); await tick(); h.emit(true); h.entry.onBackground(); assert.equal(backgroundLogs.filter(row=>row.includes('request-failed')).length,1); assert.ok(backgroundLogs.some(row=>row.includes(9900002))); assert.ok(!JSON.stringify(backgroundLogs).includes('private fixture message')); }
  finally { h.monitor.stop(); completion.destroy(); }
});
test('cancel failure does not crash or allow a second lease over the unconfirmed first one', async () => {
  const h=setup(); await h.monitor.start();
  try { h.emit(true); h.entry.onBackground(); rejectBackgroundCancel(9800004); h.entry.onForeground(); h.entry.onBackground(); assert.equal(backgroundRequests.length,1); assert.ok(backgroundLogs.some(row=>row.includes('cancel-failed')&&row.includes(9800004))); assert.ok(!JSON.stringify(backgroundLogs).includes('private cancel failure')); rejectBackgroundCancel(undefined); h.entry.onForeground(); assert.deepEqual(backgroundCancels,[1,1]); }
  finally { rejectBackgroundCancel(undefined); h.monitor.stop(); completion.destroy(); }
});
test('page failure, denied notification permission and publish failure all release completion ownership', async () => {
  for(const stage of ['page','permission','publish']){
    const failure=Object.assign(new Error('secret owned content must not enter diagnostics'),{code:1600004});
    const h=setup(stage==='page'?async()=>{throw failure}:async()=>ended); await h.monitor.start();
    try { if(stage==='permission')allow(false); if(stage==='publish')holdPublish(async()=>{throw failure}); const before=notices.length; h.emit(true); h.entry.onBackground(); h.emit(false); await tick(); assert.deepEqual(backgroundCancels,[1],stage); if(stage!=='publish')assert.equal(notices.length,before); assert.ok(!JSON.stringify(backgroundLogs).includes('secret owned content')); if(stage!=='permission')assert.ok(backgroundLogs.some(row=>row.includes(1600004))); }
    finally { h.monitor.stop(); completion.destroy(); }
  }
});
