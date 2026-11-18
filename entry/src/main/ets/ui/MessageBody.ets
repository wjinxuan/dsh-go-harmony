import { localizedSettingsText } from './SettingsLocale'
import { MessageRender } from './MessageRender'
import { MermaidPanel } from './MermaidPanel'
import { NativePluginView } from './NativePluginView'
import { CodeRun, FencedDiffLine, fencedCodeLanguage, fencedCodeRuns, fencedDiffLines, fencedDiffStyle } from './CodeHighlight'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { DshGlyphs, DshSpace, DshType, ThemeColors, themeColors } from './DshTheme'
import {
  BlockKind, InlineKind, InlineRun, MarkdownBlock, isMessageLink, isWebLink, parseInline, parseMarkdown
} from './MarkdownBlocks'

const checkedTaskGlyph: string = '\uE055'
const uncheckedTaskGlyph: string = '\uE056'

@Component
export struct MessageBody {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop @Watch('updateBlocks') text: string = ''
  @Prop @Watch('updateBlocks') streaming: boolean = false
  @State private showDiagram: boolean = false
  @State private diagramText: string = ''
  @Prop colors: ThemeColors = themeColors()
  @Prop fontSize: number = 15
  @Prop visualReplies: boolean = true
  @Prop replyState: string = 'readonly'
  @Prop replyText: string = ''
  onReply?: (text: string) => Promise<boolean>
  onOpenLink?: (url: string) => void
  @State private blocks: MarkdownBlock[] = []
  @State private codeViewportWidth: number = 0

  aboutToAppear(): void {
    this.updateBlocks()
  }

  private updateBlocks(): void {
    this.blocks = parseMarkdown(this.text, this.streaming)
  }

  private codeWidth(block: MarkdownBlock): number {
    const context = this.getUIContext()
    const pixels = context.getMeasureUtils().measureText({ textContent: block.text,
      fontSize: DshType.mono, fontFamily: DshType.monoFamily })
    return Math.max(this.codeViewportWidth, context.px2vp(pixels) + 2 * DshSpace.md + 2)
  }

