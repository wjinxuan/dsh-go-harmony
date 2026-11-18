import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const moduleUrl = source => 'data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(source));
const wireUrl = moduleUrl(readFileSync(new URL('../entry/src/main/ets/dsh/DshWire.ets', import.meta.url), 'utf8'));
const source = readFileSync(new URL('../entry/src/main/ets/ui/MessageRegeneration.ets', import.meta.url), 'utf8')
  .replace(/^import type .*\n/gm, '').replace("'../dsh/DshWire'", JSON.stringify(wireUrl));
const { forkPointAfterReply, forkPointBeforePrompt, regenerablePrompt, bumpedForkTitle, forkBeforePrompt,
  regenerationImageInfo } = await import(moduleUrl(source));
const { DshRpcError } = await import(wireUrl);
const event = (seq, type, data = {}) => ({ seq, type, time: seq, data });
const user = (seq, text = 'question', content = [{ type: 'text', text }]) =>
  ({ id: `u${seq}`, seq, role: 'user', text, content });
const reply = (seq, text = 'answer') => ({ id: `a${seq}`, seq, role: 'assistant', text });
const replyEvent = item => event(item.seq, 'assistant/message', { message: {
  id: item.id, content: [{ type: 'text', text: item.text }]
} });
const end = (seq, kind = 'completed') => event(seq, 'turn/end', { reason: { kind } });
const prompt = user(7);
const answer = reply(8);
const records = [event(0, 'permission/preset'), event(1, 'session/title'),
  event(2, 'agent/inbox/spliced'), event(3, 'turn/start'), event(4, 'agent/inbox/spliced'),
  event(5, 'step/start'), event(6, 'system/message'), event(7, 'user/message'),
  replyEvent(answer), event(9, 'step/end'), end(10)];

test('regeneration cuts before delivery bookkeeping and requires contiguous earlier history', () => {
  assert.equal(forkPointBeforePrompt(records, 7), 1);
  assert.equal(forkPointBeforePrompt(records.slice(3), 7), undefined);
  assert.equal(forkPointBeforePrompt(records.filter(item => item.seq !== 4), 7), undefined);
  assert.equal(forkPointBeforePrompt([event(0, 'turn/start')], 1), undefined);
  assert.equal(forkPointBeforePrompt([event(1, 'step/end'), event(2, 'step/start'),
    event(3, 'agent/inbox/spliced')], 4), 1);
});

test('only a durable final reply of a non-error ended turn can regenerate', () => {
  assert.equal(forkPointAfterReply(records, 8), 10);
  assert.equal(forkPointAfterReply([...records.slice(0, -1), end(10, 'aborted')], 8), 10);
  assert.equal(forkPointAfterReply([...records.slice(0, -1), end(10, 'error')], 8), undefined);
  assert.equal(forkPointAfterReply(records.slice(0, -1), 8), undefined);
  for (const type of ['assistant/message', 'tool/call', 'tool/result', 'llm/retry']) {
    assert.equal(forkPointAfterReply([...records.slice(0, -1), event(9, type), end(10)], 8), undefined);
  }
  assert.equal(forkPointAfterReply([replyEvent(reply(8, ' ')), end(10)], 8), undefined);
  assert.equal(regenerablePrompt([prompt, answer], records, answer, false, 0), prompt);
  assert.equal(regenerablePrompt([prompt, answer], records, answer, true, 0), undefined);
  assert.equal(regenerablePrompt([prompt, answer], records, answer, false, 1), undefined);
  assert.equal(regenerablePrompt([prompt, answer], records, { ...answer, seq: undefined }, false, 0), undefined);
  assert.equal(regenerablePrompt([prompt, answer, user(12)], records, answer, false, 0), undefined);
  assert.equal(regenerablePrompt([prompt, answer], [...records, event(12, 'tool/call')], answer, false, 0), undefined);
  assert.equal(regenerablePrompt([prompt, answer], [...records, event(12, 'notice')], answer, false, 0), prompt);
});

test('regeneration preserves the nearest prompt, supports image-only input, and excludes files', () => {
  const imagePrompt = user(7, '', [{ type: 'image', attachment: { attachmentId: 'image' } }]);
  assert.equal(regenerablePrompt([user(1, 'older'), imagePrompt, answer], records, answer, false, 0), imagePrompt);
  for (const content of [[], [{ type: 'file' }], [{ type: 'image' }, { type: 'file' }]]) {
    assert.equal(regenerablePrompt([user(7, '', content), answer], records, answer, false, 0), undefined);
  }
});

