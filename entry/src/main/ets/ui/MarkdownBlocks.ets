import { mathBlockSource, mathParts } from './MathData'

export enum BlockKind {
  Paragraph,
  Heading,
  ListItem,
  Quote,
  Code,
  Table,
  Rule
}

export enum InlineKind {
  Text,
  Strong,
  Emphasis,
  Code,
  Link,
  Math
}

export class InlineRun {
  text: string
  kind: InlineKind
  url: string

  constructor(text: string, kind: InlineKind = InlineKind.Text, url: string = '') {
    this.text = text
    this.kind = kind
    this.url = url
  }
}

export class MarkdownBlock {
  kind: BlockKind
  text: string
  level: number = 0
  label: string = ''
  rows: string[][] = []
  checked?: boolean

  constructor(kind: BlockKind, text: string = '') {
    this.kind = kind
    this.text = text
  }
}

const FENCE = /^[ ]{0,3}(`{3,}|~{3,})(.*)$/
const HEADING = /^[ ]{0,3}(#{1,6})[ \t]+(.+)$/
const LIST_ITEM = /^([ \t]*)([-+*]|\d{1,9}[.)])[ \t]+(.+)$/
const TASK_MARKER = /^\[([ xX])\] (.*)$/
const QUOTE = /^[ ]{0,3}>[ \t]?/
const RULE = /^[ ]{0,3}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$/
const SETEXT = /^[ ]{0,3}(=+|-+)[ \t]*$/

function tableCells(line: string): string[] {
  const source = line.trim()
  const cells: string[] = []
  let cell = ''
  let hasPipe = false
  let codeFence = 0
  for (let index = 0; index < source.length; index++) {
    const char = source[index]
    if (char === '\\' && source[index + 1] === '|') {
      cell += '|'
      index++
    } else if (char === '`') {
      let end = index + 1
      while (source[end] === '`') {
        end++
      }
      const length = end - index
      if (codeFence === 0 || codeFence === length) {
        codeFence = codeFence === 0 ? length : 0
      }
      cell += source.substring(index, end)
      index = end - 1
    } else if (char === '|' && codeFence === 0) {
      if (index !== 0) {
        cells.push(cell.trim())
      }
      cell = ''
      hasPipe = true
    } else {
      cell += char
    }
  }
  if (!hasPipe) {
    return []
  }
  if (cell.length > 0 || !source.endsWith('|')) {
    cells.push(cell.trim())
  }
  return cells
}

function tableWidth(lines: string[], index: number): number {
  if (index + 1 >= lines.length) {
    return 0
  }
  const header = tableCells(lines[index])
  const separators = tableCells(lines[index + 1])
  return header.length > 0 && header.length === separators.length &&
    separators.every((cell: string) => /^:?-+:?$/.test(cell)) ? header.length : 0
}

function startsBlock(lines: string[], index: number): boolean {
  const line = lines[index]
  return !line.trim() || FENCE.test(line) || HEADING.test(line) || RULE.test(line) ||
    QUOTE.test(line) || LIST_ITEM.test(line) || TASK_MARKER.test(line.trimStart()) || tableWidth(lines, index) > 0
}

