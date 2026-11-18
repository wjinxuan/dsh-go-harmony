import { array, number, object, string, strings } from './DshWire';

export type SpeechMode = 'auto' | 'system' | 'engine';

export interface SpeechProvider {
  id: string;
  name: string;
  location: string;
  languages: string[];
  phase: string;
  preparable: boolean;
  downloadSources: string[];
  completedBytes?: number;
  totalBytes?: number;
  failureReason?: string;
}

export interface SpeechCatalog {
  providers: SpeechProvider[];
  providerId?: string;
  language?: string;
  maxAudioBytes: number;
  maxDurationSeconds: number;
}

export interface SpeechTranscript {
  text: string;
  audioSeconds: number;
}

export function speechMode(value: Object): SpeechMode {
  return value === 'system' ? 'system' : value === 'engine' ? 'engine' : 'auto';
}

export function speechCatalog(value: Object | null | undefined): SpeechCatalog {
  const row = object(value);
  if (!Array.isArray(row['providers'])) throw new Error('主机返回了无效的语音服务目录。');
  const selection = object(row['selection']);
  const providers = array(row['providers']).map((value: Object): SpeechProvider => {
    const provider = object(value);
    const preparation = object(provider['preparation']);
    return { id: string(provider['id']), name: string(provider['name']) || string(provider['id']),
      location: string(provider['location']) || 'host-local', languages: strings(provider['languages']),
      phase: string(preparation['phase']) || 'ready',
      preparable: provider['preparation'] !== undefined && provider['preparation'] !== null,
      downloadSources: strings(provider['downloadSources']),
      completedBytes: typeof preparation['completedBytes'] === 'number' ? number(preparation['completedBytes'], 0) : undefined,
      totalBytes: typeof preparation['totalBytes'] === 'number' ? number(preparation['totalBytes'], 0) : undefined,
      failureReason: string(object(preparation['download'])['reason']) || undefined };
  }).filter((provider: SpeechProvider) => !!provider.id);
  const maxBytes = number(row['maxAudioBytes'], 4 * 1024 * 1024);
  const maxSeconds = number(row['maxDurationSeconds'], 120);
  if (maxBytes < 44 || maxSeconds <= 0) throw new Error('主机返回了无效的录音限额。');
  return { providers: providers, providerId: string(selection['providerId']) || undefined,
    language: string(selection['language']) || undefined, maxAudioBytes: maxBytes, maxDurationSeconds: maxSeconds };
}

export function selectedSpeechProvider(catalog: SpeechCatalog | undefined): SpeechProvider | undefined {
  return catalog?.providers.find((provider: SpeechProvider) => provider.id === catalog.providerId);
}

export function speechProviderUsable(provider: SpeechProvider | undefined): boolean {
  return provider !== undefined && ['ready', 'standby', 'waking'].includes(provider.phase);
}

export function speechMaxSeconds(catalog: SpeechCatalog): number {
  return Math.max(0, Math.min(Math.floor((catalog.maxAudioBytes - 44) / 32000), Math.floor(catalog.maxDurationSeconds)));
}

export function speechPreparing(provider: SpeechProvider): boolean {
  return ['downloading', 'checking', 'loading', 'waking', 'cancelling'].includes(provider.phase);
}

export function speechPhaseLabel(phase: string): string {
  if (phase === 'ready') return '可用';
  if (phase === 'standby') return '待机';
  if (phase === 'unprepared') return '尚未准备';
  if (phase === 'downloading') return '正在下载';
  if (phase === 'checking') return '正在校验';
  if (phase === 'loading') return '正在加载';
  if (phase === 'waking') return '正在唤醒';
  if (phase === 'cancelling') return '正在取消';
  if (phase === 'cancelled') return '已取消';
  if (phase === 'failed') return '准备失败';
  return '状态未知';
}

export function speechTranscript(value: Object | null | undefined): SpeechTranscript {
  const row = object(value);
  if (typeof row['text'] !== 'string') throw new Error('主机返回了无效的转写结果。');
  return { text: string(row['text']).trim(), audioSeconds: Math.max(0, number(row['audioSeconds'], 0)) };
}

export function checkSpeechWav(wav: ArrayBuffer): void {
  if (wav.byteLength < 44 || wav.byteLength > 20 * 1024 * 1024) throw new Error('录音数据超出允许范围。');
  const bytes = new Uint8Array(wav);
  const view = new DataView(wav);
  const tag = (offset: number, value: string): boolean => {
    for (let index = 0; index < value.length; index++) if (bytes[offset + index] !== value.charCodeAt(index)) return false;
    return true;
  };
  if (!tag(0, 'RIFF') || !tag(8, 'WAVE') || !tag(12, 'fmt ') || !tag(36, 'data') ||
    view.getUint32(4, true) !== wav.byteLength - 8 || view.getUint32(16, true) !== 16 ||
    view.getUint16(20, true) !== 1 || view.getUint16(22, true) !== 1 || view.getUint32(24, true) !== 16000 ||
    view.getUint32(28, true) !== 32000 || view.getUint16(32, true) !== 2 || view.getUint16(34, true) !== 16 ||
    view.getUint32(40, true) !== wav.byteLength - 44 || (wav.byteLength - 44) % 2 !== 0) {
    throw new Error('录音格式必须为 16 kHz 单声道 PCM16 WAV。');
  }
}
