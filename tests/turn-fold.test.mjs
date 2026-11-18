import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
const source = (await readFile(new URL('../entry/src/main/ets/ui/TurnFoldData.ets', import.meta.url), 'utf8')).replace(/^import type .*\n/gm, '');
const { foldedTurns } = await import('data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(source)));
const message = (seq, role, text, reasoning = '') => ({ key: 'm' + seq, position: seq, message: { id: 'm' + seq, role, text, reasoning, seq } });
const tool = (seq, card = false) => ({ key: 't' + seq, position: seq, tool: { callId: 't' + seq, name: 'read', arguments: '{}', seq, result: 'done', meta: card ? { 'dsh-go/media': {} } : {} } });
const done = { startSeq: 1, endSeq: 10, reason: 'completed' };
test('completed turn folds work while final reply, media card and artifacts remain visible', () => {
  const input = [message(2, 'user', 'ask'), message(3, 'assistant', 'intermediate'), tool(4, true), message(5, 'assistant', 'answer', 'thinking'),
    { key: 'artifact', position: 10.5, artifacts: [{ name: 'report.pdf' }] }];
  const rows = foldedTurns(input, [done], true);
  assert.deepEqual(rows.map(r => r.process ? 'process' : r.cardOnly ? 'card' : r.message?.text || 'artifact'), ['ask', 'process', 'card', 'answer', 'artifact']);
  assert.equal(rows[1].processTools, 1); assert.equal(rows[1].processMessages, 1);
  assert.equal(rows[1].process.find(r => r.tool).rowOnly, true);
  assert.equal(rows[3].message.reasoning, ''); assert.equal(input[3].message.reasoning, 'thinking');
  assert.equal(rows[1].process.at(-1).message.reasoning, 'thinking');
});
test('running/error/stopped turns never fold and ordinary single reasoning stays a capsule', () => {
  const rows = [message(2, 'user', 'ask'), tool(3), message(4, 'assistant', 'answer')];
  for (const reason of ['aborted', 'error', 'max-tokens', undefined]) assert.deepEqual(foldedTurns(rows, [{ ...done, reason }], true), rows);
  assert.deepEqual(foldedTurns(rows, [{ startSeq: 1, reason: 'completed' }], true), rows);
  assert.equal(foldedTurns(rows, [done], false), rows);
  const simple = [message(2, 'user', 'ask'), message(4, 'assistant', 'answer', 'thinking')];
  assert.deepEqual(foldedTurns(simple, [done], true), simple);
});
test('interjections separate process summaries and following tools invalidate a supposed final answer', () => {
  const rows = foldedTurns([message(2, 'user', 'first'), tool(3), message(4, 'assistant', 'before'), message(5, 'user', 'interrupt'),
    message(6, 'assistant', 'ongoing'), tool(7), message(8, 'assistant', 'final')], [done], true);
  const processes = rows.filter(r => r.process); assert.equal(processes.length, 2);
  assert.notEqual(processes[0].processId, processes[1].processId);
  assert.equal(processes[1].processMessages, 1);
  const noFinal = foldedTurns([message(2, 'user', 'ask'), message(3, 'assistant', 'not final'), tool(4)], [done], true);
  assert.equal(noFinal.length, 2); assert.ok(noFinal[1].process.some(r => r.message?.text === 'not final'));
});
