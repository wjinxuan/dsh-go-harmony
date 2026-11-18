import { util } from '@kit.ArkTS';
import { rcp } from '@kit.RemoteCommunicationKit';
import type { TransportControl } from '../remote/TransportEndpoint';
import { object } from '../dsh/DshWire';
export interface BundledBotState { enabled: boolean; configuredAtStart: boolean; restartRequired: boolean; }
export async function readBundledBot(control: TransportControl): Promise<BundledBotState> {
  if (!/^http:\/\/127\.0\.0\.1:[1-9]\d{0,4}$/.test(control.url) || !/^Bearer [A-Za-z0-9_-]{43}$/.test(control.authorization)) throw new Error('本机 Bot 服务地址无效');
  const session = rcp.createSession({ requestConfiguration: { proxy: 'no-proxy', transfer: { autoRedirect: false, timeout: { connectMs: 2000, transferMs: 5000 } } } });
  try {
    const response = await session.fetch(new rcp.Request(control.url + '/botBundle/state', 'GET', { 'authorization': control.authorization }));
    if (response.statusCode !== 200 || !response.body || response.body.byteLength > 4096) throw new Error('本机 Bot 状态未能读取');
    const value = object(JSON.parse(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(response.body))));
    return { enabled: value['enabled'] === true, configuredAtStart: value['activeAtStart'] === true, restartRequired: value['restartRequired'] === true };
  } finally { session.close(); }
}
export async function setBundledBot(control: TransportControl, enabled: boolean): Promise<void> {
  if (!/^http:\/\/127\.0\.0\.1:[1-9]\d{0,4}$/.test(control.url) || !/^Bearer [A-Za-z0-9_-]{43}$/.test(control.authorization)) throw new Error('本机 Bot 服务地址无效');
  const session = rcp.createSession({ requestConfiguration: { proxy: 'no-proxy', transfer: { autoRedirect: false, timeout: { connectMs: 2000, transferMs: 5000 } } } });
  try {
    const response = await session.fetch(new rcp.Request(control.url + '/botBundle/enable', 'POST', { 'authorization': control.authorization, 'content-type': 'application/json' }, JSON.stringify({ enabled: enabled })));
    if (response.statusCode !== 200 || !response.body || response.body.byteLength > 4096) throw new Error('本机 Bot 启用设置未能保存');
    const state = object(JSON.parse(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(response.body))));
    if (state['enabled'] !== enabled) throw new Error('本机 Bot 启用设置未生效');
  } finally { session.close(); }
}
