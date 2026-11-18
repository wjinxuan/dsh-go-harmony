import { webSocket } from '@kit.NetworkKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { DshClient } from '../dsh/DshClient'
import { number, object, string, WireObject } from '../dsh/DshWire'
import { pluginMerge, PluginPlace } from './NativePluginData'

interface PluginWait { resolve: (value: WireObject) => void; reject: (error: Error) => void; timer: number }
export class NativePluginConnection {
  private locale: string
  private client: DshClient
  private socket?: webSocket.WebSocket
  private identity: number
  private closed: boolean = false
  private ready?: Promise<string>
  private readyResolve?: (value: string) => void
  private readyReject?: (error: Error) => void
  private timer: number = -1
  private retry: number = -1
  private conn: string = ''
  private subscription?: WireObject
  private data: WireObject = {}
  private revision: string = ''
  private waiting: Map<string, PluginWait> = new Map()
  private delivered: Map<string, WireObject> = new Map()
  onData: (data: WireObject) => void = () => {}
  onChanged: () => void = () => {}
  onError: (message: string) => void = () => {}

  constructor(client: DshClient, locale: string = 'zh-CN') { this.locale = locale; this.client = client; this.identity = client.connectionIdentity() }
  private current(): boolean { return !this.closed && this.identity === this.client.connectionIdentity() }
  async open(): Promise<string> {
    if (!this.current()) throw new Error('主机连接已变更')
    if (this.conn) return this.conn
    if (this.ready) return this.ready
    const session = this.client.webSession(); const socket = webSocket.createWebSocket(); this.socket = socket
    this.ready = new Promise<string>((resolve: (value: string) => void, reject: (error: Error) => void) => {
      this.readyResolve = resolve; this.readyReject = reject
    })
    this.timer = setTimeout(() => this.dropped('插件连接超时'), 10000)
    socket.on('open', () => { const hello: WireObject = { 't': 'hello', 'v': [1], 'locale': this.locale }; void this.send(hello) })
    socket.on('message', (_error, value: string | ArrayBuffer) => { if (typeof value === 'string') this.receive(value) })
    socket.on('error', () => this.dropped('插件连接中断'))
    socket.on('close', () => this.dropped('插件连接已关闭'))
    const headers: Record<string, string> = { 'cookie': session.cookie, 'authorization': session.authorization }
    const address = session.baseUrl.replace(/^http/, 'ws') + '/dsh-go/v1/stream'
    socket.connect(address, { header: headers, supportOriginPort: deviceInfo.sdkApiVersion >= 18 }).catch(() => this.dropped('插件连接失败'))
    return this.ready
  }
  private async send(value: WireObject): Promise<void> { if (this.current() && this.socket) await this.socket.send(JSON.stringify(value)) }
  private dropped(reason: string): void {
    if (!this.socket) return
    const socket = this.socket; this.socket = undefined; this.conn = ''; this.ready = undefined
    clearTimeout(this.timer); socket.off('open'); socket.off('message'); socket.off('error'); socket.off('close'); void socket.close().catch(() => {})
    this.readyReject?.(new Error(reason)); this.readyResolve = undefined; this.readyReject = undefined
    for (const wait of this.waiting.values()) { clearTimeout(wait.timer); wait.reject(new Error(reason)) }; this.waiting.clear()
    if (!this.current()) return
    this.onError(reason)
    if (this.subscription) this.retry = setTimeout(() => { void this.open().catch(() => {}) }, 1000)
  }
  cancelPending(): void {
    for (const id of this.waiting.keys()) { const request: WireObject = { 't': 'cancel', 'pending': id }; void this.send(request) }
  }
  close(): void { this.closed = true; clearTimeout(this.retry); this.dropped('插件界面已关闭'); this.delivered.clear() }
  async subscribe(place: PluginPlace, scope: WireObject, data: WireObject, revision: string): Promise<void> {
    this.data = data; this.revision = revision
    this.subscription = { 't': 'sub', 'sub': 'view', 'pkg': place.pkg, 'id': place.id, 'scope': scope }
    await this.open(); await this.resubscribe()
  }
  private async resubscribe(): Promise<void> {
    if (!this.subscription) return
    const request: WireObject = { 't': 'sub', 'sub': 'view', 'pkg': this.subscription['pkg'],
      'id': this.subscription['id'], 'scope': this.subscription['scope'] }
    if (this.revision) request['rev'] = this.revision
    await this.send(request)
  }
  private receive(text: string): void {
    if (!this.current() || text.length > 1048576) return
    let frame: WireObject
    try { frame = object(JSON.parse(text)) } catch { return }
    const type = string(frame['t'])
    if (type === 'welcome') { clearTimeout(this.timer); this.conn = string(frame['conn']); this.readyResolve?.(this.conn); this.readyResolve = undefined; this.readyReject = undefined; void this.resubscribe() }
    else if (type === 'ping') { const pong: WireObject = { 't': 'pong', 'at': frame['at'] }; void this.send(pong) }
    else if (type === 'changed') this.onChanged()
    else if (type === 'done' || type === 'void') {
      const id = string(frame['pending']); const wait = this.waiting.get(id)
      if (wait) { clearTimeout(wait.timer); this.waiting.delete(id); type === 'done' ? wait.resolve(frame) : wait.reject(new Error('插件操作已结束：' + string(frame['reason']))) }
      else if (id && this.delivered.size < 32) { this.delivered.set(id, frame); setTimeout(() => this.delivered.delete(id), 5000) }
    } else if (frame['sub'] === 'view') {
      if (type === 'data') { this.data = object(frame['data']); this.revision = string(frame['rev']); this.onData(this.data) }
      else if (type === 'patch') {
        if (!this.revision || frame['base'] !== this.revision) { void this.resubscribe(); return }
        this.data = pluginMerge(this.data, object(frame['merge'])); this.revision = string(frame['rev']); this.onData(this.data)
      } else if (type === 'stale') this.onError('插件数据已失效，请刷新')
      else if (type === 'end') { this.subscription = undefined; this.onError('插件已结束：' + string(frame['reason'])) }
    }
  }
  async result(value: WireObject): Promise<WireObject> {
    const pending = object(value['pending']); const id = string(pending['id']); if (!id) return value
    const early = this.delivered.get(id)
    if (early) { this.delivered.delete(id); if (early['t'] === 'void') throw new Error('插件操作已结束'); return early }
    return new Promise<WireObject>((resolve: (value: WireObject) => void, reject: (error: Error) => void) => {
      const timer = setTimeout(() => { this.waiting.delete(id); reject(new Error('插件操作未能确认')) }, Math.max(1000, Math.min(60000, number(pending['timeoutMs'], 30000))))
      this.waiting.set(id, { resolve: resolve, reject: reject, timer: timer })
    })
  }
}
