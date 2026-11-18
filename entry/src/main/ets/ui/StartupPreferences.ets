import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hidebug } from '@kit.PerformanceAnalysisKit';
import { WireObject } from '../dsh/DshWire';
import { StartupHost, StartupSettings, startupHost, startupSettings, startupAutoLocal } from './StartupData';
export { StartupHost, StartupSettings, startupTarget } from './StartupData';

const FILE: string = 'dsh-startup';
export async function loadStartupSettings(context: common.Context): Promise<StartupSettings> {
  const store = await preferences.getPreferences(context, FILE);
  const raw = store.getSync('last-host-v1', '{}');
  let last: WireObject = {};
  try { last = JSON.parse(typeof raw === 'string' ? raw : '{}') as WireObject; } catch {}
  const value: WireObject = {};
  let memoryBytes: number = 0;
  try { memoryBytes = Number(hidebug.getSystemMemInfo().totalMem) * 1024; } catch {}
  value['autoStartLocal'] = startupAutoLocal(store.getSync('auto_start_local', ''), memoryBytes);
  value['restoreLastHost'] = store.getSync('remote_auto_connect_on_startup', true) !== false;
  value['lastHost'] = last;
  return startupSettings(value);
}
export async function saveStartupOptions(context: common.Context, autoStartLocal: boolean, restoreLastHost: boolean): Promise<StartupSettings> {
  const settings = await loadStartupSettings(context);
  settings.autoStartLocal = autoStartLocal; settings.restoreLastHost = restoreLastHost;
  const store = await preferences.getPreferences(context, FILE);
  store.putSync('auto_start_local', autoStartLocal); store.putSync('remote_auto_connect_on_startup', restoreLastHost);
  await store.flush(); return settings;
}
export async function rememberStartupHost(context: common.Context, kind: string, id: string = ''): Promise<void> {
  const host: StartupHost | undefined = startupHost(kind, id);
  if (!host) throw new Error('上次主机标识无效');
  const store = await preferences.getPreferences(context, FILE);
  store.putSync('last-host-v1', JSON.stringify(host)); await store.flush();
}
