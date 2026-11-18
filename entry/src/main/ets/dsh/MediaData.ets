import { array, number, object, string, strings, WireObject } from './DshWire'
import { MEDIA_PRESETS } from './MediaPresets'

export type MediaKind = 'image' | 'video'
export interface MediaParams {
  kind: MediaKind;
  model?: MediaEntry;
  modelLabel?: string;
  aspect?: string;
  count: number;
  quality?: string;
  seconds?: number;
  resolution?: string;
}
export interface MediaService {
  id: string; label: string; enabled: boolean; provider: string; baseUrl: string;
  profile: string; responseFormat: string; models: string[]; keyRef: string;
}
export interface MediaModel {
  id: string; label: string; kind: MediaKind; profile: string; ratios: string[];
  qualities: string[]; maxN: number; durations: number[]; resolutions: string[];
  maxRefs: number; firstFrame: boolean; lastFrame: boolean; edit: boolean;
  price?: number; currency: string; perSecond: boolean;
}
export interface MediaEntry { namespace: string; service: MediaService; model: MediaModel; }
export interface MediaPreset {
  id: string; label: string; provider: string; profile: string; baseUrl: string;
  responseFormat: string; models: string[]; kind: MediaKind; keyGroup: string;
}
export interface MediaNamespace {
  ns: string; revision: number; writable: boolean; value: WireObject;
  services: MediaService[]; models: MediaModel[]; presets: MediaPreset[]; catalog: WireObject;
}
export interface MediaCatalog {
  status: string; namespaces: MediaNamespace[]; entries: MediaEntry[]; credentials: WireObject;
}
export interface MediaItem {
  path: string; name: string; mime: string; width: number; height: number;
  bytes: number; duration: number; poster: string; codec: string;
}
export interface MediaMeta {
  kind: MediaKind; status: string; rid: string; job: string; items: MediaItem[];
  request: WireObject; prompt: string; revisedPrompt: string; error: WireObject; cost: WireObject;
}

const ASPECT = /^[1-9]\d?:[1-9]\d?$/
const QUALITY = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,31}$/
const RESOLUTION = /^[1-9]\d{2,3}p$/
const SERVICE = /^[a-z][a-z0-9_]{0,31}$/
const MODEL = /^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,159}$/

function bytes(text: string): number {
  try { return encodeURIComponent(text).replace(/%[A-F\d]{2}/gi, '.').length }
  catch { return fail('invalid_message') }
}
function fail(code: string): never { throw new Error(code) }
function modelTag(token: string): WireObject {
  const match = /^([^〈〉]+?)(?:〈([a-z][a-z0-9_]{0,31})\/([A-Za-z0-9][A-Za-z0-9_.:/-]{0,159})〉)?$/.exec(token)
  const label = match?.[1] || ''
  if (!label || label.trim() !== label || bytes(label) > 160 || /[〔〕·\x00-\x1f\x7f-\x9f]/.test(label) ||
    /^\d+(?::\d+|\s*(?:张|秒|p|k))$/i.test(label) || label.startsWith('质量=')) fail('invalid_model')
  const result: WireObject = { 'label': label }
  if (match?.[2]) { result['serviceId'] = match[2]; result['id'] = match[3] }
  return result
}

