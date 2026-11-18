import test from'node:test';import assert from'node:assert/strict';import{mkdtemp,rm,readFile,stat}from'node:fs/promises';import{tmpdir}from'node:os';import{join}from'node:path';import{PhoneController,createPhoneHandler}from'../runtime/phone-service.mjs';import{startTransportControl}from'../runtime/transport-control.mjs';
test('phone tool queue binds screens to callers, requires opt-in, handles denial/abort and never queues unsupported operations',async()=>{
 const root=await mkdtemp(join(tmpdir(),'phone-queue-'));const ctrl=new PhoneController(root);
 try{
  await assert.rejects(ctrl.request('screen',{},'a'),/disabled/);ctrl.setEnabled(true);assert.equal((await stat(ctrl.path)).mode&0o777,0o600);assert.equal(new PhoneController(root).enabled,true);
  const screen=ctrl.request('screen',{},'a');ctrl.complete(ctrl.next().request.id,{id:'screen1',nodes:[{id:2,actions:['scrollForward']}]});await screen;
  await assert.rejects(ctrl.request('tap',{screen:'screen1',id:2},'b'),/another/);await assert.rejects(ctrl.request('tap',{screen:'old',id:2},'a'),/expired/);
  const scroll=ctrl.request('scroll',{screen:'screen1',direction:'down'},'a');assert.equal(ctrl.next().request.args.id,2);ctrl.complete(ctrl.next().request.id,null,'Denied');await assert.rejects(scroll,/Denied/);
  await assert.rejects(ctrl.request('apps',{},'a'),/system_basic/);await assert.rejects(ctrl.request('tap_xy',{},'a'),/screenshot/);assert.equal(ctrl.next().request,null);
  const observed=ctrl.request('screen',{},'a',undefined,'a:turn');ctrl.complete(ctrl.next().request.id,{id:'shot',nodes:[],bundle:'app'});await observed;ctrl.observeImage('a','a:turn','shot',{width:540,height:1200,viewportWidth:1080,viewportHeight:2400});
  await assert.rejects(ctrl.request('tap_xy',{observation:'shot',x:10,y:20},'a',undefined,'other:turn'),/screenshot/);
  const gesture=ctrl.request('tap_xy',{observation:'shot',x:10,y:20},'a',undefined,'a:turn');assert.equal(ctrl.next().request.args.x,20);assert.equal(ctrl.next().request.args.y,40);ctrl.complete(ctrl.next().request.id,{},'Denied');await assert.rejects(gesture,/Denied/);await assert.rejects(ctrl.request('tap_xy',{observation:'shot',x:10,y:20},'a',undefined,'a:turn'),/screenshot/);
  const abort=new AbortController(),pending=ctrl.request('screen',{},'a',abort.signal);abort.abort();await assert.rejects(pending,/cancelled/);assert.equal(ctrl.next().request,null);
  const waiting=ctrl.request('screen',{},'a');ctrl.setEnabled(false);await assert.rejects(waiting,/disabled/);assert.equal(new PhoneController(root).enabled,false);assert.doesNotMatch(await readFile(ctrl.path,'utf8'),/screen1|caller/);
 }finally{ctrl.cancelAll('test teardown');await rm(root,{recursive:true,force:true})}
});
test('phone control requires loopback auth and stop disables future execution',async()=>{
 const root=await mkdtemp(join(tmpdir(),'phone-http-'));let server;
 try{server=await startTransportControl({phone:createPhoneHandler(root)});const url=server.endpoint.url+'/phone/';assert.equal((await fetch(url+'pending')).status,403);
 const call=async(action,body)=>{const response=await fetch(url+action,{method:body?'POST':'GET',headers:{authorization:server.endpoint.authorization,'content-type':'application/json'},body:body?JSON.stringify(body):undefined});return{status:response.status,value:await response.json()}};
 assert.equal((await call('pending')).value.enabled,false);assert.equal((await call('enable',{enabled:true})).value.enabled,true);assert.equal((await call('stop',{})).value.enabled,false);assert.equal((await call('complete',{id:'stale',value:{}})).status,400);
 }finally{await server?.close();await rm(root,{recursive:true,force:true})}
});
