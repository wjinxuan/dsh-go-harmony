import { util } from '@kit.ArkTS';
import { rcp } from '@kit.RemoteCommunicationKit';
import { DshWebSession } from '../dsh/DshClient';
import { object, string } from '../dsh/DshWire';
import { TransportControl } from '../remote/TransportEndpoint';
export interface WebModeEndpoint { launchUrl: string; origin: string; }
export class WebMode {
  private control: TransportControl;
  private endpoint?: WebModeEndpoint;
  constructor(control: TransportControl) { this.control = control; }
  private async request(path: string, body: string): Promise<Object> {
    if (!/^http:\/\/127\.0\.0\.1:[1-9]\d{0,4}$/.test(this.control.url) || !/^Bearer [A-Za-z0-9_-]{43}$/.test(this.control.authorization)) throw new Error('本机连接地址无效');
    const session = rcp.createSession({ requestConfiguration: { proxy: 'no-proxy', transfer: { autoRedirect: false,
      timeout: { connectMs: 3000, transferMs: 20000 } } } });
    try {
      const response = await session.fetch(new rcp.Request(this.control.url + '/web/' + path, 'POST',
        { authorization: this.control.authorization, 'content-type': 'application/json' }, body));
      if (response.statusCode !== 200 || !response.body || response.body.byteLength > 8192) throw new Error('网页连接未能建立');
      return JSON.parse(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(response.body))) as Object;
    } finally { session.close(); }
  }
  async open(session: DshWebSession): Promise<WebModeEndpoint> {
    const value = object(await this.request('open', JSON.stringify(session)));
    const origin = string(value['origin']), launchUrl = string(value['launchUrl']);
    if (!/^http:\/\/127\.0\.0\.1:[1-9]\d{0,4}$/.test(origin) || !launchUrl.startsWith(origin + '/') ||
      !/\?__dsh_web_token=[A-Za-z0-9_-]{43}$/.test(launchUrl)) throw new Error('网页连接地址无效');
    this.endpoint = { origin: origin, launchUrl: launchUrl }; return this.endpoint;
  }
  async close(): Promise<void> {
    const endpoint = this.endpoint; this.endpoint = undefined;
    if (endpoint) await this.request('close', JSON.stringify({ origin: endpoint.origin }));
  }
}
