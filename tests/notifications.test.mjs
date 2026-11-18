globalThis.AppStorage = { get: () => 'zh' };
import assert from 'node:assert/strict';import test from 'node:test';import {readFileSync} from 'node:fs';
import {ChatNotifications} from './ui/ChatNotifications.ts';import {notificationPreferences} from './ui/NotificationData.ts';import {notices,agents,allow} from './notification-fixture.mjs';
const turn=()=>new Promise(r=>setImmediate(r));
function make(){let listener,identity=1,visible='',foreground=false;const requests=[],banners=[];const client={connectionIdentity:()=>identity,onHostEvent:fn=>{listener=fn;return ()=>listener=undefined},request:async(method,args)=>{requests.push({method,args});return {records:[{type:'event',event:{seq:9,type:'turn/end',data:{reason:{kind:'completed'}}}}]}}};return {monitor:new ChatNotifications(client,{},'local',()=>visible,()=>foreground,a=>banners.push(a)),emit:async e=>{listener?.(e);await turn();await turn()},show:s=>visible=s,front:b=>foreground=b,switch:()=>identity++,banners,requests}}
const approval=(id='one')=>({type:'waterfall',event:'approval/request',eventId:id,request:{sessionId:'s',reason:'private command'}});
test('native notification request opens the EntryAbility dsh-prefixed chat route, without private conversation text',async()=>{
 notices.length=0;agents.length=0;const h=make();await h.monitor.start();await h.emit(approval());assert.equal(notices.length,1);assert.deepEqual(agents[0].wants[0].parameters,{'dsh.kind':'chat','dsh.sessionId':'s','dsh.host':'local'});assert.ok(!JSON.stringify(notices).includes('private command'));
 const ability=readFileSync(process.argv[2]+'/entry/src/main/ets/entryability/EntryAbility.ets','utf8');for(const key of Object.keys(agents[0].wants[0].parameters))assert.ok(ability.includes(key),key);h.monitor.stop();
});
test('foreground current conversation is silent; other conversation uses banner; duplicate host events do not repeat',async()=>{
 const h=make();h.front(true);h.show('s');await h.monitor.start();await h.emit(approval('a'));assert.equal(h.banners.length,0);h.show('other');await h.emit(approval('b'));await h.emit(approval('b'));assert.equal(h.banners.length,1);h.monitor.stop();
});
test('idle falling edge reads real session/page contract, permission and preference filters suppress publishes, host switch blocks stale events',async()=>{
 notices.length=0;const h=make();await h.monitor.start();await h.emit({type:'emit',event:'api-session/status',args:['s',false]});assert.equal(h.requests.length,0);await h.emit({type:'emit',event:'api-session/status',args:['s',true]});await h.emit({type:'emit',event:'api-session/status',args:['s',false]});assert.deepEqual(h.requests[0],{method:'session/page',args:{request:{address:{kind:'session',sessionId:'s'},maxMessages:1}}});assert.equal(notices.length,1);
 h.monitor.updatePreferences(notificationPreferences({enabled:false}));await h.emit(approval('off'));assert.equal(notices.length,1);h.monitor.updatePreferences(notificationPreferences());allow(false);await h.emit(approval('permission'));assert.equal(notices.length,1);allow(true);h.switch();await h.emit(approval('old'));assert.equal(notices.length,1);h.monitor.stop();
});

test('DS Bot notifications open the bounded bot/group route and respect catch-up, owned-session and foreground suppression',async()=>{
 notices.length=0;agents.length=0;const h=make();await h.monitor.start();h.monitor.setBotSessions(['s']);await h.emit(approval('owned'));assert.equal(notices.length,0);
 await h.monitor.bot({seq:1,kind:'message',botId:'bot'},true);assert.equal(notices.length,0);await h.monitor.bot({seq:2,kind:'approval',botId:'bot',roomId:'group',text:'secret command'},false);assert.equal(notices.length,1);assert.deepEqual(agents[0].wants[0].parameters,{'dsh.kind':'dsbot-room','dsh.sessionId':'group','dsh.host':'local'});assert.equal(JSON.stringify(notices).includes('secret command'),false);
 await h.monitor.bot({seq:2,kind:'approval',botId:'bot',roomId:'group'},false);assert.equal(notices.length,1);h.front(true);h.show('bot');await h.monitor.bot({seq:3,kind:'question',botId:'bot'},false);assert.equal(h.banners.length,0);h.show('other');await h.monitor.bot({seq:4,kind:'message',botId:'bot'},false);assert.equal(h.banners[0].destination,'ds-bot');assert.equal(h.banners[0].botId,'bot');assert.equal(h.banners[0].botRoom,false);h.monitor.stop();
});
