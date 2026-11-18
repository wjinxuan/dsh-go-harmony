import './require-runtime-node.mjs';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { randomUUID } from 'node:crypto';
const runtime=resolve(process.argv[2]), root=fileURLToPath(new URL('../',import.meta.url));
const home=await mkdtemp('/tmp/dsh-subscription-live-');let child, diagnostics='';let address,cookie;
async function until(check){for(let i=0;i<300;i++){const value=await check();if(value)return value;if(child.exitCode!==null)throw Error(diagnostics);await delay(30)}throw Error('Timed out '+diagnostics)}
async function start(){child=spawn(process.execPath,['--jitless','--no-addons','--expose-internals','--require',join(root,'tests/local-flock-fixture.cjs'),'--import',join(root,'tests/subscription-oauth-fixture.mjs'),join(runtime,'main.cjs'),home],{stdio:['ignore','ignore','pipe']});child.stderr.on('data',d=>diagnostics+=d);const ready=await until(()=>readFile(join(home,'ready.json'),'utf8').then(JSON.parse,()=>undefined));address=new URL(ready.url);const login=await fetch(address,{redirect:'manual'});cookie=login.headers.getSetCookie().find(s=>s.startsWith('dsh-auth-')).split(';')[0]}
async function stop(){await writeFile(join(home,'stop'),'');await once(child,'exit');await rm(join(home,'ready.json'),{force:true})}
async function rpc(method,args={}){const rpcId=randomUUID();const res=await fetch(address.origin+'/api/'+method,{method:'POST',headers:{cookie,'content-type':'application/json'},body:JSON.stringify({type:'client-request',rpcId,method,payload:{args}})});assert.equal(res.status,200);const value=await res.json();assert.equal(value.rpcId,rpcId);assert.equal(value.result.ok,true,JSON.stringify(value.result.error));return value.result.value}
try{
 await start();assert.equal((await rpc('appAuth/list')).providers.every(p=>!p.signedIn),true);
 for(const provider of ['openai-codex','anthropic']){
  let {attemptId}=await rpc('appAuth/begin',{provider});await until(async()=>['open','prompt'].includes((await rpc('appAuth/poll',{attemptId})).phase));
  await rpc('appAuth/cancel',{attemptId});assert.equal((await rpc('appAuth/poll',{attemptId})).phase,'cancelled');
  ({attemptId}=await rpc('appAuth/begin',{provider}));await until(async()=>['open','prompt'].includes((await rpc('appAuth/poll',{attemptId})).phase));await rpc('appAuth/answer',{attemptId,value:'bad'});
  assert.equal((await until(async()=>{const step=await rpc('appAuth/poll',{attemptId});return step.phase==='failed'?step:undefined})).phase,'failed');
  ({attemptId}=await rpc('appAuth/begin',{provider}));await until(async()=>['open','prompt'].includes((await rpc('appAuth/poll',{attemptId})).phase));await rpc('appAuth/answer',{attemptId,value:'synthetic-code'});
  await until(async()=>(await rpc('appAuth/poll',{attemptId})).phase==='done');assert.equal((await rpc('appAuth/list')).providers.find(p=>p.id===provider).signedIn,true);
 }
 await stop();await start();const statuses=await rpc('appAuth/list');assert.equal(statuses.providers.filter(p=>p.signedIn).length,2);
 for(const provider of ['openai-codex','anthropic'])await rpc('appAuth/signOut',{provider});assert.equal((await rpc('appAuth/list')).providers.some(p=>p.signedIn),false);
 await stop();await start();assert.equal((await rpc('appAuth/list')).providers.some(p=>p.signedIn),false);
 console.log('PASS: packaged appAuth RPC both providers cancel/denial/answer/commit/list/restart/signOut/restart. External OAuth runner is synthetic; no real provider login.');
}finally{if(child?.exitCode===null)await stop();await rm(home,{recursive:true,force:true})}
