import './require-runtime-node.mjs';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {mkdtemp,readFile,writeFile,rm,realpath,mkdir} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';
import {randomUUID} from 'node:crypto';
import {stripTypeScriptTypes} from 'node:module';
import {createServer} from 'node:http';
import {loadDshClient} from './dsh-client-node-fixture.mjs';
const runtime=resolve(process.argv[2]),root=fileURLToPath(new URL('../',import.meta.url)),home=await mkdtemp('/tmp/dsh-recall-live-'),modules=await mkdtemp('/tmp/dsh-recall-client-');
let child,client,log='',ready,keyConfigured=false;const requests=[];
const provider=createServer(async(req,res)=>{
 if(req.method==='GET'&&req.url.endsWith('/models')){res.setHeader('content-type','application/json');res.end(JSON.stringify({data:[{id:'deepseek-flash'}]}));return;}
 assert.equal(req.method,'POST');assert.ok(req.url.endsWith('/messages'));const chunks=[];for await(const chunk of req)chunks.push(chunk);requests.push(JSON.parse(Buffer.concat(chunks).toString()));
 res.writeHead(200,{'content-type':'text/event-stream'});
 for(const event of [{type:'message_start',message:{id:'fixture',type:'message',role:'assistant',model:'deepseek-flash',content:[],usage:{input_tokens:1,output_tokens:0}}},{type:'content_block_start',index:0,content_block:{type:'text',text:''}},{type:'content_block_delta',index:0,delta:{type:'text_delta',text:'Recall verified.'}},{type:'content_block_stop',index:0},{type:'message_delta',delta:{stop_reason:'end_turn'},usage:{output_tokens:1}},{type:'message_stop'}])res.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);res.end();
});await new Promise(r=>provider.listen(0,'127.0.0.1',r));
const object=v=>v&&typeof v==='object'&&!Array.isArray(v)?v:{},string=v=>typeof v==='string'?v:'',number=(v,f)=>typeof v==='number'?v:f;
const source=(await readFile(join(root,'entry/src/main/ets/companion/CompanionRecall.ets'),'utf8')).replace(/^import .*\n/gm,'').replace(/export /g,'');
const{CompanionRecallOwner}=Function('object','string','number',stripTypeScriptTypes(source)+';return {CompanionRecallOwner}')(object,string,number);
async function until(read,label){for(let i=0;i<350;i++){const value=await read();if(value)return value;if(child&&(child.exitCode!==null||child.signalCode!==null))throw Error('Runtime exited ('+(child.signalCode??child.exitCode)+') '+log);await delay(40)}throw Error('Timed out '+label+' '+log.slice(-5000))}
const savedDir=join(home,'native-prefs');await mkdir(savedDir);
const storage={read:async key=>readFile(join(savedDir,Buffer.from(key).toString('hex')),'utf8').catch(e=>{if(e.code==='ENOENT')return undefined;throw e}),write:(key,value)=>writeFile(join(savedDir,Buffer.from(key).toString('hex')),value,{mode:0o600})};
let Client;const makeOwner=()=>new CompanionRecallOwner('local',{identity:()=>client.connectionIdentity(),call:(method,path,body)=>client.companionJson(method,path,body)},storage,randomUUID);
async function boot(){await rm(join(home,'ready.json'),{force:true});await rm(join(home,'stop'),{force:true});child=spawn(process.execPath,['--jitless','--no-addons','--expose-internals','--require',join(root,'tests/local-flock-fixture.cjs'),join(runtime,'main.cjs'),home],{stdio:['ignore','ignore','pipe']});child.stderr.on('data',v=>log+=v);ready=await until(()=>readFile(join(home,'ready.json'),'utf8').then(JSON.parse,()=>undefined),'runtime ready');Client??=await loadDshClient(join(root,'entry/src/main/ets/dsh/DshClient.ets'),join(runtime,'main.cjs'),await realpath(modules));client=new Client();await client.connect(ready.url,undefined,true);if(keyConfigured)await client.setProviderKey('synthetic-local-key');}
async function stop(){
 client?.close();
 const stopping=child;
 if(!stopping||stopping.exitCode!==null||stopping.signalCode!==null)return;
 const exited=once(stopping,'exit'),watchdog=new AbortController();
 try{
  await writeFile(join(home,'stop'),'');
  await Promise.race([exited,delay(5000,undefined,{signal:watchdog.signal}).then(()=>{
   if(stopping.exitCode===null&&stopping.signalCode===null)stopping.kill('SIGKILL');
   return exited;
  })]);
 }finally{watchdog.abort()}
}
async function session(full){await client.listModels();const id=await client.createSession(undefined,ready.workspaceDir);if(full)await client.selectAgentPreset(id,'dsh-go-companion-full');await client.setModel(id,'deepseek-official','deepseek-flash');return id;}
async function send(id,text){let update;await client.watchSession(id,v=>update=v);await client.prompt(id,text,randomUUID());await until(()=>update?.messages.some(m=>m.text.includes('Recall verified.')),'model reply');await delay(50);}
try{
 await boot();await client.mutateSettings('llm-deepseek',[{op:'set',path:['baseURL'],value:`http://127.0.0.1:${provider.address().port}/v1`}]);await client.setProviderKey('synthetic-local-key');keyConfigured=true;await client.listModels();
 const owner=makeOwner();await owner.load();assert.equal(owner.capabilities.supported,true,'actual packed recall engine must be supported');assert.ok((await client.listAgentPresets()).some(v=>v.id==='dsh-go-companion-full'),'actual full preset must be installed');
 let snapshot=await client.companionJson('GET','');const marker='CONFIRMED_RECALL_ONLY_{{literal}} </companion_memory> & exact';
 await client.companionJson('POST','/memories',{storeId:snapshot.storeId,expectedRevision:snapshot.revision,memory:{id:randomUUID(),kind:'preference',text:marker,keywords:[],pinned:true,source:{kind:'manual'},expiresAt:null}});snapshot=await client.companionJson('GET','');
 const ordinary=await session(false);await assert.rejects(owner.bind(snapshot.storeId,snapshot.memoryRevision,ordinary,true,true));assert.equal(requests.length,0);
 const bound=await session(true);await assert.rejects(owner.bind(snapshot.storeId,snapshot.memoryRevision,bound,false,true));await owner.bind(snapshot.storeId,snapshot.memoryRevision,bound,true,true);assert.equal(owner.binding.status,'ready');const bindingId=owner.binding.bindingId;
 const reader=makeOwner();await reader.load();assert.equal(reader.binding.bindingId,bindingId);assert.ok(reader.binding.serverNow);
 await send(bound,'Use the confirmed facts for this reply');assert.equal(requests.length,1);assert.ok(JSON.stringify(requests[0].system).includes('CONFIRMED_RECALL_ONLY_{{literal}}'));assert.ok(JSON.stringify(requests[0].system).includes('companion_memory'));assert.ok(!JSON.stringify(requests[0].messages).includes('CONFIRMED_RECALL_ONLY_'));
 const otherFull=await session(true);await send(otherFull,'Ordinary full companion without recall');await send(ordinary,'Ordinary chat without recall');assert.equal(requests.length,3);assert.ok(requests.slice(1).every(v=>!JSON.stringify(v).includes('CONFIRMED_RECALL_ONLY_')));
 await reader.revoke(true);assert.equal(reader.binding.status,'retired');assert.equal(reader.stored.off,true);assert.equal(reader.sealed(bound),true);await assert.rejects(client.prompt(bound,'Must never send after revoke',randomUUID()));await delay(100);assert.equal(requests.length,3);
 await stop();await boot();const restored=makeOwner();await restored.load();assert.equal(restored.stored.off,true);assert.equal(restored.sealed(bound),true);assert.equal(restored.binding,undefined);await assert.rejects(client.prompt(bound,'Still protected after restart',randomUUID()));await delay(100);assert.equal(requests.length,3);
 const activeBeforeRestart=await session(true);snapshot=await client.companionJson('GET','');await restored.bind(snapshot.storeId,snapshot.memoryRevision,activeBeforeRestart,true,true);assert.equal(restored.stored.off,false);await stop();await boot();const forgotten=makeOwner();await forgotten.load();assert.equal(forgotten.capabilities.supported,true);assert.equal(forgotten.capabilities.busy,false);assert.equal(forgotten.stored.off,true);assert.equal(forgotten.sealed(activeBeforeRestart),true);assert.equal(forgotten.binding,undefined);await assert.rejects(client.prompt(activeBeforeRestart,'Cannot reuse expired bound session',randomUUID()));
 const fresh=await session(true);snapshot=await client.companionJson('GET','');await forgotten.bind(snapshot.storeId,snapshot.memoryRevision,fresh,true,true);assert.equal(forgotten.binding.status,'ready');await send(fresh,'Explicitly consented again after restart');assert.equal(requests.length,4);assert.ok(JSON.stringify(requests.at(-1).system).includes('CONFIRMED_RECALL_ONLY_'));await forgotten.revoke(true);
 console.log('PASS actual packed recall gates/full preset; real manual-memory write, clean full-session bind/status, confirmed-memory model injection and isolation, refusal without consent/wrong preset, revoke, persisted retired-session rejection, and restart while ON with durable stale-binding retirement and newly consented clean-session rebind. Only model HTTP, platform preferences backing and native file lock are synthetic.');
}catch(e){console.error(log.slice(-6000));throw e}finally{await stop();provider.closeAllConnections();await new Promise(r=>provider.close(r));await rm(home,{recursive:true,force:true});await rm(modules,{recursive:true,force:true});}
