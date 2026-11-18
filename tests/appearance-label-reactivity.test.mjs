import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/ui/settings/AppearanceSettings.ets', import.meta.url), 'utf8');
const locale = readFileSync(new URL('../entry/src/main/ets/ui/SettingsLocaleData.ets', import.meta.url), 'utf8');
const translate = Function(stripTypeScriptTypes(locale.replace(/^export /gm, '')) + '\nreturn settingsText;')();
function endParen(text, start) {
  let depth = 0, quote = '', escape = false;
  for (let i = start; i < text.length; i++) {
    const char = text[i];
    if (quote) { if (escape) escape = false; else if (char === '\\') escape = true; else if (char === quote) quote = ''; continue; }
    if (char === "'" || char === '"' || char === '`') { quote = char; continue; }
    if (char === '(') depth++;
    if (char === ')' && --depth === 0) return i;
  }
  throw Error('unterminated call');
}
function calls(text) {
  const output = [], re = /this\.(toggle|slider)(?:\.bind\(this\))?\(/g;
  for (let match; (match = re.exec(text));) {
    const end = endParen(text, re.lastIndex - 1);
    output.push({ kind: match[1], code: text.slice(match.index, end + 1) });
    re.lastIndex = end + 1;
  }
  assert.equal(output.filter(row => row.kind === 'toggle').length, 7);
  assert.equal(output.filter(row => row.kind === 'slider').length, 5);
  return output;
}
function sourceLabels(text) {
  return Object.fromEntries(['toggle', 'slider'].map(kind => {
    const start = text.indexOf('@Builder private ' + kind + '('), begin = text.indexOf('Text(', start) + 4;
    assert.ok(start >= 0 && begin > start);
    return [kind, Function('label', 'return ' + text.slice(begin + 1, endParen(text, begin)))];
  }));
}
function fixture(text, generated) {
  let language = 'zh', languageReads = 0, current;
  const labels = [], controls = [];
  const Text = new Proxy({}, { get: (_o, key) => key === 'create' ? value => { current.text = value; } : () => {} });
  const component = () => new Proxy({}, { get: (_o, key) => key === 'onChange' ? callback => { current.change = callback; } : () => {} });
  let owner;
  if (generated) {
    const body = ['toggle', 'slider'].map(kind => {
      const match = text.match(new RegExp('^    private ' + kind + '\\([^]*?^    \\}', 'm'));
      assert.ok(match, kind + ' compiled builder'); return match[0];
    }).join('\n');
    const Owner = Function('Text', 'Row', 'Toggle', 'Slider', 'ToggleType', 'SliderChangeMode',
      'return ' + stripTypeScriptTypes('(class Owner {' + body + '})'))(Text, component(), component(), component(),
        { Switch: 'switch' }, { End: 'end', Click: 'click' });
    owner = new Owner();
    owner.observeComponentCreation2 = (callback, type) => {
      if (type === Text) labels.push({ entry: current, render: () => callback(1, false) });
      callback(1, true);
    };
  } else {
    const expressions = sourceLabels(text);
    owner = {};
    owner.toggle = (label, value, change) => { const entry = current; labels.push({ entry, render: () => { entry.text = expressions.toggle.call(owner, label); } }); entry.change = change; };
    owner.slider = (label, value, min, max, change) => { const entry = current; labels.push({ entry, render: () => { entry.text = expressions.slider.call(owner, label); } }); entry.change = (value, mode) => { if (mode === 'end' || mode === 'click') change(value); }; };
  }
  Object.defineProperty(owner, 'localeLanguage', { get() { languageReads++; return language; } });
  Object.assign(owner, { colors: {}, loaded: true, busy: false, dark: false,
    value: { foldCompletedTurns: true, sidebarOpen: true, panelOpen: true, glass: true, hardwareEnterSends: false,
      visualReplies: true, wallpaper: { on: true, zoom: 1, alignX: 0, alignY: 0, blur: 0, dim: .6, lighten: .2 } },
    t(value) { return translate(value, this.localeLanguage); }, update(change) { change(this.value); return Promise.resolve(true); } });
  for (const call of calls(text)) {
    current = { kind: call.kind, code: call.code, text: '' }; controls.push(current);
    Function(stripTypeScriptTypes(call.code)).call(owner);
  }
  const render = () => { for (const item of labels) { current = item.entry; item.render(); } };
  render();
  return { owner, controls, render, setLanguage(value) { language = value; languageReads = 0; }, reads: () => languageReads };
}
function cases(label, text, generated) {
  test(label + ': every persisted toggle label follows same-page locale changes without remounting', () => {
    const f = fixture(text, generated), toggles = f.controls.filter(row => row.kind === 'toggle');
    const chinese = toggles.map(row => row.text);
    f.setLanguage('en'); f.render();
    assert.deepEqual(toggles.map(row => row.text), chinese.map(value => translate(value, 'en')));
    assert.ok(f.reads() >= 7, 'Text observers must read current locale to register the dependency');
    assert.equal(toggles[3].text, 'Glass effect');
    f.setLanguage('zh'); f.render(); assert.deepEqual(toggles.map(row => row.text), chinese);
  });
  test(label + ': all wallpaper slider labels update locale and the active dark/light label remains live', () => {
    const f = fixture(text, generated), sliders = f.controls.filter(row => row.kind === 'slider');
    const chinese = sliders.map(row => row.text); assert.equal(chinese.at(-1), '提亮');
    f.setLanguage('en'); f.render(); assert.deepEqual(sliders.map(row => row.text), chinese.map(value => translate(value, 'en')));
    f.owner.dark = true; f.render(); assert.equal(sliders.at(-1).text, translate('压暗', 'en'));
    f.setLanguage('zh'); f.render(); assert.equal(sliders.at(-1).text, '压暗');
  });
  test(label + ': label updates preserve glass and wallpaper change callbacks', () => {
    const f = fixture(text, generated); f.setLanguage('en'); f.render();
    f.controls.filter(row => row.kind === 'toggle')[3].change(false); assert.equal(f.owner.value.glass, false);
    const amount = f.controls.filter(row => row.kind === 'slider').at(-1);
    amount.change(.4, 'moving'); assert.equal(f.owner.value.wallpaper.lighten, .2);
    amount.change(.4, 'end'); assert.equal(f.owner.value.wallpaper.lighten, .4);
    f.owner.dark = true; amount.change(.8, 'click'); assert.equal(f.owner.value.wallpaper.dim, .8);
  });
}
// Source uses the real label expressions and call sites. Optional compiled mode
// captures actual persistent Text observers, not a native ArkUI renderer.
cases('source', source, false);
if (process.argv[2]) cases('actual CompileArkTS output', readFileSync(process.argv[2], 'utf8'), true);
