import { localizedSettingsText } from './SettingsLocale'
import { DshClient } from '../dsh/DshClient'
import { array, object, string, strings, WireObject } from '../dsh/DshWire'
import { editableField, fieldInput, fieldText, parseSettingsSection, SettingsField, SettingsSection } from './settings/SettingsSchema'
import { ThemeColors, themeColors } from './DshTheme'

@Component
export struct PluginConfigPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'

  @StorageProp('dshLanguage') language: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.language) }
  @Prop colors: ThemeColors = themeColors()
  @Prop entryId: string = ''
  client: DshClient = new DshClient()
  onClose: () => void = () => {}
  @State private fields: SettingsField[] = []
  @State private title: string = ''
  @State private error: string = ''
  @State private busy: boolean = true
  @State private writable: boolean = false
  @State private editing: string = ''
  @State private input: string = ''
  private detail: WireObject = {}
  private generation: number = 0
  private identity: number = 0

  aboutToAppear(): void { this.identity = this.client.connectionIdentity(); void this.load() }
  aboutToDisappear(): void { this.generation++ }
  private valid(generation: number): boolean { return generation === this.generation && this.identity === this.client.connectionIdentity() }
  private accept(raw: WireObject): void {
    const detail = raw['entry'] ? object(raw['entry']) : raw
    if (detail['v'] !== 1 || detail['entryId'] !== this.entryId || typeof detail['revision'] !== 'string') throw new Error(this.t("主机返回了无效的插件配置"))
    this.detail = detail
    const normalized: WireObject = { 'ns': this.entryId, 'schema': detail['schema'], 'value': detail['value'],
      'base': detail['base'], 'user': detail['user'], 'writable': detail['writable'],
      'secrets': array(detail['secrets']).map((value: Object): WireObject => {
        const fact = object(value); const slot: WireObject = { 'path': fact['path'], 'set': fact['configured'] === true || fact['set'] === true }; return slot
      }) }
    const parsed = parseSettingsSection(normalized, detail['writable'] === true)
    this.title = parsed.title; this.fields = parsed.fields; this.writable = parsed.writable
  }
  private async load(): Promise<void> {
    const generation = ++this.generation; this.busy = true; this.error = ''
    try {
      const result = await this.client.bridgeJson('GET', '/dsh-go/v1/plugin-config/' + encodeURIComponent(this.entryId))
      if (this.valid(generation)) this.accept(object(result))
    } catch (reason) { if (this.valid(generation)) this.error = reason instanceof Error ? reason.message : this.t("插件配置读取失败") }
    finally { if (this.valid(generation)) this.busy = false }
  }
  private async save(field: SettingsField, unset: boolean): Promise<void> {
    if (this.busy || !this.writable || !this.valid(this.generation)) return
    const generation = this.generation; this.busy = true; this.error = ''
    try {
      if (field.kind === 'secret') {
        const secret = array(this.detail['secrets']).map(object).find((row: WireObject) =>
          JSON.stringify(strings(row['path'])) === JSON.stringify(field.path))
        const fact = object(secret); const ref = string(fact['credentialRef']) || string(fact['ref']) || string(object(fact['binding'])['ref'])
        if (!ref || fact['writable'] === false) throw new Error(this.t("此密钥没有可写的凭据绑定"))
        if (unset) await this.client.clearProviderKey(ref)
        else await this.client.setProviderKey(this.input, ref)
        if (!this.valid(generation)) return
        this.editing = ''; this.input = ''; await this.load(); return
      }
      const op: WireObject = { 'op': unset ? 'unset' : 'set', 'path': field.path }
      if (!unset) op['value'] = fieldInput(field, this.input)
      const request: WireObject = { 'revision': this.detail['revision'], 'ops': [op] }
      const result = await this.client.bridgeJson('POST', '/dsh-go/v1/plugin-config/' + encodeURIComponent(this.entryId), {}, request, 60000)
      if (!this.valid(generation)) return
      this.accept(object(result)); this.editing = ''; this.input = ''
    } catch (reason) {
      if (this.valid(generation)) { this.error = reason instanceof Error ? reason.message : this.t("保存未能确认"); this.writable = false }
    } finally { if (this.valid(generation)) this.busy = false }
  }
  private canEdit(field: SettingsField): boolean {
    if (!this.writable || !editableField(field)) return false
    if (field.kind !== 'secret') return true
    const secret = array(this.detail['secrets']).map(object).find((row: WireObject) => JSON.stringify(strings(row['path'])) === JSON.stringify(field.path))
    const fact = object(secret)
    return fact['writable'] !== false && !!(string(fact['credentialRef']) || string(fact['ref']) || string(object(fact['binding'])['ref']))
  }
  build() {
    Column({ space: 12 }) {
      Row() {
        Button(this.t('返回')).onClick(this.onClose).backgroundColor(Color.Transparent).fontColor(this.colors.primary)
        Text(this.title || this.t("插件配置")).fontSize(20).fontColor(this.colors.text).layoutWeight(1)
        Button(this.t('刷新')).enabled(!this.busy).onClick(() => { this.editing = ''; this.input = ''; void this.load() })
      }.width('100%')
      if (this.error) Text(this.error + this.t("\n保存未确认时请刷新再试。")).fontColor(this.colors.danger).fontSize(13)
      if (!this.writable && !this.busy) Text(this.t('当前配置只读')).fontColor(this.colors.muted).fontSize(13)
      if (this.busy) LoadingProgress().width(28).height(28)
      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.fields, (field: SettingsField) => {
            Column({ space: 8 }) {
              Text(field.title).fontColor(this.colors.text).fontSize(15).width('100%')
              if (field.description) Text(field.description).fontColor(this.colors.muted).fontSize(12).width('100%')
              if (this.editing === JSON.stringify(field.path)) {
                if (field.kind === 'enum') {
                  ForEach(field.choices, (choice: Object) => {
                    Button(String(choice)).onClick(() => { this.input = String(choice); void this.save(field, false) })
                  }, (choice: Object) => String(choice))
                } else if (field.kind === 'boolean') {
                  Row() {
                    Button(this.t('开启')).onClick(() => { this.input = 'true'; void this.save(field, false) })
                    Button(this.t('关闭')).onClick(() => { this.input = 'false'; void this.save(field, false) })
                  }
                } else {
                  TextInput({ text: this.input, placeholder: field.kind === 'secret' ? this.t("输入新密钥") : field.title })
                    .type(field.kind === 'secret' ? InputType.Password : InputType.Normal).onChange((value: string) => { this.input = value })
                  Button(this.t('保存')).enabled(!this.busy).onClick(() => { void this.save(field, false) })
                }
                if (field.overridden || field.secretSet) Button(field.kind === 'secret' ? this.t("清除密钥") : this.t("恢复继承值"))
                  .enabled(!this.busy).onClick(() => { void this.save(field, true) })
                Button(this.t('取消')).onClick(() => { this.editing = ''; this.input = '' })
              } else {
                Text(fieldText(field) || this.t("未设置")).fontColor(this.colors.muted).fontSize(13).width('100%')
                if (this.canEdit(field)) Button(this.t('编辑')).enabled(!this.busy).onClick(() => {
                  this.editing = JSON.stringify(field.path); this.input = field.kind === 'secret' ? '' : fieldText(field)
                })
              }
            }.width('100%').padding(12).borderRadius(12).backgroundColor(this.colors.surfaceAlt)
          }, (field: SettingsField) => JSON.stringify(field.path))
        }.width('100%')
      }.layoutWeight(1)
    }.width('100%').height('100%').padding(16).backgroundColor(this.colors.background)
  }
}
