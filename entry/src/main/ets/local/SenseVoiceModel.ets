import { util } from '@kit.ArkTS';
import { rcp } from '@kit.RemoteCommunicationKit';
import { object, string, number } from '../dsh/DshWire';
import { TransportControl } from '../remote/TransportEndpoint';

export interface SenseVoiceModelState {
  phase: string;
  completedBytes: number;
  totalBytes: number;
  loaded: boolean;
  nativeAvailable: boolean;
  failure: string;
  neededBytes: number;
}
export const SENSEVOICE_MODEL_BYTES: number = 241357257;
export function emptySenseVoiceState(): SenseVoiceModelState {
  return { phase: 'waiting', completedBytes: 0, totalBytes: SENSEVOICE_MODEL_BYTES,
    loaded: false, nativeAvailable: true, failure: '', neededBytes: 0 };
}
export function senseVoiceBusy(phase: string): boolean {
  return ['downloading', 'checking', 'loading', 'cancelling'].includes(phase);
}
export function senseVoiceFailure(reason: string, neededBytes: number): string {
  if (reason === 'storage') return neededBytes > 0 ? `存储空间不足，需要至少 ${Math.ceil(neededBytes / 1000000)} MB 可用空间。` : '无法保存模型，请检查存储空间。';
  if (reason === 'integrity') return '下载的模型未通过完整性校验，请重试。';
  if (reason === 'timeout') return '模型下载超时，请检查网络后重试。';
  if (reason === 'certificate') return '无法验证下载服务器的证书，请检查网络和系统时间。';
  if (reason === 'engine') return '本机模型未能加载，请重启引擎后重试。';
  return '模型下载失败，请检查网络后重试。';
}
export class SenseVoiceModelClient {
  private control: TransportControl;
  constructor(control: TransportControl) { this.control = control; }
  async request(action: string = 'state'): Promise<SenseVoiceModelState> {
    if (!['state', 'download', 'redownload', 'cancel', 'delete'].includes(action)) throw new Error('无效的模型操作');
    const match = /^http:\/\/127\.0\.0\.1:([1-9]\d{0,4})$/.exec(this.control.url);
    if (!match || Number(match[1]) > 65535 || !/^Bearer [A-Za-z0-9_-]{43}$/.test(this.control.authorization)) {
      throw new Error('本机语音服务地址无效');
    }
    const session = rcp.createSession({ requestConfiguration: { proxy: 'no-proxy',
      transfer: { autoRedirect: false, timeout: { connectMs: 3000, transferMs: 120000 } } } });
    try {
      const response = await session.fetch(new rcp.Request(this.control.url + '/sensevoice/' + action,
        action === 'state' ? 'GET' : 'POST', { authorization: this.control.authorization }));
      if (![200, 202].includes(response.statusCode) || !response.body || response.body.byteLength > 8192) throw new Error('本机语音服务未能完成操作');
      const value = object(JSON.parse(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(response.body))));
      const failure = object(value['failure']);
      return { phase: string(value['phase']) || 'failed', completedBytes: number(value['completedBytes'], 0),
        totalBytes: number(value['totalBytes'], SENSEVOICE_MODEL_BYTES), loaded: value['loaded'] === true,
        nativeAvailable: value['nativeAvailable'] === true, failure: string(failure['reason']), neededBytes: number(failure['neededBytes'], 0) };
    } finally { session.close(); }
  }
}
