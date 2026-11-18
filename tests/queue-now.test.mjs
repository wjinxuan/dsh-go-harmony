import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

const clientSource = readFileSync(new URL('../entry/src/main/ets/dsh/DshClient.ets', import.meta.url), 'utf8');
const wireSource = readFileSync(new URL('../entry/src/main/ets/dsh/DshWire.ets', import.meta.url), 'utf8');
const panelSource = readFileSync(new URL('../entry/src/main/ets/ui/ChatActivityPanel.ets', import.meta.url), 'utf8');
const between = (source, start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)));
const errors = between(wireSource, 'export class DshRpcError', 'export function parseRpcResponse').replace('export ', '') +
  between(clientSource, 'class DshAttachmentPreparationError', 'export interface DshDuplexStream');
const { Client, DshRpcError } = vm.runInNewContext(stripTypeScriptTypes(`${errors}
class Client {
  ${between(clientSource, '  async promptWithAttachments(', '  private async attachmentBase64(')}
  ${between(clientSource, '  private async sendPrompt(', '  async approve(')}
}
({ Client, DshRpcError })`), {
  Error, object: value => value && typeof value === 'object' ? value : {},
  sessionRequest: sessionId => ({ sessionId }), requestArgs: request => ({ request })
});
const Panel = vm.runInNewContext(stripTypeScriptTypes(`(class Panel {
  ${between(panelSource, '  aboutToDisappear()', '  build()')}
})`), { DshRpcError });

const prompt = (id, options = {}) => ({ id, requestId: `request-${id}`, text: id,
  target: 'next-turn', automatic: false, resendable: true, ...options });
const attachment = id => ({ id, name: `${id}.txt`, path: `/cache/${id}`, size: 4 });
const ids = items => Array.from(items, item => item.id);

function fixture(queue) {
  const client = new Client();
  const calls = [];
  const submitted = [];
  const echoed = [];
  client.generation = 1;
  client.sessionStream = {};
  client.transcript = { sessionId: 'original', running: true, queuedPrompts: () => queue, messages: () => echoed };
  client.rpc = async (method, { request }) => {
    calls.push(`${method}:${request.itemId || request.requestId || request.sessionId}`);
    if (method === 'session/prompt') submitted.push(structuredClone(request));
    return { accepted: true };
  };
  client.stageAttachment = async (sessionId, file, check) => {
    check();
    calls.push(`stage:${sessionId}:${file.id}`);
    return { type: 'file', receiptId: `new-${file.id}` };
  };
  client.attachmentBase64 = async file => `bytes-${file.id}`;
  return { client, calls, submitted, echoed };
}

test('send now restages cached files, preserves steering and request IDs, and keeps later queue order', async () => {
  const selected = prompt('selected', { hasAttachments: true, resendable: false, target: 'next-step', text: '' });
  const later = prompt('later', { hasAttachments: true, resendable: false });
  const queue = [prompt('before'), selected, prompt('steering', { target: 'next-step' }),
    prompt('automatic', { automatic: true }), prompt('remote-file', { hasAttachments: true, resendable: false }),
    later, prompt('text')];
  const { client, calls, submitted } = fixture(queue);
  const files = new Map([[selected.requestId, [attachment('one')]], [later.requestId, [attachment('two')]]]);
  const result = await client.sendQueuedNow('original', selected.id, requestId => files.get(requestId) || []);
  assert.equal(result.sent, true);
  assert.equal(result.recoverable.length, 0);
  assert.deepEqual(calls, [
    'session/updateQueue:selected', 'session/cancel:original', 'session/updateQueue:later', 'session/updateQueue:text',
    'stage:original:one', 'session/prompt:request-selected', 'stage:original:two', 'session/prompt:request-later',
    'session/prompt:request-text'
  ]);
  assert.deepEqual(submitted.map(item => [item.sessionId, item.requestId, item.mode]), [
    ['original', selected.requestId, 'steer'], ['original', later.requestId, 'queue'], ['original', 'request-text', 'queue']
  ]);
  assert.deepEqual(submitted[0].content, [{ type: 'file', receiptId: 'new-one' }]);
});

test('an unavailable or automatic attachment cannot be removed or stop the running turn', async () => {
  for (const selected of [prompt('file', { hasAttachments: true, resendable: false }), prompt('automatic', { automatic: true })]) {
    const { client, calls } = fixture([selected]);
    await assert.rejects(client.sendQueuedNow('original', selected.id), /无法重新发送/);
    assert.deepEqual(calls, []);
  }
});

test('a selected item already consumed by the host never stops the turn', async () => {
  const { client, calls } = fixture([prompt('selected')]);
  client.updateQueue = async () => { calls.push('remove'); throw new DshRpcError('session/queue-item-not-found', 'gone'); };
  await assert.rejects(client.sendQueuedNow('original', 'selected'), /gone/);
  assert.deepEqual(calls, ['remove']);
  assert.equal(client.queueMove, undefined);
});

test('a failed cancel still puts every successfully removed prompt back', async () => {
  const { client, submitted } = fixture([prompt('selected'), prompt('later')]);
  client.cancel = async () => { throw new Error('cancel failed'); };
  const result = await client.sendQueuedNow('original', 'selected');
  assert.equal(result.sent, true);
  assert.match(result.error, /停止当前回合失败/);
  assert.deepEqual(submitted.map(item => item.requestId), ['request-selected', 'request-later']);
});

test('a later item consumed concurrently is skipped without replaying it', async () => {
  const { client, submitted } = fixture([prompt('selected'), prompt('gone'), prompt('later')]);
  const update = client.updateQueue.bind(client);
  client.updateQueue = async (session, id, action) => {
    if (id === 'gone') throw new DshRpcError('session/queue-item-not-found', 'gone');
    await update(session, id, action);
  };
  const result = await client.sendQueuedNow('original', 'selected');
  assert.equal(result.error, undefined);
  assert.deepEqual(submitted.map(item => item.requestId), ['request-selected', 'request-later']);
});

