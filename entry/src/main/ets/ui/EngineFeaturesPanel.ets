import { util } from '@kit.ArkTS'
import { pasteboard } from '@kit.BasicServicesKit'
import { DshClient, DshSubscription } from '../dsh/DshClient'
import { array, DshMessage, DshTranscript, number, object, string, strings, WireObject } from '../dsh/DshWire'
import { DshGlyphs, DshType, ThemeColors, themeColors } from './DshTheme'
import { MessageBody } from './MessageBody'
import { EngineScheduleEditor } from './EngineScheduleEditor'
import { fetchPluginMarket, verifyMarketRelease } from './EnginePluginMarket'
import {
  featureDate, featureError, featureObjects, featureRequest, jobLive, jobStatus, pluginOperationNotice,
  pluginSummary, pluginTitle, scheduleFailure, scheduleName, scheduleRule, scheduleStatus, scheduleTargetSession,
  subagentMode, marketTarget, PluginTarget, teamMessage
} from './EngineFeatureData'

@Component
export struct EngineFeaturesPanel {
  @Prop colors: ThemeColors = themeColors()
  @Prop @Watch('inputChanged') kind: string = 'plugins'
  @Prop @Watch('inputChanged') sessionId: string = ''
  client: DshClient = new DshClient()
  onClose: () => void = () => {}
  onBackHandler?: (handler: (() => boolean) | undefined) => void
  onUseSkill?: (command: string, newSession: boolean) => void
  onOpenSession?: (id: string) => void
  @State private rows: WireObject[] = []
  @State private entries: WireObject[] = []
  @State private inventoryPresets: WireObject[] = []
  @State private market: WireObject[] = []
  @State private marketLoading: boolean = false
  @State private marketError: string = ''
  @State private installSpec: string = ''
  @State private installId: string = ''
  @State private installPhase: string = ''
  @State private installLog: string = ''
  @State private installCanceling: boolean = false
  @State private management: boolean = false
  @State private team: WireObject = {}
  @State private teamMessages: WireObject[] = []
  @State private teamMessagesLoading: boolean = false
  @State private teamMessagesError: string = ''
  @State private section: string = ''
  @State private scheduleEditing: boolean = false
  @State private detailId: string = ''
  @State private detail: WireObject = {}
  @State private loading: boolean = true
  @State private detailLoading: boolean = false
  @State private writing: boolean = false
  @State private error: string = ''
  @State private detailError: string = ''
  @State private notice: string = ''
  @State private query: string = ''
  @State private output: string = ''
  @State private outputTrimmed: boolean = false
  @State private history: WireObject[] = []
  @State private historyNext: string = ''
  @State private historyPruned: boolean = false
  @State private childMessages: DshMessage[] = []
  @State private childRunning: boolean = false
  @State private childPrompt: string = ''
  private listStop?: DshSubscription
  private detailStop?: DshSubscription
  private hostStop?: DshSubscription
  private generation: number = 0
  private detailGeneration: number = 0
  private visible: boolean = false
  private scheduleBack?: () => boolean

  aboutToAppear(): void {
    this.onBackHandler?.(() => this.back())
    this.visible = true
    this.hostStop = this.client.onHostEvent((event: WireObject) => this.pluginEvent(event))
    this.inputChanged()
  }

  aboutToDisappear(): void {
    this.onBackHandler?.(undefined)
    this.visible = false
    this.generation++
    this.detailGeneration++
    this.listStop?.()
    this.detailStop?.()
    this.hostStop?.()
    this.listStop = undefined
    this.detailStop = undefined
    this.hostStop = undefined
  }

  private inputChanged(): void {
    if (!this.visible) return
    this.scheduleEditing = false
    this.closeDetail()
    this.query = ''
    this.section = this.kind === 'plugins' ? 'bundles' : this.kind === 'agents' ? 'children' : 'all'
    this.rows = []
    this.entries = []
    this.inventoryPresets = []
    this.market = []
    this.marketError = ''
    this.marketLoading = false
    this.management = false
    this.team = {}
    this.teamMessages = []
    this.teamMessagesLoading = false
    this.teamMessagesError = ''
    this.notice = ''
    void this.load()
  }

  private title(): string {
    switch (this.kind) {
      case 'plugins': return '插件'
      case 'skills': return '技能'
      case 'jobs': return '后台任务'
      case 'schedules': return '自动化任务'
      case 'agents': return '子代理与团队'
      default: return '引擎功能'
    }
  }

  private subtitle(): string {
    switch (this.kind) {
      case 'skills': return '输入 /技能名 调用'
      case 'jobs': return '引擎重启后清空'
      case 'schedules': return '到点自动发进对话'
      default: return ''
    }
  }

  private glyph(): string {
    switch (this.kind) {
      case 'plugins': return DshGlyphs.plugin
      case 'skills': return DshGlyphs.file
      case 'jobs': return DshGlyphs.terminal
      case 'schedules': return DshGlyphs.latest
      default: return DshGlyphs.model
    }
  }

  private titleOf(row: WireObject): string {
    if (this.kind === 'agents' && this.section === 'messages') {
      return `${string(row['senderName']) || string(row['senderId']) || '团队成员'} → ${string(row['recipientName'])}`
    }
    switch (this.kind) {
      case 'plugins': return pluginTitle(row) || string(row['id'])
      case 'skills': return `/${string(row['name'])}`
      case 'jobs': return string(row['label']) || string(row['id'])
      case 'schedules': return scheduleName(row)
      default: return string(row['label']) || string(row['name']) || string(row['subject']) || string(row['id'])
    }
  }

  private subtitleOf(row: WireObject): string {
    if (this.kind === 'agents' && this.section === 'messages') return string(row['text'])
    switch (this.kind) {
      case 'plugins': {
        const summary = pluginSummary(row) || string(row['moduleName']) || string(row['broken']) || string(row['version'])
        const enabled = typeof row['enabled'] === 'boolean' ? (row['enabled'] === true ? '已启用' : '已停用') : ''
        return [enabled, summary].filter((value: string) => !!value).join(' · ')
      }
      case 'skills': return string(row['description'])
      case 'jobs': return [jobStatus(row), string(row['progress'])].filter((text: string) => !!text).join(' · ')
      case 'schedules': return `${scheduleRule(row)} · ${scheduleStatus(row)}`
      default: {
        if (this.section === 'children') return subagentMode(row['mode'])
        return [string(row['status']) || string(row['phase']),
          string(row['description']) || (row['role'] === 'lead' ? '负责人' : string(row['error']))]
          .filter((value: string) => !!value).join(' · ')
      }
    }
  }

