import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { display } from '@kit.ArkUI'
import { thermal, deviceInfo, systemDateTime } from '@kit.BasicServicesKit'
import { hidebug } from '@kit.PerformanceAnalysisKit'
import displaySync from '@ohos.graphics.displaySync'
import { PerformancePreferences, PerformanceState, performancePreferences, performanceState, performanceFrames, ThermalPolicy } from './PerformanceData'

export class PerformanceMonitor {
  private context: common.Context
  private onChanged: (value: PerformanceState) => void
  private prefs: PerformancePreferences = performancePreferences()
  private policy: ThermalPolicy = new ThermalPolicy()
  private memory: number = 0
  private maximum: number = 60
  private active: boolean = false
  private generation: number = 0
  private preferenceVersion: number = 0
  private visible: boolean = true
  private working: boolean = false
  private timer: number = -1
  private pulseTimer: number = -1
  private pulsing: boolean = false
  private sync?: displaySync.DisplaySync
  private requestedRate: number = 0
  private writes: Promise<void> = Promise.resolve()
  constructor(context: common.Context, onChanged: (value: PerformanceState) => void) { this.context = context; this.onChanged = onChanged }
  private now(): number { return systemDateTime.getUptime(systemDateTime.TimeType.STARTUP, false) }
  async start(): Promise<void> {
    if (this.active) return
    this.active = true
    const generation = ++this.generation, version = this.preferenceVersion
    let store: preferences.Preferences
    try { store = await preferences.getPreferences(this.context, 'dsh-performance') } catch { if (generation === this.generation) this.active = false; throw new Error('性能设置读取失败') }
    if (!this.active || generation !== this.generation) return
    if (version === this.preferenceVersion) { try { this.prefs = performancePreferences(JSON.parse(store.getSync('preferences', '{}') as string)) } catch { this.prefs = performancePreferences() } }
    try { this.memory = Number(hidebug.getSystemMemInfo().totalMem) * 1024 } catch { /* Unknown hardware uses upstream medium defaults. */ }
    try {
      const screen = display.getDefaultDisplaySync()
      const rates = deviceInfo.sdkApiVersion >= 20 ? screen.supportedRefreshRates || [] : []
      this.maximum = Math.max(screen.refreshRate || 60, ...rates)
    } catch { /* System retains the current refresh rate if the display cannot be queried. */ }
    if (canIUse('SystemCapability.PowerManager.ThermalManager')) {
      try { this.levelChanged(thermal.getLevel()); thermal.registerThermalLevelCallback((level: thermal.ThermalLevel) => { if (this.active && generation === this.generation) this.levelChanged(level) }) } catch { /* Thermal service is optional. */ }
    }
    this.publish()
  }
  snapshot(): PerformanceState { return performanceState(this.prefs, this.memory, this.policy.level, this.policy.lightweight, this.maximum) }
  update(value: PerformancePreferences): Promise<void> {
    this.preferenceVersion++
    const next = performancePreferences(value)
    const operation = this.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(this.context, 'dsh-performance')
      const previous = store.getSync('preferences', '{}') as string
      store.putSync('preferences', JSON.stringify(next))
      try { await store.flush() } catch { store.putSync('preferences', previous); throw new Error('性能设置未能保存') }
      this.prefs = next; this.publish()
    })
    this.writes = operation.catch(() => {}); return operation
  }
  activity(visible: boolean, working: boolean): void { this.visible = visible; this.working = working; this.frames() }
  pulse(): void {
    if (!this.active) return
    this.pulsing = true; if (this.pulseTimer >= 0) clearTimeout(this.pulseTimer)
    this.pulseTimer = setTimeout(() => { this.pulsing = false; this.frames() }, 600)
    this.frames()
  }
  private levelChanged(level: number): void {
    if (!this.active) return
    this.policy.update(level, this.now())
    if (this.timer >= 0) clearTimeout(this.timer)
    if (this.policy.coolSince >= 0) this.timer = setTimeout(() => { this.policy.advance(this.now()); this.publish() }, 30010)
    this.publish()
  }
  private publish(): void { if (this.active) { this.onChanged(this.snapshot()); this.frames() } }
  private frames(): void {
    const rate = performanceFrames(this.prefs.refreshRate, this.active && this.visible, this.working || this.pulsing, this.maximum)
    if (rate === this.requestedRate) return
    try {
      if (!rate) this.sync?.stop()
      else {
        if (!this.sync) { this.sync = displaySync.create(); this.sync.on('frame', () => {}) }
        this.sync.setExpectedFrameRateRange({ min: rate, max: rate, expected: rate }); this.sync.start()
      }
      this.requestedRate = rate
    } catch { this.requestedRate = 0; try { this.sync?.stop() } catch { /* The display service is unavailable. */ } }
  }
  stop(): void {
    this.active = false; this.generation++; this.requestedRate = 0; this.pulsing = false
    if (this.timer >= 0) clearTimeout(this.timer)
    if (this.pulseTimer >= 0) clearTimeout(this.pulseTimer)
    try { thermal.unregisterThermalLevelCallback() } catch { /* No registered callback. */ }
    try { this.sync?.stop(); this.sync?.off('frame') } catch { /* Display service may have exited. */ }
    this.sync = undefined
  }
}
