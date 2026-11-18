import { object, string, strings } from '../dsh/DshWire'
import type { DshWorkspace, WireObject } from '../dsh/DshWire'

export interface WorkspaceViewPreferences { selected: string; pinned: string[]; groups: Record<string, string> }
export interface WorkspaceViewSection { kind: string; title: string; items: DshWorkspace[] }

export function workspaceViewPreferences(value: Object | null | undefined = undefined): WorkspaceViewPreferences {
  const row = object(value), groups = object(row['groups']), clean: Record<string, string> = {}
  for (const id of Object.keys(groups)) {
    const name = string(groups[id]).trim()
    if (name) clean[id] = name
  }
  return { selected: string(row['selected']), pinned: Array.from(new Set(strings(row['pinned']))), groups: clean }
}

export function workspaceSections(workspaces: DshWorkspace[], prefs: WorkspaceViewPreferences): WorkspaceViewSection[] {
  const pinned = workspaces.filter((workspace: DshWorkspace) => prefs.pinned.includes(workspace.id))
  const groups: Map<string, DshWorkspace[]> = new Map(), rest: DshWorkspace[] = []
  for (const workspace of workspaces) {
    if (prefs.pinned.includes(workspace.id)) continue
    const group = prefs.groups[workspace.id]
    if (!group) rest.push(workspace)
    else { const items = groups.get(group) || []; items.push(workspace); groups.set(group, items) }
  }
  const sections: WorkspaceViewSection[] = []
  if (pinned.length) sections.push({ kind: 'pinned', title: '置顶', items: pinned })
  groups.forEach((items: DshWorkspace[], title: string) => sections.push({ kind: 'group', title: title, items: items }))
  if (rest.length) sections.push({ kind: 'rest', title: sections.length ? '其他' : '', items: rest })
  return sections
}

export function workspacePreferenceChange(prefs: WorkspaceViewPreferences, id: string, action: string,
  value: string = ''): WorkspaceViewPreferences {
  const next = workspaceViewPreferences(prefs as Object)
  if (action === 'select') next.selected = id
  else if (action === 'pin') next.pinned = [id].concat(next.pinned.filter((current: string) => current !== id))
  else if (action === 'unpin') next.pinned = next.pinned.filter((current: string) => current !== id)
  else if (action === 'group') {
    if (value.trim()) next.groups[id] = value.trim()
    else next.groups = withoutGroup(next.groups, id)
  } else if (action === 'forget') {
    if (next.selected === id) next.selected = ''
    next.pinned = next.pinned.filter((current: string) => current !== id); next.groups = withoutGroup(next.groups, id)
  } else throw new Error('未知工作区操作')
  return next
}

function withoutGroup(groups: Record<string, string>, id: string): Record<string, string> {
  const result: Record<string, string> = {}
  for (const key of Object.keys(groups)) if (key !== id) result[key] = groups[key]
  return result
}

export function workspaceMoveRequest(ids: string[], id: string, direction: number): WireObject {
  const from = ids.indexOf(id), destination = from + direction
  if (![1, -1].includes(direction) || from < 0 || destination < 0 || destination >= ids.length) throw new Error('无法继续移动工作区')
  const request: WireObject = { 'workspaceId': id }
  const before = direction < 0 ? ids[destination] : ids[destination + 1]
  if (before) request['beforeWorkspaceId'] = before
  return { 'request': request }
}

export function workspaceMoveResult(value: Object | null | undefined, ids: string[], id: string, direction: number): string[] {
  const result = strings(object(value)['workspaceIds'])
  const expected = ids.slice(), from = expected.indexOf(id)
  workspaceMoveRequest(ids, id, direction)
  expected.splice(from, 1); expected.splice(from + direction, 0, id)
  if (result.length !== expected.length || result.some((value: string, index: number) => value !== expected[index])) {
    throw new Error('主机未确认工作区排序，请刷新后重试。')
  }
  return result
}

export function workspaceDisplayTitle(workspace: DshWorkspace): string {
  const title = workspace.title.trim()
  return title === 'default-workspace' ? '默认工作区' : title || workspace.path.split('/').filter((part: string) => !!part).pop() || workspace.path
}
