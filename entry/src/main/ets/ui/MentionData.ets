import { util } from '@kit.ArkTS'
import type { DshClient } from '../dsh/DshClient'
import { object, string, WireObject, DshSession } from '../dsh/DshWire'

// Ported from dsh-Go a9877420: mention_syntax/controller and references_api.
export type MentionKind = 'file' | 'folder' | 'session'
export interface MentionToken { start: number; end: number; kind: MentionKind; label: string }
export interface MentionQuery { start: number; end: number; query: string; quoted: boolean; pathOnly: boolean }
export interface MentionItem {
  key: string; kind: MentionKind; label: string; mention: string; detail: string;
  path?: string; sessionId?: string; subagent: boolean
}
export interface MentionSection { title: string; items: MentionItem[] }
export interface MentionRecent { key: string; mention: string; cwd?: string; sessionId?: string }
interface RankedMention { item: MentionItem; score: number; updatedAt: number }
interface MentionLookup { sections: MentionSection[]; cwd: string }
export interface MentionEdit { text: string; start: number; end: number }

export class MentionLabels {
  static readonly all: Set<string> = new Set()
  static add(label: string): void { if (label.trim()) MentionLabels.all.add(label.trim()) }
  static clear(): void { MentionLabels.all.clear() }
}

export function formatFileMention(path: string, directory: boolean = false, quoted: boolean = false): string | undefined {
  const text = directory ? `${path}/` : path
  if (!path || /[\u0000-\u001f\u007f-\u009f"]/.test(text)) return undefined
  if (!quoted && !/\s/.test(text)) return `@${text}`
  return directory ? `@"${text}` : `@"${text}"`
}

export function encodeSessionReferenceUri(id: string): string {
  const bytes = new util.TextEncoder().encodeInto(JSON.stringify(id))
  return `dsh-session:${new util.Base64Helper().encodeToStringSync(bytes).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')}`
}

export function decodeSessionReferenceUri(uri: string): string | undefined {
  if (!/^dsh-session:[A-Za-z0-9_-]+$/.test(uri)) return undefined
  try {
    const payload = uri.substring(12).replace(/-/g, '+').replace(/_/g, '/')
    const bytes = new util.Base64Helper().decodeSync(payload + '='.repeat((4 - payload.length % 4) % 4))
    const id: Object = JSON.parse(util.TextDecoder.create('utf-8', { fatal: true }).decodeWithStream(bytes))
    return typeof id === 'string' && encodeSessionReferenceUri(id) === uri ? id : undefined
  } catch { return undefined }
}

export function formatSessionMention(id: string, label: string): string {
  return `@[${label.replace(/[\\\]]/g, '\\$&')}](${encodeSessionReferenceUri(id)})`
}

export function mentionToken(raw: string, start: number): MentionToken | undefined {
  const session = /^@\[((?:\\.|[^\\\]\n])*)\]\((dsh-session:[A-Za-z0-9_-]+)\)$/.exec(raw)
  if (session && decodeSessionReferenceUri(session[2]) !== undefined) {
    return { start: start, end: start + raw.length, kind: 'session', label: session[1].replace(/\\(.)/g, '$1') }
  }
  if (!raw.startsWith('@') || raw.length < 2 || raw.startsWith('@[')) return undefined
  const quoted = raw.startsWith('@"')
  let path = raw.substring(quoted ? 2 : 1)
  if (quoted && path.endsWith('"')) path = path.substring(0, path.length - 1)
  if (!path) return undefined
  const folder = path.endsWith('/')
  const parts = path.split(/[\\/]/).filter((part: string) => !!part)
  const name = parts[parts.length - 1] || path
  return { start: start, end: start + raw.length, kind: folder ? 'folder' : 'file', label: folder ? `${name}/` : name }
}

export function parseMessageMentions(text: string, labels: string[] = []): MentionToken[] {
  if (!text.includes('@')) return []
  const tokens: MentionToken[] = []
  const sessions = /@\[((?:\\.|[^\\\]\n])*)\]\((dsh-session:[A-Za-z0-9_-]+)\)/g
  let match: RegExpExecArray | null
  while ((match = sessions.exec(text)) !== null) {
    const token = mentionToken(match[0], match.index)
    if (token) { tokens.push(token); MentionLabels.add(token.label) }
  }
  const free = (start: number, end: number): boolean => !tokens.some((t: MentionToken) => t.start < end && start < t.end)
  const known = labels.filter((label: string) => !!label).sort((a: string, b: string) => b.length - a.length)
  for (let at = text.indexOf('@'); at >= 0; at = text.indexOf('@', at + 1)) {
    if (at > 0 && !/[ \n\t\r\u3000]/.test(text[at - 1])) continue
    for (const label of known) {
      if (!text.startsWith(label, at + 1)) continue
      const end = at + 1 + label.length
      if (end < text.length && !/[ \n\t\r\u3000，。；：！？、,.;:!?)）]/.test(text[end])) continue
      if (free(at, end)) tokens.push({ start: at, end: end, kind: 'session', label: label })
      break
    }
  }
  const paths = /(^|\s)(@"[^"\n]+"|@"[^"\n]*\/(?=\s|$)|@[^\s"]+)/g
  while ((match = paths.exec(text)) !== null) {
    let raw = match[2]
    const start = match.index + match[1].length
    if (!raw.startsWith('@"')) {
      raw = raw.replace(/[.,;:!?，。；：！？、）)]+$/, '')
      const path = raw.substring(1)
      if (!path.includes('/') && !path.startsWith('~') && !/^[^.]+\.[A-Za-z0-9]|^\.[A-Za-z0-9]/.test(path)) continue
    }
    if (!free(start, start + raw.length)) continue
    const token = mentionToken(raw, start)
    if (token) tokens.push(token)
  }
  return tokens.sort((a: MentionToken, b: MentionToken) => a.start - b.start)
}

