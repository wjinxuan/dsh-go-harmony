import assert from 'node:assert/strict';
import {existsSync, readFileSync} from 'node:fs';
import test from 'node:test';

const panelUrl = new URL('../entry/src/main/ets/ui/DSBotPanel.ets', import.meta.url);
const source = readFileSync(panelUrl, 'utf8');

function block(text, start) {
  const index = text.indexOf(start);
  assert.ok(index >= 0, 'missing: ' + start);
  let depth = 0;
  for (let at = index; at < text.length; at++) {
    if (text[at] === '{') depth++;
    else if (text[at] === '}' && --depth === 0) return text.slice(index, at + 1);
  }
  throw new Error('unbalanced block: ' + start);
}

const build = block(source, 'build()');
const chatBranch = build.slice(build.indexOf("this.page === 'chat'"), build.indexOf("else Scroll()"));
const builder = name => {
  const index = source.indexOf('@Builder private ' + name + '()');
  assert.ok(index >= 0, 'missing builder: ' + name);
  return block(source.slice(index), name + '()');
};

test('phone1152: the DS Bot chat composer is pinned outside the message scroller', () => {
  const scroll = block(chatBranch, 'Scroll(this.chatScroll)');
  assert.ok(scroll.includes('this.chatMessages()'), 'messages scroll owns the message list');
  assert.ok(!scroll.includes('this.chatComposer()'), 'composer must not sit inside the scrolling content');
  assert.ok(chatBranch.indexOf('this.chatComposer()') > chatBranch.indexOf(scroll), 'composer renders after the scroller');
  assert.ok(chatBranch.includes("Column({ space: 12 }) { this.chatComposer() }"), 'composer row is a fixed column');
  assert.ok(build.includes('Scroll(this.chatScroll)'), 'the chat scroller is bound so it can follow the newest message');
});

test('phone1152: composer keeps its own send and stop controls', () => {
  const composer = builder('chatComposer');
  assert.ok(composer.includes("Button(this.t('发送'))"), 'send button lives in the composer');
  assert.ok(composer.includes('this.draft'), 'draft text drives the composer');
  assert.ok(!builder('chatMessages').includes("this.t('发送')"), 'message list must not own the send button');
  assert.ok(!builder('chatMessages').includes('this.inputController'), 'message list must not own the text input');
});

test('phone1152: accepting a message scrolls the message list to the newest item', () => {
  const send = block(source, 'private async send(');
  assert.ok(send.includes('this.chatScroll.scrollEdge(Edge.Bottom)'), 'send must follow the newest item');
  assert.ok(build.includes('Scroll(this.chatScroll)'), 'scrollEdge needs the bound scroller');
});

// The compiled output must carry the same split; skip only when the build tree is absent.
const compiledUrl = new URL('../entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/ui/DSBotPanel.ts', import.meta.url);
if (existsSync(compiledUrl)) {
  test('phone1152: compiled panel keeps the pinned composer', () => {
    const text = readFileSync(compiledUrl, 'utf8');
    assert.ok(/private chatMessages\(/.test(text), 'compiled message builder');
    assert.ok(/private chatComposer\(/.test(text), 'compiled composer builder');
    const open = text.indexOf('Scroll.create(this.chatScroll)');
    const messages = text.indexOf('this.chatMessages.bind(this)()', open);
    const pop = text.indexOf('Scroll.pop()', messages);
    const composer = text.indexOf('this.chatComposer.bind(this)()', pop);
    assert.ok(open > 0 && messages > open && pop > messages, 'message list scrolls inside the bound scroller');
    assert.ok(composer > pop, 'compiled composer renders after the scroller pops out');
    assert.ok(/scrollEdge\(\s*Edge\.Bottom\s*\)/.test(text), 'compiled follow-latest call');
  });
}
