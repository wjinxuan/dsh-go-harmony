import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { DshClient } from '../dsh/DshClient'
import { object, string, strings, WireObject } from '../dsh/DshWire'
import { TransportControl } from '../remote/TransportEndpoint'
import { ThemeColors, themeColors } from './DshTheme'
import { localizedSettingsText } from './SettingsLocale'
import { ConversationShareClient, saveSharedText } from './ConversationShareData'
import { ProfileShareController, ProfileShareHost, ProfileShareTransport, profileRows, profileSelection } from './ProfileShareData'
@Component
export struct ProfileSharePanel {
  @StorageProp('dshLanguage') private language: string = 'system'
  private t(value: string): string { return localizedSettingsText(value,this.language) }
  @Prop colors: ThemeColors = themeColors()
  client: DshClient = new DshClient()
  @Prop local: boolean = true
  @Prop relay: boolean = false
  @Prop initialPayload: WireObject = {}
  @Prop initialPlugin: string = ''
  getControl: () => Promise<TransportControl> = async () => { throw new Error('本机分享服务不可用') }
  onClose: () => void = () => {}
  onOpenPlugins?: () => void
  onBackHandler?: (handler?: () => boolean) => void
  @State private rows: WireObject[] = []
  @State private selected: string[] = []
  @State private name: string = ''
  @State private pluginOnly: boolean = false
  @State private importing: boolean = false
  @State private result: WireObject = {}
  @State private statuses: WireObject = {}
  @State private backup: string = ''
  @State private needsRestart: boolean = false
  @State private busy: boolean = false
  @State private applying: boolean = false
  @State private applied: boolean = false
  @State private error: string = ''
  @State private notice: string = ''
  @State private detail: WireObject = {}
  @State private ttl: string = '7d'
  private controller?: ProfileShareController
  private service?: ConversationShareClient
  private active: boolean = false
  private generation: number = 0
  aboutToAppear(): void {
    this.active = true; this.importing = !!this.initialPayload['kind']; this.pluginOnly = !!this.initialPlugin
    const service = new ConversationShareClient(this.getControl); this.service = service
    const transport: ProfileShareTransport = { request: (action: string,body: WireObject) => service.request(action,body), cancel: () => service.cancel() }
    const host: ProfileShareHost = { identity: () => this.client.connectionIdentity(), settings: () => this.client.describeSettings(), bundles: () => this.client.listPluginBundles(), presets: () => this.client.listAgentPresets(), request: (method: string,body: WireObject,timeout: number) => this.client.request(method,body,timeout) }
    this.controller = new ProfileShareController(transport,host,this.local,!this.local&&!this.relay)
    this.controller.onChange = () => { if (this.active) this.sync() }; this.onBackHandler?.(() => this.back()); void this.reload()
  }
  aboutToDisappear(): void { this.active = false; this.generation++; this.controller?.close(); this.onBackHandler?.(undefined) }
  private sync(): void {
    const controller = this.controller!; this.rows = profileRows((this.importing ? controller.plan : controller.source)[this.importing ? 'changes' : 'items'])
    this.result = controller.result; this.statuses = controller.statuses; this.backup = controller.backup; this.needsRestart = controller.needsRestart; this.applying = controller.applying
  }
  private back(): boolean {
    if (this.busy) { this.controller?.cancel(); this.notice = this.t('操作已取消，已完成的更改会保留'); if (!this.applying) { this.generation++; this.busy = false }; return true }
    if (this.detail['id']) { this.detail = {}; return true }
    if (this.result['file']) { this.result = {}; return true }
    return false
  }
  private async run(work: () => Promise<void>): Promise<void> {
    if (this.busy || !this.controller?.current()) return
    const generation = ++this.generation; this.busy = true; this.error = ''; this.notice = ''
    try { await work() } catch (error) { if (this.active && generation === this.generation) this.error = error instanceof Error ? error.message : '分享操作失败' }
    finally { if (this.active && generation === this.generation) { this.busy = false; this.applying = false } }
  }
  private async reload(): Promise<void> {
    await this.run(async () => {
      if (this.importing) await this.controller!.preview(this.initialPayload); else await this.controller!.load()
      if (!this.active || !this.controller!.current()) return
      this.selected = this.initialPlugin && !this.importing ? ['plugin:' + this.initialPlugin].filter((id: string) => this.rows.some((row: WireObject) => row['id'] === id && !row['blocked'])) : profileSelection(this.rows)
      this.applied = false
    })
  }
  private toggle(row: WireObject): void {
    const id = string(row['id']); if (row['blocked'] || row['kind'] === 'unchanged' || row['follows']) return
    this.selected = this.selected.includes(id) ? this.selected.filter((value: string) => value !== id) : this.pluginOnly && !this.importing ? [id] : this.selected.concat(id)
  }
  private text(row: WireObject): string {
    if (row['section'] === 'settings' && this.importing) return profileRows(row['diff']).map((diff: WireObject) => strings(diff['path']).join('.') + '\n' + JSON.stringify(diff['from']) + ' → ' + JSON.stringify(diff['to'])).join('\n\n')
    if (row['skill']) return Object.keys(object(object(row['skill'])['files'])).map((name: string) => name + '\n' + string(object(object(row['skill'])['files'])[name])).join('\n\n')
    if (row['text']) return string(row['text'])
    return JSON.stringify(row['plugin'] || row,null,2)
  }
  private confirm(): void {
    const generation = this.generation, controller = this.controller!, selected = this.selected.slice()
    this.getUIContext().showAlertDialog({ title: this.t('导入所选配置？'), message: this.t('只应用勾选的项目。插件会在所选主机运行；设置、技能和 AGENTS.md 会影响之后的对话。已完成的操作不会因取消而撤销。'),
      primaryButton: { value: this.t('取消'), action: () => {} }, secondaryButton: { value: this.t('确认导入'), action: () => {
        if (!this.active || generation !== this.generation || !controller.current()) return
        void this.run(async () => { await controller.apply(selected,true); if (this.active && controller.current()) this.applied = true })
      } } })
  }
  private publish(): void {
    const generation = this.generation, file = string(this.result['file']), ttl = this.ttl
    this.getUIContext().showAlertDialog({ title: this.t('创建加密分享链接？'), message: this.t('内容加密后上传到原版分享服务。任何拿到完整链接的人都能读取内容。请先检查所选内容。'), primaryButton: { value: this.t('取消'), action: () => {} }, secondaryButton: { value: this.t('创建链接'), action: () => {
      if (!this.active || generation !== this.generation) return
      void this.run(async () => { const response = await this.service!.request('upload', { 'file': file, 'ttl': ttl }); if (!this.active || generation + 1 !== this.generation) return
        this.notice = string(object(response['link'])['url']); if (response['recovery']) { this.error = string(response['warning']); this.detail = { 'id': 'recovery', 'text': string(response['recovery']) } }
      })
    } } })
  }
  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) { Button(this.t('返回')).onClick(() => { if (!this.back()) this.onClose() }); Text(this.importing ? this.t('导入配置') : this.t('分享配置')).fontSize(22).fontColor(this.colors.text).layoutWeight(1) }.width('100%')
      if (this.detail['id']) {
        Text(string(this.detail['title']) || string(this.detail['id'])).fontSize(18).fontColor(this.colors.text)
        Scroll() { Text(this.text(this.detail)).fontSize(14).fontColor(this.colors.text).copyOption(CopyOptions.LocalDevice).width('100%') }.layoutWeight(1).width('100%')
      } else if (this.result['file']) {
        Text(this.t('请检查内容后再分享。凭据、账号和本机路径不会包含在配置导出中。')).fontColor(this.colors.muted)
        Scroll() { Text(JSON.stringify(this.result['body'],null,2)).fontSize(13).fontColor(this.colors.text).copyOption(CopyOptions.LocalDevice).width('100%') }.width('100%').layoutWeight(1)
        Row({ space: 8 }) {
          Button(this.t('复制分享码')).layoutWeight(1).onClick(() => { void this.run(async () => { await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,string(this.result['code']))); if (this.active) this.notice = this.t('已复制') }) })
          Button(this.t('保存文件')).layoutWeight(1).onClick(() => { void this.run(async () => { const saved = await saveSharedText(this.getUIContext().getHostContext() as common.UIAbilityContext,this.name||'配置','.dshgo',string(this.result['file'])); if (this.active) this.notice = this.t(saved?'已保存':'已取消保存') }) })
        }.enabled(!this.busy)
        Row({ space: 8 }) { Select([{ value: this.t('7 天') },{ value: this.t('30 天') },{ value: this.t('永久') }]).selected(['7d','30d','forever'].indexOf(this.ttl)).onSelect((index: number) => { this.ttl = ['7d','30d','forever'][index] }); Button(this.t('创建链接')).onClick(() => this.publish()) }.enabled(!this.busy)
      } else {
        Text(this.importing ? this.t('先审阅逐项差异。涉及服务地址、权限、模型和提示文件的项目需要主动勾选。') : this.t('选择配置、固定版本插件与本机技能。请在生成后检查内容。')).fontColor(this.colors.muted).fontSize(14)
        if (!this.importing) {
          TextInput({ text: this.name, placeholder: this.t('配置名称（可选）') }).maxLength(40).onChange((value: string) => { this.name = value }).enabled(!this.busy)
          Row() { Text(this.t('仅分享一个插件')).fontColor(this.colors.text).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.pluginOnly }).onChange((value: boolean) => { this.pluginOnly = value; this.selected = [] }).enabled(!this.busy) }.width('100%')
        }
        List({ space: 8 }) { ForEach(this.rows.filter((row: WireObject) => this.importing || !this.pluginOnly || row['section'] === 'plugins'), (row: WireObject) => {
          ListItem() { Column({ space: 7 }) {
            Row({ space: 8 }) {
              Checkbox({ name: string(row['id']) }).select(this.selected.includes(string(row['id'])) || !!row['follows'] && this.selected.includes(string(row['follows']))).enabled(!this.busy&&!this.applied&&!row['blocked']&&!row['follows']&&row['kind']!=='unchanged').onChange(() => this.toggle(row))
              Text(string(row['title'])).fontColor(this.colors.text).fontSize(17).layoutWeight(1)
              Button(this.t('查看内容')).onClick(() => { this.detail = row })
            }.width('100%')
            if (row['blocked']) Text(this.t(string(row['blocked']))).fontColor(this.colors.danger).fontSize(13).width('100%')
            if (row['detail']) Text(this.t(string(row['detail']))).fontColor(this.colors.muted).fontSize(13).width('100%')
            if (row['sensitive']) Text(this.t('敏感设置：请检查完整的新旧值')).fontColor(this.colors.danger).fontSize(13).width('100%')
            if (row['integrity']) Text(this.t(row['integrity']==='verified'?'插件完整性已核验':row['integrity']==='mismatch'?'插件完整性校验不匹配':'未能核验插件完整性')).fontColor(this.colors.muted).fontSize(13).width('100%')
            if (row['kind'] === 'unchanged') Text(this.t('已是相同版本或状态')).fontColor(this.colors.muted).fontSize(13)
            if (this.statuses[string(row['id'])]) Text(this.t(string(object(this.statuses[string(row['id'])])['state'])) + ' ' + this.t(string(object(this.statuses[string(row['id'])])['detail']))).fontColor(this.colors.muted).fontSize(13).width('100%')
          }.padding(12).width('100%').backgroundColor(this.colors.surface).borderRadius(12) }
        }, (row: WireObject): string => string(row['id'])) }.width('100%').layoutWeight(1)
        if (!this.rows.length && !this.busy) Text(this.t('没有可分享或需要更改的内容')).fontColor(this.colors.muted)
        Row({ space: 8 }) {
          Button(this.t('刷新')).onClick(() => { void this.reload() }).enabled(!this.busy)
          Button(this.importing ? this.t('确认所选更改') : this.t('生成分享码')).layoutWeight(1).enabled(!this.busy&&!this.applied&&this.selected.length>0).onClick(() => { if (this.importing) this.confirm(); else void this.run(() => this.controller!.prepare(this.selected,this.name,this.pluginOnly)) })
        }.width('100%')
        if (this.onOpenPlugins) Button(this.t('打开插件管理')).onClick(() => this.onOpenPlugins?.()).enabled(!this.busy)
        if (this.backup) Text(this.t('本机备份：') + this.backup).fontSize(12).fontColor(this.colors.muted).copyOption(CopyOptions.LocalDevice)
        if (this.needsRestart) Text(this.t('请重启引擎或新建对话，使文件和插件更改生效')).fontColor(this.colors.muted).fontSize(13)
      }
      if (this.busy) Row({ space: 8 }) { LoadingProgress().width(20).height(20); Text(this.t(this.applying?'正在导入…':'正在处理…')).fontColor(this.colors.muted); Button(this.t('取消')).onClick(() => { this.back() }) }
      if (this.error) Text(this.t(this.error)).fontColor(this.colors.danger).fontSize(13).width('100%')
      if (this.notice) Text(this.notice).fontColor(this.colors.muted).fontSize(13).width('100%').copyOption(CopyOptions.LocalDevice)
    }.padding(16).width('100%').height('100%').backgroundColor(this.colors.background)
  }
}
