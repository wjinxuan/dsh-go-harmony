import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { DshGlyphs, DshSpace, DshType, ThemeColors, themeColors } from './DshTheme'
import {
  BlockKind, InlineKind, InlineRun, MarkdownBlock, isMessageLink, isWebLink, parseInline, parseMarkdown
} from './MarkdownBlocks'

@Component
export struct MessageBody {
  @Prop @Watch('updateBlocks') text: string = ''
  @Prop colors: ThemeColors = themeColors()
  @Prop fontSize: number = 15
  onOpenLink?: (url: string) => void
  @State private blocks: MarkdownBlock[] = []

  aboutToAppear(): void {
    this.updateBlocks()
  }

  private updateBlocks(): void {
    this.blocks = parseMarkdown(this.text)
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
        Text(block.text)
          .fontFamily(DshType.monoFamily)
          .fontSize(DshType.mono)
          .lineHeight(DshType.mono * DshType.monoHeight)
          .fontColor(this.colors.text)
          .padding(DshSpace.md)
          .copyOption(CopyOptions.LocalDevice)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Auto)
      .width('100%')
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
      this.codeBlock(block)
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
        Text(block.label)
          .fontColor(this.colors.muted)
          .fontSize(this.fontSize)
          .lineHeight(this.fontSize * DshType.bodyHeight)
          .constraintSize({ minWidth: 15 })
        Column() {
          this.inlineText(block.text, () => this.fontSize, () => this.colors.text, false)
        }
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

  build() {
    Column({ space: DshSpace.sm }) {
      ForEach(this.blocks, (block: MarkdownBlock) => {
        this.renderBlock(block)
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
