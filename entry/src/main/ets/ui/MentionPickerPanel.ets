import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { MentionItem, MentionPickerController, MentionSection } from './MentionData'
import { DshClient } from '../dsh/DshClient'
import { DshGlyphs, ThemeColors, themeColors } from './DshTheme'

@Component
export struct MentionPickerPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  @Prop revision: number = 0
  controller: MentionPickerController = new MentionPickerController(new DshClient())

  // Each ArkUI observer must read the reactive revision, including retained ForEach rows.
  private sections(): MentionSection[] { return this.revision >= 0 ? this.controller.sections : [] }
  private items(title: string): MentionItem[] {
    return this.sections().find((section: MentionSection) => section.title === title)?.items || []
  }
  private current(item: MentionItem): MentionItem {
    return this.revision >= 0 ? this.controller.items.find((candidate: MentionItem) => candidate.key === item.key) || item : item
  }
  private highlighted(item: MentionItem): boolean {
    return this.revision >= 0 && this.controller.items[this.controller.highlighted]?.key === item.key
  }
  private loading(): boolean { return this.revision >= 0 && this.controller.loading }
  private emptyText(): string {
    return this.loading() ? this.t("正在查找…") : this.controller.query?.pathOnly ? this.t("没有匹配的文件") : this.t("没有匹配的文件或对话")
  }

  @Builder
  private itemRow(item: MentionItem) {
    Row({ space: 10 }) {
      Text(this.current(item).subagent ? '\uE0A3' : this.current(item).kind === 'session' ? DshGlyphs.chat :
        this.current(item).kind === 'folder' ? DshGlyphs.folder : DshGlyphs.file)
        .fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.muted).width(32)
      Column({ space: 2 }) {
        Text(this.current(item).label).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.colors.text)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        if (this.current(item).detail) Text(this.current(item).detail).fontSize(12).fontColor(this.colors.muted).maxLines(1).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.highlighted(item)) {
        Text('\uE013').fontFamily(DshGlyphs.family).fontSize(16).fontColor(this.colors.hint)
      }
      if (this.current(item).kind === 'folder') {
        Button({ type: ButtonType.Normal }) {
          Text(DshGlyphs.disclosure).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.muted)
        }.width(40).height(36).backgroundColor(Color.Transparent).accessibilityText(this.f("打开文件夹 {0}", [this.current(item).label]))
          .onClick(() => this.controller.pick(this.current(item), true))
      }
    }.constraintSize({ minHeight: 52 }).padding({ left: 6, top: 8, bottom: 8, right: this.current(item).kind === 'folder' ? 0 : 12 })
      .width('100%').borderRadius(14)
      .backgroundColor(this.highlighted(item) ? this.colors.surfaceAlt : Color.Transparent)
      .accessibilityGroup(true).accessibilityText(`${this.current(item).kind === 'session' ? this.t("对话") : this.current(item).kind === 'folder' ? this.t("文件夹") : this.t("文件")}：${this.current(item).label}`)
      .accessibilityDescription(this.current(item).detail).onClick(() => this.controller.pick(this.current(item)))
  }

  build() {
    if (this.revision >= 0 && this.controller.isOpen) {
      Column() {
        if (!this.sections().length) {
          Row({ space: 10 }) {
            if (this.loading()) LoadingProgress().width(16).height(16).color(this.colors.muted)
            else Text('\uE06F').fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.hint)
            Text(this.emptyText())
              .fontSize(12).fontColor(this.colors.muted).layoutWeight(1)
          }.padding(16).width('100%')
        } else {
          Scroll() {
            Column() {
              ForEach(this.sections(), (section: MentionSection) => {
                Text(this.t(section.title)).fontSize(11).fontColor(this.colors.muted).width('100%')
                  .padding({ left: 48, top: 10, right: 16, bottom: 4 })
                ForEach(this.items(section.title), (item: MentionItem) => { this.itemRow(item) }, (item: MentionItem) => item.key)
              }, (section: MentionSection) => section.title)
            }.padding({ left: 6, right: 6, bottom: 6 }).width('100%')
          }.constraintSize({ maxHeight: 300 }).scrollBar(BarState.Auto).width('100%')
        }
      }.backgroundColor(this.colors.surface).borderRadius(20).width('100%').clip(true)
        .accessibilityText(this.t("引用"))
    }
  }
}
