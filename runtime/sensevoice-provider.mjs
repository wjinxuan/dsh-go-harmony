import { join } from 'node:path';
import { validateWave } from '@deepseek-ai/dsh-experimental-speech-to-text/wave';
import { SenseVoiceManager } from './sensevoice-manager.mjs';

export const name = 'harmony-sensevoice';
export const inject = ['speechToText'];
let manager;
export function getSenseVoiceManager() { return manager; }
export function apply(ctx) {
  manager = new SenseVoiceManager(join(process.env.DSH_HOME, 'speech-to-text', 'sensevoice'), globalThis.dshSenseVoiceNative);
  const worker = manager;
  ctx.effect(() => {
    const unregister = ctx.speechToText.register({
      info: { id: 'sensevoice-local', name: 'SenseVoiceSmall (INT8)', location: 'host-local',
        languages: ['auto', 'zh', 'en', 'yue', 'ja', 'ko'], downloadSources: ['modelscope', 'huggingface'],
        setupEstimate: { recommendedDiskBytes: 1e9, expectedMemoryBytes: 1e9, minimumMinutes: 1, maximumMinutes: 10 } },
      preparation: worker,
      transcribe(input, signal) { validateWave(input.audio, 120); return worker.transcribe(input, signal); }
    });
    worker.resume().catch(error => worker.change({ phase: 'failed', failure: { reason: error.reason ?? 'storage' } }));
    return async () => {
      const removing = unregister();
      await worker.close(); await removing;
      if (manager === worker) manager = undefined;
    };
  });
}
