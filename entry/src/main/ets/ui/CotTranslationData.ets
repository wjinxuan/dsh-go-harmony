import { number, object, string, strings } from '../dsh/DshWire'
import type { WireObject } from '../dsh/DshWire'

export interface CotTranslationLimits {
  maxTextChars: number; provider: string; targetLanguage: string; availableProviders: string[]; usable: boolean
}
export interface ReasoningFragment { text: string; suffix: string; complete: boolean }

export function cotTranslationLimits(value: Object | null | undefined): CotTranslationLimits {
  const row = object(value), preferences = object(row['preferences'])
  const maximum = number(row['maxTextChars'], 0), provider = string(preferences['provider']) || 'bing'
  const available = strings(row['availableProviders'])
  return { maxTextChars: maximum > 0 && Number.isSafeInteger(maximum) ? maximum : 4000, provider: provider,
    targetLanguage: string(preferences['targetLanguage']) || 'auto', availableProviders: available,
    usable: !available.length || available.includes(provider) }
}

export function reasoningTranslationRequest(text: string, limits: CotTranslationLimits,
  uiLanguage: string, sessionId: string): WireObject {
  if (!text.trim() || text.length > limits.maxTextChars || !limits.usable) throw new Error('当前思考片段无法翻译')
  const request: WireObject = { 'text': text, 'provider': limits.provider,
    'targetLanguage': limits.targetLanguage === 'auto' ? uiLanguage : limits.targetLanguage }
  if (sessionId) request['sessionId'] = sessionId
  return { 'request': request }
}

export function reasoningNeedsTranslation(text: string, target: string): boolean {
  if (/(?!\p{Script=Han}|\p{Script=Latin}|\p{Script=Greek}|\p{Script=Common})\p{L}|\p{Script=Greek}{2,}/u.test(text)) return true
  const cjk = text.match(/\p{Script=Han}/gu)?.length ?? 0
  const words = text.match(/\p{Script=Latin}+/gu)?.length ?? 0
  return target.toLowerCase().startsWith('zh') ? words > cjk : cjk > words
}

export function reasoningFragments(text: string, running: boolean, maxTextChars: number): ReasoningFragment[] {
  const out: ReasoningFragment[] = [], limit = Math.max(1, Math.floor(maxTextChars))
  const breaks = /\r?\n(?:[\t ]*\r?\n)+/g
  let start = 0
  while (true) {
    const match = breaks.exec(text), paragraph = text.substring(start, match?.index ?? text.length)
    let offset = 0
    while (paragraph.length - offset > limit) {
      let cut = offset + limit
      const unit = paragraph.charCodeAt(cut - 1)
      if (unit >= 0xD800 && unit <= 0xDBFF) cut--
      if (cut === offset) throw new Error('翻译服务的片段长度限制不足以容纳当前字符')
      const whitespace = /\s+\S*$/.exec(paragraph.substring(offset, cut))
      if (whitespace && whitespace.index > 0) cut = offset + whitespace.index
      const suffix = /^\s+/.exec(paragraph.substring(cut))?.[0] || ''
      out.push({ text: paragraph.substring(offset, cut), suffix: suffix, complete: true })
      offset = cut + suffix.length
    }
    out.push({ text: paragraph.substring(offset), suffix: match?.[0] || '', complete: !!match || !running })
    if (!match) return out
    start = match.index + match[0].length
  }
}

export class ReasoningTranslation {
  pending: boolean = false
  failed: boolean = false
  onChange: () => void = () => {}
  private fragments: ReasoningFragment[] = []
  private cache: Map<string, string> = new Map()
  private disposed: boolean = false
  private maxTextChars: number
  private translate: (text: string) => Promise<string>

  constructor(maxTextChars: number, translate: (text: string) => Promise<string>) {
    this.maxTextChars = maxTextChars; this.translate = translate
  }

  get text(): string {
    return this.fragments.map((fragment: ReasoningFragment) =>
      `${fragment.complete ? this.cache.get(fragment.text) ?? fragment.text : fragment.text}${fragment.suffix}`).join('')
  }

  update(source: string, running: boolean): void {
    if (this.disposed) return
    try { this.fragments = reasoningFragments(source, running, this.maxTextChars) }
    catch { this.failed = true; this.fragments = [{ text: source, suffix: '', complete: false }] }
    this.onChange(); void this.run()
  }

  retry(): void { if (!this.disposed) { this.failed = false; void this.run() } }
  dispose(): void { this.disposed = true; this.onChange = () => {} }

  private next(): ReasoningFragment | undefined {
    return this.fragments.find((fragment: ReasoningFragment) => fragment.complete && !!fragment.text.trim() && !this.cache.has(fragment.text))
  }

  private async run(): Promise<void> {
    if (this.pending || this.failed || this.disposed || !this.next()) return
    this.pending = true; this.onChange()
    try {
      let fragment = this.next()
      while (fragment && !this.disposed) {
        const result = await this.translate(fragment.text)
        if (this.disposed) return
        if (!result.trim()) throw new Error('翻译服务返回空结果')
        this.cache.set(fragment.text, result); this.onChange(); fragment = this.next()
      }
    } catch { if (!this.disposed) this.failed = true }
    finally { this.pending = false; if (!this.disposed) this.onChange() }
  }
}

export class CotTranslationHolder {
  controller?: ReasoningTranslation
  showTranslation: boolean = false
  signature: string = ''
  reset(): void { this.controller?.dispose(); this.controller = undefined; this.showTranslation = false; this.signature = '' }
}

export class CotTranslationStore {
  private scope: string = ''
  private holders: Map<string, CotTranslationHolder> = new Map()
  get(scope: string, blockId: string): CotTranslationHolder {
    if (scope !== this.scope) { this.clear(); this.scope = scope }
    let holder = this.holders.get(blockId)
    if (!holder) { holder = new CotTranslationHolder(); this.holders.set(blockId, holder) }
    return holder
  }
  clear(): void { this.holders.forEach((holder: CotTranslationHolder) => holder.reset()); this.holders.clear() }
}
