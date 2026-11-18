import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

const moduleUrl = source => 'data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(source));
const wireUrl = moduleUrl(readFileSync(new URL('../entry/src/main/ets/dsh/DshWire.ets', import.meta.url), 'utf8'));
const speechUrl = moduleUrl(readFileSync(new URL('../entry/src/main/ets/dsh/SpeechData.ets', import.meta.url), 'utf8')
  .replace("'./DshWire'", JSON.stringify(wireUrl)));
const { speechCatalog, speechMode, selectedSpeechProvider, speechProviderUsable, speechMaxSeconds,
  speechPhaseLabel, speechPreparing, speechTranscript, checkSpeechWav } = await import(speechUrl);

export function wav(samples = 16000) {
  const bytes = new Uint8Array(44 + samples * 2);
  const view = new DataView(bytes.buffer);
  for (const [offset, tag] of [[0, 'RIFF'], [8, 'WAVE'], [12, 'fmt '], [36, 'data']]) {
    bytes.set(new TextEncoder().encode(tag), offset);
  }
  view.setUint32(4, bytes.length - 8, true);
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, 16000, true);
  view.setUint32(28, 32000, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  view.setUint32(40, samples * 2, true);
  return bytes.buffer;
}

test('voice defaults to auto and rejects unknown stored modes', () => {
  assert.equal(speechMode('auto'), 'auto');
  assert.equal(speechMode('engine'), 'engine');
  assert.equal(speechMode('system'), 'system');
  for (const value of ['unknown', '', 1, {}]) assert.equal(speechMode(value), 'auto');
});

test('catalog follows actual selected provider and host readiness without inventing a local model', () => {
  const catalog = speechCatalog({ providers: [
    { id: 'external', name: 'External', location: 'cloud', languages: ['zh-CN'] },
    { id: 'local', preparation: { phase: 'unprepared' }, downloadSources: ['mirror'] },
    { name: 'invalid' }
  ], selection: { providerId: 'local', language: 'zh-CN' } });
  assert.equal(catalog.providers.length, 2);
  assert.equal(catalog.providers[0].preparable, false);
  assert.equal(speechProviderUsable(catalog.providers[0]), true);
  assert.equal(selectedSpeechProvider(catalog).id, 'local');
  assert.equal(speechProviderUsable(selectedSpeechProvider(catalog)), false);
  assert.equal(catalog.maxAudioBytes, 4 * 1024 * 1024);
  assert.equal(speechMaxSeconds(catalog), 120);
  assert.equal(selectedSpeechProvider(speechCatalog({ providers: [] })), undefined);
  assert.equal(speechProviderUsable(undefined), false);
});

test('host byte and duration limits both bound recording length', () => {
  assert.equal(speechMaxSeconds(speechCatalog({ providers: [], maxAudioBytes: 44 + 64001, maxDurationSeconds: 120 })), 2);
  assert.equal(speechMaxSeconds(speechCatalog({ providers: [], maxAudioBytes: 200000, maxDurationSeconds: 2.9 })), 2);
  assert.throws(() => speechCatalog({ providers: [], maxAudioBytes: 1 }), /限额/);
  assert.throws(() => speechCatalog({ providers: [], maxDurationSeconds: 0 }), /限额/);
  assert.throws(() => speechCatalog({}), /目录/);
});

test('only known ready phases are usable; unknown remote phase text is not displayed', () => {
  for (const phase of ['ready', 'standby', 'waking']) assert.equal(speechProviderUsable({ phase }), true);
  for (const phase of ['downloading', 'failed', 'private arbitrary error']) assert.equal(speechProviderUsable({ phase }), false);
  assert.equal(speechPhaseLabel('private arbitrary error'), '状态未知');
  assert.equal(speechPreparing({ phase: 'downloading' }), true);
  assert.equal(speechPreparing({ phase: 'failed' }), false);
});

test('transcription preserves recognized text while rejecting malformed success envelopes', () => {
  assert.deepEqual(speechTranscript({ text: '  识别结果  ', audioSeconds: 1.5 }), { text: '识别结果', audioSeconds: 1.5 });
  assert.deepEqual(speechTranscript({ text: '' }), { text: '', audioSeconds: 0 });
  assert.throws(() => speechTranscript({ audioSeconds: 5 }), /转写结果/);
});

test('WAV validation accepts canonical PCM16 and rejects headers inconsistent with the actual bytes', () => {
  checkSpeechWav(wav());
  for (const [offset, value] of [[0, 0], [20, 3], [22, 2], [24, 44100], [34, 8], [40, 3]]) {
    const bytes = wav();
    new DataView(bytes).setUint16(offset, value, true);
    assert.throws(() => checkSpeechWav(bytes), /格式/);
  }
  assert.throws(() => checkSpeechWav(new ArrayBuffer(12)), /范围/);
  assert.throws(() => checkSpeechWav(new ArrayBuffer(20 * 1024 * 1024 + 1)), /范围/);
});

const panelSource = readFileSync(new URL('../entry/src/main/ets/ui/SpeechPanel.ets', import.meta.url), 'utf8');
const methods = panelSource.slice(panelSource.indexOf('  aboutToAppear()'), panelSource.indexOf('  @Builder'));
const Panel = vm.runInNewContext(stripTypeScriptTypes(`(class Panel {${methods}})`), {
  speechPreparing, setTimeout, clearTimeout
});

function panelFixture() {
  const panel = new Panel();
  Object.assign(panel, { active: true, generation: 0, timer: -1, connected: true, loading: false, busy: false,
    client: { connectionIdentity: () => 1, speechCatalog: async () => undefined } });
  return panel;
}

test('late catalog from a previous connection cannot become the new host model', async () => {
  const panel = panelFixture();
  let resolve;
  panel.client.speechCatalog = () => new Promise(ok => { resolve = ok; });
  const loading = panel.load();
  panel.client.connectionIdentity = () => 2;
  resolve({ providers: [{ id: 'old', phase: 'ready' }] });
  await loading;
  assert.equal(panel.catalog, undefined);
});

test('providers without preparation controls cannot execute fake prepare/cancel actions', async () => {
  const panel = panelFixture();
  const calls = [];
  const provider = { id: 'cloud', phase: 'ready', preparable: false };
  panel.catalog = { providers: [provider] };
  panel.client.prepareSpeech = async () => calls.push('prepare');
  panel.client.cancelSpeechPreparation = async () => calls.push('cancel');
  await panel.act(provider, 'prepare');
  await panel.act(provider, 'cancel');
  assert.deepEqual(calls, []);
});

test('host configuration does not refresh a replacement host after an old response', async () => {
  const panel = panelFixture();
  const provider = { id: 'old', languages: ['zh-CN'], phase: 'ready', preparable: true };
  panel.catalog = { providers: [provider] };
  let resolve;
  panel.client.configureSpeech = () => new Promise(ok => { resolve = ok; });
  let loads = 0;
  panel.client.speechCatalog = async () => { loads++; return undefined; };
  const saving = panel.act(provider, 'select');
  panel.scopeChanged();
  resolve();
  await saving;
  assert.equal(loads, 1);
  assert.equal(panel.catalog, undefined);
});
