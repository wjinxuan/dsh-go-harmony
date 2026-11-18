import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { SpeechMode, speechMode } from '../dsh/SpeechData';

export async function loadSpeechMode(context: common.Context): Promise<SpeechMode> {
  const store = await preferences.getPreferences(context, 'dsh-voice');
  return speechMode(store.getSync('voice_recognition_mode', 'auto'));
}

export async function saveSpeechMode(context: common.Context, mode: SpeechMode): Promise<void> {
  const store = await preferences.getPreferences(context, 'dsh-voice');
  store.putSync('voice_recognition_mode', mode);
  await store.flush();
}