export function activeMentionQuery(text: string, caret: number, tokens: MentionToken[] = []): MentionQuery | undefined {
  if (caret < 1 || caret > text.length) return undefined
  const line = text.lastIndexOf('\n', caret - 1) + 1
  const before = text.substring(line, caret)
  const match = /(?:^|\s)(@"([^"]*))$/.exec(before) || /(?:^|\s)(@([^\s]*))$/.exec(before)
  if (!match) return undefined
  const start = line + match.index + match[0].indexOf('@')
  if (tokens.some((t: MentionToken) => t.start <= start && start < t.end)) return undefined
  const quoted = match[1].startsWith('@"')
  return { start: start, end: caret, query: match[2], quoted: quoted, pathOnly: quoted || match[2].includes('/') }
}

export function fuzzyMentionScore(text: string, query: string): number | undefined {
  if (!query) return 0
  const t = text.toLowerCase(), q = query.toLowerCase(), at = t.indexOf(q)
  if (at === 0) return 1000 - t.length
  if (at > 0) return (/[ \n\t\r\u3000/_\-.]/.test(t[at - 1]) ? 800 : 600) - at - t.length / 100
  let ti = 0, gaps = 0
  for (let i = 0; i < q.length; i++) {
    const next = t.indexOf(q[i], ti)
    if (next < 0) return undefined
    gaps += next - ti
    ti = next + 1
  }
  return 300 - gaps - t.length / 100
}

export function mentionAge(time: number, now: number): string {
  const minutes = Math.floor((now - time) / 60000)
  if (minutes < 1) return '刚刚'
  if (minutes < 60) return `${minutes}分钟`
  if (minutes < 1440) return `${Math.floor(minutes / 60)}小时`
  const days = Math.floor(minutes / 1440)
  if (days < 30) return `${days}天`
  if (days < 365) return `${Math.floor(days / 30)}个月`
  return `${Math.floor(days / 365)}年`
}

export function mentionRecents(value: Object | null | undefined): MentionRecent[] {
  if (!Array.isArray(value)) return []
  const entries: MentionRecent[] = []
  for (const item of value as Object[]) {
    const row = object(item)
    const key = string(row['key']), mention = string(row['mention'])
    if (!/^[fs]:.+/.test(key) || !mention || entries.some((entry: MentionRecent) => entry.key === key)) continue
    entries.push({ key: key, mention: mention, cwd: string(row['cwd']), sessionId: string(row['sessionId']) })
    if (entries.length === 12) break
  }
  return entries
}

// RichEditor builder spans are one visible character; wire references keep their exact text.
export function mentionDisplayOffset(raw: number, tokens: MentionToken[]): number {
  let delta = 0
  for (const t of tokens) {
    if (raw <= t.start) break
    if (raw < t.end) return t.start - delta + 1
    delta += t.end - t.start - 1
  }
  return raw - delta
}

export function mentionRawOffset(display: number, tokens: MentionToken[]): number {
  let delta = 0
  for (const t of tokens) {
    if (display <= t.start - delta) break
    delta += t.end - t.start - 1
  }
  return display + delta
}

export class MentionComposer {
  revision: number = 0
  text: string = ''
  tokens: MentionToken[] = []
  start: number = 0
  end: number = 0

