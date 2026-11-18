import { localizedSettingsText } from './SettingsLocale'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { DshClient } from '../dsh/DshClient'
import { array, object, string, number, DshModelInfo, WireObject } from '../dsh/DshWire'
import { DshGlyphs, ThemeColors, themeColors } from './DshTheme'
import { SubscriptionLogin, SubscriptionStatus, SubscriptionStep, subscriptionStatuses, subscriptionStep,
  subscriptionBrowserUrl } from './SubscriptionData'
import { CONTEXT_PRESETS, modelTokenText, subscriptionContextOps } from './settings/ProviderModelData'

@Component
export struct SubscriptionsPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  client: DshClient = new DshClient()
  @Prop colors: ThemeColors = themeColors()
  @Prop @Watch('connectionChanged') connectionIdentity: number = 0
  onClose: () => void = () => {}
  onChanged: () => void = () => {}
  onBackHandler?: (handler: (() => boolean) | undefined) => void
  @State private providers: SubscriptionStatus[] = []
  @State private loading: boolean = true
  @State private busy: boolean = false
  @State private error: string = ''
  @State private selected: string = ''
  @State private loginProvider: string = ''
  @State private step: SubscriptionStep = subscriptionStep({ 'phase': 'starting' } as WireObject)
  @State private answerText: string = ''
  @State private answering: boolean = false
  @State private models: DshModelInfo[] = []
  @State private modelId: string = ''
  @State private contextText: string = ''
  @State private overrides: WireObject = {}
  @State private writable: boolean = false
  private revision: number = 0
  private login?: SubscriptionLogin
  private active: boolean = false
  private generation: number = 0
  private source: number = -1
  private opened: string = ''

  aboutToAppear(): void { this.active = true; this.source = this.client.connectionIdentity(); this.onBackHandler?.(() => this.back()); void this.refresh() }
  aboutToDisappear(): void { this.active = false; this.generation++; void this.login?.close().catch(() => {}); this.onBackHandler?.(undefined) }
  private connectionChanged(): void {
    if (!this.active || this.source === this.client.connectionIdentity()) return
    this.generation++; void this.login?.close().catch(() => {}); this.login = undefined
    this.error = this.t('主机连接已更改，请重新打开订阅。'); this.busy = true; this.loading = false
  }
  private current(generation: number): boolean { return this.active && generation === this.generation && this.source === this.client.connectionIdentity() }
  private back(): boolean {
    if (this.busy) return true
    if (this.loginProvider) { void this.closeLogin(); return true }
    if (this.modelId) { this.modelId = ''; this.error = ''; return true }
    if (this.selected) { this.selected = ''; this.models = []; this.error = ''; return true }
    return false
  }
  private async refresh(): Promise<void> {
    const generation = ++this.generation; this.loading = true; this.error = ''
    try {
      const list = subscriptionStatuses(await this.client.request('appAuth/list'))
      if (this.current(generation)) this.providers = list
    } catch { if (this.current(generation)) this.error = this.t('无法读取订阅，请检查主机是否支持订阅登录。') }
    finally { if (this.current(generation)) this.loading = false }
  }
  private async openUrl(value: string): Promise<void> {
    const address = subscriptionBrowserUrl(value), generation = this.generation
    if (!address || !this.current(generation)) return
    try { await (this.getUIContext().getHostContext() as common.UIAbilityContext).openLink(address) }
    catch { if (this.current(generation)) this.error = this.t('无法打开浏览器，可以重试或复制链接。') }
  }
  private async copy(value: string): Promise<void> {
    try { await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value)) }
    catch { this.error = this.t('未能复制，请重试。') }
  }
  private begin(provider: string): void {
    if (this.busy || !this.current(this.generation)) return
    void this.login?.close().catch(() => {})
    this.loginProvider = provider; this.answerText = ''; this.opened = ''; this.error = ''
    const connection = this.source
    const login = new SubscriptionLogin((method: string, args: WireObject) => this.client.request(method, args), provider,
      () => connection === this.client.connectionIdentity())
    this.login = login
    login.onChange = () => {
      if (!this.active || this.login !== login || !this.current(this.generation)) return
      this.step = login.step; this.answering = login.answering
      if (this.step.phase === 'open' && this.step.url && this.opened !== this.step.url) {
        this.opened = this.step.url; void this.openUrl(this.step.url)
      }
      if (this.step.phase === 'done') {
        this.onChanged()
        setTimeout(() => { if (this.active && this.login === login) void this.closeLogin() }, 900)
      }
    }
    void login.start()
  }
  private async closeLogin(): Promise<void> {
    const login = this.login; this.login = undefined; this.loginProvider = ''; this.answerText = ''
    try { await login?.close() } catch { this.error = this.t('取消未能确认，请刷新订阅状态。') }
    if (this.active && this.source === this.client.connectionIdentity()) await this.refresh()
  }
  private async submitAnswer(): Promise<void> { if (await this.login?.answer(this.answerText)) this.answerText = '' }
  private async details(provider: string): Promise<void> {
    this.selected = provider; this.loading = true; this.error = ''
    const generation = ++this.generation
    try {
      const catalog = await this.client.listModels(), settings = await this.client.describeSettings()
      if (!this.current(generation)) return
      this.models = catalog.groups.find(group => group.id === provider)?.models || []
      const ns = array(settings['namespaces']).map(object).find((row: WireObject) => row['ns'] === 'llm-pi-ai')
      const profile = object(object(object(ns?.['value'])['providers'])[provider])
      this.overrides = object(profile['modelOverrides']); this.revision = number(ns?.['revision'], 0)
      this.writable = ns !== undefined && settings['writable'] !== false && ns['writable'] !== false && Object.keys(profile).length > 0
    } catch { if (this.current(generation)) this.error = this.t('无法读取订阅模型，请重试。') }
    finally { if (this.current(generation)) this.loading = false }
  }
  private async saveContext(): Promise<void> {
    if (this.busy || !this.writable || !this.modelId) return
    const generation = this.generation, modelId = this.modelId, raw = this.contextText
    this.busy = true; this.error = ''
    try {
      const ops = subscriptionContextOps(this.selected, modelId, this.overrides, raw)
      await this.client.mutateSettings('llm-pi-ai', ops, this.revision)
      if (!this.current(generation)) return
      await this.details(this.selected)
      if (this.error) return
      const actual = object(this.overrides[modelId])['contextWindow']
      const expected = ops[0].op === 'set' ? object(ops[0].value)['contextWindow'] : undefined
      if (actual !== expected) throw new Error(this.t('主机读回的上下文长度与提交值不同。'))
      this.modelId = ''; this.onChanged()
    } catch (reason) { if (this.active) this.error = reason instanceof Error ? reason.message : this.t('无法保存模型上下文长度。') }
    finally { if (this.active) this.busy = false }
  }
  private signOut(provider: SubscriptionStatus): void {
    this.getUIContext().showAlertDialog({ title: `${this.t('退出登录')} ${provider.title}?`, message: this.t('移除此主机保存的订阅授权及渠道。'),
      primaryButton: { value: this.t('取消'), action: () => {} }, secondaryButton: { value: this.t('退出登录'), action: () => {
        const generation = this.generation; this.busy = true; this.error = ''
        this.client.request('appAuth/signOut', { 'provider': provider.id }).then(async () => {
          if (!this.current(generation)) return
          this.selected = ''; await this.refresh()
          if (this.providers.some((item: SubscriptionStatus) => item.id === provider.id && item.signedIn)) this.error = this.t('主机仍报告已登录，请重试。')
          this.onChanged()
        }).catch(() => { if (this.current(generation)) this.error = this.t('退出登录未完成，请重试。') })
          .finally(() => { if (this.active) this.busy = false })
      } } })
  }
  @Builder private button(label: string, action: () => void) {
    Button(label).width('100%').height(48).backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.text).enabled(!this.busy).onClick(action)
  }
  @Builder private loginBody() {
    Column({ space: 16 }) {
      Text(this.loginProvider === 'openai-codex' ? this.t('登录 ChatGPT') : this.t('登录 Claude')).fontSize(22).fontColor(this.colors.text)
      Text(this.t(this.step.message) || (this.step.phase === 'done' ? this.t('已登录') : this.step.phase === 'failed' ? this.t('登录未完成') : this.t('正在准备登录…')))
        .fontColor(this.colors.muted).textAlign(TextAlign.Center)
      if (this.step.phase === 'starting') { LoadingProgress().width(32).height(32) }
      if (this.step.phase === 'open' || this.step.phase === 'device') {
        if (this.step.userCode) { Text(this.step.userCode).fontSize(28).fontColor(this.colors.text).copyOption(CopyOptions.LocalDevice) }
        this.button(this.t('打开浏览器'), () => { void this.openUrl(this.step.url) })
        this.button(this.step.userCode ? this.t('复制代码') : this.t('复制链接'), () => { void this.copy(this.step.userCode || this.step.url) })
      }
      if (this.step.phase === 'prompt') {
        TextArea({ text: this.answerText, placeholder: this.step.placeholder || this.t('粘贴授权码或浏览器完整网址') })
          .height(120).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).enabled(!this.answering)
          .onChange((value: string) => this.answerText = value)
        Button(this.answering ? this.t('正在提交…') : this.t('继续')).width('100%').height(48).backgroundColor(this.colors.primary).fontColor(this.colors.onPrimary)
          .enabled(!this.answering && !!this.answerText.trim()).onClick(() => { void this.submitAnswer() })
      }
      if (this.step.phase === 'failed' || this.step.phase === 'cancelled') {
        Text(this.t(this.step.error) || this.t('登录已取消')).fontColor(this.colors.danger)
        this.button(this.t('重试'), () => { this.answerText = ''; this.opened = ''; this.error = ''; void this.login?.start() })
      }
      this.button(this.step.phase === 'done' ? this.t('完成') : this.t('取消'), () => { void this.closeLogin() })
    }.padding(24).width('100%').backgroundColor(this.colors.surface).borderRadius(28)
  }
  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Button({ type: ButtonType.Circle }) { Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text) }
          .width(44).height(44).backgroundColor(this.colors.surface).onClick(() => { if (!this.back()) this.onClose() })
        Text(this.modelId || (this.selected === 'openai-codex' ? 'ChatGPT' : this.selected === 'anthropic' ? 'Claude' : this.t('订阅')))
          .fontSize(22).fontColor(this.colors.text).layoutWeight(1)
      }.width('100%')
      if (this.error) { Text(this.t(this.error)).fontColor(this.colors.danger).width('100%') }
      if (this.loading) { LoadingProgress().width(32).height(32) }
      Scroll() {
        Column({ space: 14 }) {
          if (this.loginProvider) { this.loginBody() }
          else if (this.modelId) {
            Text(this.t('上下文长度')).fontSize(18).fontColor(this.colors.text)
            TextInput({ text: this.contextText, placeholder: this.t('默认（使用模型目录）') }).fontColor(this.colors.text).backgroundColor(this.colors.surface)
              .enabled(!this.busy).onChange((value: string) => this.contextText = value)
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(CONTEXT_PRESETS, (count: number) => { Button(modelTokenText(count)).margin(4).fontColor(this.colors.text)
                .backgroundColor(this.colors.surface).enabled(!this.busy).onClick(() => this.contextText = this.contextText === String(count) ? '' : String(count)) })
            }
            Text(this.t('留空使用目录值。修改会影响引擎的上下文统计与压缩，在下一次请求生效。')).fontSize(13).fontColor(this.colors.muted)
            this.button(this.t('保存'), () => { void this.saveContext() })
          } else if (this.selected) {
            ForEach(this.providers.filter((provider: SubscriptionStatus) => provider.id === this.selected), (provider: SubscriptionStatus) => {
              Text(provider.account || this.t('已登录')).fontColor(this.colors.muted)
              ForEach(this.models, (model: DshModelInfo) => {
                this.button(model.name || model.id, () => { this.modelId = model.id; const value = number(object(this.overrides[model.id])['contextWindow'], 0); this.contextText = value ? String(value) : '' })
              }, (model: DshModelInfo) => model.id)
              this.button(this.t('刷新模型'), () => { void this.details(provider.id) })
              this.button(this.t('退出登录'), () => this.signOut(provider))
            })
          } else {
            ForEach(this.providers, (provider: SubscriptionStatus) => {
              Column({ space: 10 }) {
                Text(provider.title).fontSize(20).fontColor(this.colors.text).width('100%')
                Text(provider.signedIn ? provider.account || this.t('已登录') : this.t('连接已有订阅，在此主机使用订阅模型。')).fontColor(this.colors.muted).width('100%')
                this.button(provider.signedIn ? this.t('管理订阅与模型') : this.t('登录'), () => { if (provider.signedIn) void this.details(provider.id); else this.begin(provider.id) })
              }.padding(16).width('100%').backgroundColor(this.colors.surface).borderRadius(14)
            }, (provider: SubscriptionStatus) => `${provider.id}|${provider.signedIn}|${provider.account}`)
            this.button(this.t('刷新'), () => { void this.refresh() })
          }
        }.width('100%')
      }.width('100%').layoutWeight(1).align(Alignment.Top)
    }.width('100%').height('100%').padding(16).backgroundColor(this.colors.background)
  }
}
