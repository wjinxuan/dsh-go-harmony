import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { Worker } from 'node:worker_threads';
import { once } from 'node:events';
import { resolve } from 'node:path';

const [addon, home, wave] = process.argv.slice(2).map(path => resolve(path));
process.env.DSH_SENSEVOICE_TEST_HOME = home;
const require = createRequire(import.meta.url);
require(addon);
const bridge = globalThis.dshSenseVoiceNative;
assert.equal(typeof bridge.load, 'function');
const wav = await readFile(wave);
let start = 12, pcm;
while (start + 8 < wav.length) {
  const size = wav.readUInt32LE(start + 4);
  if (wav.toString('ascii', start, start + 4) === 'data') { pcm = wav.subarray(start + 8, start + 8 + size); break; }
  start += 8 + size + (size & 1);
}
assert.ok(pcm);
const samples = Float32Array.from({ length: pcm.length / 2 }, (_, i) => pcm.readInt16LE(i * 2) / 32768);
await bridge.load();
const started = bridge.transcribe(samples, 'zh');
assert.throws(() => bridge.load(), /busy/);
const text = await started;
assert.match(text, /开饭时间/);
assert.match(text, /9.*5/);
assert.equal(await bridge.transcribe(new Float32Array(16000), 'auto'), '');
assert.throws(() => bridge.transcribe(new Float32Array([NaN]), 'auto'), /Invalid PCM/);
const cancelled = bridge.transcribe(samples, 'zh'); bridge.cancel();
await assert.rejects(cancelled, /cancelled/);
await bridge.unload();
await assert.rejects(bridge.transcribe(samples, 'zh'), /not loaded/);

// An isolate being terminated must join its native work before freeing V8 handles or model memory.
const worker = new Worker(`
  const { parentPort } = require('node:worker_threads');
  require(${JSON.stringify(addon)});
  globalThis.dshSenseVoiceNative.load().then(() => {
    const pending = globalThis.dshSenseVoiceNative.transcribe(new Float32Array(120 * 16000), 'auto');
    pending.catch(() => {});
    parentPort.postMessage('working');
  });
`, { eval: true });
const [message] = await once(worker, 'message'); assert.equal(message, 'working');
await worker.terminate();
console.log(`SenseVoice native bridge passed: ${text}`);