  restore(text: string): void {
    this.revision++
    this.text = text
    this.tokens = parseMessageMentions(text)
    this.start = this.end = text.length
  }

  select(start: number, end: number): void {
    this.start = Math.max(0, Math.min(start, this.text.length))
    this.end = Math.max(this.start, Math.min(end, this.text.length))
    for (const token of this.tokens) {
      if (token.start < this.start && this.start < token.end) this.start = token.start
      if (token.start < this.end && this.end < token.end) this.end = token.end
    }
  }

  replace(start: number, end: number, inserted: string, parse: boolean = true, picked?: MentionToken): void {
    this.revision++
    const previous = this.text
    start = Math.max(0, Math.min(start, previous.length))
    end = Math.max(start, Math.min(end, previous.length))
    for (const token of this.tokens) {
      if (start === end && token.start < start && start < token.end) start = end = token.end
      else if (token.start < end && start < token.end) {
        start = Math.min(start, token.start); end = Math.max(end, token.end)
      }
    }
    const delta = inserted.length - (end - start)
    this.text = previous.substring(0, start) + inserted + previous.substring(end)
    this.tokens = this.tokens.filter((t: MentionToken) => t.end <= start || t.start >= end)
      .map((t: MentionToken): MentionToken => t.start >= end ?
        { start: t.start + delta, end: t.end + delta, kind: t.kind, label: t.label } : t)
    const added = picked ? [picked] : parse && inserted.length > 1 ?
      parseMessageMentions(this.text).filter((t: MentionToken) => t.start >= start && t.end <= start + inserted.length) : []
    this.tokens = this.tokens.concat(added).sort((a: MentionToken, b: MentionToken) => a.start - b.start)
    this.start = this.end = start + inserted.length
  }

  insert(raw: string, start: number, end: number): void {
    const followsSpace = end < this.text.length && /[ \n\t\u3000]/.test(this.text[end])
    this.replace(start, end, followsSpace ? raw : `${raw} `, false, mentionToken(raw, start))
    if (followsSpace) this.start = this.end = this.end + 1
  }
}

export class MentionPickerController {
  readonly composer: MentionComposer = new MentionComposer()
  sections: MentionSection[] = []
  query?: MentionQuery
  loading: boolean = false
  highlighted: number = -1
  recents: MentionRecent[] = []
  onChange: () => void = () => {}
  onLabelsChange: () => void = () => {}
  onRecents: (entries: MentionRecent[]) => void = () => {}
  private client: DshClient
  private sessionId: string = ''
  private connection: number = -1
  private generation: number = 0
  private dismissedAt: number = -1
  private timer?: number
  private all?: Promise<DshSession[]>
  private base?: Promise<WireObject[]>
  private local?: Promise<DshSession[]>
  private cwd: string = ''

  constructor(client: DshClient) { this.client = client }

  get isOpen(): boolean { return !!this.query && this.dismissedAt !== this.query.start }
  get items(): MentionItem[] {
    const items: MentionItem[] = []
    for (const section of this.sections) items.push(...section.items)
    return items
  }

  setContext(sessionId: string): void {
    const connection = this.client.connectionIdentity()
    if (sessionId === this.sessionId && connection === this.connection) return
    if (connection !== this.connection) { MentionLabels.clear(); this.onLabelsChange() }
    this.sessionId = sessionId; this.connection = connection
    this.reset()
    this.local = this.client.listSessions().catch((): DshSession[] => [])
    void this.local.then((items: DshSession[]) => {
      if (sessionId !== this.sessionId || connection !== this.client.connectionIdentity()) return
      for (const item of items) MentionLabels.add(item.title)
      this.onLabelsChange()
    })
  }

  restore(text: string): void { this.composer.restore(text); this.reset(); this.onChange() }

  changed(): void { this.updateQuery(); this.onChange() }

  select(start: number, end: number): void { this.composer.select(start, end); this.updateQuery(); this.onChange() }

  dismiss(): void {
    if (!this.query) return
    this.dismissedAt = this.query.start
    this.cancel()
    this.loading = false
    this.onChange()
  }

  reset(): void {
    this.cancel(); this.query = undefined; this.sections = []; this.highlighted = -1
    this.dismissedAt = -1; this.loading = false; this.all = undefined; this.base = undefined; this.local = undefined
  }

  private cancel(): void {
    this.generation++
    if (this.timer !== undefined) clearTimeout(this.timer)
    this.timer = undefined
  }

