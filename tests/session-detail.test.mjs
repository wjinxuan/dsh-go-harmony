import assert from 'node:assert/strict';
import test from 'node:test';
import { goalRoundCap, sessionFileChanges, turnTotalTokens } from './ui/SessionDetailData.ts';

function call(seq, id, name, args) {
  return { seq, type: 'tool/call', data: { callId: id, name, arguments: JSON.stringify(args) } };
}

function result(seq, id, turn, meta, isError = false) {
  return { seq, type: 'tool/result', data: { turn, message: { toolCallId: id, isError }, meta } };
}

test('aggregates confirmed writes and edits by path with host diff precedence', () => {
  const [file] = sessionFileChanges([
    call(1, 'write', 'write', { file_path: './folder/a.txt', content: 'old\n' }),
    result(2, 'write', 1, { operation: 'create' }),
    call(3, 'edit', 'edit', { file_path: 'folder//a.txt', old_string: 'old', new_string: 'ignored' }),
    result(4, 'edit', 2, { diffs: [{ oldText: 'start\nold\nend', newText: 'start\nnew\nend' }] }),
    call(5, 'error', 'edit', { file_path: 'missing.txt', old_string: 'a', new_string: 'b' }),
    result(6, 'error', 2, {}, true)
  ]);
  assert.equal(file.path, 'folder/a.txt');
  assert.equal(file.created, true);
  assert.equal(file.edits, 2);
  assert.equal(file.turn, 2);
  assert.equal(file.added, 2);
  assert.equal(file.removed, 1);
  assert.deepEqual(file.lines.map(line => `${line.marker}${line.text}`),
    ['+old', '@下一次变更', ' start', '-old', '+new', ' end']);
});

test('supports legacy replace and insert without attributing successful shell or unknown overwrite', () => {
  const changes = sessionFileChanges([
    call(1, 'replace', 'str_replace_editor', { path: 'a', command: 'str_replace', old_str: 'a', new_str: 'b' }),
    result(2, 'replace', 1, {}),
    call(3, 'insert', 'str_replace_editor', { path: 'a', command: 'insert', new_str: 'one\n' }),
    result(4, 'insert', 1, {}),
    call(5, 'shell', 'bash', { path: 'b', command: 'file update' }),
    result(6, 'shell', 2, { diffs: [{ newText: 'opaque' }] }),
    call(7, 'overwrite', 'write', { file_path: 'c', content: 'unknown before' }),
    result(8, 'overwrite', 3, { operation: 'update' })
  ]);
  assert.deepEqual(changes.map(change => [change.path, change.edits, change.added, change.removed]), [['a', 2, 2, 1]]);
});

test('round cap accepts a positive safe integer and token totals honor a host-provided total', () => {
  assert.equal(goalRoundCap(''), undefined);
  assert.equal(goalRoundCap(' 7 '), 7);
  for (const value of ['-1', '0', '1.3', '4e2', '9007199254740992']) assert.throws(() => goalRoundCap(value), /正整数/);
  assert.equal(turnTotalTokens({ spans: [
    { usage: { inputTokens: 1, outputTokens: 2, totalTokens: 8 } },
    {},
    { usage: { inputTokens: 4, outputTokens: 5 } }
  ] }), 17);
});
