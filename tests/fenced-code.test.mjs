import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import * as syntax from '../entry/src/main/ets/ui/highlight/FencedHighlight.js';

const directory = new URL('../entry/src/main/ets/ui/highlight/', import.meta.url);
const registry = JSON.parse(await readFile(new URL('registry.json', directory)));
const ets = new URL('../entry/src/main/ets/', import.meta.url);
const moduleUrl = source => 'data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(source));
const wireUrl = moduleUrl(await readFile(new URL('dsh/DshWire.ets', ets), 'utf8'));
const ansiUrl = moduleUrl(await readFile(new URL('ui/AnsiData.ets', ets), 'utf8'));
const diffUrl = moduleUrl((await readFile(new URL('ui/SessionDetailData.ets', ets), 'utf8'))
  .replace(/^import .*\n/, `import { array, number, object, string } from ${JSON.stringify(wireUrl)};\n`));
const native = await import(moduleUrl((await readFile(new URL('ui/CodeHighlight.ets', ets), 'utf8'))
  .replace('HighlightRun, ', '').replace('SessionDiffLine, ', '').replace(/^import \{ ThemeColors \}.*\n/m, '')
  .replace("'./highlight/FencedHighlight.js'", JSON.stringify(new URL('FencedHighlight.js', directory).href))
  .replace("'./AnsiData'", JSON.stringify(ansiUrl)).replace("'./SessionDetailData'", JSON.stringify(diffUrl))));

test('all 56 fixed upstream grammars and all 66 aliases are registered', () => {
  assert.equal(registry.languages.length, 56);
  assert.deepEqual(syntax.highlightLanguages(), registry.languages);
  for (const name of registry.languages) assert.equal(syntax.normalizedLanguage(name), name);
  for (const [alias, name] of Object.entries(registry.aliases)) assert.equal(syntax.normalizedLanguage(alias), name);
  assert.equal(syntax.normalizedLanguage('JS title="中文"'), 'javascript');
  assert.equal(syntax.normalizedLanguage('unknown-language'), '');
});

test('JS uses official grammar scopes and preserves Chinese, templates, comments and regex literals', () => {
  const code = 'const 问候 = "你好";\nfunction greet(name) { return `你好 ${name}`; }\n// 注释 const fake\nconst rx = /a+b/gi;\n';
  const spans = syntax.highlightCode(code, 'js');
  assert.equal(spans.map(s => s.text).join(''), code);
  assert.ok(spans.some(s => s.text === 'const' && s.scopes.includes('keyword')));
  assert.ok(spans.some(s => s.text.includes('你好') && s.scopes.includes('string')));
  assert.ok(spans.some(s => s.text === 'greet' && s.scopes.includes('title.function')));
  assert.ok(spans.some(s => s.text.includes('注释 const fake') && s.scopes.includes('comment')));
  assert.ok(spans.some(s => s.text.includes('/a+b/gi') && s.scopes.includes('regexp')));
});

test('all grammar outputs preserve source; markup is inert and unknown/ANSI fences stay plain', () => {
  const code = '<script>alert("中文")</script>\nconst x = 17;\n+new\n-old\n';
  for (const language of registry.languages) {
    const runs = syntax.highlightCode(code, language);
    assert.equal(runs.map(s => s.text).join(''), code, language);
  }
  const ansi = '\u001b[31mred\u001b[0m';
  assert.deepEqual(syntax.highlightCode(ansi, 'ansi'), [{ text: ansi, scopes: [] }]);
  assert.deepEqual(syntax.highlightCode(code, 'plain'), [{ text: code, scopes: [] }]);
});

test('long streaming code chunks and oversized fallback preserve every character', () => {
  const code = Array.from({ length: 1600 }, (_, i) => `const n${i} = "中文 ${i}";\n`).join('');
  assert.equal(syntax.codeChunks(code).join(''), code);
  assert.ok(syntax.codeChunks(code).length > 1);
  assert.equal(syntax.highlightCode(code, 'js').map(s => s.text).join(''), code);
  const hugeLine = '"' + '中'.repeat(25000) + '"';
  assert.deepEqual(syntax.highlightCode(hugeLine, 'js'), [{ text: hugeLine, scopes: [] }]);
  for (const partial of ['const value = "', 'const value = "中', 'const value = "中文";']) {
    assert.equal(syntax.highlightCode(partial, 'js').map(s => s.text).join(''), partial);
  }
});