  private idOf(row: WireObject): string {
    if (this.kind === 'plugins') return string(row['entryId']) || string(row['name']) || string(row['id'])
    if (this.kind === 'skills') return string(row['name'])
    return string(row['id'])
  }

  private emptyText(): string {
    if (this.query.trim()) return '没有匹配的项目'
    switch (this.kind) {
      case 'plugins': return '当前主机没有可显示的插件'
      case 'skills': return '这个对话还没有技能'
      case 'jobs': return '没有后台任务'
      case 'schedules': return this.section === 'all' ? '还没有自动化任务' : '没有符合状态的任务'
      case 'agents': return this.section === 'children' ? '这个对话还没有子代理' :
        this.section === 'messages' ? '还没有团队消息' : '这个对话还没有代理团队'
      default: return '没有项目'
    }
  }

  private async load(): Promise<void> {
    const generation = ++this.generation
    this.listStop?.()
    this.listStop = undefined
    this.loading = true
    this.error = ''
    try {
      if (['jobs', 'skills', 'agents'].includes(this.kind) && !this.sessionId) {
        throw new Error('请先打开或创建一个对话')
      }
      if (this.kind === 'jobs') {
        const stop = await this.client.watchJobs(this.sessionId, (items: WireObject[]) => {
          if (generation !== this.generation) return
          this.rows = featureObjects(items, 'id')
          const job = this.rows.find((row: WireObject) => row['id'] === this.detailId)
          if (job) this.detail = job
          this.loading = false
        }, (reason?: string) => {
          if (generation !== this.generation) return
          this.loading = false
          this.error = reason || '主机结束了后台任务订阅'
        })
        if (generation !== this.generation) stop()
        else this.listStop = stop
        return
      }
      if (this.kind === 'plugins') {
        await this.loadPlugins(generation)
      } else if (this.kind === 'skills') {
        const items = await this.client.listSkills(this.sessionId)
        if (generation === this.generation) this.rows = items
      } else if (this.kind === 'schedules') {
        const items = featureObjects(await this.client.scheduleCatalog(), 'id')
        if (generation === this.generation) {
          this.rows = items
          const schedule = items.find((row: WireObject) => row['id'] === this.detailId)
          if (schedule) this.detail = schedule
        }
      } else if (this.kind === 'agents') {
        const args: WireObject = { 'sessionId': this.sessionId }
        const result = await this.client.request('session/projections', featureRequest(args))
        if (generation === this.generation) {
          if (result === null) throw new Error('主机找不到这个对话')
          const projections = object(object(result)['values'])
          if (projections['subagentCatalog'] === undefined && projections['agentTeam'] === undefined) {
            this.notice = '主机没有为这个对话返回子代理或团队数据。'
          }
          this.rows = featureObjects(projections['subagentCatalog'], 'id')
          this.team = object(projections['agentTeam'])
          if (this.section === 'messages') void this.loadTeamMessages()
        }
      }
    } catch (reason) {
      if (generation === this.generation) this.error = featureError(reason, '没能读取当前主机的数据')
    } finally {
      if (generation === this.generation && this.kind !== 'jobs') this.loading = false
      if (generation === this.generation && this.error) this.loading = false
    }
  }

  private async loadPlugins(generation: number): Promise<void> {
    const result = await this.client.pluginInventory()
    if (generation !== this.generation) return
    this.entries = featureObjects(result['entries'], 'entryId')
    this.inventoryPresets = featureObjects(result['agentPresets'], 'id')
    this.management = result['managementAvailable'] === true
    if (!this.management) {
      this.rows = []
      this.section = this.section === 'bundles' ? 'entries' : this.section
      this.notice = '当前主机未启用插件管理。可以查看已加载插件和预设组成。'
      return
    }
    const bundles = await Promise.all([this.client.listPluginBundles(), this.client.listPlugins()])
    if (generation !== this.generation) return
    this.rows = featureObjects(bundles[0], 'name')
    this.entries = featureObjects(bundles[1], 'entryId')
    const detail = this.currentRows().find((row: WireObject) => this.idOf(row) === this.detailId)
    if (detail) this.detail = detail
  }

  private currentRows(): WireObject[] {
    if (this.kind === 'plugins') {
      if (this.section === 'market') return this.market
      if (this.section === 'entries') return this.entries
      if (this.section === 'presets') return this.inventoryPresets
    }
    if (this.kind === 'agents') {
      if (this.section === 'members') return featureObjects(this.team['members'], 'id')
      if (this.section === 'messages') return this.teamMessages
      if (this.section === 'tasks') {
        return featureObjects(this.team['tasks'], 'id').filter((row: WireObject) => row['status'] !== 'deleted')
      }
    }
    return this.rows
  }

  private shownRows(): WireObject[] {
    const query = this.query.trim().toLowerCase()
    return this.currentRows().filter((row: WireObject) => {
      if (this.kind === 'schedules') {
        if (this.section === 'active' && row['status'] !== 'active') return false
        if (this.section === 'ended' && row['status'] === 'active') return false
      }
      return !query || `${this.titleOf(row)} ${this.subtitleOf(row)} ${string(row['prompt'])}`.toLowerCase().includes(query)
    })
  }

  private closeDetail(): void {
    this.detailGeneration++
    this.detailStop?.()
    this.detailStop = undefined
    this.detailId = ''
    this.detail = {}
    this.detailLoading = false
    this.writing = false
    this.detailError = ''
    this.output = ''
    this.outputTrimmed = false
    this.history = []
    this.historyNext = ''
    this.historyPruned = false
    this.childMessages = []
    this.childRunning = false
    this.childPrompt = ''
  }

  private back(): boolean {
    if (this.writing || this.installCanceling) return true
    if (this.scheduleEditing) {
      if (!this.scheduleBack?.()) this.scheduleEditing = false
      return true
    }
    if (!this.detailId) return false
    this.closeDetail()
    return true
  }

  private showDetail(row: WireObject): void {
    this.closeDetail()
    this.detail = row
    this.detailId = this.idOf(row)
    if (this.kind === 'jobs') void this.followJob()
    else if (this.kind === 'schedules') void this.loadHistory()
    else if (this.kind === 'agents' && this.section === 'children' && row['mode'] !== 'external') void this.followChild()
    else if (this.kind === 'agents' && this.section === 'members' && row['role'] !== 'lead') void this.followChild()
  }

