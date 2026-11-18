import { util } from '@kit.ArkTS'
import { array, object, parseRpcResponse, string, WireObject } from './DshWire'

function invalid(): never { throw new Error('DSH 二进制响应格式无效') }
function find(body: Uint8Array, needle: number[], start: number): number {
  for (let offset = start; offset <= body.length - needle.length; offset++) {
    let match = true
    for (let index = 0; index < needle.length; index++) if (body[offset + index] !== needle[index]) { match = false; break }
    if (match) return offset
  }
  return -1
}
function decode(body: Uint8Array): string { return util.TextDecoder.create('utf-8').decodeToString(body) }

export function parseBinaryRpcResponse(buffer: ArrayBuffer, contentType: string, rpcId: string, method: string): Object | null | undefined {
  const boundary = /(?:^|;)\s*boundary=(?:"([^"\r\n]+)"|([^;\s]+))/i.exec(contentType)
  const text = boundary?.[1] || boundary?.[2] || ''
  if (!text || text.length > 200 || !/^[\x20-\x7e]+$/.test(text) || buffer.byteLength > 64 * 1024 * 1024) invalid()
  const delimiter: number[] = []
  for (const char of `--${text}`) delimiter.push(char.charCodeAt(0))
  const body = new Uint8Array(buffer); const fields = new Map<string, Uint8Array>()
  let at = find(body, delimiter, 0)
  if (at < 0) invalid()
  while (true) {
    let start = at + delimiter.length
    if (body[start] === 45 && body[start + 1] === 45) break
    if (body[start] === 13 && body[start + 1] === 10) start += 2
    else if (body[start] === 10) start++
    else invalid()
    const headerEnd = find(body, [13, 10, 13, 10], start)
    if (headerEnd < 0 || headerEnd - start > 8192) invalid()
    const headers = decode(body.subarray(start, headerEnd))
    const name = /(?:^|;)\s*name="([^"\r\n]*)"/im.exec(headers)?.[1]
    const end = find(body, [13, 10].concat(delimiter), headerEnd + 4)
    if (!name || fields.has(name) || end < 0 || fields.size >= 64) invalid()
    fields.set(name, body.slice(headerEnd + 4, end)); at = end + 2
  }
  const metadata = fields.get('metadata')
  if (!metadata || metadata.byteLength > 1024 * 1024) invalid()
  fields.delete('metadata')
  const json = decode(metadata)
  const root: WireObject = { 'value': parseRpcResponse(json, rpcId, method) }
  const envelope = object(JSON.parse(json))
  const attachments = array(envelope['attachments'])
  if (!attachments.length || attachments.length !== fields.size) invalid()
  for (const raw of attachments) {
    const attachment = object(raw); const part = string(attachment['part']); const path = attachment['path']
    if (attachment['codec'] !== 'bytes' || !part || !Array.isArray(path) || array(path).length > 32) invalid()
    const bytes = fields.get(part)
    if (!bytes) invalid()
    fields.delete(part)
    let parent: Object | null | undefined = root; let key: string | number = 'value'
    for (const segment of array(path)) {
      const value: Object | null | undefined = Array.isArray(parent) ? (parent as Object[])[key as number] : object(parent)[key as string]
      if (Array.isArray(value)) {
        if (typeof segment !== 'number' || !Number.isInteger(segment) || segment < 0 || segment >= value.length) invalid()
      } else if (typeof segment !== 'string' || ['__proto__', 'constructor', 'prototype'].includes(segment) ||
        !Object.keys(object(value)).includes(segment)) invalid()
      parent = value; key = segment as string | number
    }
    if (Array.isArray(parent)) {
      if ((parent as Object[])[key as number] !== null) invalid()
      ;(parent as Object[])[key as number] = bytes
    } else {
      if (object(parent)[key as string] !== null) invalid()
      object(parent)[key as string] = bytes
    }
  }
  if (fields.size) invalid()
  return root['value']
}
