import { array, object, string, DshSession, DshSessionSearchHit, WireObject } from '../dsh/DshWire'

export interface SessionSearchResult {
  id: string
  title: string
  cwd: string
  updatedAt: number
  archived: boolean
  titleMatch: boolean
  snippet: string
}

export function foldSearchText(value: string): string {
  let folded = ''
  for (const char of value) {
    const first = char.charCodeAt(0)
    if (first === 0x3000) folded += ' '
    else if (first >= 0xff01 && first <= 0xff5e) folded += String.fromCharCode(first - 0xfee0).toLowerCase()
    else {
      const lower = char.toLowerCase()
      folded += lower.length === char.length ? lower : char
    }
  }
  return folded
}

function searchTerms(query: string): string[] {
  return Array.from(new Set(foldSearchText(query).trim().split(/\s+/).filter((term: string) => !!term)))
}

interface MatchRange { start: number; end: number }
export interface SearchSpan { text: string; highlighted: boolean }

// The Host sends plain text. These offsets match the original title/snippet, including full-width characters.
export function searchSpans(text: string, query: string, excerpt: boolean = false): SearchSpan[] {
  const folded = foldSearchText(text)
  const ranges: MatchRange[] = []
  for (const term of searchTerms(query)) {
    let found = folded.indexOf(term)
    while (found >= 0) {
      ranges.push({ start: found, end: found + term.length })
      found = folded.indexOf(term, found + term.length)
    }
  }
  if (ranges.length === 0) return [{ text: text, highlighted: false }]
  ranges.sort((left: MatchRange, right: MatchRange) => left.start - right.start || right.end - left.end)
  const merged: MatchRange[] = [ranges[0]]
  for (let index = 1; index < ranges.length; index++) {
    const next = ranges[index]
    const last = merged[merged.length - 1]
    if (next.start <= last.end) last.end = Math.max(last.end, next.end)
    else merged.push(next)
  }
  const spans: SearchSpan[] = []
  let start = 0
  if (excerpt && merged[0].start > 15) {
    start = merged[0].start - 14
    const unit = text.charCodeAt(start)
    if (unit >= 0xdc00 && unit <= 0xdfff) start--
    const space = text.indexOf(' ', start)
    if (space >= 0 && space - start <= 8 && space < merged[0].start - 1) start = space + 1
    spans.push({ text: '…', highlighted: false })
  }
  for (const range of merged) {
    if (range.start > start) spans.push({ text: text.substring(start, range.start), highlighted: false })
    spans.push({ text: text.substring(range.start, range.end), highlighted: true })
    start = range.end
  }
  if (start < text.length) spans.push({ text: text.substring(start), highlighted: false })
  return spans
}

export function sessionSearchRows(sessions: DshSession[], query: string, hits: DshSessionSearchHit[], archivedOnly: boolean): SessionSearchResult[] {
  const terms = searchTerms(query)
  const byId: Map<string, DshSession> = new Map()
  const snippets: Map<string, string> = new Map()
  const results: SessionSearchResult[] = []
  const included: Set<string> = new Set()
  for (const session of sessions) {
    if (!archivedOnly || session.archived === true) byId.set(session.id, session)
  }
  const folders = new Set(sessions.map((row: DshSession) => sessionFolder(row.cwd)))
  for (const row of hits) {
    if (byId.has(row.sessionId) && !snippets.has(row.sessionId)) snippets.set(row.sessionId, row.snippet)
  }
  const newest = Array.from(byId.values()).sort((left: DshSession, right: DshSession) =>
    right.updatedAt - left.updatedAt || left.id.localeCompare(right.id))
  for (const session of newest) {
    const text = foldSearchText(`${session.title}\n${folders.size > 1 ? sessionFolder(session.cwd) : ''}`)
    if (terms.every((term: string) => text.includes(term))) {
      included.add(session.id)
      results.push(searchResult(session, true, snippets.get(session.id) || ''))
    }
  }
  for (const entry of snippets) {
    const session = byId.get(entry[0])
    if (session && !included.has(session.id)) results.push(searchResult(session, false, entry[1]))
  }
  return results
}

