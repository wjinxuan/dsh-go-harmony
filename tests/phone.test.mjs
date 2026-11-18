import test from'node:test';import assert from'node:assert/strict';
import{phoneCaptureSupported,phoneChecks,phonePolicy,updatePhoneRule,phonePolicyRule}from'./PhoneData.ts';
import{capturePhoneScreen}from'./PhoneControl.ts';import{state,deviceInfo}from'./phone-platform-fixture.mjs';
import{phoneRequestValid,phoneWriteAllowed,parsePhoneAction}from'./PhoneAccessibilityData.ts';
import{phoneTaskFirstStart}from'./PhoneTaskData.ts';
import{collectPhoneList}from'./PhoneCollect.ts';
test('collection scrolls the bound list, deduplicates descendants, honors limits/cancel and reports app changes',async()=>{
 const page=(id,items,bundle='app')=>({id,bundle,truncated:false,nodes:[{id:0,parent:-1,type:'Page',bounds:[0,0,100,100],text:'not a list item'},{id:1,parent:0,type:'List',bounds:[0,10,100,80],actions:['scrollForward']},...items.map((text,i)=>({id:i+2,parent:1,type:'Text',text}))]});
 let scrolls=0,reads=0;const a=page('s1',['A','B']),args={initial:a,list:1,max_pages:5};
 const result=await collectPhoneList(args,async command=>{if(command.action==='scrollForward'){scrolls++;assert.equal(command.nodeId,1);return{acknowledged:true}}return reads++===0?a:page('s'+(reads+1),['B','C'])},()=>true);
 assert.deepEqual(result.items,['A','B','C']);assert.equal(result.reason,'no-new-items');assert.equal(scrolls,2);assert.equal(result.complete,true);
 assert.equal((await collectPhoneList({...args,max_pages:1},async command=>{if(command.action!=='screen')throw Error('must not scroll');return a},()=>true)).reason,'page-limit');
 await assert.rejects(collectPhoneList(args,async()=>({}),()=>false),/取消/);
 await assert.rejects(collectPhoneList(args,async c=>c.action==='screen'?page('changed',[],'other'):{},()=>true),/目标应用/);
});
test('phone usage counts a confirmed engine turn once across tools and separately for later turns',()=>{
 const started=[];let calls=0;for(const task of ['session-a:15','session-a:15','session-b:15','session-a:22','session-a:15',''])if(phoneTaskFirstStart(started,task))calls++;
 assert.equal(calls,3);for(let i=0;i<200;i++)phoneTaskFirstStart(started,'session-a:'+i);assert.equal(started.length,128);
});
test('accessibility requests expire, allow only fixed actions, require explicit approval and block protected destinations',()=>{
 const id='12345678-1234-1234-1234-123456789abc',now=Date.now();assert.equal(phoneRequestValid({id,expires:now+1000,command:{action:'screen'}},now).id,id);
 for(const request of [{id,expires:now-1,command:{action:'screen'}},{id,expires:now+90000,command:{action:'screen'}},{id:'../escape',expires:now+1000,command:{action:'screen'}}])assert.throws(()=>phoneRequestValid(request,now));
 assert.throws(()=>parsePhoneAction({action:'shell'}));assert.throws(()=>parsePhoneAction({action:'setText',text:'x'.repeat(8193)}));
 for(const [bundle,deny,password,approved] of [['com.dshgo.harmony',[],false,true],['com.huawei.hmos.settings',[],false,true],['com.bank.app',['com.bank.app'],false,true],['com.example.app',[],true,true],['com.example.app',[],false,false]])assert.throws(()=>phoneWriteAllowed(bundle,deny,password,approved));
 assert.doesNotThrow(()=>phoneWriteAllowed('com.example.app',[],false,true));
});
test('phone capture eligibility follows actual SDK device matrix and never labels unavailable input observed',()=>{
 assert.equal(phoneCaptureSupported('phone',20),false);assert.equal(phoneCaptureSupported('phone',21),true);assert.equal(phoneCaptureSupported('2in1',14),true);assert.equal(phoneCaptureSupported('wearable',26),false);
 for(const item of phoneChecks('phone',21,1080,2400).filter(x=>['input','tree','background'].includes(x.stage))){assert.equal(item.observed,false);assert.equal(item.state,item.stage==='background'?'unsupported':'not_run');}
});
test('deny policies win over per-write confirmation and malformed app identifiers cannot persist',()=>{
 const policy=phonePolicy({denyPackages:['com.example.app','invalid'],confirmEveryWritePackages:['com.example.app'],confirmMode:'unknown'});assert.equal(policy.confirmMode,'ask');assert.equal(phonePolicyRule(policy,'com.example.app'),'deny');assert.deepEqual(policy.denyPackages,['com.example.app']);
 const moved=updatePhoneRule(policy,'com.example.app','confirm');assert.deepEqual(moved.denyPackages,[]);assert.equal(phonePolicyRule(moved,'com.example.app'),'confirm');assert.throws(()=>updatePhoneRule(policy,'evil\napp','deny'));
});
test('capture permission denial and retired requests never access screen',async()=>{
 state.permission=-1;state.captures=0;await assert.rejects(capturePhoneScreen({},true,0,()=>true),/授权/);assert.equal(state.captures,0);
 state.permission=0;assert.equal(await capturePhoneScreen({},true,0,()=>false),undefined);assert.equal(state.captures,0);
 deviceInfo.sdkApiVersion=20;await assert.rejects(capturePhoneScreen({},true,0,()=>true),/API 21/);deviceInfo.sdkApiVersion=21;
});
test('actual capture adapter releases source/conversion buffers, transfers only successful result ownership, and cleans OCR errors/cancel',async()=>{
 state.events=[];state.ocrFails=false;const result=await capturePhoneScreen({},true,0,()=>true);assert.equal(result.text,'真实 fixture 文本');assert.deepEqual(state.events,['packer:release','decoder:release','source:release']);await result.pixels.release();
 state.events=[];state.ocrFails=true;await assert.rejects(capturePhoneScreen({},true,0,()=>true),/OCR/);assert.deepEqual(state.events,['packer:release','decoder:release','source:release','result:release']);
 state.events=[];state.ocrFails=false;let calls=0;assert.equal(await capturePhoneScreen({},true,0,()=>++calls===1),undefined);assert.deepEqual(state.events,['packer:release','decoder:release','source:release','result:release']);
});