// Grammar v1 is shared with dsh-media, including its error precedence and byte limits.
export function parseMediaHeader(text: string): WireObject | undefined {
  const prefix = /^〔生成(图像|视频)(?=〕|·|\s|$)/.exec(text)
  if (!prefix) return undefined
  const newline = text.indexOf('\n')
  if (newline < 0) fail('missing_prompt')
  const line = text.slice(0, newline).replace(/\r$/, '')
  const prompt = text.slice(newline + 1)
  if (!prompt.trim()) fail('missing_prompt')
  if (bytes(line) > 1024 || bytes(prompt) > 4096) fail('too_long')
  if (!line.endsWith('〕') || /[\r\n]/.test(line)) fail('invalid_header')
  const tokens = line.slice(1, -1).split(' · ')
  if (!['生成图像', '生成视频'].includes(tokens[0]) || tokens.length > 5 ||
    tokens.some((token: string) => !token || token.trim() !== token || /[〔〕·]/.test(token))) fail('invalid_header')
  const image = tokens[0] === '生成图像'
  const result: WireObject = { 'kind': image ? 'image' : 'video', 'prompt': prompt }
  let previous = 0
  for (const token of tokens.slice(1)) {
    let rank = 0
    if (/^[+-]?\d+(?:\.\d+)?:[+-]?\d+(?:\.\d+)?$/.test(token)) {
      if (!ASPECT.test(token)) fail('invalid_aspect')
      rank = 1; result['aspect'] = token
    } else if (/^[+-]?\d+(?:\.\d+)?\s*张$/.test(token)) {
      if (!image || !/^[1-4] 张$/.test(token)) fail('invalid_count')
      rank = 2; result['n'] = Number(token.slice(0, -2))
    } else if (/^[+-]?\d+(?:\.\d+)?\s*秒$/.test(token)) {
      const value = Number(token.slice(0, -2))
      if (image || !/^[1-9]\d? 秒$/.test(token) || value > 60) fail('invalid_seconds')
      rank = 2; result['seconds'] = value
    } else if (token.startsWith('质量=')) {
      if (!image || !QUALITY.test(token.slice(3))) fail('invalid_quality')
      rank = 3; result['quality'] = token.slice(3)
    } else if (/^[+-]?\d+(?:\.\d+)?[pPkK]$/.test(token)) {
      if (image || !RESOLUTION.test(token)) fail('invalid_quality')
      rank = 3; result['quality'] = token
    } else { rank = 4; result['model'] = modelTag(token) }
    if (rank <= previous) fail('invalid_order')
    previous = rank
  }
  return result
}

export function formatMediaHeader(value: WireObject): string {
  const kind = value['kind']
  if (Object.keys(value).some((key: string) => !['kind', 'prompt', 'aspect', 'n', 'seconds', 'quality', 'model'].includes(key)) ||
    !['image', 'video'].includes(string(kind)) || typeof value['prompt'] !== 'string') fail('invalid_message')
  const image = kind === 'image'
  if ((image && Object.keys(value).includes('seconds')) || (!image && Object.keys(value).includes('n'))) fail('invalid_order')
  const parts: string[] = [image ? '生成图像' : '生成视频']
  if (Object.keys(value).includes('aspect')) {
    if (typeof value['aspect'] !== 'string' || !ASPECT.test(string(value['aspect']))) fail('invalid_aspect')
    parts.push(string(value['aspect']))
  }
  for (const key of ['n', 'seconds']) {
    if (!(Object.keys(value).includes(key))) continue
    const v = value[key]
    if (typeof v !== 'number' || !Number.isSafeInteger(v) || v < 1 || v > (key === 'n' ? 4 : 60)) {
      fail(key === 'n' ? 'invalid_count' : 'invalid_seconds')
    }
    parts.push(`${v} ${key === 'n' ? '张' : '秒'}`)
  }
  if (Object.keys(value).includes('quality')) {
    const quality = value['quality']
    if (typeof quality !== 'string' || !(image ? QUALITY : RESOLUTION).test(quality)) fail('invalid_quality')
    parts.push(image ? `质量=${quality}` : quality)
  }
  if (Object.keys(value).includes('model')) {
    const tag = object(value['model'])
    if (typeof tag['label'] !== 'string' || Object.keys(tag).some((key: string) => !['label', 'serviceId', 'id'].includes(key))) fail('invalid_model')
    const label = string(tag['label'])
    if (modelTag(label)['label'] !== label || modelTag(label)['serviceId'] !== undefined) fail('invalid_model')
    if ((Object.keys(tag).includes('serviceId')) !== (Object.keys(tag).includes('id')) || (Object.keys(tag).includes('serviceId') &&
      (!SERVICE.test(string(tag['serviceId'])) || !MODEL.test(string(tag['id']))))) fail('invalid_model')
    parts.push(Object.keys(tag).includes('serviceId') ? `${label}〈${tag['serviceId']}/${tag['id']}〉` : label)
  }
  const text = `〔${parts.join(' · ')}〕\n${value['prompt']}`
  const parsed = parseMediaHeader(text)
  if (!parsed) fail('invalid_header')
  for (const key of ['kind', 'prompt', 'aspect', 'n', 'seconds', 'quality']) {
    if (parsed[key] !== value[key]) fail('invalid_header')
  }
  if ((Object.keys(parsed).includes('model')) !== (Object.keys(value).includes('model'))) fail('invalid_model')
  for (const key of ['label', 'serviceId', 'id']) {
    if (object(parsed['model'])[key] !== object(value['model'])[key]) fail('invalid_model')
  }
  return text
}