test('all removed attachments survive definite preparation failures and later text is still put back', async () => {
  const selected = prompt('selected', { hasAttachments: true, resendable: false });
  const later = prompt('later', { hasAttachments: true, resendable: false });
  const { client, submitted } = fixture([selected, later, prompt('text')]);
  client.stageAttachment = async () => { throw new Error('upload unavailable'); };
  const result = await client.sendQueuedNow('original', selected.id, request => [attachment(request)]);
  assert.equal(result.sent, false);
  assert.deepEqual(ids(result.recoverable), ['selected', 'later']);
  assert.deepEqual(submitted.map(item => item.requestId), ['request-text']);
});

test('definite prompt rejection restores every removed item, including non-bad-request errors', async () => {
  const { client } = fixture([prompt('selected'), prompt('later')]);
  client.submitPromptContent = async () => { throw new DshRpcError('session/writer-held', 'writer held'); };
  const result = await client.sendQueuedNow('original', 'selected');
  assert.deepEqual(ids(result.recoverable), ['selected', 'later']);
});

test('unknown prompt acceptance is not made into a duplicate draft, but a durable echo proves success', async () => {
  for (const accepted of [false, true]) {
    const { client, echoed } = fixture([prompt('selected')]);
    client.submitPromptContent = async () => {
      if (accepted) echoed.push({ role: 'user', requestId: 'request-selected' });
      throw new Error('transport response lost');
    };
    const result = await client.sendQueuedNow('original', 'selected');
    assert.equal(result.sent, accepted);
    assert.equal(result.recoverable.length, 0);
    if (accepted) assert.equal(result.error, undefined);
    else assert.match(result.error, /未获主机确认/);
  }
});

test('changing conversation after removal only puts removed prompts back into the original session', async () => {
  const selected = prompt('selected', { hasAttachments: true, resendable: false });
  const { client, calls, submitted } = fixture([selected, prompt('later')]);
  const local = [attachment('retained')];
  const update = client.updateQueue.bind(client);
  client.updateQueue = async (...args) => {
    await update(...args);
    local.length = 0;
    client.transcript = { sessionId: 'replacement' };
  };
  const result = await client.sendQueuedNow('original', selected.id, () => local);
  assert.equal(result.sent, true);
  assert.deepEqual(calls, ['session/updateQueue:selected', 'stage:original:retained', 'session/prompt:request-selected']);
  assert.equal(submitted[0].sessionId, 'original');
});

test('host change during restaging sends nothing through the replacement connection and recovers no old content', async () => {
  const selected = prompt('selected', { hasAttachments: true, resendable: false });
  const { client, submitted } = fixture([selected, prompt('later')]);
  client.stageAttachment = async () => { client.generation++; return { type: 'file', receiptId: 'obsolete' }; };
  const result = await client.sendQueuedNow('original', selected.id, () => [attachment('old-host')]);
  assert.equal(result.sent, false);
  assert.equal(result.recoverable.length, 0);
  assert.equal(submitted.length, 0);
});

test('image fallback restages as files with the original steering mode and request ID', async () => {
  const selected = prompt('selected', { hasAttachments: true, resendable: false, target: 'next-step' });
  const { client, submitted } = fixture([selected]);
  const submit = client.submitPromptContent.bind(client);
  let attempt = 0;
  client.submitPromptContent = async (...args) => {
    await submit(...args);
    if (++attempt === 1) throw new DshRpcError('session/attachment-invalid', 'image refused', 'MODEL_DOES_NOT_SUPPORT_IMAGES');
  };
  const result = await client.sendQueuedNow('original', selected.id,
    () => [{ ...attachment('image'), mediaType: 'image/png' }]);
  assert.equal(result.sent, true);
  assert.deepEqual(submitted.map(item => [item.requestId, item.mode]), [
    ['request-selected', 'steer'], ['request-selected', 'steer']
  ]);
  assert.equal(submitted[1].content[1].receiptId, 'new-image');
});

test('relay image refusal and fallback upload failure are definite recoverable outcomes', async () => {
  for (const allowFallback of [false, true]) {
    const selected = prompt('selected', { hasAttachments: true, resendable: false });
    const { client } = fixture([selected]);
    client.submitPromptContent = async () => {
      throw new DshRpcError('session/attachment-invalid', 'image refused', 'MODEL_DOES_NOT_SUPPORT_IMAGES');
    };
    client.stageAttachment = async () => { throw new Error('fallback upload failed'); };
    const result = await client.sendQueuedNow('original', selected.id,
      () => [{ ...attachment('image'), mediaType: 'image/png' }], allowFallback);
    assert.deepEqual(ids(result.recoverable), ['selected']);
  }
});

test('queue panel dispatches local attachments through the host callback and blocks overlapping attachment work', async () => {
  const item = prompt('selected', { hasAttachments: true, resendable: false });
  const panel = new Panel();
  const calls = [];
  Object.assign(panel, { busy: '', generation: 0, sessionId: 'original', attachmentBusy: false,
    attachmentRequests: [item.requestId], client: { connectionIdentity: () => 7 },
    onSendNow: async (...args) => { calls.push(args); return { sent: true, recoverable: [] }; } });
  await panel.act(item, 'now');
  assert.deepEqual(calls[0], ['original', 7, item]);
  panel.attachmentBusy = true;
  await panel.act(item, 'now');
  panel.attachmentBusy = false;
  panel.attachmentRequests = [];
  await panel.act(item, 'now');
  assert.equal(calls.length, 1);
});
