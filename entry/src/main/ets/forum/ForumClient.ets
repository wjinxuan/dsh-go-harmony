import { util } from '@kit.ArkTS';
import { rcp } from '@kit.RemoteCommunicationKit';
import { object, string, WireObject } from '../dsh/DshWire';
import { TransportControl } from '../remote/TransportEndpoint';
import { privateVaultKey } from '../local/PrivateVaultKey';
export interface ForumAuthState { 'baseUrl': string; signedIn: boolean; waiting: boolean; user: WireObject; }
export class ForumClient {
  private control: TransportControl;
  private base: string = '';
  private session: rcp.Session;
  private closed: boolean = false;
  constructor(control: TransportControl) {
    if (!/^http:\/\/127\.0\.0\.1:[1-9]\d{0,4}$/.test(control.url) || !/^Bearer [A-Za-z0-9_-]{43}$/.test(control.authorization)) throw new Error('社区连接服务地址无效');
    this.control = control;
    this.session = rcp.createSession({ requestConfiguration: { proxy: 'no-proxy', transfer: { autoRedirect: false,
      timeout: { connectMs: 5000, transferMs: 120000 } } } });
  }
  async unlock(): Promise<ForumAuthState> {
    const value = await this.call('unlock', { 'masterKey': await privateVaultKey('forum') });
    return this.auth(value);
  }
  auth(value: Object): ForumAuthState {
    const data = object(value); this.base = string(data['baseUrl']);
    return { 'baseUrl': this.base, signedIn: data['signedIn'] === true, waiting: data['waiting'] === true, user: object(data['user']) };
  }
  async call(action: string, args: WireObject = {}): Promise<Object> {
    if (this.closed) throw new Error('社区连接已关闭');
    args['expectedBase'] = this.base;
    const response = await this.session.fetch(new rcp.Request(this.control.url + '/forum/call', 'POST',
      { authorization: this.control.authorization, 'content-type': 'application/json' }, JSON.stringify({ action: action, args: args })));
    if (!response.body || response.body.byteLength > 9 * 1024 * 1024) throw new Error('社区返回内容无效');
    const value = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(response.body))) as Object;
    if (response.statusCode !== 200) throw new Error(string(object(object(value)['error'])['message']) || '社区请求未能完成');
    return value;
  }
  close(): void { if (!this.closed) { this.closed = true; this.session.close(); } }
}
