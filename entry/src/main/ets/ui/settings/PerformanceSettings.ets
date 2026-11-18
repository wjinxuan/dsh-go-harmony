import { PerformancePreferences, PerformanceState, performancePreferences, performanceState } from '../PerformanceData'
import { localizedSettingsText, localizedSettingsFormat } from '../SettingsLocale'
import { ThemeColors, themeColors } from '../DshTheme'
@Component
export struct PerformanceSettings {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  @Prop colors: ThemeColors = themeColors()
  @Prop state: PerformanceState = performanceState()
  onClose: () => void = () => {}
  onChange: (value: PerformancePreferences) => Promise<void> = async () => { throw new Error(this.t("性能服务尚未就绪")) }
  @State private busy: boolean = false
  @State private error: string = ''
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private async change(key: string, value: string | boolean | undefined): Promise<void> {
    if (this.busy) return
    this.busy = true; this.error = ''
    const next = performancePreferences(this.state.preferences)
    if (key === 'mode') next.mode = value as string
    else if (key === 'refreshRate') next.refreshRate = value as string
    else if (key === 'blur') next.blur = value as boolean
    else if (key === 'animations') next.animations = value as boolean
    else if (key === 'fluid') next.fluid = value as boolean
    else { next.blur = undefined; next.animations = undefined; next.fluid = undefined }
    try { await this.onChange(next) } catch { this.error = this.t('性能设置未能保存') }
    finally { this.busy = false }
  }
  @Builder private toggle(label: string, value: boolean, key: string) {
    Row() { Text(this.t(label)).fontColor(this.colors.text).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: value }).onChange((next: boolean) => { void this.change(key, next) }) }.width('100%').padding(10)
  }
  build() {
    Column({ space: 14 }) {
      Row() { Button(this.t('返回')).onClick(this.onClose); Text(this.t('性能')).fontSize(22).fontColor(this.colors.text).layoutWeight(1) }.width('100%')
      Scroll() { Column({ space: 12 }) {
        ForEach(['auto', 'full', 'light'], (mode: string) => {
          Button(this.t(mode === 'auto' ? '自动' : mode === 'full' ? '完整效果' : '轻量模式')).width('100%')
            .backgroundColor(this.state.preferences.mode === mode ? this.colors.primary : this.colors.surface)
            .fontColor(this.state.preferences.mode === mode ? this.colors.onPrimary : this.colors.text).onClick(() => { void this.change('mode', mode) })
        })
        Text(this.t(this.state.cooling ? '设备正在降温，已临时采用轻量效果。温度恢复 30 秒后恢复所选设置。' : '自动模式根据设备内存和温度选择效果；手动覆盖的效果设置会保留。'))
          .fontSize(13).fontColor(this.colors.muted).width('100%')
        Text(this.t('屏幕刷新率')).fontSize(17).fontColor(this.colors.text).width('100%')
        Select([{ value: this.t('自动') }, { value: this.t('最高刷新率') }, { value: this.t('跟随系统') }])
          .selected(['auto', 'max', 'system'].indexOf(this.state.preferences.refreshRate))
          .value(this.t(this.state.preferences.refreshRate === 'max' ? '最高刷新率' : this.state.preferences.refreshRate === 'system' ? '跟随系统' : '自动'))
          .onSelect((index: number) => { void this.change('refreshRate', ['auto', 'max', 'system'][index]) })
        Text(this.t('自动：滚动和流式输出时请求最高刷新率，停下后交回系统。实际刷新率由设备决定。')).fontSize(13).fontColor(this.colors.muted)
        this.toggle(this.t("模糊效果"), this.state.blur, 'blur')
        this.toggle(this.t("动画"), this.state.animations, 'animations')
        if (this.state.animations) this.toggle(this.t("灵动动效"), this.state.fluid, 'fluid')
        Button(this.t('恢复当前模式的默认效果')).onClick(() => { void this.change('reset', undefined) })
        Text(localizedSettingsFormat('内存 {0} GiB · 最高 {1} Hz · 温度等级 {2}', [this.state.memoryBytes > 0 ? (this.state.memoryBytes / 1073741824).toFixed(1) : '—', this.state.maxRefreshRate, this.state.thermal < 0 ? '—' : this.state.thermal], this.localeLanguage))
          .fontSize(12).fontColor(this.colors.muted).width('100%')
      }.width('100%').enabled(!this.busy) }.layoutWeight(1).width('100%')
      if (this.error) Text(this.error).fontColor(this.colors.danger)
    }.padding(16).width('100%').height('100%')
  }
}
