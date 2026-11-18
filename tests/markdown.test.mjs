import assert from 'node:assert/strict'
import { test } from 'node:test'
import { BlockKind, InlineKind, parseInline, parseMarkdown } from './MarkdownBlocks.ts'

test('classifies blocks and preserves line order, nested lists, and code', () => {
  const source = '# Title\r\n\r\nA paragraph.\r\n\r\n1. First\r\n  - Second\r\n\r\n> Quoted\r\n> line\r\n\r\n' +
    '~~~ets\r\nColumn()\r\n~~~\r\n\r\n| Name | Value |\r\n| :--- | ---: |\r\n| a\\|b | `a|b` |'
  const blocks = parseMarkdown(source)
  assert.deepEqual(blocks.map(block => block.kind), [
    BlockKind.Heading, BlockKind.Paragraph, BlockKind.ListItem, BlockKind.ListItem, BlockKind.Quote,
    BlockKind.Code, BlockKind.Table
  ])
  assert.deepEqual(blocks.slice(2, 4).map(block => [block.label, block.level]), [['1.', 0], ['•', 1]])
  assert.equal(blocks[4].text, 'Quoted\nline')
  assert.deepEqual([blocks[5].label, blocks[5].text], ['ets', 'Column()'])
  assert.deepEqual(blocks[6].rows, [['Name', 'Value'], ['a|b', '`a|b`']])
})

test('shows an open code fence while streaming', () => {
  const blocks = parseMarkdown('Heading\n---\n\n```js\nconst x = ')
  assert.equal(blocks[0].kind, BlockKind.Heading)
  assert.equal(blocks[0].level, 2)
  assert.equal(blocks[1].kind, BlockKind.Code)
  assert.equal(blocks[1].text, 'const x = ')
})

test('replaces the bullets of Markdown tasks with checked or unchecked boxes', () => {
  const blocks = parseMarkdown('待办\n\n- [ ] 张三:整理数据\n  - [x] 李四:修复上线\n- [ ](https://example.com)')
  assert.deepEqual(blocks.slice(1).map(block => [block.kind, block.checked, block.label, block.level, block.text]), [
    [BlockKind.ListItem, false, '', 0, '张三:整理数据'],
    [BlockKind.ListItem, true, '', 1, '李四:修复上线'],
    [BlockKind.ListItem, undefined, '•', 0, '[ ](https://example.com)']
  ])
})

test('keeps the number on ordered tasks and recognizes a standalone task at a block boundary', () => {
  const blocks = parseMarkdown('1. [X] **done**\n\n正文\n[ ] Standalone\n\n```\n[x] source\n```')
  assert.deepEqual(blocks.map(block => [block.kind, block.checked, block.label, block.text]), [
    [BlockKind.ListItem, true, '1.', '**done**'],
    [BlockKind.Paragraph, undefined, '', '正文'],
    [BlockKind.ListItem, false, '', 'Standalone'],
    [BlockKind.Code, undefined, '', '[x] source']
  ])
})

test('styles inline runs and keeps unsafe links and inline HTML inert', () => {
  const spans = parseInline('**bold** *italic* `code` [safe](https://example.com) ' +
    '[settings](dshgo://open/settings) [unsafe](javascript:evil) <script> https://example.org/a.')
  assert.deepEqual(spans.filter(run => run.kind !== InlineKind.Text).map(run => [run.kind, run.text]), [
    [InlineKind.Strong, 'bold'], [InlineKind.Emphasis, 'italic'], [InlineKind.Code, 'code'],
    [InlineKind.Link, 'safe'], [InlineKind.Link, 'settings'], [InlineKind.Link, 'https://example.org/a']
  ])
  assert.match(spans.filter(run => run.kind === InlineKind.Text).map(run => run.text).join(''), /javascript:evil/)
})

test('keeps underscores inside words and retains standalone underscore emphasis', () => {
  for (const identifier of ['HARMONY_DSH_OK', 'file__part__name', '引擎_状态_确认', '_mode_flag', 'mode_flag_']) {
    const spans = parseInline(identifier)
    assert.ok(spans.every(run => run.kind === InlineKind.Text), identifier)
    assert.equal(spans.map(run => run.text).join(''), identifier)
  }
  const spans = parseInline('HARMONY_DSH_OK，_斜体_，__粗体__，foo*bar*baz')
  assert.deepEqual(spans.filter(run => run.kind !== InlineKind.Text).map(run => [run.kind, run.text]), [
    [InlineKind.Emphasis, '斜体'], [InlineKind.Strong, '粗体'], [InlineKind.Emphasis, 'bar']
  ])
})

test('math recognizes inline and display delimiters but never prices or fenced code', () => {
  for (const price of ['$5 and $10', '$5-$10', '5$ 和 10$', '$5 and 10$', '\\$5']) {
    assert.equal(parseInline(price).some(run => run.kind === InlineKind.Math), false, price);
  }
  for (const formula of ['$x^2$', '\\(x^2\\)']) {
    assert.deepEqual(parseInline('A ' + formula + ' B').map(run => [run.kind, run.text]), [
      [InlineKind.Text, 'A '], [InlineKind.Math, 'x^2'], [InlineKind.Text, ' B']]);
  }
  assert.equal(parseInline('`$x$`').some(run => run.kind === InlineKind.Math), false);
  const blocks = parseMarkdown('A\n\n$$\n\\frac{a}{b}\n$$\n\n```tex\n$x$\n```');
  assert.deepEqual(blocks.map(block => [block.kind, block.label, block.text]), [
    [BlockKind.Paragraph, '', 'A'], [BlockKind.Code, 'dsh-math', '\\frac{a}{b}'], [BlockKind.Code, 'tex', '$x$']]);
});
test('streamed display math stays copyable until closed and does not cross code fences', () => {
  const open = parseMarkdown('Before\n\n$$\\frac{a}', true);
  assert.equal(open.at(-1).label, 'dsh-math-pending');
  assert.equal(open.at(-1).text, '\\frac{a}');
  const complete = parseMarkdown('Before\n\n$$\\frac{a}{b}$$', true);
  assert.equal(complete.at(-1).label, 'dsh-math');
  const fenced = parseMarkdown('```\n$$a$$\n```');
  assert.equal(fenced.length, 1);
  assert.equal(fenced[0].label, '');
  assert.equal(fenced[0].text, '$$a$$');
  assert.equal(parseInline('$x$10').some(run => run.kind === InlineKind.Math), false);
});
