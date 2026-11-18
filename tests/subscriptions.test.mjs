import assert from 'node:assert/strict';
import test from 'node:test';
import { SubscriptionLogin, subscriptionBrowserUrl, subscriptionStatuses, subscriptionStep } from './ui/SubscriptionData.ts';
import { parseModelTokens, providerModelDraft, providerModelValue, subscriptionContextOps } from './ui/settings/ProviderModelData.ts';
const deferred = () => { let resolve, reject; const promise = new Promise((a,b) => { resolve=a; reject=b }); return { promise, resolve, reject }; };
const turn = () => new Promise(r => setImmediate(r));
test('subscription URLs, phases and list fail closed without token exposure', () => {
  for (const url of ['http://login.test', 'https://user:pass@login.test', 'https://login.test\\@evil.test', 'https://login.test/\nfoo']) assert.equal(subscriptionBrowserUrl(url), '');
  assert.equal(subscriptionBrowserUrl('https://auth.test/authorize?state=test'), 'https://auth.test/authorize?state=test');
  assert.equal(subscriptionStep({ phase:'open', url:'javascript:alert(1)' }).phase, 'failed');
  assert.equal(subscriptionStep({ phase:'unexpected' }).phase, 'failed');
  assert.deepEqual(subscriptionStatuses({providers:[{id:'openai-codex',signedIn:true,account:'test@example.test',access:'secret'},{id:'openai-codex'},{id:'other'}]}), [{id:'openai-codex',title:'ChatGPT',signedIn:true,account:'test@example.test'}]);
});
test('actual request contract, prompt answer, successful terminal and no cancel after done', async () => {
  const events=[], wait=deferred(); let answered=false;
  const login=new SubscriptionLogin(async(method,args) => {events.push([method,args]); if(method==='appAuth/begin')return {attemptId:'a'}; if(method==='appAuth/answer') answered=true; if(method==='appAuth/poll')return answered?{phase:'done'}:{phase:'prompt',placeholder:'URL'}},'anthropic',()=>true,()=>wait.promise);
  const run=login.start(); await turn(); assert.equal(login.step.phase,'prompt'); assert.equal(await login.answer('  pasted  '),true); wait.resolve(); await run; assert.equal(login.step.phase,'done'); await login.close();
  assert.deepEqual(events.find(([m])=>m==='appAuth/answer'), ['appAuth/answer',{attemptId:'a',value:'pasted'}]); assert.equal(events.some(([m])=>m==='appAuth/cancel'),false);
});
test('closing during begin cancels late attempt only on same host', async () => {
  for(const current of [true,false]) { const start=deferred(),calls=[]; let same=true; const login=new SubscriptionLogin(async(m,a)=>{calls.push([m,a]); if(m==='appAuth/begin')return start.promise},'openai-codex',()=>same); const run=login.start(); same=current; await login.close(); start.resolve({attemptId:'late'}); await run; assert.equal(calls.filter(([m])=>m==='appAuth/cancel').length,current?1:0) }
});
test('three polling failures stop and retry cancels prior live attempt', async () => {
  let begins=0,polls=0;const cancels=[];
  const login=new SubscriptionLogin(async(m,a)=>{if(m==='appAuth/begin')return {attemptId:String(++begins)};if(m==='appAuth/cancel')cancels.push(a.attemptId);if(m==='appAuth/poll'){polls++;if(begins===1)throw Error('offline');return {phase:'done'}}},'anthropic',()=>true,async()=>{});
  await login.start();assert.equal(login.step.phase,'failed');assert.equal(polls,3);await login.start();assert.deepEqual(cancels,['1']);assert.equal(login.step.phase,'done');
});
test('failed answer cannot be overwritten by an older in-flight poll', async () => {
  const waits=[], stale=deferred();let polls=0;
  const login=new SubscriptionLogin(async(m)=>{if(m==='appAuth/begin')return {attemptId:'a'};if(m==='appAuth/poll')return ++polls===1?{phase:'prompt'}:stale.promise;if(m==='appAuth/answer')throw Error('denied')},'anthropic',()=>true,()=>{const wait=deferred();waits.push(wait);return wait.promise});
  const run=login.start();await turn();waits[0].resolve();await turn();assert.equal(await login.answer('code'),false);stale.resolve({phase:'done'});await turn();waits.at(-1).resolve();await run;assert.equal(login.step.phase,'failed');await login.close();
});
test('token parsing matches original decimal K/M; model changes preserve metadata and custom reasoning mapping', () => {
  assert.equal(parseModelTokens('1.5M'),1500000);assert.equal(parseModelTokens('128K'),128000);assert.equal(parseModelTokens('1_024'),1024);for(const text of ['0','1.1','-2','Infinity'])assert.equal(parseModelTokens(text),undefined);
  const before={id:'m',name:'old',contextWindow:32768,input:['text','audio'],compat:{stream:true},reasoningEfforts:{off:null,minimal:'tiny',high:'heavy',none:'invalid'}};
  const draft=providerModelDraft(before);draft.name='New';draft.context='200K';draft.levels.push('max');const next=providerModelValue(before,draft);
  assert.deepEqual(next.compat,before.compat);assert.deepEqual(next.input,before.input);assert.equal(next.contextWindow,200000);assert.deepEqual(next.reasoningEfforts,{off:null,minimal:'tiny',high:'heavy',max:'max'});
  draft.context='0';assert.throws(()=>providerModelValue(before,draft));
});
test('subscription context clearing preserves unrelated overrides and last-entry cleanup', () => {
  const overrides={m:{contextWindow:99,name:'Kept',compat:{x:true}}};
  assert.deepEqual(subscriptionContextOps('anthropic','m',overrides,''),[{op:'set',path:['providers','anthropic','modelOverrides','m'],value:{name:'Kept',compat:{x:true}}}]);
  assert.deepEqual(subscriptionContextOps('openai-codex','m',{m:{contextWindow:99}},''),[{op:'unset',path:['providers','openai-codex','modelOverrides']}]);
  assert.throws(()=>subscriptionContextOps('custom','m',{},'32K'));
});
