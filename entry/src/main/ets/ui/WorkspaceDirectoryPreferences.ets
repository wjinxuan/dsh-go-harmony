import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { directoryPreferenceKey, recentDirectoryPaths } from './SessionManagementData'

const STORE: string = 'dsh-workspace-directories'

export async function loadRecentDirectories(context: common.Context, scope: string): Promise<string[]> {
  const key = directoryPreferenceKey(scope)
  if (!key) return []
  try {
    const store = await preferences.getPreferences(context, STORE)
    return recentDirectoryPaths(JSON.parse(store.getSync(key, '[]') as string))
  } catch { return [] }
}

export async function rememberRecentDirectory(context: common.Context, scope: string, path: string): Promise<string[]> {
  const key = directoryPreferenceKey(scope)
  if (!key) return []
  const store = await preferences.getPreferences(context, STORE)
  let previous: string[] = []
  try { previous = recentDirectoryPaths(JSON.parse(store.getSync(key, '[]') as string)) }
  catch { previous = [] }
  const paths = recentDirectoryPaths([path].concat(previous))
  store.putSync(key, JSON.stringify(paths))
  await store.flush()
  return paths
}