export function sessionFolder(path: string): string {
  const trimmed = path.replace(/[/\\]+$/, '')
  return trimmed.split(/[/\\]/).pop() || (path ? '/' : '')
}

function searchResult(session: DshSession, titleMatch: boolean, snippet: string): SessionSearchResult {
  return { id: session.id, title: session.title, cwd: session.cwd, updatedAt: session.updatedAt,
    archived: session.archived === true, titleMatch: titleMatch, snippet: snippet }
}

export interface HostDirectoryEntry {
  name: string
  path: string
  hidden: boolean
}

export interface HostDirectoryLevel {
  path: string
  home: string
  crumbs: HostDirectoryEntry[]
  entries: HostDirectoryEntry[]
  truncated: boolean
}

function directoryEntries(value: Object | null | undefined): HostDirectoryEntry[] {
  return array(value).map(object).filter((row: WireObject) => !!string(row['path']) && !!string(row['name']))
    .map((row: WireObject): HostDirectoryEntry => {
      return { name: string(row['name']), path: string(row['path']), hidden: row['hidden'] === true }
    })
}

export function directoryLevel(value: WireObject): HostDirectoryLevel {
  const path = string(value['path'])
  if (!path || !Array.isArray(value['entries'])) throw new Error('主机没有返回文件夹内容')
  const crumbs = directoryEntries(value['crumbs'])
  if (crumbs.length === 0) crumbs.push({ name: path, path: path, hidden: false })
  return { path: path, home: string(value['home']), crumbs: crumbs, entries: directoryEntries(value['entries']),
    truncated: value['truncated'] === true }
}

export function directoryNameProblem(value: string): string {
  const name = value.trim()
  if (!name || name.length > 120) return '请输入 1 到 120 个字符的文件夹名称'
  if (name === '.' || name === '..' || /[/\\\x00-\x1f\x7f]/.test(name)) return '名字里不能有「/」或「\\」'
  return ''
}

export function absoluteHostPath(value: string): boolean {
  return /^(?:\/|[A-Za-z]:[/\\]|\\\\[^\\]+\\[^\\]+)/.test(value) && !/[\x00-\x1f\x7f]/.test(value)
}

export function directoryParent(path: string): string {
  const trimmed = path.replace(/[/\\]+$/, '')
  const cut = Math.max(trimmed.lastIndexOf('/'), trimmed.lastIndexOf('\\'))
  if (cut < 0) return ''
  if (cut === 0 || /^[A-Za-z]:$/.test(trimmed.substring(0, cut))) return trimmed.substring(0, cut + 1)
  const parent = trimmed.substring(0, cut)
  return absoluteHostPath(parent) ? parent : ''
}

export function recentDirectoryPaths(value: Object | null | undefined): string[] {
  const paths = array(value).map(string).filter((path: string) => path.length <= 4096 && absoluteHostPath(path))
  return Array.from(new Set(paths)).slice(0, 4)
}

export function directoryPreferenceKey(scope: string): string {
  const value = scope.trim()
  if (value === 'local' || value === '本机') return 'host-local'
  const authority = value.replace(/^https?:\/\//i, '').split(/[/?#]/)[0].toLowerCase()
  if (!/^(?:[a-z0-9.-]+|\[[a-f0-9:]+\])(?::[0-9]{1,5})?$/.test(authority) || authority.length > 180) return ''
  return `host-remote-${authority}`
}

export function sessionActionError(error: Object, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback
}

export function deletionOutcomeUnknown(error: Object): boolean {
  return !(error instanceof Error) || !/（(session-active|session-related|writer-held|not-found|unavailable|busy)）/.test(error.message)
}

export class SessionDeletionGate {
  private pendingConnections: Set<number> = new Set()
  private inFlight: Set<number> = new Set()

  blocked(connection: number): boolean {
    return this.pendingConnections.has(connection) || this.inFlight.has(connection)
  }

  markUnknown(connection: number): void { this.pendingConnections.add(connection) }

  begin(connection: number): boolean {
    if (this.blocked(connection)) return false
    this.inFlight.add(connection)
    return true
  }

  end(connection: number): void { this.inFlight.delete(connection) }

  reconcile(connection: number): void {
    if (!this.inFlight.has(connection)) this.pendingConnections.delete(connection)
  }
}
