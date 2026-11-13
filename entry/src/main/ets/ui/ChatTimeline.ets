import type { DshMessage, DshTool, DshTurnNotice } from '../dsh/DshWire'

export interface ChatRow {
  key: string;
  position: number;
  message?: DshMessage;
  tool?: DshTool;
  notice?: DshTurnNotice;
}

export class ChatTimeline {
  private sessionId: string = ''
  private rows: Map<string, ChatRow> = new Map()
  private revision: number = 0

  update(sessionId: string, messages: DshMessage[], tools: DshTool[], notices: DshTurnNotice[] = []): ChatRow[] {
    if (sessionId !== this.sessionId) {
      this.sessionId = sessionId
      this.rows.clear()
    }
    const next = new Map<string, ChatRow>()
    for (const message of messages) {
      const id = `message:${message.id}`
      const old = this.rows.get(id)
      const prior = old?.message
      const changed = !prior || prior.role !== message.role || prior.text !== message.text ||
        (prior.reasoning ?? '') !== (message.reasoning ?? '') || prior.usage?.inputTokens !== message.usage?.inputTokens ||
        prior.usage?.outputTokens !== message.usage?.outputTokens
      next.set(id, { key: old && !changed ? old.key : this.nextKey(id),
        position: message.seq ?? Number.MAX_SAFE_INTEGER, message: message })
    }
    for (const tool of tools) {
      const id = `tool:${tool.callId}`
      const old = this.rows.get(id)
      const prior = old?.tool
      const changed = !prior || prior.name !== tool.name || prior.arguments !== tool.arguments ||
        prior.result !== tool.result || (prior.isError === true) !== (tool.isError === true)
      next.set(id, { key: old && !changed ? old.key : this.nextKey(id), position: tool.seq, tool: tool })
    }
    for (const notice of notices) {
      const id = `notice:${notice.seq}`
      const old = this.rows.get(id)
      const changed = !old?.notice || JSON.stringify(old.notice) !== JSON.stringify(notice)
      next.set(id, { key: old && !changed ? old.key : this.nextKey(id), position: notice.seq, notice: notice })
    }
    this.rows = next
    return Array.from(next.values()).sort((a: ChatRow, b: ChatRow) => a.position - b.position)
  }

  private nextKey(id: string): string {
    this.revision++
    return `${id}:${this.revision}`
  }
}
