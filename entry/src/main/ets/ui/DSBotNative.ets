import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { DshClient } from '../dsh/DshClient'
import { dsBotAnswer, DsBotEvent } from '../dsh/DsBotProtocol'
import { object, string, WireObject } from '../dsh/DshWire'
import { DSBotHub, DSBotInbox, DSBotTransport } from './DSBotData'

export async function createDSBotHub(client: DshClient, context: common.Context, host: string, locale: () => string, rpc: boolean = false): Promise<DSBotHub> {
  const identity = client.connectionIdentity(), store = await preferences.getPreferences(context,'dsh-bot-inbox')
  const key = 'host:' + host
  let inbox: DSBotInbox = { boot: '', seen: {} }
  try { const value = object(JSON.parse(store.getSync(key,'{}') as string)); inbox = { boot: string(value['boot']), seen: object(value['seen']), seq: typeof value['seq'] === 'number' ? value['seq'] as number : undefined } } catch { /* Unread counters are local, never authority for mutation. */ }
  const transport: DSBotTransport = {
    current: (): boolean => client.connectionIdentity() === identity,
    call: async (endpoint: string, payload: WireObject, timeout?: number): Promise<Object | null> => {
      if (!rpc) return client.dsBotCall(endpoint,payload,timeout)
      const args: WireObject = { 'endpoint': endpoint, 'payload': payload }; return dsBotAnswer(await client.request('dsBot/call',args,timeout))
    },
    cancel: (session: string): Promise<void> => client.cancel(session),
    feed: (consume: (event: DsBotEvent) => void, failed: (reason: string) => void): (() => void) => {
      if (!rpc) return client.dsBotFeed(consume,failed)
      let stop: (() => void) | undefined = undefined, cancelled = false
      void client.openStream('dsBot/feed',{},(value: WireObject) => { if (!cancelled) consume({ event: string(value['event']), data: object(value['data']) }) },(error?: string) => { if (!cancelled) failed(error || 'DS Bot 实时连接已断开') }).then((value: () => void) => { stop = value; if (cancelled) stop() }).catch(() => { if (!cancelled) failed('DS Bot 实时连接失败') })
      return (): void => { cancelled = true; stop?.() }
    }
  }
  const hub = new DSBotHub(transport,locale,inbox)
  let writes: Promise<void> = Promise.resolve()
  hub.onInbox = (value: DSBotInbox): void => { const snapshot = JSON.stringify(value); writes = writes.catch(() => {}).then(async () => { store.putSync(key,snapshot); await store.flush() }) }
  return hub
}
