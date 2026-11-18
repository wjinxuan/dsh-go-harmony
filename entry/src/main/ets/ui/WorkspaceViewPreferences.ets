import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { workspacePreferenceChange, workspaceViewPreferences, WorkspaceViewPreferences } from './WorkspaceViewData'
import { directoryPreferenceKey } from './SessionManagementData'

const STORE: string = 'dsh-workspace-views'

export async function loadWorkspaceView(context: common.Context, scope: string): Promise<WorkspaceViewPreferences> {
  const key = directoryPreferenceKey(scope)
  if (!key) return workspaceViewPreferences()
  try {
    const store = await preferences.getPreferences(context, STORE)
    return workspaceViewPreferences(JSON.parse(store.getSync(key, '{}') as string))
  } catch { return workspaceViewPreferences() }
}

export async function changeWorkspaceView(context: common.Context, scope: string, id: string,
  action: string, value: string = ''): Promise<WorkspaceViewPreferences> {
  const key = directoryPreferenceKey(scope)
  if (!key) throw new Error('当前主机没有可用的工作区设置标识')
  const store = await preferences.getPreferences(context, STORE)
  let current: WorkspaceViewPreferences
  try { current = workspaceViewPreferences(JSON.parse(store.getSync(key, '{}') as string)) }
  catch { current = workspaceViewPreferences() }
  const next = workspacePreferenceChange(current, id, action, value)
  store.putSync(key, JSON.stringify(next)); await store.flush()
  return next
}
