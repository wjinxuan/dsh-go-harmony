import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { DshClient } from '../dsh/DshClient'
import { array, object, string, WireObject } from '../dsh/DshWire'
import { loadMediaCatalog } from '../dsh/MediaApi'
import { MediaCatalog, MediaEntry, MediaKind, MediaModel, MediaNamespace, MediaPreset, MediaService,
  defaultMediaEntry, mediaServiceWire, mediaUrlIssue } from '../dsh/MediaData'
import { ThemeColors, themeColors } from './DshTheme'

function origin(value: string): string { return /^https:\/\/[^/]+/i.exec(value)?.[0].toLowerCase() || '' }

@Component
export struct MediaSettingsPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  client: DshClient = new DshClient()
  onClose: () => void = () => {}
  onOpenPlugins: () => void = () => {}
  onBackHandler?: (handler: (() => boolean) | undefined) => void
  @State private catalog: MediaCatalog = { status: 'loading', namespaces: [], entries: [], credentials: {} }
  @State private loading: boolean = false
  @State private working: boolean = false
  @State private error: string = ''
  @State private notice: string = ''
  @State private page: string = 'home'
  @State private namespace: string = ''
  @State private draft: MediaService | undefined = undefined
  @State private keyInput: string = ''
  private active: boolean = false
  private generation: number = 0
  private connection: number = 0

  aboutToAppear(): void {
    this.active = true; this.connection = this.client.connectionIdentity()
    this.onBackHandler?.((): boolean => this.back()); void this.load()
  }
  aboutToDisappear(): void {
    this.active = false; this.generation++; this.keyInput = ''; this.onBackHandler?.(undefined)
  }
  private back(): boolean {
    if (this.working) return true
    if (this.page === 'home') return false
    this.page = 'home'; this.draft = undefined; this.keyInput = ''; this.error = ''; this.notice = ''; return true
  }
  private current(generation: number): boolean {
    return this.active && generation === this.generation && this.connection === this.client.connectionIdentity()
  }
  private ns(): MediaNamespace | undefined { return this.catalog.namespaces.find((n: MediaNamespace) => n.ns === this.namespace) }
  private async load(): Promise<void> {
    const generation = ++this.generation; this.loading = true; this.error = ''
    try {
      const catalog = await loadMediaCatalog(this.client)
      if (!this.current(generation)) return
      this.catalog = catalog
      if (!this.namespace) this.namespace = catalog.namespaces[0]?.ns || ''
      if (this.draft) this.draft = this.ns()?.services.find((s: MediaService) => s.id === this.draft?.id)
    } catch { if (this.current(generation)) this.error = this.t("无法读取媒体设置，请重试。") }
    finally { if (this.current(generation)) this.loading = false }
  }
  private edit(ns: MediaNamespace, service: MediaService): void {
    this.namespace = ns.ns; this.draft = service; this.page = 'detail'; this.error = ''; this.notice = ''; this.keyInput = ''
  }
  private change(field: string, value: string | boolean): void {
    if (!this.draft) return
    const wire = mediaServiceWire(this.draft); wire[field] = value
    const old = this.draft
    this.draft = { id: old.id, label: string(wire['label']), enabled: wire['enabled'] === true,
      provider: string(wire['provider']), baseUrl: string(wire['baseUrl']), profile: string(wire['profile']),
      responseFormat: string(wire['responseFormat']), keyRef: string(wire['keyRef']), models: old.models.slice() }
  }
  private toggleModel(id: string, enabled: boolean): void {
    if (!this.draft || (!enabled && this.draft.models.length <= 1)) return
    const next = this.draft.models.filter((model: string) => model !== id)
    if (enabled) next.push(id)
    this.draft = { id: this.draft.id, label: this.draft.label, enabled: this.draft.enabled, provider: this.draft.provider,
      baseUrl: this.draft.baseUrl, profile: this.draft.profile, responseFormat: this.draft.responseFormat,
      keyRef: this.draft.keyRef, models: next }
  }
  private async write(patch: WireObject, success: string): Promise<boolean> {
    const ns = this.ns(); const generation = this.generation
    if (!ns?.writable || this.working || !this.current(generation)) return false
    this.working = true; this.error = ''; this.notice = ''
    try {
      await this.client.updateSettings(ns.ns, patch, ns.revision)
      if (!this.current(generation)) return false
      await this.load()
      this.notice = success; return true
    } catch { if (this.current(generation)) this.error = this.t("保存失败。设置可能已被其他客户端修改，请刷新后重试。"); return false }
    finally { if (this.active) this.working = false }
  }
  private save(): void {
    const draft = this.draft; const ns = this.ns()
    if (!draft || !ns) return
    const issue = mediaUrlIssue(draft.baseUrl.trim(), draft.profile)
    if (issue) { this.error = issue; return }
    if (!/^[A-Za-z_][A-Za-z0-9_]{0,127}$/.test(draft.keyRef) || !draft.models.length || draft.models.length > 16) {
      this.error = this.t("请填写有效凭据名称，并保留 1 至 16 个模型"); return
    }
    const changed = ns.services.find((s: MediaService) => s.id === draft.id)
    const shared = ns.services.filter((s: MediaService) => s.id !== draft.id && s.keyRef === draft.keyRef)
    const requiresConfirm = (changed && origin(changed.baseUrl) !== origin(draft.baseUrl)) ||
      shared.some((s: MediaService) => origin(s.baseUrl) !== origin(draft.baseUrl))
    if (requiresConfirm) {
      this.getUIContext().showAlertDialog({ title: this.t("确认 API Key 发送目标"), message:
        this.f("此服务将把 {0} 对应的密钥发送至 {1}。请确认这是可信的服务地址。", [draft.keyRef, origin(draft.baseUrl)]),
        primaryButton: { value: this.t("取消"), action: () => {} }, secondaryButton: { value: this.t("保存地址"), action: () => { void this.saveDraft() } } })
    } else void this.saveDraft()
  }
  private async saveDraft(): Promise<void> {
    const draft = this.draft; const ns = this.ns(); if (!draft || !ns) return
    const rows = array(ns.value['services']).slice(); const index = rows.findIndex((v: Object) => object(v)['id'] === draft.id)
    const wire = mediaServiceWire(draft); wire['baseUrl'] = draft.baseUrl.trim()
    if (index < 0) rows.push(wire); else rows[index] = wire
    await this.write({ 'services': rows }, this.t("服务已保存"))
  }
  private add(ns: MediaNamespace, preset: MediaPreset): void {
    const models = preset.models.filter((id: string) => ns.models.some((m) => m.id === id && m.kind === preset.kind && m.profile === preset.profile))
    if (!models.length) { this.error = this.t("此主机目录已不再提供该预设的模型"); return }
    let stem = preset.id.replace(/-/g, '_').slice(0, 24); if (!/^[a-z][a-z0-9_]*$/.test(stem)) stem = 'media_service'
    let id = stem; let suffix = 2
    while (ns.services.some((s: MediaService) => s.id === id)) id = `${stem}_${suffix++}`
    const donor = ns.services.find((s: MediaService) => s.provider === preset.provider && !!s.keyRef && origin(s.baseUrl) === origin(preset.baseUrl))
    const keyStem = `DSH_MEDIA_${preset.keyGroup.toUpperCase().replace(/[^A-Z0-9]+/g, '_') || 'SERVICE'}`
    let key = `${keyStem}_API_KEY`; suffix = 2
    while (ns.services.some((s: MediaService) => s.keyRef === key)) key = `${keyStem}_${suffix++}_API_KEY`
    this.edit(ns, { id: id, label: preset.label, enabled: true, provider: preset.provider, baseUrl: preset.baseUrl,
      profile: preset.profile, responseFormat: preset.responseFormat, models: models.slice(0, 16), keyRef: donor?.keyRef || key })
  }
  private deleteService(): void {
    const draft = this.draft; const ns = this.ns(); if (!draft || !ns) return
    this.getUIContext().showAlertDialog({ title: this.t("删除媒体服务"), message: this.f("删除“{0}”？已生成的文件和 API Key 会保留。", [draft.label || draft.id]),
      primaryButton: { value: this.t("取消"), action: () => {} }, secondaryButton: { value: this.t("删除"), action: () => {
        void this.write({ 'services': array(ns.value['services']).filter((v: Object) => object(v)['id'] !== draft.id) }, this.t("服务已删除"))
          .then((ok: boolean) => { if (ok) { this.page = 'home'; this.draft = undefined } })
      } } })
  }
  private async credential(clear: boolean): Promise<void> {
    const draft = this.draft; const generation = this.generation
    if (!draft || this.working || !this.current(generation) || !draft.keyRef.startsWith('DSH_MEDIA_') ||
      object(this.catalog.credentials[draft.keyRef])['writable'] === false) return
    this.working = true; this.error = ''; this.notice = ''
    try {
      if (clear) await this.client.clearProviderKey(draft.keyRef)
      else await this.client.setProviderKey(this.keyInput, draft.keyRef)
      if (!this.current(generation)) return
      this.keyInput = ''; await this.load(); this.notice = clear ? this.t("API Key 已清除") : this.t("API Key 已保存")
    } catch { if (this.current(generation)) this.error = this.t("API Key 更新失败，请检查输入或主机权限。") }
    finally { if (this.active) this.working = false }
  }
  private async setDefault(entry: MediaEntry, kind: MediaKind): Promise<void> {
    this.namespace = entry.namespace
    const current = object(this.ns()?.value['defaults']); const defaults: WireObject = {}
    for (const key of Object.keys(current)) defaults[key] = current[key]
    defaults[`${kind}ServiceId`] = entry.service.id; defaults[`${kind}ModelId`] = entry.model.id
    await this.write({ 'defaults': defaults }, this.t("默认模型已保存"))
  }

  @Builder
  private field(title: string, value: string, field: string) {
    Column({ space: 4 }) {
      Text(title).fontSize(13).fontColor(this.colors.muted).width('100%')
      TextInput({ text: value }).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
        .enabled(!this.working && this.ns()?.writable === true).onChange((value: string) => this.change(field, value))
    }.width('100%')
  }
  @Builder
  private defaults(kind: MediaKind) {
    Column({ space: 6 }) {
      Text(kind === 'image' ? this.t("默认图像模型") : this.t("默认视频模型")).fontSize(16).fontColor(this.colors.text)
      ForEach(this.catalog.entries.filter((e: MediaEntry) => e.model.kind === kind), (e: MediaEntry) => {
        Button(`${defaultMediaEntry(this.catalog, kind)?.model.id === e.model.id &&
          defaultMediaEntry(this.catalog, kind)?.service.id === e.service.id ? '✓ ' : ''}${e.model.label} · ${e.service.label || e.service.id}`)
          .width('100%').backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.text).enabled(!this.working)
          .onClick(() => { void this.setDefault(e, kind) })
      }, (e: MediaEntry) => `${e.namespace}/${e.service.id}/${e.model.id}`)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  build() {
    Column({ space: 10 }) {
      Row() {
        Button(this.t("返回")).fontColor(this.colors.primary).backgroundColor(this.colors.surface)
          .onClick(() => { if (!this.back()) this.onClose() })
        Text(this.page === 'detail' ? this.draft?.label || this.t("媒体服务") : this.t("图像与视频")).fontSize(20)
          .fontColor(this.colors.text).layoutWeight(1)
        Button(this.t("刷新")).enabled(!this.working).fontColor(this.colors.primary).backgroundColor(this.colors.surface)
          .onClick(() => { void this.load() })
      }.width('100%')
      if (this.error) Text(this.t(this.error)).fontColor(this.colors.danger).fontSize(13)
      if (this.notice) Text(this.notice).fontColor(this.colors.success).fontSize(13)
      if (this.loading) LoadingProgress().width(24).height(24)
      Scroll() {
        Column({ space: 16 }) {
          if (!this.catalog.namespaces.length && !this.loading) {
            Text(this.catalog.status === 'unsupported' ? this.t("媒体目录版本不受支持") : this.t("此主机尚未提供媒体服务设置"))
              .fontColor(this.colors.muted).padding(20)
            Button(this.t("管理插件")).onClick(this.onOpenPlugins)
          } else if (this.page === 'home') {
            ForEach(this.catalog.namespaces, (ns: MediaNamespace) => {
              ForEach(ns.services, (service: MediaService) => {
                Button({ type: ButtonType.Normal }) {
                  Column({ space: 4 }) {
                    Text(service.label || service.provider || service.id).fontSize(17).fontColor(this.colors.text)
                    Text(`${service.enabled ? this.t("已启用") : this.t("已停用")} · ${object(this.catalog.credentials[service.keyRef])['configured'] === true ? this.t("API Key 已配置") : this.t("API Key 未配置")}`)
                      .fontSize(13).fontColor(this.colors.muted)
                    Text(service.models.join(' · ')).fontSize(12).fontColor(this.colors.muted).maxLines(2)
                  }.padding(14).width('100%').alignItems(HorizontalAlign.Start)
                }.width('100%').backgroundColor(this.colors.surfaceAlt).borderRadius(12).onClick(() => this.edit(ns, service))
              }, (s: MediaService) => s.id)
              Text(this.t("添加服务")).fontColor(this.colors.muted).fontSize(14).width('100%')
              ForEach(ns.presets.filter((p: MediaPreset) => p.models.some((id: string) =>
                ns.models.some((m) => m.id === id && m.profile === p.profile && m.kind === p.kind))), (preset: MediaPreset) => {
                Button(`＋ ${preset.label}`).width('100%').fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt)
                  .enabled(ns.writable && !this.working).onClick(() => this.add(ns, preset))
              }, (p: MediaPreset) => p.id)
            }, (ns: MediaNamespace) => ns.ns)
            this.defaults('image')
            this.defaults('video')
          } else if (this.draft) {
            Row() {
              Text(this.t("启用此服务")).fontColor(this.colors.text).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.draft.enabled }).enabled(!this.working && this.ns()?.writable === true)
                .onChange((enabled: boolean) => this.change('enabled', enabled))
            }.width('100%')
            this.field(this.t("服务名称"), this.draft.label, 'label')
            Text(this.t("模型（至少保留一个）")).fontColor(this.colors.muted).width('100%')
            ForEach(this.ns()?.models.filter((m: MediaModel) => m.profile === this.draft?.profile) || [], (model: MediaModel) => {
              Row() {
                Text(model.label).fontColor(this.colors.text).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.draft?.models.includes(model.id) || false })
                  .enabled(!this.working && this.ns()?.writable === true &&
                    !(this.draft?.models.length === 1 && this.draft.models.includes(model.id)))
                  .onChange((enabled: boolean) => this.toggleModel(model.id, enabled))
              }.width('100%')
            }, (model: MediaModel) => model.id)
            this.field(this.t("API 基础地址"), this.draft.baseUrl, 'baseUrl')
            Text(this.f("协议：{0}", [this.draft.profile])).fontSize(13).fontColor(this.colors.muted).width('100%')
            this.field(this.t("凭据引用"), this.draft.keyRef, 'keyRef')
            ForEach(this.ns()?.services.filter((s: MediaService) => s.id !== this.draft?.id &&
              s.provider === this.draft?.provider && s.keyRef !== this.draft?.keyRef) || [], (s: MediaService) => {
              Button(this.f("复用 {0} 的密钥", [s.label || s.id])).fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt)
                .enabled(!this.working).onClick(() => this.change('keyRef', s.keyRef))
            }, (s: MediaService) => s.id)
            if (this.draft.profile === 'openai-compatible' || this.draft.profile === 'openai-gpt-image') {
              this.field(this.t("响应格式（留空 / url / b64_json）"), this.draft.responseFormat, 'responseFormat')
            }
            Button(this.t("保存服务")).width('100%').backgroundColor(this.colors.primary).fontColor(this.colors.onPrimary)
              .enabled(!this.working && this.ns()?.writable === true).onClick(() => this.save())
            if (this.ns()?.services.some((s: MediaService) => s.id === this.draft?.id)) {
              Text(object(this.catalog.credentials[this.draft.keyRef])['configured'] === true ? this.t("API Key 已配置") : this.t("API Key 未配置"))
                .fontColor(this.colors.muted).width('100%')
              if (this.draft.keyRef.startsWith('DSH_MEDIA_') && object(this.catalog.credentials[this.draft.keyRef])['writable'] !== false) {
                TextInput({ text: this.keyInput, placeholder: this.t("输入新的 API Key") }).type(InputType.Password)
                  .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).enabled(!this.working)
                  .onChange((value: string) => { this.keyInput = value })
                Row({ space: 8 }) {
                  Button(this.t("保存 API Key")).enabled(!this.working && !!this.keyInput.trim()).onClick(() => { void this.credential(false) })
                  Button(this.t("清除 API Key")).enabled(!this.working && object(this.catalog.credentials[this.draft.keyRef])['configured'] === true)
                    .onClick(() => { this.getUIContext().showAlertDialog({ title: this.t("清除 API Key"), message: this.t("引用此密钥的服务都将无法继续生成。"),
                      primaryButton: { value: this.t("取消"), action: () => {} }, secondaryButton: { value: this.t("清除"), action: () => { void this.credential(true) } } }) })
                }
              } else Text(this.t("此凭据来自其他服务或环境变量，请在其所属设置中修改。")).fontSize(13).fontColor(this.colors.muted)
              Button(this.t("删除服务")).fontColor(this.colors.danger).backgroundColor(this.colors.surfaceAlt)
                .enabled(!this.working && this.ns()?.writable === true).onClick(() => this.deleteService())
            } else Text(this.t("保存服务后可配置 API Key。")).fontSize(13).fontColor(this.colors.muted)
          }
        }.width('100%')
      }.layoutWeight(1).width('100%')
    }.padding(16).width('100%').height('100%').backgroundColor(this.colors.surface)
  }
}
