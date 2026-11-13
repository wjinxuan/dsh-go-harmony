import { array, number, object, string, strings, WireObject } from '../dsh/DshWire'

export function featureRequest(request: WireObject): WireObject {
  const args: WireObject = {}
  args['request'] = request
  return args
}

export function featureObjects(value: Object | null | undefined, id: string): WireObject[] {
  return array(value).map(object).filter((row: WireObject) => !!string(row[id]))
}

export function featureError(error: Object, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback
}

export function localizedPluginText(value: Object | null | undefined): string {
  if (typeof value === 'string') return value
  const names = object(value)
  const keys = Object.keys(names)
  const chinese = keys.find((key: string) => /^zh(?:[-_]|$)/i.test(key) && !!string(names[key]))
  const english = keys.find((key: string) => /^en(?:[-_]|$)/i.test(key) && !!string(names[key]))
  const first = keys.find((key: string) => !!string(names[key]))
  const plain = string(names[''])
  return string(names['zh']) || (chinese ? string(names[chinese]) : '') ||
    (/[\u3400-\u9fff]/.test(plain) ? plain : '') || (english ? string(names[english]) : '') || plain ||
    (first ? string(names[first]) : '')
}

export function pluginTitle(row: WireObject): string {
  return localizedPluginText(object(row['meta'])['title']) || string(row['name']) || string(row['moduleName']) ||
    string(row['entryId']) || string(row['rowId'])
}

export function pluginSummary(row: WireObject): string {
  return localizedPluginText(object(row['meta'])['description']) || string(row['description'])
}

export function pluginOperationNotice(result: WireObject): string {
  const error = object(result['error'])
  const code = string(error['code'])
  if (code) {
    const incompatibilities = featureObjects(error['incompatible'], 'name').map((row: WireObject) =>
      `${string(row['name'])} ${string(row['version'])} · DSH ${string(row['runtimeVersion'])}`).join('\n')
    const diagnostic = string(error['diagnostic'])
    throw new Error([`插件操作失败（${code}）`, diagnostic, incompatibilities].filter((value: string) => !!value).join('\n'))
  }
  const warnings = strings(result['warnings']).join('\n')
  switch (result['application']) {
    case 'applied': return warnings || (result['changed'] === true ? '已应用' : '设置已是所选状态')
    case 'restart-required': return warnings ? `重启主机引擎后生效\n${warnings}` : '重启主机引擎后生效'
    case 'overridden': return warnings ? `插件状态由其他配置覆盖\n${warnings}` : '插件状态由其他配置覆盖'
    case 'cancelled': throw new Error('插件操作已取消')
    default: throw new Error('主机未确认插件操作成功')
  }
}

export function scheduleName(row: WireObject): string {
  return string(row['title']).trim() || string(row['prompt']).split('\n')[0].trim() || '未命名任务'
}

export function scheduleRule(row: WireObject): string {
  const zone = string(row['timeZone'])
  const time = string(row['time'])
  switch (row['kind']) {
    case 'after': return `延迟 ${number(row['afterSeconds'], 0)} 秒`
    case 'at': return '指定时间'
    case 'every': return `每 ${number(row['everySeconds'], 0)} 秒`
    case 'daily': return `每天 ${time} ${zone}`.trim()
    case 'weekly': {
      const labels: string[] = ['', '一', '二', '三', '四', '五', '六', '日']
      const days = array(row['weekdays']).map((day: Object) => labels[number(day, 0)] || '').filter((day: string) => !!day)
      return `每周${days.join('、')} ${time} ${zone}`.trim()
    }
    case 'cron': return `${string(row['expression'])} ${zone}`.trim()
    case 'rrule': return string(row['rrule']) || '重复规则'
    default: return string(row['kind']) || '指定时间'
  }
}

export function scheduleStatus(row: WireObject): string {
  switch (row['status']) {
    case 'active': return '已开启'
    case 'paused': return '已暂停'
    case 'ended':
    case 'inactive': return '已结束'
    default: return string(row['status']) || '状态未知'
  }
}

export function scheduleTargetSession(row: WireObject): string {
  const target = object(row['target'])
  return target['kind'] === 'session' ? string(target['sessionId']) : string(row['sessionId'])
}

