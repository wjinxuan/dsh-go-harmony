import { localizedSettingsText } from '../SettingsLocale'
import { WireObject } from '../../dsh/DshWire'
import { ThemeColors, themeColors } from '../DshTheme'
import { CONTEXT_PRESETS, OUTPUT_PRESETS, modelTokenText, providerModelDraft, providerModelValue } from './ProviderModelData'

const OFFERED_LEVELS: string[] = ['off', 'low', 'medium', 'high', 'xhigh', 'max']
@Component
export struct ProviderModelEditor {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  value: WireObject = {}
  defaultImages: boolean = false
  onSave: (value: WireObject) => void = () => {}
  onCancel: () => void = () => {}
  @State private name: string = ''
  @State private contextText: string = ''
  @State private output: string = ''
  @State private images: boolean = false
  @State private levels: string[] = []
  @State private error: string = ''
  aboutToAppear(): void {
    const draft = providerModelDraft(this.value, this.defaultImages)
    this.name = draft.name; this.contextText = draft.context; this.output = draft.output; this.images = draft.images; this.levels = draft.levels
  }
  private submit(): void {
    try {
      const draft = providerModelDraft(this.value, this.defaultImages)
      draft.name = this.name; draft.context = this.contextText; draft.output = this.output; draft.images = this.images; draft.levels = this.levels
      this.onSave(providerModelValue(this.value, draft, this.defaultImages))
    } catch (reason) { this.error = reason instanceof Error ? reason.message : this.t('模型参数无效。') }
  }
  @Builder private field(label: string, value: () => string, change: (value: string) => void) {
    Text(label).fontColor(this.colors.muted).fontSize(13).width('100%')
    TextInput({ text: value(), placeholder: this.t('默认') }).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).onChange(change)
  }
  build() {
    Column({ space: 10 }) {
      Text(`${this.t('模型参数')} · ${providerModelDraft(this.value).id}`).fontSize(18).fontColor(this.colors.text).width('100%')
      if (this.error) { Text(this.t(this.error)).fontColor(this.colors.danger) }
      this.field(this.t('显示名称'), () => this.name, (value: string) => this.name = value)
      this.field(this.t('上下文长度'), () => this.contextText, (value: string) => this.contextText = value)
      Flex({ wrap: FlexWrap.Wrap }) { ForEach(CONTEXT_PRESETS, (count: number) => {
        Button(modelTokenText(count)).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).margin(3)
          .onClick(() => this.contextText = this.contextText === String(count) ? '' : String(count))
      }) }
      this.field(this.t('最大输出 Token'), () => this.output, (value: string) => this.output = value)
      Flex({ wrap: FlexWrap.Wrap }) { ForEach(OUTPUT_PRESETS, (count: number) => {
        Button(modelTokenText(count)).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).margin(3)
          .onClick(() => this.output = this.output === String(count) ? '' : String(count))
      }) }
      Row() { Text(this.t('支持图片输入')).fontColor(this.colors.text).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.images }).selectedColor(this.colors.primary).onChange((value: boolean) => this.images = value) }.width('100%')
      Text(this.t('思考深度')).fontColor(this.colors.muted).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) { ForEach(OFFERED_LEVELS, (level: string) => {
        Button(level).fontColor(this.levels.includes(level) ? this.colors.onPrimary : this.colors.text)
          .backgroundColor(this.levels.includes(level) ? this.colors.primary : this.colors.surfaceAlt).margin(3)
          .onClick(() => this.levels = this.levels.includes(level) ? this.levels.filter((item: string) => item !== level) : this.levels.concat(level))
      }) }
      Text(this.t('留空继承渠道默认值；更改会在保存渠道后生效。')).fontSize(13).fontColor(this.colors.muted)
      Button(this.t('应用模型参数')).width('100%').backgroundColor(this.colors.primary).fontColor(this.colors.onPrimary).onClick(() => this.submit())
      Button(this.t('返回渠道')).width('100%').backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.text).onClick(this.onCancel)
    }.width('100%')
  }
}
