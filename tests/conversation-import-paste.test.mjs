import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/ui/ConversationImportPanel.ets', import.meta.url), 'utf8');
const results = { SUCCESS: 0, TEMPORARY_AUTHORIZATION_FAILED: 1 };

function click(text, generated = false) {
  const start = text.indexOf(generated ? 'PasteButton.onClick(' : '.onClick(', text.indexOf(generated ? 'PasteButton.create(' : 'PasteButton('));
  const callback = text.indexOf('(', start) + 1;
  assert.ok(start >= 0 && callback > 0, 'security component callback exists');
  let depth = 1, quote = '', escaped = false, end = callback;
  for (; end < text.length; end++) {
    const char = text[end];
    if (quote) { if (escaped) escaped = false; else if (char === '\\') escaped = true; else if (char === quote) quote = ''; continue; }
    if (char === "'" || char === '"' || char === '`') { quote = char; continue; }
    if (char === '(') depth++;
    else if (char === ')' && --depth === 0) break;
  }
  assert.equal(depth, 0, 'complete callback');
  const code = stripTypeScriptTypes('(' + text.slice(callback, end) + ')');
  const invoke = Function('PasteButtonOnClickResult', 'event', 'result', 'const callback = ' + code + '; return callback(event, result);');
  return function(event, result) { return invoke.call(this, results, event, result); };
}

function behavior(label, callback) {
  test(label + ': denied paste authorization is visible and never reads or clears the clipboard draft', () => {
    let reads = 0;
    const owner = { text: 'existing draft', error: '', t: value => value, paste() { reads++; } };
    callback.call(owner, {}, results.TEMPORARY_AUTHORIZATION_FAILED);
    assert.equal(reads, 0); assert.equal(owner.text, 'existing draft');
    assert.equal(owner.error, '未能获得本次剪贴板访问授权。');
  });
  test(label + ': only successful security authorization starts the existing guarded paste operation', () => {
    let reads = 0;
    const owner = { error: '', t: value => value, paste() { reads++; } };
    callback.call(owner, {}, results.SUCCESS);
    assert.equal(reads, 1); assert.equal(owner.error, '');
  });
}

behavior('source callback', click(source));
if (process.argv[2]) behavior('actual CompileArkTS callback', click(readFileSync(process.argv[2], 'utf8'), true));
