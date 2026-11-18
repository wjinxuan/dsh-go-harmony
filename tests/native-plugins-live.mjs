import { loadPluginConnection } from './native-plugin-loader.mjs';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdir, readFile, realpath, writeFile, symlink } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { loadDshClient } from './dsh-client-node-fixture.mjs';
const temp = await realpath(resolve(process.argv[2])); const runtime = join(temp, 'runtime'); const home = join(temp, 'home');
const root = fileURLToPath(new URL('../', import.meta.url)); await mkdir(home, { recursive: true });
const plugin = join(runtime, 'node_modules', 'harmony-native-fixture'); await mkdir(plugin, { recursive: true });
await writeFile(join(plugin, 'package.json'), JSON.stringify({ name: 'harmony-native-fixture', type: 'module', version: '1.0.0', main: 'index.js', dsh:{bundle:{patch:'./cordis.patch.yml'}},
  dshGo: { v: 1, assets: 'assets', minApp: '1.0.0', wants: ['draft'], contributes: { 'composer.actions': [{ id: 'greet', label: 'Fixture greet' }], panels: [{ id: 'status', title: 'Fixture panel', placement: ['features'],live:true }] } } }));
await mkdir(join(plugin,'assets'));
const assetBytes=await readFile(join(root,'entry/src/main/resources/base/media/companion_widget_idle.png'));await writeFile(join(plugin,'assets','fixture.png'),assetBytes);
await writeFile(join(plugin, 'index.js'), `import z from '@deepseek-ai/schemastery';
export const name='harmony-native-fixture';
export const Config=z.object({label:z.string().default('Before')});
export function apply(ctx,config){ctx.inject(['dshGo'],ctx=>{
 ctx.dshGo.on('greet',(scope)=>({insert:'Synthetic '+scope.draft}));
 ctx.dshGo.panel('status',{view:{type:'stack',title:'Fixture',children:[{type:'text',text:{$:'data.label'}}]},data(scope,emit){emit({label:config.label});const timer=setTimeout(()=>emit({label:'Stream update'}),300);return()=>clearTimeout(timer)},actions:{refresh:()=>({patch:{label:'Updated'}}),later:()=>({pending:{label:'Fixture wait',timeoutMs:1000},result:async signal=>{await new Promise(r=>setTimeout(r,100));return {toast:'Fixture done'}}}),cancel:()=>({pending:{timeoutMs:1000},result:signal=>new Promise((resolve,reject)=>signal.addEventListener('abort',()=>reject(Error('cancelled'))))})}});
});}`);
await writeFile(join(plugin,'cordis.patch.yml'),'- insert:\n    - id: harmony-native-fixture\n      name: harmony-native-fixture\n');
await mkdir(join(home,'profile','node_modules'),{recursive:true});
await symlink(plugin,join(home,'profile','node_modules','harmony-native-fixture'));
await mkdir(join(home,'node_modules'),{recursive:true});await symlink(plugin,join(home,'node_modules','harmony-native-fixture'));
const mainPath=join(runtime,'main.cjs');let main=await readFile(mainPath,'utf8');
await writeFile(mainPath,main.replace("const startedBundles = ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app'];","const startedBundles = ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app','harmony-native-fixture'];").replace('dependencies: {}, dsh:',"dependencies: {'harmony-native-fixture':'file:"+plugin+"'}, dsh:"));

