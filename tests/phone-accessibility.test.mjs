import test from'node:test';import assert from'node:assert/strict';import{mkdtemp,readdir,rm,stat,mkdir,writeFile}from'node:fs/promises';import{join}from'node:path';import{tmpdir}from'node:os';
import{fixture}from'./phone-accessibility-fixture.mjs';import Ability from'./PhoneAccessibilityAbility.ts';import{phoneAccessibilityCall}from'./PhoneAccessibilityClient.ts';
test('actual extension/file bridge reads nodes then performs explicit action, rejects replay/changed screen/denied app and removes private requests',async()=>{
 fixture.root=await mkdtemp(join(tmpdir(),'phone-accessibility-'));await mkdir(join(fixture.root,'phone-control'));await writeFile(join(fixture.root,'phone-control/policy.json'),JSON.stringify({denyPackages:[]}));const ability=new Ability();ability.onConnect();
 const command=(action,tree)=>({action,screenId:tree?.id??'',nodeId:0,text:'typed fixture',approved:action!=='screen'});
 try{
  const tree=await phoneAccessibilityCall(ability.context,command('screen'),()=>true);assert.equal(tree.bundle,'com.example.app');assert.equal(tree.nodes[0].text,'Read target');
  const result=await phoneAccessibilityCall(ability.context,command('setText',tree),()=>true);assert.equal(result.acknowledged,true);assert.deepEqual(fixture.calls,[{action:'setText',params:{setText:'typed fixture'}}]);
  await assert.rejects(phoneAccessibilityCall(ability.context,command('click',tree),()=>true),/屏幕/);
  const next=await phoneAccessibilityCall(ability.context,command('screen'),()=>true);fixture.text='Changed target';await assert.rejects(phoneAccessibilityCall(ability.context,command('click',next),()=>true),/节点已变化/);assert.equal(fixture.calls.length,1);
  const keyTree=await phoneAccessibilityCall(ability.context,command('screen'),()=>true);await phoneAccessibilityCall(ability.context,command('home',keyTree),()=>true);assert.equal(fixture.calls[1].action,'home');
  const gestureTree=await phoneAccessibilityCall(ability.context,command('screen'),()=>true);await phoneAccessibilityCall(ability.context,{...command('gestureSwipe',gestureTree),x:10,y:20,x2:100,y2:200,duration:400,width:1080,height:2400},()=>true);assert.equal(fixture.calls[2].gesture.durationTime,400);assert.deepEqual(fixture.calls[2].gesture.points.map(p=>[p.positionX,p.positionY]),[[10,20],[100,200]]);
  await assert.rejects(phoneAccessibilityCall(ability.context,{...command('gestureTap',gestureTree),x:10,y:20,width:1080,height:2400},()=>true),/屏幕/);
  fixture.password=true;const secret=await phoneAccessibilityCall(ability.context,command('screen'),()=>true);assert.equal(secret.nodes[0].text,'••••');await assert.rejects(phoneAccessibilityCall(ability.context,command('setText',secret),()=>true),/密码/);
  await writeFile(join(fixture.root,'phone-control/policy.json'),JSON.stringify({denyPackages:['com.example.app']}));await assert.rejects(phoneAccessibilityCall(ability.context,command('screen'),()=>true),/禁止/);
  await assert.rejects(phoneAccessibilityCall(ability.context,command('screen'),()=>false),/取消/);
  assert.deepEqual((await readdir(join(fixture.root,'phone-control'))).filter(name=>/request|response/.test(name)),[]);assert.equal((await stat(join(fixture.root,'phone-control/ready.json'))).mode&0o777,0o600);
 }finally{ability.onDisconnect();await new Promise(r=>setTimeout(r,250));await rm(fixture.root,{recursive:true,force:true})}
});