  private showStatus(message: Resource): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message })
    } catch {
      // The page may have been dismissed before the system action finished.
    }
  }

  private async copyCode(code: string): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, code))
      this.showStatus($r('app.string.markdown_copied'))
    } catch {
      this.showStatus($r('app.string.markdown_copy_failed'))
    }
  }

  private async openLink(url: string): Promise<void> {
    if (!isMessageLink(url)) {
      return
    }
    if (this.onOpenLink) {
      this.onOpenLink(url)
      return
    }
    if (!isWebLink(url)) {
      this.showStatus($r('app.string.markdown_link_failed'))
      return
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await context.openLink(url)
    } catch {
      this.showStatus($r('app.string.markdown_link_failed'))
    }
  }

  @Builder
  private inlineText(value: string, size: () => number, color: () => string, bold: boolean) {
    if (parseInline(value).some((run: InlineRun) => run.kind === InlineKind.Math)) {
      MessageRender({ text: value, colors: this.colors, fontSize: size(), textColor: color(), bold: bold,
        onOpenLink: (url: string) => { void this.openLink(url) } })
    } else {
    Text() {
      ForEach(parseInline(value), (run: InlineRun) => {
        if (run.kind === InlineKind.Link) {
          Span(run.text)
            .fontColor(this.colors.primary)
            .decoration({ type: TextDecorationType.Underline, color: this.colors.primary })
            .onClick(() => { void this.openLink(run.url) })
        } else if (run.kind === InlineKind.Code) {
          Span(run.text)
            .fontFamily(DshType.monoFamily)
            .fontSize(size() * 0.875)
            .textBackgroundStyle({ color: this.colors.codeSurface, radius: DshSpace.xs })
        } else if (run.kind === InlineKind.Strong) {
          Span(run.text).fontWeight(FontWeight.Medium)
        } else if (run.kind === InlineKind.Emphasis) {
          Span(run.text).fontStyle(FontStyle.Italic)
        } else {
          Span(run.text)
        }
      })
    }
    .width('100%')
    .fontSize(size())
    .fontColor(color())
    .fontWeight(bold ? FontWeight.Medium : FontWeight.Normal)
    .lineHeight(size() * (bold ? 1.35 : DshType.bodyHeight))
    .wordBreak(WordBreak.BREAK_WORD)
    .copyOption(CopyOptions.LocalDevice)
    }
  }

  @Builder
  private codeBlock(block: MarkdownBlock) {
    Column() {
      Row() {
        Text(block.label || 'text')
          .fontSize(DshType.label)
          .fontFamily(DshType.monoFamily)
          .fontColor(this.colors.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (block.label.toLowerCase() === 'mermaid') {
          Button(this.t("预览")).height(38).fontSize(13).fontColor(this.colors.primary).backgroundColor(Color.Transparent)
            .onClick(() => { this.diagramText = block.text; this.showDiagram = true })
        }
        Button({ type: ButtonType.Normal }) {
          Text(DshGlyphs.copy)
            .fontFamily(DshGlyphs.family)
            .fontSize(17)
            .fontColor(this.colors.muted)
        }
        .width(42)
        .height(38)
        .backgroundColor(Color.Transparent)
        .accessibilityText($r('app.string.markdown_copy_code'))
        .onClick(() => { void this.copyCode(block.text) })
      }
      .padding({ left: DshSpace.md, right: DshSpace.xs })
      .width('100%')
      .backgroundColor(this.colors.codeHeader)
      Divider().color(this.colors.codeBorder)
      Scroll() {
        if (fencedCodeLanguage(block.label) === 'diff') {
          Column({ space: 0 }) {
            ForEach(fencedDiffLines(block.text), (line: FencedDiffLine) => {
              Text(line.text || ' ')
                .fontFamily(DshType.monoFamily)
                .fontSize(DshType.mono)
                .lineHeight(DshType.mono * DshType.monoHeight)
                .fontColor(fencedDiffStyle(line.kind, this.colors).color)
                .backgroundColor(fencedDiffStyle(line.kind, this.colors).background)
                .padding({ left: DshSpace.md, right: DshSpace.md })
                .width('100%')
                .copyOption(CopyOptions.LocalDevice)
            }, (line: FencedDiffLine, index: number) => `${index}/${line.kind}/${line.text}`)
          }.width(this.codeWidth(block)).padding({ top: DshSpace.md, bottom: DshSpace.md })
        } else {
        Text() {
          ForEach(fencedCodeRuns(block.text, block.label, this.colors), (run: CodeRun) => {
            Span(run.text).fontColor(run.style.color)
              .fontStyle(run.style.italic ? FontStyle.Italic : FontStyle.Normal)
              .fontWeight(run.style.weight)
              .decoration({ type: run.style.underline ? TextDecorationType.Underline : TextDecorationType.None })
              .textBackgroundStyle({ color: run.style.background })
          }, (run: CodeRun, index: number) => `${index}/${JSON.stringify(run)}`)
        }
          .fontFamily(DshType.monoFamily)
          .fontSize(DshType.mono)
          .lineHeight(DshType.mono * DshType.monoHeight)
          .fontColor(this.colors.text)
          .padding(DshSpace.md)
          .width(this.codeWidth(block))
          .copyOption(CopyOptions.LocalDevice)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Auto)
      .width('100%')
      .onAreaChange((_old: Area, area: Area) => { this.codeViewportWidth = Number(area.width) })
    }
    .width('100%')
    .backgroundColor(this.colors.codeSurface)
    .border({ width: 0.5, color: this.colors.codeBorder, radius: DshSpace.cardRadius })
    .clip(true)
  }

  @Builder
  private tableBlock(block: MarkdownBlock) {
    Scroll() {
      Column() {
        ForEach(block.rows, (row: string[], rowIndex: number) => {
          Row() {
            ForEach(row, (cell: string, columnIndex: number) => {
              Column() {
                this.inlineText(cell, () => this.fontSize * 0.875, () => this.colors.text, rowIndex === 0)
              }
              .width(122)
              .padding({ left: DshSpace.sm, right: DshSpace.sm, top: DshSpace.sm, bottom: DshSpace.sm })
              .border({ width: { right: columnIndex < row.length - 1 ? 0.5 : 0 }, color: this.colors.border })
            })
          }
          .alignItems(VerticalAlign.Top)
          .backgroundColor(rowIndex === 0 ? this.colors.codeHeader :
            rowIndex % 2 === 0 ? this.colors.surfaceAlt : this.colors.surface)
          if (rowIndex < block.rows.length - 1) {
            Divider().color(this.colors.border)
          }
        })
      }
      .width(block.rows[0].length * 122)
      .border({ width: 0.5, color: this.colors.border, radius: DshSpace.sm })
      .clip(true)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Auto)
    .width('100%')
  }

  @Builder
  private renderBlock(block: MarkdownBlock) {
    if (block.kind === BlockKind.Code) {
      if (block.label.toLowerCase() === 'dsh-ui' && this.visualReplies && !this.streaming) {
        NativePluginView({ colors: this.colors, view: block.text, budget: 'model', onReply: this.onReply,
          replyState: this.replyState, replyText: this.replyText })
      } else if (block.label === 'dsh-math') {
        MessageRender({ text: block.text, colors: this.colors, fontSize: this.fontSize, display: true })
      } else if (block.label === 'dsh-math-pending') {
        Text(block.text).fontFamily(DshType.monoFamily).fontColor(this.colors.muted).fontSize(this.fontSize * 0.875)
          .copyOption(CopyOptions.LocalDevice).width('100%')
      } else this.codeBlock(block)
    } else if (block.kind === BlockKind.Table) {
      this.tableBlock(block)
    } else if (block.kind === BlockKind.Heading) {
      this.inlineText(block.text, () => this.fontSize + Math.max(1, 8 - block.level * 2), () => this.colors.text, true)
    } else if (block.kind === BlockKind.Quote) {
      Column() {
        this.inlineText(block.text, () => this.fontSize, () => this.colors.muted, false)
      }
      .width('100%')
      .padding({ left: DshSpace.md })
      .border({ width: { left: 2 }, color: this.colors.border })
    } else if (block.kind === BlockKind.ListItem) {
      Row({ space: DshSpace.sm }) {
        if (block.label) {
          Text(block.label)
            .fontColor(this.colors.muted)
            .fontSize(this.fontSize)
            .lineHeight(this.fontSize * DshType.bodyHeight)
            .constraintSize({ minWidth: 15 })
        }
        Row({ space: DshSpace.xs }) {
          if (block.checked !== undefined) {
            Text(block.checked ? checkedTaskGlyph : uncheckedTaskGlyph)
              .fontFamily(DshGlyphs.family)
              .fontColor(block.checked ? this.colors.primary : this.colors.muted)
              .fontSize(18)
              .lineHeight(this.fontSize * DshType.bodyHeight)
              .accessibilityText(block.checked ? $r('app.string.markdown_task_checked') :
                $r('app.string.markdown_task_unchecked'))
          }
          Column() {
            this.inlineText(block.text, () => this.fontSize, () => this.colors.text, false)
          }
          .layoutWeight(1)
        }
        .alignItems(VerticalAlign.Top)
        .layoutWeight(1)
      }
      .alignItems(VerticalAlign.Top)
      .padding({ left: block.level * DshSpace.md })
      .width('100%')
    } else if (block.kind === BlockKind.Rule) {
      Divider().color(this.colors.border)
    } else {
      this.inlineText(block.text, () => this.fontSize, () => this.colors.text, false)
    }
  }

  @Builder
  private diagramPreview() {
    MermaidPanel({ text: this.diagramText, colors: this.colors, onClose: () => { this.showDiagram = false } })
  }

  build() {
    Column({ space: DshSpace.sm }) {
      ForEach(this.blocks, (block: MarkdownBlock) => {
        this.renderBlock(block)
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .bindContentCover($$this.showDiagram, this.diagramPreview)
  }
}
