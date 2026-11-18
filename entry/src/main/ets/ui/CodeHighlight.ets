// dsh-Go a9877420 highlight_theme.dart / diff_view.dart (PiPilot-derived MIT).
// Fixed original themes and grammars are recorded under highlight/SOURCE.json.
import { HighlightRun, highlightCode, normalizedLanguage } from './highlight/FencedHighlight.js'
import { isDarkSurface } from './AnsiData'
import { SessionDiffLine, toolDiffLines } from './SessionDetailData'
import { ThemeColors } from './DshTheme'

export interface CodeStyle { color: string; background: string; italic: boolean; weight: number; underline: boolean }
export interface CodeRun { text: string; style: CodeStyle }
export interface FencedDiffLine { text: string; kind: string }
const LIGHT: Record<string, CodeStyle> = {
  'root': { color: '#1E232E', background: '#00000000', italic: false, weight: 400, underline: false },
  'keyword': { color: '#6A499B', background: '#00000000', italic: false, weight: 400, underline: false },
  'doctag': { color: '#6A499B', background: '#00000000', italic: false, weight: 400, underline: false },
  'template-tag': { color: '#6A499B', background: '#00000000', italic: false, weight: 400, underline: false },
  'selector-tag': { color: '#6A499B', background: '#00000000', italic: false, weight: 400, underline: false },
  'name': { color: '#6A499B', background: '#00000000', italic: false, weight: 400, underline: false },
  'string': { color: '#336F43', background: '#00000000', italic: false, weight: 400, underline: false },
  'regexp': { color: '#336F43', background: '#00000000', italic: false, weight: 400, underline: false },
  'meta-string': { color: '#336F43', background: '#00000000', italic: false, weight: 400, underline: false },
  'char.escape': { color: '#336F43', background: '#00000000', italic: false, weight: 400, underline: false },
  'number': { color: '#90561A', background: '#00000000', italic: false, weight: 400, underline: false },
  'literal': { color: '#90561A', background: '#00000000', italic: false, weight: 400, underline: false },
  'symbol': { color: '#90561A', background: '#00000000', italic: false, weight: 400, underline: false },
  'bullet': { color: '#90561A', background: '#00000000', italic: false, weight: 400, underline: false },
  'comment': { color: '#636975', background: '#00000000', italic: true, weight: 400, underline: false },
  'quote': { color: '#636975', background: '#00000000', italic: true, weight: 400, underline: false },
  'title': { color: '#2C5CA3', background: '#00000000', italic: false, weight: 400, underline: false },
  'title.function': { color: '#2C5CA3', background: '#00000000', italic: false, weight: 400, underline: false },
  'function': { color: '#2C5CA3', background: '#00000000', italic: false, weight: 400, underline: false },
  'section': { color: '#2C5CA3', background: '#00000000', italic: false, weight: 600, underline: false },
  'link': { color: '#2C5CA3', background: '#00000000', italic: false, weight: 400, underline: true },
  'title.class': { color: '#006E77', background: '#00000000', italic: false, weight: 400, underline: false },
  'class-title': { color: '#006E77', background: '#00000000', italic: false, weight: 400, underline: false },
  'type': { color: '#006E77', background: '#00000000', italic: false, weight: 400, underline: false },
  'built_in': { color: '#006E77', background: '#00000000', italic: false, weight: 400, underline: false },
  'selector-class': { color: '#006E77', background: '#00000000', italic: false, weight: 400, underline: false },
  'selector-id': { color: '#006E77', background: '#00000000', italic: false, weight: 400, underline: false },
  'attr': { color: '#97464F', background: '#00000000', italic: false, weight: 400, underline: false },
  'attribute': { color: '#97464F', background: '#00000000', italic: false, weight: 400, underline: false },
  'property': { color: '#97464F', background: '#00000000', italic: false, weight: 400, underline: false },
  'selector-attr': { color: '#97464F', background: '#00000000', italic: false, weight: 400, underline: false },
  'selector-pseudo': { color: '#97464F', background: '#00000000', italic: false, weight: 400, underline: false },
  'meta': { color: '#726042', background: '#00000000', italic: false, weight: 400, underline: false },
  'meta keyword': { color: '#726042', background: '#00000000', italic: false, weight: 400, underline: false },
  'operator': { color: '#4F5562', background: '#00000000', italic: false, weight: 400, underline: false },
  'punctuation': { color: '#4F5562', background: '#00000000', italic: false, weight: 400, underline: false },
  'addition': { color: '#1F613C', background: '#DCF4E3', italic: false, weight: 400, underline: false },
  'deletion': { color: '#923A37', background: '#FFE4E2', italic: false, weight: 400, underline: false },
  'emphasis': { color: '', background: '#00000000', italic: true, weight: 400, underline: false },
  'strong': { color: '', background: '#00000000', italic: false, weight: 700, underline: false }
}

