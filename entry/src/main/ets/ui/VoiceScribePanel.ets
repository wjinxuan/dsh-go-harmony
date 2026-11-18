import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { DshClient, DshSubscription } from '../dsh/DshClient'
import { url } from '@kit.ArkTS'
import { string, WireObject } from '../dsh/DshWire'
import { VoiceScribeController, VoiceScribeField, VoiceScribeProvider, VoiceScribeTransport } from './VoiceScribeData'
import { DshGlyphs, ThemeColors, themeColors } from './DshTheme'

@Component
export struct VoiceScribePanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  @Prop @Watch('sourceChanged') scope: string = ''
  @Prop @Watch('sourceChanged') connected: boolean = false
  @Prop relay: boolean = false
  entryId: string = ''
  client: DshClient = new DshClient()
  onClose: () => void = () => {}
  onBackHandler?: (handler: (() => boolean) | undefined) => void
  @State private ready: boolean = false
  @State private sourceLost: boolean = false
  @State private loading: boolean = false
  @State private saving: boolean = false
  @State private error: string = ''
  @State private language: string = ''
  @State private polishPrompt: string = ''
  @State private providers: VoiceScribeProvider[] = []
  @State private hotwordsPath: string = ''
  @State private hotwordsRules: number = 0
  @State private hotwordsError: string = ''
  @State private editing: string = ''
  @State private draft: string = ''
  private active: boolean = false
  private connection: number = 0
  private sourceScope: string = ''
  private editorGeneration: number = 0
  private controller?: VoiceScribeController
  private stop?: DshSubscription

  aboutToAppear(): void {
    this.active = true; this.connection = this.client.connectionIdentity(); this.sourceScope = this.scope
    const transport: VoiceScribeTransport = {
      inventory: (): Promise<WireObject> => this.client.pluginInventory(),
      request: (body: WireObject): Promise<WireObject> => this.client.voiceScribeRequest(body)
    }
    this.controller = new VoiceScribeController(this.entryId, transport, () => this.current())
    this.controller.onChange = () => this.sync()
    this.onBackHandler?.(() => this.back())
    this.stop = this.client.onHostEvent((event: WireObject) => {
      const name = string(event['event'])
      if (/plugin.*chang/i.test(name) || /plugin.*chang/i.test(string(event['type']))) {
        this.controller?.invalidate(); this.editing = ''; void this.controller?.refresh()
      }
    })
    if (!this.relay && this.connected) void this.controller.refresh()
  }

  aboutToDisappear(): void {
    this.active = false; this.stop?.(); this.controller?.dispose(); this.onBackHandler?.(undefined)
  }

  private current(): boolean {
    return this.active && this.connected && !this.relay && !this.sourceLost && this.scope === this.sourceScope &&
      this.client.connectionIdentity() === this.connection
  }

  private sourceChanged(): void {
    if (this.active && (!this.connected || this.scope !== this.sourceScope || this.client.connectionIdentity() !== this.connection)) {
      this.sourceLost = true; this.editing = ''; this.controller?.invalidate()
    }
  }

  private sync(): void {
    const controller = this.controller
    if (!this.active || !controller) return
    this.loading = controller.loading; this.saving = controller.saving; this.error = controller.error
    const data = controller.data; this.ready = data !== undefined
    if (data) {
      this.language = data.language; this.polishPrompt = data.polishPrompt; this.providers = data.providers.slice()
      this.hotwordsPath = data.hotwordsPath; this.hotwordsRules = data.hotwordsRules; this.hotwordsError = data.hotwordsError
    }
  }

  private edit(field: VoiceScribeField): void {
    if (!this.current() || this.loading || this.saving || !this.controller?.data) return
    this.editing = field; this.draft = field === 'language' ? this.language : this.polishPrompt
    this.editorGeneration = this.controller.generation
  }

  private back(): boolean {
    if (!this.editing) return false
    if (this.saving) return true
    const original = this.editing === 'language' ? this.language : this.polishPrompt
    if (this.draft === original) this.editing = ''
    else this.getUIContext().showAlertDialog({ title: this.t("放弃更改？"), message: this.t("语音速记设置尚未保存。"),
      primaryButton: { value: this.t("继续编辑"), action: () => {} },
      secondaryButton: { value: this.t("放弃"), action: () => { this.editing = '' } } })
    return true
  }

  private async save(reset: boolean = false): Promise<void> {
    if (!this.controller || !this.editing || !this.current()) return
    if (await this.controller.save(this.editorGeneration, this.editing as VoiceScribeField, reset ? '' : this.draft)) this.editing = ''
  }

  private providerHost(value: string): string {
    try { return url.URL.parseURL(value).hostname || value } catch { return value }
  }

  @Builder
  private field(title: string, value: () => string, field: VoiceScribeField) {
    Row({ space: 12 }) {
      Column({ space: 6 }) {
        Text(title).fontSize(16).fontColor(this.colors.text)
        Text(value()).fontSize(14).fontColor(this.colors.muted).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text(DshGlyphs.disclosure).fontFamily(DshGlyphs.family).fontColor(this.colors.muted)
    }.width('100%').padding(16).backgroundColor(this.colors.surface).borderRadius(14)
      .enabled(this.current() && !this.loading && !this.saving).onClick(() => this.edit(field))
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Button(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(21).fontColor(this.colors.text)
          .backgroundColor(Color.Transparent).accessibilityText(this.t("返回")).onClick(() => { if (!this.back()) this.onClose() })
        Text(this.editing ? (this.editing === 'language' ? this.t("识别语言") : this.t("润色提示词")) : this.t("语音速记")).fontSize(22)
          .fontColor(this.colors.text).layoutWeight(1)
        if (!this.editing && !this.relay && !this.sourceLost) {
          Button(DshGlyphs.refresh).fontFamily(DshGlyphs.family).fontColor(this.colors.primary)
            .backgroundColor(Color.Transparent).accessibilityText(this.t("刷新语音速记设置"))
            .enabled(!this.loading && !this.saving && this.connected).onClick(() => { void this.controller?.refresh() })
        }
      }.width('100%').padding(12)
      Scroll() {
        Column({ space: 12 }) {
          if (this.sourceLost) Text(this.t("主机连接已变更，请关闭此页后重新打开。")).fontColor(this.colors.warning)
          else if (this.relay) Text(this.t("中继连接暂不支持语音速记设置。")).fontColor(this.colors.muted)
          else if (!this.connected) Text(this.t("连接主机后查看语音速记设置。")).fontColor(this.colors.muted)
          else if (this.editing) {
            if (this.editing === 'polishPrompt') {
              TextArea({ text: this.draft, placeholder: this.t("留空使用内置提示词") }).height(280).maxLength(8000)
                .fontColor(this.colors.text).backgroundColor(this.colors.surface).onChange((value: string) => { this.draft = value })
            } else {
              TextInput({ text: this.draft, placeholder: this.t("留空使用插件默认语言") }).fontColor(this.colors.text)
                .backgroundColor(this.colors.surface).onChange((value: string) => { this.draft = value })
            }
            Button(this.saving ? this.t("保存中…") : this.t("保存")).width('100%').enabled(!this.saving && this.current())
              .backgroundColor(this.colors.primary).fontColor(this.colors.onPrimary).onClick(() => { void this.save() })
            Button(this.t("恢复默认")).width('100%').enabled(!this.saving && this.current()).onClick(() => { void this.save(true) })
          } else if (this.loading && !this.ready) LoadingProgress().width(32).height(32)
          else if (this.ready) {
            this.field(this.t("识别语言"), () => this.language || this.t("插件默认"), 'language')
            this.field(this.t("润色提示词"), () => this.polishPrompt || this.t("内置提示词"), 'polishPrompt')
            if (this.providers.length) {
              Text(this.t("转写服务")).fontSize(14).fontColor(this.colors.muted).width('100%')
              ForEach(this.providers, (provider: VoiceScribeProvider, index: number) => {
                Column({ space: 6 }) {
                  Text(provider.model).fontSize(16).fontColor(this.colors.text)
                  Text(`${this.providerHost(provider.url)} · ${provider.hasKey ? this.t("密钥已设置") : this.t("未设置密钥")}`)
                    .fontSize(13).fontColor(this.colors.muted)
                }.width('100%').alignItems(HorizontalAlign.Start).padding(16).backgroundColor(this.colors.surface).borderRadius(14)
              }, (_provider: VoiceScribeProvider, index: number) => `${index}`)
            }
            Text(this.t("热词")).fontSize(14).fontColor(this.colors.muted).width('100%')
            Column({ space: 6 }) {
              Text(this.f("{0} 条热词规则", [this.hotwordsRules])).fontColor(this.colors.text)
              if (this.hotwordsError || this.hotwordsPath) Text(this.hotwordsError || this.hotwordsPath)
                .fontSize(13).fontColor(this.hotwordsError ? this.colors.danger : this.colors.muted)
            }.width('100%').alignItems(HorizontalAlign.Start).padding(16).backgroundColor(this.colors.surface).borderRadius(14)
          }
          if (this.error) {
            Text(this.t(this.error)).fontColor(this.colors.danger).width('100%')
            if (!this.ready && !this.sourceLost) Button(this.t("重试")).enabled(!this.loading).onClick(() => { void this.controller?.refresh() })
          }
        }.width('100%').padding(16).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor(this.colors.background)
  }
}
