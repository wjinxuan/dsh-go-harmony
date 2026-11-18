import { NativePluginDrafts } from './NativePluginDrafts'
import { NativePluginInput } from './NativePluginInput'
import { PLUGIN_INPUTS, pluginInputData, pluginInputIssue } from './NativePluginControlsData'
import { modelUiAnswer, ModelUiAnswer } from './NativePluginReplyData'
import { localizedSettingsText } from './SettingsLocale'
import { DshClient } from '../dsh/DshClient'
import { NativePluginImage } from './NativePluginImage'
import { NativePluginChart } from './NativePluginChart'
import { array, number, object, string, WireObject } from '../dsh/DshWire'
import { parsePluginView, pluginAction, pluginBindings, PluginNode, pluginText } from './NativePluginData'
import { ThemeColors, themeColors } from './DshTheme'

@Component
export struct NativePluginView {
  @StorageProp('dshLanguage') language: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.language) }
  @Prop colors: ThemeColors = themeColors()
  @Prop @Watch('viewChanged') view: Object = ''
  @Prop data: WireObject = {}
  @Prop budget: string = 'panel'
  @Prop replyState: string = 'readonly'
  @Prop replyText: string = ''
  @State private replyBusy: boolean = false
  @State private replySent: string = ''
  @State private replyError: string = ''
  @State private draftRevision: number = 0
  private controller: NativePluginDrafts = new NativePluginDrafts()
  @State private formError: string = ''
  @Prop pluginName: string = ''
  @Prop pkg: string = ''
  client?: DshClient
  onAction?: (action: WireObject) => Promise<boolean>
  onReply?: (text: string) => Promise<boolean>
  aboutToAppear(): void { this.setupDrafts() }
  private setupDrafts(): void { this.controller.handler = this.onAction; this.controller.changed = () => { this.draftRevision++; this.formError = this.controller.error }; this.controller.syncRemote(this.data); this.controller.syncInputs(parsePluginView(this.view, this.controller.data(), this.budget).root) }
  private viewChanged(): void { this.controller.dispose(); this.controller = new NativePluginDrafts(); this.setupDrafts(); this.formError = ''; this.replyError = ''; this.replySent = '' }
  aboutToDisappear(): void { this.controller.dispose() }
  private effectiveData(): WireObject { const revision = this.draftRevision; this.controller.syncRemote(this.data); return this.controller.data() }
  private inputValue(bind: string, value: Object | null, action: Object | null | undefined): void { this.setupDrafts(); this.controller.edit(bind, value) }
  private performAction(action: WireObject): void { this.setupDrafts(); void this.controller.invoke(action) }
  private submitForm(form: PluginNode): void { this.setupDrafts(); void this.controller.submit(form) }
  private async sendReply(text: string): Promise<boolean> {
    if (!this.onReply || this.replyBusy || this.replySent || this.replyState !== 'live') return false
    this.replyBusy = true; this.replyError = ''
    try {
      const accepted = await this.onReply(text)
      if (accepted) this.replySent = text; else this.replyError = '发送未能确认，请重试'
      return accepted
    } catch { this.replyError = '发送失败，请重试'; return false }
    finally { this.replyBusy = false }
  }
  private answer(): ModelUiAnswer | undefined { return modelUiAnswer(parsePluginView(this.view, this.effectiveData(), this.budget), this.replySent || this.replyText) }
  build() {
    Column({ space: 10 }) {
      if (this.pluginName) Text(this.pluginName).fontSize(12).fontColor(this.colors.muted).width('100%')
      if (parsePluginView(this.view, this.effectiveData(), this.budget).title) {
        Text(parsePluginView(this.view, this.effectiveData(), this.budget).title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%')
      }
      NativePluginNodeView({ colors: this.colors, pkg: this.pkg, client: this.client, node: parsePluginView(this.view, this.effectiveData(), this.budget).root,
        title: parsePluginView(this.view, this.effectiveData(), this.budget).title, answer: this.answer(),
        locked: this.budget === 'model' && (this.replyState !== 'live' || !!this.replySent || this.replyBusy),
        onAction: this.budget === 'panel' && this.onAction ? (action: WireObject) => this.performAction(action) : undefined, onSubmit: (form: PluginNode) => this.submitForm(form),
        onValue: this.budget === 'panel' && this.onAction ? (bind: string, value: Object | null, action: Object | null | undefined) => this.inputValue(bind, value, action) : undefined, onReply: this.budget === 'model' && this.onReply ? (text: string): Promise<boolean> => this.sendReply(text) : undefined })
      if (this.formError) Text(this.t(this.formError)).fontSize(12).fontColor(this.colors.danger)
      if (this.replyError) Text(this.t(this.replyError)).fontSize(12).fontColor(this.colors.danger)
      if (this.budget === 'model' && this.replyState === 'expired') Text(this.t('此卡片已失效')).fontSize(12).fontColor(this.colors.muted)
      if (parsePluginView(this.view, this.effectiveData(), this.budget).issue) Text(parsePluginView(this.view, this.effectiveData(), this.budget).issue)
        .fontSize(12).fontColor(this.colors.muted).width('100%')
    }.width('100%').padding(12).borderRadius(16).backgroundColor(this.colors.surfaceAlt)
  }
}

