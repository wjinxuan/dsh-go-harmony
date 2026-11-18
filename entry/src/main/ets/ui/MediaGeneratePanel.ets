import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { DshClient } from '../dsh/DshClient'
import { MediaCatalog, MediaEntry, MediaKind, MediaParams, fitMediaParams, formatMediaMessage } from '../dsh/MediaData'
import { loadMediaCatalog } from '../dsh/MediaApi'
import { ThemeColors, themeColors } from './DshTheme'

@Component
export struct MediaGeneratePanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  client: DshClient = new DshClient()
  currentParams?: MediaParams
  onSelected: (params: MediaParams) => void = () => {}
  onSettings: () => void = () => {}
  onClose: () => void = () => {}
  @State private catalog: MediaCatalog = { status: 'loading', namespaces: [], entries: [], credentials: {} }
  @State private params: MediaParams = { kind: 'image', count: 1 }
  @State private loading: boolean = false
  @State private error: string = ''
  private active: boolean = false
  private generation: number = 0

  aboutToAppear(): void { this.active = true; void this.load() }
  aboutToDisappear(): void { this.active = false; this.generation++ }

  private async load(): Promise<void> {
    const generation = ++this.generation; const connection = this.client.connectionIdentity()
    this.loading = true; this.error = ''
    try {
      const catalog = await loadMediaCatalog(this.client)
      if (!this.active || generation !== this.generation || connection !== this.client.connectionIdentity()) return
      this.catalog = catalog
      const initial = this.currentParams || { kind: 'image', count: 1 } as MediaParams
      const same = initial.model && catalog.entries.find((e: MediaEntry) => e.namespace === initial.model?.namespace &&
        e.service.id === initial.model?.service.id && e.model.id === initial.model?.model.id)
      this.params = fitMediaParams({ kind: initial.kind, model: same, aspect: initial.aspect, count: initial.count,
        quality: initial.quality, seconds: initial.seconds, resolution: initial.resolution }, catalog)
    } catch { if (this.active && generation === this.generation) this.error = this.t("无法读取此主机的媒体服务，请重试。") }
    finally { if (this.active && generation === this.generation) this.loading = false }
  }

  private choose(kind: MediaKind, model?: MediaEntry): void {
    this.params = fitMediaParams({ kind: kind, model: model, count: this.params.count,
      aspect: this.params.aspect, quality: this.params.quality, seconds: this.params.seconds,
      resolution: this.params.resolution }, this.catalog)
  }

  private change(field: string, value: string): void {
    const old = this.params
    this.params = { kind: old.kind, model: old.model, count: field === 'count' ? Number(value) : old.count,
      aspect: field === 'aspect' ? value : old.aspect, quality: field === 'quality' ? value || undefined : old.quality,
      seconds: field === 'seconds' ? Number(value) : old.seconds, resolution: field === 'resolution' ? value : old.resolution }
  }

  private select(): void {
    if (!this.params.model) return
    try { formatMediaMessage(this.params, '.'); this.onSelected(this.params) }
    catch { this.error = this.t("这些参数无法写入生成请求，请重新选择。") }
  }

  private choiceValues(field: string): string[] {
    const model = this.params.model?.model
    if (!model) return []
    if (field === 'aspect') return model.ratios
    if (field === 'count') return ['1', '2', '3', '4'].slice(0, model.maxN)
    if (field === 'quality') return [''].concat(model.qualities)
    if (field === 'seconds') return model.durations.map((value: number) => String(value))
    if (field === 'resolution') return model.resolutions
    return []
  }

  private choiceSelected(field: string): string {
    if (field === 'aspect') return this.params.aspect || ''
    if (field === 'count') return String(this.params.count)
    if (field === 'quality') return this.params.quality || ''
    if (field === 'seconds') return String(this.params.seconds || '')
    if (field === 'resolution') return this.params.resolution || ''
    return ''
  }

  @Builder
  private choices(title: string, field: string) {
    if (this.choiceValues(field).length) {
      Column({ space: 8 }) {
        Text(this.t(title)).fontSize(14).fontColor(this.colors.muted).width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.choiceValues(field), (value: string) => {
            Button(value || this.t("自动")).height(38).margin({ right: 8, bottom: 8 })
              .fontColor(value === this.choiceSelected(field) ? this.colors.onPrimary : this.colors.text)
              .backgroundColor(value === this.choiceSelected(field) ? this.colors.primary : this.colors.surfaceAlt)
              .onClick(() => this.change(field, value))
          }, (value: string) => value)
        }
      }.width('100%')
    }
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Button(this.t("返回")).onClick(this.onClose).backgroundColor(this.colors.surface).fontColor(this.colors.primary)
        Text(this.t("生成")).fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.colors.text).layoutWeight(1)
        Button(this.t("服务设置")).onClick(this.onSettings).backgroundColor(this.colors.surface).fontColor(this.colors.primary)
      }.width('100%')
      if (this.loading) { LoadingProgress().width(28).height(28) }
      else if (this.error) {
        Text(this.t(this.error)).fontColor(this.colors.danger)
        Button(this.t("重试")).onClick(() => { void this.load() })
      } else if (!this.catalog.entries.length) {
        Text(this.catalog.status === 'missing' ? this.t("此主机尚未提供图像与视频服务") :
          this.catalog.status === 'unsupported' ? this.t("媒体插件目录版本不受支持，请更新应用或插件") : this.t("添加服务并配置 API Key 后即可生成"))
          .fontColor(this.colors.muted).textAlign(TextAlign.Center).padding(24)
        Button(this.t("配置图像与视频")).onClick(this.onSettings)
      } else {
        Row({ space: 12 }) {
          Button(this.t("图像")).backgroundColor(this.params.kind === 'image' ? this.colors.primary : this.colors.surfaceAlt)
            .fontColor(this.params.kind === 'image' ? this.colors.onPrimary : this.colors.text).onClick(() => this.choose('image'))
          Button(this.t("视频")).backgroundColor(this.params.kind === 'video' ? this.colors.primary : this.colors.surfaceAlt)
            .fontColor(this.params.kind === 'video' ? this.colors.onPrimary : this.colors.text).onClick(() => this.choose('video'))
        }
        Scroll() {
          Column({ space: 14 }) {
            ForEach(this.catalog.entries.filter((e: MediaEntry) => e.model.kind === this.params.kind), (entry: MediaEntry) => {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 8 }) {
                  Column({ space: 3 }) {
                    Text(entry.model.label).fontSize(16).fontColor(this.colors.text)
                    Text(entry.service.label || entry.service.provider).fontSize(12).fontColor(this.colors.muted)
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  if (this.params.model?.namespace === entry.namespace && this.params.model?.service.id === entry.service.id &&
                    this.params.model?.model.id === entry.model.id) Text('✓').fontColor(this.colors.primary)
                }.width('100%').padding(12)
              }.width('100%').backgroundColor(this.colors.surfaceAlt).borderRadius(12)
                .onClick(() => this.choose(this.params.kind, entry))
            }, (e: MediaEntry) => `${e.namespace}/${e.service.id}/${e.model.id}`)
            if (this.params.model) {
              this.choices('比例', 'aspect')
              if (this.params.kind === 'image') {
                this.choices('数量', 'count')
                this.choices('质量', 'quality')
              } else {
                this.choices('时长（秒）', 'seconds')
                this.choices('分辨率', 'resolution')
              }
              if (this.params.model.model.maxRefs > 0 || this.params.model.model.firstFrame) {
                Text(this.params.kind === 'image' ? this.f("可在输入框添加参考图，最多 {0} 张", [this.params.model.model.maxRefs]) :
                  this.params.model.model.lastFrame ? this.t("可在输入框添加首帧与尾帧图片") : this.t("可在输入框添加首帧图片")).fontSize(13).fontColor(this.colors.muted)
              }
              if (this.params.model.model.price !== undefined) {
                Text(this.f("预计 {0} {1}", [this.params.model.model.currency, ((this.params.model.model.price || 0) *
                  (this.params.model.model.perSecond ? this.params.seconds || 1 : this.params.count)).toFixed(3)]))
                  .fontSize(13).fontColor(this.colors.muted)
              }
            } else Text(this.t("此主机没有可用的此类模型")).fontColor(this.colors.muted)
          }.width('100%')
        }.layoutWeight(1)
        Button(this.t("使用这些参数")).width('100%').enabled(!!this.params.model).backgroundColor(this.colors.primary)
          .fontColor(this.colors.onPrimary).onClick(() => this.select())
      }
    }.padding(16).width('100%').height('100%').backgroundColor(this.colors.surface)
  }
}
