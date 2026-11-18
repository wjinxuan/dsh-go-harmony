import test from'node:test';import assert from'node:assert/strict';import{attachPhoneScreenImage}from'./PhoneScreenImage.ts';import{state}from'./phone-platform-fixture.mjs';
test('screen image adapter checks native context, emits bounded PNG geometry, and releases images on success/change/cancel',async()=>{
 state.events=[];state.permission=0;const before={id:'before',bundle:'fixture.app',nodes:[],truncated:false};
 const result=await attachPhoneScreenImage({},before,()=>true);assert.equal(result.observation,'after');assert.equal(result.image.mediaType,'image/png');assert.equal(result.image.height,1280);assert.equal(result.image.viewportHeight,2400);assert.ok(state.events.includes('result:release'));
 state.events=[];state.tree={...state.tree,bundle:'other.app'};await assert.rejects(attachPhoneScreenImage({},before,()=>true),/变化/);assert.ok(state.events.includes('result:release'));
 state.events=[];let checks=0;state.tree={...state.tree,bundle:'fixture.app'};await assert.rejects(attachPhoneScreenImage({},before,()=>++checks<3),/取消/);assert.ok(state.events.includes('result:release'));
});