@Component
struct NativePluginNodeView {
  @StorageProp('dshLanguage') language: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.language) }
  @Prop colors: ThemeColors = themeColors()
  @Prop node: PluginNode = { type: 'invalid', raw: {}, children: [], key: '' }
  @Prop title: string = ''
  @Prop answer: ModelUiAnswer | undefined = undefined
  @Prop locked: boolean = false
  @Prop pkg: string = ''
  client?: DshClient
  onAction?: (action: WireObject) => void
  onSubmit?: (form: PluginNode) => void
  onValue?: (bind: string, value: Object | null, action: Object | null | undefined) => void
  @State private sectionIndex: number = 0
  @State private expanded: boolean = false
  onReply?: (text: string) => Promise<boolean>
  @State private choices: string[] = []
  @State private free: string = ''
  @State private submitted: boolean = false
  private text(key: string): string { return pluginText(this.node.raw[key]) }
  private rows(key: string = 'items', max: number = 50): WireObject[] { return array(this.node.raw[key]).slice(0, max).map(object) }
  private tone(value: Object | null | undefined): string {
    const tone = string(value)
    return ['danger', 'bad', 'error'].includes(tone) ? this.colors.danger : ['success', 'good', 'positive'].includes(tone) ?
      this.colors.success : ['warning', 'warn'].includes(tone) ? this.colors.warning : tone === 'muted' || tone === 'secondary' ? this.colors.muted : this.colors.text
  }
  private tap(raw: Object | null | undefined): void { const action = pluginAction(raw); if (action) this.onAction?.(action) }
  private async reply(body: string): Promise<void> {
    if (!this.onReply || this.submitted || this.locked) return
    this.submitted = true
    try { this.submitted = await this.onReply('[dsh-ui reply]' + (this.title ? ' ' + this.title.replace(/[\r\n]+/g, ' ') : '') + '\n' + body) }
    catch { this.submitted = false }
  }
  private selectedChoices(): string[] { return this.answer?.key === this.node.key ? this.answer.selected : this.choices }
  private optionLabel(value: Object): string { return typeof value === 'string' ? value.slice(0, 80) : string(object(value)['label']).slice(0, 80) }
  private choose(label: string): void {
    if (this.node.raw['multi'] === true) this.choices = this.choices.includes(label) ? this.choices.filter((v: string) => v !== label) : this.choices.concat(label)
    else this.choices = [label]
  }
  private submitOptions(): void {
    const selected = array(this.node.raw['options']).filter((value: Object) => this.choices.includes(this.optionLabel(value)))
    if (this.onReply) void this.reply((this.choices.length ? (this.language === 'en' ? 'Select: ' : '选择：') + this.choices.map((value: string) => value.replace(/\s*[\r\n]+\s*/g, ' ').trim()).join('、') : '') + (this.free.trim() ? (this.language === 'en' ? '\nOther: ' : '\n其他：') + this.free.trim().replace(/[\r\n]+/g, ' ') : ''))
    else {
      const args: WireObject = { 'selected': selected.map((value: Object) => string(object(value)['value']) || this.optionLabel(value)) }
      if (this.free.trim()) args['freetext'] = this.free.trim()
      const action: WireObject = { 'id': this.node.raw['id'], 'args': args }; this.tap(action)
    }
  }
  private confirm(confirmed: boolean): void {
    const label = string(this.node.raw[confirmed ? 'confirmLabel' : 'cancelLabel']) || (confirmed ? '确认' : '取消')
    if (this.onReply) void this.reply((this.language === 'en' ? confirmed ? 'Confirm' : 'Cancel' : confirmed ? '确认' : '取消') + (label !== (confirmed ? '确认' : '取消') ? '：' + label : ''))
    else { const args: WireObject = { 'confirmed': confirmed }; const action: WireObject = { 'id': this.node.raw['id'], 'args': args }; this.tap(action) }
  }
  private fraction(): number { const max = number(this.node.raw['max'], 100); return max > 0 ? Math.min(100, Math.max(0, number(this.node.raw['value'], 0) / max * 100)) : 0 }
  // Stable keys preserve input focus; each retained observer must read the current @Prop node.
  private childKeys(): string[] { return this.node.children.map((child: PluginNode) => child.key) }
  private child(key: string): PluginNode {
    const current = this.node.children.find((child: PluginNode) => child.key === key)
    if (current) return current
    const missing: PluginNode = { type: 'invalid', raw: {}, children: [], key: key }
    return missing
  }
  private imageSource(): string { const src = string(this.node.raw['src']); return /^data:image\/(?:png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/.test(src) && src.length <= 65536 ? src : '' }
  @Builder
  private pair(label: string, value: string) {
    Row({ space: 12 }) { Text(label).fontSize(13).fontColor(this.colors.muted).layoutWeight(1); Text(value).fontSize(14).fontColor(this.colors.text) }.width('100%')
  }
  @Builder
  private render() {
    if (PLUGIN_INPUTS.includes(this.node.type)) {
      NativePluginInput({ colors: this.colors, raw: this.node.raw, onValue: this.onValue })
    } else if (['form', 'grid', 'collapsible'].includes(this.node.type)) {
      Column({ space: 10 }) {
        if (this.node.raw['label']) Text(string(this.node.raw['label'])).fontSize(15).fontColor(this.colors.text).onClick(() => { this.expanded = !this.expanded })
        if (this.node.type === 'collapsible') Button(this.expanded ? this.t('收起') : this.t('展开')).onClick(() => { this.expanded = !this.expanded })
        if (this.node.type !== 'collapsible' || this.expanded || this.node.raw['expanded'] === true) {
          ForEach(this.childKeys(), (key: string) => { NativePluginNodeView({ colors: this.colors, pkg: this.pkg, client: this.client, node: this.child(key), title: this.title, answer: this.answer, locked: this.locked, onAction: this.onAction, onSubmit: this.onSubmit, onValue: this.onValue, onReply: this.onReply }) }, (key: string) => key)
          if (this.node.type === 'form' && this.onAction && pluginAction(this.node.raw['submit'])) Button(string(this.node.raw['submitLabel']) || this.t('提交')).onClick(() => this.onSubmit?.(this.node))
        }
      }.width('100%')
    } else if (['tabs', 'accordion', 'carousel', 'timeline'].includes(this.node.type)) {
      Column({ space: 8 }) {
        ForEach(this.childKeys(), (key: string, index: number) => {
          Button(string(this.child(key).raw['title']) || String(index + 1)).onClick(() => { this.sectionIndex = index; this.expanded = !this.expanded })
          if (this.node.type === 'timeline' || this.sectionIndex === index && (this.node.type !== 'accordion' || this.expanded)) NativePluginNodeView({ colors: this.colors, pkg: this.pkg, client: this.client, node: this.child(key), title: this.title, answer: this.answer, locked: this.locked, onAction: this.onAction, onSubmit: this.onSubmit, onValue: this.onValue, onReply: this.onReply })
        }, (key: string) => key)
      }.width('100%')
    } else if (this.node.type === 'divider') Divider().color(this.colors.border)
    else if (this.node.type === 'spacer') Blank().height(this.node.raw['size'] === 'L' ? 24 : this.node.raw['size'] === 'S' ? 8 : 16)
    else if (this.node.type === 'badge' || this.node.type === 'tag') Text(this.text('text')).fontSize(12).fontColor(this.tone(this.node.raw['tone'])).padding(6).borderRadius(10).backgroundColor(this.colors.surface)
    else if (this.node.type === 'codeBlock') Text(string(this.node.raw['code']).slice(0, 8000)).fontSize(12).fontFamily('monospace').fontColor(this.colors.text).copyOption(CopyOptions.LocalDevice).width('100%').padding(10)
    else if (this.node.type === 'emptyState') {
      Column({ space: 8 }) { Text(this.text('title')).fontSize(17).fontColor(this.colors.text); if (this.node.raw['message']) Text(this.text('message')).fontSize(13).fontColor(this.colors.muted)
        if (this.onAction && object(this.node.raw['action'])['label']) Button(string(object(this.node.raw['action'])['label'])).onClick(() => this.tap(object(this.node.raw['action'])['action']))
      }.width('100%').padding(20)
    } else if (this.node.type === 'gallery') {
      Column({ space: 10 }) { ForEach(this.rows('items', 24), (row: WireObject) => {
        NativePluginImage({ colors: this.colors, source: string(row['src']), description: string(row['alt']), pkg: this.pkg, client: this.client }).onClick(() => this.tap(row['action']))
        if (row['caption']) Text(string(row['caption'])).fontSize(12).fontColor(this.colors.muted)
      }) }.width('100%')
    } else if (this.node.type === 'stack') {
      Column({ space: 10 }) { ForEach(this.childKeys(), (key: string) => {
        NativePluginNodeView({ colors: this.colors, pkg: this.pkg, client: this.client, node: this.child(key), title: this.title, answer: this.answer, locked: this.locked, onAction: this.onAction, onSubmit: this.onSubmit, onValue: this.onValue, onReply: this.onReply })
      }, (key: string) => key) }.width('100%')
    } else if (this.node.type === 'row') {
      Row({ space: 10 }) { ForEach(this.childKeys(), (key: string) => {
        NativePluginNodeView({ colors: this.colors, pkg: this.pkg, client: this.client, node: this.child(key), title: this.title, answer: this.answer, locked: this.locked, onAction: this.onAction, onSubmit: this.onSubmit, onValue: this.onValue, onReply: this.onReply }).layoutWeight(1)
      }, (key: string) => key) }.width('100%').alignItems(VerticalAlign.Top)
    } else if (this.node.type === 'text' || this.node.type === 'callout') {
      Text(this.text('text')).fontSize(14).fontColor(this.tone(this.node.raw['tone'])).width('100%').copyOption(CopyOptions.LocalDevice)
        .padding(this.node.type === 'callout' ? 10 : 0)
    } else if (this.node.type === 'metric') {
      Column({ space: 4 }) {
        Text(this.text('label')).fontSize(12).fontColor(this.colors.muted).width('100%')
        Text(this.text('value')).fontSize(26).fontWeight(FontWeight.Medium).fontColor(this.tone(this.node.raw['tone'])).width('100%')
        if (this.node.raw['caption']) Text(this.text('caption')).fontSize(12).fontColor(this.colors.muted).width('100%')
      }.width('100%')
    } else if (this.node.type === 'progress') {
      Column({ space: 6 }) {
        this.pair(string(this.node.raw['label']), string(this.node.raw['caption']) || Math.round(this.fraction()) + '%')
        Progress({ value: this.fraction(), total: 100, type: this.node.raw['shape'] === 'ring' ? ProgressType.Ring : ProgressType.Linear })
          .color(this.colors.primary).width('100%')
      }.width('100%')
    } else if (this.node.type === 'keyValue') {
      Column({ space: 8 }) { ForEach(this.rows('items', 24), (row: WireObject) => { this.pair(pluginText(row['label']), pluginText(row['value'])) }) }.width('100%')
    } else if (this.node.type === 'list' || this.node.type === 'steps') {
      Column({ space: 8 }) {
        ForEach(this.rows(), (row: WireObject, index: number) => {
          Row({ space: 8 }) {
            if (this.node.type === 'steps') Text(['done', 'completed'].includes(string(row['status'])) ? '✓' : String(index + 1)).fontColor(this.colors.primary)
            Column({ space: 3 }) {
              Text(pluginText(row['title'] ?? row['label'])).fontSize(14).fontColor(this.tone(row['tone'])).width('100%')
              if (row['subtitle'] || row['detail']) Text(pluginText(row['subtitle'] ?? row['detail'])).fontSize(12).fontColor(this.colors.muted).width('100%')
            }.layoutWeight(1)
            if (row['trailing']) Text(pluginText(row['trailing'])).fontSize(12).fontColor(this.colors.muted)
          }.width('100%').padding(6).onClick(() => this.tap(row['action']))
        })
      }.width('100%')
    } else if (this.node.type === 'actions') {
      Row({ space: 8 }) { ForEach(this.rows('items', 4), (row: WireObject) => {
        if (this.onAction && pluginAction(row['action'])) Button(pluginText(row['label'], 80)).onClick(() => this.tap(row['action']))
      }) }.width('100%')
    } else if (this.node.type === 'options') {
      Column({ space: 8 }) {
        ForEach(array(this.node.raw['options']).slice(0, 12), (option: Object) => {
          Row({ space: 8 }) {
            Text(this.selectedChoices().includes(this.optionLabel(option)) ? '●' : '○').fontColor(this.colors.primary)
            Text(this.optionLabel(option)).fontSize(14).fontColor(this.colors.text).layoutWeight(1)
          }.width('100%').padding(8).enabled(!this.locked && !this.submitted && !!(this.onAction || this.onReply)).onClick(() => this.choose(this.optionLabel(option)))
        })
        if (this.node.raw['freetext'] && (this.onAction || this.onReply)) TextInput({ text: this.answer?.key === this.node.key ? this.answer.free : this.free, placeholder: this.t('自己填写') }).enabled(!this.locked && !this.submitted).onChange((value: string) => { this.free = value.slice(0, 2000) })
        if (this.onAction || this.onReply) Button(this.submitted || this.answer?.key === this.node.key ? this.t('已提交') : this.t('提交选择')).enabled(!this.locked && !this.submitted && (!!this.choices.length || !!this.free.trim())).onClick(() => this.submitOptions())
      }.width('100%')
    } else if (this.node.type === 'confirm') {
      if (this.onAction || this.onReply) Row({ space: 8 }) {
        Button((this.answer?.key === this.node.key && this.answer.confirmed === true ? '✓ ' : '') + (string(this.node.raw['confirmLabel']) || this.t('确认'))).enabled(!this.locked && !this.submitted).onClick(() => this.confirm(true))
        Button((this.answer?.key === this.node.key && this.answer.confirmed === false ? '✓ ' : '') + (string(this.node.raw['cancelLabel']) || this.t('取消'))).enabled(!this.locked && !this.submitted).onClick(() => this.confirm(false))
      }
    } else if (this.node.type === 'table') {
      Scroll() { Column({ space: 6 }) {
        Row({ space: 8 }) { ForEach(array(this.node.raw['columns']).slice(0, 8), (value: Object) => {
          Text(typeof value === 'string' ? value : pluginText(object(value)['label'])).fontWeight(FontWeight.Medium).width(100).fontSize(13).fontColor(this.colors.text)
        }) }
        ForEach(array(this.node.raw['rows']).slice(0, 50), (row: Object) => {
          Row({ space: 8 }) { ForEach(array(row).slice(0, 8), (value: Object) => { Text(pluginText(value, 200)).width(100).fontSize(13).fontColor(this.colors.text) }) }
        })
      } }.scrollable(ScrollDirection.Horizontal).width('100%')
    } else if (this.node.type === 'compare') {
      Row({ space: 12 }) { ForEach(this.rows('items', 4), (row: WireObject) => {
        Column({ space: 8 }) {
          Text(pluginText(row['title'])).fontSize(15).fontColor(this.colors.text)
          if (row['badge']) Text(pluginText(row['badge'])).fontSize(12).fontColor(this.colors.primary)
          ForEach(array(row['rows']).slice(0, 12), (pair: Object) => {
            this.pair(pluginText(Array.isArray(pair) ? array(pair)[0] : object(pair)['label']), pluginText(Array.isArray(pair) ? array(pair)[1] : object(pair)['value']))
          })
        }.layoutWeight(1)
      }) }.width('100%').alignItems(VerticalAlign.Top)
    } else if (this.node.type === 'chart') {
      NativePluginChart({ colors: this.colors, chart: this.node.raw })
    } else if (this.node.type === 'image' || this.node.type === 'avatar') {
      NativePluginImage({ colors: this.colors, source: string(this.node.raw['src']), description: string(this.node.raw['alt']), pkg: this.pkg, client: this.client })
    } else Text(this.t('插件界面有误')).fontColor(this.colors.muted).fontSize(13)
  }
  build() { this.render() }
}
