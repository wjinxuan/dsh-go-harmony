import { object, string, strings } from '../dsh/DshWire'
import type { DshSession } from '../dsh/DshWire'

export interface QuickPanelPreferences { swipe: boolean; items: string[] }
export interface QuickDestination { id: string; title: string }
export interface LauncherEntry { kind: string; text: string; sessionId: string; host: string }
export interface RecentChatShortcut { id: string; title: string; host: string }

export const QUICK_DESTINATIONS: QuickDestination[] = [
  { id: 'web', title: '网页版' }, { id: 'remote', title: '远程主机' }, { id: 'plugins', title: '插件' },
  { id: 'engine', title: '引擎' }, { id: 'settings', title: '设置' }, { id: 'settingsSearch', title: '搜索设置' },
  { id: 'features', title: '全部功能' }
]

export function quickPanelPreferences(value: Object | null | undefined = undefined): QuickPanelPreferences {
  const row = object(value)
  const items = Array.isArray(row['items']) ? strings(row['items']) : ['plugins', 'engine', 'settings']
  return { swipe: row['swipe'] !== false, items: Array.from(new Set(items.filter((id: string) =>
    QUICK_DESTINATIONS.some((destination: QuickDestination) => destination.id === id)))) }
}

export function quickDestinationTitle(id: string): string {
  return QUICK_DESTINATIONS.find((destination: QuickDestination) => destination.id === id)?.title || id
}

export function moveQuickDestination(items: string[], id: string, direction: number): string[] {
  const result = items.slice(), from = result.indexOf(id), to = from + direction
  if (![1, -1].includes(direction) || from < 0 || to < 0 || to >= result.length) return result
  result.splice(from, 1); result.splice(to, 0, id); return result
}

// Only fixed pages/setting rows from upstream page_links.dart may be opened by an external URL.
export const PAGE_LINK_IDS: string[] = [
  'settings', 'models', 'permission', 'personalization', 'agent-presets', 'phone', 'phone-unlocks',
  'web-search', 'media', 'plugins', 'appearance', 'pets', 'interface', 'notifications', 'voice', 'performance',
  'background', 'system-permissions', 'privacy', 'shared-links', 'engine', 'remote', 'engine-settings',
  'subagent-settings', 'agent-loop', 'shell-settings', 'plugin-inventory', 'all-features', 'diagnostics', 'about',
  'account', 'chat-text-size', 'permission-default', 'phone-files', 'phone-confirm', 'dark-mode', 'general',
  'usage-stats', 'schedules', 'cordis', 'agent-team', 'forum', 'community', 'ds-bot', 'workspaces', 'companion'
]

export function appPageLink(value: string): string {
  if (value.length > 2048 || /[\x00-\x20\x7f]/.test(value.trim())) return ''
  const match = /^dshgo:\/\/open(\/[^?#]*)$/i.exec(value.trim())
  if (!match) return ''
  try {
    const segments = match[1].split('/').filter((part: string) => !!part).map((part: string) => decodeURIComponent(part))
    return segments.length === 1 && PAGE_LINK_IDS.includes(segments[0]) ? segments[0] : ''
  } catch { return '' }
}

export function launcherEntry(value: Object | null | undefined): LauncherEntry | undefined {
  const row = object(value), kind = string(row['kind']), text = string(row['text'])
  if (text.length > 131072) return undefined
  if (kind === 'new' || kind === 'voice') return { kind: kind, text: text, sessionId: '', host: '' }
  const id = string(row['sessionId']), host = string(row['host'])
  if (['chat','dsbot-bot','dsbot-room'].includes(kind) && id.length > 0 && id.length <= 256 && !/[\x00-\x1f\x7f]/.test(id) && host.length <= 4096) {
    return { kind: kind, text: '', sessionId: id, host: host }
  }
  return undefined
}

export function recentChatShortcuts(sessions: DshSession[], host: string): RecentChatShortcut[] {
  return sessions.filter((session: DshSession) => !session.archived && session.origin !== 'subagent')
    .slice().sort((a: DshSession, b: DshSession) => b.updatedAt - a.updatedAt).slice(0, 3)
    .map((session: DshSession): RecentChatShortcut => ({ id: session.id, title: session.title.trim() || '未命名对话', host: host }))
}
