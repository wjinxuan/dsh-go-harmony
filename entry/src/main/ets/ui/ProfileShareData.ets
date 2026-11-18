import { array, object, string, strings, number, WireObject } from '../dsh/DshWire'
export interface ProfileShareTransport {
  request: (action: string, body: WireObject) => Promise<WireObject>
  cancel: () => void
}
export interface ProfileShareHost {
  identity: () => number
  settings: () => Promise<WireObject>
  bundles: () => Promise<WireObject[]>
  presets: () => Promise<WireObject[]>
  request: (method: string, body: WireObject, timeout: number) => Promise<Object | null | undefined>
}
export function profileRows(value: Object | null | undefined): WireObject[] { return array(value).map(object) }
export function profileSelection(rows: WireObject[]): string[] { return rows.filter((row: WireObject) => row['defaultOn'] === true && !row['blocked'] && !row['follows']).map((row: WireObject) => string(row['id'])) }
function profileValueEqual(left: Object | null | undefined, right: Object | null | undefined): boolean {
  if (left === right) return true
  if (Array.isArray(left) || Array.isArray(right)) {
    if (!Array.isArray(left) || !Array.isArray(right)) return false
    const a = array(left), b = array(right)
    return a.length === b.length && a.every((value: Object | null, index: number) => profileValueEqual(value, b[index]))
  }
  if (!left || !right || typeof left !== 'object' || typeof right !== 'object') return false
  const a = object(left), b = object(right), keys = Object.keys(a), other = Object.keys(b)
  return keys.length === other.length && keys.every((key: string) => other.includes(key) && profileValueEqual(a[key], b[key]))
}
export class ProfileShareController {
  source: WireObject = {}
  plan: WireObject = {}
  result: WireObject = {}
  statuses: WireObject = {}
  backup: string = ''
  needsRestart: boolean = false
  applying: boolean = false
  onChange: () => void = () => {}
  private generation: number = 0
  private identity: number
  private stopped: boolean = false
  private installId: string = ''
  private service: ProfileShareTransport
  private host: ProfileShareHost
  private local: boolean
  private canInstall: boolean
  constructor(service: ProfileShareTransport, host: ProfileShareHost, local: boolean, canInstall: boolean) {
    this.service = service; this.host = host; this.local = local; this.canInstall = canInstall; this.identity = host.identity()
  }
  current(): boolean { return !this.stopped && this.identity === this.host.identity() }
  private check(generation: number): void { if (!this.current() || generation !== this.generation) throw new Error('分享操作已取消或主机已变更') }
  cancel(): void {
    this.generation++; this.service.cancel()
    if (this.installId && this.current()) { const args: WireObject = { 'requestId': this.installId }; void this.host.request('pluginManager/cancelInstall', args, 300000).catch(() => {}) }
  }
  close(): void { this.cancel(); this.stopped = true }
  private async snapshot(): Promise<WireObject> {
    const generation = this.generation
    const result: WireObject = { 'local': this.local, 'canInstall': this.canInstall }
    const settings = this.host.settings().then((v: WireObject) => { result['settings'] = v }).catch(() => {})
    const bundles = this.host.bundles().then((v: WireObject[]) => { result['bundles'] = v }).catch(() => {})
    const presets = this.host.presets().then((v: WireObject[]) => { result['presets'] = v }).catch(() => {})
    await Promise.all([settings,bundles,presets]); this.check(generation); return result
  }
  async load(): Promise<void> {
    const generation = this.generation, snapshot = await this.snapshot()
    const args: WireObject = { 'snapshot': snapshot, 'local': this.local }
    const value = await this.service.request('profile-source',args); this.check(generation); this.source = value; this.result = {}; this.onChange()
  }
  async prepare(selected: string[], name: string, pluginOnly: boolean): Promise<void> {
    const generation = this.generation
    const args: WireObject = { 'source': this.source, 'selected': selected, 'name': name, 'pluginOnly': pluginOnly }
    const value = await this.service.request('profile-prepare', args); this.check(generation); this.result = value; this.onChange()
  }
  async preview(payload: WireObject): Promise<void> {
    const generation = this.generation, snapshot = await this.snapshot()
    const args: WireObject = { 'payload': payload, 'snapshot': snapshot }
    const value = await this.service.request('profile-plan',args); this.check(generation); this.plan = value; this.statuses = {}; this.onChange()
  }
  private status(id: string, state: string, detail: string = ''): void {
    const next: WireObject = {}; for (const key of Object.keys(this.statuses)) next[key] = this.statuses[key]
    const row: WireObject = { 'state': state, 'detail': detail }; next[id] = row; this.statuses = next; this.onChange()
  }
  private operation(value: Object | null | undefined): WireObject {
    const result = object(value)
    if (strings(result['pendingBuilds']).length) throw new Error('插件需要构建脚本，请到插件管理中审阅后继续')
    if (object(result['error'])['code'] || !['applied','restart-required'].includes(string(result['application']))) throw new Error('主机未确认插件操作成功')
    if (result['application'] === 'restart-required') this.needsRestart = true
    return result
  }
  private async plugin(row: WireObject, generation: number): Promise<void> {
    if (!this.canInstall) throw new Error('当前主机不支持插件安装或启用')
    const plugin = object(row['plugin']), name = string(plugin['name']), bundles = await this.host.bundles(); this.check(generation)
    const current = bundles.find((v: WireObject) => v['name'] === name)
    if (row['kind'] === 'upgrade' && (!current || current['version'] !== row['fromVersion'] || current['source'] !== row['fromSource'])) throw new Error('插件版本刚被改过，请重新预览')
    if (row['kind'] === 'install' && current?.['installed'] === true) throw new Error('插件刚被安装，请重新预览')
    if (row['kind'] === 'enable' && !row['installSpec']) {
      const args: WireObject = { 'name': name, 'enabled': true }; this.operation(await this.host.request('pluginManager/setBundleEnabled', args, 60000)); this.check(generation); return
    }
    const inspectOptions: WireObject = {}
    const spec = string(row['installSpec']), inspectArgs: WireObject = { 'spec': spec, 'options': inspectOptions }
    const inspected = object(await this.host.request('pluginManager/inspect',inspectArgs,60000)); this.check(generation)
    if (inspected['status'] !== 'accepted' || inspected['bundle'] === false || inspected['name'] !== name || plugin['source'] === 'npm' && inspected['version'] !== plugin['version']) throw new Error('主机未确认指定插件版本可安装')
    if (row['kind'] === 'upgrade') {
      const removal: WireObject = { 'name': name }; const removed = this.operation(await this.host.request('pluginManager/removeBundle',removal,600000)); this.check(generation)
      if (removed['changed'] !== true) throw new Error('主机未确认旧插件已卸载')
    }
    const id = 'dsh-app-share-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2)
    const options: WireObject = { 'requestId': id, 'enabled': true, 'saveExact': true }
    if (string(inspected['registry'])) options['registry'] = inspected['registry']
    const args: WireObject = { 'spec': spec, 'options': options }; this.installId = id
    try {
      let result: Object | null | undefined = undefined
      try { result = await this.host.request('pluginManager/installBundle',args,1800000) }
      catch (failure) { this.check(generation); const wait: WireObject = { 'requestId': id }; result = await this.host.request('pluginManager/waitForInstall',wait,1800000) }
      this.check(generation); this.operation(result)
    } finally { if (this.installId === id) this.installId = '' }
  }
  async apply(selected: string[], confirmed: boolean): Promise<void> {
    if (!confirmed || this.applying) throw new Error('需要确认导入')
    const generation = this.generation; this.check(generation)
    const rows = profileRows(this.plan['changes']), allowed = rows.filter((v: WireObject) => !v['blocked'] && v['kind'] !== 'unchanged' && !v['follows'])
    if (!selected.length || selected.some((id: string) => !allowed.some((v: WireObject) => v['id'] === id))) throw new Error('导入选择已失效，请重新预览')
    this.applying = true; this.statuses = {}; this.needsRestart = false
    const chosen = rows.filter((v: WireObject) => selected.includes(string(v['id'])) || selected.includes(string(v['follows'])))
    for (const row of chosen) this.status(string(row['id']),'pending')
    try {
      if (this.local) { const args: WireObject = { 'confirmed': true }; const result = await this.service.request('profile-backup',args); this.check(generation); this.backup = string(result['backup']) }
      for (const row of chosen) {
        const id = string(row['id']); this.check(generation); this.status(id,'running')
        try {
          const section = string(row['section'])
          if (section === 'plugins') await this.plugin(row,generation)
          else if (section === 'presets') { if (object(this.statuses[string(row['follows'])])['state'] !== 'done') throw new Error('所属插件未安装，预设已跳过') }
          else if (section === 'settings') {
            const ns = id.slice(9), current = await this.host.settings(); this.check(generation)
            const view = profileRows(current['namespaces']).find((v: WireObject) => v['ns'] === ns)
            if (!view || current['writable'] === false || view['writable'] === false) throw new Error('当前主机没有可写的配置项')
            if (row['revision'] !== undefined && row['revision'] !== view['revision']) throw new Error('主机设置已更改，请重新预览后导入')
            if (row['revision'] === undefined) {
              const settings: WireObject = {}; settings[ns] = object(object(this.plan['payload'])['settings'])[ns]
              const payload: WireObject = { 'v': 1, 'kind': 'profile', 'settings': settings }
              const snapshot: WireObject = { 'settings': current, 'local': this.local, 'canInstall': this.canInstall }
              const review: WireObject = { 'payload': payload, 'snapshot': snapshot }
              const fresh = await this.service.request('profile-plan',review); this.check(generation)
              const admitted = profileRows(fresh['changes']).find((v: WireObject) => v['id'] === id)
              if (!admitted || admitted['blocked'] || admitted['sensitive'] === true && row['sensitive'] !== true ||
                JSON.stringify(admitted['ops']) !== JSON.stringify(row['ops'])) throw new Error('主机设置已更改，请重新预览后导入')
            }
            const args: WireObject = { 'ns': ns, 'ops': row['ops'] ?? [], 'expectedRevision': number(view['revision'],0) }
            await this.host.request('settings/mutate',args,20000); this.check(generation)
            const readback = await this.host.settings(); this.check(generation)
            const acknowledged = profileRows(readback['namespaces']).find((v: WireObject) => v['ns'] === ns)
            if (!acknowledged || profileRows(row['ops']).some((op: WireObject) => {
              let value: Object | null | undefined = acknowledged['value']
              let saved: Object | null | undefined = acknowledged['user']
              for (const key of strings(op['path'])) { value = object(value)[key]; saved = object(saved)[key] }
              // settings.user is the persisted raw override; value includes schema defaults,
              // including extra members inside arrays. An inherited/legacy value remains exact.
              return !profileValueEqual(saved === undefined ? value : saved, op['value'])
            })) throw new Error('主机未确认配置已导入')
          } else if (section === 'skills' || section === 'agentsMd') {
            if (!this.local) throw new Error('技能和提示文件只能导入本机引擎')
            const expected: WireObject = {}; expected[id] = row['expected']
            const args: WireObject = { 'payload': object(this.plan['payload']), 'selected': [id], 'expected': expected, 'confirmed': true }
            const result = await this.service.request('profile-files-apply',args); this.check(generation)
            if (!strings(result['done']).includes(id)) throw new Error('本机未确认文件已导入'); this.backup = string(result['backup']); this.needsRestart = true
          }
          this.check(generation); this.status(id,'done')
        } catch (error) { this.check(generation); this.status(id,'failed',error instanceof Error ? error.message : '导入失败') }
      }
    } finally { this.applying = false; for (const row of chosen) { const id = string(row['id']); if (['pending','running'].includes(string(object(this.statuses[id])['state']))) this.status(id,'skipped','操作已取消，已完成的更改会保留') }; this.onChange() }
  }
}
