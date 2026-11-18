import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import test from 'node:test';
const dir = await mkdtemp('/tmp/dsh-ansi-');
await writeFile(dir + '/AnsiData.ts', await readFile(new URL('../entry/src/main/ets/ui/AnsiData.ets', import.meta.url)));
const { parseAnsi, stripAnsi, isDarkSurface } = await import(pathToFileURL(dir + '/AnsiData.ts'));
await rm(dir, { recursive: true });
test('SGR colors, emphasis, resets and literal plain text', () => {
 const runs = parseAnsi('a\x1b[31;1;3;4mb\x1b[22;23;24;39mc\x1b[44md\x1b[0me', false);
 assert.deepEqual(runs.map(r => [r.text, r.foreground, r.background, r.bold, r.italic, r.underline]), [
  ['a', undefined, undefined, false, false, false], ['b', '#903C39', undefined, true, true, true],
  ['c', undefined, undefined, false, false, false], ['d', undefined, '#2E2E5A9A', false, false, false],
  ['e', undefined, undefined, false, false, false]]);
 assert.equal(isDarkSurface('#14171E'), true);
 assert.equal(isDarkSurface('#EDF0F6'), false);
 assert.equal(parseAnsi('\x1b[91mred', true)[0].foreground, '#F9AEA7');
});
test('256/truecolor and incomplete color sequences', () => {
 assert.equal(parseAnsi('\x1b[38;5;196mred', true)[0].foreground, '#ff0000');
 assert.equal(parseAnsi('\x1b[48;2;1;2;300mtext', false)[0].background, '#2E0102ff');
 assert.equal(parseAnsi('\x1b[38;5;232mgray', true)[0].foreground, '#080808');
 for (const sequence of ['38;5', '38;5;999', '38;2;1', '48;2']) {
  assert.equal(parseAnsi(`\x1b[${sequence}mtext`, false)[0].foreground, undefined);
 }
});
test('OSC hyperlinks/titles and cursor controls are inert; incomplete stream escape is hidden', () => {
 const source = '\x1b]8;;https://evil.invalid\x07safe\x1b]8;;\x1b\\\x1b[2J!\x1b[31';
 assert.equal(stripAnsi(source), 'safe!');
 assert.equal(parseAnsi(source, true).map(r => r.text).join(''), 'safe!');
 assert.equal(parseAnsi('\x1b]title', false).length, 0);
});
