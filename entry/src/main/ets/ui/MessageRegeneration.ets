import type { DshClient } from '../dsh/DshClient'
import type { DshMessage, DshSessionRecord, DshSessionProjections, WireObject } from '../dsh/DshWire'
import { array, DshRpcError, object, string } from '../dsh/DshWire'

export interface RegeneratedFork {
  sessionId: string;
  title?: string;
  leftQueued: number;
}

export function forkPointAfterReply(records: DshSessionRecord[], replySeq: number): number | undefined {
  let found = false
  for (const record of records) {
    if (!found) {
      if (record.seq < replySeq) continue
      const content = array(object(record.data['message'])['content']).map(object)
      if (record.seq !== replySeq || record.type !== 'assistant/message' ||
        !content.some((part: WireObject) => part['type'] === 'text' && !!string(part['text']).trim())) return undefined
      found = true
      continue
    }
    if (record.type === 'turn/end') return object(record.data['reason'])['kind'] === 'error' ? undefined : record.seq
    if (['assistant/message', 'tool/call', 'tool/result', 'llm/retry'].includes(record.type)) return undefined
  }
  return undefined
}

export function forkPointBeforePrompt(records: DshSessionRecord[], promptSeq: number): number | undefined {
  let expected = promptSeq - 1
  for (let index = records.length - 1; index >= 0; index--) {
    const record = records[index]
    if (record.seq >= promptSeq) continue
    if (record.seq !== expected) return undefined
    expected--
    if (!['agent/inbox/spliced', 'turn/start', 'step/start', 'system/message'].includes(record.type)) return record.seq
  }
  return undefined
}

export function regenerablePrompt(messages: DshMessage[], records: DshSessionRecord[], reply: DshMessage,
  running: boolean, pendingCount: number): DshMessage | undefined {
  if (running || pendingCount > 0 || reply.role !== 'assistant' || reply.seq === undefined || !reply.text.trim() ||
    forkPointAfterReply(records, reply.seq) === undefined) return undefined
  const at = messages.findIndex((item: DshMessage) => item.id === reply.id && item.seq === reply.seq)
  if (at < 0 || at !== messages.length - 1 || records.some((record: DshSessionRecord) =>
    record.seq > reply.seq! && ['tool/call', 'tool/result'].includes(record.type))) return undefined
  for (let index = at - 1; index >= 0; index--) {
    const prompt = messages[index]
    if (prompt.role !== 'user') continue
    const content = prompt.content || []
    if (prompt.seq === undefined || content.some((part: WireObject) => part['type'] === 'file') ||
      (!prompt.text.trim() && !content.some((part: WireObject) => part['type'] === 'image'))) return undefined
    return prompt
  }
  return undefined
}

export function bumpedForkTitle(title: string): string {
  const ascii = /^(.*?)\((\d+)\)$/.exec(title)
  if (ascii) return `${ascii[1]}(${BigInt(ascii[2]) + BigInt(1)})`
  const fullWidth = /^(.*?)（(\d+)）$/.exec(title)
  return fullWidth ? `${fullWidth[1]}（${BigInt(fullWidth[2]) + BigInt(1)}）` : `${title} (1)`
}

export async function forkBeforePrompt(client: DshClient, sourceId: string, promptSeq: number,
  records: DshSessionRecord[], sourceTitle: string, current: () => boolean): Promise<RegeneratedFork | undefined> {
  if (!current()) return undefined
  let cut = forkPointBeforePrompt(records, promptSeq)
  if (cut === undefined && promptSeq > 0) {
    const history = await client.sessionPage(sourceId, undefined, 100, promptSeq - 1)
    if (!current()) return undefined
    cut = forkPointBeforePrompt(history.records, promptSeq)
  }
  if (cut === undefined) throw new Error('未找到这条消息之前的更早记录。')
  const child = await client.forkSession(sourceId, cut)
  if (!current()) return undefined
  let projections: DshSessionProjections | null = null
  try { projections = await client.sessionProjections(child) } catch (_) {}
  if (!current()) return undefined
  const inbox = object(projections?.values['inbox'])
  let left = 0
  for (const item of array(inbox['next-step']).concat(array(inbox['next-turn']))) {
    try { await client.updateQueue(child, string(object(item)['id']), 'remove') }
    catch (error) {
      if (!(error instanceof DshRpcError) || error.code !== 'session/queue-item-not-found') left++
    }
    if (!current()) return undefined
  }
  let title: string | undefined
  const inherited = string(projections?.values['title'])
  if (inherited.trim()) {
    try { title = await client.renameSession(child, bumpedForkTitle(sourceTitle.trim() ? sourceTitle : inherited)) }
    catch (_) {}
  }
  return current() ? { sessionId: child, title: title, leftQueued: left } : undefined
}

export interface RegenerationImageInfo {
  name: string;
  mediaType: string;
}

export function regenerationImageInfo(reference: WireObject, buffer: ArrayBuffer, index: number): RegenerationImageInfo {
  const bytes = new Uint8Array(buffer)
  const at = (offset: number, signature: number[]): boolean =>
    bytes.length >= offset + signature.length && signature.every((value: number, index: number) => bytes[offset + index] === value)
  let type = string(reference['mediaType']) || 'application/octet-stream'
  if (at(0, [137, 80, 78, 71, 13, 10, 26, 10])) type = 'image/png'
  else if (at(0, [255, 216, 255])) type = 'image/jpeg'
  else if (at(0, [71, 73, 70, 56])) type = 'image/gif'
  else if (at(0, [82, 73, 70, 70]) && at(8, [87, 69, 66, 80])) type = 'image/webp'
  const extension = type === 'image/jpeg' ? 'jpg' : type === 'image/gif' ? 'gif' : type === 'image/webp' ? 'webp' : 'png'
  return { name: string(reference['name']).trim() || `image-${index + 1}.${extension}`, mediaType: type }
}
