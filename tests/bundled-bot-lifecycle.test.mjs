import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import test from 'node:test';
const source=readFileSync(new URL('../entry/src/main/ets/pages/Index.ets',import.meta.url),'utf8');
const settle=()=>new Promise(resolve=>setImmediate(resolve));
function deferred(){let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return{promise,resolve,reject}}
function fixture(text,indent){
 const names=['connect','disconnect','aboutToDisappear','loadBundledBot','changeBundledBot','openTransportControl'];
 const methods=names.map(name=>{const match=text.match(new RegExp('^ {'+indent+'}(?:private )?(?:async )?'+name+'\\([^]*?^ {'+indent+'}\\}', 'm'));assert.ok(match,name+' actual method');return match[0]}).join('\n');
 const noop=()=>{}, reads=[],writes=[],starts=[],read=deferred(),write=deferred(),credential=deferred();
 let page,delayRead=false,delayWrite=false,delayCredential=false;
 const control={url:'http://127.0.0.1:43001',authorization:'Bearer synthetic'},endpoint={url:'http://127.0.0.1:43002/?token=synthetic',workspaceDir:'/owned/workspace',transportControl:control};
 const dependencies={readBundledBot:async c=>{reads.push({control:c,busy:page.busy,version:page.connectionVersion});if(delayRead)return read.promise;return{enabled:false,restartRequired:false}},setBundledBot:async(c,enabled)=>{writes.push({control:c,enabled,busy:page.busy});if(delayWrite)await write.promise},loadLocalApiKey:async()=>undefined,normalizeProviderKey:x=>x,saveLocalApiKey:async()=>{if(delayCredential)await credential.promise},removeLocalApiKey:async()=>{},object:x=>x??{},loadWorkspaceView:async()=>({selected:''}),ChatNotifications:class{async start(){}stop(){}},PetActivityFeed:class{async start(){}close(){}},companionBindingIds:async()=>[],rememberStartupHost:async()=>{}};
 const Page=Function(...Object.keys(dependencies),'return '+stripTypeScriptTypes('(class Page{'+methods+'})'))(...Object.values(dependencies));
 page=Object.assign(new Page(),{mode:'local',modelKey:'',rememberKey:false,hasSavedKey:false,localConfigured:false,address:'https://fixture.invalid/?token=synthetic',authorization:'',connectionVersion:1,chatVersion:1,busy:false,maintenanceBusy:false,connected:false,engineReady:false,bundledBotAvailable:false,bundledBotEnabled:false,bundledBotRestart:false,t:x=>x,getUIContext:()=>({getHostContext:()=>({})}),localEngine:{async start(){starts.push(page.busy);return endpoint},async stop(){}},client:{async connect(){},async setLocalModelKey(){},onHostEvent:noop,async watchWorkspaces(){},async listPluginBundles(){return[]},close:noop},hostScope:()=> 'owned-local',finishOnboarding:async()=>{},refreshSessions:async()=>{},startDSBot:async()=>{},refreshQuickPlugins:async()=>{},errorMessage:e=>e.message,retireRegeneration:noop,releaseTransport:noop,clearAttachments:noop,restoreKeyboardAvoidance:noop,mentions:{reset:noop},questionDrafts:new Map(),composerDrafts:new Map(),cotTranslations:new Map(),recoveryRequestIds:new Map(),visualReplyRequests:new Map()});
 return{page,control,endpoint,reads,writes,starts,read,write,credential,delayCredential(){delayCredential=true},delayRead(){delayRead=true},delayWrite(){delayWrite=true},async connect(){const value=await page.connect(undefined,undefined,false,true);await settle();return value}};
}
function cases(label,text,indent){
 test(label+': actual local connect loads bundled status while busy using its already started engine endpoint',async()=>{
  const f=fixture(text,indent);assert.equal(await f.connect(),true);assert.equal(f.page.bundledBotAvailable,true,'phone1067: enabled=false must still expose the built-in enable row');assert.equal(f.reads.length,1);assert.equal(f.reads[0].busy,true,'state request occurs before connect finally clears busy');assert.equal(f.reads[0].control,f.control);assert.equal(f.starts.length,1,'read must not restart or reenter the engine');assert.equal(f.page.busy,false);
 });
 test(label+': enable and subsequent read reuse the current control without taking global busy ownership',async()=>{
  const f=fixture(text,indent);await f.connect();f.reads.length=0;f.starts.length=0;f.page.busy=true;
  await f.page.changeBundledBot(true);assert.equal(f.writes.length,1);assert.equal(f.writes[0].control,f.control);assert.equal(f.reads[0].control,f.control);assert.equal(f.starts.length,0);assert.equal(f.page.busy,true);
 });
 test(label+': missing local control is unavailable and cannot silently start a second engine',async()=>{
  const f=fixture(text,indent);f.endpoint.transportControl=undefined;await f.connect();assert.equal(f.page.bundledBotAvailable,false);assert.equal(f.reads.length,0);const count=f.starts.length;await assert.rejects(f.page.changeBundledBot(true));assert.equal(f.starts.length,count);assert.equal(f.writes.length,0);
 });
 test(label+': remote connection never reads or writes a cached local control',async()=>{
  const f=fixture(text,indent);f.page.mode='remote';f.page.bundledBotControl=f.control;f.page.bundledBotAvailable=true;assert.equal(await f.connect(),true);assert.equal(f.reads.length,0);assert.equal(f.starts.length,0);assert.equal(f.page.bundledBotAvailable,false);await assert.rejects(f.page.changeBundledBot(true));assert.equal(f.writes.length,0);
 });
 test(label+': delayed status from a retired connection cannot replace the new hosts state',async()=>{
  const f=fixture(text,indent);f.delayRead();await f.connect();assert.equal(f.reads.length,1);f.page.connectionVersion++;f.page.mode='remote';f.page.bundledBotAvailable=false;f.page.bundledBotEnabled=false;f.read.resolve({enabled:true,restartRequired:true});await settle();assert.equal(f.page.bundledBotAvailable,false);assert.equal(f.page.bundledBotEnabled,false);
 });
 test(label+': delayed enable acknowledgement cannot clear or reload a replacement connection',async()=>{
  const f=fixture(text,indent);await f.connect();f.reads.length=0;f.delayWrite();const pending=f.page.changeBundledBot(true);await settle();assert.equal(f.writes.length,1);f.page.connectionVersion++;f.page.bundledBotControl={url:'http://127.0.0.1:43003',authorization:'Bearer new-fixture'};f.page.bundledBotAvailable=true;f.page.bundledBotEnabled=true;f.write.resolve();await pending;assert.equal(f.reads.length,0);assert.equal(f.page.bundledBotAvailable,true);assert.equal(f.page.bundledBotEnabled,true);
 });
 test(label+': retired connect does not refresh a replacement host after delayed DSBot initialization',async()=>{
  const f=fixture(text,indent),started=deferred();f.page.startDSBot=()=>started.promise;const connecting=f.page.connect(undefined,undefined,false,true);await settle();f.page.connectionVersion++;const replacement={url:'http://127.0.0.1:43004',authorization:'Bearer replacement'};f.page.bundledBotControl=replacement;f.page.bundledBotAvailable=true;started.resolve();assert.equal(await connecting,false);await settle();assert.equal(f.reads.length,0);assert.equal(f.page.bundledBotControl,replacement);assert.equal(f.page.bundledBotAvailable,true);
 });
 test(label+': rejected credential persistence from retired connect cannot restore or overwrite a control',async()=>{
  for(const replacement of [undefined,{url:'http://127.0.0.1:43005',authorization:'Bearer replacement'}]){const f=fixture(text,indent);f.delayCredential();const connecting=f.page.connect('synthetic-key',true,false,false);await settle();f.page.aboutToDisappear();f.page.bundledBotControl=replacement;f.credential.reject(Error('Synthetic credential persistence failure'));assert.equal(await connecting,false);assert.equal(f.page.bundledBotControl,replacement);assert.equal(f.reads.length,0)}
 });
 test(label+': disconnect and page disposal retire cached control before stale UI actions',async()=>{
  for(const dispose of [false,true]){const f=fixture(text,indent);await f.connect();if(dispose)f.page.aboutToDisappear();else await f.page.disconnect(false);assert.equal(f.page.bundledBotControl,undefined);assert.equal(f.page.bundledBotAvailable,false);await assert.rejects(f.page.changeBundledBot(true));assert.equal(f.writes.length,0)}
 });
}
cases('source',source,2);
if(process.argv[2])cases('actual CompileArkTS output',readFileSync(process.argv[2],'utf8'),4);