const DshClient = await loadDshClient(join(root, 'entry/src/main/ets/dsh/DshClient.ets'), join(runtime, 'main.cjs'), temp);
const child = spawn(process.execPath, ['--jitless', '--no-addons', '--expose-internals', '--require', join(root, 'tests/local-flock-fixture.cjs'), join(runtime, 'main.cjs'), home], { stdio: ['ignore', 'pipe', 'pipe'],env:{...process.env,DSH_HARMONY_DEBUG:'1'} });
let logs = ''; child.stdout.on('data', b => { logs += b }); child.stderr.on('data', b => { logs += b });
const client = new DshClient();
try {
 let ready; for(let i=0;i<300&&!ready;i++){ready=await readFile(join(home,'ready.json'),'utf8').then(JSON.parse,()=>undefined);if(child.exitCode!==null)throw Error('Engine exited '+logs.slice(-4000));if(!ready)await delay(50);}
 assert.ok(ready, logs.slice(-4000)); await client.connect(ready.url, undefined, true);
 assert.deepEqual(Buffer.from(await client.pluginAsset('harmony-native-fixture','fixture.png')),assetBytes,'actual authenticated binary assets retain every byte');
 assert.match(await client.webBootPage(),/__DSH_BOOT__/,'host boot graph is read as text only');
 const caps = { v:'1',app:'1.0.15',locale:'zh-CN',surfaces:'composer.actions,panels',components:'stack,text' };
 let contributions;
 for(let i=0;i<40;i++){contributions=await client.bridgeJson('GET','/dsh-go/v1/contributions',caps);if(contributions?.plugins.some(p=>p.pkg==='harmony-native-fixture'))break;await delay(100);}
 const fixture=contributions.plugins.find(p=>p.pkg==='harmony-native-fixture'); if (!fixture) console.log('Fixture diagnostic', (await client.listPlugins()).filter(row=>JSON.stringify(row).includes('harmony-native-fixture')), (await client.listPluginBundles()).find(row=>row.name==='harmony-native-fixture'));  assert.ok(fixture, JSON.stringify(contributions)+'\n'+logs.slice(-5000)); assert.equal(fixture.native,true);
 const view=await client.bridgeJson('GET','/dsh-go/v1/views/harmony-native-fixture/status',caps); assert.equal(view.data.label,'Before');
 const result=await client.bridgeJson('POST','/dsh-go/v1/invoke',{}, {v:1,pkg:'harmony-native-fixture',id:'greet',surface:'composer.actions',scope:{},context:{draft:'draft'},locale:'zh-CN',userGesture:true});
 assert.deepEqual(result.effects,[{type:'insert',text:'Synthetic draft'}]);
 const NativePluginConnection=await loadPluginConnection(runtime);const stream=new NativePluginConnection(client,'en');let streamData;
 stream.onData=value=>{streamData=value};await stream.subscribe({pkg:'harmony-native-fixture',id:'status'}, {},view.data,view.rev??'');
 for(let i=0;i<60&&streamData?.label!=='Stream update';i++)await delay(25);assert.equal(streamData.label,'Stream update','native stream receives real initial snapshot and update');
 const conn=await stream.open();const invoke={v:1,pkg:'harmony-native-fixture',id:'status',surface:'panel',scope:{},stream:conn,userGesture:true};
 const ack=await client.bridgeJson('POST','/dsh-go/v1/invoke',{}, {...invoke,action:'later'});assert.ok(ack.pending?.id);assert.deepEqual((await stream.result(ack)).effects,[{type:'toast',text:'Fixture done'}]);
 const cancelAck=await client.bridgeJson('POST','/dsh-go/v1/invoke',{}, {...invoke,action:'cancel'});const cancelled=stream.result(cancelAck);stream.cancelPending();await assert.rejects(cancelled,/结束/);stream.close();
 const configList=await client.bridgeJson('GET','/dsh-go/v1/plugin-config'); const entry=(Array.isArray(configList)?configList:configList.entries).find(e=>e.entryId==='harmony-native-fixture'); assert.ok(entry?.configurable,JSON.stringify(entry)+'\n'+logs.slice(-30000));
 const detail=await client.bridgeJson('GET','/dsh-go/v1/plugin-config/harmony-native-fixture'); assert.equal(detail.value.label,'Before');
 const changed=await client.bridgeJson('POST','/dsh-go/v1/plugin-config/harmony-native-fixture',{}, {revision:detail.revision,ops:[{op:'set',path:['label'],value:'After'}]},60000);
 assert.equal((changed.entry??changed).value.label,'After');
 await assert.rejects(client.bridgeJson('POST','/dsh-go/v1/plugin-config/harmony-native-fixture',{}, {revision:detail.revision,ops:[{op:'set',path:['label'],value:'Wrong'}]}),/conflict/);
 assert.equal((await client.bridgeJson('GET','/dsh-go/v1/plugin-config/harmony-native-fixture')).value.label,'After');
 const unauthenticated=await fetch(ready.url+'/dsh-go/v1/contributions'); assert.equal(unauthenticated.status,401);
 await assert.rejects(client.bridgeJson('GET','https://evil.example/dsh-go/v1/contributions'),/路径/);
 await assert.rejects(client.bridgeJson('GET','/dsh-go/v1/views/x/%2e%2e/config'),/路径/);
 const settings=await client.describeSettings(); assert.ok(settings.namespaces.some(ns=>ns.ns==='dsh-media'), 'real media settings registered');
 const blocked={inspect:{spec:'harmony-native-fixture'},listVersions:{name:'harmony-native-fixture'},updateBundle:{name:'harmony-native-fixture',version:'1.0.1'},installBundle:{spec:'harmony-native-fixture',options:{approvedBuilds:['*']}},removeBundle:{name:'harmony-native-fixture'},setPluginEnabled:{id:'include:harmony-native-fixture',enabled:false},setBundleEnabled:{name:'harmony-native-fixture',enabled:false},setVersionExemption:{packageVersion:'fixture@1.0.0',runtimeVersion:'0.2.2-rc.1',enabled:true,acceptRisk:true},waitForInstall:{requestId:'fixture'},cancelInstall:{requestId:'fixture'}};
 for(const [method,args] of Object.entries(blocked)) await assert.rejects(client.request('pluginManager/'+method,args),/unsupported-platform/,method);
 const inventory=await client.pluginInventory(); assert.equal(inventory.managementAvailable,false,'local package scripts stay disabled');
 const sibling=await client.forkConnection();assert.ok((await sibling.describeSettings()).namespaces.length);sibling.close();assert.ok((await client.describeSettings()).namespaces.length,'closing companion subscription keeps main connection alive');
 const snapshot=await client.companionJson('GET','');assert.equal(snapshot.v,1);const touched=await client.companionJson('POST','/events',{storeId:snapshot.storeId,expectedRevision:snapshot.revision,type:'pet'});assert.ok(touched.revision>=snapshot.revision);
 const beforeMemory=await client.companionJson('GET','/memories');const memoryId='84b7cf4a-8732-4c84-819c-44537a39a843';await client.companionJson('POST','/memories',{storeId:beforeMemory.storeId,expectedRevision:beforeMemory.revision,memory:{id:memoryId,kind:'fact',text:'Synthetic confirmed fixture only',keywords:[],pinned:true,source:{kind:'manual'},expiresAt:null}});
 await assert.rejects(client.companionJson('POST','/memories/delete',{storeId:beforeMemory.storeId,expectedRevision:beforeMemory.revision,id:memoryId}),/conflict/);const afterMemory=await client.companionJson('GET','/memories');assert.ok(afterMemory.memories.some(m=>m.id===memoryId));await client.companionJson('POST','/memories/delete',{storeId:afterMemory.storeId,expectedRevision:afterMemory.revision,id:memoryId});
 await assert.rejects(client.companionJson('GET','/../../credentials'),/路径/);
 const owned=await client.forkConnection();client.close();await assert.rejects(owned.describeSettings(),/连接|closed|Closed/);await client.connect(ready.url,undefined,true);
 console.log('PASS: actual authenticated binary asset + text-only boot graph, packaged bridge contribution/view/invoke, native stream snapshot/update/deferred completion/cancel, editable config save + stale revision rejection, unauthenticated 401, companion state/memory optimistic writes + isolated child client closure, media namespace and disabled local package scripts (synthetic plugin only).');
} finally {
 client.close(); await writeFile(join(home,'stop'),''); await Promise.race([once(child,'exit'),delay(5000)]);if(child.exitCode===null)child.kill('SIGKILL');
 await writeFile(join(temp,'native-plugins-engine.log'),logs);
}
