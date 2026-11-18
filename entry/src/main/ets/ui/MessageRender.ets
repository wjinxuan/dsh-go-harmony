import { localizedSettingsText } from './SettingsLocale'
import { webview } from '@kit.ArkWeb'
import { InlineKind, InlineRun, isMessageLink, parseInline } from './MarkdownBlocks'
import { isDarkSurface } from './AnsiData'
import { ThemeColors, themeColors } from './DshTheme'

class RenderBridge {
  onHeight: (height: number, revision: number) => void = () => {}
  onStatus: (value: string, revision: number) => void = () => {}
  onLink: (value: string, revision: number) => void = () => {}
  height(value: number, revision: number): void { this.onHeight(value, revision) }
  status(value: string, revision: number): void { this.onStatus(value, revision) }
  link(value: string, revision: number): void { this.onLink(value, revision) }
}

interface RenderRun { text: string; kind: string; url: string }
interface RenderOptions { size: number; color: string; accent: string; code: string; bold: boolean; display: boolean }
function scriptValue(value: Object): string { return JSON.stringify(value).replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029') }

@Component
export struct MessageRender {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop @Watch('refresh') text: string = ''
  @Prop diagram: boolean = false
  @Prop display: boolean = false
  @Prop @Watch('refresh') colors: ThemeColors = themeColors()
  @Prop @Watch('refresh') fontSize: number = 15
  @Prop @Watch('refresh') bold: boolean = false
  @Prop @Watch('refresh') textColor: string = ''
  onOpenLink?: (url: string) => void
  @State private measuredHeight: number = 30
  @State private problem: string = ''
  @State private ready: boolean = false
  private controller: webview.WebviewController = new webview.WebviewController()
  private bridge: RenderBridge = new RenderBridge()
  private revision: number = 0
  private active: boolean = false
  private loaded: boolean = false
  private scripts: Promise<void> = Promise.resolve()

  aboutToAppear(): void {
    this.active = true
    this.bridge.onHeight = (height: number, revision: number): void => {
      if (this.active && revision === this.revision && Number.isFinite(height)) this.measuredHeight = Math.max(20, height)
    }
    this.bridge.onStatus = (value: string, revision: number): void => {
      if (!this.active || revision !== this.revision) return
      this.ready = value === 'ready'; this.problem = value === 'syntax' ? this.t("图表语法有误，请检查源码。") : ''
    }
    this.bridge.onLink = (value: string, revision: number): void => {
      if (this.active && revision === this.revision && isMessageLink(value)) this.onOpenLink?.(value)
    }
  }

  aboutToDisappear(): void {
    this.active = false; this.revision++
    try { this.controller.deleteJavaScriptRegister('renderBridge') } catch { /* The renderer may have exited. */ }
  }

  private address(): string { return this.diagram ? 'resource://rawfile/render/mermaid.html' : 'resource://rawfile/render/math.html' }

  private refresh(): void {
    const revision = ++this.revision
    if (!this.loaded || !this.active) return
    this.problem = ''; this.ready = !this.diagram
    let script: string
    if (this.diagram) {
      script = `window.renderDiagram(${scriptValue(this.text)},${isDarkSurface(this.colors.surface)},${scriptValue(this.colors.surface)},${scriptValue(this.colors.text)},${revision})`
    } else {
      const runs: RenderRun[] = this.display ? [{ text: this.text, kind: 'math', url: '' }] :
        parseInline(this.text).map((run: InlineRun): RenderRun => ({ text: run.text, url: run.url,
          kind: run.kind === InlineKind.Math ? 'math' : run.kind === InlineKind.Link ? 'link' :
            run.kind === InlineKind.Code ? 'code' : run.kind === InlineKind.Strong ? 'strong' :
              run.kind === InlineKind.Emphasis ? 'emphasis' : 'text' }))
      const options: RenderOptions = { size: this.fontSize, color: this.textColor || this.colors.text,
        accent: this.colors.primary, code: this.colors.codeSurface, bold: this.bold, display: this.display }
      script = `window.renderMath(${scriptValue(runs)},${scriptValue(options)},${revision})`
    }
    this.scripts = this.scripts.catch(() => {}).then(async (): Promise<void> => {
      if (!this.active || revision !== this.revision) return
      try { await this.controller.runJavaScript(script) }
      catch { if (this.active && revision === this.revision) this.problem = this.t("显示已退出，请重新打开。") }
    })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Web({ src: this.address(), controller: this.controller })
        .width('100%').height('100%').backgroundColor(Color.Transparent)
        .javaScriptAccess(true).fileAccess(false).blockNetwork(true).domStorageAccess(false)
        .multiWindowAccess(false).zoomAccess(this.diagram).onlineImageAccess(false).mixedMode(MixedMode.None)
        .onOverrideUrlLoading((request: WebResourceRequest): boolean => request.getRequestUrl() !== this.address())
        .javaScriptProxy({ object: this.bridge, name: 'renderBridge', methodList: ['height', 'status', 'link'], controller: this.controller })
        .onPageEnd((event: OnPageEndEvent): void => { if (event.url === this.address()) { this.loaded = true; this.refresh() } })
        .onRenderExited(() => { this.loaded = false; this.problem = this.t("显示已退出，请重新打开。") })
      if (this.problem) Text(this.problem).fontSize(14).fontColor(this.colors.muted).backgroundColor(this.colors.surface).padding(16)
      else if (this.diagram && !this.ready) LoadingProgress().width(24).height(24).color(this.colors.primary)
    }.width('100%').height(this.diagram ? '100%' : this.measuredHeight)
  }
}
