import { DrawContext, LengthMetrics, UIContext } from '@kit.ArkUI'
import { common2D, drawing, text as graphicsText } from '@kit.ArkGraphics2D'
import { MentionLabels, MentionToken, parseMessageMentions } from './MentionData'
import { DshGlyphs, DshType, ThemeColors, themeColors } from './DshTheme'

export interface MentionMessagePart {
  text: string;
  token?: MentionToken;
}

export function mentionMessageParts(value: string): MentionMessagePart[] {
  const parts: MentionMessagePart[] = []
  let at = 0
  for (const token of parseMessageMentions(value, Array.from(MentionLabels.all))) {
    if (token.start > at) parts.push({ text: value.substring(at, token.start) })
    parts.push({ text: value.substring(token.start, token.end), token: token })
    at = token.end
  }
  if (at < value.length) parts.push({ text: value.substring(at) })
  return parts
}

function mentionColor(value: string, alpha: number = 255): common2D.Color {
  return { alpha: alpha, red: parseInt(value.substring(1, 3), 16),
    green: parseInt(value.substring(3, 5), 16), blue: parseInt(value.substring(5, 7), 16) }
}

class MentionMessageSpan extends CustomSpan {
  private static fonts?: graphicsText.FontCollection
  private token: MentionToken
  private colors: ThemeColors
  private ui: UIContext
  private label?: graphicsText.Paragraph
  private icon?: graphicsText.Paragraph
  private width: number = 0
  private height: number = 0
  private iconWidth: number = 0

  constructor(token: MentionToken, colors: ThemeColors, ui: UIContext) {
    super()
    this.token = token; this.colors = colors; this.ui = ui
  }

  private paragraph(value: string, style: graphicsText.TextStyle, width: number): graphicsText.Paragraph {
    if (!MentionMessageSpan.fonts) {
      MentionMessageSpan.fonts = graphicsText.FontCollection.getGlobalInstance()
      MentionMessageSpan.fonts.loadFontSync(DshGlyphs.family, $rawfile('fonts/DshIcons.ttf'))
    }
    const builder = new graphicsText.ParagraphBuilder({ maxLines: 1 }, MentionMessageSpan.fonts)
    builder.pushStyle(style)
    builder.addText(value)
    const paragraph = builder.build()
    paragraph.layoutSync(width)
    return paragraph
  }

  onMeasure(info: CustomSpanMeasureInfo): CustomSpanMetrics {
    const size = this.ui.fp2px(info.fontSize)
    this.iconWidth = size * 0.8125
    const maximum = Math.min(this.ui.vp2px(200), info.maxWidth ?? this.ui.vp2px(200))
    const labelWidth = Math.max(0, maximum - this.iconWidth - this.ui.vp2px(17))
    this.label = this.paragraph(this.token.label, { fontSize: size * 0.875,
      fontWeight: graphicsText.FontWeight.W500, color: mentionColor(this.colors.text),
      heightScale: 1.25, heightOnly: true, ellipsis: '…' }, labelWidth)
    const glyph = this.token.kind === 'session' ? DshGlyphs.chat :
      this.token.kind === 'folder' ? DshGlyphs.folder : DshGlyphs.file
    this.icon = this.paragraph(glyph, { fontSize: this.iconWidth,
      fontFamilies: [DshGlyphs.family], color: mentionColor(this.colors.primary) }, this.iconWidth)
    this.width = Math.min(maximum, this.label.getLongestLine() + this.iconWidth + this.ui.vp2px(17))
    this.height = Math.max(this.label.getHeight(), this.icon.getHeight()) + this.ui.vp2px(2)
    return { width: this.ui.px2vp(this.width), height: this.ui.px2vp(this.height) }
  }

  onDraw(context: DrawContext, info: CustomSpanDrawInfo): void {
    if (!this.label || !this.icon) return
    const center = (info.lineTop + info.lineBottom) / 2
    const top = center - this.height / 2
    const margin = this.ui.vp2px(1)
    const brush = new drawing.Brush()
    brush.setAntiAlias(true)
    const foreground = mentionColor(this.colors.text)
    brush.setColor(foreground.red > 128 ? { alpha: 23, red: 255, green: 255, blue: 255 } :
      mentionColor(this.colors.text, 15))
    context.canvas.attachBrush(brush)
    context.canvas.drawRoundRect(new drawing.RoundRect({ left: info.x + margin, top: top,
      right: info.x + this.width - margin, bottom: top + this.height }, this.height / 2, this.height / 2))
    context.canvas.detachBrush()
    this.icon.paint(context.canvas, info.x + this.ui.vp2px(6), center - this.icon.getHeight() / 2)
    this.label.paint(context.canvas, info.x + this.ui.vp2px(9) + this.iconWidth, center - this.label.getHeight() / 2)
  }
}

@Component
export struct MentionMessage {
  @Prop @Watch('updateText') text: string = ''
  @Prop @Watch('updateText') colors: ThemeColors = themeColors()
  @Prop @Watch('updateText') fontSize: number = 16
  @Prop @Watch('updateText') labelsRevision: number = 0
  private controller: TextController = new TextController()
  private ready: boolean = false

  aboutToDisappear(): void { this.ready = false }

  private updateText(): void {
    if (!this.ready) return
    const styled = new MutableStyledString('')
    for (const part of mentionMessageParts(this.text)) {
      styled.appendStyledString(part.token ? new StyledString(new MentionMessageSpan(part.token, this.colors, this.getUIContext())) :
        new StyledString(part.text, [{ start: 0, length: part.text.length, styledKey: StyledStringKey.FONT,
          styledValue: new TextStyle({ fontSize: LengthMetrics.fp(this.fontSize), fontColor: this.colors.text }) }]))
    }
    this.controller.setStyledString(styled)
  }

  build() {
    Text(undefined, { controller: this.controller })
      .width('100%').fontSize(this.fontSize).fontColor(this.colors.text)
      .lineHeight(this.fontSize * DshType.bodyHeight).wordBreak(WordBreak.BREAK_WORD)
      // The parent message menu copies the original wire text, including complete references.
      .copyOption(CopyOptions.None).accessibilityText(this.text)
      .onAppear(() => { this.ready = true; this.updateText() })
  }
}