export function formatMediaMessage(params: MediaParams, prompt: string): string {
  const value: WireObject = { 'kind': params.kind, 'prompt': prompt }
  if (params.aspect) value['aspect'] = params.aspect
  if (params.kind === 'image') {
    value['n'] = params.count
    if (params.quality) value['quality'] = params.quality
  } else {
    if (params.seconds !== undefined) value['seconds'] = params.seconds
    if (params.resolution) value['quality'] = params.resolution
  }
  if (params.model) {
    const tag: WireObject = { 'label': params.model.model.label, 'serviceId': params.model.service.id, 'id': params.model.model.id }
    value['model'] = tag
  } else if (params.modelLabel) {
    const tag: WireObject = { 'label': params.modelLabel }; value['model'] = tag
  }
  return formatMediaHeader(value)
}

export function mediaServices(raw: Object | null | undefined): MediaService[] {
  return array(raw).map((item: Object): MediaService => {
    const s = object(item)
    return { id: string(s['id']), label: string(s['label']), enabled: s['enabled'] === true, provider: string(s['provider']),
      baseUrl: string(s['baseUrl']), profile: string(s['profile']), responseFormat: string(s['responseFormat']),
      models: (typeof s['models'] === 'string' ? string(s['models']).split(',') : strings(s['models']))
        .map((id: string) => id.trim()).filter((id: string) => !!id), keyRef: string(s['keyRef']) }
  }).filter((s: MediaService) => !!s.id)
}

export function mediaServiceWire(s: MediaService): WireObject {
  return { 'id': s.id, 'label': s.label, 'enabled': s.enabled, 'provider': s.provider, 'baseUrl': s.baseUrl,
    'profile': s.profile, 'responseFormat': s.responseFormat, 'models': s.models.join(', '), 'keyRef': s.keyRef }
}

function schemaNode(value: Object | null | undefined, refs: WireObject): WireObject {
  return typeof value === 'number' || typeof value === 'string' ? object(refs[String(value)]) : object(value)
}

function catalogMeta(raw: WireObject): WireObject | undefined {
  const schema = object(raw['schema']); const refs = object(schema['refs'])
  let root = schema['refs'] ? schemaNode(schema['uid'], refs) : schema
  for (let i = 0; i < 12 && ['transform', 'lazy'].includes(string(root['type'])); i++) root = schemaNode(root['inner'], refs)
  let field = schemaNode(object(root['dict'])['services'], refs)
  for (let i = 0; i < 12; i++) {
    const meta = object(field['meta']); const extra = object(meta['extra'])
    if (Object.keys(extra).includes('dsh-go/media/catalog')) return extra['dsh-go/media/catalog'] === null ? undefined : object(extra['dsh-go/media/catalog'])
    if (!['transform', 'lazy'].includes(string(field['type']))) break
    field = schemaNode(field['inner'], refs)
  }
  return undefined
}

function mediaModel(raw: Object): MediaModel {
  const m = object(raw); const frame = object(m['frames']); const price = object(m['price'])
  return { id: string(m['id']), label: string(m['label']), kind: m['kind'] === 'video' ? 'video' : 'image', profile: string(m['profile']),
    ratios: Array.from(new Set(strings(m['ratios']).filter((v: string) => ASPECT.test(v)))),
    qualities: Array.from(new Set(strings(m['qualities']).filter((v: string) => QUALITY.test(v)))),
    maxN: Math.max(1, Math.min(4, number(m['maxN'], 1))), durations: array(m['durations']).filter((v: Object) =>
      typeof v === 'number' && Number.isInteger(v) && v >= 1 && v <= 60) as number[],
    resolutions: Array.from(new Set(strings(m['resolutions']).filter((v: string) => RESOLUTION.test(v)))),
    maxRefs: Math.max(0, Math.min(99, number(m['maxRefs'], 0))),
    firstFrame: frame['first'] === true, lastFrame: frame['last'] === true, edit: m['edit'] === true,
    price: typeof price['amount'] === 'number' && number(price['amount'], -1) >= 0 ? number(price['amount'], 0) : undefined,
    currency: string(price['currency']) || 'CNY', perSecond: price['unit'] === 'second' }
}

