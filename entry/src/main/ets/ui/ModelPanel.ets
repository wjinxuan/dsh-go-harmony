import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { DshClient } from '../dsh/DshClient'
import {
  DshModelCatalogFailure, DshModelInfo, DshModelSelection, DshProviderGroup, DshReasoningEffort, DshSessionProjections
} from '../dsh/DshWire'
import { ThemeColors, themeColors, DshGlyphs } from './DshTheme'
import { catalogModel, defaultModelEffort, filterModelGroups, modelDisplayName, projectedModelSelection } from './ModelSelectionData'

@Component
export struct ModelPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  @Prop @Watch('sessionChanged') sessionId: string = ''
  @Prop currentSelection: DshModelSelection | undefined = undefined
  client: DshClient = new DshClient()
  onClose: () => void = () => {}
  onBackHandler?: (handler: (() => boolean) | undefined) => void
  onManageModels: () => void = () => {}
  onSelected: (name: string, selection: DshModelSelection, warning?: string) => void = () => {}

  @State private groups: DshProviderGroup[] = []
  @State private failures: string[] = []
  @State private query: string = ''
  @State private loading: boolean = true
  @State private loadError: boolean = false
  @State private selection: DshModelSelection | undefined = undefined
  @State private model: DshModelInfo | undefined = undefined
  @State private writing: boolean = false
  @State private retrySelection: DshModelSelection | undefined = undefined
  private generation: number = 0
  private catalogIdentity: number = -1
  private active: boolean = false

  aboutToAppear(): void {
    this.active = true
    this.onBackHandler?.(() => this.back())
    this.sessionChanged()
  }

  aboutToDisappear(): void {
    this.active = false
    this.onBackHandler?.(undefined)
    this.generation++
  }

  private sessionChanged(): void {
    if (!this.active) return
    this.query = ''
    this.model = undefined
    this.groups = []
    this.failures = []
    this.selection = undefined
    this.retrySelection = undefined
    this.writing = false
    void this.load()
  }

  private back(): boolean {
    if (this.writing) return true
    if (!this.model) return false
    this.model = undefined
    this.retrySelection = undefined
    return true
  }

  private sameTarget(generation: number, connection: number, sessionId: string): boolean {
    return this.active && generation === this.generation && connection === this.client.connectionIdentity() &&
      sessionId === this.sessionId
  }

  private async load(): Promise<void> {
    const generation = ++this.generation
    const connection = this.client.connectionIdentity()
    const sessionId = this.sessionId
    this.catalogIdentity = -1
    this.loading = true
    this.loadError = false
    this.retrySelection = undefined
    try {
      const readCatalog = this.client.listModels()
      const projection: Promise<DshSessionProjections | null> = sessionId ?
        this.client.sessionProjections(sessionId).catch((): null => null) : Promise.resolve(null)
      const catalog = await readCatalog
      const session = await projection
      if (!this.sameTarget(generation, connection, sessionId)) return
      this.groups = filterModelGroups(catalog.groups, '')
      this.failures = catalog.failures.map((failure: DshModelCatalogFailure) => failure.name || failure.provider).filter(name => !!name)
      this.selection = projectedModelSelection(session) ?? this.currentSelection ?? catalog.defaultSelection
      this.catalogIdentity = connection
    } catch {
      if (this.sameTarget(generation, connection, sessionId)) {
        this.groups = []
        this.failures = []
        this.loadError = true
      }
    } finally {
      if (this.sameTarget(generation, connection, sessionId)) this.loading = false
    }
  }

  private isSelected(model: DshModelInfo): boolean {
    return this.selection?.provider === model.provider && this.selection?.model === model.id
  }

  private pick(model: DshModelInfo): void {
    if (this.loading || this.writing || this.loadError) return
    this.retrySelection = undefined
    if (model.efforts.length > 1) this.model = model
    else void this.choose(model.provider, model.id, defaultModelEffort(model))
  }

  private async choose(provider: string, id: string, effort: string): Promise<void> {
    if (this.loading || this.writing || this.loadError) return
    const generation = this.generation
    const connection = this.client.connectionIdentity()
    const sessionId = this.sessionId
    if (!this.sameTarget(generation, connection, sessionId) || this.catalogIdentity !== connection) return
    const model = catalogModel(this.groups, provider, id)
    if (!model || (effort && !model.efforts.some((item: DshReasoningEffort) => item.id === effort))) return
    const requested: DshModelSelection = { provider: provider, model: id, reasoningEffort: effort || undefined }
    this.retrySelection = undefined
    if (!sessionId) {
      this.selection = requested
      this.onSelected(modelDisplayName(this.groups, requested), requested)
      return
    }

    this.writing = true
    try {
      const result = await this.client.setModel(sessionId, provider, id, requested.reasoningEffort)
      if (!this.sameTarget(generation, connection, sessionId)) return
      this.selection = result.selected
      this.onSelected(modelDisplayName(this.groups, result.selected), result.selected,
        result.defaultSave?.status === 'failed' ? this.t("当前对话模型已切换，未能保存为新对话默认模型。") : undefined)
    } catch {
      if (this.sameTarget(generation, connection, sessionId)) this.retrySelection = requested
    } finally {
      if (this.sameTarget(generation, connection, sessionId)) this.writing = false
    }
  }

  private retryChoice(): void {
    const selection = this.retrySelection
    if (selection) void this.choose(selection.provider, selection.model, selection.reasoningEffort || '')
  }

  @Builder
  private effortChoice(model: DshModelInfo, effort: DshReasoningEffort) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text(effort.name || effort.id).fontSize(15).fontColor(this.colors.text)
          if (effort.description) {
            Text(effort.description).fontSize(13).fontColor(this.colors.muted)
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.isSelected(model) && this.selection?.reasoningEffort === effort.id) {
          Text(this.t("当前")).fontSize(12).fontColor(this.colors.primary)
        }
        if (defaultModelEffort(model) === effort.id) {
          Text(this.t("默认")).fontSize(12).fontColor(this.colors.hint)
        }
      }.width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 })
    }.width('100%').constraintSize({ minHeight: 44 }).backgroundColor(this.colors.surfaceAlt).borderRadius(12)
      .enabled(!this.writing).onClick(() => { void this.choose(model.provider, model.id, effort.id) })
  }

  @Builder
  private effortPanel(model: DshModelInfo) {
    Scroll() {
      Column({ space: 12 }) {
        Text(model.name || model.id).fontSize(19).fontColor(this.colors.text)
        Text(this.t("思考深度")).fontSize(14).fontColor(this.colors.muted)
        ForEach(model.efforts, (effort: DshReasoningEffort) => {
          this.effortChoice(model, effort)
        }, (effort: DshReasoningEffort) => JSON.stringify(effort))
        Button(this.t("返回模型列表")).fontColor(this.colors.muted).backgroundColor(Color.Transparent)
          .enabled(!this.writing).onClick(() => { this.back() })
      }.width('100%').padding(16).backgroundColor(this.colors.surface).borderRadius(18)
    }.layoutWeight(1).width('100%').align(Alignment.Top)
  }

  @Builder
  private modelRow(model: DshModelInfo) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        Column({ space: 5 }) {
          Text(model.name || model.id).fontSize(16).fontColor(this.colors.text)
          if (model.description) { Text(model.description).fontSize(13).fontColor(this.colors.muted).maxLines(2) }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (this.isSelected(model)) {
          Text(DshGlyphs.check).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.primary)
            .accessibilityText(this.t("当前模型"))
        }
      }.width('100%').padding(16)
    }.width('100%').backgroundColor(this.colors.surface).borderRadius(14).enabled(!this.writing)
      .onClick(() => this.pick(model))
  }

  @Builder
  private modelList() {
    List({ space: 12 }) {
      ForEach(filterModelGroups(this.groups, this.query), (group: DshProviderGroup) => {
        ListItem() {
          Column({ space: 6 }) {
            Text(group.name || group.id).fontSize(13).fontColor(this.colors.muted).padding({ left: 8, bottom: 4 })
            ForEach(group.models, (model: DshModelInfo) => { this.modelRow(model) },
              (model: DshModelInfo) => JSON.stringify(model))
          }.alignItems(HorizontalAlign.Start).width('100%')
        }
      }, (group: DshProviderGroup) => JSON.stringify(group))
    }.layoutWeight(1).width('100%')
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Button({ type: ButtonType.Circle }) {
          Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text)
        }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText(this.t("返回"))
          .enabled(!this.writing).onClick(() => { if (!this.back()) this.onClose() })
        Text(this.t("选择模型")).fontSize(22).fontColor(this.colors.text).layoutWeight(1)
        Button(this.t("管理模型")).fontSize(14).fontColor(this.colors.primary).backgroundColor(this.colors.surface)
          .height(42).enabled(!this.writing).onClick(this.onManageModels)
      }.width('100%')
      if (!this.model && !this.loading && !this.loadError && this.groups.length > 0) {
        Row({ space: 8 }) {
          TextInput({ text: this.query, placeholder: this.t("搜索模型或渠道") }).height(44)
            .fontColor(this.colors.text).backgroundColor(this.colors.surface).layoutWeight(1)
            .enabled(!this.writing).onChange((value: string) => { this.query = value })
          if (this.query) {
            Button(this.t("清除")).fontColor(this.colors.primary).backgroundColor(this.colors.surface)
              .height(44).enabled(!this.writing).onClick(() => { this.query = '' })
          }
        }.width('100%')
      }
      if (this.retrySelection) {
        Row({ space: 8 }) {
          Text(this.t("未能切换模型。")).fontSize(14).fontColor(this.colors.danger).layoutWeight(1)
          Button(this.t("重试切换")).fontColor(this.colors.primary).backgroundColor(this.colors.surface)
            .height(42).onClick(() => this.retryChoice())
        }.width('100%')
      }
      if (!this.model && !this.loading && !this.loadError && this.failures.length > 0) {
        Row({ space: 8 }) {
          Text(this.f("以下渠道未返回模型：{0}", [this.failures.join('、')])).fontSize(13).fontColor(this.colors.warning)
            .maxLines(3).layoutWeight(1)
          Button(this.t("刷新")).fontColor(this.colors.primary).backgroundColor(this.colors.surface)
            .height(40).enabled(!this.writing).onClick(() => { void this.load() })
        }.width('100%')
      }
      if (this.writing) {
        LoadingProgress().width(28).height(28).color(this.colors.primary).accessibilityText(this.t("正在切换模型"))
      }
      if (this.loading) {
        LoadingProgress().width(32).height(32).color(this.colors.primary).accessibilityText(this.t("正在读取模型列表"))
      } else if (this.loadError) {
        Text(this.t("模型列表加载失败")).fontSize(15).fontColor(this.colors.danger)
        Button(this.t("重试加载")).fontColor(this.colors.primary).backgroundColor(this.colors.surface)
          .height(44).onClick(() => { void this.load() })
      } else if (this.model) {
        this.effortPanel(this.model)
      } else if (this.groups.length === 0) {
        Text(this.t("暂无可用模型。可以在「管理模型」中检查 API Key 和渠道。"))
          .fontSize(14).fontColor(this.colors.muted).padding(12)
      } else if (filterModelGroups(this.groups, this.query).length === 0) {
        Text(this.t("没有匹配的模型")).fontSize(14).fontColor(this.colors.muted).padding(12)
      } else {
        this.modelList()
      }
    }.padding(16).width('100%').height('100%').backgroundColor(this.colors.background)
  }
}
