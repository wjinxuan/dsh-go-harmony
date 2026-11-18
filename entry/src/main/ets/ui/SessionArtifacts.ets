import { array, DshSessionRecord, object, string, turnTraces, WireObject } from '../dsh/DshWire'

export interface SessionArtifact {
  path: string; name: string; kind: string; description: string; turn: number; endSeq: number; origin: string;
}

export function artifactKind(path: string): string {
  const extension = path.split('.').pop()?.toLowerCase() || ''
  const groups: Record<string, string[]> = {
    'image': ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic', 'heif', 'avif', 'tif', 'tiff', 'ico', 'svg'],
    'pdf': ['pdf'], 'document': ['doc', 'docx', 'odt', 'rtf', 'pages', 'wps', 'epub'],
    'spreadsheet': ['xls', 'xlsx', 'ods', 'csv', 'tsv', 'numbers', 'et'], 'slides': ['ppt', 'pptx', 'odp', 'key', 'dps'],
    'archive': ['zip', 'tar', 'gz', 'tgz', 'bz2', 'xz', '7z', 'rar', 'zst', 'apk'],
    'audio': ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'opus', 'amr', 'mid', 'midi'],
    'video': ['mp4', 'mov', 'webm', 'mkv', 'avi', 'm4v', '3gp'], 'web': ['html', 'htm', 'mhtml'],
    'markdown': ['md', 'markdown'], 'text': ['txt', 'log'], 'contact': ['ics', 'vcf']
  }
  return Object.keys(groups).find((kind: string) => groups[kind].includes(extension)) || 'other'
}

export function resolveArtifactPath(path: string, cwd: string = ''): string {
  if (!path.trim()) return ''
  let value = path
  if (value.startsWith('file://')) { try { value = decodeURI(value.slice(7)) } catch { return '' } }
  if (/^[A-Za-z]:[\\/]/.test(value)) return value
  if (/^[A-Za-z][A-Za-z\d+.-]*:/.test(value) || /[\x00-\x1f]/.test(value)) return ''
  if (!value.startsWith('/')) { if (!cwd.startsWith('/')) return value; value = `${cwd}/${value}` }
  const parts: string[] = []
  for (const part of value.split('/')) {
    if (!part || part === '.') continue
    if (part === '..') parts.pop(); else parts.push(part)
  }
  return `/${parts.join('/')}`
}

function nameOf(path: string): string { return path.split(/[\\/]/).pop() || path }
function artifact(path: string, turn: number, endSeq: number, origin: string, description: string = ''): SessionArtifact {
  return { path: path, name: nameOf(path), kind: artifactKind(path), description: description,
    turn: turn, endSeq: endSeq, origin: origin }
}

export function sessionArtifacts(records: DshSessionRecord[], cwd: string = ''): SessionArtifact[] {
  const closing = new Map<number, number>()
  for (const trace of turnTraces(records)) if (trace.endSeq !== undefined) closing.set(trace.turn, trace.endSeq)
  const declared = new Map<number, Map<string, SessionArtifact>>()
  const written = new Map<number, Map<string, SessionArtifact>>()
  const calls = new Map<string, WireObject>()
  const replies = new Map<number, string>(); const named = new Map<number, string[]>()
  let currentTurn = 0
  for (const record of records) {
    const data = record.data
    if (record.type === 'turn/start' && typeof data['turn'] === 'number') currentTurn = data['turn'] as number
    const turn = typeof data['turn'] === 'number' ? data['turn'] as number : currentTurn
    const endSeq = closing.get(turn)
    if (endSeq === undefined) continue
    if (record.type === 'deliverables/presented' && Number.isSafeInteger(turn) && turn > 0 &&
      string(data['callId']) && Array.isArray(data['files'])) {
      for (const raw of array(data['files'])) {
        const file = object(raw); const path = resolveArtifactPath(string(file['path']), cwd)
        if (!path.trim() || (file['description'] !== undefined && file['description'] !== null && typeof file['description'] !== 'string')) continue
        const files = declared.get(turn) || new Map<string, SessionArtifact>()
        files.set(path, artifact(path, turn, endSeq, 'delivered', string(file['description']).trim())); declared.set(turn, files)
      }
    } else if (record.type === 'tool/call') {
      const call: WireObject = { 'name': data['name'] }
      try { call['args'] = object(JSON.parse(string(data['arguments']))); } catch { continue }
      calls.set(string(data['callId']), call)
      const list = named.get(turn) || []; list.push(string(data['arguments'])); named.set(turn, list)
    } else if (record.type === 'tool/result') {
      const result = object(data['message']); const call = calls.get(string(result['toolCallId']))
      if (!call || result['isError'] === true || data['error'] || data['failure']) continue
      const args = object(call['args']); const meta = object(data['meta'])
      if (!(call['name'] === 'write' && meta['operation'] === 'create') &&
        !(call['name'] === 'str_replace_editor' && args['command'] === 'create')) continue
      const recorded = string(meta['path']); const path = resolveArtifactPath(recorded.startsWith('/') ? recorded :
        string(args['file_path']) || string(args['path']), cwd)
      if (!path || ['other', 'markdown', 'text'].includes(artifactKind(path))) continue
      const files = written.get(turn) || new Map<string, SessionArtifact>()
      if (!files.has(path)) files.set(path, artifact(path, turn, endSeq, 'written'))
      written.set(turn, files)
    } else if (record.type === 'assistant/message') {
      const text = array(object(data['message'])['content']).map((raw: Object) => {
        const content = object(raw); return content['type'] === 'text' ? string(content['text']) : ''
      }).join('')
      if (text.trim()) replies.set(turn, text)
    }
  }
  const result: SessionArtifact[] = []
  closing.forEach((endSeq: number, turn: number) => {
    const deliveries = declared.get(turn)
    if (deliveries?.size) { result.push(...Array.from(deliveries.values())); return }
    const files = written.get(turn) || new Map<string, SessionArtifact>()
    const pattern = /!?\[[^\]\n]*\]\(\s*<?([^\s)>]+)>?(?:\s+"[^"]*")?\s*\)/g
    const reply = replies.get(turn) || ''; let match: RegExpExecArray | null
    while ((match = pattern.exec(reply)) !== null) {
      let path = match[1]; try { path = decodeURI(path) } catch { continue }
      path = resolveArtifactPath(path, cwd)
      if (!path || ['other', 'markdown', 'text'].includes(artifactKind(path)) ||
        !(named.get(turn) || []).some((args: string) => args.includes(nameOf(path)))) continue
      if (!files.has(path)) files.set(path, artifact(path, turn, endSeq, 'linked'))
    }
    result.push(...Array.from(files.values()))
  })
  return result.sort((a: SessionArtifact, b: SessionArtifact) => a.endSeq - b.endSeq)
}