const DARK: Record<string, CodeStyle> = {
  'root': { color: '#E6E9F0', background: '#00000000', italic: false, weight: 400, underline: false },
  'keyword': { color: '#C4ACF2', background: '#00000000', italic: false, weight: 400, underline: false },
  'doctag': { color: '#C4ACF2', background: '#00000000', italic: false, weight: 400, underline: false },
  'template-tag': { color: '#C4ACF2', background: '#00000000', italic: false, weight: 400, underline: false },
  'selector-tag': { color: '#C4ACF2', background: '#00000000', italic: false, weight: 400, underline: false },
  'name': { color: '#C4ACF2', background: '#00000000', italic: false, weight: 400, underline: false },
  'string': { color: '#97D2A2', background: '#00000000', italic: false, weight: 400, underline: false },
  'regexp': { color: '#97D2A2', background: '#00000000', italic: false, weight: 400, underline: false },
  'meta-string': { color: '#97D2A2', background: '#00000000', italic: false, weight: 400, underline: false },
  'char.escape': { color: '#97D2A2', background: '#00000000', italic: false, weight: 400, underline: false },
  'number': { color: '#F2BB8A', background: '#00000000', italic: false, weight: 400, underline: false },
  'literal': { color: '#F2BB8A', background: '#00000000', italic: false, weight: 400, underline: false },
  'symbol': { color: '#F2BB8A', background: '#00000000', italic: false, weight: 400, underline: false },
  'bullet': { color: '#F2BB8A', background: '#00000000', italic: false, weight: 400, underline: false },
  'comment': { color: '#868C97', background: '#00000000', italic: true, weight: 400, underline: false },
  'quote': { color: '#868C97', background: '#00000000', italic: true, weight: 400, underline: false },
  'title': { color: '#95BDF8', background: '#00000000', italic: false, weight: 400, underline: false },
  'title.function': { color: '#95BDF8', background: '#00000000', italic: false, weight: 400, underline: false },
  'function': { color: '#95BDF8', background: '#00000000', italic: false, weight: 400, underline: false },
  'section': { color: '#95BDF8', background: '#00000000', italic: false, weight: 600, underline: false },
  'link': { color: '#95BDF8', background: '#00000000', italic: false, weight: 400, underline: true },
  'title.class': { color: '#85CFD8', background: '#00000000', italic: false, weight: 400, underline: false },
  'class-title': { color: '#85CFD8', background: '#00000000', italic: false, weight: 400, underline: false },
  'type': { color: '#85CFD8', background: '#00000000', italic: false, weight: 400, underline: false },
  'built_in': { color: '#85CFD8', background: '#00000000', italic: false, weight: 400, underline: false },
  'selector-class': { color: '#85CFD8', background: '#00000000', italic: false, weight: 400, underline: false },
  'selector-id': { color: '#85CFD8', background: '#00000000', italic: false, weight: 400, underline: false },
  'attr': { color: '#ECA4A9', background: '#00000000', italic: false, weight: 400, underline: false },
  'attribute': { color: '#ECA4A9', background: '#00000000', italic: false, weight: 400, underline: false },
  'property': { color: '#ECA4A9', background: '#00000000', italic: false, weight: 400, underline: false },
  'selector-attr': { color: '#ECA4A9', background: '#00000000', italic: false, weight: 400, underline: false },
  'selector-pseudo': { color: '#ECA4A9', background: '#00000000', italic: false, weight: 400, underline: false },
  'meta': { color: '#BFAF95', background: '#00000000', italic: false, weight: 400, underline: false },
  'meta keyword': { color: '#BFAF95', background: '#00000000', italic: false, weight: 400, underline: false },
  'operator': { color: '#B6BBC5', background: '#00000000', italic: false, weight: 400, underline: false },
  'punctuation': { color: '#B6BBC5', background: '#00000000', italic: false, weight: 400, underline: false },
  'addition': { color: '#98D5AC', background: '#1C3424', italic: false, weight: 400, underline: false },
  'deletion': { color: '#F2A7A1', background: '#422423', italic: false, weight: 400, underline: false },
  'emphasis': { color: '', background: '#00000000', italic: true, weight: 400, underline: false },
  'strong': { color: '', background: '#00000000', italic: false, weight: 700, underline: false }
}

export function fencedCodeLanguage(label: string): string { return normalizedLanguage(label) }

export function fencedCodeStyle(scopes: string[], colors: ThemeColors): CodeStyle {
  const theme = isDarkSurface(colors.codeSurface) ? DARK : LIGHT
  let color = colors.text
  let background = '#00000000'
  let italic = false
  let weight = 400
  let underline = false
  for (const scope of scopes) {
    const style = theme[scope]
    if (!style) continue
    if (style.color) color = scope === 'root' ? colors.text :
      scope === 'operator' || scope === 'punctuation' ? colors.muted : style.color
    if (style.background !== '#00000000') background = style.background
    if (style.italic) italic = true
    if (style.weight !== 400) weight = style.weight
    if (style.underline) underline = true
  }
  return { color: color, background: background, italic: italic, weight: weight, underline: underline }
}

export function fencedCodeRuns(code: string, label: string, colors: ThemeColors): CodeRun[] {
  return highlightCode(code, label).map((run: HighlightRun): CodeRun =>
    ({ text: run.text, style: fencedCodeStyle(run.scopes, colors) }))
}

export function fencedDiffLines(code: string): FencedDiffLine[] {
  // Use the shared tool diff parser where a complete unified header is present.
  // Bare fenced snippets also have meaning in the original parseUnifiedDiff.
  const parsed: SessionDiffLine[] = toolDiffLines('', '{}', code, undefined)
  return code.split('\n').map((text: string, index: number): FencedDiffLine => {
    const marker = parsed[index]?.marker
    const kind = text.startsWith('@@') ? 'hunk' :
      /^(\+\+\+|---|diff |index )/.test(text) ? 'meta' :
      marker === '+' || text.startsWith('+') ? 'add' :
      marker === '-' || text.startsWith('-') ? 'del' : 'context'
    return { text: text, kind: kind }
  })
}

export function fencedDiffStyle(kind: string, colors: ThemeColors): CodeStyle {
  if (kind === 'add' || kind === 'del') return fencedCodeStyle([kind === 'add' ? 'addition' : 'deletion'], colors)
  return { color: kind === 'hunk' || kind === 'meta' ? colors.muted : colors.text,
    background: kind === 'hunk' ? colors.codeHeader : '#00000000', italic: false, weight: 400, underline: false }
}
