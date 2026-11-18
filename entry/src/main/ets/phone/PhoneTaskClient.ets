import { util } from '@kit.ArkTS';
import { rcp } from '@kit.RemoteCommunicationKit';
import { object, string } from '../dsh/DshWire';
import type { WireObject } from '../dsh/DshWire';
import type { TransportControl } from '../remote/TransportEndpoint';
export class PhoneTaskClient {
  private control: TransportControl;
  constructor(control: TransportControl) { this.control = control; }
  async request(action: string, body: WireObject = {}): Promise<WireObject> {
    if (!['pending', 'enable', 'complete', 'stop'].includes(action) || !/^http:\/\/127\.0\.0\.1:[1-9]\d{0,4}$/.test(this.control.url) || !/^Bearer [A-Za-z0-9_-]{43}$/.test(this.control.authorization)) throw new Error('本机手机控制服务无效');
    const session = rcp.createSession({ requestConfiguration: { proxy: 'no-proxy', transfer: { autoRedirect: false, timeout: { connectMs: 2000, transferMs: 5000 } } } });
    try {
      const request = new rcp.Request(this.control.url + '/phone/' + action, action === 'pending' ? 'GET' : 'POST', { 'authorization': this.control.authorization, 'content-type': 'application/json' }, action === 'pending' ? undefined : JSON.stringify(body));
      const response = await session.fetch(request);
      if (!response.body || response.body.byteLength > 300000) throw new Error('手机控制服务响应无效');
      const value = object(JSON.parse(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(response.body))));
      if (response.statusCode !== 200) throw new Error(string(value['error']) || '手机操作未能完成');
      return value;
    } finally { session.close(); }
  }
}
