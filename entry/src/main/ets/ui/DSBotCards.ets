import { object, string, DshRpcError, WireObject } from '../dsh/DshWire'
import { DSBotHub, DSBotScope, dsBotEntries, dsBotFailure } from './DSBotData'
import { DSBotView, dsBotChoiceValue, dsBotView, dsBotViewAnswer } from './DSBotViewData'
import { ThemeColors, themeColors } from './DshTheme'
import { localizedSettingsText } from './SettingsLocale'

@Component
export struct DSBotCards {
  @StorageProp('dshLanguage') private language: string = 'system'
  @Prop colors: ThemeColors = themeColors()
  @Prop @Watch('reset') question: WireObject = {}
  @Prop @Watch('reset') view: WireObject = {}
  @Prop @Watch('reset') scope: DSBotScope = { epoch: -1, boot: '', id: '', room: false, session: '' }
  hub?: DSBotHub
  onOpenWeb: () => void = () => {}
  @State private selected: string[] = []
  @State private custom: string = ''
  @State private fields: WireObject = {}
  @State private inputs: WireObject = {}
  @State private busy: boolean = false
  @State private failure: string = ''
  private identity: string = ''
  private t(value: string): string { return localizedSettingsText(value,this.language) }
  private reset(): void { const next = String(this.scope.epoch)+':'+this.scope.session+':'+string(this.question['id'])+':'+string(this.view['id']); if (next !== this.identity) { this.identity = next; this.selected = []; this.custom = ''; this.fields = {}; this.inputs = {}; this.busy = false; this.failure = '' } }
  aboutToAppear(): void { this.reset() }
  private card(): DSBotView { return dsBotView(object(this.view['view'])) }
  private text(row: WireObject, key: string): string { return string(row[key]) }
  private choose(label: string, multi: boolean): void { this.selected = multi ? this.selected.includes(label) ? this.selected.filter((value: string) => value !== label) : this.selected.concat(label) : [label] }
  private setField(key: string,value: Object, choice: boolean): void { const next: WireObject = {}; const old = choice ? this.inputs : this.fields; for (const name of Object.keys(old)) next[name] = old[name]; next[key] = value; if (choice) this.inputs = next; else this.fields = next }
  private async answer(dismiss: boolean = false, confirmed?: boolean): Promise<void> {
    const hub = this.hub, scope = this.scope, id = this.identity; if (!hub || this.busy) return
    this.busy = true; this.failure = ''
    try {
      if (this.question['id']) await hub.answerQuestion(scope,string(this.question['id']),this.selected,this.custom,dismiss)
      else { const card = this.card(); const value: WireObject = dismiss ? {} : dsBotViewAnswer(card,this.inputs,this.selected,this.fields,confirmed); await hub.answerView(scope,string(this.view['id']),string(card.control['id']),value,dismiss) }
    } catch (error) { if (id === this.identity && hub.same(scope)) this.failure = error instanceof DshRpcError ? dsBotFailure(error as Error) : (error as Error).message }
    finally { if (id === this.identity) this.busy = false }
  }
  build() {
    Column({ space: 12 }) {
      if (this.question['id']) {
        Text(this.text(this.question,'question')).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%')
        if (this.question['detail']) Text(this.text(this.question,'detail')).fontColor(this.colors.muted).width('100%')
        ForEach(dsBotEntries(this.question['options']), (option: WireObject) => {
          Button((this.selected.includes(this.text(option,'label')) ? '✓ ' : '') + this.text(option,'label'))
            .onClick(() => this.choose(this.text(option,'label'),this.question['multiSelect'] === true)).enabled(!this.busy)
          if (option['description']) Text(this.text(option,'description')).fontColor(this.colors.muted).fontSize(12)
        })
        if (this.question['allowCustom'] === true) TextInput({ text: this.custom, placeholder: this.t('填写自己的回答') }).onChange((value: string) => { this.custom = value }).enabled(!this.busy)
        Button(this.t('发送')).enabled(!this.busy && (!!this.custom.trim() || this.selected.length > 0) && this.hub?.writable() === true).onClick(() => { void this.answer() })
      } else if (this.view['id']) {
        Text(this.text(this.view,'title')).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%')
        if (!this.card().supported) Button(this.t('在网页中打开')).onClick(this.onOpenWeb)
        else {
          ForEach(this.card().lines, (line: string) => { Text(line).fontColor(this.colors.text).width('100%') })
          ForEach(this.card().choices, (choice: WireObject) => {
            Text(this.text(choice,'label')).fontColor(this.colors.muted).width('100%')
            ForEach(dsBotEntries(choice['options']), (option: WireObject) => {
              Button(((this.inputs[this.text(choice,'id')] ?? choice['value'] ?? dsBotChoiceValue(dsBotEntries(choice['options'])[0])) === dsBotChoiceValue(option) ? '✓ ' : '') + this.text(option,'label'))
                .enabled(!this.busy).onClick(() => this.setField(this.text(choice,'id'),dsBotChoiceValue(option),true))
            })
          })
          if (this.card().control['type'] === 'options') {
            ForEach(dsBotEntries(this.card().control['options']), (option: WireObject) => {
              Button((this.selected.includes(this.text(option,'label')) ? '✓ ' : '') + this.text(option,'label'))
                .onClick(() => this.choose(this.text(option,'label'),this.card().control['multi'] === true)).enabled(!this.busy)
            })
          }
          if (this.card().control['type'] === 'form') {
            ForEach(dsBotEntries(this.card().control['fields']), (field: WireObject) => {
              Text(this.text(field,'label')).fontColor(this.colors.muted).width('100%')
              TextInput({ text: this.text(this.fields,this.text(field,'id')), placeholder: this.text(field,'placeholder') })
                .onChange((value: string) => this.setField(this.text(field,'id'),value,false)).enabled(!this.busy)
            })
          }
          if (this.card().control['type'] === 'confirm') {
            Row({ space: 12 }) {
              Button(this.text(this.card().control,'cancelLabel') || this.t('取消')).onClick(() => { void this.answer(false,false) })
              Button(this.text(this.card().control,'confirmLabel') || this.t('确认')).onClick(() => { void this.answer(false,true) })
            }.enabled(!this.busy && this.hub?.writable() === true)
          } else if (this.card().control['id']) {
            Button(this.text(this.card().control,'submitLabel') || this.text(this.card().control,'label') || this.t('发送'))
              .onClick(() => { void this.answer() }).enabled(!this.busy && this.hub?.writable() === true && (this.card().control['type'] !== 'options' || this.selected.length > 0))
          }
        }
      }
      if (this.question['id'] || this.view['id']) Button(this.t('忽略')).enabled(!this.busy && this.hub?.writable() === true).onClick(() => { void this.answer(true) })
      if (this.failure) Text(this.t(this.failure)).fontColor(this.colors.danger)
    }.width('100%').padding(16).borderRadius(16).backgroundColor(this.colors.surfaceAlt)
  }
}
