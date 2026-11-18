import { PluginSeatsPanel } from './PluginSeatsPanel'
import { WebModePanel } from './WebModePanel'
import { cordisShown, cordisStatus } from './PluginSeatData'
import { TransportControl } from '../remote/TransportEndpoint'
import { nativePluginLocale } from './NativePluginLocale'
import { localizedSettingsText } from './SettingsLocale'
import { DshClient, DshSubscription } from '../dsh/DshClient'
import { array, object, string, WireObject } from '../dsh/DshWire'
import { pluginCaps, pluginReplyEffects, pluginMerge, pluginPlaces, PluginPlace, PluginEffect } from './NativePluginData'
import { NativePluginConnection } from './NativePluginConnection'
import { NativePluginView } from './NativePluginView'
import { PluginConfigPanel } from './PluginConfigPanel'
import { localizedPluginText } from './EngineFeatureData'
import { ThemeColors, themeColors } from './DshTheme'

@Component
export struct NativePluginsPanel {
  @StorageProp('dshLanguage') @Watch('languageChanged') language: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.language) }
  @Prop colors: ThemeColors = themeColors()
  @Prop @Watch('scopeChanged') sessionId: string = ''
  @Prop initialPlace: PluginPlace | undefined = undefined
  @Prop initialSection: string = 'panels'
  getControl: () => Promise<TransportControl> = async () => { throw new Error('本机连接服务不可用') }
  onOpenNamespace: (id: string) => void = () => {}
  onOpenSession: (id: string) => void = () => {}
  onBackHandler?: (handler: (() => boolean) | undefined) => void
  private seatsBack?: () => boolean
  @State private webTarget: WireObject | undefined = undefined
  client: DshClient = new DshClient()
  onClose: () => void = () => {}
  onEffect?: (effect: PluginEffect) => void
  onOpenWeb?: () => void
  @State private section: string = 'panels'
  @State private places: PluginPlace[] = []
  @State private configs: WireObject[] = []
  @State private cordis: WireObject[] = []
  @State private selected: PluginPlace | undefined = undefined
  @State private view: WireObject = {}
  @State private data: WireObject = {}
  @State private configId: string = ''
  @State private error: string = ''
  @State private busy: boolean = false
  private reloadLanguage: boolean = false
  private languageChanged(): void {
    if (this.busy) { this.reloadLanguage = true; return }
    this.reloadLanguage = false
    if (this.selected) void this.open(this.selected); else void this.load()
  }
  private settled(generation: number): void { if (this.current(generation)) { this.busy = false; if (this.reloadLanguage) this.languageChanged() } }
  private generation: number = 0
  private identity: number = 0
  private stream?: NativePluginConnection
  private stop?: DshSubscription
  aboutToAppear(): void {
    this.section = ['panels', 'configs', 'cordis', 'seats'].includes(this.initialSection) ? this.initialSection : 'panels'
    this.onBackHandler?.(() => this.back())
    this.identity = this.client.connectionIdentity()
    this.stop = this.client.onHostEvent((event: WireObject) => {
      if (['cordis/dynamic-package', 'cordis/dynamic-retract', 'cordis/request-run', 'cordis/request-run-resolved'].includes(string(event['event'])) && this.section === 'cordis') void this.load()
    })
    if (this.initialPlace) void this.open(this.initialPlace); else void this.load()
  }
  aboutToDisappear(): void { this.onBackHandler?.(undefined); this.generation++; this.stop?.(); this.stream?.close() }
  private current(generation: number): boolean { return generation === this.generation && this.identity === this.client.connectionIdentity() }
  private scopeChanged(): void { this.stream?.close(); if (this.selected) void this.open(this.selected); else void this.load() }
  private scope(): WireObject { const scope: WireObject = {}; if (this.sessionId) scope['sessionId'] = this.sessionId; return scope }
  private async load(): Promise<void> {
    const generation = ++this.generation; this.busy = true; this.error = ''; this.stream?.close(); this.stream = undefined
    try {
      if (this.section === 'panels') {
        const value = await this.client.bridgeJson('GET', '/dsh-go/v1/contributions', pluginCaps(nativePluginLocale(this.language)))
        if (!this.current(generation)) return
        if (value === null) throw new Error('此主机尚未安装原生插件桥接')
        this.places = pluginPlaces(value).filter((place: PluginPlace) => place.surface === 'panel')
      } else if (this.section === 'configs') {
        const value = await this.client.bridgeJson('GET', '/dsh-go/v1/plugin-config')
        if (!this.current(generation)) return
        if (value === null) throw new Error('此主机尚未提供插件专用配置')
        this.configs = array(Array.isArray(value) ? value : object(value)['entries']).map(object)
      } else if (this.section === 'cordis') {
        const value = await this.client.request('dynamicCordisRunner/inventory')
        if (!this.current(generation)) return
        this.cordis = array(value).map(object).filter((row: WireObject) => !!string(row['pluginId']) && !!string(row['agentId']))
      }
    } catch (reason) { if (this.current(generation)) this.error = reason instanceof Error ? reason.message : '插件界面读取失败' }
    finally { this.settled(generation) }
  }
  private async open(place: PluginPlace): Promise<void> {
    const generation = ++this.generation; this.selected = place; this.busy = true; this.error = ''; this.view = {}; this.data = {}; this.stream?.close()
    try {
      const query = pluginCaps(nativePluginLocale(this.language)); for (const key of Object.keys(this.scope())) query[key] = this.scope()[key]
      const value = object(await this.client.bridgeJson('GET', '/dsh-go/v1/views/' + place.pkg.split('/').map(encodeURIComponent).join('/') + '/' + encodeURIComponent(place.id), query))
      if (!this.current(generation)) return
      if ((value['pkg'] !== undefined && value['pkg'] !== place.pkg) || (value['id'] !== undefined && value['id'] !== place.id)) throw new Error('插件面板响应不匹配')
      this.view = object(value['view']); this.data = object(value['data'])
      const stream = new NativePluginConnection(this.client, nativePluginLocale(this.language)); this.stream = stream
      stream.onData = (data: WireObject) => { if (this.current(generation)) this.data = data }
      stream.onError = (message: string) => { if (this.current(generation)) this.error = message }
      stream.onChanged = () => { if (this.current(generation) && this.selected) void this.open(this.selected) }
      if (place.live || value['live'] === true) await stream.subscribe(place, this.scope(), this.data, string(value['rev']))
    } catch (reason) { if (this.current(generation)) this.error = reason instanceof Error ? reason.message : '插件面板读取失败' }
    finally { this.settled(generation) }
  }
  private async invoke(action: WireObject): Promise<boolean> {
    const place = this.selected; const stream = this.stream; if (!place || !stream || this.busy) return false
    const generation = this.generation; const gesture = action['gesture'] === false ? 0 : typeof action['gestureAt'] === 'number' ? Number(action['gestureAt']) : Date.now(); this.busy = true; this.error = ''
    try {
      const conn = await stream.open(); if (!this.current(generation)) return false
      const body: WireObject = { 'v': 1, 'pkg': place.pkg, 'id': place.id, 'surface': 'panel', 'action': action['id'],
        'value': action['args'], 'scope': this.scope(), 'locale': nativePluginLocale(this.language), 'stream': conn, 'userGesture': action['gesture'] !== false }
      const acknowledgment = object(await this.client.bridgeJson('POST', '/dsh-go/v1/invoke', {}, body)); const arrived = Date.now()
      const value = await stream.result(acknowledgment)
      if (!this.current(generation)) return false
      for (const effect of pluginReplyEffects(value['effects'], gesture, arrived, !!acknowledgment['pending'])) {
        if (effect.type === 'patch' && (!effect.id || effect.id === place.id)) this.data = pluginMerge(this.data, effect.data)
        else if (effect.type === 'refresh' && (!effect.id || effect.id === place.id)) void this.open(place)
        else if (effect.type === 'open' && effect.id.startsWith('panel:')) {
          const target = this.places.find((item: PluginPlace) => item.pkg === place.pkg && item.id === effect.id.slice(6)); if (target) void this.open(target)
        } else this.onEffect?.(effect)
      }
      return true
    } catch (reason) { if (this.current(generation)) this.error = reason instanceof Error ? reason.message : '插件操作未能确认'; return false }
    finally { this.settled(generation) }
  }
  private cordisTitle(row: WireObject): string { return string(cordisShown(row)['name']) || string(row['pluginId']) }
  private cordisTarget(): WireObject { return { 'session': this.sessionId, 'panel': 'cordis' } }
  private back(): boolean {
    if (this.webTarget) { this.webTarget = undefined; return true }
    if (this.configId) { this.configId = ''; return true }
    if (this.section === 'seats' && this.seatsBack?.()) return true
    if (this.selected && this.busy) { this.stream?.cancelPending(); return true }
    if (this.selected && !this.initialPlace) { this.selected = undefined; void this.load(); return true }
    return false
  }
  private cordisAction(row: WireObject, remove: boolean): void {
    const generation = this.generation; const identity = this.client.connectionIdentity()
    this.getUIContext().showAlertDialog({ title: remove ? '移除动态插件？' : '停止动态插件？', message: this.cordisTitle(row),
      primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: remove ? '移除' : '停止', action: () => {
        if (!this.current(generation) || identity !== this.client.connectionIdentity()) return
        void this.mutateCordis(row, remove)
      } } })
  }
  private async mutateCordis(row: WireObject, remove: boolean): Promise<void> {
    const generation = this.generation; this.busy = true; this.error = ''
    try {
      const args: WireObject = { 'agentId': row['agentId'], 'pluginId': row['pluginId'] }
      const result = object(await this.client.request('dynamicCordisRunner/' + (remove ? 'undefineFromPanel' : 'stopFromPanel'), args))
      if (!this.current(generation)) return
      if (result['ok'] !== true && !(!remove && result['reason'] === 'not-running')) throw new Error('主机没有找到这个动态插件')
      await this.load()
    } catch (reason) { if (this.current(generation)) this.error = reason instanceof Error ? reason.message : '操作未能确认' }
    finally { this.settled(generation) }
  }
  build() {
    if (this.webTarget) Column() { Button(this.t('返回')).onClick(() => { this.webTarget = undefined }); WebModePanel({ colors: this.colors, client: this.client, getControl: this.getControl, initialTarget: this.webTarget, onOpenSession: this.onOpenSession }).layoutWeight(1) }.width('100%').height('100%')
    else if (this.configId) PluginConfigPanel({ colors: this.colors, client: this.client, entryId: this.configId, onClose: () => { this.configId = '' } })
    else Column({ space: 12 }) {
      Row() {
        Button(this.t('返回')).onClick(() => { if (!this.back()) this.onClose() })
        Text(this.selected?.title || '插件界面').fontSize(20).fontColor(this.colors.text).layoutWeight(1)
        Button(this.t('刷新')).enabled(!this.busy).onClick(() => { if (this.selected) void this.open(this.selected); else void this.load() })
      }.width('100%')
      if (!this.selected) Row({ space: 6 }) {
        ForEach(['panels', 'configs', 'cordis', 'seats'], (section: string, index: number) => {
          Button(['面板', '配置', 'Cordis', '席位'][index]).fontSize(12).onClick(() => { this.section = section; void this.load() })
        })
      }
      if (!this.selected && this.section === 'seats') Button(this.t('打开主机 Web 面板')).onClick(() => { this.webTarget = {} })
      if (this.error) Text(this.t(this.error)).fontSize(13).fontColor(this.colors.danger).width('100%')
      if (this.busy) Row() { LoadingProgress().width(28).height(28); if (this.selected) Button(this.t('取消操作')).onClick(() => this.stream?.cancelPending()) }
      if (!this.selected && this.section === 'seats') PluginSeatsPanel({ colors: this.colors, client: this.client, sessionId: this.sessionId, getControl: this.getControl, onOpenNamespace: this.onOpenNamespace, onOpenSession: this.onOpenSession, onBackHandler: (handler?: () => boolean) => { this.seatsBack = handler } }).layoutWeight(1)
      else Scroll() { Column({ space: 12 }) {
        if (this.selected) NativePluginView({ colors: this.colors, client: this.client, pkg: this.selected.pkg, view: this.view, data: this.data, pluginName: this.selected.plugin,
          onAction: (action: WireObject): Promise<boolean> => this.invoke(action) })
        else if (this.section === 'panels') {
          if (!this.places.length && !this.busy && !this.error) Text(this.t('当前没有原生插件面板')).fontColor(this.colors.muted)
          ForEach(this.places, (place: PluginPlace) => { Button(place.plugin + ' · ' + place.title).width('100%').onClick(() => { void this.open(place) }) })
        } else if (this.section === 'configs') {
          ForEach(this.configs, (row: WireObject) => {
            Column({ space: 4 }) {
              Text(localizedPluginText(row['label']) || string(row['entryId'])).fontSize(15).fontColor(this.colors.text)
              if (row['configurable'] === true) Button(row['writable'] === false ? '查看配置' : '打开配置').onClick(() => { this.configId = string(row['entryId']) })
              else Text(string(row['reason']) || this.t('暂不支持配置')).fontSize(12).fontColor(this.colors.muted)
            }.width('100%').padding(12).backgroundColor(this.colors.surfaceAlt).borderRadius(12)
          })
        } else if (this.section === 'cordis') {
          Text(this.t('动态定义随引擎重启清空。含浏览器界面的启动与审批在主机 Web 页面完成。')).fontSize(12).fontColor(this.colors.muted)
          Button(this.t('打开主机 Web 面板')).onClick(() => { this.webTarget = this.cordisTarget() })
          ForEach(this.cordis, (row: WireObject) => {
            Column({ space: 6 }) {
              Text(this.cordisTitle(row)).fontSize(16).fontColor(this.colors.text)
              Text(string(row['agentId']) + ' · ' + string(row['pluginId'])).fontSize(12).fontColor(this.colors.muted)
              if (cordisShown(row)['description']) Text(string(cordisShown(row)['description'])).fontSize(13).fontColor(this.colors.text)
              if (row['hasClient']) Text(this.t('包含主机网页界面')).fontSize(12).fontColor(this.colors.muted)
              Text(this.t(cordisStatus(row))).fontSize(12).fontColor(this.colors.muted)
              if (object(row['latestRun'])['error']) Text(string(object(object(row['latestRun'])['error'])['message'])).fontSize(12).fontColor(this.colors.danger)
              Row() { if (row['activeRun']) Button(this.t('停止')).enabled(!this.busy).onClick(() => this.cordisAction(row, false)); Button(this.t('移除')).enabled(!this.busy).onClick(() => this.cordisAction(row, true)) }
            }.width('100%').padding(12).backgroundColor(this.colors.surfaceAlt).borderRadius(12)
          })
          if (!this.cordis.length && !this.busy && !this.error) Text(this.t('没有动态插件')).fontColor(this.colors.muted)
        }
      }.width('100%') }.layoutWeight(1)
    }.width('100%').height('100%').padding(16).backgroundColor(this.colors.background)
  }
}
