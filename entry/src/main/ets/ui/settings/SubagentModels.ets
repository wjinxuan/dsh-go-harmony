import { DshClient } from '../../dsh/DshClient'
import { DshSettingsOp, DshProviderGroup } from '../../dsh/DshWire'
import { SettingsSection } from './SettingsSchema'
import { subagentRoutes, subagentCandidates, pickSubagentModel, SubagentModel } from './SubagentModelsData'
import { localizedSettingsText } from '../SettingsLocale'
import { ThemeColors, themeColors } from '../DshTheme'
@Component
export struct SubagentModels {
  @StorageProp('dshLanguage') private language: string = 'system'
  @Prop colors: ThemeColors = themeColors()
  @Prop section: SettingsSection = { id: '', title: '', description: '', revision: 0, writable: false, autoGenerate: true, fields: [], value: {} }
  @Prop busy: boolean = false
  client: DshClient = new DshClient()
  onWrite: (ops: DshSettingsOp[]) => Promise<SettingsSection | undefined> = async () => undefined
  onManageModels: () => void = () => {}
  @State private groups: DshProviderGroup[] = []
  @State private pending: boolean = false
  @State private loading: boolean = false
  @State private saving: boolean = false
  @State private error: string = ''
  private active: boolean = false
  private generation: number = 0
  private t(value: string): string { return localizedSettingsText(value, this.language) }
  aboutToAppear(): void { this.active = true; void this.load() }
  aboutToDisappear(): void { this.active = false; this.generation++ }
  private async load(): Promise<void> {
    const generation = ++this.generation, identity = this.client.connectionIdentity(); this.loading = true; this.error = ''
    try { const models = await this.client.listModels(); if (this.active && generation === this.generation && identity === this.client.connectionIdentity()) { this.groups = models.groups; if (models.failures.length) this.error = '部分模型目录读取失败，请重试。' } }
    catch { if (this.active && generation === this.generation && identity === this.client.connectionIdentity()) this.error = '模型目录未能读取，已保留当前允许的模型。' }
    finally { if (this.active && generation === this.generation) this.loading = false }
  }
  private async toggle(enabled: boolean): Promise<void> {
    if (this.busy || this.saving || !this.section.writable) return
    if (enabled && !subagentRoutes(this.section.value['allowedModels']).length) { this.pending = true; return }
    if (!enabled && this.pending && this.section.value['enabled'] !== true) { this.pending = false; return }
    const generation = this.generation, identity = this.client.connectionIdentity(); this.saving = true; this.error = ''
    try { const section = await this.onWrite([{ op: 'set', path: ['enabled'], value: enabled }]); if (this.active && generation === this.generation && identity === this.client.connectionIdentity() && section?.value['enabled'] === enabled) this.pending = false }
    catch (error) { if (this.active && generation === this.generation && identity === this.client.connectionIdentity()) this.error = (error as Error).message }
    finally { if (this.active && generation === this.generation) this.saving = false }
  }
  private selected(model: SubagentModel): boolean { return subagentRoutes(this.section.value['allowedModels']).some(route => route.provider === model.provider && route.model === model.model) }
  private async pick(model: SubagentModel): Promise<void> {
    if (this.busy || this.saving || !this.section.writable || (!model.available && !this.selected(model))) return
    const generation = this.generation, identity = this.client.connectionIdentity(); this.saving = true; this.error = ''
    try { const next = await this.onWrite(pickSubagentModel(this.section.value, this.pending, { provider: model.provider, model: model.model })); if (this.active && generation === this.generation && identity === this.client.connectionIdentity() && next?.value['enabled'] === true && subagentRoutes(next.value['allowedModels']).some(route => route.provider === model.provider && route.model === model.model)) this.pending = false }
    catch (error) { if (this.active && generation === this.generation && identity === this.client.connectionIdentity()) this.error = (error as Error).message }
    finally { if (this.active && generation === this.generation) this.saving = false }
  }
  build() {
    Column({ space: 10 }) {
      Row() { Text(this.t('子代理可自行选择模型')).fontColor(this.colors.text).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.pending || this.section.value['enabled'] === true }).enabled(this.section.writable && !this.busy && !this.saving).onChange((enabled: boolean) => { void this.toggle(enabled) }) }.width('100%')
      if (this.pending) Text(this.t('请选择第一个模型后启用。')).fontColor(this.colors.muted)
      if (this.pending || this.section.value['enabled'] === true) {
        ForEach(subagentCandidates(this.groups, subagentRoutes(this.section.value['allowedModels'])), (model: SubagentModel) => {
          Row({ space: 8 }) { Checkbox().select(this.selected(model)).enabled(!this.busy && !this.saving && this.section.writable && (model.available || this.selected(model))).onChange(() => { void this.pick(model) })
            Column() { Text(model.title).fontColor(this.colors.text).width('100%'); Text(model.providerTitle + (model.available ? '' : ' · ' + this.t('当前不可用'))).fontColor(this.colors.muted).fontSize(12).width('100%') }.layoutWeight(1) }.width('100%')
        }, (model: SubagentModel) => model.provider + '/' + model.model)
        if (this.loading) LoadingProgress().width(22).height(22)
        Button(this.t('刷新模型目录')).enabled(!this.loading && !this.busy && !this.saving).onClick(() => { void this.load() })
        Button(this.t('管理模型')).enabled(!this.busy && !this.saving).onClick(this.onManageModels)
      }
      if (this.error) Text(this.t(this.error)).fontColor(this.colors.danger)
    }.width('100%').padding(14).backgroundColor(this.colors.surface).borderRadius(14)
  }
}
