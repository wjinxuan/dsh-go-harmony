import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

const source = await readFile(new URL('../entry/src/main/ets/ui/MermaidPanel.ets', import.meta.url), 'utf8');
const component = source.slice(source.indexOf('export struct MermaidPanel'), source.indexOf('\n  build()')) + '\n}';
const executable = stripTypeScriptTypes(component.replace('export struct', 'class')
  .replace(/@(?:Prop|State)\s*/g, '').replace(/@StorageProp\('dshLanguage'\)\s*/g, '') + '\nMermaidPanel');

test('fullscreen diagram avoids actual status/cutout/navigation areas and updates on rotation', () => {
  const rect = (width = 0, height = 0) => ({ left: 0, top: 0, width, height });
  const area = (top = 0, bottom = 0, left = 0, right = 0) => ({
    topRect: rect(1200, top), bottomRect: rect(1200, bottom), leftRect: rect(left, 2400), rightRect: rect(right, 2400)
  });
  const areas = [area(120, 0), area(102, 0), area(0, 60)];
  let change, removed;
  const target = {
    getWindowAvoidArea: type => areas[type],
    on: (event, callback) => { assert.equal(event, 'avoidAreaChange'); change = callback; },
    off: (event, callback) => { assert.equal(event, 'avoidAreaChange'); removed = callback; }
  };
  const Panel = vm.runInNewContext(executable, {
    localizedSettingsText: value => value, themeColors: () => ({}),
    window: { AvoidAreaType: { TYPE_SYSTEM: 0, TYPE_CUTOUT: 1, TYPE_NAVIGATION_INDICATOR: 2 },
      findWindow: name => { assert.equal(name, 'diagram-window'); return target; } }
  });
  const panel = new Panel();
  panel.getUIContext = () => ({ getWindowName: () => 'diagram-window', px2vp: value => value / 3 });
  panel.aboutToAppear?.();
  assert.equal(panel.safeInsets?.top ?? 0, 40, 'header must begin below the 120 px system status area');
  assert.equal(panel.safeInsets.bottom, 20, 'diagram controls must avoid the navigation indicator');
  assert.match(source, /\.safeAreaPadding\(this\.safeInsets\)/, 'measured insets must reach the modal root layout');
  areas[0] = area(); areas[1] = area(0, 0, 96); areas[2] = area(0, 36);
  change({ type: 1, area: areas[1] });
  assert.equal(panel.safeInsets.top, 0); assert.equal(panel.safeInsets.left, 32); assert.equal(panel.safeInsets.bottom, 12);
  const before = panel.safeInsets;
  panel.aboutToDisappear();
  assert.equal(removed, change, 'dismissal must remove this exact window listener');
  areas[0] = area(300); change({ type: 0, area: areas[0] });
  assert.equal(panel.safeInsets, before, 'a late window event cannot update the dismissed modal');
});