test('diff and patch retain headers, markers, Chinese text and every line of a long patch', () => {
  const code = 'diff --git a/中文.js b/中文.js\nindex a..b 100644\n--- a/中文.js\n+++ b/中文.js\n@@ -1,2 +1,2 @@\n-旧值\n+新值\n 保留\n\\ No newline at end of file';
  for (const label of ['diff', 'patch', 'PATCH']) assert.equal(native.fencedCodeLanguage(label), 'diff');
  const lines = native.fencedDiffLines(code);
  assert.deepEqual(lines.map(line => line.kind), ['meta', 'meta', 'meta', 'meta', 'hunk', 'del', 'add', 'context', 'context']);
  assert.equal(lines.map(line => line.text).join('\n'), code);
  assert.deepEqual(native.fencedDiffLines('-old\n+new\n unchanged').map(line => line.kind), ['del', 'add', 'context']);
  const long = code + '\n' + Array.from({ length: 2500 }, (_, i) => `+第${i}行 ${'内容'.repeat(30)}`).join('\n') + '\n';
  assert.equal(native.fencedDiffLines(long).map(line => line.text).join('\n'), long);
  assert.equal(native.fencedDiffLines(long).filter(line => line.kind === 'add').length, 2501);
});

test('native spans use original Mist light/dark colors including full diff row backgrounds', () => {
  for (const dark of [false, true]) {
    const colors = { codeSurface: dark ? '#14171E' : '#EDF0F6', codeHeader: dark ? '#1A1E26' : '#E7EBF3',
      text: dark ? '#E6E9F0' : '#1E232E', muted: dark ? '#B6BBC5' : '#4F5562' };
    const runs = native.fencedCodeRuns('const x = "中文"; // note\n', 'js', colors);
    assert.equal(runs.map(run => run.text).join(''), 'const x = "中文"; // note\n');
    assert.equal(runs.find(run => run.text === 'const').style.color, dark ? '#C4ACF2' : '#6A499B');
    assert.equal(runs.find(run => run.text.includes('中文')).style.color, dark ? '#97D2A2' : '#336F43');
    assert.equal(runs.find(run => run.text.includes('// note')).style.italic, true);
    assert.deepEqual([native.fencedDiffStyle('add', colors).color, native.fencedDiffStyle('add', colors).background],
      dark ? ['#98D5AC', '#1C3424'] : ['#1F613C', '#DCF4E3']);
    assert.deepEqual([native.fencedDiffStyle('del', colors).color, native.fencedDiffStyle('del', colors).background],
      dark ? ['#F2A7A1', '#422423'] : ['#923A37', '#FFE4E2']);
    assert.equal(native.fencedDiffStyle('hunk', colors).background, colors.codeHeader);
    assert.equal(native.fencedDiffStyle('meta', colors).color, colors.muted);
  }
});

test('vendored runtime and grammars match their recorded hashes', async () => {
  const manifest = JSON.parse(await readFile(new URL('SOURCE.json', directory)));
  assert.equal(manifest.highlightJs.version, '11.9.0');
  for (const [file, info] of Object.entries(manifest.files)) {
    assert.equal(createHash('sha256').update(await readFile(new URL(file, directory))).digest('hex'), info.sha256, file);
  }
});

test('MessageBody dispatches native colored fences while copying raw source and retaining horizontal scroll', async () => {
  const source = await readFile(new URL('../entry/src/main/ets/ui/MessageBody.ets', import.meta.url), 'utf8');
  assert.match(source, /fencedCodeRuns\(block\.text, block\.label/);
  assert.match(source, /fencedDiffLines\(block\.text\)/);
  assert.match(source, /this\.copyCode\(block\.text\)/);
  assert.match(source, /scrollable\(ScrollDirection\.Horizontal\)/);
  assert.doesNotMatch(source, /parseAnsi\(block\.text/);
});