  private async followJob(): Promise<void> {
    const generation = this.detailGeneration
    this.detailLoading = true
    this.detailError = ''
    try {
      const stop = await this.client.followJob(this.sessionId, this.detailId, (frame: WireObject) => {
        if (generation !== this.detailGeneration) return
        if (frame['type'] === 'opened' || frame['type'] === 'status') {
          const job = object(frame['job'])
          if (job['id'] === this.detailId) this.detail = job
          this.detailLoading = false
        } else if (frame['type'] === 'output') {
          let text = this.output
          if (frame['lossy'] === true) this.outputTrimmed = true
          for (const value of array(frame['chunks'])) {
            const chunk = object(value)
            if (chunk['gapBefore'] === true) text += '\n[… 主机已裁剪早期输出 …]\n'
            text += string(chunk['text'])
          }
          if (text.length > 160000) this.outputTrimmed = true
          this.output = text.slice(-160000)
        }
      }, (reason?: string) => {
        if (generation !== this.detailGeneration) return
        if (reason || this.detailLoading) this.detailError = reason || '主机没有返回任务详情'
        this.detailLoading = false
      })
      if (generation !== this.detailGeneration) stop()
      else this.detailStop = stop
    } catch (reason) {
      if (generation === this.detailGeneration) {
        this.detailLoading = false
        this.detailError = featureError(reason, '没能读取输出')
      }
    }
  }

  private async loadHistory(before?: string): Promise<void> {
    const generation = this.detailGeneration
    this.detailLoading = true
    this.detailError = ''
    try {
      const target = this.detail['target'] ? undefined : string(this.detail['sessionId']) || undefined
      const history = await this.client.scheduleHistory(this.detailId, target, 20, before)
      if (generation !== this.detailGeneration) return
      scheduleFailure(history)
      const records = array(history['records']).map(object)
      this.history = before ? this.history.concat(records) : records
      this.historyNext = string(history['nextBefore'])
      this.historyPruned = history['earlierRecordsPruned'] === true
    } catch (reason) {
      if (generation === this.detailGeneration) this.detailError = featureError(reason, '没能读取运行记录')
    } finally {
      if (generation === this.detailGeneration) this.detailLoading = false
    }
  }

  private async followChild(): Promise<void> {
    const generation = this.detailGeneration
    this.detailLoading = true
    this.detailError = ''
    const transcript = new DshTranscript(this.detailId)
    const mode = string(this.detail['mode'])
    const address: WireObject = { 'kind': 'subagent', 'parentSessionId': this.sessionId, 'childSessionId': this.detailId,
      'mode': mode === 'one-shot' || mode === 'continuable' ? mode : 'unknown' }
    const args: WireObject = { 'address': address, 'assistantStream': true, 'maxMessages': 100 }
    try {
      const stop = await this.client.openStream('session/follow', featureRequest(args), (frame: WireObject) => {
        if (generation !== this.detailGeneration) return
        transcript.apply(frame)
        this.childMessages = transcript.messages()
        this.childRunning = transcript.running
        if (frame['type'] === 'snapshot') {
          this.detailLoading = false
          const values = object(object(frame['projections'])['values'])
          const resolved = string(object(values['subagent'])['mode'])
          if (resolved === 'continuable' || resolved === 'one-shot') {
            const row: WireObject = { 'mode': resolved }
            for (const key of Object.keys(this.detail)) {
              if (key !== 'mode') row[key] = this.detail[key]
            }
            this.detail = row
          }
        }
      }, (reason?: string) => {
        if (generation !== this.detailGeneration) return
        if (reason || this.detailLoading) this.detailError = reason || '主机没有返回子代理会话'
        this.detailLoading = false
        this.childRunning = false
      })
      if (generation !== this.detailGeneration) stop()
      else this.detailStop = stop
    } catch (reason) {
      if (generation === this.detailGeneration) {
        this.detailLoading = false
        this.detailError = featureError(reason, '没能读取子代理会话')
      }
    }
  }

  private teamSnapshot(member: WireObject, parent: string): Promise<WireObject> {
    const id = string(member['id'])
    const address: WireObject = member['role'] === 'lead' ? { 'kind': 'session', 'sessionId': id } :
      { 'kind': 'subagent', 'parentSessionId': parent, 'childSessionId': id, 'mode': 'unknown' }
    const request: WireObject = { 'address': address, 'assistantStream': false, 'maxMessages': 200 }
    return new Promise<WireObject>((resolve: (snapshot: WireObject) => void, reject: (reason: Error) => void) => {
      let stop: DshSubscription | undefined = undefined
      let done = false
      const timer = setTimeout(() => { done = true; stop?.(); reject(new Error('读取团队消息超时')) }, 15000)
      this.client.openStream('session/follow', featureRequest(request), (frame: WireObject) => {
        if (done || frame['type'] !== 'snapshot') return
        done = true
        clearTimeout(timer)
        stop?.()
        resolve(frame)
      }, (reason?: string) => {
        if (done) return
        done = true
        clearTimeout(timer)
        reject(new Error(reason || '主机没有返回团队会话'))
      }).then((subscription: DshSubscription) => {
        if (done) subscription()
        else stop = subscription
      }).catch(() => {
        if (done) return
        done = true
        clearTimeout(timer)
        reject(new Error('无法订阅团队会话'))
      })
    })
  }

  private async loadTeamMessages(): Promise<void> {
    const generation = this.generation
    this.teamMessagesLoading = true
    this.teamMessagesError = ''
    const members = featureObjects(this.team['members'], 'id')
    const lead = members.find((row: WireObject) => row['role'] === 'lead')
    const parent = lead ? string(lead['id']) : this.sessionId
    const unreadable: string[] = []
    const messages: WireObject[] = []
    await Promise.all(members.map(async (member: WireObject) => {
      const name = string(member['name']) || string(member['id'])
      try {
        const snapshot = await this.teamSnapshot(member, parent)
        for (const record of array(snapshot['records'])) {
          const row = teamMessage(object(object(record)['event']), string(member['id']))
          if (row) {
            row['recipientName'] = name
            const sender = members.find((candidate: WireObject) => candidate['id'] === row['senderId'])
            if (sender && !row['senderName']) row['senderName'] = sender['name']
            messages.push(row)
          }
        }
      } catch { unreadable.push(name) }
    }))
    if (!this.visible || generation !== this.generation) return
    this.teamMessages = messages.sort((a: WireObject, b: WireObject) => number(b['time'], 0) - number(a['time'], 0))
    this.teamMessagesError = unreadable.length ? `没能读取这些成员的消息：${unreadable.join('、')}` : ''
    this.teamMessagesLoading = false
  }

