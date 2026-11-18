import type { DshMessage, DshTurnTrace } from '../dsh/DshWire'
import type { ChatRow } from './ChatTimeline'

function piece(rows: ChatRow[], id: string): ChatRow[] {
  let answer = -1
  for (let i = rows.length - 1; i >= 0; i--) {
    if (rows[i].tool || rows[i].tools) break
    if (rows[i].message?.role === 'assistant' && rows[i].message!.text.trim()) { answer = i; break }
  }
  const process: ChatRow[] = [], kept: ChatRow[] = []
  let tools = 0, messages = 0
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i]
    if (row.tools) { tools += row.tools.length; process.push(row) }
    else if (row.tool) {
      tools++
      const meta = row.tool.meta
      const card = meta && typeof meta === 'object' && Object.keys(meta).some((key: string) => key === 'dsh-go/media' || key === 'dsh-go/view')
      if (card) {
        process.push({ key: row.key, position: row.position, tool: row.tool, rowOnly: true })
        kept.push({ key: row.key + '/card', position: row.position, tool: row.tool, cardOnly: true })
      }
      else process.push(row)
    } else if (row.message?.role === 'assistant') {
      const message = row.message
      if (i === answer) {
        if (message.reasoning?.trim()) {
          const thinking: DshMessage = { id: message.id, role: message.role, seq: message.seq, text: '', reasoning: message.reasoning }
          process.push({ key: row.key + '/thought', position: row.position, message: thinking })
        }
        const reply: DshMessage = { id: message.id, role: message.role, seq: message.seq, text: message.text, requestId: message.requestId, content: message.content, usage: message.usage, reasoning: '' }
        kept.push({ key: row.key, position: row.position, message: reply })
      } else { if (message.text.trim()) messages++; process.push(row) }
    } else if (row.notice) process.push(row)
    else kept.push(row)
  }
  if (!process.length || (!tools && !messages && process.length <= 1)) return rows
  const folded: ChatRow = { key: 'process/' + id + '/' + rows.map((row: ChatRow) => row.key).join('|'), position: rows[0].position,
    process: process, processId: id, processTools: tools, processMessages: messages }
  return [folded].concat(kept)
}

export function foldedTurns(rows: ChatRow[], turns: DshTurnTrace[], enabled: boolean): ChatRow[] {
  if (!enabled) return rows
  const completed = turns.filter((turn: DshTurnTrace) => turn.reason === 'completed' && turn.endSeq !== undefined)
  const result: ChatRow[] = []; let pending: ChatRow[] = []; let active: DshTurnTrace | undefined = undefined
  const flush = (cut: number = -1): void => {
    if (pending.length) result.push(...piece(pending, `${active?.startSeq}/${cut}`))
    pending = []
  }
  for (const row of rows) {
    const turn = completed.find((item: DshTurnTrace) => row.position >= item.startSeq && row.position <= item.endSeq!)
    if (turn !== active) { flush(); active = turn }
    if (!turn) result.push(row)
    else if (row.message?.role === 'user') { flush(row.position); result.push(row) }
    else pending.push(row)
  }
  flush(); return result
}
