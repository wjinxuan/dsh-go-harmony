import { object, string, DshRpcError } from './DshWire.ts'

export const DSBOT_ENDPOINTS: string[] = ['hello', 'state', 'avatar', 'chat', 'room-chat', 'send', 'file-text', 'duplicate-bot',
  'create-bot', 'update-bot', 'folders', 'delete-bot', 'set-main', 'create-room', 'update-room', 'delete-room', 'room-continue',
  'stop-member-work', 'approval-answer', 'answer-question', 'dismiss-question', 'view-reply', 'dismiss-view', 'memory-view',
  'memory-forget', 'memory-edit', 'memory-add', 'usage-summary', 'notices']
export interface DsBotEvent { event: string; data: WireObject }
export function dsBotAnswer(value: Object | null | undefined): Object | null {
  const answer = object(value)
  if (typeof answer['ok'] !== 'boolean') throw new DshRpcError('bot/protocol', 'DS Bot 返回了无效响应')
  if (answer['ok'] !== true) { const error = object(answer['error']); throw new DshRpcError(string(error['code']) || 'bot/failed', string(error['message']) || 'DS Bot 操作失败') }
  return answer['value'] ?? null
}
// Bounded incremental SSE. CRLF and UTF-8 splits are handled independently by the transport decoder.
export class DsBotSseParser {
  private tail: string = ''
  private kind: string = 'message'
  private lines: string[] = []
  private size: number = 0
  push(text: string): DsBotEvent[] {
    this.tail += text
    if (this.tail.length > 2097152) throw new Error('DS Bot 事件过大')
    const result: DsBotEvent[] = []
    let end = this.tail.indexOf('\n')
    while (end >= 0) {
      const line = this.tail.substring(0,end).replace(/\r$/, ''); this.tail = this.tail.substring(end+1)
      if (!line) {
        if (this.lines.length) { try { const value: Object = JSON.parse(this.lines.join('\n')); if (value && typeof value === 'object' && !Array.isArray(value)) result.push({ event: this.kind, data: object(value) }) } catch { /* Unknown/malformed events are ignored like the original client. */ } }
        this.kind = 'message'; this.lines = []; this.size = 0
      } else if (!line.startsWith(':')) {
        const colon = line.indexOf(':'); const key = colon < 0 ? line : line.substring(0,colon)
        const value = colon < 0 ? '' : line.substring(colon+1).replace(/^ /,'')
        if (key === 'event') this.kind = value
        if (key === 'data') { this.size += value.length; if (this.size > 2097152) throw new Error('DS Bot 事件过大'); this.lines.push(value) }
      }
      end = this.tail.indexOf('\n')
    }
    return result
  }
}
