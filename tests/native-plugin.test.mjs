import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
let counter = 0;
const moduleUrl = code => 'data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(code) + `\n//# sourceURL=native-plugin-${counter++}.js`);
const wire = moduleUrl(await readFile(new URL('../entry/src/main/ets/dsh/DshWire.ets', import.meta.url), 'utf8'));
const wireImport = source => source.replace(/(?:DshMessage, |, WireObject)/g, '').replace("'../dsh/DshWire'", JSON.stringify(wire));
const controlsUrl = moduleUrl(wireImport(await readFile(new URL('../entry/src/main/ets/ui/NativePluginControlsData.ets', import.meta.url), 'utf8')));
const source = await readFile(new URL('../entry/src/main/ets/ui/NativePluginData.ets', import.meta.url), 'utf8');
const modelUrl=moduleUrl(wireImport(await readFile(new URL('../entry/src/main/ets/ui/NativePluginModel.ets',import.meta.url),'utf8')));
const dataUrl = moduleUrl(wireImport(source).replace("'./NativePluginModel'",JSON.stringify(modelUrl)).replace("'./NativePluginControlsData'", JSON.stringify(controlsUrl)));
const { pluginPlaces, pluginBinding, pluginBindings, parsePluginView, pluginAction, pluginEffects, pluginMerge } = await import(dataUrl);
const { pluginInputPath, pluginInputData, pluginInputIssue } = await import(controlsUrl);
const replies = await readFile(new URL('../entry/src/main/ets/ui/NativePluginReplyData.ets', import.meta.url), 'utf8');
const { modelUiReplyState, modelUiAnswer } = await import(moduleUrl(wireImport(replies).replace(/import \{ PluginNode, PluginView \} from '.\/NativePluginData'\n/, '')));

test('native contributions are ready, supported, uniquely named and bounded by the original surface quotas', () => {
  const plugin = { pkg: '@fixture/cards', title: 'Cards', state: 'ok', native: true, wants: ['draft'], contributes: {
    'composer.actions': [{ id: 'a', label: 'A', effect: { insert: 'hello' } }, { id: 'a', label: 'duplicate' }, { id: 'b', label: 'B', requires: ['voice'] }, { id: 'c', label: 'C' }, { id: 'd', label: 'D' }],
    panels: [{ id: 'main', title: 'Main', placement: ['features'], live: true }, { id: 'hidden', ready: false }]
  } };
  const places = pluginPlaces({ v: 1, plugins: [plugin, { ...plugin, pkg: 'bad/pkg' }, { ...plugin, pkg: 'disabled', native: false }] });
  assert.deepEqual(places.map(p => p.id), ['a', 'c', 'main']);
  assert.deepEqual(places[0].effects, [{ insert: 'hello' }]); assert.equal(places[2].surface, 'panel');
  assert.deepEqual(pluginPlaces({ v: 2, plugins: [plugin] }), []);
});

test('bindings are data-only, not executable and never resolve prototype paths or bound component types', () => {
  const data = { rows: [{ name: 'Alpha' }], malicious: { $: 'data.private' }, private: 'hidden' };
  assert.equal(pluginBinding({ $: 'data.rows[0].name' }, data), 'Alpha');
  assert.equal(pluginBinding({ $: 'data.rows.0.name' }, data), 'Alpha');
  assert.equal(pluginBinding({ $: 'data.rows[-1]' }, data), null);
  assert.equal(pluginBinding({ $: 'data.constructor' }, data), null);
  assert.equal(pluginBinding({ $: 'data.rows.map(x=>x)' }, data), null);
  assert.deepEqual(pluginBindings({ value: { $: 'data.malicious' } }, data), { value: { $: 'data.private' } });
  assert.equal(parsePluginView({ type: { $: 'data.type' } }, { type: 'text' }).root.type, 'invalid');
});

test('tool cards enforce independent byte, depth, children and node budgets and isolate invalid children', () => {
  assert.match(parsePluginView({ type: 'text', text: '😀'.repeat(2200) }, {}, 'toolCard').issue, /大小/);
  let nested = { type: 'text', text: 'deep' }; for (let i = 0; i < 8; i++) nested = { type: 'stack', children: [nested] };
  assert.match(parsePluginView(nested, {}, 'toolCard').issue, /无法/);
  const view = parsePluginView({ type: 'stack', children: [{ type: 'text', text: 'ok' }, { type: 'WebView', html: '<script/>' }] });
  assert.equal(view.root.children[0].type, 'text'); assert.equal(view.root.children[1].type, 'invalid');
  assert.equal(parsePluginView({ type: 'stack', children: Array.from({ length: 40 }, () => ({ type: 'text', text: 'x' })) }, {}, 'toolCard').root.children.length, 16);
  assert.equal(pluginAction({ id: 'send', args: { text: 'a'.repeat(1025) } }), undefined);
});