export function scheduleFailure(result: WireObject): void {
  const code = string(result['code'])
  if (!code) return
  switch (code) {
    case 'schedule_not_found': throw new Error('这个任务已经不在了')
    case 'schedule_conflict': throw new Error('任务刚被改过，刷新后再试')
    case 'schedule_ended': throw new Error('任务已结束，不能再改')
    case 'schedule_execution_pending': throw new Error('这项任务已有一次运行在排队或进行中')
    default: throw new Error(string(result['message']) || `主机拒绝任务操作（${code}）`)
  }
}

export function jobLive(job: WireObject): boolean {
  return job['status'] === 'running' || job['status'] === 'stopping'
}

export function jobStatus(job: WireObject): string {
  switch (job['status']) {
    case 'running': return '运行中'
    case 'stopping': return '正在停止'
    case 'completed': return '已完成'
    case 'killed': return '已停止'
    case 'failed': return '失败'
    default: return string(job['status']) || '状态未知'
  }
}

export function featureDate(value: Object | null | undefined): string {
  const timestamp = typeof value === 'string' ? Date.parse(value) : number(value, NaN)
  if (!Number.isFinite(timestamp)) return ''
  const date = new Date(timestamp)
  return Number.isFinite(date.getTime()) ? date.toLocaleString() : ''
}

export function subagentMode(value: Object | null | undefined): string {
  switch (value) {
    case 'one-shot': return '一次性'
    case 'continuable': return '可继续'
    case 'external': return '外部任务'
    default: return '模式未知'
  }
}

export function teamMessage(event: WireObject, recipient: string): WireObject | undefined {
  if (event['type'] !== 'user/message') return undefined
  const message = object(event['data'])
  const source = object(message['source'])
  if (source['kind'] !== 'agent-message' && source['kind'] !== 'team-message') return undefined
  const parts = array(message['content']).map(object).filter((part: WireObject) => part['type'] === 'text')
    .map((part: WireObject) => string(part['text']))
  const first = /^Team message from (.+?):\s*$/.exec(parts[0]?.trim() || '')
  const sender = string(source['senderName']) || (first ? first[1] : '')
  if (source['kind'] === 'agent-message' && !sender) return undefined
  const body = (first ? parts.slice(1) : parts).join('\n').trim()
  if (!body) return undefined
  const row: WireObject = { 'id': `${recipient}|${number(event['seq'], -1)}`, 'recipient': recipient,
    'senderId': string(source['senderSessionId']) || string(source['senderId']), 'senderName': sender,
    'time': event['time'], 'text': body }
  return row
}

export function scheduleTiming(kind: string, value: string, zone: string, weekdays: number[]): WireObject {
  const text = value.trim()
  const timing: WireObject = { 'kind': kind }
  if (!text) throw new Error('请输入运行时间')
  if (kind === 'after' || kind === 'every') {
    const seconds = Number(text)
    if (!/^\d+$/.test(text) || !Number.isSafeInteger(seconds) || seconds < (kind === 'every' ? 60 : 1)) {
      throw new Error(kind === 'every' ? '间隔至少 60 秒' : '请输入大于 0 的整秒数')
    }
    timing[kind === 'every' ? 'every_seconds' : 'after_seconds'] = seconds
  } else if (kind === 'at') {
    const local = /^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?)$/.exec(text)
    if (local && zone.trim()) {
      const date = new Date(`${local[1]}T00:00:00Z`)
      if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== local[1]) {
        throw new Error('请输入有效的日历日期')
      }
      const at: WireObject = { 'date': local[1], 'time': scheduleClock(local[2]),
        'time_zone': zone.trim() }
      timing['at'] = at
    } else if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/.test(text) &&
      Number.isFinite(Date.parse(text))) timing['at'] = text
    else throw new Error('请输入日期和时间，例如 2027-01-20 09:00，并填写时区')
  } else if (kind === 'daily' || kind === 'weekly') {
    if (!zone.trim()) throw new Error('请输入时区')
    const rule: WireObject = { 'time': scheduleClock(text), 'time_zone': zone.trim() }
    if (kind === 'weekly') {
      if (!weekdays.length) throw new Error('至少选一天')
      if (weekdays.some((day: number) => !Number.isInteger(day) || day < 1 || day > 7) ||
          new Set<number>(weekdays).size !== weekdays.length) throw new Error('星期必须为 1 到 7，且不能重复')
      rule['weekdays'] = weekdays.slice().sort((a: number, b: number) => a - b)
    }
    timing[kind] = rule
  } else if (kind === 'cron') {
    if (text.split(/\s+/).length !== 5) throw new Error('请输入五段 Cron 表达式')
    if (!zone.trim()) throw new Error('请输入时区')
    const cron: WireObject = { 'expression': text, 'time_zone': zone.trim() }
    timing['cron'] = cron
  } else if (kind === 'rrule') timing['rrule'] = text
  else throw new Error('未知的任务规则')
  return timing
}

