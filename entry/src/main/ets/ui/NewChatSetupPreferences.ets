import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { newChatModes, newChatSetupRecords, NewChatModes } from './NewChatOptionsData'
import type { WireObject } from '../dsh/DshWire'

const STORE: string = 'dsh-new-chat-setup'
const KEY: string = 'owed-modes-v1'

export async function loadNewChatSetup(context: common.Context, scope: string, sessionId: string): Promise<NewChatModes> {
  const store = await preferences.getPreferences(context, STORE)
  const setups = newChatSetupRecords(store.getSync(KEY, '{}') as string)
  return newChatModes(setups[JSON.stringify([scope, sessionId])])
}

export async function saveNewChatSetup(context: common.Context, scope: string, sessionId: string, modes: NewChatModes): Promise<void> {
  if (!scope || !sessionId) throw new Error('新对话设置缺少主机或会话标识')
  const store = await preferences.getPreferences(context, STORE)
  const setups = newChatSetupRecords(store.getSync(KEY, '{}') as string)
  const key = JSON.stringify([scope, sessionId])
  const next: WireObject = {}
  const keys = Object.keys(setups).filter((value: string) => value !== key)
  for (const old of keys) next[old] = setups[old]
  if (modes.preset || modes.permission) next[key] = modes
  store.putSync(KEY, JSON.stringify(next)); await store.flush()
}
