import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { loadMediaModules } from './media-loader.mjs';
import { parseGenerationMessage } from '../runtime/vendor/dsh-media/src/header.js';

const source = readFileSync(new URL('../entry/src/main/ets/ui/MediaGeneratePanel.ets', import.meta.url), 'utf8');
const { mediaCatalog, fitMediaParams, formatMediaMessage, parseMediaHeader } = await loadMediaModules();
const schema = JSON.parse(readFileSync(new URL('./fixtures/media/settings_describe_media_m0.json', import.meta.url)));
const upstream = JSON.parse(readFileSync(new URL('../runtime/vendor/dsh-media/data/models.json', import.meta.url)));
const meta = Object.values(schema.namespaces[0].schema.refs).find(node => node.meta?.extra?.['dsh-go/media/catalog']).meta.extra['dsh-go/media/catalog'];
meta.models = upstream.models; meta.capabilities = { image: true, video: true };
schema.namespaces[0].value.services = [
  { id: 'image_fixture', label: 'Image', provider: 'Synthetic', enabled: true, profile: 'openai-gpt-image', baseUrl: 'https://synthetic.invalid/v1',
    keyRef: 'DSH_MEDIA_SLOT_1_API_KEY', models: 'gpt-image-2.5-flare' },
  { id: 'video_fixture', label: 'Video', provider: 'Synthetic', enabled: true, profile: 'ark-video', baseUrl: 'https://ark.cn-beijing.volces.com',
    keyRef: 'DSH_MEDIA_SLOT_1_API_KEY', models: 'doubao-seedance-2-5-260628' }
];
schema.namespaces[0].value.defaults = {};
const catalog = mediaCatalog(schema, { DSH_MEDIA_SLOT_1_API_KEY: { configured: true } });
assert.equal(catalog.entries.length, 2);
const method = (text, name) => {
  const found = text.match(new RegExp('^  private ' + name + '\\([\\s\\S]*?^  }', 'm'));
  return found?.[0];
};
const methods = ['choose', 'change', 'select', 'choiceValues', 'choiceSelected'].map(name => method(source, name)).filter(Boolean).join('\n');
const Owner = Function('fitMediaParams', 'formatMediaMessage', 'return ' + stripTypeScriptTypes('(class Owner {' + methods + '})'))(fitMediaParams, formatMediaMessage);
function owner() {
  return Object.assign(new Owner(), { catalog, params: fitMediaParams({ kind: 'image', count: 2, aspect: '3:2', quality: 'high' }, catalog),
    t: value => value, colors: { primary: 'selected', surfaceAlt: 'normal', text: 'text', onPrimary: 'white' }, onSelected() {} });
}

// Recreate only the captured @Builder parameter boundary from actual source.
// The expressions evaluated below are extracted from the real ForEach/style/click.
function sourceChoices(state, field) {
  const declaration = source.match(/private choices\(([^)]*)\)/)[1];
  const parameters = declaration.split(',').map(value => value.split(':')[0].trim());
  const builder = source.slice(source.indexOf('private choices('), source.indexOf('\n  build()'));
  const values = builder.match(/ForEach\((.*), \(value: string\) =>/)[1];
  const color = builder.match(/\.backgroundColor\((.*?)\)\n/)[1];
  const click = builder.match(/\.onClick\(\(\) => (this\.change\([^\n]*?\))\)/)[1];
  const call = source.split('\n').find(line => line.includes('this.choices(') && line.includes("'" + field + "'"));
  assert.ok(call, field);
  const args = Function('return [' + call.trim().slice('this.choices('.length, -1) + ']') .call(state);
  return Function(...parameters, 'return { values: () => ' + values + ', color: value => ' + color + ', click: value => ' + click + ' }')
    .call(state, ...args);
}

test('image → video retains the builder but replaces ratios with the actual video catalogue', () => {
  const state = owner(), view = sourceChoices(state, 'aspect');
  assert.deepEqual(view.values(), ['1:1', '3:2', '2:3']);
  state.choose('video');
  assert.equal(state.params.aspect, '16:9');
  assert.deepEqual(view.values(), ['16:9', '9:16', '1:1']);
  for (const aspect of view.values()) {
    view.click(aspect);
    assert.equal(state.params.aspect, aspect);
    assert.equal(parseMediaHeader(formatMediaMessage(state.params, 'video')).aspect, aspect);
  }
  state.choose('image'); assert.deepEqual(view.values(), ['1:1', '3:2', '2:3']);
});