function isMap(value: Object | null | undefined): boolean {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function brokenCatalog(catalog: WireObject): boolean {
  if (!Number.isInteger(catalog['v']) || !Array.isArray(catalog['models'])) return true
  for (const key of ['capabilities', 'limits']) if (catalog[key] !== undefined && !isMap(catalog[key])) return true
  const max = object(catalog['limits'])['maxN']
  if (max !== undefined && !Number.isInteger(max)) return true
  const ids: string[] = []
  for (const raw of array(catalog['models'])) {
    const model = object(raw); const id = string(model['id'])
    if (!id || ids.includes(id) || !string(model['label']) || typeof model['kind'] !== 'string') return true
    ids.push(id)
    if (!['image', 'video'].includes(string(model['kind']))) continue
    for (const key of ['ratios', 'qualities', 'resolutions']) {
      if (model[key] !== undefined && (!Array.isArray(model[key]) || array(model[key]).some((v: Object) => typeof v !== 'string'))) return true
    }
    for (const key of ['maxN', 'maxRefs']) if (model[key] !== undefined && !Number.isInteger(model[key])) return true
    if (model['profile'] !== undefined && typeof model['profile'] !== 'string') return true
    if (model['edit'] !== undefined && typeof model['edit'] !== 'boolean') return true
    if (model['durations'] !== undefined && (!Array.isArray(model['durations']) ||
      array(model['durations']).some((v: Object) => typeof v !== 'number'))) return true
    if (model['frames'] !== undefined && !isMap(model['frames'])) return true
    for (const key of ['first', 'last']) {
      const flag = object(model['frames'])[key]
      if (flag !== undefined && typeof flag !== 'boolean') return true
    }
  }
  return false
}

export function mediaCatalog(raw: WireObject, credentials: WireObject = {}): MediaCatalog {
  const namespaces: MediaNamespace[] = []; const entries: MediaEntry[] = []
  let status = 'missing'
  for (const row of array(raw['namespaces'])) {
    const view = object(row); const catalog = catalogMeta(view)
    if (!catalog) continue
    if (!Number.isInteger(catalog['v'])) { status = 'broken'; continue }
    if (catalog['v'] !== 1 || (catalog['contract'] !== undefined && catalog['contract'] !== 'dsh-go/media/catalog')) {
      status = 'unsupported'; continue
    }
    if (brokenCatalog(catalog)) { status = 'broken'; continue }
    const value = object(view['value']); const services = mediaServices(value['services'])
    const models = array(catalog['models']).filter((m: Object) => ['image', 'video'].includes(string(object(m)['kind']))).map(mediaModel)
    const presets: MediaPreset[] = !Array.isArray(catalog['presets']) ? MEDIA_PRESETS : array(catalog['presets']).map((raw: Object): MediaPreset => {
      const p = object(raw)
      return { id: string(p['id']), label: string(p['label']), provider: string(p['provider']), profile: string(p['profile']),
        baseUrl: string(p['baseUrl']), responseFormat: string(p['responseFormat']), models: strings(p['models']),
        kind: p['kind'] === 'video' ? 'video' : 'image', keyGroup: string(p['keyGroup']) || string(p['id']).split('-')[0] }
    }).filter((p: MediaPreset) => /^[a-z][a-z0-9-]{0,31}$/.test(p.id) && !!p.label && p.label.length <= 80 &&
      !!p.provider && p.provider.length <= 80 && !!p.profile && p.profile.length <= 80 &&
      p.models.length > 0 && p.models.length <= 16 && new Set(p.models).size === p.models.length &&
      ['', 'url', 'b64_json'].includes(p.responseFormat) && !mediaUrlIssue(p.baseUrl, p.profile))
    const ns: MediaNamespace = { ns: string(view['ns']), revision: number(view['revision'], 0), writable: raw['writable'] !== false && view['writable'] !== false,
      value: value, services: services, models: models, presets: presets, catalog: catalog }
    namespaces.push(ns)
    const limits = [4, number(object(catalog['limits'])['maxN'], 4), number(object(value['limits'])['maxImages'], 4)]
    for (const service of services) {
      if (!service.enabled || !SERVICE.test(service.id) || services.filter((s: MediaService) => s.id === service.id).length !== 1 ||
        object(credentials[service.keyRef])['configured'] !== true) continue
      for (const id of Array.from(new Set(service.models))) {
        const model = models.find((m: MediaModel) => m.id === id)
        if (!model || (model.profile && service.profile && model.profile !== service.profile) ||
          (object(catalog['capabilities'])[model.kind] !== undefined && object(catalog['capabilities'])[model.kind] !== true)) continue
        const tag: WireObject = { 'label': model.label, 'serviceId': service.id, 'id': model.id }
        try { formatMediaHeader({ 'kind': 'image', 'prompt': '.', 'model': tag }) }
        catch { continue }
        const limited = mediaModel(object(array(catalog['models']).find((v: Object) => object(v)['id'] === id)))
        limited.maxN = Math.max(1, Math.min(model.maxN, ...limits))
        entries.push({ namespace: ns.ns, service: service, model: limited })
      }
    }
  }
  return { status: namespaces.length ? 'ready' : status, namespaces: namespaces,
    entries: entries.filter((e: MediaEntry) => entries.filter((other: MediaEntry) =>
      other.service.id === e.service.id && other.model.id === e.model.id).length === 1), credentials: credentials }
}

export function defaultMediaEntry(catalog: MediaCatalog, kind: MediaKind): MediaEntry | undefined {
  const choices = catalog.entries.filter((e: MediaEntry) => e.model.kind === kind)
  for (const prefix of [kind, '']) {
    for (const ns of catalog.namespaces) {
      const d = object(ns.value['defaults']); const service = string(d[prefix ? `${prefix}ServiceId` : 'serviceId'])
      const group = choices.filter((e: MediaEntry) => e.namespace === ns.ns && e.service.id === service)
      if (group.length) return group.find((e: MediaEntry) => e.model.id === string(d[`${kind}ModelId`])) ||
        group.find((e: MediaEntry) => e.model.id === string(d['modelId'])) || group[0]
    }
  }
  return choices[0]
}

export function fitMediaParams(params: MediaParams, catalog: MediaCatalog): MediaParams {
  if (!params.model && params.modelLabel) return params
  const entry = params.model ? catalog.entries.find((e: MediaEntry) => e.namespace === params.model?.namespace &&
    e.service.id === params.model?.service.id && e.model.id === params.model?.model.id && e.model.kind === params.kind) : defaultMediaEntry(catalog, params.kind)
  if (!entry) return params
  const model = entry.model; const video = params.kind === 'video'
  const pick = (value: string | undefined, allowed: string[], preferred: string): string | undefined =>
    value && allowed.includes(value) ? value : allowed.includes(preferred) ? preferred : allowed[0]
  const seconds = model.durations.length ? model.durations.reduce((a: number, b: number) =>
    params.seconds === undefined ? Math.min(a, b) : Math.abs(a - params.seconds) <= Math.abs(b - params.seconds) ? a : b) : undefined
  return { kind: params.kind, model: entry, aspect: pick(params.aspect, model.ratios, video ? '16:9' : '1:1'),
    count: video ? 1 : Math.min(Math.max(1, params.count), model.maxN),
    quality: !video && params.quality && model.qualities.includes(params.quality) ? params.quality : undefined,
    seconds: video ? seconds : undefined, resolution: video ? pick(params.resolution, model.resolutions, '720p') : undefined }
}

export function mediaParamsFromMeta(meta: MediaMeta, catalog: MediaCatalog): MediaParams {
  const request = meta.request; const id = string(request['model']); const label = string(request['label'])
  const provider = string(request['provider'])
  const matches = catalog.entries.filter((entry: MediaEntry) => entry.model.kind === meta.kind &&
    (id ? entry.model.id === id && (!provider || entry.service.provider === provider) : !!label && entry.model.label === label))
  const pinned = matches.length === 1 ? matches[0] : undefined
  return fitMediaParams({ kind: meta.kind, model: pinned, modelLabel: pinned ? undefined : label || id || undefined,
    aspect: string(request['aspect']) || undefined, count: meta.kind === 'video' ? 1 : number(request['n'], meta.items.length || 1),
    quality: meta.kind === 'image' ? string(request['quality']) || undefined : undefined,
    seconds: meta.kind === 'video' && typeof request['seconds'] === 'number' ? Math.round(number(request['seconds'], 1)) : undefined,
    resolution: meta.kind === 'video' ? string(request['resolution']) || string(request['res']) || undefined : undefined }, catalog)
}

export function regenerateMediaMessage(meta: MediaMeta, catalog: MediaCatalog): string | undefined {
  if (!meta.prompt.trim()) return undefined
  const params = mediaParamsFromMeta(meta, catalog)
  if (!params.model) return undefined
  try { return formatMediaMessage(params, meta.prompt) } catch { return undefined }
}

export function validateMediaReferences(params: MediaParams, catalog: MediaCatalog, count: number): void {
  const entry = params.model && catalog.entries.find((e: MediaEntry) => e.namespace === params.model?.namespace &&
    e.service.id === params.model?.service.id && e.model.id === params.model?.model.id && e.model.kind === params.kind)
  if (!entry) throw new Error('请先选择此主机可用的生成模型')
  if (count > 0 && entry.model.maxRefs === 0) throw new Error('此模型不支持参考图片')
  if (params.kind === 'video' && count >= 2 && !entry.model.lastFrame) throw new Error('此视频模型不支持尾帧图片')
  if (count > entry.model.maxRefs) throw new Error(`此模型最多支持 ${entry.model.maxRefs} 张参考图片`)
}

export function mediaUrlIssue(value: string, profile: string): string {
  if (!/^https:\/\/[^/?#@\s\\]+(?:\/[^?#\s\\]*)?$/.test(value) || value.length > 2048 || /[\x00-\x1f\x7f]/.test(value)) return '请输入不含账号、查询参数或片段的 HTTPS 基础地址'
  const authority = value.slice(8).split('/')[0]
  const endpoint = /^(\[[A-Fa-f0-9:.]+\]|[^:\[\]]+)(?::(\d+))?$/.exec(authority)
  if (!endpoint || (endpoint[2] && (Number(endpoint[2]) < 1 || Number(endpoint[2]) > 65535))) return 'HTTPS 地址的主机或端口无效'
  const path = value.replace(/^https:\/\/[^/]+/, '').replace(/\/+$/, '').toLowerCase()
  if (/\/(images\/(generations|edits)|chat\/completions|responses|contents\/generations\/tasks|video\/(submit|status)|video-synthesis|multimodal-generation\/generation)(\/|$)/.test(path)) return '请填写 API 基础地址，不要填写具体生成端点'
  if (['ark-image', 'ark-video', 'ali-wan-image', 'ali-video', 'silicon-image', 'silicon-video'].includes(profile) && path) return '此协议需要域名根地址'
  return ''
}

export function mediaMeta(raw: Object | null | undefined): MediaMeta | undefined {
  const m = object(object(raw)['dsh-go/media'])
  if (number(m['v'], 1) < 1) return undefined
  const items = array(m['items']).map((raw: Object): MediaItem => {
    const i = object(raw); const path = string(i['path'])
    return { path: path, name: path.split(/[\\/]/).pop() || '媒体', mime: string(i['mime']), width: number(i['width'], 0),
      height: number(i['height'], 0), bytes: number(i['bytes'], 0), duration: number(i['duration'], 0),
      poster: string(i['poster']), codec: string(i['codec']) }
  }).filter((i: MediaItem) => !!i.path && !/[\x00-\x1f]/.test(i.path))
  const status = ['running', 'failed'].includes(string(m['status'])) ? string(m['status']) : 'done'
  const kind = string(m['kind']) || (items.length ? items[0].mime.startsWith('video/') ? 'video' : 'image' : '')
  if (!['image', 'video'].includes(kind) || (!items.length && status === 'done')) return undefined
  return { kind: kind === 'video' ? 'video' : 'image', status: status, rid: string(m['rid']), job: string(m['job']), items: items,
    request: object(m['request']), prompt: string(m['prompt']), revisedPrompt: string(m['revisedPrompt']),
    error: object(m['error']), cost: object(m['cost']) }
}
