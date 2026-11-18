import { common } from '@kit.AbilityKit'
import { ThemeColors, themeColors } from './DshTheme'
import { localizedSettingsText } from './SettingsLocale'
import { SystemAccessState, systemAccess, requestSystemAccess } from './SystemAccess'

@Component
export struct SystemAccessPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  @StorageProp('dshForeground') @Watch('foregroundChanged') private foreground: boolean = true
  @Prop colors: ThemeColors = themeColors()
  @Prop backgroundPage: boolean = false
  onClose: () => void = () => {}
  onPhone: () => void = () => {}
  onNotifications: () => void = () => {}
  @State private state: SystemAccessState = { microphone: 'unknown', notifications: 'unknown', capture: false }
  @State private busy: boolean = false
  @State private error: string = ''
  private active: boolean = false
  private generation: number = 0
  private lifetime: number = 0
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext }
  aboutToAppear(): void { this.active = true; this.busy = false; this.lifetime++; void this.refresh() }
  aboutToDisappear(): void { this.active = false; this.generation++; this.lifetime++ }
  private foregroundChanged(): void { if (this.active && this.foreground) void this.refresh() }
  private async refresh(): Promise<void> {
    const generation = ++this.generation
    const state = await systemAccess(this.context())
    if (this.active && generation === this.generation) this.state = state
  }
  private async request(kind: string): Promise<void> {
    if (this.busy) return
    const lifetime = this.lifetime
    this.busy = true; this.error = ''
    try { await requestSystemAccess(this.context(), kind) }
    catch { if (this.active && lifetime === this.lifetime) this.error = this.t("系统没有完成此操作，请在系统设置中查看当前应用的权限。") }
    finally { if (this.active && lifetime === this.lifetime) { this.busy = false; await this.refresh() } }
  }
  private label(value: string): string { return this.t(value === 'granted' ? '已允许' : value === 'denied' ? '未允许' : '无法读取') }
  @Builder private row(title: string, state: string, action: () => void) {
    Button(this.t(title) + ' · ' + state).width('100%').fontColor(this.colors.text).backgroundColor(this.colors.surface).enabled(!this.busy).onClick(action)
  }
  build() {
    Column({ space: 14 }) {
      Row() { Button(this.t('返回')).onClick(this.onClose); Text(this.t(this.backgroundPage ? '后台运行' : '系统权限')).fontSize(22).fontColor(this.colors.text).layoutWeight(1) }.width('100%')
      Scroll() { Column({ space: 14 }) {
        if (this.backgroundPage) {
          Text(this.t('本机引擎会受到系统后台调度限制。离开应用或锁屏后，正在运行的任务可能暂停；返回后会重新连接并读取实际状态。')).fontColor(this.colors.text).fontSize(15)
          Text(this.t('需要长时间运行的任务可使用远程主机。主机继续执行，手机重连后恢复查看。')).fontColor(this.colors.muted).fontSize(14)
          Button(this.t('打开应用系统设置')).enabled(!this.busy).onClick(() => { void this.request('settings') })
          Text(this.t('后台保活与电池管理由设备系统控制，本应用不能自行授予或保证后台运行权限。')).fontColor(this.colors.muted).fontSize(13)
        }
        this.row(this.t("麦克风"), this.label(this.state.microphone), () => { void this.request('microphone') })
        this.row(this.t("通知"), this.label(this.state.notifications), () => { void this.request('notifications') })
        Button(this.t('通知偏好')).enabled(!this.busy).onClick(this.onNotifications)
        this.row(this.t("读取屏幕"), this.t(this.state.capture ? '每次由你授权' : '当前系统不支持'), this.onPhone)
        Text(this.t('文件和照片由系统选择器按次授权，无需读取整个存储空间。')).fontSize(14).fontColor(this.colors.muted)
        if (!this.backgroundPage) Button(this.t('打开应用系统设置')).enabled(!this.busy).onClick(() => { void this.request('settings') })
        Button(this.t('刷新状态')).enabled(!this.busy).onClick(() => { void this.refresh() })
        if (this.error) Text(this.t(this.error)).fontColor(this.colors.danger)
      }.width('100%') }.layoutWeight(1).width('100%')
    }.padding(16).width('100%').height('100%').backgroundColor(this.colors.background)
  }
}
