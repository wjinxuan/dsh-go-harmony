import { localizedSettingsText } from './SettingsLocale'
import { DshClient } from '../dsh/DshClient'
import { string } from '../dsh/DshWire'
import { CotTranslationHolder, CotTranslationLimits, ReasoningTranslation, cotTranslationLimits,
  reasoningNeedsTranslation, reasoningTranslationRequest } from './CotTranslationData'
import { ThemeColors, themeColors } from './DshTheme'
import { MessageBody } from './MessageBody'

@Component
export struct CotReasoning {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop @Watch('sourceChanged') text: string = ''
  @Prop @Watch('sourceChanged') running: boolean = false
  @Prop @Watch('opened') expanded: boolean = true
  @Prop @Watch('reset') sessionId: string = ''
  @Prop @Watch('reset') scope: string = ''
  @Prop @Watch('reset') uiLanguage: string = 'zh'
  @Prop colors: ThemeColors = themeColors()
  @Prop fontSize: number = 14
  client: DshClient = new DshClient()
  holder: CotTranslationHolder = new CotTranslationHolder()
  onOpenSettings?: () => void
  @State private translated: string = ''
  @State private pending: boolean = false
  @State private failed: boolean = false
  @State private showing: boolean = false
  @State private started: boolean = false
  @State private offered: boolean = false
  private limits?: CotTranslationLimits
  private active: boolean = false
  private generation: number = 0

  aboutToAppear(): void {
    this.active = true; this.listen(); this.sourceChanged(); this.opened()
  }

  aboutToDisappear(): void {
    this.active = false; this.generation++
    if (this.holder.controller) this.holder.controller.onChange = () => {}
  }

  private listen(): void {
    if (this.holder.controller) this.holder.controller.onChange = () => this.sync()
    this.sync()
  }

  private sync(): void {
    if (!this.active) return
    const controller = this.holder.controller
    this.started = !!controller; this.pending = controller?.pending ?? false; this.failed = controller?.failed ?? false
    this.translated = controller?.text ?? ''; this.showing = this.holder.showTranslation && !this.failed
  }

  private sourceChanged(): void {
    this.holder.controller?.update(this.text, this.running)
    this.offer()
  }

  private offer(): void {
    const limits = this.limits
    this.offered = !!limits?.usable && reasoningNeedsTranslation(this.text,
      limits.targetLanguage === 'auto' ? this.uiLanguage : limits.targetLanguage)
  }

  private reset(): void {
    if (!this.active) return
    this.holder.reset(); this.limits = undefined; this.offered = false; this.sync(); this.opened()
  }

  private opened(): void { if (this.active && this.expanded) void this.load() }

  private async load(): Promise<void> {
    const generation = ++this.generation, connection = this.client.connectionIdentity()
    try {
      const limits = cotTranslationLimits(await this.client.request('cotTranslation/limits'))
      if (!this.active || generation !== this.generation || connection !== this.client.connectionIdentity()) return
      this.limits = limits
      const signature = `${connection}|${this.sessionId}|${this.uiLanguage}|${limits.provider}|${limits.targetLanguage}`
      if (this.holder.signature && this.holder.signature !== signature) this.holder.reset()
      this.holder.signature = signature; this.listen(); this.offer()
    } catch {
      if (this.active && generation === this.generation) { this.limits = undefined; this.offered = false }
    }
  }

  private startTranslation(): void {
    const limits = this.limits
    if (!limits?.usable || !this.offered) return
    const connection = this.client.connectionIdentity(), sessionId = this.sessionId, language = this.uiLanguage
    if (!this.holder.controller) {
      this.holder.controller = new ReasoningTranslation(limits.maxTextChars, async (source: string): Promise<string> => {
        if (connection !== this.client.connectionIdentity()) throw new Error(this.t("主机连接已变更"))
        const result = string(await this.client.request('cotTranslation/translate',
          reasoningTranslationRequest(source, limits, language, sessionId), 120000))
        if (connection !== this.client.connectionIdentity()) throw new Error(this.t("主机连接已变更"))
        return result
      })
    }
    this.holder.showTranslation = true; this.listen(); this.sourceChanged()
  }

  private toggle(): void { this.holder.showTranslation = !this.holder.showTranslation; this.sync() }

  build() {
    Column({ space: 6 }) {
      if (this.expanded) {
        if (this.started || this.offered) {
          Row({ space: 10 }) {
            if (this.failed) {
              Text(this.t("暂时无法翻译")).fontSize(12).fontColor(this.colors.muted)
              Button(this.t("重试")).fontSize(12).height(28).fontColor(this.colors.muted).backgroundColor(this.colors.surfaceAlt)
                .onClick(() => this.holder.controller?.retry())
            } else {
              Button(this.started ? (this.showing ? this.t("查看原文") : this.t("查看译文")) : this.t("翻译"))
                .fontSize(12).height(28).fontColor(this.colors.muted).backgroundColor(this.colors.surfaceAlt)
                .onClick(() => { if (this.started) this.toggle(); else this.startTranslation() })
                .gesture(LongPressGesture().onAction(() => this.onOpenSettings?.()))
            }
            if (this.pending && !this.failed) LoadingProgress().width(14).height(14).accessibilityText(this.t("正在翻译"))
          }.width('100%')
        }
        MessageBody({ text: this.showing ? this.translated : this.text, colors: this.colors, fontSize: this.fontSize, streaming: this.running })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
