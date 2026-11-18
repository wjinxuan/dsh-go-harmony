import { localizedSettingsText } from './SettingsLocale'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { writeShareCache } from './ShareCache'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { systemShare } from '@kit.ShareKit'
import { DshClient } from '../dsh/DshClient'
import { array, object, string, DshMessage, WireObject } from '../dsh/DshWire'
import { TransportControl } from '../remote/TransportEndpoint'
import { ThemeColors, themeColors } from './DshTheme'
import { ConversationShareClient, SharedConversation, sharedConversation, sharePictures, saveSharedText } from './ConversationShareData'
import { ConversationReplay } from './ConversationReplay'

@Component
export struct ConversationSharePanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  @Prop source: WireObject = {}
  @Prop sessionId: string = ''
  @Prop initialOnly: string[] = []
  client: DshClient = new DshClient()
  getControl: () => Promise<TransportControl> = async () => { throw new Error(this.t("本机分享服务不可用")) }
  onClose: () => void = () => {}
  onShared: () => void = () => {}
  onBackHandler: (handler?: () => boolean) => void = () => {}
  @State private mode: string = 'all'
  @State private only: string[] = []
  @State private from: string = '1'
  @State private to: string = '1'
  @State private thinking: boolean = true
  @State private tools: boolean = true
  @State private toolOutput: boolean = true
  @State private images: boolean = true
  @State private ttl: string = '7d'
  @State private action: string = ''
  @State private error: string = ''
  @State private notice: string = ''
  @State private replay: string = ''
  @State private link: string = ''
  @State private recovery: string = ''
  private service?: ConversationShareClient
  private active: boolean = false
  private generation: number = 0
  private shareController?: systemShare.ShareController
  private completed?: (value: systemShare.ShareOperationResult) => void
  private dismissed?: () => void
  aboutToAppear(): void {
    this.active = true; this.service = new ConversationShareClient(this.getControl)
    this.to = this.messages().filter((m: DshMessage) => m.role === 'user').length.toString()
    this.only = this.initialOnly.slice(); if (this.only.length) this.mode = 'messages'
    this.onBackHandler(() => this.back())
  }
  aboutToDisappear(): void { this.active = false; this.generation++; this.service?.cancel(); this.releaseShare(); this.onBackHandler(undefined) }
  private releaseShare(): void {
    try { if (this.completed) this.shareController?.off('shareCompleted', this.completed) } catch { /* Platform event is optional. */ }
    try { if (this.dismissed) this.shareController?.off('dismiss', this.dismissed) } catch { /* Platform event is optional. */ }
    this.shareController = undefined
  }
  private back(): boolean {
    if (this.action) { this.generation++; this.service?.cancel(); this.action = ''; this.notice = this.t("已取消分享操作"); return true }
    if (this.replay) { this.replay = ''; return true }
    if (this.recovery) { this.error = this.t("请先保存链接恢复凭据，再离开此页。"); return true }
    return false
  }
  private messages(): DshMessage[] { return (this.source['messages'] as DshMessage[] || []).filter((m: DshMessage) => m.seq !== undefined) }
  private options(): WireObject {
    const options: WireObject = { 'thinking': this.thinking, 'tools': this.tools, 'toolOutput': this.toolOutput, 'images': this.images }
    if (this.mode === 'range') { options['from'] = Number(this.from); options['to'] = Number(this.to) }
    if (this.mode === 'messages') options['only'] = this.only
    return options
  }
  private selectedMessages(): DshMessage[] {
    const messages = this.messages()
    if (this.mode === 'messages') return messages.filter((m: DshMessage) => this.only.includes(m.id))
    if (this.mode !== 'range') return messages
    const prompts = messages.filter((m: DshMessage) => m.role === 'user')
    const lo = prompts[Number(this.from) - 1]?.seq, hi = prompts[Number(this.to)]?.seq ?? Number.MAX_SAFE_INTEGER
    return lo === undefined ? [] : messages.filter((m: DshMessage) => (m.seq ?? -1) >= lo && (m.seq ?? -1) < hi)
  }
  private async prepare(current: () => boolean): Promise<SharedConversation> {
    const pictures = this.images ? await sharePictures(this.client, this.sessionId, this.selectedMessages(), current) : []
    if (!current()) throw new Error(this.t("分享操作已取消"))
    return sharedConversation(await this.service!.request('prepare', { 'source': this.source, 'options': this.options(), 'images': pictures }))
  }
  private async begin(action: string): Promise<void> {
    if (this.action || !this.service) return
    const generation = ++this.generation, identity = this.client.connectionIdentity()
    const current = (): boolean => this.active && generation === this.generation && identity === this.client.connectionIdentity()
    this.action = action; this.error = ''; this.notice = ''; this.link = ''
    try {
      const result = await this.prepare(current)
      if (!current()) return
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      if (action === 'preview') this.replay = result.html
      else if (action === 'code') { await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, result.code)); this.notice = this.t("已复制分享码"); this.onShared() }
      else if (action === 'file' || action === 'html') {
        const saved = await saveSharedText(context, string(result.body['title']), action === 'html' ? '.html' : '.dshgo', action === 'html' ? result.html : result.file)
        if (current()) { this.notice = saved ? this.t("已保存分享文件") : this.t("已取消保存"); if (saved) this.onShared() }
      } else if (action === 'share') await this.shareFile(context, result, current)
      else if (action === 'link') {
        const response = await this.service.request('upload', { 'file': result.file, 'ttl': this.ttl })
        if (current()) {
          this.link = string(object(response['link'])['url']); this.recovery = string(response['recovery'])
          this.notice = string(response['warning']) || this.t("加密链接已创建。密钥只在链接片段中，请仅发给需要查看的人。"); this.onShared()
        }
      }
    } catch (error) { if (current()) this.error = error instanceof Error ? error.message : this.t("分享失败，请重试") }
    finally { if (this.active && generation === this.generation) this.action = '' }
  }
  private async shareFile(context: common.UIAbilityContext, result: SharedConversation, current: () => boolean): Promise<void> {
    this.releaseShare()
    const path = await writeShareCache(context.cacheDir, result.file)
    if (!current()) { await fileIo.unlink(path); return }
    const record: systemShare.SharedRecord = { utd: 'general.file', uri: fileUri.getUriFromPath(path), title: string(result.body['title']) + '.dshgo' }
    const controller = new systemShare.ShareController(new systemShare.SharedData(record)); this.shareController = controller
    let completed = false
    this.completed = (): void => { completed = true; if (current()) { this.notice = this.t("系统已确认分享完成"); this.onShared() } }
    this.dismissed = (): void => { if (current() && !completed) this.notice = this.t("分享面板已关闭") }
    try { controller.on('shareCompleted', this.completed); controller.on('dismiss', this.dismissed) } catch { /* Older devices omit optional events. */ }
    try { await controller.show(context, { selectionMode: systemShare.SelectionMode.SINGLE, previewMode: systemShare.SharePreviewMode.DEFAULT }) }
    catch { if (!completed) { await fileIo.unlink(path); throw new Error(this.t("系统未能打开分享面板")) } }
  }
  private async saveRecovery(): Promise<void> {
    try {
      if (await saveSharedText(this.getUIContext().getHostContext() as common.UIAbilityContext, this.t("分享链接恢复凭据"), '.json', this.recovery)) { this.recovery = ''; this.notice = this.t("已保存恢复凭据") }
    } catch { this.error = this.t("恢复凭据保存失败，请重试") }
  }
  @Builder private toggle(label: string, value: boolean, change: (value: boolean) => void) {
    Row() { Text(label).fontColor(this.colors.text).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: value }).onChange(change).selectedColor(this.colors.primary) }.width('100%').padding({ top: 6, bottom: 6 })
  }
  build() {
    if (this.replay) ConversationReplay({ colors: this.colors, html: this.replay, onClose: () => { this.replay = '' } })
    else Column({ space: 12 }) {
      Row() { Button(this.t("返回")).onClick(() => { if (!this.back()) this.onClose() }); Text(this.t("分享对话")).fontSize(22).fontColor(this.colors.text).layoutWeight(1) }.width('100%')
      Scroll() {
        Column({ space: 12 }) {
          Text(this.t("已加载的消息和回合")).fontSize(14).fontColor(this.colors.muted).width('100%')
          Row({ space: 8 }) { ForEach(['all', 'range', 'messages'], (value: string) => {
            Button(value === 'all' ? this.t("全部") : value === 'range' ? this.t("回合范围") : this.t("选择消息")).backgroundColor(this.mode === value ? this.colors.primary : this.colors.surface)
              .fontColor(this.mode === value ? Color.White : this.colors.text).onClick(() => { this.mode = value })
          }) }.width('100%')
          if (this.mode === 'range') Row({ space: 8 }) {
            TextInput({ text: this.from, placeholder: this.t("起始回合") }).type(InputType.Number).layoutWeight(1).onChange((v: string) => { this.from = v })
            Text(this.t("至")).fontColor(this.colors.muted)
            TextInput({ text: this.to, placeholder: this.t("结束回合") }).type(InputType.Number).layoutWeight(1).onChange((v: string) => { this.to = v })
          }
          if (this.mode === 'messages') ForEach(this.messages(), (message: DshMessage) => {
            Row({ space: 10 }) {
              Checkbox().select(this.only.includes(message.id)).onChange((checked: boolean) => { this.only = checked ? this.only.concat(message.id) : this.only.filter((id: string) => id !== message.id) })
              Text((message.role === 'user' ? this.t("你：") : this.t("助手：")) + message.text).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).fontSize(14).fontColor(this.colors.text).layoutWeight(1)
            }.width('100%').padding(8)
          }, (message: DshMessage): string => message.id)
          this.toggle(this.t("思考过程"), this.thinking, (v: boolean) => { this.thinking = v })
          this.toggle(this.t("工具、目标与待办"), this.tools, (v: boolean) => { this.tools = v })
          if (this.tools) this.toggle(this.t("工具输出"), this.toolOutput, (v: boolean) => { this.toolOutput = v })
          this.toggle(this.t("附带图片"), this.images, (v: boolean) => { this.images = v })
          Text(this.t("分享前会遮挡识别到的凭据和私人路径；请预览并确认内容。回复中的外链图片不会加载。")).fontSize(13).fontColor(this.colors.muted).width('100%')
          Button(this.t("预览与回放")).width('100%').onClick(() => { void this.begin('preview') })
          Row({ space: 8 }) { Button(this.t("分享文件")).layoutWeight(1).onClick(() => { void this.begin('share') }); Button(this.t("复制分享码")).layoutWeight(1).onClick(() => { void this.begin('code') }) }.width('100%')
          Row({ space: 8 }) { Button(this.t("保存 .dshgo")).layoutWeight(1).onClick(() => { void this.begin('file') }); Button(this.t("导出为网页")).layoutWeight(1).onClick(() => { void this.begin('html') }) }.width('100%')
          Select([{ value: this.t("7 天") }, { value: this.t("30 天") }, { value: this.t("永久") }]).selected(['7d', '30d', 'forever'].indexOf(this.ttl)).value(this.ttl === 'forever' ? this.t("永久") : this.ttl === '30d' ? this.t("30 天") : this.t("7 天"))
            .onSelect((i: number) => { this.ttl = ['7d', '30d', 'forever'][i] })
          Button(this.t("创建加密链接")).width('100%').onClick(() => { void this.begin('link') })
        }.width('100%').enabled(!this.action && !this.recovery)
      }.width('100%').layoutWeight(1)
      if (this.action) Row({ space: 8 }) { LoadingProgress().width(20).height(20); Text(this.t("正在准备分享…")).fontColor(this.colors.muted); Button(this.t("取消")).onClick(() => { this.back() }) }
      if (this.link) Button(this.t("复制加密链接")).onClick(async () => { await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.link)); this.notice = this.t("链接已复制") })
      if (this.recovery) Button(this.t("保存链接恢复凭据")).onClick(() => { void this.saveRecovery() })
      if (this.notice) Text(this.notice).fontSize(13).fontColor(this.colors.muted).width('100%')
      if (this.error) Text(this.t(this.error)).fontSize(13).fontColor(this.colors.danger).width('100%')
    }.padding(16).width('100%').height('100%')
  }
}
