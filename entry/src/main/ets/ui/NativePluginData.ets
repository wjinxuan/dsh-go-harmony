import { relaxedModelJson, normalizeModelUi, isGenui, genuiView } from './NativePluginModel'
import { PLUGIN_INPUTS, PLUGIN_CONTAINERS, PLUGIN_DISPLAYS, pluginInputPath } from './NativePluginControlsData'
import { array, number, object, string, strings, WireObject } from '../dsh/DshWire'

export const PLUGIN_COMPONENTS: string[] = ['stack', 'row', 'text', 'metric', 'chart', 'compare', 'steps', 'callout',
  'options', 'confirm', 'list', 'keyValue', 'progress', 'table', 'actions', 'image', ...PLUGIN_INPUTS, ...PLUGIN_CONTAINERS, ...PLUGIN_DISPLAYS]
export interface PluginPlace {
  pkg: string; plugin: string; id: string; title: string; surface: string; placement: string[];
  effects: WireObject[]; wants: string[]; live: boolean
}
export interface PluginEffect { type: string; text: string; id: string; args: string; data: WireObject }
export interface PluginNode { type: string; raw: WireObject; children: PluginNode[]; key: string }
export interface PluginView { title: string; root: PluginNode; issue: string; dialect?: string }
const ID: RegExp = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$/
const FORBIDDEN: string[] = ['__proto__', 'constructor', 'prototype']

export function pluginCaps(locale: string = 'zh-CN'): WireObject {
  const caps: WireObject = { 'v': '1', 'app': '1.0.15', 'locale': locale,
    'surfaces': 'composer.actions,message.actions,composer.strip,panels,composer.tools,session.actions,plugin',
    'components': PLUGIN_COMPONENTS.join(',') }
  return caps
}

export function pluginPlaces(value: Object | null | undefined): PluginPlace[] {
  const envelope = object(value)
  if (envelope['v'] !== 1) return []
  const places: PluginPlace[] = []; const seen: Set<string> = new Set()
  for (const item of array(envelope['plugins']).slice(0, 128)) {
    const plugin = object(item); const pkg = string(plugin['pkg'])
    if (!/^(?:@[a-z0-9._~-]+\/)?[a-z0-9._~-]+$/.test(pkg) || plugin['native'] === false ||
      (plugin['state'] !== undefined && plugin['state'] !== 'ok')) continue
    const contributions = object(plugin['contributes'])
    for (const surface of ['composer.actions', 'message.actions', 'composer.strip', 'panels', 'composer.tools', 'session.actions']) {
      let count = 0
      for (const raw of array(contributions[surface])) {
        const row = object(raw); const id = string(row['id']); const key = `${pkg}|${surface}|${id}`
        if (!ID.test(id) || row['ready'] === false || strings(row['requires']).length || seen.has(key)) continue
        if (++count > (surface === 'panels' ? 4 : surface === 'composer.strip' ? 1 : 2)) break
        const effect = row['effect']; const effects = (Array.isArray(effect) ? array(effect) : effect ? [effect] : []).map(object)
        places.push({ pkg: pkg, plugin: string(plugin['title']) || pkg, id: id,
          title: (string(row['title']) || string(row['label']) || string(row['text']) || id).slice(0, surface === 'panels' ? 16 : surface === 'composer.actions' ? 10 : surface === 'composer.tools' ? 8 : surface === 'composer.strip' ? 24 : 12),
          surface: surface === 'panels' ? 'panel' : surface, wants: strings(plugin['wants']),
          effects: effects, live: row['live'] === true,
          placement: typeof row['placement'] === 'string' ? [string(row['placement'])] : strings(row['placement']) })
        seen.add(key)
      }
    }
  }
  return places
}

export function pluginBinding(value: Object | null | undefined, data: Object | null | undefined): Object | null | undefined {
  const binding = object(value)
  if (Object.keys(binding).length !== 1 || typeof binding['$'] !== 'string') return value
  const path = string(binding['$']); if (!path.startsWith('data')) return null
  let cursor = 4; let current = data; let count = 0
  while (cursor < path.length) {
    const segment = /^(?:\.([^.\[\]]+)|\[(\d+)\])/.exec(path.slice(cursor))
    if (!segment || ++count > 16) return null
    const key = segment[1] ?? segment[2]
    if (FORBIDDEN.includes(key)) return null
    if (Array.isArray(current)) {
      if (!/^\d+$/.test(key)) return null
      current = array(current)[Number(key)]
    } else {
      const map = object(current); if (!Object.keys(map).includes(key)) return null
      current = map[key]
    }
    cursor += segment[0].length
  }
  return current ?? null
}

