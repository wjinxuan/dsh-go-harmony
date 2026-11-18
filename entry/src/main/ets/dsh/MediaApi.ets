import { util } from '@kit.ArkTS'
import { DshClient } from './DshClient'
import { array, number, object, string, WireObject } from './DshWire'
import { MediaCatalog, MediaNamespace, MediaService, mediaCatalog } from './MediaData'

export async function loadMediaCatalog(client: DshClient): Promise<MediaCatalog> {
  const connection = client.connectionIdentity()
  const raw = await client.describeSettings()
  const catalog = mediaCatalog(raw)
  if (connection !== client.connectionIdentity()) throw new Error('主机已切换')
  const refs = Array.from(new Set(catalog.namespaces.flatMap((ns: MediaNamespace) => ns.services.map((s: MediaService) => s.keyRef))))
  const credentials: WireObject = refs.length ? await client.describeCredentials(refs) : {}
  if (connection !== client.connectionIdentity()) throw new Error('主机已切换')
  return mediaCatalog(raw, credentials)
}

export async function readMediaFile(client: DshClient, sessionId: string, path: string, maxBytes: number,
  sink: (chunk: Uint8Array) => Promise<void>, current: () => boolean): Promise<number> {
  if (!sessionId || !path || /[\x00-\x1f]/.test(path)) throw new Error('媒体路径无效')
  const connection = client.connectionIdentity()
  const check = (): void => {
    if (!current() || connection !== client.connectionIdentity()) throw new Error('媒体读取已取消')
  }
  check()
  const args: WireObject = { 'workspaceFileScopeId': sessionId, 'path': path }
  const stat = object(await client.request('workspaceFiles/stat', args))
  check()
  const total = typeof stat['bytes'] === 'number' ? number(stat['bytes'], 0) : undefined
  if (total !== undefined && (!Number.isSafeInteger(total) || total < 0 || total > maxBytes)) throw new Error('媒体文件超过大小限制')
  let version = string(stat['version']); let offset = 0
  while (true) {
    check()
    const range: WireObject = { 'offset': offset, 'length': Math.min(1024 * 1024, maxBytes - offset + 1) }
    const options: WireObject = { 'range': range }
    const request: WireObject = { 'workspaceFileScopeId': sessionId, 'path': path, 'options': options }
    const result = object(await client.request('workspaceFiles/readBytes', request, 120000))
    check()
    const nextVersion = string(result['version'])
    if (version && nextVersion && version !== nextVersion) throw new Error('媒体文件已变化，请重试')
    if (nextVersion) version = nextVersion
    const raw = result['data']
    let chunk: Uint8Array
    if (typeof raw === 'string') {
      if (raw.length > 1400000 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(raw)) throw new Error('媒体数据格式无效')
      chunk = new util.Base64Helper().decodeSync(raw)
    } else if (raw instanceof Uint8Array) chunk = raw
    else if (Array.isArray(raw) && array(raw).every((v: Object) => typeof v === 'number' && Number.isInteger(v) && v >= 0 && v <= 255)) {
      chunk = new Uint8Array(raw as number[])
    } else throw new Error('主机未返回媒体字节数据')
    if (chunk.length > 1024 * 1024 || offset + chunk.length > maxBytes) throw new Error('媒体文件超过大小限制')
    if (total !== undefined && offset + chunk.length > total) throw new Error('媒体文件大小已变化')
    if (chunk.length) await sink(chunk)
    offset += chunk.length
    check()
    if (result['eof'] === true || !chunk.length) {
      if (total !== undefined && offset !== total) throw new Error('媒体文件未完整读取')
      if (!offset) throw new Error('媒体文件为空')
      return offset
    }
  }
}
