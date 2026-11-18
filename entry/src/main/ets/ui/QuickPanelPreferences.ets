import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { QuickPanelPreferences, quickPanelPreferences } from './ShellNavigationData'

const STORE: string = 'dsh-quick-panel'

export async function loadQuickPanelPreferences(context: common.Context): Promise<QuickPanelPreferences> {
  try {
    const store = await preferences.getPreferences(context, STORE)
    return quickPanelPreferences(JSON.parse(store.getSync('preferences', '{}') as string))
  } catch { return quickPanelPreferences() }
}

export async function saveQuickPanelPreferences(context: common.Context, value: QuickPanelPreferences): Promise<void> {
  const store = await preferences.getPreferences(context, STORE)
  store.putSync('preferences', JSON.stringify(quickPanelPreferences(value))); await store.flush()
}
