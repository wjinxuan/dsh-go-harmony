import { localizedSettingsText } from './SettingsLocale'
import { SessionArtifact } from './SessionArtifacts'
import { DshGlyphs, ThemeColors, themeColors } from './DshTheme'

@Component
export struct ArtifactCard {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  @Prop items: SessionArtifact[] = []
  onOpen: (path: string) => void = () => {}
  build() {
    Column({ space: 8 }) {
      Text(this.t("交付文件")).fontSize(14).fontColor(this.colors.muted).width('100%')
      ForEach(this.items, (item: SessionArtifact) => {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 12 }) {
            Text(DshGlyphs.file).fontFamily(DshGlyphs.family).fontSize(24).fontColor(this.colors.primary)
            Column({ space: 4 }) {
              Text(item.name).fontSize(16).fontColor(this.colors.text).maxLines(2).width('100%')
              if (item.description) Text(item.description).fontSize(13).fontColor(this.colors.muted).maxLines(3).width('100%')
            }.layoutWeight(1)
            Text('›').fontSize(20).fontColor(this.colors.muted)
          }.padding(14).width('100%')
        }.width('100%').backgroundColor(this.colors.surfaceAlt).borderRadius(12).onClick(() => this.onOpen(item.path))
      }, (item: SessionArtifact) => `${item.turn}/${item.path}/${item.description}`)
    }.width('100%')
  }
}
