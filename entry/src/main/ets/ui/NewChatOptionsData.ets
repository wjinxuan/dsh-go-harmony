import type { DshClient } from '../dsh/DshClient'
import { object, string } from '../dsh/DshWire'
import type { WireObject } from '../dsh/DshWire'

export interface NewChatModes { preset: string; permission: string }

export function newChatModes(value: Object | null | undefined): NewChatModes {
  const row = object(value)
  return { preset: string(row['preset']), permission: string(row['permission']) }
}

export function newChatSetupRecords(encoded: string): WireObject {
  try {
    const value: Object | null = JSON.parse(encoded)
    if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('invalid setup records')
    const records = object(value)
    for (const key of Object.keys(records)) {
      const item = records[key], row = object(item)
      if (!item || typeof item !== 'object' || Array.isArray(item) ||
        typeof row['preset'] !== 'string' || typeof row['permission'] !== 'string') throw new Error('invalid setup')
    }
    return records
  } catch { throw new Error('新对话的待确认设置已损坏，无法确认发送条件。请重新选择智能体和权限。') }
}

export function newChatPresets(presets: WireObject[]): WireObject[] {
  return presets.filter((preset: WireObject) => preset['id'] !== 'dsh-go-companion-full')
}

export function defaultNewChatPreset(presets: WireObject[]): string {
  return string(presets.find((preset: WireObject) => preset['isDefault'] === true)?.['id']) || string(presets[0]?.['id'])
}

export function newChatPresetToApply(presets: WireObject[], picked: string): string {
  const offered = newChatPresets(presets)
  if (offered.some((preset: WireObject) => preset['id'] === picked && !preset['broken'])) return picked
  const hiddenDefault = presets.some((preset: WireObject) => preset['id'] === 'dsh-go-companion-full' && preset['isDefault'] === true)
  const fallback = offered.find((preset: WireObject) => preset['id'] === defaultNewChatPreset(offered))
  return hiddenDefault && fallback && !fallback['broken'] ? string(fallback['id']) : ''
}

export async function resolveNewChatModes(client: DshClient, picked: NewChatModes): Promise<NewChatModes> {
  const presets = await client.listAgentPresets(), permissions = await client.permissionPresets()
  if (picked.preset && !newChatPresets(presets).some((preset: WireObject) => preset['id'] === picked.preset && !preset['broken'])) {
    throw new Error('所选智能体预设已不可用，请重新选择后发送。')
  }
  if (picked.permission && !permissions.options.some((option) => option.value === picked.permission)) {
    throw new Error('所选权限预设已不可用，请重新选择后发送。')
  }
  return { preset: newChatPresetToApply(presets, picked.preset),
    permission: picked.permission }
}

// A failed pick remains owed; a retry never submits the draft under unconfirmed choices.
export async function applyNewChatModes(client: DshClient, sessionId: string, modes: NewChatModes,
  current: () => boolean, onSettled: (remaining: NewChatModes) => Promise<void> = async () => {}): Promise<NewChatModes> {
  const remaining: NewChatModes = { preset: modes.preset, permission: modes.permission }
  const check = (): void => { if (!sessionId || !current()) throw new Error('新对话所属的主机或会话已变更') }
  check()
  if (remaining.preset) {
    await client.selectAgentPreset(sessionId, remaining.preset); check()
    const accepted = await client.sessionProjections(sessionId); check()
    if (accepted?.agentPreset !== remaining.preset) throw new Error('对话已创建，但智能体预设尚未确认。消息尚未发送。')
    remaining.preset = ''; await onSettled({ preset: remaining.preset, permission: remaining.permission }); check()
  }
  if (remaining.permission) {
    await client.setPermissionPreset(sessionId, remaining.permission); check()
    const accepted = await client.sessionProjections(sessionId); check()
    if (accepted?.permissionPreset !== remaining.permission) throw new Error('对话已创建，但权限预设尚未确认。消息尚未发送。')
    remaining.permission = ''; await onSettled({ preset: remaining.preset, permission: remaining.permission }); check()
  }
  return remaining
}