test('retained option buttons read the current selection instead of the builder creation value', () => {
  const state = owner(), view = sourceChoices(state, 'aspect');
  assert.equal(view.color('3:2'), 'selected'); view.click('2:3');
  assert.equal(view.color('2:3'), 'selected'); assert.equal(view.color('3:2'), 'normal');
  const counts = sourceChoices(state, 'count'); counts.click('1');
  assert.equal(counts.color('1'), 'selected'); assert.equal(counts.color('2'), 'normal');
});

test('same-kind model capability replacement refreshes all retained choice lists', () => {
  const state = owner(), ratio = sourceChoices(state, 'aspect'), count = sourceChoices(state, 'count'), quality = sourceChoices(state, 'quality');
  const changed = structuredClone(state.params.model); changed.model.ratios = ['4:3']; changed.model.maxN = 1; changed.model.qualities = ['low'];
  state.catalog = { ...catalog, entries: [changed, catalog.entries[1]] }; state.choose('image', changed);
  assert.deepEqual(ratio.values(), ['4:3']); assert.deepEqual(count.values(), ['1']); assert.deepEqual(quality.values(), ['', 'low']);
  state.choose('video'); const seconds = sourceChoices(state, 'seconds'), resolution = sourceChoices(state, 'resolution');
  const video = structuredClone(state.params.model); video.model.durations = [8, 12]; video.model.resolutions = ['1080p'];
  state.catalog = { ...catalog, entries: [changed, video] }; state.choose('video', video);
  assert.deepEqual(seconds.values(), ['8', '12']); assert.deepEqual(resolution.values(), ['1080p']);
});

test('video 1:1 is explicitly serialized and survives the real shared header parser', () => {
  const state = owner(); state.choose('video'); state.change('aspect', '1:1'); state.change('seconds', '10');
  const message = formatMediaMessage(state.params, '合成视频测试');
  assert.match(message, /^〔生成视频 · 1:1 · 10 秒 · 720p · Seedance 2\.5〈video_fixture\/doubao-seedance-2-5-260628〉〕/);
  assert.deepEqual(parseMediaHeader(message), { kind: 'video', prompt: '合成视频测试', aspect: '1:1', seconds: 10, quality: '720p',
    model: { label: 'Seedance 2.5', serviceId: 'video_fixture', id: 'doubao-seedance-2-5-260628' } });
  assert.deepEqual(parseGenerationMessage(message), parseMediaHeader(message), 'the untouched upstream parser used by the synthetic provider sees explicit 1:1');
});

if (process.argv[2]) {
  const compiled = readFileSync(process.argv[2], 'utf8');
  const start = compiled.indexOf('    private choices('), end = compiled.indexOf('\n    initialRender()', start);
  assert.ok(start >= 0 && end > start);
  const generatedMethod = stripTypeScriptTypes('(class View {' + compiled.slice(start, end) + '})');
  let choiceState;
  const widget = () => new Proxy({}, { get: (_target, name) => name === 'createWithLabel' ? value => { choiceState.labels.push(value); } : () => {} });
  const If = widget(), Column = widget(), Text = widget(), Flex = widget(), Button = widget(), ForEach = widget();
  const Generated = Function('If', 'Column', 'Text', 'Flex', 'Button', 'ForEach', 'FlexWrap', 'return ' + generatedMethod)
    (If, Column, Text, Flex, Button, ForEach, { Wrap: 0 });
  test('actual compiled builder callbacks refresh image/video ratios without remount', () => {
    const state = owner(), callbacks = [], branches = new Map(); let currentId = 0;
    choiceState = state; state.labels = [];
    state.observeComponentCreation2 = callback => { const id = callbacks.length; callbacks.push(callback); currentId = id; callback(id, true); };
    state.ifElseBranchUpdateFunction = (branch, build) => { if (branches.get(currentId) !== branch) { branches.set(currentId, branch); build(); } };
    state.forEachUpdateFunction = (_id, items) => { state.latestValues = [...items]; };
    const signature = compiled.slice(start, compiled.indexOf('{', start));
    const initialArgs = signature.includes('values:') ? ['比例', 'aspect', state.params.model.model.ratios, state.params.aspect] : ['比例', 'aspect'];
    Generated.prototype.choices.call(state, ...initialArgs);
    assert.deepEqual(state.latestValues, ['1:1', '3:2', '2:3']);
    state.choose('video');
    callbacks.slice().forEach((callback, id) => { currentId = id; callback(id, false); });
    assert.deepEqual(state.latestValues, ['16:9', '9:16', '1:1']);
  });
}
