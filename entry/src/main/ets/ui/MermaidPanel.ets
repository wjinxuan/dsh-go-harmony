import { localizedSettingsText } from './SettingsLocale'
import { pasteboard } from '@kit.BasicServicesKit'
import { window } from '@kit.ArkUI'
import { DshGlyphs, ThemeColors, themeColors } from './DshTheme'
import { MessageRender } from './MessageRender'

@Component
export struct MermaidPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop text: string = ''
  @Prop colors: ThemeColors = themeColors()
  onClose: () => void = () => {}
  @State private safeInsets: Padding = { top: 0, right: 0, bottom: 0, left: 0 }
  private targetWindow: window.Window | undefined = undefined
  private avoidChanged: (options: window.AvoidAreaOptions) => void = (_options: window.AvoidAreaOptions): void => {
    this.updateSafeInsets()
  }

  aboutToAppear(): void {
    try {
      const name = this.getUIContext().getWindowName()
      if (!name) return
      this.targetWindow = window.findWindow(name)
      this.updateSafeInsets()
      this.targetWindow.on('avoidAreaChange', this.avoidChanged)
    } catch { /* The window may already be closing. */ }
  }

  aboutToDisappear(): void {
    try { this.targetWindow?.off('avoidAreaChange', this.avoidChanged) } catch { /* The window may have closed. */ }
    this.targetWindow = undefined
  }

  private updateSafeInsets(): void {
    const target = this.targetWindow
    if (!target) return
    let top = 0; let right = 0; let bottom = 0; let left = 0
    for (const type of [window.AvoidAreaType.TYPE_SYSTEM, window.AvoidAreaType.TYPE_CUTOUT,
      window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR]) {
      try {
        const area = target.getWindowAvoidArea(type)
        top = Math.max(top, area.topRect.height); right = Math.max(right, area.rightRect.width)
        bottom = Math.max(bottom, area.bottomRect.height); left = Math.max(left, area.leftRect.width)
      } catch { /* Some window types do not expose every avoid-area category. */ }
    }
    const ui = this.getUIContext()
    this.safeInsets = { top: ui.px2vp(top), right: ui.px2vp(right), bottom: ui.px2vp(bottom), left: ui.px2vp(left) }
  }

  private async copy(): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.text))
      this.getUIContext().getPromptAction().showToast({ message: this.t("已复制代码") })
    } catch { this.getUIContext().getPromptAction().showToast({ message: this.t("无法复制代码") }) }
  }
  build() {
    Column() {
      Row({ space: 12 }) {
        Button(this.t("返回")).onClick(this.onClose).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
        Text(this.t("图表预览")).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.colors.text).layoutWeight(1)
        Button({ type: ButtonType.Circle }) { Text(DshGlyphs.copy).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.text) }
          .width(44).height(44).backgroundColor(this.colors.surfaceAlt).accessibilityText(this.t("复制代码")).onClick(() => { void this.copy() })
      }.height(56).padding({ left: 12, right: 12 }).width('100%')
      Column() { MessageRender({ text: this.text, colors: this.colors, diagram: true }) }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').safeAreaPadding(this.safeInsets).backgroundColor(this.colors.surface)
  }
}
