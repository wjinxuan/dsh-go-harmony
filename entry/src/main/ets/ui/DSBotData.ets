import { array, number, object, string, strings, DshRpcError, WireObject } from '../dsh/DshWire'
import { DsBotEvent } from '../dsh/DsBotProtocol'

export interface DSBotTransport {
  call: (endpoint: string, payload: WireObject, timeout?: number) => Promise<Object | null>
  feed: (consume: (event: DsBotEvent) => void, failed: (reason: string) => void) => () => void
  current: () => boolean
  cancel: (sessionId: string) => Promise<void>
}
export interface DSBotScope { epoch: number; boot: string; id: string; room: boolean; session: string }
export interface DSBotInbox { boot: string; seen: WireObject; seq?: number }
export interface DSBotRange { first: number; last: number }
export function dsBotFailure(error: Error): string {
  const code = error instanceof DshRpcError ? error.code : ''
  if (code === 'bot/read-only') return '此团队由另一台主机管理，当前只能查看。'
  if (code === 'bot/http-404') return '此主机尚未安装或启用 DS Bot。'
  if (code === 'bot/http-401' || code === 'bot/http-403') return '主机认证失败，请重新连接。'
  if (code === 'bot/connection-changed' || code === 'bot/stale') return '主机或 Bot 已更改，请重新打开。'
  if (code === 'bot/protocol') return 'DS Bot 返回了无效响应。'
  return 'DS Bot 操作未能完成，请重试。'
}
export function dsBotItems(value: Object | null | undefined): WireObject[] {
  return array(value).map(object).filter((item: WireObject) => ['user','bot','event','answer','divider'].includes(string(item['kind'])))
}
export function dsBotMerge(before: WireObject[], after: WireObject[]): WireObject[] {
  const result: WireObject[] = before.slice()
  for (const item of after) {
    const at = result.findIndex((other: WireObject) => item['id'] && other['id'] ? item['id'] === other['id'] :
      item['kind'] === other['kind'] && item['time'] === other['time'] && item['text'] === other['text'])
    if (at >= 0) result[at] = item; else result.push(item)
  }
  return result
}
export function dsBotSession(bot: WireObject): string { return string(bot['sessionId']) || string(bot['id']) }
export function dsBotToken(id: string): string { return id.trim() }
export function dsBotMemoryTarget(id: string, room: boolean): WireObject { return room ? { 'roomId': id } : { 'botId': id } }
export function dsBotEntries(value: Object | null | undefined): WireObject[] { return array(value).map(object) }
export function dsBotWork(live: WireObject, id: string, room: boolean): WireObject[] {
  const work = object(live['work'])
  return room ? dsBotEntries(object(work['rooms'])[id]) : Object.keys(object(object(work['bots'])[id])).length ? [object(object(work['bots'])[id])] : []
}
export function dsBotBotPayload(draft: WireObject, create: boolean): WireObject {
  const name = string(draft['name']).trim()
  if (!name || name.length > 200) throw new Error('请输入 Bot 名称（最多 200 字）')
  const value: WireObject = { 'name': name }
  for (const key of ['role','instructions','color','model','effort']) if (typeof draft[key] === 'string') value[key] = draft[key]
  if (create && typeof draft['brief'] === 'string' && string(draft['brief']).trim()) value['brief'] = string(draft['brief']).trim()
  if (!create && typeof draft['workDir'] === 'string') value['workDir'] = string(draft['workDir']).trim()
  return value
}
export function dsBotRoomPayload(draft: WireObject, previous?: WireObject): WireObject {
  const members = strings(draft['members']); if (members.length < 2 || new Set(members).size !== members.length) throw new Error('群聊至少需要两个不同的 Bot')
  const admin = string(draft['admin']); if (admin && !members.includes(admin)) throw new Error('管理员必须是群聊成员')
  if (!previous) return { 'name': string(draft['name']).trim(), 'members': members, 'admin': admin || members[0], 'greet': draft['greet'] !== false }
  const old = strings(previous['members']); const value: WireObject = { 'name': string(draft['name']).trim(), 'notice': string(draft['notice']),
    'mode': draft['mode'] === 'everyone' ? 'everyone' : 'admin', 'admin': admin || members[0],
    'add': members.filter((id: string) => !old.includes(id)), 'remove': old.filter((id: string) => !members.includes(id)), 'workDir': string(draft['workDir']).trim() }
  const limit = string(draft['relayLimit']).trim()
  if (limit && (!/^\d+$/.test(limit) || Number(limit) < 1 || Number(limit) > 200)) throw new Error('群聊接力上限须为 1–200，留空使用默认值')
  value['relayLimit'] = limit ? Number(limit) : null
  return value
}
export class DSBotHub {
  availability: string = 'connecting'
  hello: WireObject = {}
  team: WireObject = {}
  live: WireObject = {}
  failure: string = ''
  feedConnected: boolean = false
  chatId: string = ''
  chatRoom: boolean = false
  chatSession: string = ''
  chatItems: WireObject[] = []
  cursor: Object | null | undefined = undefined
  streamText: string = ''
  streamAttempt: string = ''
  chatLoading: boolean = false
  unread: Map<string, number> = new Map()
  latest: Map<string, WireObject> = new Map()
  onChange: () => void = () => {}
  onNotice: (notice: WireObject, caughtUp: boolean) => void = () => {}
  onInbox: (inbox: DSBotInbox) => void = () => {}
  private listeners: Set<() => void> = new Set()
  subscribe(listener: () => void): () => void { this.listeners.add(listener); return () => { this.listeners.delete(listener) } }
  private transport: DSBotTransport
  private locale: () => string
  private epoch: number = 0
  private closed: boolean = false
  private stopFeed?: () => void
  private retry: number = -1
  private refreshTimer: number = -1
  private chatPoll: number = -1
  private continued: Set<string> = new Set()
  private failures: number = 0
  private refreshBusy: boolean = false
  private refreshAgain: boolean = false
  private chatEpoch: number = 0
  private viewEpoch: number = 0
  private noticesBusy: boolean = false
  private ranges: DSBotRange[] = []
  private inbox: DSBotInbox = { boot: '', seen: {} }
  private viewing: string = ''
  private catchupPending: boolean = true
  private sequenceFloor: number = -1
  constructor(transport: DSBotTransport, locale: () => string, inbox?: DSBotInbox) { this.transport = transport; this.locale = locale; if (inbox) this.inbox = inbox }
  current(): boolean { return !this.closed && this.transport.current() }
  bots(): WireObject[] { return dsBotEntries(this.team['bots']) }
  rooms(): WireObject[] { return dsBotEntries(this.team['rooms']) }
  entity(id: string, room: boolean): WireObject | undefined { return (room ? this.rooms() : this.bots()).find((entry: WireObject) => entry['id'] === id) }
  readOnly(): string { return string(this.team['readOnly']) || string(this.hello['readOnly']) }
  writable(): boolean { return this.current() && this.availability === 'ready' && !this.readOnly() }
  supports(name: string): boolean { return strings(this.hello['capabilities']).includes(name) }
  ownedSessions(): string[] { const result: string[] = []; for (const bot of this.bots()) result.push(string(bot['id']),dsBotSession(bot),...strings(bot['parts'])); for (const room of this.rooms()) result.push(string(room['id']),...strings(room['parts'])); return Array.from(new Set(result.filter((id: string) => !!id))) }
  scope(id: string = '', room: boolean = false): DSBotScope { const entity = this.entity(id,room); return { epoch: this.epoch, boot: string(this.hello['boot']), id: id, room: room, session: id ? room ? id : dsBotSession(entity || {}) : '' } }
  same(scope: DSBotScope, write: boolean = false): boolean {
    if (!this.current() || scope.epoch !== this.epoch || scope.boot !== string(this.hello['boot']) || this.availability !== 'ready' || (write && !this.writable())) return false
    const entity = scope.id ? this.entity(scope.id,scope.room) : undefined
    return !scope.id || !!entity && (scope.room || dsBotSession(entity) === scope.session)
  }
  assert(scope: DSBotScope, write: boolean = false): void { if (!this.same(scope,write)) throw new DshRpcError(this.readOnly() ? 'bot/read-only' : 'bot/stale','DS Bot target changed') }
  private changed(): void { if (this.current()) { this.onChange(); for (const listener of this.listeners) listener() } }
  async start(): Promise<void> {
    if (!this.current()) return
    const epoch = ++this.epoch; this.stopFeed?.(); this.stopFeed = undefined; clearTimeout(this.retry); clearTimeout(this.refreshTimer); clearTimeout(this.chatPoll)
    this.availability = 'connecting'; this.failure = ''; this.feedConnected = false; this.refreshBusy = false; this.refreshAgain = false; this.noticesBusy = false; this.changed()
    try {
      const client: WireObject = { 'name': 'dsh-go', 'platform': 'harmony' }; const request: WireObject = { 'client': client, 'api': [1] }
      const hello = object(await this.transport.call('hello', request))
      if (!this.current() || epoch !== this.epoch) return
      this.hello = hello
      const boot = string(hello['boot'])
      if (this.inbox.boot !== boot || this.inbox.seq === undefined) { this.inbox = { boot: boot, seen: {}, seq: number(hello['seq'],0) }; this.ranges = []; this.unread.clear(); this.latest.clear(); this.onInbox(this.inbox) }
      this.sequenceFloor = number(this.inbox.seq,-1); this.catchupPending = true
      if (hello['api'] !== 1) { this.availability = 'outdated'; this.changed(); return }
      await this.refresh(true)
      if (this.current() && epoch === this.epoch && this.availability === 'ready') { this.connectFeed(); void this.catchUp() }
    } catch (error) {
      if (!this.current() || epoch !== this.epoch) return
      const failure = error as Error, code = failure instanceof DshRpcError ? failure.code : ''
      this.availability = ['bot/http-404','gateway/invocation-unavailable'].includes(code) ? 'missing' : ['bot/not-found','bot/read-only'].includes(code) ? 'outdated' : code === 'METHOD_NOT_ALLOWED' ? 'relay' : code === 'bot/offline' ? 'offline' : 'failed'
      this.failure = dsBotFailure(failure); this.changed()
    }
  }
  async refresh(full: boolean = false): Promise<void> {
    if (!this.current()) return
    if (this.refreshBusy) { this.refreshAgain = true; return }
    this.refreshBusy = true; const epoch = this.epoch
    try {
      do {
        this.refreshAgain = false
        const payload: WireObject = { 'locale': this.locale(), 'avatars': 'ref' }
        if (!full && this.team['revision'] !== undefined) payload['since'] = this.team['revision']
        if (this.team['modelsKey']) payload['models'] = this.team['modelsKey']
        const state = object(await this.transport.call('state',payload))
        if (!this.current() || epoch !== this.epoch) return
        if (typeof state['revision'] !== 'number' || state['unchanged'] !== true && !Array.isArray(state['bots'])) throw new DshRpcError('bot/protocol','Invalid team')
        this.live = state
        if (state['unchanged'] !== true) { if (!Array.isArray(state['models']) && Array.isArray(this.team['models'])) state['models'] = this.team['models']; this.team = state }
        this.availability = 'ready'; this.failure = ''; this.changed()
        const entity = this.entity(this.chatId,this.chatRoom)
        if (this.chatId && (!entity || !this.chatRoom && this.chatSession && dsBotSession(entity) !== this.chatSession)) { this.chatEpoch++; this.chatItems = []; this.streamText = ''; this.chatSession = ''; if (entity) void this.loadChat() }
      } while (this.refreshAgain)
    } catch (error) { if (this.current() && epoch === this.epoch) { this.failure = dsBotFailure(error as Error); if (this.availability !== 'ready') this.availability = 'failed'; this.changed() } }
    finally { if (epoch === this.epoch) this.refreshBusy = false }
  }
  private scheduleRefresh(): void { if (this.refreshTimer >= 0) return; this.refreshTimer = setTimeout(() => { this.refreshTimer = -1; void this.refresh() },100) }
  private connectFeed(): void {
    if (!this.current()) return
    const epoch = this.epoch
    try { this.stopFeed = this.transport.feed((event: DsBotEvent) => { if (this.current() && epoch === this.epoch) this.event(event) }, (reason: string) => {
      if (!this.current() || epoch !== this.epoch) return
      this.stopFeed = undefined; this.feedConnected = false; this.failure = reason; this.changed()
      this.retry = setTimeout(() => this.connectFeed(), [500,1000,2000,5000,10000][Math.min(this.failures++,4)])
    }) } catch { this.retry = setTimeout(() => this.connectFeed(),1000) }
  }
  kick(): void { if (!this.current()) return; if (!this.stopFeed) { clearTimeout(this.retry); this.failures = 0; this.connectFeed() }; void this.refresh(); void this.catchUp() }
  private event(event: DsBotEvent): void {
    const value = event.data
    if (event.event === 'hello') {
      const boot = string(value['boot']); if (boot && boot !== this.hello['boot']) { this.chatEpoch++; this.chatItems = []; this.streamText = ''; this.ranges = []; void this.start(); return }
      this.feedConnected = true; this.failures = 0; this.failure = ''; this.scheduleRefresh(); void this.catchUp()
    } else if (event.event === 'revision') this.scheduleRefresh()
    else if (event.event === 'live') { this.live = value; this.changed() }
    else if (event.event === 'notice') this.notice(value, false)
    else if (event.event === 'room') { if (value['roomId'] === this.chatId && this.chatRoom) void this.loadChat(); this.scheduleRefresh() }
    else if (event.event === 'message') {
      if (!this.chatRoom && value['botId'] === this.chatId && value['sessionId'] === (this.chatSession || dsBotSession(this.entity(this.chatId,false) || {}))) { this.chatItems = dsBotMerge(this.chatItems,dsBotItems([object(value['item'])])); this.streamText = ''; this.streamAttempt = ''; this.changed() }
    } else if (event.event === 'stream' && !this.chatRoom && value['botId'] === this.chatId && value['sessionId'] === (this.chatSession || dsBotSession(this.entity(this.chatId,false) || {}))) {
      const attempt = string(value['attemptId']); if (attempt !== this.streamAttempt) { this.streamAttempt = attempt; this.streamText = '' }
      this.streamText = string(value['text']); if (['done','failed','cancelled'].includes(string(value['phase']))) this.streamText = ''; this.changed()
    }
  }
  private addSequence(seq: number): boolean {
    if (!Number.isSafeInteger(seq) || seq <= this.sequenceFloor || seq < 0 || this.ranges.some((range: DSBotRange) => seq >= range.first && seq <= range.last)) return false
    let at = 0; while (at < this.ranges.length && this.ranges[at].last < seq-1) at++
    let first = seq, last = seq
    while (at < this.ranges.length && this.ranges[at].first <= last+1) { const old = this.ranges.splice(at,1)[0]; first = Math.min(first,old.first); last = Math.max(last,old.last) }
    this.ranges.splice(at,0,{ first: first, last: last }); return true
  }
  private notice(notice: WireObject, caughtUp: boolean): void {
    const seq = number(notice['seq'],-1); if (!this.addSequence(seq)) return
    const id = string(notice['roomId']) || string(notice['botId']); if (!id) return
    const previous = this.latest.get(id)
    if (!previous || seq > number(previous['seq'],-1)) this.latest.set(id,notice)
    if (id === this.viewing) this.markRead(id)
    else if (seq > number(this.inbox.seen[id],0)) { this.unread.set(id,(this.unread.get(id) || 0)+1); if (['message','group','done','question','view','approval'].includes(string(notice['kind']))) this.onNotice(notice,caughtUp) }
    if (!this.catchupPending) { this.inbox.seq = Math.max(number(this.inbox.seq,0),seq); this.onInbox(this.inbox) }
    this.changed()
  }
  private async catchUp(): Promise<void> {
    if (!this.current() || this.noticesBusy || this.availability !== 'ready') return
    this.noticesBusy = true; const epoch = this.epoch
    try {
      const boot = string(this.hello['boot']), since = number(this.inbox.seq,0)
      const payload: WireObject = { 'boot': boot, 'since': since }
      const answer = object(await this.transport.call('notices',payload))
      if (!this.current() || epoch !== this.epoch) return
      const next = string(answer['boot']); if (next && next !== boot) { void this.start(); return }
      if (answer['reset'] !== true) for (const notice of dsBotEntries(answer['notices'])) this.notice(notice,true)
      const observed = this.ranges.length ? this.ranges[this.ranges.length-1].last : since
      this.inbox.seq = Math.max(since,number(answer['seq'],since),observed); this.sequenceFloor = this.inbox.seq; this.ranges = []; this.catchupPending = false
      this.onInbox(this.inbox)
    } catch { /* Feed stays usable; foreground/reconnect retries catch-up. */ }
    finally { if (epoch === this.epoch) this.noticesBusy = false }
  }
  markRead(id: string): void { const notice = this.latest.get(id); if (notice) this.inbox.seen[id] = Math.max(number(this.inbox.seen[id],0),number(notice['seq'],0)); this.unread.delete(id); this.onInbox(this.inbox); this.changed() }
  viewingChat(id: string): void { this.viewing = id; if (id) this.markRead(id) }
  async openChat(id: string, room: boolean): Promise<void> { clearTimeout(this.chatPoll); this.chatEpoch++; this.viewEpoch++; this.chatId = id; this.chatRoom = room; this.chatSession = ''; this.chatItems = []; this.cursor = undefined; this.streamText = ''; this.viewingChat(id); await this.loadChat() }
  closeChat(): void { clearTimeout(this.chatPoll); this.chatEpoch++; this.viewEpoch++; this.chatId = ''; this.chatItems = []; this.streamText = ''; this.viewingChat(''); this.changed() }
  async loadChat(older: boolean = false): Promise<void> {
    if (!this.chatId || !this.entity(this.chatId,this.chatRoom)) return
    clearTimeout(this.chatPoll); const first = !this.chatSession
    const scope = this.scope(this.chatId,this.chatRoom); const epoch = ++this.chatEpoch; const id = this.chatId, room = this.chatRoom
    const payload = dsBotMemoryTarget(id,room); if (older && this.cursor !== undefined && this.cursor !== null) payload['cursor'] = this.cursor
    this.chatLoading = true; this.changed()
    try {
      const value = object(await this.transport.call(room ? 'room-chat' : 'chat',payload))
      if (!this.same(scope) || epoch !== this.chatEpoch || id !== this.chatId) return
      const session = room ? string(value['roomId']) : string(value['sessionId']); if (!session || room && session !== id || !room && session !== scope.session) throw new DshRpcError('bot/stale','Chat changed')
      const items = dsBotItems(value['items']); this.chatSession = session
      this.chatItems = older || first ? dsBotMerge(items,this.chatItems) : dsBotMerge(this.chatItems.filter((item: WireObject) => item['live'] !== true),items)
      if (older || this.cursor === undefined) this.cursor = value['cursor'] ?? null
      this.markRead(id)
      if (room && value['running'] === true) this.chatPoll = setTimeout(() => { if (this.same(scope) && this.chatId === id) void this.loadChat() },1000)
    } catch (error) { if (this.same(scope) && epoch === this.chatEpoch) this.failure = dsBotFailure(error as Error) }
    finally { if (epoch === this.chatEpoch) { this.chatLoading = false; this.changed() } }
  }
  async read(endpoint: string, payload: WireObject, scope: DSBotScope = this.scope()): Promise<Object | null> { this.assert(scope); const value = await this.transport.call(endpoint,payload); this.assert(scope); return value }
  async write(endpoint: string, payload: WireObject, scope: DSBotScope = this.scope()): Promise<Object | null> {
    this.assert(scope,true); const value = await this.transport.call(endpoint,payload,endpoint === 'send' ? 40000 : 20000)
    this.assert(scope,true)
    if (this.current() && scope.epoch === this.epoch && scope.boot === string(this.hello['boot'])) await this.refresh()
    return value
  }
  async send(text: string, scope: DSBotScope): Promise<boolean> { const clean = text.trim(); if (!clean || clean.length > 100000) throw new Error('请输入 1–100000 字的消息'); await this.write('send',{ 'sessionId': scope.id, 'text': clean },scope); if (this.same(scope)) { await this.loadChat(); return true }; return false }
  async continueRoom(scope: DSBotScope, paused: string[]): Promise<void> {
    this.assert(scope,true); const current = dsBotEntries(this.entity(scope.id,true)?.['paused']).map((item: WireObject) => string(item['id']))
    if (!scope.room || !paused.length || JSON.stringify(paused) !== JSON.stringify(current)) throw new DshRpcError('bot/stale','Paused calls changed')
    const key = JSON.stringify([scope.epoch,scope.boot,scope.id,paused]); if (this.continued.has(key)) return
    this.continued.add(key)
    try { await this.write('room-continue',{ 'roomId': scope.id },scope) } catch (error) { this.continued.delete(key); throw error as Error }
  }
  async stop(scope: DSBotScope): Promise<void> { this.assert(scope,true); await this.transport.cancel(scope.session); if (this.same(scope)) await this.refresh() }
  question(id: string): WireObject { const bot = this.entity(id,false); return object(object(this.team['questions'])[dsBotSession(bot || {})] || object(this.team['questions'])[id]) }
  view(id: string): WireObject { const bot = this.entity(id,false); return object(object(this.team['views'])[dsBotSession(bot || {})] || object(this.team['views'])[id]) }
  async answerQuestion(scope: DSBotScope, questionId: string, selected: string[], custom: string, dismiss: boolean = false): Promise<void> {
    this.assert(scope,true); const current = this.question(scope.id); if (current['id'] !== questionId) throw new DshRpcError('bot/stale','Question changed')
    const options = dsBotEntries(current['options']).map((option: WireObject) => string(option['label']))
    if (selected.some((label: string) => !options.includes(label)) || current['multiSelect'] !== true && selected.length > 1 || custom.trim() && current['allowCustom'] !== true) throw new Error('回答选项已更改')
    if (!dismiss && !selected.length && !custom.trim()) throw new Error('请选择或填写回答')
    const answer: WireObject = { 'selected': selected }; if (custom.trim()) answer['custom'] = custom.trim()
    await this.write(dismiss ? 'dismiss-question' : 'answer-question', dismiss ? { 'sessionId': scope.session } : { 'sessionId': scope.session, 'questionId': questionId, 'answer': answer },scope)
  }
  async answerView(scope: DSBotScope, viewId: string, action: string, values: WireObject, dismiss: boolean = false): Promise<void> {
    this.assert(scope,true); if (this.question(scope.id)['id'] || this.view(scope.id)['id'] !== viewId) throw new DshRpcError('bot/stale','View changed')
    await this.write(dismiss ? 'dismiss-view' : 'view-reply', dismiss ? { 'sessionId': scope.session } : { 'sessionId': scope.session, 'viewId': viewId, 'action': action, 'values': values },scope)
  }
  async approval(scope: DSBotScope, id: string, allow: boolean): Promise<void> {
    this.assert(scope,true); const approval = dsBotEntries(object(this.live['work'])['approvals']).find((entry: WireObject) => entry['id'] === id)
    if (!approval || approval['answerable'] !== true || (scope.room ? approval['roomId'] !== scope.id : approval['botId'] !== scope.id || approval['roomId'])) throw new DshRpcError('bot/stale','Approval changed')
    await this.write('approval-answer',{ 'id': id, 'choice': allow ? 'allow' : 'reject' },scope)
  }
  close(): void { this.closed = true; this.epoch++; this.chatEpoch++; this.stopFeed?.(); this.stopFeed = undefined; clearTimeout(this.retry); clearTimeout(this.refreshTimer); clearTimeout(this.chatPoll); this.listeners.clear(); this.onChange = () => {}; this.onNotice = () => {}; this.onInbox = () => {} }
}

export interface DSBotMention { start: number; end: number; query: string }
export function dsBotMention(text: string,start: number,end: number): DSBotMention | undefined {
  if (start !== end || start < 0 || start > text.length) return undefined
  let at = start-1
  while (at >= 0 && text[at] !== '@') { if (/\s/.test(text[at])) return undefined; at-- }
  if (at < 0 || at > 0 && /[A-Za-z0-9_.]/.test(text[at-1])) return undefined
  const query = text.substring(at+1,start); return query.length > 40 ? undefined : { start: at, end: start, query: query }
}
