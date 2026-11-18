import { ProfileSharePanel } from './ProfileSharePanel'
import { DshClient } from '../dsh/DshClient'
import { localizedSettingsText } from './SettingsLocale'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { TransportControl } from '../remote/TransportEndpoint'
import { ThemeColors, themeColors } from './DshTheme'
import { ConversationShareClient, sharedConversation, SharedConversation, SharedLink, sharedLinks,
  shareLinkInput, readSharedFile, saveSharedText } from './ConversationShareData'
import { string, WireObject } from '../dsh/DshWire'
import { ConversationReplay } from './ConversationReplay'
import { inlineShareCode } from './ShareLaunchData'

@Component
export struct ConversationImportPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  client: DshClient = new DshClient()
  @Prop local: boolean = true
  @Prop relay: boolean = false
  onOpenPlugins?: () => void
  @State private profile: WireObject = {}
  private profileBack?: () => boolean
  @Prop colors: ThemeColors = themeColors()
  @Prop initialTab: string = 'import'
  @Prop initialInput: string = ''
  @Prop initialFile: string = ''
  getControl: () => Promise<TransportControl> = async () => { throw new Error(this.t("本机分享服务不可用")) }
  onClose: () => void = () => {}
  onBackHandler: (handler?: () => boolean) => void = () => {}
  @State private tab: string = 'import'
  @State private text: string = ''
  @State private result: SharedConversation | undefined = undefined
  @State private replay: boolean = false
  @State private busy: boolean = false
  @State private error: string = ''
  @State private notice: string = ''
  @State private links: SharedLink[] = []
  private service?: ConversationShareClient
  private active: boolean = false
  private generation: number = 0
  aboutToAppear(): void {
    this.active = true; this.tab = this.initialTab; this.text = this.initialInput
    this.service = new ConversationShareClient(this.getControl); this.onBackHandler(() => this.back())
    if (this.tab === 'links') void this.refreshLinks()
    if (this.initialFile) void this.readFile(this.initialFile)
  }
  aboutToDisappear(): void { this.active = false; this.generation++; this.service?.cancel(); this.onBackHandler(undefined) }
  private back(): boolean {
    if (this.profile['kind']) { if (this.profileBack?.()) return true; this.profile = {}; return true }
    if (this.busy) { this.generation++; this.service?.cancel(); this.busy = false; this.notice = this.t("操作已取消"); return true }
    if (this.replay) { this.replay = false; return true }
    if (this.result) { this.result = undefined; return true }
    return false
  }
  private async run(work: () => Promise<void>): Promise<void> {
    if (this.busy) return
    const generation = ++this.generation; this.busy = true; this.error = ''; this.notice = ''
    try { await work() } catch (error) { if (this.active && generation === this.generation) this.error = error instanceof Error ? error.message : this.t("操作失败") }
    finally { if (this.active && generation === this.generation) this.busy = false }
  }
  private async decode(text: string): Promise<void> {
    const generation = this.generation, link = shareLinkInput(text)
    const body: WireObject = link ? { 'link': link } : { 'text': inlineShareCode(text) || text }
    const response = await this.service!.request('decode', body)
    if (!this.active || generation !== this.generation) return
    const payload = response['body'] as WireObject
    if (payload['kind'] === 'plugin' || payload['kind'] === 'profile') { this.profile = payload; this.result = undefined; return }
    this.result = sharedConversation(response); this.replay = false
  }
  private async readFile(uri: string = ''): Promise<void> {
    await this.run(async () => {
      const generation = this.generation
      const text = await readSharedFile(this.getUIContext().getHostContext() as common.UIAbilityContext, uri)
      if (text && this.active && generation === this.generation) await this.decode(text)
    })
  }
  private async refreshLinks(): Promise<void> {
    await this.run(async () => {
      const generation = this.generation, links = sharedLinks(await this.service!.request('links'))
      if (this.active && generation === this.generation) this.links = links
    })
  }
  private confirmDelete(link: SharedLink): void {
    this.getUIContext().showAlertDialog({ title: this.t("删除分享链接？"), message: this.t("删除后此链接将无法打开，原会话和已下载的文件不受影响。"),
      primaryButton: { value: this.t("取消"), action: () => {} }, secondaryButton: { value: this.t("删除"), action: () => {
        void this.run(async () => {
          const generation = this.generation
          await this.service!.request('delete', { 'id': link.id })
          if (this.active && generation === this.generation) { this.links = this.links.filter((item: SharedLink) => item.id !== link.id); this.notice = this.t("链接已删除") }
        })
      } } })
  }
  private async paste(): Promise<void> {
    await this.run(async () => {
      const generation = this.generation, data = await pasteboard.getSystemPasteboard().getData()
      if (this.active && generation === this.generation) this.text = data.getPrimaryText().slice(0, 6 * 1024 * 1024)
    })
  }
  build() {
    if (this.profile['kind']) ProfileSharePanel({ colors: this.colors, client: this.client, local: this.local, relay: this.relay, initialPayload: this.profile, getControl: this.getControl, onOpenPlugins: this.onOpenPlugins, onClose: () => { this.profile = {} }, onBackHandler: (handler?: () => boolean) => { this.profileBack = handler } })
    else if (this.replay && this.result) ConversationReplay({ colors: this.colors, html: this.result.html, onClose: () => { this.replay = false } })
    else Column({ space: 12 }) {
      Row() { Button(this.t("返回")).onClick(() => { if (!this.back()) this.onClose() }); Text(this.tab === 'links' ? this.t("分享链接") : this.t("打开分享")).fontSize(22).fontColor(this.colors.text).layoutWeight(1) }.width('100%')
      if (this.result) {
        Text(string(this.result.body['title'])).fontSize(21).fontColor(this.colors.text).width('100%')
        Text(this.t("只读会话，打开不会安装插件、运行工具或改动当前会话。")).fontSize(14).fontColor(this.colors.muted).width('100%')
        Button(this.t("阅读与回放")).width('100%').onClick(() => { this.replay = true })
        Button(this.t("保存会话文件")).width('100%').onClick(() => { void this.run(async () => {
          const result = this.result
          if (result) this.notice = await saveSharedText(this.getUIContext().getHostContext() as common.UIAbilityContext, string(result.body['title']), '.dshgo', result.file) ? this.t("已保存") : this.t("已取消保存")
        }) })
        Blank()
      } else if (this.tab === 'links') {
        Button(this.t("刷新")).onClick(() => { void this.refreshLinks() }).enabled(!this.busy)
        List({ space: 8 }) {
          ForEach(this.links, (link: SharedLink) => {
            ListItem() { Column({ space: 8 }) {
              Text(link.title || this.t("对话")).fontSize(17).fontColor(this.colors.text).width('100%')
              Text(link.expiresAt ? this.t("有效期至 ") + link.expiresAt : this.t("永久链接")).fontSize(12).fontColor(this.colors.muted).width('100%')
              Row({ space: 8 }) {
                Button(this.t("打开")).onClick(() => { void this.run(() => this.decode(link.url)) })
                Button(this.t("复制链接")).onClick(() => { void this.run(async () => {
                  await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, link.url)); this.notice = this.t("链接已复制")
                }) })
                Button(this.t("删除")).fontColor(this.colors.danger).onClick(() => { this.confirmDelete(link) })
              }.width('100%')
            }.padding(14).width('100%').backgroundColor(this.colors.surface).borderRadius(12) }
          }, (link: SharedLink): string => link.id)
        }.width('100%').layoutWeight(1).enabled(!this.busy)
        if (!this.links.length && !this.busy) Text(this.t("还没有此设备创建的分享链接")).fontColor(this.colors.muted)
      } else {
        Text(this.t("粘贴会话、插件或配置分享码，也可以打开加密链接或 .dshgo 文件。")).fontSize(14).fontColor(this.colors.muted).width('100%')
        TextArea({ text: this.text, placeholder: this.t("分享码或链接") }).layoutWeight(1).onChange((value: string) => { this.text = value }).enabled(!this.busy)
        Row({ space: 8 }) {
          PasteButton({ icon: PasteIconStyle.LINES, text: PasteDescription.PASTE }).width(120).onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => { if (result === PasteButtonOnClickResult.SUCCESS) void this.paste(); else this.error = this.t('未能获得本次剪贴板访问授权。') })
          Button(this.t("选择文件")).layoutWeight(1).onClick(() => { void this.readFile() })
        }.width('100%').enabled(!this.busy)
        Button(this.t("打开")).width('100%').enabled(!!this.text.trim() && !this.busy).onClick(() => { void this.run(() => this.decode(this.text)) })
      }
      if (this.busy) Row({ space: 8 }) { LoadingProgress().width(20).height(20); Text(this.t("正在处理…")).fontColor(this.colors.muted); Button(this.t("取消")).onClick(() => { this.back() }) }
      if (this.notice) Text(this.notice).fontSize(13).fontColor(this.colors.muted).width('100%')
      if (this.error) Text(this.t(this.error)).fontSize(13).fontColor(this.colors.danger).width('100%')
    }.padding(16).width('100%').height('100%')
  }
}