test('fork title numbering matches both parenthesis styles without rounding large counters', () => {
  assert.equal(bumpedForkTitle('标题'), '标题 (1)');
  assert.equal(bumpedForkTitle('标题 (9)'), '标题 (10)');
  assert.equal(bumpedForkTitle('标题（9）'), '标题（10）');
  assert.equal(bumpedForkTitle('v(99999999999999999999)'), 'v(100000000000000000000)');
});

function fixture() {
  const calls = [];
  const client = {
    async sessionPage(...args) { calls.push(['history', ...args]); return { records }; },
    async forkSession(...args) { calls.push(['fork', ...args]); return 'child'; },
    async sessionProjections(id) { calls.push(['projections', id]); return { values: {
      title: 'inherited', inbox: { 'next-step': [{ id: 'step' }], 'next-turn': [{ id: 'turn' }] }
    } }; },
    async updateQueue(...args) { calls.push(['queue', ...args]); },
    async renameSession(...args) { calls.push(['rename', ...args]); return args[1]; }
  };
  return { client, calls };
}

test('fork preparation loads a missing prefix, removes both queues, and renames only the child', async () => {
  const { client, calls } = fixture();
  assert.deepEqual(await forkBeforePrompt(client, 'original', 7, records.slice(7), 'source', () => true),
    { sessionId: 'child', title: 'source (1)', leftQueued: 0 });
  assert.deepEqual(calls, [['history', 'original', undefined, 100, 6], ['fork', 'original', 1],
    ['projections', 'child'], ['queue', 'child', 'step', 'remove'], ['queue', 'child', 'turn', 'remove'],
    ['rename', 'child', 'source (1)']]);
});

test('cleanup failure keeps the child and counts only queues still present', async () => {
  const { client } = fixture();
  client.updateQueue = async (_id, item) => {
    throw new DshRpcError(item === 'step' ? 'session/queue-item-not-found' : 'gateway/internal', 'private');
  };
  client.renameSession = async () => { throw new Error('private'); };
  assert.deepEqual(await forkBeforePrompt(client, 'original', 7, records, 'source', () => true),
    { sessionId: 'child', title: undefined, leftQueued: 1 });
});

test('unnamed forks retain automatic titling and failed projection reads still return the created child', async () => {
  for (const fail of [false, true]) {
    const { client, calls } = fixture();
    client.sessionProjections = async () => { if (fail) throw new Error('private'); return { values: {} }; };
    const result = await forkBeforePrompt(client, 'original', 7, records, 'source', () => true);
    assert.equal(result.title, undefined);
    assert.deepEqual(calls, [['fork', 'original', 1]]);
  }
});

test('stale preparation never forks or performs cleanup on a replacement connection', async () => {
  for (const stage of ['sessionPage', 'forkSession', 'sessionProjections', 'updateQueue']) {
    const { client, calls } = fixture();
    let current = true;
    const original = client[stage];
    client[stage] = async (...args) => { const result = await original(...args); current = false; return result; };
    assert.equal(await forkBeforePrompt(client, 'original', 7, records.slice(7), 'source', () => current), undefined);
    assert.equal(calls.at(-1)[0], { sessionPage: 'history', forkSession: 'fork',
      sessionProjections: 'projections', updateQueue: 'queue' }[stage]);
  }
  const { client, calls } = fixture();
  client.sessionPage = async () => ({ records: [] });
  await assert.rejects(forkBeforePrompt(client, 'original', 7, [], '', () => true), /更早/);
  assert.deepEqual(calls, []);
});

test('original image metadata uses magic bytes, original names, and ordered default names', () => {
  assert.deepEqual(regenerationImageInfo({ name: ' original.jpg ', mediaType: 'image/jpeg' },
    new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]).buffer, 0),
    { name: 'original.jpg', mediaType: 'image/png' });
  for (const [signature, type, extension] of [
    [[255, 216, 255], 'image/jpeg', 'jpg'], [[71, 73, 70, 56], 'image/gif', 'gif'],
    [[82, 73, 70, 70, 0, 0, 0, 0, 87, 69, 66, 80], 'image/webp', 'webp']
  ]) {
    assert.deepEqual(regenerationImageInfo({}, new Uint8Array(signature).buffer, 2),
      { name: `image-3.${extension}`, mediaType: type });
  }
  assert.deepEqual(regenerationImageInfo({ mediaType: 'image/png' }, new Uint8Array([0]).buffer, 0),
    { name: 'image-1.png', mediaType: 'image/png' });
});