function scheduleClock(text: string): string {
  if (!/^([01]\d|2[0-3]):[0-5]\d(?::[0-5]\d(?:\.\d{1,3})?)?$/.test(text)) throw new Error('请输入 24 小时时间')
  return text.length === 5 ? `${text}:00` : text
}

const PACKAGE = /^(?:@[a-z0-9][a-z0-9._~-]*\/)?[a-z0-9][a-z0-9._~-]*$/
const VERSION = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$/
const HTTPS = /^https:\/\/[A-Za-z0-9.-]+(?::\d+)?(?:\/[A-Za-z0-9._~@/+-]*)?$/i

export interface PluginTarget {
  spec: string
  registry: string
  version: string
}

function versionOrder(a: string, b: string): number {
  const first = VERSION.exec(a)
  const second = VERSION.exec(b)
  if (!first || !second) return 0
  for (let index = 1; index <= 3; index++) {
    const order = Number(second[index]) - Number(first[index])
    if (order !== 0) return order
  }
  if (!first[4] || !second[4]) return !first[4] ? (!second[4] ? 0 : -1) : 1
  const left = first[4].split('.')
  const right = second[4].split('.')
  for (let index = 0; index < Math.min(left.length, right.length); index++) {
    if (left[index] === right[index]) continue
    const leftNumber = /^\d+$/.test(left[index])
    const rightNumber = /^\d+$/.test(right[index])
    if (leftNumber && rightNumber) return Number(right[index]) - Number(left[index])
    if (leftNumber !== rightNumber) return leftNumber ? 1 : -1
    return left[index] > right[index] ? -1 : 1
  }
  return right.length - left.length
}

export function marketTarget(name: string, version: WireObject): PluginTarget | undefined {
  const value = string(version['version'])
  if (!PACKAGE.test(name) || !VERSION.test(value)) return undefined
  const source = object(version['source'])
  if (source['type'] === 'npm') {
    const registry = string(source['registry'])
    if (registry && !HTTPS.test(registry)) return undefined
    return { spec: `${name}@${value}`, registry: registry, version: value }
  }
  if (source['type'] !== 'git') return undefined
  const url = string(source['url'])
  const commit = string(source['commit'])
  const path = string(source['path'])
  if (!HTTPS.test(url) || !/^https:\/\/[^/]+\/[^/]+\/[^/]+/.test(url) || /\.(?:tgz|tar\.gz)$/i.test(url) ||
      !/^[a-f0-9]{40}$/.test(commit)) return undefined
  if (path && path.split('/').some((part: string) => !/^[A-Za-z0-9._@+-]+$/.test(part) || part === '.' || part === '..')) {
    return undefined
  }
  return { spec: `git+${url.endsWith('.git') ? url : `${url}.git`}#${commit}${path ? `&path:/${path}` : ''}`,
    registry: '', version: value }
}

export function marketEntries(index: WireObject, sidecar: WireObject): WireObject[] {
  if (index['format'] !== 1 || !Array.isArray(index['plugins'])) throw new Error('插件目录格式有误')
  const listings: WireObject = sidecar['schema'] === 1 ? object(sidecar['plugins']) : {}
  const names: Set<string> = new Set()
  const rows: WireObject[] = []
  for (const entry of array(index['plugins'])) {
    const row = object(entry)
    const name = string(row['name'])
    if (!PACKAGE.test(name) || names.has(name)) continue
    const versions = array(row['versions']).map(object)
      .filter((version: WireObject) => !!marketTarget(name, version))
      .sort((a: WireObject, b: WireObject) => versionOrder(string(a['version']), string(b['version'])))
    if (!versions.length) continue
    names.add(name)
    const version = versions[0]
    const listing = object(listings[name])
    const current: WireObject = listing['version'] === version['version'] ? listing : {}
    const meta: WireObject = { 'title': current['title'] ?? row['title'], 'description': current['summary'] ?? row['description'] }
    const normalized: WireObject = { 'name': name, 'meta': meta, 'version': version['version'], 'release': version,
      'listing': current, 'author': row['author'], 'category': row['category'], 'repository': row['repository'],
      'homepage': row['homepage'], 'keywords': row['keywords'], 'description': localizedPluginText(row['description']) }
    rows.push(normalized)
  }
  return rows
}

