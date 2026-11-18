import { object, string, WireObject } from '../dsh/DshWire'
import { pluginAction, pluginBinding, pluginBindings, PluginNode } from './NativePluginData'
import { PLUGIN_INPUTS, pluginInputData, pluginInputIssue, pluginInputSubmitted } from './NativePluginControlsData'
interface PluginDraft { value: Object | null; revision: number; clean: boolean }
interface PluginRequest { key: string; action: WireObject; revisions: Map<string, number>; bindings: string[]; resolve: (ok: boolean) => void }
// One sequential invocation lane preserves edits made while an earlier request is in flight.
export class NativePluginDrafts {
  private remote: WireObject = {}
  private inputs: Map<string, PluginNode> = new Map()
  private drafts: Map<string, PluginDraft> = new Map()
  private timers: Map<string, number> = new Map()
  private queue: PluginRequest[] = []
  private revision: number = 0
  private running: boolean = false
  private disposed: boolean = false
  private lastChange: number = 0
  private sequence: number = 0
  private remoteRevision: number = 0
  private changedRemote: Map<string, number> = new Map()
  error: string = ''
  handler?: (action: WireObject) => Promise<boolean>
  changed?: () => void
  syncRemote(value: WireObject): void {
    if (value === this.remote) return
    this.remoteRevision++
    for (const bind of this.inputs.keys()) {
      const ref: WireObject = { '$': bind }
      if (JSON.stringify(pluginBinding(ref, this.remote)) !== JSON.stringify(pluginBinding(ref, value))) {
        this.changedRemote.set(bind, this.remoteRevision)
        if (this.drafts.get(bind)?.clean) this.drafts.delete(bind)
      }
    }
    this.remote = value
  }
  syncInputs(root: PluginNode): void {
    this.inputs.clear()
    const visit = (node: PluginNode): void => { const bind = string(node.raw['bind']); if (PLUGIN_INPUTS.includes(node.type) && bind) this.inputs.set(bind, node); node.children.forEach(visit) }; visit(root)
    for (const bind of this.drafts.keys()) if (!this.inputs.has(bind)) this.drafts.delete(bind)
    for (const bind of this.timers.keys()) if (!this.inputs.has(bind)) { clearTimeout(this.timers.get(bind)); this.timers.delete(bind) }
    this.queue = this.queue.filter((request: PluginRequest) => { if (request.bindings.some((bind: string) => !this.inputs.has(bind))) { request.resolve(false); return false }; return true })
  }
  data(): WireObject { let value = this.remote; for (const entry of this.drafts.entries()) value = pluginInputData(value, entry[0], entry[1].value); return value }
  private value(bind: string): Object | null { return this.drafts.get(bind)?.value ?? this.inputs.get(bind)?.raw['value'] ?? null }
  edit(bind: string, value: Object | null): void {
    const input = this.inputs.get(bind)
    if (!this.handler || !input || input.raw['readOnly'] === true || this.disposed) return
    this.drafts.set(bind, { value: value, revision: ++this.revision, clean: false }); this.error = ''
    clearTimeout(this.timers.get(bind)); this.timers.delete(bind)
    if (input.raw['onChange']) this.timers.set(bind, setTimeout(() => {
      this.timers.delete(bind); const current = this.inputs.get(bind); if (!current || this.disposed) return
      this.error = pluginInputIssue(current.raw, this.value(bind)); const action = pluginAction(current.raw['onChange'])
      if (!this.error && action) {
        const args = object(pluginBindings(action['args'], this.data())); args['bind'] = bind; args['value'] = pluginInputSubmitted(current.raw, this.value(bind))
        const request: WireObject = { 'id': action['id'], 'args': args, 'gesture': false }; void this.enqueue('change:' + bind, request, [bind])
      }
      this.changed?.()
    }, 250))
    this.changed?.()
  }
  async submit(form: PluginNode): Promise<boolean> {
    const action = pluginAction(form.raw['submit']); if (!action) return false
    const values: WireObject = {}; this.error = ''
    const visit = (node: PluginNode): void => {
      const bind = string(node.raw['bind'])
      if (PLUGIN_INPUTS.includes(node.type) && bind && node.raw['readOnly'] !== true) {
        this.error = this.error || pluginInputIssue(node.raw, this.value(bind)); values[bind] = pluginInputSubmitted(node.raw, this.value(bind))
      }
      node.children.forEach(visit)
    }; visit(form)
    if (this.error) { this.changed?.(); return false }
    const bindings = Object.keys(values)
    for (const bind of bindings) { clearTimeout(this.timers.get(bind)); this.timers.delete(bind) }
    this.queue = this.queue.filter((request: PluginRequest) => { if (request.key.startsWith('change:') && bindings.includes(request.key.slice(7))) { request.resolve(false); return false }; return true })
    const args = object(pluginBindings(action['args'], this.data())); args['values'] = values
    const request: WireObject = { 'id': action['id'], 'args': args, 'gestureAt': Date.now() }
    return this.enqueue('submit:' + form.key, request, bindings)
  }
  invoke(action: WireObject): Promise<boolean> {
    const request = object(pluginBindings(action, this.data())); request['gestureAt'] = Date.now()
    return this.enqueue('action:' + (++this.sequence), request, [])
  }
  private enqueue(key: string, action: WireObject, bindings: string[]): Promise<boolean> {
    if (this.disposed || !this.handler || encodeURIComponent(JSON.stringify(action['args'] || null)).replace(/%[A-F\d]{2}/g, 'x').length > 4096 || this.queue.length >= 120) {
      this.error = '插件操作未能确认'; this.changed?.(); return Promise.resolve(false)
    }
    this.queue = this.queue.filter((request: PluginRequest) => { if (request.key === key) { request.resolve(false); return false }; return true })
    const revisions: Map<string, number> = new Map(); for (const bind of bindings) revisions.set(bind, this.drafts.get(bind)?.revision || 0)
    return new Promise<boolean>((resolve: (ok: boolean) => void) => { this.queue.push({ key: key, action: action, revisions: revisions, bindings: bindings, resolve: resolve }); void this.drain() })
  }
  private async drain(): Promise<void> {
    if (this.running || this.disposed) return
    this.running = true
    try {
      while (this.queue.length && !this.disposed) {
        const request = this.queue.shift()!; const revision = this.remoteRevision
        if (request.action['gesture'] === false) { const wait = 250 - (Date.now() - this.lastChange); if (wait > 0) await new Promise<void>((resolve: () => void) => setTimeout(resolve, wait)); this.lastChange = Date.now() }
        let ok = false
        try { if (!this.disposed && this.handler) ok = await this.handler(request.action) } catch {}
        if (this.disposed) ok = false
        for (const bind of request.bindings) {
          const draft = this.drafts.get(bind); if (!draft || draft.revision !== request.revisions.get(bind)) continue
          if (ok) { if ((this.changedRemote.get(bind) || 0) > revision) this.drafts.delete(bind); else draft.clean = true }
        }
        if (!ok && !this.disposed) this.error = '插件操作未能确认'
        request.resolve(ok); this.changed?.()
      }
    } finally { this.running = false }
  }
  dispose(): void { this.disposed = true; this.handler = undefined; for (const timer of this.timers.values()) clearTimeout(timer); this.timers.clear(); for (const request of this.queue) request.resolve(false); this.queue = [] }
}
