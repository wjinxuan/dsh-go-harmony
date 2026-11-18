import { object, string } from '../dsh/DshWire';

export interface StartupHost { kind: string; id: string; }
export interface StartupSettings { autoStartLocal: boolean; restoreLastHost: boolean; lastHost?: StartupHost; }
export function startupAutoLocal(stored: Object | null | undefined, memoryBytes: number): boolean {
  if (typeof stored === 'boolean') return stored;
  return !(memoryBytes > 0 && memoryBytes < 5 * 1024 * 1024 * 1024);
}
export function startupHost(kind: string, id: string = ''): StartupHost | undefined {
  if (kind === 'local') return { kind: 'local', id: '' };
  if (!['http', 'ssh', 'relay'].includes(kind) || !id || id.length > 256 || /[\x00-\x20\x7f/?#@]/.test(id)) return undefined;
  return { kind: kind, id: id };
}
export function startupSettings(value: Object): StartupSettings {
  const data = object(value), last = object(data['lastHost']);
  return { autoStartLocal: data['autoStartLocal'] !== false, restoreLastHost: data['restoreLastHost'] !== false,
    lastHost: startupHost(string(last['kind']), string(last['id'])) };
}
// A prior remote host takes precedence only when restoration is enabled. Manual navigation always wins.
export function startupTarget(settings: StartupSettings, manuallyTouched: boolean, onboardingComplete: boolean): StartupHost | undefined {
  if (manuallyTouched || !onboardingComplete) return undefined;
  const last = settings.lastHost;
  if (settings.restoreLastHost && last && last.kind !== 'local') return last;
  return settings.autoStartLocal ? startupHost('local') : undefined;
}
