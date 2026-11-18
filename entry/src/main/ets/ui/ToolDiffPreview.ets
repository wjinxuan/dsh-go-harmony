import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { DshTool } from '../dsh/DshWire'
import { SessionDiffLine, toolDiffLines } from './SessionDetailData'
import { DshType, ThemeColors, themeColors } from './DshTheme'

@Component
export struct ToolDiffPreview {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  @Prop @Watch('update') item: DshTool = { callId: '', name: '', arguments: '', seq: 0 }
  @State private lines: SessionDiffLine[] = []
  @State private shown: number = 80
  aboutToAppear(): void { this.update() }
  private update(): void {
    this.lines = this.item.isError ? [] : toolDiffLines(this.item.name, this.item.arguments, this.item.result || '', this.item.meta)
    this.shown = 80
  }
  build() {
    if (this.lines.length) {
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(this.t("变更")).fontColor(this.colors.muted).fontSize(13)
          Text(`+${this.lines.filter((line: SessionDiffLine) => line.marker === '+').length}`).fontColor(this.colors.success).fontSize(13)
          Text(`−${this.lines.filter((line: SessionDiffLine) => line.marker === '-').length}`).fontColor(this.colors.danger).fontSize(13)
        }.width('100%')
        ForEach(this.lines.slice(0, this.shown), (line: SessionDiffLine) => {
          Row({ space: 6 }) {
            Text(`${line.oldLine === undefined ? '' : line.oldLine} ${line.newLine === undefined ? '' : line.newLine}`)
              .width(54).fontSize(10).fontFamily(DshType.monoFamily).fontColor(this.colors.hint).textAlign(TextAlign.End)
            Text(`${line.marker === '@' ? '' : line.marker}${line.text}`).layoutWeight(1).fontSize(12)
              .fontFamily(DshType.monoFamily).fontColor(line.marker === '+' ? this.colors.success :
                line.marker === '-' ? this.colors.danger : this.colors.muted).copyOption(CopyOptions.LocalDevice)
          }.width('100%').alignItems(VerticalAlign.Top)
        }, (line: SessionDiffLine, index: number) => `${index}/${line.marker}/${line.text}`)
        if (this.lines.length > this.shown) Button(this.f("继续显示（{0} / {1} 行）", [this.shown, this.lines.length]))
          .fontColor(this.colors.primary).backgroundColor(this.colors.surface)
          .onClick(() => { this.shown = Math.min(this.lines.length, this.shown + 400) })
      }.width('100%').padding(10).backgroundColor(this.colors.codeSurface).borderRadius(12)
    }
  }
}
