import test from 'node:test';import assert from 'node:assert/strict';
import {executePhoneIntent} from './PhoneIntent.ts';import {fixture,context,deviceInfo} from './phone-intent-fixture.mjs';
test('native intents call SDK dial/calendar/share/navigation/draft/settings and preserve real failure/cancellation',async()=>{
 const run=args=>executePhoneIntent(context,args,()=>true);fixture.calls=[];
 assert.equal((await run({kind:'dial',number:'+86 13800138000'})).businessResult,'unknown');assert.deepEqual(fixture.calls.at(-1),['dial','+86 13800138000']);
 assert.equal((await run({kind:'calendar',title:'Fixture meeting',begin:'2026-11-18T15:00',location:'Room'})).eventId,12);assert.equal(fixture.calls.at(-1)[1].endTime-fixture.calls.at(-1)[1].startTime,3600000);
 fixture.eventId=-1;assert.equal((await run({kind:'calendar',title:'Cancelled',begin:'2026-11-18T15:00'})).cancelled,true);
 await run({kind:'share',text:'Fixture share'});assert.equal(fixture.calls.at(-1)[1].content,'Fixture share');await assert.rejects(run({kind:'share',text:'x',app:'android.package'}),/系统分享/);
 await run({kind:'navigate',lat:31,lng:121,mode:'transit'});assert.equal(fixture.calls.at(-1)[1].vehicleType,3);await run({kind:'navigate',destination:'Fixture park'});assert.equal(fixture.calls.at(-1)[1].sceneType,3);
 fixture.navigationError=true;await assert.rejects(run({kind:'navigate',destination:'Fixture park'}),/refused/);fixture.navigationError=false;
 await run({kind:'sms_draft',number:'13800138000',text:'Draft only'});const want=fixture.calls.at(-1)[1];assert.equal(want.bundleName,'com.ohos.mms');assert.equal(want.parameters.content,'Draft only');
 await run({kind:'settings',page:'wifi'});fixture.network=false;await assert.rejects(run({kind:'settings',page:'wifi'}),/未打开/);await run({kind:'settings',page:'app_notifications'});
 await assert.rejects(run({kind:'settings',page:'app_notifications',app:'other.app'}),/等价接口/);
  for(const page of ['mobile_network','display','sound','nfc']){await run({kind:'settings',page});assert.equal(fixture.calls.at(-1)[0],page)}deviceInfo.sdkApiVersion=23;await assert.rejects(run({kind:'settings',page:'nfc'}),/API 24/);await assert.rejects(run({kind:'settings',page:'display'}),/API 26/);
 const count=fixture.calls.length;await assert.rejects(executePhoneIntent(context,{kind:'dial',number:'1'},()=>false),/取消/);assert.equal(fixture.calls.length,count);
 await assert.rejects(run({kind:'dial',number:'123;call'}),/号码/);await assert.rejects(run({kind:'calendar',title:'Bad',begin:'x'}),/无效/);
});