  private updateQuery(): void {
    if (this.connection !== this.client.connectionIdentity()) { this.reset(); return }
    const c = this.composer
    const next = c.start === c.end ? activeMentionQuery(c.text, c.end, c.tokens) : undefined
    const previous = this.query
    if (next?.start === previous?.start && next?.end === previous?.end && next?.query === previous?.query &&
      next?.quoted === previous?.quoted) return
    this.query = next
    if (!next) { this.reset(); return }
    if (!previous || previous.start !== next.start) this.dismissedAt = -1
    if (this.dismissedAt === next.start) return
    this.cancel(); this.sections = []; this.highlighted = -1; this.loading = true
    const generation = this.generation, connection = this.connection
    const fetch = (): void => { void this.fetch(next, generation, connection) }
    if (!previous || previous.start !== next.start) fetch()
    else this.timer = setTimeout(fetch, 120)
  }

  private visibleSessions(): Promise<DshSession[]> {
    if (!this.local) this.local = this.client.listSessions().catch((): DshSession[] => [])
    return this.local
  }

  private async fetch(query: MentionQuery, generation: number, connection: number): Promise<void> {
    const result = await this.lookup(query).catch((): MentionLookup => ({ sections: [], cwd: '' }))
    if (generation !== this.generation || connection !== this.client.connectionIdentity()) return
    this.sections = result.sections; this.cwd = result.cwd; this.loading = false
    for (const item of this.items) if (item.kind === 'session') MentionLabels.add(item.label)
    this.onLabelsChange()
    this.highlighted = query.query && this.items.length ? 0 : -1
    this.onChange()
  }

  private rank(key: string): number { return this.recents.findIndex((entry: MentionRecent) => entry.key === key) }

  private ranked(rows: RankedMention[], byTime: boolean): MentionItem[] {
    rows.sort((a: RankedMention, b: RankedMention): number => {
      const ra = this.rank(a.item.key), rb = this.rank(b.item.key)
      if (ra >= 0 || rb >= 0) return ra < 0 ? 1 : rb < 0 ? -1 : ra - rb
      return (!byTime ? b.score - a.score : 0) || b.updatedAt - a.updatedAt
    })
    return rows.map((row: RankedMention) => row.item)
  }

  private async lookup(q: MentionQuery): Promise<MentionLookup> {
    const sid = this.sessionId, now = Date.now()
    if (!sid) {
      if (q.pathOnly) return { sections: [], cwd: '' }
      const rows: RankedMention[] = []
      for (const s of await this.visibleSessions()) {
        const title = s.title.trim() || s.id, score = fuzzyMentionScore(title, q.query)
        if (score === undefined) continue
        rows.push({ item: { key: `s:${s.id}`, kind: 'session', label: title, detail: mentionAge(s.updatedAt, now),
          mention: formatSessionMention(s.id, title), sessionId: s.id, subagent: false }, score: score, updatedAt: s.updatedAt })
      }
      return { sections: this.assemble(q, [], [], this.ranked(rows, !q.query), '', sid), cwd: '' }
    }
    if (!this.all) this.all = this.client.listSessions(true, true).catch((): DshSession[] => [])
    if (!this.base) this.base = this.client.sessionReferences(sid, '').catch((): WireObject[] => [])
    const filesFuture = this.client.fileReferences(sid, q.query).catch((): WireObject[] => [])
    const typedFuture = q.pathOnly || !q.query ? Promise.resolve<WireObject[]>([]) :
      this.client.sessionReferences(sid, q.query).catch((): WireObject[] => [])
    const allFuture = this.all, baseFuture = this.base, localFuture = this.visibleSessions()
    const files = await filesFuture, all = await allFuture
    const base = q.pathOnly ? [] : await baseFuture, typed = await typedFuture
    const visible = await localFuture
    const cwd = all.find((s: DshSession) => s.id === sid)?.cwd || ''
    const fileItems: MentionItem[] = []
    for (const file of files) {
      const path = string(file['path']), directory = file['kind'] === 'directory'
      const mention = formatFileMention(path, directory, q.quoted)
      if (!mention) continue
      const slash = path.lastIndexOf('/'), name = path.substring(slash + 1)
      fileItems.push({ key: `f:${path}`, kind: directory ? 'folder' : 'file', label: directory ? `${name}/` : name,
        detail: q.query.includes('/') || slash < 0 ? '' : path.substring(0, slash), mention: mention, path: path, subagent: false })
    }
    fileItems.sort((a: MentionItem, b: MentionItem) => {
      const ra = this.rank(a.key), rb = this.rank(b.key)
      return ra < 0 ? rb < 0 ? 0 : 1 : rb < 0 ? -1 : ra - rb
    })
    const children: RankedMention[] = [], conversations: RankedMention[] = [], seen: Set<string> = new Set()
    for (const row of base.concat(typed)) {
      const id = string(row['sessionId']), mention = string(row['mention'])
      if (!id || id === sid || !mention || seen.has(id)) continue
      seen.add(id)
      const summary = all.find((s: DshSession) => s.id === id)
      const child = summary?.origin === 'subagent' && summary?.parentSessionId === sid
      if (!child && (summary?.origin === 'subagent' || (visible.length && !visible.some((s: DshSession) => s.id === id)))) continue
      const title = string(row['displayTitle']) || string(row['label']) || id
      const fromServer = typed.some((s: WireObject) => s['sessionId'] === id)
      const score = fuzzyMentionScore(title, q.query) ?? (fromServer ? 100 : undefined)
      if (score === undefined) continue
      const created = row['createdAt'], timestamp = typeof created === 'string' ? Date.parse(created) : typeof created === 'number' ? created : 0
      const when = summary?.updatedAt ?? (Number.isFinite(timestamp) ? timestamp : 0)
      const place = row['sameWorkspace'] === true ? '' : string(row['cwd']).split(/[\\/]/).filter((s: string) => !!s).pop() || ''
      const age = mentionAge(when, now)
      const item: MentionItem = { key: `s:${id}`, kind: 'session', label: title, detail: place ? `${place} · ${age}` : age,
        mention: mention, sessionId: id, subagent: child }
      const ranked: RankedMention = { item: item, score: score, updatedAt: when }
      if (child) children.push(ranked)
      else conversations.push(ranked)
    }
    return { sections: this.assemble(q, fileItems, this.ranked(children, !q.query), this.ranked(conversations, !q.query), cwd, sid), cwd: cwd }
  }

