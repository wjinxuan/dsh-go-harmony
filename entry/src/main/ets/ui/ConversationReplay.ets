import { localizedSettingsText } from './SettingsLocale'
import { webview } from '@kit.ArkWeb'
import { ThemeColors, themeColors } from './DshTheme'

@Component
export struct ConversationReplay {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  @Prop html: string = ''
  onClose: () => void = () => {}
  private controller: webview.WebviewController = new webview.WebviewController()
  @State private error: string = ''
  private active: boolean = false
  private started: boolean = false

  aboutToAppear(): void {
    this.active = true
    this.started = false
  }

  aboutToDisappear(): void {
    this.active = false
  }

  build() {
    Column() {
      Row() {
        Button(this.t("返回")).onClick(this.onClose).fontColor(this.colors.primary).backgroundColor(Color.Transparent)
        Text(this.t("会话回放")).fontSize(20).fontColor(this.colors.text).layoutWeight(1)
      }.width('100%').padding(12)
      if (this.error) Text(this.t(this.error)).fontColor(this.colors.danger).padding(16)
      Web({ src: 'about:blank', controller: this.controller }).layoutWeight(1).width('100%')
        .javaScriptAccess(true).fileAccess(false).blockNetwork(true).domStorageAccess(false)
        .multiWindowAccess(false).onlineImageAccess(false).mixedMode(MixedMode.None)
        .onPageEnd((event: OnPageEndEvent): void => {
          // The initial Web.src navigation must finish before loading the replay.
          if (!this.active || this.started || event.url !== 'about:blank') return
          this.started = true
          try { this.controller.loadData(this.html, 'text/html', 'UTF-8', 'https://dsh-replay.invalid/') }
          catch { this.error = this.t("回放页面未能加载") }
        })
        .onOverrideUrlLoading((request: WebResourceRequest): boolean => !['about:blank', 'https://dsh-replay.invalid/'].includes(request.getRequestUrl()))
        .onRenderExited(() => { this.error = this.t("回放页面已退出，请返回后重新打开。") })
    }.width('100%').height('100%').backgroundColor(this.colors.background)
  }
}
