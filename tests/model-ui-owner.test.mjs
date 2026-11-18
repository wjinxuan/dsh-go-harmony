import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
const source = await readFile(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const methods = source.slice(source.indexOf('  private settleVisualReply('), source.indexOf('  private async refreshQuickPlugins('));
const stateSource = await readFile(new URL('../entry/src/main/ets/ui/NativePluginReplyData.ets', import.meta.url), 'utf8');
const state = stateSource.slice(stateSource.indexOf('export function modelUiReplyState('), stateSource.indexOf('export function modelUiAnswer(')).replace('export ', '');
const Owner = vm.runInNewContext(stripTypeScriptTypes(`${state}\n(class Owner { ${methods} })`), { util: { generateRandomUUID: () => 'same-request' } });
const assistant = { id: 'card', role: 'assistant', seq: 4, text: 'choose' }, text = '[dsh-ui reply]\n选择：One';
const fixture = () => {
  const owner = new Owner(), prompts = [];
  Object.assign(owner, { t: value => value, recordUsage() {}, messages: [assistant], visualReplyRequests: new Map(), visualReplyPending: [],
    visualReplyAfterSeq: -1, connected: true, sessionId: 's', chatVersion: 1, connectionVersion: 1, draft: 'unsent draft',
    applyPendingModes: async () => true, applyPendingModel: async () => true,
    client: { prompt: async (...args) => { prompts.push(args); } } });
  return { owner, prompts };
};
test('card answers keep composer content and reuse the same request after an unacknowledged send', async () => {
  const { owner, prompts } = fixture(); let attempt = 0;
  owner.client.prompt = async (...args) => { prompts.push(args); if (!attempt++) throw Error('disconnected'); };
  assert.equal(await owner.sendVisualReply(assistant, text), false);
  assert.equal(owner.sending, false); assert.equal(owner.visualState('card').state, 'live');
  assert.equal(await owner.sendVisualReply(assistant, text), true);
  assert.deepEqual(prompts[0], prompts[1]); assert.equal(owner.draft, 'unsent draft');
  assert.equal(owner.visualState('card').state, 'answered');
  assert.equal(await owner.sendVisualReply(assistant, text), false); assert.equal(prompts.length, 2);
});
test('unconfirmed session modes and host switches prevent card answers', async () => {
  const { owner, prompts } = fixture(); owner.applyPendingModes = async () => false;
  assert.equal(await owner.sendVisualReply(assistant, text), false); assert.equal(prompts.length, 0);
  owner.applyPendingModes = async () => { owner.connectionVersion++; return true; };
  assert.equal(await owner.sendVisualReply(assistant, text), false); assert.equal(prompts.length, 0);
});
test('early and late durable echoes settle pending state without unlocking an answered card', async () => {
  for (const early of [true, false]) {
    const { owner } = fixture(); const echo = { id: 'answer', role: 'user', seq: 8, text };
    owner.client.prompt = async () => { if (early) owner.messages.push(echo); };
    assert.equal(await owner.sendVisualReply(assistant, text), true);
    if (!early) { assert.equal(owner.visualReplyPending.length, 1); owner.messages.push(echo); owner.settleVisualReply(); }
    assert.equal(owner.visualReplyPending.length, 0); assert.equal(owner.visualState('card').state, 'answered');
    assert.equal(owner.draft, 'unsent draft');
  }
});
