import test from 'node:test';import assert from 'node:assert/strict';
import { startupSettings,startupTarget,startupHost,startupAutoLocal } from './StartupData.ts';
test('low-memory startup default is only used in the absence of a saved boolean',()=>{
 const gib=1024**3;assert.equal(startupAutoLocal('',4*gib),false);assert.equal(startupAutoLocal('',5*gib),true);assert.equal(startupAutoLocal('',0),true);
 assert.equal(startupAutoLocal(true,2*gib),true);assert.equal(startupAutoLocal(false,16*gib),false);
});
test('startup defaults and explicit opt-outs preserve user choices',()=>{
 assert.deepEqual(startupTarget(startupSettings({}),false,true),{kind:'local',id:''});
 assert.equal(startupTarget(startupSettings({autoStartLocal:false}),false,true),undefined);
 assert.equal(startupTarget(startupSettings({}),true,true),undefined);assert.equal(startupTarget(startupSettings({}),false,false),undefined);
 const remote=startupSettings({lastHost:{kind:'http',id:'stable-id'}});
 assert.deepEqual(startupTarget(remote,false,true),{kind:'http',id:'stable-id'});
 remote.restoreLastHost=false;assert.equal(startupTarget(remote,false,true).kind,'local');remote.autoStartLocal=false;assert.equal(startupTarget(remote,false,true),undefined);
});
test('host persistence keeps stable identifiers, rejects credentials/URLs/controls and unknown host types',()=>{
 for(const id of ['https://secret.test/?token=x','name?token=x','name\nprivate','name@private','a'.repeat(257),''])assert.equal(startupHost('http',id),undefined);
 assert.equal(startupHost('other','id'),undefined);assert.deepEqual(startupHost('ssh','ssh:host-id'),{kind:'ssh',id:'ssh:host-id'});
 assert.deepEqual(startupSettings({lastHost:{kind:'local',id:'https://secret'}}).lastHost,{kind:'local',id:''});
});
