import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';
import { util } from './mention-fixture.mjs';

const load = name => readFileSync(new URL(`../entry/src/main/ets/ui/${name}.ets`, import.meta.url), 'utf8')
  .replace(/^import .*\n/gm, '').replace(/^export /gm, '');
const measured = [], painted = [], loadedFonts = [];
const graphicsText = {
  FontCollection: { getGlobalInstance: () => ({ loadFontSync: (...args) => loadedFonts.push(args) }) },
  FontWeight: { W500: 500 },
  ParagraphBuilder: class {
    constructor(options) { this.options = options; }
    pushStyle(style) { this.style = style; }
    addText(value) { this.value = value; }
    build() {
      const paragraph = { ...this,
        layoutSync(width) { this.limit = width; measured.push(this); },
        getLongestLine() { return Math.min(this.limit, Array.from(this.value).length * this.style.fontSize / 2); },
        getHeight() { return this.style.fontSize * (this.style.heightScale || 1); },
        paint(_canvas, x, y) { painted.push({ value: this.value, style: this.style, x, y }); }
      };
      return paragraph;
    }
  }
};
const source = load('MentionData') + '\n' + load('MentionMessage').split('@Component')[0];
const { mentionMessageParts, MentionMessageSpan, MentionLabels, formatSessionMention } = vm.runInNewContext(
  stripTypeScriptTypes(`${source}\n({ mentionMessageParts, MentionMessageSpan, MentionLabels, formatSessionMention })`), {
    util, CustomSpan: class {}, graphicsText, DshGlyphs: { family: 'DshIcons', file: 'f', folder: 'd', chat: 'c' },
    $rawfile: path => path,
    drawing: { Brush: class { setAntiAlias() {} setColor(color) { this.color = color; } },
      RoundRect: class { constructor(rect, rx, ry) { Object.assign(this, { rect, rx, ry }); } } }
  });
const ui = { fp2px: value => value * 3, vp2px: value => value * 2, px2vp: value => value / 2 };
const colors = { text: '#1E232E', primary: '#4B67B4' };

test('user text keeps literal Markdown, whitespace, and complete reference wire text beside chips', () => {
  MentionLabels.clear();
  const canonical = formatSessionMention('conversation-id', '带空格 的会话');
  const original = `**literal**\n\`code\` ${canonical} 和 @"folder name/report.md"\n`;
  const parts = mentionMessageParts(original);
  assert.equal(parts.map(part => part.text).join(''), original);
  assert.deepEqual(Array.from(parts.filter(part => part.token), part => [part.token.kind, part.token.label]),
    [['session', '带空格 的会话'], ['file', 'report.md']]);
  assert.equal(parts[0].text, '**literal**\n`code` ');
  assert.equal(parts[1].text, canonical);
});

test('remembered session labels decorate host echoes and plain emails or unknown words stay text', () => {
  MentionLabels.clear();
  mentionMessageParts(formatSessionMention('s', '旧会话'));
  const echoed = mentionMessageParts('@旧会话，接着看 @folder/ 与 a@example.com 和 @someone');
  assert.deepEqual(Array.from(echoed.filter(part => part.token), part => [part.token.kind, part.token.label]),
    [['session', '旧会话'], ['folder', 'folder/']]);
  assert.equal(echoed.map(part => part.text).join(''), '@旧会话，接着看 @folder/ 与 a@example.com 和 @someone');
  assert.equal(mentionMessageParts('').length, 0);
});

test('native chip measurement bounds long labels and scales label, icon, line height, and exact font resource', () => {
  measured.length = 0;
  const chip = new MentionMessageSpan({ kind: 'session', label: 'long label '.repeat(100), start: 0, end: 1 }, colors, ui);
  const metrics = chip.onMeasure({ fontSize: 16 });
  assert.equal(metrics.width, 200);
  assert.equal(metrics.height, (16 * 3 * 0.875 * 1.25 + 4) / 2);
  assert.equal(measured[0].style.fontSize, 16 * 3 * 0.875);
  assert.equal(measured[0].style.fontWeight, 500);
  assert.equal(measured[0].style.ellipsis, '…');
  assert.equal(measured[0].options.maxLines, 1);
  assert.equal(measured[1].style.fontSize, 16 * 3 * 0.8125);
  assert.equal(measured[1].style.fontFamilies[0], 'DshIcons');
  assert.deepEqual(loadedFonts[0], ['DshIcons', 'fonts/DshIcons.ttf']);
  assert.equal(chip.onMeasure({ fontSize: 16, maxWidth: 240 }).width, 120);
});

test('native chip draws a centered stadium with primary icon and neutral label and background', () => {
  painted.length = 0;
  const chip = new MentionMessageSpan({ kind: 'file', label: 'main.ts', start: 0, end: 8 }, colors, ui);
  const metrics = chip.onMeasure({ fontSize: 16 });
  let shape, brush;
  chip.onDraw({ canvas: { attachBrush(value) { brush = value; }, detachBrush() {},
    drawRoundRect(value) { shape = value; } } }, { x: 10, lineTop: 5, lineBottom: 85, baseline: 65 });
  assert.equal(shape.rx, shape.ry);
  assert.equal(shape.rx, metrics.height);
  assert.equal((shape.rect.top + shape.rect.bottom) / 2, 45);
  assert.equal(shape.rect.right - shape.rect.left, metrics.width * 2 - 4);
  assert.deepEqual(JSON.parse(JSON.stringify(brush.color)), { alpha: 15, red: 30, green: 35, blue: 46 });
  assert.equal(painted[0].value, 'f');
  assert.deepEqual(JSON.parse(JSON.stringify(painted[0].style.color)), { alpha: 255, red: 75, green: 103, blue: 180 });
  assert.equal(painted[1].value, 'main.ts');
  assert.deepEqual(JSON.parse(JSON.stringify(painted[1].style.color)), { alpha: 255, red: 30, green: 35, blue: 46 });
});
