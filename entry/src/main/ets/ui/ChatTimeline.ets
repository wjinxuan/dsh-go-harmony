import type { DshCommandNotice, DshMessage, DshTool, DshTurnNotice, DshTurnTrace, WireObject } from '../dsh/DshWire'
import type { SessionArtifact } from './SessionArtifacts'

export interface ChatRow {
  key: string;
  position: number;
  message?: DshMessage;
  tool?: DshTool;
  tools?: DshTool[];
  artifacts?: SessionArtifact[];
  notice?: DshTurnNotice;
  command?: DshCommandNotice;
  process?: ChatRow[];
  processId?: string;
  processTools?: number;
  processMessages?: number;
  cardOnly?: boolean;
  rowOnly?: boolean;
}

export class ChatTimeline {
  private sessionId: string = ''
  private rows: Map<string, ChatRow> = new Map()
  private revision: number = 0

  update(sessionId: string, messages: DshMessage[], tools: DshTool[], notices: DshTurnNotice[] = [],
    commands: DshCommandNotice[] = [], artifacts: SessionArtifact[] = [], turns: DshTurnTrace[] = []): ChatRow[] {
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
        prior.usage?.outputTokens !== message.usage?.outputTokens ||
        JSON.stringify(prior.content) !== JSON.stringify(message.content)
      next.set(id, { key: old && !changed ? old.key : this.nextKey(id),
        position: message.seq ?? Number.MAX_SAFE_INTEGER, message: message })
    }
    for (const tool of tools) {
      const id = `tool:${tool.callId}`
      const old = this.rows.get(id)
      const prior = old?.tool
      const changed = !prior || prior.name !== tool.name || prior.arguments !== tool.arguments ||
        prior.result !== tool.result || (prior.isError === true) !== (tool.isError === true) ||
        JSON.stringify(prior.content) !== JSON.stringify(tool.content) || timelineMeta(prior.meta) !== timelineMeta(tool.meta) ||
        JSON.stringify(prior.failure) !== JSON.stringify(tool.failure)
      next.set(id, { key: old && !changed ? old.key : this.nextKey(id), position: tool.seq, tool: tool })
    }
    for (const notice of notices) {
      const id = `notice:${notice.seq}`
      const old = this.rows.get(id)
      const changed = !old?.notice || JSON.stringify(old.notice) !== JSON.stringify(notice)
      next.set(id, { key: old && !changed ? old.key : this.nextKey(id), position: notice.seq, notice: notice })
    }
    for (const command of commands) {
      const id = `command:${command.id}`
      const old = this.rows.get(id)
      const changed = !old?.command || JSON.stringify(old.command) !== JSON.stringify(command)
      next.set(id, { key: old && !changed ? old.key : this.nextKey(id),
        position: command.seq ?? Number.MAX_SAFE_INTEGER, command: command })
    }
    for (const item of artifacts) {
      const id = `artifacts:${item.endSeq}`
      const group = next.get(id)
      if (group?.artifacts) group.artifacts.push(item)
      else next.set(id, { key: id, position: item.endSeq + 0.5, artifacts: [item] })
    }
    for (const id of next.keys()) {
      const row = next.get(id)!
      if (!row.artifacts) continue
      const old = this.rows.get(id)
      row.key = old && JSON.stringify(old.artifacts) === JSON.stringify(row.artifacts) ? old.key : this.nextKey(id)
    }
    this.rows = next
    return groupToolRows(Array.from(next.values()).sort((a: ChatRow, b: ChatRow) => a.position - b.position), turns)
  }

  private nextKey(id: string): string {
    this.revision++
    return `${id}:${this.revision}`
  }
}

function timelineMeta(value: Object | null | undefined): string {
  const selected: WireObject = {}
  if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
    const meta = value as WireObject
    for (const key of ['dsh-go/media', 'dsh-go/view', 'diffs', 'operation', 'path']) {
      if (meta[key] !== undefined) selected[key] = meta[key]
    }
  }
  return JSON.stringify(selected)
}

export function groupToolRows(rows: ChatRow[], turns: DshTurnTrace[] = []): ChatRow[] {
  const grouped: ChatRow[] = []; let run: ChatRow[] = []
  const boundary = (position: number): number => turns.findIndex((turn: DshTurnTrace) => position >= turn.startSeq && position <= (turn.endSeq ?? Number.MAX_SAFE_INTEGER))
  const flush = (): void => {
    if (run.length >= 3) grouped.push({ key: `group:${run.map((row: ChatRow) => row.key).join('|')}`,
      position: run[0].position, tools: run.map((row: ChatRow) => row.tool!) })
    else for (const row of run) grouped.push(row)
    run = []
  }
  for (const row of rows) {
    const meta = row.tool?.meta
    const card = meta !== null && typeof meta === 'object' &&
      Object.keys(meta).some((key: string) => key === 'dsh-go/media' || key === 'dsh-go/view')
    if (row.tool && !card) { if (run.length && boundary(run[0].position) !== boundary(row.position)) flush(); run.push(row) }
    else { flush(); grouped.push(row) }
  }
  flush()
  return grouped
}
