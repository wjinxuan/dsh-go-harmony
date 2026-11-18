import assert from 'node:assert/strict';import test from 'node:test';import {readFileSync} from 'node:fs';import {stripTypeScriptTypes} from 'node:module';
import {planProfile} from '../runtime/share-profile.mjs';
import {ProfileShareController} from './profile-share-fixture.mjs';
function fixture(){let id=1;const calls=[],state={writable:true,namespaces:[{ns:'example',revision:1,writable:true,value:{depth:1,keep:8}}]};let blocked;
 const host={identity:()=>id,settings:async()=>structuredClone(state),bundles:async()=>[],presets:async()=>[],request:async(method,args)=>{calls.push({method,args});if(blocked)await blocked;if(method==='settings/mutate'){assert.equal(args.expectedRevision,state.namespaces[0].revision);for(const op of args.ops)state.namespaces[0].value[op.path[0]]=op.value;state.namespaces[0].revision++;return{};}if(method==='pluginManager/inspect')return {status:'accepted',name:'p',version:'1.0.0'};return {application:'applied',changed:true};}};
 const service={request:async(action,args)=>{calls.push({action,args});if(action==='profile-plan')return planProfile(args.payload,args.snapshot);if(action==='profile-backup')return{backup:'backups/fixture'};return{};},cancel:()=>{}};
 const controller=new ProfileShareController(service,host,false,true);return {controller,state,calls,host,service,retire:()=>id++,block:p=>blocked=p};}
const payload={v:1,kind:'profile',settings:{example:{depth:3}}};
test('preview and cancellation perform no writes; confirmed import preserves unrelated settings and verifies revision plus read-back',async()=>{const f=fixture();await f.controller.preview(payload);assert.equal(f.calls.filter(v=>v.method).length,0);await assert.rejects(f.controller.apply(['settings:example'],false),/确认/);await f.controller.apply(['settings:example'],true);assert.deepEqual(f.state.namespaces[0].value,{depth:3,keep:8});assert.equal(f.controller.statuses['settings:example'].state,'done');assert.equal(f.calls.find(v=>v.method==='settings/mutate').args.expectedRevision,1);});
test('concurrent host edit is a failed row, never silently overwritten; a retired target cannot apply',async()=>{const f=fixture();await f.controller.preview(payload);f.state.namespaces[0].revision++;await f.controller.apply(['settings:example'],true);assert.equal(f.controller.statuses['settings:example'].state,'failed');assert.equal(f.state.namespaces[0].value.depth,1);assert.ok(!f.calls.some(v=>v.method==='settings/mutate'));f.retire();await assert.rejects(f.controller.apply(['settings:example'],true),/主机已变更/);});
test('cancellation stops subsequent steps and duplicate apply cannot run while a mutation is pending',async()=>{const f=fixture();await f.controller.preview({...payload,settings:{example:{depth:3},second:{a:1}},plugins:[{name:'p',source:'npm',version:'1.0.0',spec:'p@1.0.0'}]});let release;f.block(new Promise(r=>release=r));const running=f.controller.apply(['plugin:p','settings:example'],true);await new Promise(r=>setImmediate(r));await assert.rejects(f.controller.apply(['plugin:p'],true),/确认/);f.controller.cancel();release();await assert.rejects(running,/取消/);assert.ok(!f.calls.some(v=>v.method==='settings/mutate'||v.method==='pluginManager/installBundle'));assert.equal(f.controller.statuses['settings:example'].state,'skipped');});
test('plugin install requires exact inspect response; changed installed packages and build approvals fail safely',async()=>{const f=fixture(),plugin={name:'p',source:'npm',version:'1.0.0',spec:'p@1.0.0'};await f.controller.preview({v:1,kind:'plugin',plugin});f.host.request=async(method,args)=>{f.calls.push({method,args});return method==='pluginManager/inspect'?{status:'accepted',name:'different',version:'1.0.0'}:{application:'applied'};};await f.controller.apply(['plugin:p'],true);assert.equal(f.controller.statuses['plugin:p'].state,'failed');assert.ok(!f.calls.some(v=>v.method==='pluginManager/installBundle'));
 const g=fixture();await g.controller.preview({v:1,kind:'plugin',plugin});g.host.request=async(method,args)=>{g.calls.push({method,args});return method==='pluginManager/inspect'?{status:'accepted',name:'p',version:'1.0.0'}:{pendingBuilds:['dependency'],application:'restart-required'};};await g.controller.apply(['plugin:p'],true);assert.equal(g.controller.statuses['plugin:p'].state,'failed');assert.ok(g.calls.find(v=>v.method==='pluginManager/installBundle').args.options.approvedBuilds===undefined);});
