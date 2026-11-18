import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { common } from '@kit.AbilityKit'
import { fileIo, picker } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import type { TransportControl } from '../remote/TransportEndpoint'
import type { DshClient } from '../dsh/DshClient'
import { object, string, array, DshMessage, WireObject } from '../dsh/DshWire'
import { fittedSize } from './AttachmentGalleryData'
import { privateVaultKey } from '../local/PrivateVaultKey'
export { shareLinkInput } from './ShareLaunchData'

export interface SharedConversation { body: WireObject; assets: WireObject; code: string; file: string; html: string }
export interface SharedLink { id: string; url: string; title: string; created: string; expiresAt: string }
export class ConversationShareClient {
  private requests: Set<http.HttpRequest> = new Set()
  private generation: number = 0
  private getControl: () => Promise<TransportControl>
  constructor(getControl: () => Promise<TransportControl>) { this.getControl = getControl }
  cancel(): void { this.generation++; for (const request of this.requests) request.destroy(); this.requests.clear() }
  async request(action: string, body: WireObject = {}): Promise<WireObject> {
    const generation = this.generation, control = await this.getControl()
    if (generation !== this.generation) throw new Error('分享操作已取消')
    if (!/^http:\/\/127\.0\.0\.1:\d+$/.test(control.url) || !control.authorization ||
      !['prepare', 'rounds', 'decode', 'links', 'upload', 'delete', 'profile-source', 'profile-prepare', 'profile-plan', 'profile-backup', 'profile-files-apply'].includes(action)) throw new Error('本机分享服务不可用')
    if (['links', 'upload', 'delete'].includes(action)) body['masterKey'] = await privateVaultKey('share')
    if (generation !== this.generation) throw new Error('分享操作已取消')
    const encoded = JSON.stringify(body)
    if (util.TextEncoder.create('utf-8').encodeInto(encoded).byteLength > 24 * 1024 * 1024) throw new Error('会话过大，请减少选择的消息或图片')
    const request = http.createHttp(); this.requests.add(request)
    try {
      const response = await request.request(control.url + '/share/' + action, { method: http.RequestMethod.POST,
        header: { 'Authorization': control.authorization, 'Content-Type': 'application/json' }, extraData: encoded,
        expectDataType: http.HttpDataType.STRING, connectTimeout: 10000, readTimeout: 95000, maxLimit: 32 * 1024 * 1024,
        usingProxy: false, maxRedirects: 0 })
      if (generation !== this.generation) throw new Error('分享操作已取消')
      const result = object(JSON.parse(response.result as string))
      if (response.responseCode !== 200) throw new Error(string(result['error']) || '分享操作失败')
      return result
    } finally { this.requests.delete(request); request.destroy() }
  }
}
export function sharedConversation(value: WireObject): SharedConversation {
  const file = string(value['file']), code = string(value['code']), html = string(value['html']), body = object(value['body'])
  if (!file || !code || !html || body['kind'] !== 'conversation' || file.length > 4 * 1024 * 1024 || html.length > 12 * 1024 * 1024) throw new Error('分享服务返回内容无效')
  return { body: body, assets: object(value['assets']), code: code, file: file, html: html }
}
export function sharedLinks(value: WireObject): SharedLink[] {
  return array(value['links']).map((raw: Object): SharedLink => {
    const item = object(raw)
    return { id: string(item['id']), url: string(item['url']), title: string(item['title']), created: string(item['created']), expiresAt: string(item['expiresAt']) }
  })
}
export async function saveSharedText(context: common.UIAbilityContext, title: string, suffix: string, text: string): Promise<boolean> {
  const name = (title.replace(/[\x00-\x1f\x7f/\\:*?"<>|]/g, '').trim().slice(0, 80) || '对话') + suffix
  const targets = await new picker.DocumentViewPicker(context).save({ newFileNames: [name] })
  if (!targets[0]) return false
  const file = await fileIo.open(targets[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
  try {
    const bytes = util.TextEncoder.create('utf-8').encodeInto(text)
    if (await fileIo.write(file.fd, bytes.buffer) !== bytes.byteLength) throw new Error('未能完整保存文件')
    await fileIo.fsync(file.fd)
  } finally { await fileIo.close(file) }
  return true
}
export async function readSharedFile(context: common.UIAbilityContext, uri: string = ''): Promise<string> {
  const targets = uri ? [uri] : await new picker.DocumentViewPicker(context).select({ maxSelectNumber: 1, fileSuffixFilters: ['DSH Go|.dshgo'] })
  if (!targets[0]) return ''
  const file = await fileIo.open(targets[0], fileIo.OpenMode.READ_ONLY)
  try {
    const info = await fileIo.stat(file.fd)
    if (!info.isFile() || info.size > 4 * 1024 * 1024) throw new Error('请选择 4 MB 以内的 .dshgo 文件')
    const data = new ArrayBuffer(info.size), count = await fileIo.read(file.fd, data)
    if (count !== info.size) throw new Error('文件读取不完整')
    return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(data))
  } finally { await fileIo.close(file) }
}
export async function sharePictures(client: DshClient, sessionId: string, messages: DshMessage[], current: () => boolean): Promise<WireObject[]> {
  const result: WireObject[] = [], seen: string[] = []
  for (const message of messages) for (const part of message.content || []) {
    if (part['type'] !== 'image') continue
    const ref = object(part['attachment']), id = string(ref['attachmentId'])
    if (!id || seen.includes(id)) continue
    if (!current()) throw new Error('分享操作已取消')
    seen.push(id)
    const bytes = await client.readSessionImage(sessionId, ref, undefined, current)
    const source = image.createImageSource(bytes)
    let pixel: image.PixelMap | undefined = undefined
    const packer = image.createImagePacker()
    try {
      const info = await source.getImageInfo(), size = fittedSize(info.size.width, info.size.height, 1600)
      if (!current()) throw new Error('分享操作已取消')
      pixel = await source.createPixelMap({ desiredSize: { width: size[0], height: size[1] }, desiredPixelFormat: image.PixelMapFormat.RGBA_8888 })
      const rgba = new ArrayBuffer(size[0] * size[1] * 4); await pixel.readPixelsToBuffer(rgba)
      const view = new Uint8Array(rgba); let transparent = false
      for (let i = 3; i < view.length; i += 4) { if (view[i] < 255) { transparent = true; break } }
      let type = transparent ? 'image/png' : 'image/jpeg'
      let packed = await packer.packing(pixel, { format: type, quality: 82 })
      if (transparent && packed.byteLength > 1080 * 1024) { type = 'image/jpeg'; packed = await packer.packing(pixel, { format: type, quality: 82 }) }
      if (!current()) throw new Error('分享操作已取消')
      result.push({ 'attachmentId': id, 'type': type, 'data': new util.Base64Helper().encodeToString(new Uint8Array(packed)), 'w': size[0], 'h': size[1] })
    } finally { await pixel?.release(); await source.release(); await packer.release() }
  }
  return result
}
