import { AnsiRun, isDarkSurface, parseAnsi } from './AnsiData'
import { DshType, ThemeColors, themeColors } from './DshTheme'

@Component
export struct AnsiText {
  @Prop text: string = ''
  @Prop colors: ThemeColors = themeColors()
  @Prop error: boolean = false
  build() {
    Text() {
      ForEach(parseAnsi(this.text, isDarkSurface(this.colors.codeSurface)), (run: AnsiRun) => {
        Span(run.text)
          .fontColor(run.foreground ?? (this.error ? this.colors.danger : this.colors.text))
          .textBackgroundStyle({ color: run.background ?? Color.Transparent })
          .fontWeight(run.bold ? FontWeight.Medium : FontWeight.Normal)
          .fontStyle(run.italic ? FontStyle.Italic : FontStyle.Normal)
          .decoration({ type: run.underline ? TextDecorationType.Underline : TextDecorationType.None })
      })
    }
    .fontFamily(DshType.monoFamily).fontSize(12).lineHeight(18)
    .width('100%').copyOption(CopyOptions.LocalDevice)
  }
}