  private async runAction(action: () => Promise<void>): Promise<void> {
    if (this.writing) return
    const generation = this.detailGeneration
    this.writing = true
    this.detailError = ''
    this.notice = ''
    try { await action() }
    catch (reason) {
      if (generation === this.detailGeneration) this.detailError = featureError(reason, '主机未完成操作')
    } finally {
      if (generation === this.detailGeneration) this.writing = false
    }
  }

  private confirm(title: string, message: string, label: string, action: () => Promise<void>): void {
    const generation = this.detailGeneration
    this.getUIContext().showAlertDialog({ title: title, message: message,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: label, action: () => {
        if (generation === this.detailGeneration) void this.runAction(action)
      } }
    })
  }

  private async togglePlugin(id: string, bundle: boolean, enabled: boolean): Promise<void> {
    const generation = this.detailGeneration
    const result = bundle ? await this.client.setBundleEnabled(id, enabled) : await this.client.setPluginEnabled(id, enabled)
    if (generation !== this.detailGeneration) return
    this.notice = pluginOperationNotice(result)
    await this.loadPlugins(this.generation)
  }

  private async loadMarket(): Promise<void> {
    if (this.marketLoading) return
    const kind = this.kind
    this.marketLoading = true
    this.marketError = ''
    try {
      const rows = await fetchPluginMarket()
      if (this.visible && this.kind === kind) this.market = rows
    } catch (reason) {
      if (this.visible && this.kind === kind) this.marketError = featureError(reason, '插件目录没打开')
    } finally {
      if (this.visible && this.kind === kind) this.marketLoading = false
    }
  }

  private pluginEvent(event: WireObject): void {
    if (!this.installId || this.kind !== 'plugins') return
    const payload = object(array(event['args'])[0])
    if (payload['requestId'] !== this.installId) return
    if (event['event'] === 'plugin-manager/install-state') {
      switch (payload['phase']) {
        case 'cancelling': this.installPhase = '正在取消安装'; break
        case 'applying': this.installPhase = '正在应用插件'; break
        case 'installing': this.installPhase = '正在安装插件'; break
      }
    } else if (event['event'] === 'plugin-manager/install-log') {
      this.installLog = (this.installLog + string(payload['text'])).slice(-12000)
    }
  }

  private async inspectPlugin(spec: string, registry: string, target?: PluginTarget): Promise<void> {
    if (!spec) return
    const generation = this.detailGeneration
    const options: WireObject = {}
    if (registry) options['registry'] = registry
    const args: WireObject = { 'spec': spec, 'options': options }
    if (target && this.section === 'market') {
      await verifyMarketRelease(string(this.detail['name']), target, object(this.detail['listing']))
      if (generation !== this.detailGeneration) return
    }
    const result = object(await this.client.request('pluginManager/inspect', args, 60000))
    if (generation !== this.detailGeneration) return
    if (result['status'] !== 'accepted' || result['bundle'] === false) {
      throw new Error(string(result['reason']) || string(result['problem']) || '主机未确认软件包可安装')
    }
    const name = string(result['name']) || spec
    const version = string(result['version'])
    if (target?.version && version && version !== target.version) throw new Error('主机读取到不同的插件版本')
    const resolvedRegistry = string(result['registry']) || registry
    this.confirm('安装插件？', `${name}${version ? ` ${version}` : ''}\n插件会在当前主机运行。`, '安装',
      () => this.installPlugin(spec, resolvedRegistry))
  }

  private async installPlugin(spec: string, registry: string): Promise<void> {
    const generation = this.detailGeneration
    const requestId = util.generateRandomUUID()
    const options: WireObject = { 'requestId': requestId, 'enabled': true, 'saveExact': true }
    if (registry) options['registry'] = registry
    const args: WireObject = { 'spec': spec, 'options': options }
    this.installId = requestId
    this.installPhase = '正在安装插件'
    this.installLog = ''
    try {
      let response: Object | null | undefined
      try { response = await this.client.request('pluginManager/installBundle', args, 1800000) }
      catch (reason) {
        if (generation !== this.detailGeneration) return
        if (reason instanceof Error && !/通信失败|连接已变更|HTTP (502|503|504)/.test(reason.message)) throw reason
        this.installPhase = '正在查询主机安装状态'
        const wait: WireObject = { 'requestId': requestId }
        response = await this.client.request('pluginManager/waitForInstall', wait, 1800000)
        if (response === null || response === undefined) throw new Error('主机未确认安装结果，请刷新已安装列表核对')
      }
      if (generation !== this.detailGeneration) return
      this.notice = pluginOperationNotice(object(response))
      this.installSpec = ''
      await this.loadPlugins(this.generation)
    } finally {
      if (this.installId === requestId) {
        this.installId = ''
        this.installPhase = ''
        this.installCanceling = false
      }
    }
  }

  private async cancelInstall(): Promise<void> {
    if (!this.installId || this.installCanceling) return
    const id = this.installId
    this.installCanceling = true
    try {
      const args: WireObject = { 'requestId': id }
      const result = object(await this.client.request('pluginManager/cancelInstall', args, 300000))
      if (!this.visible || this.installId !== id) return
      if (result['status'] === 'cancelled') this.installPhase = '安装已取消'
      else if (result['status'] === 'too-late') this.installPhase = '主机已开始应用，正在等待结果'
      else this.detailError = '主机未找到进行中的安装'
    } catch (reason) {
      if (this.visible && this.installId === id) this.detailError = featureError(reason, '主机未确认取消安装')
    } finally { if (this.installId === id) this.installCanceling = false }
  }

  private async removeBundle(): Promise<void> {
    const generation = this.detailGeneration
    const args: WireObject = { 'name': this.detailId }
    const result = object(await this.client.request('pluginManager/removeBundle', args, 600000))
    if (generation !== this.detailGeneration) return
    this.notice = pluginOperationNotice(result)
    if (result['changed'] === true) this.closeDetail()
    await this.loadPlugins(this.generation)
  }

  private async runSchedule(): Promise<void> {
    const generation = this.detailGeneration
    const row = this.detail
    const id = this.detailId
    if (row['target']) {
      const result = await this.client.runSchedule(id)
      if (generation !== this.detailGeneration) return
      scheduleFailure(result)
      if (result['id'] !== id || !result['target']) throw new Error('主机未确认任务已运行')
      this.detail = result
    } else {
      const session = scheduleTargetSession(row)
      const prompt = string(row['prompt'])
      if (!session || !prompt.trim()) throw new Error('主机未返回任务的对话或指令')
      await this.client.prompt(session, prompt)
    }
    if (generation !== this.detailGeneration) return
    this.notice = '主机已接受运行请求'
    await this.loadHistory()
  }

  private async deleteSchedule(): Promise<void> {
    const generation = this.detailGeneration
    const row = this.detail
    const id = this.detailId
    const request: WireObject = { 'sessionId': scheduleTargetSession(row), 'id': id }
    const result = row['target'] ? await this.client.editSchedule(id, 'delete', string(row['updatedAt']) || undefined) :
      object(await this.client.request('schedule/delete', featureRequest(request)))
    if (generation !== this.detailGeneration) return
    scheduleFailure(result)
    if (result['deleted'] !== true) throw new Error('主机未确认删除，任务可能已经移除')
    this.closeDetail()
    this.notice = '任务已删除'
    await this.load()
  }

  private async changeScheduleState(active: boolean): Promise<void> {
    const generation = this.detailGeneration
    const id = this.detailId
    const patch: WireObject = { 'active': active }
    const result = await this.client.editSchedule(id, 'update', string(this.detail['updatedAt']) || undefined, patch)
    if (generation !== this.detailGeneration) return
    scheduleFailure(result)
    if (result['id'] !== id || !result['target']) throw new Error('主机未确认任务状态已修改')
    this.detail = result
    await this.load()
  }

  private async sendChild(): Promise<void> {
    const generation = this.detailGeneration
    const text = this.childPrompt.trim()
    if (!text) return
    const content: WireObject = { 'type': 'text', 'text': text }
    const request: WireObject = { 'requestId': util.generateRandomUUID(), 'parentSessionId': this.sessionId,
      'childSessionId': this.detailId, 'mode': 'continuable', 'delivery': 'queue', 'content': [content] }
    await this.client.request('subagents/prompt', featureRequest(request))
    if (generation === this.detailGeneration && this.childPrompt.trim() === text) this.childPrompt = ''
  }

  private async stopChild(): Promise<void> {
    const args: WireObject = { 'childSessionId': this.detailId, 'parentSessionId': this.sessionId, 'mode': 'continuable' }
    await this.client.request('subagents/interruptByParent', args)
  }

  private async copy(value: string): Promise<void> {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value)
    await pasteboard.getSystemPasteboard().setData(data)
    this.notice = '已复制'
  }

  private savedSchedule(task: WireObject): void {
    this.scheduleEditing = false
    this.showDetail(task)
    this.notice = '任务已保存'
    void this.load()
  }

  @Builder
  private iconButton(glyph: string, label: string, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      Text(glyph).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.text)
    }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText(label).onClick(action)
  }

  @Builder
  // Builder observers must read state when they run, not a primitive captured at creation.
  private action(label: () => string, enabled: () => boolean, action: () => void, destructive: boolean = false) {
    Button(label()).fontSize(14).fontColor(destructive ? this.colors.danger : this.colors.primary)
      .backgroundColor(this.colors.surfaceAlt).enabled(!this.writing && enabled()).onClick(action)
  }

  @Builder
  private tab(key: string, label: () => string) {
    Button(label()).fontSize(13).type(ButtonType.Capsule).padding({ left: 9, right: 9 }).height(36)
      .backgroundColor(this.section === key ? this.colors.primaryContainer : this.colors.surface)
      .fontColor(this.section === key ? this.colors.onPrimaryContainer : this.colors.muted).layoutWeight(1)
      .enabled(!this.writing).onClick(() => {
        this.section = key; this.query = ''; this.detailError = ''
        if (key === 'market' && this.market.length === 0) void this.loadMarket()
        if (key === 'messages' && !this.teamMessagesLoading) void this.loadTeamMessages()
      })
  }

  @Builder
  private labelValue(label: string, value: () => string) {
    if (value()) {
      Column({ space: 4 }) {
        Text(label).fontColor(this.colors.muted).fontSize(13).width('100%')
        Text(value()).fontColor(this.colors.text).fontSize(15).width('100%').copyOption(CopyOptions.LocalDevice)
      }.width('100%')
    }
  }

  @Builder
  private listRow(row: WireObject) {
    Row({ space: 12 }) {
      Text(this.glyph()).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.primary)
      Column({ space: 5 }) {
        Text(this.titleOf(row)).fontSize(16).fontColor(this.colors.text).width('100%').maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitleOf(row)) {
          Text(this.subtitleOf(row)).fontSize(13).fontColor(this.colors.muted).width('100%').maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(DshGlyphs.disclosure).fontFamily(DshGlyphs.family).fontSize(16).fontColor(this.colors.hint)
    }.width('100%').padding(16).backgroundColor(this.colors.surface).borderRadius(14)
      .onClick(() => {
        const id = this.idOf(row)
        const current = this.currentRows().find((candidate: WireObject) => this.idOf(candidate) === id)
        if (current) this.showDetail(current)
      })
  }

  @Builder
  private rowList() {
    if (this.kind === 'plugins') {
      Row({ space: 6 }) {
        if (this.management) this.tab('bundles', () => '已安装')
        this.tab('market', () => '插件市场')
        this.tab('entries', () => '插件条目')
        this.tab('presets', () => '预设组成')
      }.width('100%')
      if (this.section === 'market') {
        if (this.marketError) {
          Text(this.marketError).fontSize(13).fontColor(this.colors.danger).width('100%')
          this.action(() => '重试', () => true, () => { void this.loadMarket() })
        }
        if (this.marketLoading) LoadingProgress().width(28).height(28).color(this.colors.primary)
      } else if (this.section === 'bundles' && this.management) {
        Row({ space: 8 }) {
          TextInput({ text: this.installSpec, placeholder: '插件包名或安装地址' }).layoutWeight(1).height(42)
            .fontColor(this.colors.text).backgroundColor(this.colors.surface).enabled(!this.writing)
            .onChange((value: string) => { this.installSpec = value })
          this.action(() => '添加', () => !!this.installSpec.trim(), () => {
            void this.runAction(() => this.inspectPlugin(this.installSpec.trim(), ''))
          })
        }.width('100%')
      }
    } else if (this.kind === 'schedules') {
      Row({ space: 6 }) {
        this.tab('all', () => `全部 ${this.rows.length}`)
        this.tab('active', () => `已开启 ${this.activeCount()}`)
        this.tab('ended', () => `未运行 ${this.rows.length - this.activeCount()}`)
      }.width('100%')
    } else if (this.kind === 'agents') {
      Row({ space: 6 }) {
        this.tab('children', () => '子代理')
        this.tab('members', () => '团队成员')
        this.tab('tasks', () => '团队任务')
        this.tab('messages', () => '团队消息')
      }.width('100%')
      if (string(this.team['failure']) && this.section !== 'children') {
        Text(string(this.team['failure'])).fontSize(13).fontColor(this.colors.danger).width('100%')
      }
      if (this.section === 'messages') {
        if (this.teamMessagesLoading) LoadingProgress().width(28).height(28).color(this.colors.primary)
        if (this.teamMessagesError) Text(this.teamMessagesError).fontSize(13).fontColor(this.colors.danger).width('100%')
      }
    }
    if (this.kind !== 'jobs' && this.currentRows().length > 0) {
      TextInput({ text: this.query, placeholder: this.kind === 'schedules' ? '搜索任务' : '搜索' })
        .height(44).fontColor(this.colors.text).backgroundColor(this.colors.surface)
        .onChange((value: string) => { this.query = value })
    }
    if (this.loading) {
      LoadingProgress().width(32).height(32).color(this.colors.primary)
    } else if (this.shownRows().length === 0 && !this.error &&
      !(this.kind === 'plugins' && this.section === 'market' && (this.marketLoading || this.marketError)) &&
      !(this.kind === 'agents' && this.section === 'messages' && (this.teamMessagesLoading || this.teamMessagesError))) {
      Column({ space: 8 }) {
        Text(this.glyph()).fontFamily(DshGlyphs.family).fontSize(32).fontColor(this.colors.hint)
        Text(this.emptyText()).fontSize(16).fontColor(this.colors.text).textAlign(TextAlign.Center)
        if (this.kind === 'jobs') {
          Text('开发服务器这类命令会在这里').fontSize(13).fontColor(this.colors.muted).textAlign(TextAlign.Center)
        } else if (this.kind === 'skills') {
          Text('放进 .dsh/skills 的技能会出现在这里').fontSize(13).fontColor(this.colors.muted)
        }
      }.padding(24).width('100%')
    }
    if (this.kind === 'jobs') {
      if (this.liveJobs(true).length > 0) {
        Text('进行中').fontSize(13).fontColor(this.colors.muted).width('100%').padding(4)
        ForEach(this.liveJobs(true), (row: WireObject) => { this.listRow(row) },
          (row: WireObject) => this.rowKey(row))
      }
      if (this.liveJobs(false).length > 0) {
        Text(`已结束 · ${this.liveJobs(false).length}`).fontSize(13).fontColor(this.colors.muted).width('100%').padding(4)
        ForEach(this.liveJobs(false), (row: WireObject) => { this.listRow(row) },
          (row: WireObject) => this.rowKey(row))
      }
    } else {
      ForEach(this.shownRows(), (row: WireObject) => { this.listRow(row) },
        (row: WireObject) => this.rowKey(row))
    }
  }

  private rowKey(row: WireObject): string {
    return `${this.kind}|${this.section}|${this.idOf(row)}|${this.titleOf(row)}|${this.subtitleOf(row)}`
  }

  private activeCount(): number {
    return this.rows.filter((row: WireObject) => row['status'] === 'active').length
  }

  private liveJobs(live: boolean): WireObject[] {
    return this.rows.filter((row: WireObject) => jobLive(row) === live)
  }

  @Builder
  private pluginDetail() {
    this.labelValue('简介', () => pluginSummary(this.detail))
    this.labelValue('插件', () => string(this.detail['moduleName']) || string(this.detail['name']))
    this.labelValue('版本', () => string(this.detail['version']))
    this.labelValue('来源', () => string(this.detail['source']))
    this.labelValue('加载状态', () => string(this.detail['fiberPhase']))
    this.labelValue('只读原因', () => string(this.detail['readOnlyReason']))
    this.labelValue('配置诊断', () => string(object(this.detail['meta'])['error']) || string(this.detail['broken']))
    this.labelValue('插件错误', () => string(object(this.detail['error'])['code']))
    this.labelValue('诊断信息', () => string(object(this.detail['error'])['diagnostic']))
    this.labelValue('覆盖项', () => strings(this.detail['overrides']).join('\n'))
    if (this.section === 'market') {
      this.marketDetail()
    }
    if (this.section === 'presets' && this.detail['isDefault'] === true) {
      Text('默认预设').fontColor(this.colors.primary).fontSize(13).width('100%')
    }
    if (this.section !== 'presets' && this.section !== 'market' && typeof this.detail['enabled'] === 'boolean') {
      Row({ space: 10 }) {
        Text(this.detail['enabled'] === true ? '已启用' : '已停用').fontSize(14).fontColor(this.colors.muted)
        if (this.management && !this.detail['readOnlyReason'] && this.detail['availability'] !== 'missing') {
          this.action(() => this.detail['enabled'] === true ? '停用' : '启用', () => true, () => {
            void this.runAction(() => this.togglePlugin(this.detailId, this.section === 'bundles', this.detail['enabled'] !== true))
          })
        }
      }.width('100%')
    }
    if (this.section === 'bundles' && this.management && this.detail['removable'] === true && !this.detail['readOnlyReason']) {
      this.action(() => '卸载插件', () => true, () => {
        this.confirm('卸载插件？', this.titleOf(this.detail), '卸载', () => this.removeBundle())
      }, true)
    }
    if (this.section === 'bundles' && this.management && string(object(this.detail['installTarget'])['spec'])) {
      this.action(() => '获取', () => true, () => {
        void this.runAction(() => this.inspectPlugin(string(object(this.detail['installTarget'])['spec']), ''))
      })
    }
    ForEach(array(this.detail['rows']).map(object), (row: WireObject) => {
      Column({ space: 8 }) {
        Text(pluginTitle(row)).fontSize(15).fontColor(this.colors.text).width('100%')
        if (pluginSummary(row)) {
          Text(pluginSummary(row)).fontSize(13).fontColor(this.colors.muted).width('100%')
        }
        if (row['enabled'] === 'conditional') this.labelValue('条件启用', () => string(row['condition']))
        else if (typeof row['enabled'] === 'boolean') {
          Text(row['enabled'] === true ? '已启用' : '已停用').fontColor(this.colors.muted).fontSize(13).width('100%')
        }
      }.padding(12).width('100%').borderRadius(12).backgroundColor(this.colors.surfaceAlt)
    }, (row: WireObject, index: number) => `${this.detailId}|${index}|${JSON.stringify(row)}`)
  }

  @Builder
  private marketDetail() {
    this.labelValue('作者', () => string(this.detail['author']))
    this.labelValue('软件包', () => string(this.detail['name']))
    this.labelValue('主页', () => string(this.detail['homepage']))
    this.labelValue('仓库', () => string(object(this.detail['repository'])['url']))
    this.labelValue('上架类型', () => string(object(this.detail['listing'])['tier']))
    this.labelValue('风险提示', () => strings(object(object(this.detail['listing'])['risk'])['flags']).join('、'))
    this.labelValue('需要的 DSH 版本', () => string(object(object(this.detail['release'])['engines'])['dsh']))
    if (this.marketInstalled()) {
      Text('已安装').fontSize(14).fontColor(this.colors.muted).width('100%')
    } else if (this.management && !strings(object(this.detail['listing'])['blockedVersions']).includes(string(this.detail['version']))) {
      this.action(() => '获取', () => true, () => { void this.runAction(() => this.inspectMarketPlugin()) })
    } else if (this.management) {
      Text('官方目录已屏蔽这个版本。').fontSize(14).fontColor(this.colors.danger).width('100%')
    }
  }

  private marketInstalled(): boolean {
    return this.rows.some((row: WireObject) => row['name'] === this.detail['name'] && row['installed'] === true)
  }

  private async inspectMarketPlugin(): Promise<void> {
    const target = marketTarget(this.detailId, object(this.detail['release']))
    if (!target) throw new Error('目录没有提供有效的安装来源')
    await this.inspectPlugin(target.spec, target.registry, target)
  }

  @Builder
  private skillDetail() {
    this.labelValue('说明', () => string(this.detail['description']))
    this.labelValue('适用', () => string(this.detail['whenToUse']))
    this.labelValue('来源', () => string(this.detail['path']))
    if (this.detail['modelInvocable'] === false) {
      Text('仅可通过 /命令 调用').fontSize(13).fontColor(this.colors.muted).width('100%')
    }
    Row({ space: 8 }) {
      if (this.onUseSkill) {
        this.action(() => '在对话里用', () => true, () => this.onUseSkill?.(`/${this.detailId} `, false))
        this.action(() => '新对话里用', () => true, () => this.onUseSkill?.(`/${this.detailId} `, true))
      } else {
        this.action(() => '复制命令', () => true, () => { void this.runAction(() => this.copy(`/${this.detailId}`)) })
      }
    }.width('100%')
  }

  @Builder
  private jobDetail() {
    this.labelValue('状态', () => jobStatus(this.detail))
    this.labelValue('任务信息', () => string(this.detail['detail']))
    this.labelValue('开始时间', () => featureDate(this.detail['startedAt']))
    this.labelValue('结束时间', () => featureDate(this.detail['finishedAt']))
    Row({ space: 8 }) {
      if (this.detail['status'] === 'running') {
        this.action(() => '停止', () => true, () => {
          this.confirm('停止这个任务？', this.titleOf(this.detail), '停止', async () => {
            const generation = this.detailGeneration
            const requested = await this.client.killJob(this.sessionId, this.detailId)
            if (generation !== this.detailGeneration) return
            if (!requested) throw new Error('任务已经结束了')
            this.notice = '主机已接受停止请求'
          })
        }, true)
      }
      if (this.output) this.action(() => '复制输出', () => true, () => { void this.runAction(() => this.copy(this.output)) })
    }.width('100%')
    Text('任务输出').fontSize(15).fontColor(this.colors.text).width('100%')
    if (this.outputTrimmed) Text('显示保留的最近输出').fontSize(12).fontColor(this.colors.muted).width('100%')
    Text(this.output || (this.detailLoading || jobLive(this.detail) ? '等待输出…' : '没有输出'))
      .fontFamily(DshType.monoFamily).fontSize(13).lineHeight(20).width('100%').padding(12)
      .fontColor(this.colors.text).backgroundColor(this.colors.codeSurface).borderRadius(12).copyOption(CopyOptions.LocalDevice)
  }

  @Builder
  private scheduleDetail() {
    this.labelValue('规则', () => `${scheduleRule(this.detail)} · ${scheduleStatus(this.detail)}`)
    this.labelValue('指令', () => string(this.detail['prompt']))
    this.labelValue('下次运行', () => this.detail['status'] === 'active' ? featureDate(this.detail['scheduledAt']) : '')
    this.labelValue('上次运行', () => featureDate(object(this.detail['lastDelivery'])['deliveredAt']))
    this.labelValue('关联对话', () => scheduleTargetSession(this.detail))
    if (object(this.detail['target'])['kind'] === 'new_once') this.labelValue('在哪里运行', () => '第一次新建对话，之后沿用')
    if (object(this.detail['target'])['kind'] === 'new') this.labelValue('在哪里运行', () => '每次新建对话')
    Row({ space: 8 }) {
      this.action(() => '立即运行', () => true, () => {
        this.confirm('立即运行这个任务？', '主机会按此任务的指令与目的地立即运行。', '立即运行', () => this.runSchedule())
      })
      this.action(() => '删除任务', () => true, () => {
        this.confirm('删除这个任务？', '会停止之后的运行，并删掉它的运行记录。原来的对话不受影响。', '删除', () => this.deleteSchedule())
      }, true)
    }.width('100%')
    if (this.detail['target'] && (this.detail['status'] === 'active' || this.detail['status'] === 'paused')) {
      this.action(() => this.detail['status'] === 'active' ? '暂停' : '恢复', () => true, () => {
        void this.runAction(() => this.changeScheduleState(this.detail['status'] === 'paused'))
      })
    }
    this.action(() => '编辑任务', () => true, () => { this.scheduleEditing = true })
    if (this.onOpenSession && scheduleTargetSession(this.detail)) {
      this.action(() => '去对话里看看', () => true, () => this.onOpenSession?.(scheduleTargetSession(this.detail)))
    }
    Text('运行记录').fontSize(16).fontColor(this.colors.text).width('100%')
    if (this.history.length === 0 && !this.detailLoading && !this.detailError) {
      Text('还没有运行过').fontSize(13).fontColor(this.colors.muted).width('100%')
    }
    ForEach(this.history, (record: WireObject) => {
      Column({ space: 6 }) {
        this.labelValue('送达时间', () => featureDate(record['deliveredAt']) || featureDate(record['scheduledAt']))
        if (string(record['prompt'])) Text(string(record['prompt'])).fontSize(14).fontColor(this.colors.text).width('100%')
        if (this.onOpenSession && string(record['targetSessionId'])) {
          this.action(() => '去对话里看看', () => true, () => this.onOpenSession?.(string(record['targetSessionId'])))
        }
      }.width('100%').backgroundColor(this.colors.surfaceAlt).borderRadius(12).padding(12)
    }, (record: WireObject, index: number) => `${index}|${JSON.stringify(record)}`)
    if (this.historyNext) this.action(() => '加载更早的记录', () => !this.detailLoading, () => { void this.loadHistory(this.historyNext) })
    if (this.historyPruned) Text('主机已按保留策略清理更早记录。').fontSize(12).fontColor(this.colors.muted).width('100%')
  }

  @Builder
  private agentDetail() {
    if (this.section === 'members') {
      this.labelValue('身份', () => this.detail['role'] === 'lead' ? '负责人' : '成员')
      this.labelValue('状态', () => string(this.detail['phase']))
      this.labelValue('错误', () => string(this.detail['error']))
      this.labelValue('会话 ID', () => this.detailId)
      if (this.detail['role'] === 'lead') {
        if (this.onOpenSession) this.action(() => '打开对话', () => true, () => this.onOpenSession?.(this.detailId))
      } else this.childTranscript()
    } else if (this.section === 'tasks') {
      this.labelValue('说明', () => string(this.detail['description']))
      this.labelValue('状态', () => string(this.detail['status']))
      this.labelValue('负责人', () => string(this.detail['ownerName']))
      this.labelValue('前置任务', () => strings(this.detail['blockedBy']).join('、'))
      this.labelValue('写入范围', () => strings(this.detail['writeScopes']).join('\n'))
      this.labelValue('写入范围警告', () => strings(this.detail['writeScopeWarnings']).join('\n'))
    } else if (this.section === 'messages') {
      this.labelValue('时间', () => featureDate(this.detail['time']))
      MessageBody({ text: string(this.detail['text']), colors: this.colors })
    } else {
      this.labelValue('模式', () => subagentMode(this.detail['mode']))
      this.labelValue('创建时间', () => featureDate(this.detail['createdAt']))
      this.labelValue('上级对话', () => this.sessionId)
      if (this.detail['mode'] === 'external') {
        Text('外部任务没有可打开的会话记录。').fontSize(13).fontColor(this.colors.muted).width('100%')
      } else this.childTranscript()
    }
  }

  @Builder
  private childTranscript() {
    if (this.childMessages.length === 0 && !this.detailLoading && !this.detailError) {
      Text('暂无会话消息').fontSize(13).fontColor(this.colors.muted).width('100%')
    }
    ForEach(this.childMessages, (message: DshMessage) => {
      Column({ space: 8 }) {
        Text(message.role === 'user' ? '用户' : '子代理').fontSize(13).fontColor(this.colors.muted).width('100%')
        MessageBody({ text: message.text, colors: this.colors })
      }.padding(12).width('100%').borderRadius(12).backgroundColor(this.colors.surfaceAlt)
    }, (message: DshMessage) => JSON.stringify([message.id, message.role, message.text]))
    if (this.detail['mode'] === 'continuable') {
      TextArea({ text: this.childPrompt, placeholder: '给子代理发消息' }).height(84)
        .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
        .onChange((text: string) => { this.childPrompt = text })
      Row({ space: 8 }) {
        this.action(() => '发送', () => !!this.childPrompt.trim() && !this.detailLoading, () => { void this.runAction(() => this.sendChild()) })
        if (this.childRunning) this.action(() => '停止', () => true, () => { void this.runAction(() => this.stopChild()) }, true)
      }.width('100%')
    }
  }

  @Builder
  private details() {
    Column({ space: 14 }) {
      if (this.kind === 'plugins') this.pluginDetail()
      else if (this.kind === 'skills') this.skillDetail()
      else if (this.kind === 'jobs') this.jobDetail()
      else if (this.kind === 'schedules') this.scheduleDetail()
      else if (this.kind === 'agents') this.agentDetail()
      if (this.detailLoading || this.writing) LoadingProgress().width(28).height(28).color(this.colors.primary)
      if (this.detailError) Text(this.detailError).fontColor(this.colors.danger).fontSize(14).width('100%')
    }.alignItems(HorizontalAlign.Start).padding(16).borderRadius(14).backgroundColor(this.colors.surface).width('100%')
  }

  @Builder
  private featurePage() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        this.iconButton(DshGlyphs.back, '返回', () => {
          if (!this.back()) this.onClose()
        })
        Text(this.detailId ? (this.kind === 'jobs' ? '任务输出' : this.titleOf(this.detail)) : this.title())
          .fontSize(22).fontWeight(FontWeight.Medium).fontColor(this.colors.text).layoutWeight(1).maxLines(2)
        if (!this.detailId) this.iconButton(DshGlyphs.refresh, '刷新', () => {
          if (this.writing) return
          if (this.kind === 'plugins' && this.section === 'market') void this.loadMarket()
          else void this.load()
        })
        if (this.kind === 'schedules' && !this.detailId) this.iconButton(DshGlyphs.add, '新建任务', () => { this.scheduleEditing = true })
      }.width('100%')
      if (this.notice) Text(this.notice).fontSize(13).fontColor(this.colors.muted).width('100%')
      if (this.error) Text(this.error).fontSize(14).fontColor(this.colors.danger).width('100%')
      if (this.installId) {
        Row({ space: 8 }) {
          Text(this.installPhase).fontSize(14).fontColor(this.colors.muted).layoutWeight(1)
          Button('取消安装').fontColor(this.colors.danger).backgroundColor(this.colors.surfaceAlt)
            .enabled(!this.installCanceling).onClick(() => { void this.cancelInstall() })
        }.width('100%')
        if (this.installLog) {
          Text(this.installLog).fontFamily(DshType.monoFamily).fontSize(12).fontColor(this.colors.muted)
            .maxLines(6).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').copyOption(CopyOptions.LocalDevice)
        }
      }
      if (!this.detailId && this.detailError) Text(this.detailError).fontSize(14).fontColor(this.colors.danger).width('100%')
      if (!this.detailId && this.subtitle()) Text(this.subtitle()).fontSize(14).fontColor(this.colors.muted).width('100%')
      Scroll() {
        Column({ space: 10 }) {
          if (this.detailId) this.details()
          else this.rowList()
        }.alignItems(HorizontalAlign.Start).width('100%')
      }.layoutWeight(1).width('100%').align(Alignment.TopStart)
    }.width('100%').height('100%').padding(16).backgroundColor(this.colors.background)
  }

  build() {
    if (this.scheduleEditing) {
      EngineScheduleEditor({ colors: this.colors, client: this.client, sessionId: this.sessionId, task: this.detail,
        onBackHandler: (handler: (() => boolean) | undefined) => { this.scheduleBack = handler },
        onClose: () => { this.scheduleEditing = false }, onSaved: (task: WireObject) => this.savedSchedule(task) })
    } else this.featurePage()
  }
}