test('effects retain the exact whitelist and user gesture window; data merges drop prototype keys', () => {
  const now = 10000;
  const effects = [{ insert: 'hi' }, { command: { name: 'compact', args: 'now' } }, { open: 'panel:tools' }, { link: 'https://example.com/page' }, { link: 'https://user:password@example.com' }, { type: 'eval', code: 'run()' }, { patch: { score: 3 } }];
  assert.deepEqual(pluginEffects(effects, now - 3001, now).map(e => e.type), []);
  assert.deepEqual(pluginEffects(effects, now, now).map(e => e.type), ['insert', 'command', 'open', 'link']);
  assert.deepEqual(pluginMerge({ a: { b: 1, c: 2 }, x: 1 }, JSON.parse('{"a":{"b":null,"d":3},"x":null,"__proto__":{"bad":1}}')), { a: { c: 2, d: 3 } });
  assert.equal({}.bad, undefined);
});


test('model reply state derives from ordered transcript and pending sends without mutating history', () => {
  const assistant={id:'a',role:'assistant',text:'Card'};
  assert.deepEqual(modelUiReplyState([assistant],'a',false),{state:'live',text:''});
  assert.equal(modelUiReplyState([assistant],'a',true).state,'running');
  assert.equal(modelUiReplyState([assistant],'missing',false).state,'expired');
  assert.equal(modelUiReplyState([assistant,{id:'b',role:'assistant',text:'Later'}],'a',false).state,'expired');
  assert.equal(modelUiReplyState([assistant,{id:'u',role:'user',text:'Ordinary'}],'a',false).state,'expired');
  assert.equal(modelUiReplyState([assistant],'a',true,['[dsh-ui reply] Plan\nSelect: A']).state,'answered');
  assert.equal(modelUiReplyState([assistant,{id:'u',role:'user',text:'[dsh-ui reply] Plan\nSelect: B'}],'a',false).state,'answered');
});
test('model history matches visible labels and title, confirms only the target card', () => {
  const view=parsePluginView({type:'stack',title:'Plan',children:[{type:'options',options:['A、B','C'],multi:true,freetext:true},{type:'confirm'}]},undefined,'model');
  assert.deepEqual(modelUiAnswer(view,'[dsh-ui reply] Plan\nSelect: A、B、C\nOther: typed'),{key:'root.0',selected:['A、B','C'],free:'typed'});
  assert.equal(modelUiAnswer(view,'[dsh-ui reply] Another\n选择：C'),undefined);
  assert.equal(modelUiAnswer(view,'[dsh-ui reply] Plan\n选择：unknown'),undefined);
  assert.equal(modelUiAnswer(view,'[dsh-ui reply] Plan\nCancel').confirmed,false);
  assert.equal(modelUiAnswer(view,'[dsh-ui reply] Plan\nOther: only typed').free,'only typed');
});
test('actual model send awaits acknowledgement, blocks duplicate taps, and retries false/throws', async () => {
  const component=await readFile(new URL('../entry/src/main/ets/ui/NativePluginView.ets',import.meta.url),'utf8');
  const start=component.indexOf('  private async sendReply('),end=component.indexOf('  private answer()',start);
  const {Harness}=await import(moduleUrl('export class Harness { replyState="live"; replyBusy=false;replySent="";replyError="";onReply;'+component.slice(start,end)+' send(text){return this.sendReply(text)} }'));
  const view=new Harness();let resolve;let calls=0;view.onReply=()=>{calls++;return new Promise(r=>{resolve=r})};
  const pending=view.send('choice');assert.equal(view.replyBusy,true);assert.equal(await view.send('again'),false);assert.equal(calls,1);
  resolve(false);assert.equal(await pending,false);assert.equal(view.replyBusy,false);assert.equal(view.replySent,'');assert.ok(view.replyError);
  view.onReply=async()=>{throw Error('network')};assert.equal(await view.send('retry'),false);
  view.onReply=async()=>true;assert.equal(await view.send('accepted'),true);assert.equal(view.replySent,'accepted');assert.equal(await view.send('duplicate'),false);
  const old=new Harness();old.replyState='answered';old.onReply=async()=>{throw Error('must not run')};assert.equal(await old.send('history'),false);
});
test('v2 input bindings reject prototype paths, overlap, passwords and invalid ranges', () => {
  const input={type:'textField',label:'Name',bind:'data.name',value:{$:'data.name'}};
  assert.equal(parsePluginView({v:2,type:'form',children:[input]}, {name:'Sam'}).root.children[0].raw.value,'Sam');
  assert.equal(parsePluginView({type:'form',children:[input]},{}).root.type,'invalid');
  assert.equal(parsePluginView({v:2,type:'form',children:[input,{...input,bind:'data.name.sub'}]},{}).root.children[1].type,'invalid');
  assert.equal(parsePluginView({v:2,type:'textField',label:'Password',bind:'data.password',password:true},{}).root.type,'invalid');
  assert.equal(pluginInputPath('data.__proto__.x'),undefined);assert.equal(pluginInputPath('data.list[0]'),undefined);
  const original={profile:{name:'A'}};assert.deepEqual(pluginInputData(original,'data.profile.name','B'),{profile:{name:'B'}});assert.equal(original.profile.name,'A');
  assert.ok(pluginInputIssue({type:'slider',min:0,max:10,range:true},[8,3]));
  assert.ok(pluginInputIssue({type:'date'},'2026-02-30'));assert.equal(pluginInputIssue({type:'date'},'2026-02-28'),'');
});


