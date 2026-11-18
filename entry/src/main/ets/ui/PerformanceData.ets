import { object, string } from '../dsh/DshWire'
export interface PerformancePreferences { mode: string; refreshRate: string; blur?: boolean; animations?: boolean; fluid?: boolean }
export interface PerformanceState { preferences: PerformancePreferences; memoryBytes: number; tier: string; thermal: number; cooling: boolean;
  blur: boolean; animations: boolean; fluid: boolean; lightweight: boolean; maxRefreshRate: number; available: boolean }
export function performancePreferences(raw: Object | null | undefined = undefined): PerformancePreferences {
  const value = object(raw), mode = string(value['mode']), refresh = string(value['refreshRate'])
  return { mode: ['auto', 'full', 'light'].includes(mode) ? mode : 'auto', refreshRate: ['auto', 'max', 'system'].includes(refresh) ? refresh : 'auto',
    blur: typeof value['blur'] === 'boolean' ? value['blur'] as boolean : undefined,
    animations: typeof value['animations'] === 'boolean' ? value['animations'] as boolean : undefined,
    fluid: typeof value['fluid'] === 'boolean' ? value['fluid'] as boolean : undefined }
}
export function performanceState(prefs: PerformancePreferences = performancePreferences(), memoryBytes: number = 0,
  level: number = -1, cooling: boolean = false, maxRefreshRate: number = 60): PerformanceState {
  const tier = memoryBytes > 0 && memoryBytes < 5 * 1024 * 1024 * 1024 ? 'low' : 'medium'
  const light = cooling || prefs.mode === 'light' || (prefs.mode === 'auto' && tier === 'low')
  const animations = prefs.animations ?? !light
  return { preferences: prefs, memoryBytes: memoryBytes, tier: tier, thermal: level, cooling: cooling,
    blur: prefs.blur ?? !light, animations: animations, fluid: animations && (prefs.fluid ?? !light), lightweight: light,
    maxRefreshRate: maxRefreshRate, available: memoryBytes > 0 || level >= 0 }
}
export class ThermalPolicy {
  level: number = -1
  lightweight: boolean = false
  coolSince: number = -1
  update(level: number, now: number): void {
    if (!Number.isInteger(level) || level < 0 || level > 7) return
    this.level = level
    if (level >= 2) { this.lightweight = true; this.coolSince = -1 }
    else if (this.lightweight && this.coolSince < 0) this.coolSince = now
    this.advance(now)
  }
  advance(now: number): void {
    if (this.coolSince >= 0 && this.level >= 0 && this.level < 2 && now >= this.coolSince && now - this.coolSince >= 30000) {
      this.lightweight = false; this.coolSince = -1
    }
  }
}
export function performanceFrames(mode: string, foreground: boolean, active: boolean, maximum: number): number {
  if (!foreground || mode === 'system' || (mode === 'auto' && !active)) return 0
  return Math.max(30, Math.min(240, Number.isFinite(maximum) && maximum > 0 ? maximum : 60))
}
