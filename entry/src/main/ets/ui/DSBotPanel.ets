import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { MessageBody } from './MessageBody'
import { DshModelInfo, DshReasoningEffort } from '../dsh/DshWire'
import { DshClient } from '../dsh/DshClient'
import { number, object, string, strings, WireObject } from '../dsh/DshWire'
import { DSBotHub, DSBotScope, dsBotBotPayload, dsBotMention, dsBotEntries, dsBotFailure, dsBotMemoryTarget, dsBotRoomPayload, dsBotSession, dsBotWork } from './DSBotData'
import { createDSBotHub } from './DSBotNative'
import { DSBotCards } from './DSBotCards'
import { ThemeColors, themeColors } from './DshTheme'
import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'

@Component
export struct DSBotPanel {
  @StorageProp('dshLanguage') private language: string = 'system'
  @Prop colors: ThemeColors = themeColors()
  client: DshClient = new DshClient()
  hub?: DSBotHub
  @Prop hostScope: string = 'local'
  @Prop rpc: boolean = false
  @Prop initialId: string = ''
  @Prop initialRoom: boolean = false
  private initialOpened: boolean = false
  onClose: () => void = () => {}
  onOpenPlugins: (name: string) => void = () => {}
  onOpenWeb: () => void = () => {}
  onOpenSession: (id: string) => void = () => {}
  @Prop bundledAvailable: boolean = false
  @Prop bundledEnabled: boolean = false
  @Prop bundledRestart: boolean = false
  onBundledChange?: (enabled: boolean) => Promise<void>
  onBackHandler?: (handler?: () => boolean) => void
  private owned: boolean = false
  private active: boolean = false
  private stop?: () => void
  private version: number = 0
  private pageEpoch: number = 0
  private editorScope?: DSBotScope
  private editorPrevious: WireObject = {}
  @State private revision: number = 0
  @State private page: string = 'team'
  @State private team: WireObject = {}
  @State private live: WireObject = {}
  @State private status: string = 'connecting'
  @State private error: string = ''
  @State private busy: boolean = false
  @State private selected: string = ''
  @State private room: boolean = false
  @State private draft: string = ''
  @State private caretStart: number = 0
  @State private caretEnd: number = 0
  private inputController: TextAreaController = new TextAreaController()
  private chatScroll: Scroller = new Scroller()
  @State private models: DshModelInfo[] = []
  private resourceTimer: number = -1
  @State private form: WireObject = {}
  @State private items: WireObject[] = []
  @State private images: WireObject = {}
  @State private memory: WireObject = {}
  @State private memoryText: string = ''
  @State private memoryScope: string = 'own'
  @State private memoryEditing: WireObject | undefined = undefined
  @State private usage: WireObject = {}
  @State private folders: WireObject = {}
  @State private fullText: string = ''
  @State private fullWhole: boolean = true
  private t(value: string): string { return localizedSettingsText(value,this.language) }
  private f(value: string,args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value,args,this.language) }
  private s(value: WireObject,key: string): string { return string(value[key]) }
  private entity(): WireObject { return this.hub?.entity(this.selected,this.room) || {} }
  private canWrite(): boolean { return !this.busy && this.hub?.writable() === true }
  private scope(): DSBotScope { return this.hub?.scope(this.selected,this.room) || { epoch: -1, boot: '', id: '', room: false, session: '' } }
  aboutToAppear(): void { this.active = true; this.onBackHandler?.(() => this.back()); void this.open() }
  aboutToDisappear(): void { this.active = false; clearTimeout(this.resourceTimer); this.version++; this.pageEpoch++; this.stop?.(); this.onBackHandler?.(undefined); this.hub?.viewingChat(''); if (this.owned) this.hub?.close() }
  private async open(): Promise<void> {
    const version = ++this.version
    try {
      if (!this.hub) { const hub = await createDSBotHub(this.client,this.getUIContext().getHostContext() as common.UIAbilityContext,this.hostScope,() => this.language === 'en' ? 'en-US' : 'zh-CN',this.rpc); if (!this.active || version !== this.version) { hub.close(); return }; this.hub = hub; this.owned = true }
      this.stop = this.hub.subscribe(() => this.sync()); this.sync(); if (this.hub.availability === 'connecting') await this.hub.start(); else this.hub.kick()
    } catch (error) { if (this.active && version === this.version) { this.status = 'failed'; this.error = dsBotFailure(error as Error) } }
  }
  private sync(): void {
    if (!this.active || !this.hub) return
    if (!this.initialOpened && this.initialId && this.hub.availability === 'ready' && this.hub.entity(this.initialId,this.initialRoom)) { this.initialOpened = true; void this.showChat(this.initialId,this.initialRoom) }
    this.revision++; this.team = this.hub.team; this.live = this.hub.live; this.status = this.hub.availability; this.items = this.hub.chatItems.slice()
    if (this.hub.failure) this.error = this.hub.failure
    if (this.selected && !this.hub.entity(this.selected,this.room) && this.status === 'ready' && this.page !== 'editor') { this.page = 'team'; this.selected = ''; this.draft = '' }
  }
  private back(): boolean {
    if (this.page === 'team') return false
    clearTimeout(this.resourceTimer); this.pageEpoch++; this.error = ''; this.memoryEditing = undefined
    if (['memory','usage','folders','editor'].includes(this.page) && this.selected) this.page = 'details'
    else if (this.page === 'full') this.page = 'chat'
    else if (this.page === 'details') this.page = 'chat'
    else { this.page = 'team'; this.selected = ''; this.draft = ''; this.hub?.closeChat() }
    return true
  }
  private async showChat(id: string,room: boolean): Promise<void> { this.pageEpoch++; this.selected = id; this.room = room; this.page = 'chat'; this.draft = ''; this.error = ''; await this.hub?.openChat(id,room); this.sync() }
  private async run(action: () => Promise<void>): Promise<void> { if (this.busy) return; this.busy = true; this.error = ''; const version = this.version; try { await action() } catch (error) { if (this.active && version === this.version) this.error = dsBotFailure(error as Error) } finally { if (this.active && version === this.version) { this.busy = false; this.sync() } } }
  private confirm(title: string,body: string,action: () => Promise<void>): void { this.getUIContext().showAlertDialog({ title: title, message: body, primaryButton: { value: this.t('取消'), action: () => {} }, secondaryButton: { value: this.t('确认'), action: () => { void this.run(action) } } }) }
  private async send(): Promise<void> { const hub = this.hub, scope = this.scope(), text = this.draft, epoch = this.pageEpoch; if (!hub) return; await this.run(async () => { const accepted = await hub.send(text,scope); if (accepted && epoch === this.pageEpoch && this.draft === text) { this.draft = ''; setTimeout(() => { if (this.active) this.chatScroll.scrollEdge(Edge.Bottom) },60) } }) }
  private async edit(create: boolean,room: boolean = this.room): Promise<void> {
    if (!this.hub) return
    this.pageEpoch++; this.room = room; this.editorScope = create ? this.hub.scope() : this.scope(); this.editorPrevious = create ? {} : this.entity(); this.page = 'editor'; this.error = ''
    const previous = this.editorPrevious, form: WireObject = {}
    if (create) { form['name'] = ''; form['members'] = []; form['admin'] = ''; form['greet'] = true; form['color'] = 'blue'; form['model'] = string(this.team['defaultModel']); form['effort'] = '' }
    else { for (const key of Object.keys(previous)) form[key] = previous[key]; form['relayLimit'] = previous['relayLimit'] === null || previous['relayLimit'] === undefined ? '' : String(previous['relayLimit']) }
    this.form = form
    if (!room) { const epoch = this.pageEpoch; try { const catalog = await this.client.listModels(); if (this.active && epoch === this.pageEpoch) this.models = catalog.groups.flatMap((group) => group.models) } catch { if (this.active && this.page === 'editor') this.error = '无法读取模型可用的思考力度。' } }
  }
  private efforts(): DshReasoningEffort[] { const model = this.models.find((item: DshModelInfo) => item.provider + '/' + item.id === this.form['model']); return model?.efforts || [] }
  private set(key: string,value: Object): void { const next: WireObject = {}; for (const name of Object.keys(this.form)) next[name] = this.form[name]; next[key] = value; if (key === 'model' && this.form['model'] !== value) next['effort'] = ''; this.form = next }
  private async save(): Promise<void> {
    const hub = this.hub, scope = this.editorScope, room = this.room, epoch = this.pageEpoch; if (!hub || !scope) return
    const creating = !scope.id
    let payload: WireObject
    try { payload = room ? dsBotRoomPayload(this.form,creating ? undefined : this.editorPrevious) : dsBotBotPayload(this.form,creating); if (!creating) payload['id'] = scope.id }
    catch (error) { this.error = (error as Error).message; return }
    await this.run(async () => { const result = object(await hub.write((creating ? 'create-' : 'update-')+(room ? 'room' : 'bot'),payload,scope)); if (!this.active || epoch !== this.pageEpoch || !hub.current()) return; const id = creating ? string(result['id']) : scope.id; if (id && hub.entity(id,room)) await this.showChat(id,room); else { this.page = 'team'; this.selected = '' } })
  }
  private mutate(endpoint: string,payload: WireObject): void { const hub = this.hub,scope = this.scope(); if (hub) void this.run(async () => { await hub.write(endpoint,payload,scope) }) }
  private async details(): Promise<void> { this.pageEpoch++; this.page = 'details'; this.error = ''; const hub = this.hub, scope = this.scope(); if (!hub || this.room || this.images[this.selected]) return; try { const value = object(await hub.read('avatar',{ 'botId': scope.id },scope)); const image = string(value['image']); if (hub.same(scope) && /^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/.test(image) && image.length < 2097152) { const next: WireObject = {}; for (const key of Object.keys(this.images)) next[key] = this.images[key]; next[scope.id] = image; this.images = next } } catch {} }
  private async resource(page: string, refresh: boolean = false): Promise<void> {
    const hub = this.hub,scope = this.scope(), epoch = ++this.pageEpoch; if (!hub) return
    this.page = page; this.error = ''; if (page === 'memory' && !refresh) { this.memory = {}; this.memoryText = ''; this.memoryEditing = undefined; this.memoryScope = this.room ? 'group' : 'own' }; if (page === 'usage' && !refresh) this.usage = {}
    await this.run(async () => { const payload: WireObject = page === 'folders' ? {} : dsBotMemoryTarget(scope.id,scope.room); const value = object(await hub.read(page === 'memory' ? 'memory-view' : page === 'usage' ? 'usage-summary' : 'folders',payload,scope)); if (epoch === this.pageEpoch) { if (page === 'memory') this.memory = value; else if (page === 'usage') this.usage = value; else this.folders = value; if (page === 'memory' && value['summarizing'] === true || page === 'usage' && value['scanning'] === true) { clearTimeout(this.resourceTimer); this.resourceTimer = setTimeout(() => { if (this.active && epoch === this.pageEpoch) void this.resource(page,true) },1500) } } })
  }
  private async memorySave(): Promise<void> {
    const hub = this.hub,scope = this.scope(), epoch = this.pageEpoch, entry = this.memoryEditing, text = this.memoryText.trim(); if (!hub || !text) return
    if (entry && !hub.supports('memory-edit')) return
    const payload = dsBotMemoryTarget(scope.id,scope.room); payload['scope'] = entry ? entry['scope'] : this.memoryScope; payload['text'] = entry ? entry['text'] : text
    if (entry) { payload['topic'] = entry['topic'] ?? null; payload['next'] = text }
    await this.run(async () => { const value = object(await hub.write(entry ? 'memory-edit' : 'memory-add',payload,scope)); if (epoch === this.pageEpoch && hub.same(scope)) { this.memory = value; this.memoryText = ''; this.memoryEditing = undefined } })
  }
  private forget(entry: WireObject): void { const hub = this.hub,scope = this.scope(),epoch = this.pageEpoch; if (!hub) return; const payload = dsBotMemoryTarget(scope.id,scope.room); payload['scope'] = entry['scope']; payload['topic'] = entry['topic'] ?? null; payload['text'] = entry['text']; this.confirm(this.t('删除这条记忆？'),this.s(entry,'text'),async () => { const value = object(await hub.write('memory-forget',payload,scope)); if (epoch === this.pageEpoch && hub.same(scope)) this.memory = value }) }
  private async full(item: WireObject): Promise<void> { const hub = this.hub,scope = this.scope(),epoch = ++this.pageEpoch; if (!hub) return; this.page = 'full'; this.fullText = ''; this.fullWhole = true; await this.run(async () => { const value = await hub.read('file-text',{ 'file': object(object(item['whole'])['file']) },scope); if (epoch === this.pageEpoch) { this.fullText = typeof value === 'string' ? value : string(object(value)['text']); this.fullWhole = object(value)['whole'] !== false } }) }
  private orderedBots(): WireObject[] { const main = strings(this.team['mainBotIds']); return dsBotEntries(this.team['bots']).sort((a: WireObject,b: WireObject) => { const left = main.indexOf(string(a['id'])), right = main.indexOf(string(b['id'])); if (left >= 0 || right >= 0) return left >= 0 && right >= 0 ? left-right : left >= 0 ? -1 : 1; return number(this.hub?.latest.get(string(b['id']))?.['time'],number(b['createdAt'],0))-number(this.hub?.latest.get(string(a['id']))?.['time'],number(a['createdAt'],0)) }) }
  private approvals(): WireObject[] { return dsBotEntries(object(this.live['work'])['approvals']).filter((row: WireObject) => this.room ? row['roomId'] === this.selected : row['botId'] === this.selected && !row['roomId']) }
  private mentionOptions(): WireObject[] {
    const active = dsBotMention(this.draft,this.caretStart,this.caretEnd); if (!active) return []
    const query = active.query.toLowerCase(), members = strings(this.entity()['members']),admin = this.entity()['admin']
    const result: WireObject[] = dsBotEntries(this.team['bots']).filter((bot: WireObject) => members.includes(string(bot['id'])) && string(bot['name']).toLowerCase().includes(query)).sort((a: WireObject,b: WireObject) => a['id'] === admin ? -1 : b['id'] === admin ? 1 : 0).map((bot: WireObject): WireObject => ({ 'label': bot['name'], 'insert': '@'+string(bot['name']) }))
    if (!query || ['all','everyone','所有人',this.t('所有人').toLowerCase()].some((name: string) => name.includes(query))) result.push({ 'label': this.t('所有人'), 'insert': '@所有人' })
    return result
  }
  private pickMention(value: string): void { const active = dsBotMention(this.draft,this.caretStart,this.caretEnd); if (!active) return; this.draft = this.draft.substring(0,active.start)+value+' '+this.draft.substring(active.end); this.caretStart = active.start+value.length+1; this.caretEnd = this.caretStart; this.inputController.caretPosition(this.caretStart) }
  private total(row: WireObject): number { return number(row['input'],0)+number(row['cacheRead'],0)+number(row['cacheWrite'],0)+number(row['output'],0) }
  @Builder private heading(label: string) { Text(this.t(label)).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%').margin({ top: 12 }) }
  @Builder private field(label: string,key: string,multi: boolean = false) {
    Text(this.t(label)).fontSize(13).fontColor(this.colors.muted).width('100%')
    if (multi) TextArea({ text: this.s(this.form,key) }).height(120).onChange((value: string) => this.set(key,value)).enabled(!this.busy)
    else TextInput({ text: this.s(this.form,key) }).onChange((value: string) => this.set(key,value)).enabled(!this.busy)
  }
  @Builder private unavailable() {
    if (this.status === 'connecting') LoadingProgress().width(32).height(32)
    else {
      Text(this.t(this.status === 'missing' ? '此主机尚未安装或启用 DS Bot。' : this.status === 'outdated' ? '此版本 DS Bot 不支持移动端 API。' : this.status === 'relay' ? '中继未开放 DS Bot，请通过 SSH 连接。' : this.status === 'offline' ? '请先连接主机。' : '无法读取 DS Bot 团队。')).fontColor(this.colors.muted).width('100%')
      Button(this.t('重试')).onClick(() => { void this.hub?.start() })
      Button(this.t('在网页中打开')).onClick(this.onOpenWeb)
      if (this.status === 'missing' || this.status === 'outdated') {
        Button(this.t('安装或管理 DS Bot')).onClick(() => this.onOpenPlugins('ds-bot'))
        Text('dsh plugin --profile web add ds-bot').fontFamily('monospace').copyOption(CopyOptions.LocalDevice).fontColor(this.colors.text)
        Button(this.t('复制命令')).onClick(() => { void pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,'dsh plugin --profile web add ds-bot')) })
      }
    }
  }
  @Builder private teamPage() {
    if (this.status !== 'ready') this.unavailable()
    else {
      this.heading('Bot')
      ForEach(this.orderedBots(),(bot: WireObject) => {
        Button() { Column({ space: 4 }) { Text((strings(this.team['mainBotIds']).includes(this.s(bot,'id')) ? '★ ' : '')+this.s(bot,'name')).fontColor(this.colors.text).width('100%'); Text(this.s(this.hub?.latest.get(this.s(bot,'id')) || {},'text') || this.s(bot,'role') || this.t('还没有对话')).maxLines(2).fontColor(this.colors.muted).width('100%'); if (this.hub?.unread.get(this.s(bot,'id'))) Text(String(this.hub?.unread.get(this.s(bot,'id')))).fontColor(this.colors.primary); if (dsBotWork(this.live,this.s(bot,'id'),false).length) Text(this.t('正在工作')).fontColor(this.colors.primary) } }.padding(12).backgroundColor(this.colors.surfaceAlt).borderRadius(12).width('100%').onClick(() => { void this.showChat(this.s(bot,'id'),false) })
      },(bot: WireObject) => this.s(bot,'id'))
      Button(this.t('新建 Bot')).enabled(this.canWrite()).onClick(() => { this.selected = ''; void this.edit(true,false) })
      this.heading('群聊')
      ForEach(dsBotEntries(this.team['rooms']),(room: WireObject) => {
        Button() { Column({ space: 4 }) { Text(this.s(room,'name')).fontColor(this.colors.text).width('100%'); Text(this.s(this.hub?.latest.get(this.s(room,'id')) || {},'text') || this.s(room,'preview')).maxLines(2).fontColor(this.colors.muted).width('100%'); if (this.hub?.unread.get(this.s(room,'id'))) Text(String(this.hub?.unread.get(this.s(room,'id')))).fontColor(this.colors.primary) } }.padding(12).backgroundColor(this.colors.surfaceAlt).borderRadius(12).width('100%').onClick(() => { void this.showChat(this.s(room,'id'),true) })
      },(room: WireObject) => this.s(room,'id'))
      Button(this.t('新建群聊')).enabled(this.canWrite() && dsBotEntries(this.team['bots']).length >= 2).onClick(() => { this.selected = ''; void this.edit(true,true) })
    }
  }
  @Builder private chatMessages() {
    Row({ space: 12 }) { Text(this.s(this.entity(),'name')).fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.colors.text).layoutWeight(1); Button(this.t('详情')).onClick(() => { void this.details() }) }.width('100%')
    if (this.hub?.cursor !== null && this.hub?.cursor !== undefined) Button(this.t('加载更早的消息')).enabled(!this.hub?.chatLoading).onClick(() => { void this.hub?.loadChat(true) })
    ForEach(this.items,(item: WireObject,index: number) => {
      Column({ space: 6 }) {
        Text(this.s(item,'name') || (item['kind'] === 'user' ? this.t('你') : this.s(this.entity(),'name'))).fontSize(12).fontColor(this.colors.muted).width('100%')
        MessageBody({ text: this.s(item,'text') || (number(item['images'],0) > 0 ? this.t('图片消息') : this.s(item,'event')), colors: this.colors, fontSize: 16, visualReplies: false })
        if (item['whole']) Button(this.t('查看全文')).onClick(() => { void this.full(item) })
      }.padding(12).borderRadius(14).backgroundColor(item['kind'] === 'user' ? this.colors.surfaceAlt : this.colors.surface).width('100%')
    },(item: WireObject,index: number) => this.s(item,'id') || String(index)+':'+this.s(item,'kind'))
    if (this.hub?.streamText) MessageBody({ text: this.hub.streamText, streaming: true, colors: this.colors, fontSize: 16, visualReplies: false })
    if (!this.room && (this.hub?.question(this.selected)['id'] || this.hub?.view(this.selected)['id'])) DSBotCards({ colors: this.colors, hub: this.hub, scope: this.scope(), question: this.hub?.question(this.selected) || {}, view: this.hub?.view(this.selected) || {}, onOpenWeb: this.onOpenWeb })
    ForEach(this.approvals(),(approval: WireObject) => {
      Column({ space: 8 }) { Text(this.s(approval,'tool')).fontColor(this.colors.text); Text(this.s(approval,'reason')).fontColor(this.colors.muted); Row({ space: 12 }) { Button(this.t('拒绝')).onClick(() => { const hub = this.hub,scope = this.scope(); if (hub) void this.run(() => hub.approval(scope,this.s(approval,'id'),false)) }); Button(this.t('允许')).onClick(() => { const hub = this.hub,scope = this.scope(); if (hub) void this.run(() => hub.approval(scope,this.s(approval,'id'),true)) }) }.enabled(this.canWrite() && approval['answerable'] === true) }.padding(12).backgroundColor(this.colors.surfaceAlt).borderRadius(12)
    },(approval: WireObject) => this.s(approval,'id'))
    if (this.room && dsBotEntries(this.entity()['paused']).length) Button(this.t('继续群聊接力')).enabled(this.canWrite()).onClick(() => { const hub = this.hub,scope = this.scope(),paused = dsBotEntries(this.entity()['paused']).map((item: WireObject) => string(item['id'])); if (hub) void this.run(() => hub.continueRoom(scope,paused)) })
  }
  @Builder private chatComposer() {
    if (this.room) { ForEach(this.mentionOptions(),(option: WireObject) => { Button(this.s(option,'label')).onClick(() => this.pickMention(this.s(option,'insert'))) }) }
    TextArea({ text: this.draft, controller: this.inputController, placeholder: this.room ? this.t('输入消息，使用 @名称 提及成员') : this.t('发送消息') }).height(110).onChange((value: string) => { this.draft = value }).onTextSelectionChange((start: number,end: number) => { this.caretStart = start; this.caretEnd = end }).enabled(this.status === 'ready')
    Row({ space: 12 }) { Button(this.t('发送')).enabled(this.canWrite() && !!this.draft.trim()).onClick(() => { void this.send() }); if (dsBotWork(this.live,this.selected,this.room).length) Button(this.t('停止')).enabled(this.canWrite()).onClick(() => { const hub = this.hub,scope = this.scope(); if (hub) void this.run(() => hub.stop(scope)) }) }
  }
  @Builder private detailPage() {
    if (this.images[this.selected]) Image(this.s(this.images,this.selected)).width(64).height(64).borderRadius(32)
    Text(this.s(this.entity(),'name')).fontSize(24).fontWeight(FontWeight.Medium).fontColor(this.colors.text)
    Text(this.s(this.entity(),'role') || this.s(this.entity(),'notice')).fontColor(this.colors.muted)
    Button(this.t('编辑资料')).enabled(this.canWrite()).onClick(() => { void this.edit(false) })
    if (!this.room) {
      Text(this.s(this.entity(),'model') || this.s(this.entity(),'appliedModel') || this.t('尚未选择模型')).fontColor(this.colors.muted)
      Text(this.s(this.entity(),'instructions')).fontColor(this.colors.text).width('100%').copyOption(CopyOptions.LocalDevice)
      Button(strings(this.team['mainBotIds']).includes(this.selected) ? this.t('取消主 Bot') : this.t('设为主 Bot')).enabled(this.canWrite()).onClick(() => this.mutate('set-main',{ 'id': this.selected, 'main': !strings(this.team['mainBotIds']).includes(this.selected) }))
      Button(this.t('复制 Bot')).enabled(this.canWrite()).onClick(() => { const hub = this.hub,scope = this.scope(); if (hub) void this.run(async () => { const value = object(await hub.write('duplicate-bot',{ 'id': scope.id },scope)); if (hub.same(scope) && string(value['id'])) await this.showChat(string(value['id']),false) }) })
      Button(this.t('用量统计')).onClick(() => { void this.resource('usage') })
    } else {
      ForEach(strings(this.entity()['members']),(id: string) => {
        Row({ space: 12 }) { Text(this.s(this.hub?.entity(id,false) || {},'name') + (this.entity()['admin'] === id ? ' ★' : '')).layoutWeight(1).fontColor(this.colors.text); if (dsBotWork(this.live,this.selected,true).some((work: WireObject) => work['botId'] === id)) Button(this.t('停止')).enabled(this.canWrite()).onClick(() => this.mutate('stop-member-work',{ 'roomId': this.selected, 'botId': id })) }.width('100%')
      })
    }
    Text(this.s(this.entity(),'workDir') || this.t('默认工作目录')).fontColor(this.colors.muted).copyOption(CopyOptions.LocalDevice)
    Button(this.t('工作目录')).onClick(() => { void this.resource('folders') })
    if (this.team['memory'] !== false) Button(this.t('记忆')).onClick(() => { void this.resource('memory') })
    Button(this.t('完整会话记录')).onClick(() => this.onOpenSession(this.room ? this.selected : dsBotSession(this.entity())))
    ForEach(strings(this.entity()['parts']),(id: string) => { Button(this.f('历史会话 {0}',[id])).onClick(() => this.onOpenSession(id)) })
    Button(this.room ? this.t('删除群聊') : this.t('删除 Bot')).fontColor(this.colors.danger).enabled(this.canWrite()).onClick(() => { const hub = this.hub,scope = this.scope(); if (hub) this.confirm(this.room ? this.t('删除群聊？') : this.t('删除 Bot？'),this.t('此操作会移除该对象及其专用会话，无法撤销。'),async () => { await hub.write(scope.room ? 'delete-room' : 'delete-bot',{ 'id': scope.id },scope); if (hub.current() && this.selected === scope.id) { this.page = 'team'; this.selected = ''; this.draft = '' } }) })
  }
  @Builder private editorPage() {
    this.field('名称','name')
    if (this.room) {
      this.heading('成员')
      ForEach(dsBotEntries(this.team['bots']),(bot: WireObject) => { Button((strings(this.form['members']).includes(this.s(bot,'id')) ? '✓ ' : '') + this.s(bot,'name')).enabled(!this.busy).onClick(() => { const id = this.s(bot,'id'),members = strings(this.form['members']); this.set('members',members.includes(id) ? members.filter((item: string) => item !== id) : members.concat(id)); if (!strings(this.form['members']).includes(this.s(this.form,'admin'))) this.set('admin',strings(this.form['members'])[0] || '') }) })
      this.heading('管理员')
      ForEach(strings(this.form['members']),(id: string) => { Button((this.form['admin'] === id ? '✓ ' : '') + this.s(this.hub?.entity(id,false) || {},'name')).onClick(() => this.set('admin',id)).enabled(!this.busy) })
      if (this.editorScope?.id) { this.field('群公告','notice',true); Row({ space: 12 }) { Button(this.t('管理员先回复')).onClick(() => this.set('mode','admin')); Button(this.t('所有成员依次回复')).onClick(() => this.set('mode','everyone')) }; Text(this.t(this.form['mode'] === 'everyone' ? '所有成员依次回复' : '管理员先回复')).fontColor(this.colors.primary); this.field('接力上限（留空使用默认值）','relayLimit'); this.field('工作目录','workDir') }
      else Row() { Text(this.t('创建后问候')).fontColor(this.colors.text).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.form['greet'] !== false }).onChange((value: boolean) => this.set('greet',value)) }.width('100%')
    } else {
      this.field('角色','role'); this.field('指令','instructions',true); this.field('颜色（名称或 #RRGGBB）','color')
      this.heading('模型')
      Button(this.t('使用默认模型')).onClick(() => this.set('model','')).enabled(!this.busy)
      ForEach(dsBotEntries(this.team['models']),(model: WireObject) => { Button((this.form['model'] === model['ref'] ? '✓ ' : '') + this.s(model,'providerName')+' · '+this.s(model,'name')+(model['needsKey'] === true ? ' · '+this.t('需要 API Key') : '')).enabled(!this.busy && model['needsKey'] !== true).onClick(() => this.set('model',this.s(model,'ref'))) },(model: WireObject) => this.s(model,'ref'))
      this.heading('思考力度')
      Button(this.t('默认')).onClick(() => this.set('effort','')).enabled(!this.busy)
      ForEach(this.efforts(),(effort: DshReasoningEffort) => { Button((this.form['effort'] === effort.id ? '✓ ' : '') + effort.name).onClick(() => this.set('effort',effort.id)).enabled(!this.busy) })
      if (this.editorScope?.id) this.field('工作目录','workDir')
      else this.field('初始任务（可选）','brief',true)
    }
    Button(this.t('保存')).enabled(this.canWrite() && !!this.s(this.form,'name').trim()).onClick(() => { void this.save() })
  }
  @Builder private memoryPage() {
    this.heading('记忆')
    if (this.memory['summarizing'] === true) Text(this.t('正在整理记忆…')).fontColor(this.colors.muted)
    if (object(this.memory['summary'])['text']) Text(this.s(object(this.memory['summary']),'text')).fontColor(this.colors.text).width('100%')
    if (this.memory['error']) Text(this.s(this.memory,'error')).fontColor(this.colors.danger)
    ForEach(dsBotEntries(this.memory['entries']),(entry: WireObject) => {
      Column({ space: 8 }) { Text(this.s(entry,'scope')+' · '+this.s(entry,'topic')).fontSize(12).fontColor(this.colors.muted).width('100%'); Text(this.s(entry,'text')).fontColor(this.colors.text).width('100%').copyOption(CopyOptions.LocalDevice); Text([this.s(entry,'added'),this.s(entry,'by'),this.s(entry,'source')].filter((value: string) => !!value).join(' · ')).fontSize(12).fontColor(this.colors.muted).width('100%'); Row({ space: 12 }) { if (this.hub?.supports('memory-edit')) Button(this.t('编辑')).onClick(() => { this.memoryEditing = entry; this.memoryText = this.s(entry,'text') }); Button(this.t('删除')).onClick(() => this.forget(entry)) }.enabled(this.canWrite()) }.padding(12).borderRadius(12).backgroundColor(this.colors.surfaceAlt)
    })
    if (!this.memoryEditing) Row({ space: 12 }) { Button(this.t(this.room ? '群聊记忆' : '个人记忆')).onClick(() => { this.memoryScope = this.room ? 'group' : 'own' }); Button(this.t('团队记忆')).onClick(() => { this.memoryScope = 'team' }); Text(this.memoryScope).fontColor(this.colors.primary) }
    TextArea({ text: this.memoryText, placeholder: this.t('填写记忆内容') }).height(120).onChange((value: string) => { this.memoryText = value }).enabled(this.canWrite())
    Button(this.memoryEditing ? this.t('保存修改') : this.t('添加记忆')).enabled(this.canWrite() && !!this.memoryText.trim()).onClick(() => { void this.memorySave() })
    if (this.memoryEditing) Button(this.t('取消编辑')).onClick(() => { this.memoryEditing = undefined; this.memoryText = '' })
    Button(this.t('刷新')).enabled(!this.busy).onClick(() => { void this.resource('memory') })
  }
  @Builder private usageRow(title: string,row: WireObject) {
    this.heading(title)
    Text(this.f('总计 {0} tokens · {1} 次调用',[this.total(row),number(row['calls'],0)])).fontColor(this.colors.text).width('100%')
    Text(this.f('输入 {0} · 输出 {1} · 缓存读取 {2} · 缓存写入 {3}',[number(row['input'],0),number(row['output'],0),number(row['cacheRead'],0),number(row['cacheWrite'],0)])).fontColor(this.colors.muted).width('100%')
  }
  @Builder private usagePage() {
    if (this.usage['scanning'] === true) Text(this.t('正在扫描历史记录，当前统计尚未完整。')).fontColor(this.colors.muted)
    this.usageRow('过去 24 小时',object(this.usage['day'])); this.usageRow('过去 7 天',object(this.usage['week'])); this.usageRow('过去 30 天',object(this.usage['month']))
    ForEach(dsBotEntries(this.usage['models']),(model: WireObject) => { this.usageRow(this.s(model,'name') || this.s(model,'key'),model) })
    Button(this.t('刷新')).enabled(!this.busy).onClick(() => { void this.resource('usage') })
  }
  @Builder private foldersPage() {
    Text(this.t('选择主机已有目录，或在编辑资料中填写绝对路径。')).fontColor(this.colors.muted).width('100%')
    Text(this.s(this.folders,'team')).fontColor(this.colors.text).copyOption(CopyOptions.LocalDevice)
    Button(this.t('恢复默认工作目录')).enabled(this.canWrite()).onClick(() => this.mutate(this.room ? 'update-room' : 'update-bot',{ 'id': this.selected, 'workDir': '' }))
    ForEach(dsBotEntries(this.folders['folders']),(folder: WireObject) => { Button(this.s(folder,'title') || this.s(folder,'path')).enabled(this.canWrite()).onClick(() => this.mutate(this.room ? 'update-room' : 'update-bot',{ 'id': this.selected, 'workDir': this.s(folder,'path') })); Text(this.s(folder,'path')).fontColor(this.colors.muted).copyOption(CopyOptions.LocalDevice) })
  }
  build() {
    Column({ space: 0 }) {
      Row({ space: 12 }) { Button(this.t('返回')).onClick(() => { if (!this.back()) this.onClose() }); Text('DS Bot').fontSize(22).fontWeight(FontWeight.Medium).fontColor(this.colors.text).layoutWeight(1); Button(this.t('刷新')).enabled(!this.busy).onClick(() => { this.error = ''; if (this.status === 'ready') this.hub?.kick(); else void this.hub?.start() }) }.width('100%').padding(16)
      if (this.bundledAvailable && this.onBundledChange) {
        Row({ space: 12 }) { Text(this.t('内置 DS Bot')).fontColor(this.colors.text).layoutWeight(1); Button(this.bundledEnabled ? this.t('停用') : this.t('启用')).enabled(!this.busy).onClick(() => { const enabled = !this.bundledEnabled; this.confirm(enabled ? this.t('启用内置 DS Bot？') : this.t('停用内置 DS Bot？'),this.t('保存后需要重启本机引擎，已有团队数据会保留。'),async () => { await this.onBundledChange?.(enabled) }) }) }.padding(12).width('100%')
        if (this.bundledRestart) Text(this.t('设置已保存，请重启本机引擎后生效。')).fontColor(this.colors.warning).padding(12)
      }
      if (this.hub?.readOnly()) Text(this.hub.readOnly()).fontColor(this.colors.warning).width('100%').padding(12)
      if (this.error) Text(this.t(this.error)).fontColor(this.colors.danger).width('100%').padding(12)
      if (this.busy) Progress({ value: 20, total: 100, type: ProgressType.Linear }).width('100%')
      if (this.page === 'chat') {
        Column({ space: 12 }) {
          Scroll(this.chatScroll) { Column({ space: 12 }) { if (this.revision >= 0) this.chatMessages() }.width('100%').padding({ left: 16, right: 16, bottom: 12 }) }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
          if (this.revision >= 0) Column({ space: 12 }) { this.chatComposer() }.width('100%').padding({ left: 16, right: 16, bottom: 16 })
        }.layoutWeight(1).width('100%')
      } else Scroll() { Column({ space: 12 }) {
        if (this.revision >= 0) {
          if (this.page === 'team') this.teamPage()
          else if (this.page === 'details') this.detailPage()
          else if (this.page === 'editor') this.editorPage()
          else if (this.page === 'memory') this.memoryPage()
          else if (this.page === 'usage') this.usagePage()
          else if (this.page === 'folders') this.foldersPage()
          else if (this.page === 'full') { if (!this.fullWhole) Text(this.t('主机只返回了部分内容。')).fontColor(this.colors.warning); Text(this.fullText).fontColor(this.colors.text).copyOption(CopyOptions.LocalDevice).width('100%') }
        }
      }.width('100%').padding({ left: 16, right: 16, bottom: 24 }) }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor(this.colors.background)
  }
}