export function pluginBindings(value: Object | null | undefined, data: Object | null | undefined, depth: number = 0): Object | null | undefined {
  if (depth > 32) return null
  const resolved = pluginBinding(value, data)
  if (resolved !== value) return resolved
  if (Array.isArray(value)) return array(value).slice(0, 200).map((child: Object) => pluginBindings(child, data, depth + 1) ?? null)
  if (value && typeof value === 'object') {
    const out: WireObject = {}
    for (const key of Object.keys(object(value)).slice(0, 128)) {
      if (!FORBIDDEN.includes(key)) out[key] = ['type', 'action', 'onChange', 'submit'].includes(key) ? object(value)[key] : pluginBindings(object(value)[key], data, depth + 1)
    }
    return out
  }
  return value
}

export function pluginText(value: Object | null | undefined, limit: number = 2000): string {
  if (value === null || value === undefined) return '—'
  if (typeof value === 'string') return value.slice(0, limit)
  if (typeof value === 'boolean') return value ? '是' : '否'
  return typeof value === 'number' && Number.isFinite(value) ? String(value) : '—'
}

export function parsePluginView(value: Object | null | undefined, data: Object | null | undefined = undefined, budget: string = 'panel'): PluginView {
  const bytes = budget === 'model' ? 16384 : budget === 'toolCard' ? 8192 : budget === 'strip' ? 2048 : 32768
  const maxNodes = ['model', 'toolCard'].includes(budget) ? 40 : budget === 'strip' ? 8 : 120
  const maxDepth = ['model', 'toolCard'].includes(budget) ? 6 : budget === 'strip' ? 3 : 8
  const maxChildren = budget === 'panel' ? 32 : budget === 'strip' ? 4 : 16
  const invalid: PluginNode = { type: 'invalid', raw: {}, children: [], key: 'invalid' }
  try {
    let raw = typeof value === 'string' ? budget === 'model' ? relaxedModelJson(value) : JSON.parse(value) as Object : value
    const genui = budget === 'model' && isGenui(raw)
    if (budget === 'model') raw = genui ? genuiView(raw) : normalizeModelUi(raw)
    if (budget === 'model' && Object.keys(object(raw)).length === 1 && Array.isArray(object(raw)['item'])) raw = object(raw)['item']
    if (Array.isArray(raw)) { const layout: WireObject = { 'type': 'stack', 'children': raw }; raw = layout }
    if (encodeURIComponent(JSON.stringify(raw) || '').replace(/%[A-F\d]{2}/g, 'x').length > bytes) {
      return { title: '', root: invalid, issue: '插件界面超过大小限制' }
    }
    const evaluated = object(pluginBindings(raw, data)); let count = 0; let issue = ''; const bindings: string[] = []; let inputCount = 0
    const version2 = evaluated['v'] === 2
    const walk = (current: WireObject, depth: number, path: string, inForm: boolean = false): PluginNode => {
      const type = string(current['type'])
      if (++count > maxNodes || depth > maxDepth || !PLUGIN_COMPONENTS.includes(type)) {
        issue = '部分插件内容无法显示'; return { type: 'invalid', raw: {}, children: [], key: path }
      }
      const control = PLUGIN_INPUTS.includes(type) || PLUGIN_CONTAINERS.includes(type) || PLUGIN_DISPLAYS.includes(type)
      if (control && (!version2 || budget === 'strip' || budget === 'model' && !genui) || type === 'form' && inForm) { issue = '此界面不支持这个控件'; return { type: 'invalid', raw: {}, children: [], key: path } }
      if (PLUGIN_INPUTS.includes(type)) {
        const bind = string(current['bind'])
        if (++inputCount > 32 || !string(current['label']) || current['password'] === true || current['obscureText'] === true || current['inputType'] === 'password' || current['keyboardType'] === 'password' ||
          (bind && (!pluginInputPath(bind) || bindings.some((value: string) => value === bind || value.startsWith(bind + '.') || bind.startsWith(value + '.'))))) { issue = '插件输入字段无效'; return { type: 'invalid', raw: {}, children: [], key: path } }
        if (bind) { bindings.push(bind); const reference: WireObject = { '$': bind }; current['value'] = pluginBinding(reference, data) }
      }
      if (['tabs', 'accordion', 'carousel', 'timeline'].includes(type)) {
        const sections = array(current['items']).slice(0, type === 'timeline' ? 24 : 8).map((section: Object, index: number): PluginNode => {
          const row = object(section); const group: WireObject = { 'type': 'stack', 'title': row['label'], 'children': row['children'] || [] }
          return walk(group, depth + 1, `${path}.section${index}`, inForm)
        })
        return { type: type, raw: current, key: path, children: sections }
      }
      const children = array(current['children'])
      if (children.length > maxChildren) issue = '部分插件内容已折叠'
      return { type: type, raw: current, key: path, children: type === 'stack' || type === 'row' || PLUGIN_CONTAINERS.includes(type) ?
        children.slice(0, maxChildren).map((child: Object, index: number) => walk(object(child), depth + 1, `${path}.${index}`, inForm || type === 'form')) : [] }
    }
    const root = walk(evaluated, 1, 'root')
    return { title: string(evaluated['title']).slice(0, 120), root: root, issue: issue, dialect: genui ? 'genui' : '' }
  } catch { return { title: '', root: invalid, issue: '插件界面有误' } }
}