  private assemble(q: MentionQuery, files: MentionItem[], children: MentionItem[], chats: MentionItem[], cwd: string, sid: string): MentionSection[] {
    const sections: MentionSection[] = []
    const recent: MentionItem[] = []
    if (!q.query && !q.pathOnly) {
      const candidates = files.concat(children).concat(chats)
      for (const entry of this.recents) {
        if (entry.key.startsWith('f:') && entry.cwd !== cwd || entry.key === `s:${sid}`) continue
        const item = candidates.find((item: MentionItem) => item.key === entry.key)
        if (item) recent.push(item)
        if (recent.length === 3) break
      }
    }
    if (recent.length) sections.push({ title: '最近', items: recent })
    const rest = (items: MentionItem[], limit: number): MentionItem[] => items
      .filter((item: MentionItem) => !recent.some((picked: MentionItem) => picked.key === item.key)).slice(0, limit)
    const typed = !!q.query || q.pathOnly
    const f = rest(files, typed ? files.length : 5), c = rest(children, typed ? children.length : 4), s = rest(chats, typed ? 20 : 8)
    if (f.length) sections.push({ title: '文件', items: f })
    if (c.length) sections.push({ title: '子代理', items: c })
    if (s.length) sections.push({ title: '对话', items: s })
    return sections
  }

  pick(item: MentionItem, drill: boolean = false): boolean {
    if (!this.isOpen || this.connection !== this.client.connectionIdentity() || !this.items.includes(item) || !this.query) return false
    const q = this.query
    if (drill) {
      if (item.kind !== 'folder') return false
      this.composer.replace(q.start, q.end, item.mention, false)
    } else {
      const recent: MentionRecent = { key: item.key, mention: item.mention, cwd: item.path === undefined ? '' : this.cwd,
        sessionId: item.sessionId || this.sessionId }
      this.recents = [recent].concat(this.recents.filter((entry: MentionRecent) => entry.key !== item.key)).slice(0, 12)
      this.onRecents(this.recents)
      this.composer.insert(item.mention, q.start, q.end)
    }
    this.changed()
    return true
  }

  pickHighlighted(): boolean {
    const item = this.items[this.highlighted]
    return !!this.query?.query && !!item && this.pick(item)
  }

  key(name: string, repeated: boolean = false): boolean {
    if (!this.isOpen) return false
    if (name === 'Escape') { this.dismiss(); return true }
    const all = this.items
    if (!all.length) return false
    if (name === 'ArrowDown' || name === 'ArrowUp') {
      this.highlighted = name === 'ArrowDown' ? (this.highlighted + 1) % all.length : this.highlighted <= 0 ? all.length - 1 : this.highlighted - 1
      this.onChange(); return true
    }
    const item = all[this.highlighted]
    if (!item || repeated) return false
    return ['Enter', 'Tab'].includes(name) && this.pick(item, name === 'Tab' && item.kind === 'folder')
  }
}
