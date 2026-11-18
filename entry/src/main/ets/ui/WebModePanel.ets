import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { WireObject, object, string } from '../dsh/DshWire'
import { isDarkSurface } from './AnsiData'
import { localizedSettingsText } from './SettingsLocale'
import { webview } from '@kit.ArkWeb';
import { DshClient } from '../dsh/DshClient';
import { WebMode, WebModeEndpoint } from '../local/WebMode';
import { TransportControl } from '../remote/TransportEndpoint';
import { ThemeColors, themeColors } from './DshTheme';
class IslandBridge {
  receive: (text: string) => void = () => {}
  postMessage(text: string): void { if (typeof text === 'string' && text.length <= 65536) this.receive(text) }
}
@Component
export struct WebModePanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop initialTarget: WireObject = {}
  @Prop island: WireObject = {}
  onIslandStatus: (status: string) => void = () => {}
  onOpenSession: (session: string) => void = () => {}
  @State private islandReady: boolean = false
  @State private islandFailed: boolean = false
  private bridge: IslandBridge = new IslandBridge()
  private load: number = 0
  private readyTimer: number = -1
  private touched: number = 0
  @Prop @Watch('themeChanged') colors: ThemeColors = themeColors();
  client: DshClient = new DshClient();
  getControl: () => Promise<TransportControl> = async () => { throw new Error(this.t("本机连接服务尚未启动")); };
  @State private launchUrl: string = '';
  @State private error: string = '';
  @State private busy: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private active: boolean = false;
  private version: number = 0;
  private generation: number = -1;
  private origin: string = '';
  private mode?: WebMode;
  private timer: number = -1;
  aboutToAppear(): void { this.active = true; this.bridge.receive = (text: string) => this.islandMessage(text); void this.open(); }
  aboutToDisappear(): void { this.active = false; this.version++; this.load++; clearTimeout(this.readyTimer); this.bridge.receive = () => {}; try { this.controller.deleteJavaScriptRegister('DshGoIsland') } catch {} if (this.timer !== -1) clearInterval(this.timer); this.timer = -1; void this.close(); }
  private async close(): Promise<void> {
    const mode = this.mode; this.mode = undefined; this.launchUrl = ''; this.origin = '';
    await mode?.close().catch(() => {});
  }
  private async open(): Promise<void> {
    if (this.busy) return;
    const version = ++this.version; this.busy = true; this.error = '';
    let mode: WebMode | undefined;
    try {
      await this.close();
      const session = this.client.webSession(); this.generation = session.generation;
      mode = new WebMode(await this.getControl());
      const endpoint: WebModeEndpoint = await mode.open(session);
      if (!this.active || version !== this.version || this.generation !== this.client.connectionIdentity()) { await mode.close(); return; }
      this.mode = mode; this.origin = endpoint.origin; this.launchUrl = endpoint.launchUrl;
      if (this.island['slot'] === 'sidebar.right.pane.tab' && this.island['cell']) this.launchUrl += '#dsh-go-tab=' + encodeURIComponent(string(this.island['cell']));
      else if (this.island['mask'] === true) this.launchUrl += '#dsh-go-island=' + encodeURIComponent(string(this.island['slot']));
      this.islandReady = false; this.islandFailed = false;
      if (this.timer !== -1) clearInterval(this.timer);
      this.timer = setInterval(() => {
        if (this.generation !== this.client.connectionIdentity()) { this.error = this.t("主机连接已切换，请重新打开网页模式。"); void this.close(); }
      }, 500);
    } catch { await mode?.close().catch(() => {}); if (this.active && version === this.version) this.error = this.t("网页模式未能打开，请确认当前主机已连接。"); }
    finally { if (this.active && version === this.version) this.busy = false; }
  }
  private islandCurrent(): boolean { return this.active && this.generation === this.client.connectionIdentity() && !!this.origin }
  private hasIsland(): boolean { return Object.keys(this.island).length > 0 }
  private theme(): WireObject { const tokens: WireObject = { '--background': this.colors.background, '--foreground': this.colors.text, '--primary': this.colors.primary }; return { 'dark': isDarkSurface(this.colors.background), 'tokens': tokens } }
  private themeChanged(): void { if (this.islandReady && this.islandCurrent()) void this.controller.runJavaScript('window.__dshGoIsland && window.__dshGoIsland.setTheme(' + JSON.stringify(this.theme()) + ')').catch(() => {}) }
  private async asset(name: string): Promise<string> {
    const context = this.getUIContext().getHostContext() as common.Context
    return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(await context.resourceManager.getRawFileContent('islands/' + name))
  }
  private async inject(): Promise<void> {
    if (!this.islandCurrent() || this.islandFailed) return
    const load = ++this.load, version = this.version
    const current = (): boolean => this.islandCurrent() && load === this.load && version === this.version
    try {
      const opener = await this.asset('open.js'); if (!current()) return
      await this.controller.runJavaScript(opener); if (!current()) return
      if (!this.hasIsland()) {
        if (Object.keys(this.initialTarget).length) await this.controller.runJavaScript('window.__dshAppOpen(' + JSON.stringify(this.initialTarget) + ')')
        return
      }
      const script = await this.asset('island.js'), css = await this.asset('island.css'); if (!current()) return
      const config: WireObject = {}; for (const key of Object.keys(this.island)) config[key] = this.island[key]
      const insets: WireObject = { 'top': 0, 'bottom': 0 }
      config['load'] = load; config['css'] = css; config['theme'] = this.theme(); config['insets'] = insets; config['bootMs'] = 15000; config['slotMs'] = 8000
      await this.controller.runJavaScript(script); if (!current()) return
      clearTimeout(this.readyTimer)
      this.readyTimer = setTimeout(() => { if (current() && !this.islandReady) this.failIsland() }, 25000)
      await this.controller.runJavaScript('window.__dshGoIsland.init(' + JSON.stringify(config) + ')')
    } catch { if (current()) this.failIsland() }
  }
  private failIsland(): void { this.islandFailed = true; this.islandReady = false; clearTimeout(this.readyTimer); this.error = this.t('插件界面未能在应用内打开，可改用主机网页。'); this.onIslandStatus('error') }
  private islandMessage(raw: string): void {
    if (!this.islandCurrent() || this.islandFailed || !this.hasIsland()) return
    let message: WireObject; try { message = object(JSON.parse(raw)) } catch { return }
    if (message['load'] !== this.load) return
    if (message['t'] === 'ready') { clearTimeout(this.readyTimer); this.islandReady = true; this.onIslandStatus('ready'); return }
    if (message['t'] === 'error' || message['t'] === 'empty') { this.failIsland(); return }
    if (!this.islandReady || !this.touched || Date.now() - this.touched > 3000) return
    if (message['t'] === 'session') { const id = string(message['id']); if (id && id.length <= 256 && !/[\x00-\x1f\x7f]/.test(id)) { this.touched = 0; this.onOpenSession(id) } }
    else if (message['t'] === 'link') {
      const url = string(message['url']); if (!/^https:\/\/[^\s@]+$/.test(url) || url.length > 4096) return
      this.touched = 0
      const version = this.version
      this.getUIContext().showAlertDialog({ title: this.t('打开插件链接？'), message: url,
        primaryButton: { value: this.t('取消'), action: () => {} }, secondaryButton: { value: this.t('打开'), action: () => {
          if (version === this.version && this.islandCurrent()) void (this.getUIContext().getHostContext() as common.UIAbilityContext).openLink(url).catch(() => { this.error = this.t('无法打开链接') })
        } } })
    }
  }
  build() {
    Column({ space: 8 }) {
      if (!this.hasIsland()) Row({ space: 8 }) {
        Text(this.t("网页模式")).fontSize(17).fontColor(this.colors.text).layoutWeight(1);
        Button(this.busy ? this.t("连接中…") : this.t("重新连接")).height(34).fontSize(13).enabled(!this.busy).onClick(() => { void this.open(); });
      }.width('100%').padding({ left: 12, right: 12 });
      if (this.error) Text(this.t(this.error)).fontSize(13).fontColor(this.colors.danger).padding(12);
      if (this.launchUrl) {
        Web({ src: this.launchUrl, controller: this.controller }).javaScriptAccess(true).domStorageAccess(true)
          .javaScriptProxy({ object: this.bridge, name: 'DshGoIsland', methodList: ['postMessage'], controller: this.controller })
          .onPageEnd(() => { void this.inject() }).onTouch((event: TouchEvent) => { if (event.type === TouchType.Down) this.touched = Date.now() })
          .onPermissionRequest((event) => event.request.deny())
          .opacity(this.hasIsland() && !this.islandReady ? 0 : 1)
          .fileAccess(false).mixedMode(MixedMode.None).multiWindowAccess(false)
          .onOverrideUrlLoading((request: WebResourceRequest) => {
            const value = request.getRequestUrl();
            return !value.startsWith(this.origin + '/') || this.generation !== this.client.connectionIdentity();
          }).width('100%').layoutWeight(1);
      } else Blank().layoutWeight(1);
    }.width('100%').height('100%').backgroundColor(this.colors.background);
  }
}