export function parseMarkdown(source: string, streaming: boolean = false): MarkdownBlock[] {
  const lines = mathBlockSource(source, streaming).replace(/\r\n?/g, '\n').split('\n')
  const blocks: MarkdownBlock[] = []
  let index = 0
  while (index < lines.length) {
    const line = lines[index]
    index++
    if (!line.trim()) {
      continue
    }
    const fence = FENCE.exec(line)
    if (fence) {
      const content: string[] = []
      const closing = new RegExp('^[ ]{0,3}' + fence[1][0] + '{' + fence[1].length + ',}[ \\t]*$')
      while (index < lines.length && !closing.test(lines[index])) {
        content.push(lines[index])
        index++
      }
      if (index < lines.length) {
        index++
      }
      const block = new MarkdownBlock(BlockKind.Code, content.join('\n'))
      block.label = fence[2].trim().split(/\s+/)[0]
      blocks.push(block)
      continue
    }
    const heading = HEADING.exec(line)
    const setext = index < lines.length && SETEXT.test(lines[index]) &&
      !QUOTE.test(line) && !LIST_ITEM.test(line) && !TASK_MARKER.test(line.trimStart()) && !RULE.test(line)
    if (heading || setext) {
      const block = new MarkdownBlock(BlockKind.Heading)
      if (heading) {
        block.text = heading[2].replace(/[ \t]+#+[ \t]*$/, '')
        block.level = heading[1].length
      } else {
        block.text = line.trim()
        block.level = lines[index].trim().startsWith('=') ? 1 : 2
        index++
      }
      blocks.push(block)
      continue
    }
    if (RULE.test(line)) {
      blocks.push(new MarkdownBlock(BlockKind.Rule))
      continue
    }
    const columns = tableWidth(lines, index - 1)
    if (columns > 0) {
      const block = new MarkdownBlock(BlockKind.Table)
      block.rows.push(tableCells(line))
      index++
      while (index < lines.length && lines[index].trim()) {
        const row = tableCells(lines[index])
        if (row.length === 0) {
          break
        }
        while (row.length < columns) {
          row.push('')
        }
        block.rows.push(row.slice(0, columns))
        index++
      }
      blocks.push(block)
      continue
    }
    if (QUOTE.test(line)) {
      const quote: string[] = [line.replace(QUOTE, '')]
      while (index < lines.length && QUOTE.test(lines[index])) {
        quote.push(lines[index].replace(QUOTE, ''))
        index++
      }
      blocks.push(new MarkdownBlock(BlockKind.Quote, quote.join('\n')))
      continue
    }
    const list = LIST_ITEM.exec(line)
    const body = list ? list[3] : line.trimStart()
    const task = TASK_MARKER.exec(body)
    if (list || task) {
      const block = new MarkdownBlock(BlockKind.ListItem, task ? task[2] : body)
      if (task) {
        block.checked = task[1] !== ' '
      }
      if (list) {
        block.label = list[2].length === 1 ? (task ? '' : '•') : list[2].replace(/\)$/, '.')
        block.level = Math.min(4, Math.floor(list[1].replace(/\t/g, '  ').length / 2))
        while (index < lines.length && /^\s+\S/.test(lines[index]) && !startsBlock(lines, index)) {
          block.text += '\n' + lines[index].trim()
          index++
        }
      }
      blocks.push(block)
      continue
    }
    const paragraph: string[] = [line.trim()]
    while (index < lines.length && !startsBlock(lines, index) &&
      !(index + 1 < lines.length && SETEXT.test(lines[index + 1]))) {
      paragraph.push(lines[index].trim())
      index++
    }
    blocks.push(new MarkdownBlock(BlockKind.Paragraph, paragraph.join('\n')))
  }
  return blocks
}

export function isWebLink(url: string): boolean {
  return /^https?:\/\/[^\s<>"']+$/i.test(url)
}

export function isMessageLink(url: string): boolean {
  return isWebLink(url) || /^dshgo:\/\/open\/[A-Za-z0-9_-]+$/i.test(url)
}

function parseInlinePlain(source: string): InlineRun[] {
  const spans: InlineRun[] = []
  // Underscores require a word boundary on the outside and non-space on the inside.
  const token =
    /\\([\\`*_\[\]()|!])|(`+)([^\n]+?)\2(?!`)|!?\[([^\]\n]+)\]\(([^\s)]+)\)|\*\*([^*\n]+)\*\*|(?<![^\p{P}\p{S}\s]|_)__(?!\s)([^_\n]+)(?<!\s)__(?![^\p{P}\p{S}\s]|_)|\*([^*\n]+)\*|(?<![^\p{P}\p{S}\s]|_)_(?!\s)([^_\n]+)(?<!\s)_(?![^\p{P}\p{S}\s]|_)|<(https?:\/\/[^\s<>]+)>|(https?:\/\/[^\s<>]+)/giu
  let offset = 0
  let match = token.exec(source)
  while (match !== null) {
    if (match.index > offset) {
      spans.push(new InlineRun(source.substring(offset, match.index)))
    }
    if (match[1]) {
      spans.push(new InlineRun(match[1]))
    } else if (match[3]) {
      spans.push(new InlineRun(match[3], InlineKind.Code))
    } else if (match[4]) {
      const url = match[5]
      spans.push(isMessageLink(url) && !match[0].startsWith('!')
        ? new InlineRun(match[4], InlineKind.Link, url)
        : new InlineRun(match[0]))
    } else if (match[6] || match[7]) {
      spans.push(new InlineRun(match[6] || match[7], InlineKind.Strong))
    } else if (match[8] || match[9]) {
      spans.push(new InlineRun(match[8] || match[9], InlineKind.Emphasis))
    } else {
      const raw = match[10] || match[11]
      const url = match[10] ? raw : raw.replace(/[.,;!?，。；！？]+$/, '')
      if (isWebLink(url)) {
        spans.push(new InlineRun(url, InlineKind.Link, url))
        if (url !== raw) {
          spans.push(new InlineRun(raw.substring(url.length)))
        }
      } else {
        spans.push(new InlineRun(match[0]))
      }
    }
    offset = token.lastIndex
    match = token.exec(source)
  }
  if (offset < source.length) {
    spans.push(new InlineRun(source.substring(offset)))
  }
  return spans
}

export function parseInline(source: string): InlineRun[] {
  const result: InlineRun[] = []
  for (const part of mathParts(source)) {
    if (part.math) result.push(new InlineRun(part.text, InlineKind.Math))
    else result.push(...parseInlinePlain(part.text))
  }
  return result
}
