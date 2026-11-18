import { localizedSettingsText } from './SettingsLocale'
import { MentionToken } from './MentionData'
import { DshGlyphs, ThemeColors, themeColors } from './DshTheme'

@Component
export struct MentionChip {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  @Prop fontSize: number = 16
  @Prop token: MentionToken = { start: 0, end: 0, kind: 'file', label: '' }

  build() {
    Row({ space: 3 }) {
      Text(this.token.kind === 'session' ? DshGlyphs.chat : this.token.kind === 'folder' ? DshGlyphs.folder : DshGlyphs.file)
        .fontFamily(DshGlyphs.family).fontSize(this.fontSize * 0.8125).fontColor(this.colors.primary)
      Text(this.token.label).fontSize(this.fontSize * 0.875).fontWeight(FontWeight.Medium)
        .lineHeight(this.fontSize * 0.875 * 1.25).fontColor(this.colors.text).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
    }.margin({ left: 1, right: 1 }).padding({ left: 5, right: 7, top: 1, bottom: 1 }).borderRadius(999)
      .backgroundColor(parseInt(this.colors.text.substring(1, 3), 16) > 128 ? '#17FFFFFF' : `#0F${this.colors.text.substring(1)}`)
      .constraintSize({ maxWidth: 200 }).accessibilityGroup(true)
      .accessibilityText(`${this.token.kind === 'session' ? this.t("对话") : this.token.kind === 'folder' ? this.t("文件夹") : this.t("文件")}：${this.token.label}`)
  }
}
