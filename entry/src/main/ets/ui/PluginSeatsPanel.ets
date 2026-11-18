import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { DshClient } from '../dsh/DshClient'
import { TransportControl } from '../remote/TransportEndpoint'
import { array, object, string, WireObject } from '../dsh/DshWire'
import { ThemeColors, themeColors } from './DshTheme'
import { localizedSettingsText } from './SettingsLocale'
import { PluginSeat, pluginSeats, seatConfig, seatWebTarget, parseWebBoot } from './PluginSeatData'
import { WebModePanel } from './WebModePanel'

@Component
export struct PluginSeatsPanel {
  @StorageProp('dshLanguage') language: string = 'system'
  @Prop colors: ThemeColors = themeColors()
  @Prop sessionId: string = ''
  client: DshClient = new DshClient()
  getControl: () => Promise<TransportControl> = async () => { throw new Error('本机连接服务不可用') }
  onOpenNamespace: (id: string) => void = () => {}
  onOpenSession: (id: string) => void = () => {}
  onBackHandler?: (handler: (() => boolean) | undefined) => void
  @State private seats: PluginSeat[] = []
  @State private shown: PluginSeat | undefined = undefined
  @State private config: WireObject = {}
  @State private nativeNamespaces: string[] = []
  @State private probe: boolean = false
  @State private busy: boolean = false
  @State private error: string = ''
  private inventory: WireObject = {}
  private recipes: WireObject = {}
  private namespaces: WireObject[] = []
  private bundles: WireObject[] = []
  private active: boolean = false
  private generation: number = 0
  private probed: boolean = false
  private t(value: string): string { return localizedSettingsText(value, this.language) }
  aboutToAppear(): void { this.onBackHandler?.(() => { if (!this.shown) return false; this.shown = undefined; this.config = {}; return true }); this.active = true; void this.load() }
  aboutToDisappear(): void { this.onBackHandler?.(undefined); this.active = false; this.generation++ }
  private async load(): Promise<void> {
    const generation = ++this.generation, identity = this.client.connectionIdentity(); this.busy = true; this.error = ''
    try {
      const value = object(await this.client.bridgeJson('GET', '/dsh-go/v1/inventory').catch((): WireObject => ({})))
      const context = this.getUIContext().getHostContext() as common.Context
      const recipes = object(JSON.parse(util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(await context.resourceManager.getRawFileContent('islands/recipes.json'))))
      const bundles = await this.client.listPluginBundles().catch((): WireObject[] => [])
      const settings = await this.client.describeSettings().catch((): WireObject => ({}))
      const boot = parseWebBoot(await this.client.webBootPage().catch(() => ''))
      if (!this.active || generation !== this.generation || identity !== this.client.connectionIdentity()) return
      this.inventory = value; this.recipes = recipes; this.bundles = bundles; this.namespaces = array(settings['namespaces']).map(object)
      this.seats = pluginSeats(value, bundles, boot)
      if (value['routeGuard'] === true && (!value['slots'] || object(value['occupancy'])['stale'] === true) && !this.probed) { this.probed = true; this.probe = true }
      else if (!value['slots'] && !this.seats.length) this.error = '主机尚未上报网页插件席位，可打开主机网页后重试。'
    } catch { if (this.active && generation === this.generation) this.error = '插件席位读取失败，请检查主机连接。' }
    finally { if (this.active && generation === this.generation) this.busy = false }
  }
  private probeConfig(): WireObject { const target: WireObject = {}; return { 'mode': 'probe', 'slot': '', 'target': target, 'mask': false } }
  private open(seat: PluginSeat): void {
    const bundle = this.bundles.find((row: WireObject) => row['name'] === seat.pkg)
    const rows = array(bundle?.['rows']).map(object).map((row: WireObject) => string(row['rowId']))
    this.nativeNamespaces = ['settings.section', 'plugins.bundle.config', 'plugins.row.config'].includes(seat.slot) ?
      this.namespaces.filter((ns: WireObject) => rows.includes(string(ns['ns'])) && ns['autoGenerate'] !== false &&
        (seat.slot !== 'plugins.row.config' || seat.cell.split('#').pop() === ns['ns'])).map((ns: WireObject) => string(ns['ns'])) : []
    this.config = seatConfig(seat, this.sessionId, this.recipes, this.inventory['routeGuard'] === true) || {}
    this.shown = seat
  }
  build() {
    Column({ space: 10 }) {
      if (this.shown) {
        Row() { Button(this.t('返回席位')).onClick(() => { this.shown = undefined; this.config = {} }); Text(this.shown.title).fontColor(this.colors.text).layoutWeight(1) }.width('100%')
        if (this.nativeNamespaces.length) {
          ForEach(this.nativeNamespaces, (id: string) => { Button(id).width('100%').onClick(() => this.onOpenNamespace(id)) })
          Button(this.t('打开主机 Web 面板')).onClick(() => { this.nativeNamespaces = []; this.config = {} })
        } else {
          WebModePanel({ colors: this.colors, client: this.client, getControl: this.getControl, island: this.config,
            initialTarget: seatWebTarget(this.shown, this.sessionId), onOpenSession: this.onOpenSession }).layoutWeight(1)
          if (Object.keys(this.config).length) Button(this.t('打开主机 Web 面板')).onClick(() => { const seat = this.shown; this.shown = undefined; this.config = {}; setTimeout(() => { if (this.active) this.shown = seat }, 0) })
        }
      } else {
        Scroll() { Column({ space: 10 }) {
        Button(this.t('刷新席位')).enabled(!this.busy).onClick(() => { void this.load() })
        if (this.probe) WebModePanel({ colors: this.colors, client: this.client, getControl: this.getControl,
          island: this.probeConfig(), onIslandStatus: (status: string) => {
            this.probe = false; if (status === 'ready') void this.load(); else this.error = '主机未能上报插件席位，请打开主机网页后重试。'
          } }).height(1).opacity(0)
        ForEach(this.seats, (seat: PluginSeat) => {
          Button({ type: ButtonType.Normal }) { Column({ space: 4 }) { Text(seat.title).fontColor(this.colors.text).width('100%'); Text(seat.pkg + ' · ' + seat.slot).fontColor(this.colors.muted).fontSize(12).width('100%') }.padding(12) }
            .backgroundColor(this.colors.surfaceAlt).width('100%').onClick(() => this.open(seat))
        }, (seat: PluginSeat) => JSON.stringify([seat.slot, seat.pkg, seat.cell]))
        if (!this.seats.length && !this.busy && !this.error && !this.probe) Text(this.t('还没有主机 Web 页面上报席位')).fontColor(this.colors.muted)
        if (this.error) Text(this.t(this.error)).fontColor(this.colors.danger)
        }.width('100%') }.layoutWeight(1).width('100%')
      }
    }.width('100%').height('100%')
  }
}