test('v2 draft submission serializes exact visible bindings and preserves newer edits across replies', async () => {
  const draftSource=await readFile(new URL('../entry/src/main/ets/ui/NativePluginDrafts.ets',import.meta.url),'utf8');
  const {NativePluginDrafts}=await import(moduleUrl(wireImport(draftSource).replace(', PluginNode','').replace("'./NativePluginData'",JSON.stringify(dataUrl)).replace("'./NativePluginControlsData'",JSON.stringify(controlsUrl))));
  const view={v:2,type:'form',submit:{id:'save',args:{extra:'fixed'}},children:[{type:'textField',label:'Name',bind:'data.name',onChange:{id:'change'}}]};
  const controller=new NativePluginDrafts();controller.syncRemote({name:'Before'});controller.syncInputs(parsePluginView(view,controller.data()).root);
  const calls=[];let resolve;controller.handler=async action=>{calls.push(action);return new Promise(r=>{resolve=r})};
  controller.edit('data.name','First');const form=parsePluginView(view,controller.data()).root;const pending=controller.submit(form);
  assert.deepEqual(calls[0].args,{extra:'fixed',values:{'data.name':'First'}});assert.equal(typeof calls[0].gestureAt,'number');
  controller.edit('data.name','Later');controller.syncRemote({name:'SERVER FIRST'});resolve(true);assert.equal(await pending,true);assert.equal(controller.data().name,'Later');
  controller.dispose();await new Promise(r=>setTimeout(r,300));assert.equal(calls.length,1,'disposed controls never send queued changes');
  const clean=new NativePluginDrafts();clean.syncRemote({name:'Before'});clean.syncInputs(parsePluginView(view,clean.data()).root);clean.handler=async()=>true;clean.edit('data.name','Accepted');await clean.submit(parsePluginView(view,clean.data()).root);
  assert.equal(clean.data().name,'Accepted');clean.syncRemote({name:'Canonical'});assert.equal(clean.data().name,'Canonical');clean.dispose();
});
test('v2 change callback has no gesture and carries bind + typed value without submitting other invalid fields', async()=>{
  const draftSource=await readFile(new URL('../entry/src/main/ets/ui/NativePluginDrafts.ets',import.meta.url),'utf8');
  const {NativePluginDrafts}=await import(moduleUrl(wireImport(draftSource).replace(', PluginNode','').replace("'./NativePluginData'",JSON.stringify(dataUrl)).replace("'./NativePluginControlsData'",JSON.stringify(controlsUrl))));
  const c=new NativePluginDrafts(),calls=[];c.handler=async action=>{calls.push(action);return true};c.syncRemote({n:1,required:''});
  c.syncInputs(parsePluginView({v:2,type:'stack',children:[{type:'number',label:'N',bind:'data.n',onChange:{id:'changed'}},{type:'textField',label:'Required',bind:'data.required',required:true}]},c.data()).root);
  c.edit('data.n','42');await new Promise(r=>setTimeout(r,300));assert.equal(calls.length,1);assert.deepEqual(calls[0].args,{bind:'data.n',value:42});assert.equal(calls[0].gesture,false);c.dispose();
});


test('model JSON repair keeps URL/string syntax intact, normalizes numeric fields, and genui is read-only data',()=>{
  const repaired=parsePluginView('{/*note*/"type":"stack","children":[{"type":"text","text":"https://x/*literal*/"}, {"type":"progress","value":"50",},],}',undefined,'model');
  assert.equal(repaired.root.children[0].raw.text,'https://x/*literal*/');assert.equal(repaired.root.children[1].raw.value,50);
  const genui=parsePluginView({title:'Report',items:[{type:'stat',label:'Count',value:42},{type:'button',label:'Run',action:'rm -rf'}]},undefined,'model');
  assert.equal(genui.dialect,'genui');assert.equal(genui.root.children[0].type,'metric');assert.equal(genui.root.children[1].type,'tag');assert.equal(genui.root.children[1].raw.action,undefined);
  assert.equal(parsePluginView('{"type":"text",//comment\n"text":"A"}',undefined,'panel').root.type,'invalid','plugin JSON is strict');
});