test('unacknowledged settings cannot report success and local readonly packages cannot enter apply',async()=>{const f=fixture();await f.controller.preview(payload);f.host.request=async()=>({});await f.controller.apply(['settings:example'],true);assert.equal(f.controller.statuses['settings:example'].state,'failed');const local=new ProfileShareController(f.service,f.host,true,false);await local.preview({v:1,kind:'plugin',plugin:{name:'p',source:'npm',spec:'p@1.0.0',version:'1.0.0'}});assert.ok(local.plan.changes[0].blocked);await assert.rejects(local.apply(['plugin:p'],true),/选择已失效/);});
test('new plugin namespace must revalidate its actual schema before applying reviewed settings',async()=>{const f=fixture();const profile={v:1,kind:'profile',plugins:[{name:'p',source:'npm',version:'1.0.0',spec:'p@1.0.0'}],settings:{newPlugin:{opaque:'imported-value'}}};await f.controller.preview(profile);const planned=f.controller.plan.changes.find(v=>v.id==='settings:newPlugin');assert.equal(planned.revision,undefined);assert.equal(planned.defaultOn,true);f.state.namespaces.push({ns:'newPlugin',revision:0,writable:true,value:{},schema:{type:'object',dict:{opaque:{type:'string',meta:{role:'secret'}}}}});await f.controller.apply(['settings:newPlugin'],true);assert.equal(f.controller.statuses['settings:newPlugin'].state,'failed');assert.match(f.controller.statuses['settings:newPlugin'].detail,/重新预览/);assert.ok(!f.calls.some(v=>v.method==='settings/mutate'));});

function providerFixture(changeUser = () => {}, includeUser = true) {
 const f=fixture(), models=[{id:'share-owned',name:'Isolated share fixture',contextWindow:8000,maxTokens:1000,input:['text']}];
 const raw={api:'openai-completions',baseURL:'https://example.invalid/v1',models};
 const profile={v:1,kind:'profile',settings:{example:{providers:{'share-owned':raw}}}};
 f.host.request=async(method,args)=>{f.calls.push({method,args});assert.equal(method,'settings/mutate');assert.equal(args.expectedRevision,1);
  const user={providers:{'share-owned':structuredClone(raw)}};changeUser(user.providers['share-owned']);
  // Real dsh-settings describes raw overrides separately from schema-resolved effective values.
  f.state.namespaces[0].value.providers={'share-owned':{...structuredClone(raw),models:models.map(v=>({...v,compat:{}})),headers:{}}};
  if(includeUser)f.state.namespaces[0].user=user;
  f.state.namespaces[0].revision++;return {};
 };
 return {...f,profile,raw};
}
test('settings acknowledgement uses persisted overrides when schema defaults expand objects inside a model array',async()=>{
 const f=providerFixture();await f.controller.preview(f.profile);await f.controller.apply(['settings:example'],true);
 assert.equal(f.controller.statuses['settings:example'].state,'done');
 assert.equal(f.state.namespaces[0].value.providers['share-owned'].models[0].compat.constructor,Object);
 assert.equal(f.calls.filter(v=>v.method==='settings/mutate').length,1);
});
test('persisted JSON object member order is immaterial while array contents, order, length and exact user values remain checked',async()=>{
 const f=providerFixture(p=>{p.models=[{input:['text'],maxTokens:1000,contextWindow:8000,name:'Isolated share fixture',id:'share-owned'}]});
 await f.controller.preview(f.profile);await f.controller.apply(['settings:example'],true);assert.equal(f.controller.statuses['settings:example'].state,'done');
 for(const change of [p=>{p.models=[]},p=>{p.models[0].maxTokens=999},p=>{p.models[0].input=['image','text']},p=>{p.models.push({...p.models[0]})},p=>{p.models[0].unexpected='unreviewed'}]){
  const g=providerFixture(change);await g.controller.preview(g.profile);await g.controller.apply(['settings:example'],true);assert.equal(g.controller.statuses['settings:example'].state,'failed');assert.match(g.controller.statuses['settings:example'].detail,/未确认/);
 }
});
test('effective read-back remains the exact fallback when no user override exists, including older descriptors',async()=>{
 const f=fixture();f.state.namespaces[0].user={};await f.controller.preview(payload);await f.controller.apply(['settings:example'],true);assert.equal(f.controller.statuses['settings:example'].state,'done');
 const g=providerFixture(()=>{},false);await g.controller.preview(g.profile);await g.controller.apply(['settings:example'],true);assert.equal(g.controller.statuses['settings:example'].state,'failed','defaults are not blindly ignored without an exact persisted override');
});