export function pluginAction(value: Object | null | undefined): WireObject | undefined {
  const raw = object(value); const id = typeof value === 'string' ? value : string(raw['id'])
  const args = object(raw['args'])
  if (!ID.test(id) || JSON.stringify(args).length > 1024) return undefined
  const action: WireObject = { 'id': id, 'args': args }; return action
}

export function pluginEffects(raw: Object | null | undefined, gestureAt: number, now: number = Date.now()): PluginEffect[] {
  const effects: PluginEffect[] = []
  for (const entry of array(raw).slice(0, 4)) {
    let body = object(entry); let type = string(body['type'])
    if (!type && Object.keys(body).length === 1) {
      type = Object.keys(body)[0]; const value = body[type]
      if (['insert', 'toast', 'copy'].includes(type)) body = { 'text': value }
      else if (type === 'link') body = { 'url': value }
      else if (type === 'open' || type === 'command') body = typeof value === 'string' ? { 'name': value, 'page': value } : object(value)
      else if (type === 'patch') body = { 'data': value }
      else if (type === 'refresh') body = { 'id': value }
    }
    if (!['patch', 'refresh'].includes(type) && (now - gestureAt > 3000 || now < gestureAt)) continue
    let text = string(body['text']); let id = ''; const args = string(body['args'])
    if (['insert', 'copy', 'toast'].includes(type)) { if (!text) continue; text = text.slice(0, type === 'toast' ? 40 : type === 'insert' ? 2000 : 8000) }
    else if (type === 'command') { id = string(body['name']); if (!/^[A-Za-z0-9_-]{1,64}$/.test(id) || args.length > 500) continue }
    else if (type === 'open') { id = string(body['panel']) ? 'panel:' + string(body['panel']) : string(body['page']); if (!id) continue }
    else if (type === 'link') { text = string(body['url']); if (!/^https:\/\/[^/@\s?#]+(?:[/?#]|$)/.test(text) || text.length > 2048) continue }
    else if (type === 'patch' || type === 'refresh') id = string(body['id'])
    else continue
    effects.push({ type: type, text: text, id: id, args: args, data: object(body['data']) })
  }
  return effects
}

export function pluginMerge(base: WireObject, patch: WireObject, depth: number = 0): WireObject {
  if (depth > 32) return base
  const result: WireObject = {}
  for (const key of Object.keys(base)) if (patch[key] !== null && !FORBIDDEN.includes(key)) result[key] = base[key]
  for (const key of Object.keys(patch)) {
    if (FORBIDDEN.includes(key)) continue
    if (patch[key] === null) continue
    if (patch[key] && typeof patch[key] === 'object' && !Array.isArray(patch[key])) result[key] = pluginMerge(object(result[key]), object(patch[key]), depth + 1)
    else result[key] = patch[key]
  }
  return result
}

export function pluginReplyEffects(raw: Object | null | undefined, gestureAt: number, acknowledgedAt: number, deferred: boolean, now: number = Date.now()): PluginEffect[] {
  if (!deferred) return pluginEffects(raw, gestureAt, now)
  const timely = acknowledgedAt >= gestureAt && acknowledgedAt - gestureAt <= 3000
  return pluginEffects(raw, timely ? now : gestureAt, now).filter((effect: PluginEffect) => ['insert', 'copy', 'toast', 'patch'].includes(effect.type))
}
