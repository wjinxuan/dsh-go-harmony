import { localizedSettingsText } from './SettingsLocale'
import { common } from '@kit.AbilityKit'
import { DshClient } from '../dsh/DshClient'
import { object, string } from '../dsh/DshWire'
import type { DshSessionDetail, WireObject } from '../dsh/DshWire'
import { DshGlyphs, ThemeColors, themeColors } from './DshTheme'
import { QuickPanelPreferences, QUICK_DESTINATIONS, QuickDestination, quickPanelPreferences,
  quickDestinationTitle, moveQuickDestination } from './ShellNavigationData'
import { loadQuickPanelPreferences, saveQuickPanelPreferences } from './QuickPanelPreferences'

@Component
export struct QuickPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  @Prop @Watch('sessionChanged') sessionId: string = ''
  @Prop title: string = ''
  @Prop cwd: string = ''
  @Prop model: string = ''
  @Prop pluginPanels: WireObject[] = []
  client: DshClient = new DshClient()
  onClose: () => void = () => {}
  onOpen: (destination: string) => void = () => {}
  onSessionDetail: () => void = () => {}
  onPlugin: (id: string) => void = () => {}
  onPreferencesChange: (preferences: QuickPanelPreferences) => void = () => {}
  @State private preferences: QuickPanelPreferences = quickPanelPreferences()
  @State private configuring: boolean = false
  @State private section: string = 'info'
  @State private loading: boolean = false
  @State private saving: boolean = false
  @State private preferencesLoaded: boolean = false
  @State private error: string = ''
  @State private detail: DshSessionDetail | undefined = undefined
  private active: boolean = false
  private generation: number = 0

  aboutToAppear(): void {
    this.active = true
    const context = this.getUIContext().getHostContext() as common.Context | undefined
    if (context) void loadQuickPanelPreferences(context).then((value: QuickPanelPreferences) => {
      if (this.active) { this.preferences = value; this.preferencesLoaded = true; this.onPreferencesChange(value) }
    })
    this.sessionChanged()
  }

  aboutToDisappear(): void { this.active = false; this.generation++ }

  private sessionChanged(): void { this.detail = undefined; if (this.active && this.sessionId) void this.load() }

  private async load(): Promise<void> {
    const generation = ++this.generation, connection = this.client.connectionIdentity()
    this.loading = true; this.error = ''
    try {
      const detail = await this.client.sessionDetail(this.sessionId)
      if (this.active && generation === this.generation && connection === this.client.connectionIdentity()) this.detail = detail
    } catch { if (this.active && generation === this.generation) this.error = this.t("对话信息未能读取，请重试。") }
    finally { if (this.active && generation === this.generation) this.loading = false }
  }

  private async save(value: QuickPanelPreferences): Promise<void> {
    if (!this.active || this.saving || !this.preferencesLoaded) return
    if (value.swipe === this.preferences.swipe && value.items.length === this.preferences.items.length &&
      value.items.every((id: string, index: number) => id === this.preferences.items[index])) return
    const context = this.getUIContext().getHostContext() as common.Context | undefined
    if (!context) return
    this.saving = true; this.error = ''
    try {
      await saveQuickPanelPreferences(context, value)
      if (this.active) { this.preferences = value; this.onPreferencesChange(value) }
    } catch { if (this.active) this.error = this.t("快捷入口设置未能保存，请重试。") }
    finally { if (this.active) this.saving = false }
  }

  private toggleDestination(id: string, selected: boolean): void {
    if (this.preferences.items.includes(id) === selected) return
    const items = selected ? this.preferences.items.concat(id) : this.preferences.items.filter((value: string) => value !== id)
    void this.save({ swipe: this.preferences.swipe, items: items })
  }

  private moveDestination(id: string, direction: number): void {
    void this.save({ swipe: this.preferences.swipe, items: moveQuickDestination(this.preferences.items, id, direction) })
  }

  private metric(group: string, field: string): string {
    const value = object(this.detail?.projections?.values[group])[field]
    return typeof value === 'number' ? `${value}` : '—'
  }

  @Builder
  private information(title: string, value: () => string) {
    Column({ space: 4 }) {
      Text(title).fontSize(12).fontColor(this.colors.muted)
      Text(value() || '—').fontSize(14).fontColor(this.colors.text).textOverflow({ overflow: TextOverflow.Ellipsis }).maxLines(3)
    }.width('100%').alignItems(HorizontalAlign.Start).padding(12).backgroundColor(this.colors.surface).borderRadius(12)
  }

  @Builder
  private configure() {
    Row({ space: 10 }) {
      Text(this.t("左滑打开快捷面板")).fontColor(this.colors.text).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.preferences.swipe }).enabled(!this.saving)
        .onChange((value: boolean) => { void this.save({ swipe: value, items: this.preferences.items }) })
    }.width('100%')
    Text(this.t("勾选要显示的入口；用上移、下移调整顺序。")).fontSize(13).fontColor(this.colors.muted)
    ForEach(QUICK_DESTINATIONS, (destination: QuickDestination) => {
      Row({ space: 8 }) {
        Checkbox({ name: destination.id }).select(this.preferences.items.includes(destination.id)).enabled(!this.saving)
          .onChange((selected: boolean) => this.toggleDestination(destination.id, selected))
        Text(this.t(destination.title)).fontColor(this.colors.text).layoutWeight(1)
      }.width('100%')
    }, (destination: QuickDestination) => destination.id)
    ForEach(this.preferences.items, (id: string, index: number) => {
      Row({ space: 8 }) {
        Text(this.t(quickDestinationTitle(id))).fontSize(14).fontColor(this.colors.text).layoutWeight(1)
        Button(this.t("上移")).fontSize(12).enabled(!this.saving && index > 0).onClick(() => this.moveDestination(id, -1))
        Button(this.t("下移")).fontSize(12).enabled(!this.saving && index < this.preferences.items.length - 1).onClick(() => this.moveDestination(id, 1))
      }.width('100%')
    }, (id: string) => id)
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(this.configuring ? this.t("设置快捷入口") : this.t("快捷面板")).fontSize(20).fontColor(this.colors.text).layoutWeight(1)
        Button(this.configuring ? this.t("完成") : this.t("设置")).fontSize(13).onClick(() => { this.configuring = !this.configuring })
        Button(DshGlyphs.close).fontFamily(DshGlyphs.family).backgroundColor(Color.Transparent)
          .fontColor(this.colors.text).accessibilityText(this.t("关闭快捷面板")).onClick(this.onClose)
      }.width('100%')
      Scroll() {
        Column({ space: 10 }) {
          if (this.configuring) this.configure()
          else if (this.sessionId) {
            Row({ space: 8 }) {
              Button(this.t("信息")).fontColor(this.section === 'info' ? this.colors.primary : this.colors.muted).onClick(() => { this.section = 'info' })
              Button(this.t("插件")).fontColor(this.section === 'plugins' ? this.colors.primary : this.colors.muted).onClick(() => { this.section = 'plugins' })
              Blank()
              Button(this.t("详情")).onClick(this.onSessionDetail)
            }.width('100%')
            if (this.section === 'info') {
              this.information(this.t("对话"), () => this.title || this.t("未命名对话"))
              this.information(this.t("工作目录"), () => this.cwd)
              this.information(this.t("模型"), () => this.model)
              if (this.loading) LoadingProgress().width(28).height(28)
              else if (this.detail) {
                this.information(this.t("智能体"), () => this.detail?.projections?.agentPreset || '')
                this.information(this.t("权限"), () => this.detail?.projections?.permissionPreset || '')
                this.information(this.t("输入 / 输出 Token"), () => `${this.metric('tokenUsage', 'uncachedInputTokens')} / ${this.metric('tokenUsage', 'outputTokens')}`)
                this.information(this.t("上下文占用 / 窗口"), () => `${this.metric('contextPressure', 'projectedTokens')} / ${this.metric('contextPressure', 'contextWindow')}`)
                this.information(this.t("回合"), () => this.metric('sessionStats', 'turns'))
              }
            } else if (this.pluginPanels.length) {
              ForEach(this.pluginPanels, (panel: WireObject) => {
                Button(string(panel['title']) || string(panel['id'])).width('100%').onClick(() => this.onPlugin(string(panel['id'])))
              }, (panel: WireObject) => string(panel['id']))
            } else {
              Text(this.t("当前对话没有可显示的插件面板")).fontColor(this.colors.muted).padding(20)
              Button(this.t("浏览插件")).onClick(() => this.onOpen('plugins'))
            }
          }
          if (this.error) {
            Text(this.t(this.error)).fontColor(this.colors.danger)
            if (!this.configuring) Button(this.t("重试")).enabled(!this.loading).onClick(() => { void this.load() })
          }
          if (!this.configuring) {
            ForEach(this.preferences.items, (id: string) => {
              Button(this.t(quickDestinationTitle(id))).width('100%').fontColor(this.colors.text).backgroundColor(this.colors.surface)
                .onClick(() => this.onOpen(id))
            }, (id: string) => id)
            if (!this.preferences.items.length) Text(this.t("还没有快捷入口，可在右上角设置中添加。")).fontColor(this.colors.muted)
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1)
    }.padding(16).width('100%').height('100%').backgroundColor(this.colors.background)
  }
}
