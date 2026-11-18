import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { util } from '@kit.ArkTS'
import { webview } from '@kit.ArkWeb'
import { pasteboard } from '@kit.BasicServicesKit'
import { DshClient, DshSubscription } from '../dsh/DshClient'
import { TerminalApi, TerminalAttachment, TerminalEnvironment, TerminalFrame, TerminalInfo, TerminalShell } from '../dsh/Terminal'
import { ThemeColors, themeColors } from './DshTheme'

const TERMINAL_PAGE = 'resource://rawfile/terminal/index.html'

class TerminalBridge {
  onInput: (value: string, revision: number) => void = () => {}
  onSize: (cols: number, rows: number) => void = () => {}
  onModifierUsed: () => void = () => {}
  onDisplayOverflow: () => void = () => {}
  input(value: string, revision: number): void { if (typeof value === 'string') this.onInput(value, revision) }
  size(cols: number, rows: number): void { this.onSize(cols, rows) }
  modifierUsed(): void { this.onModifierUsed() }
  displayOverflow(): void { this.onDisplayOverflow() }
}

function scriptText(value: string): string {
  return JSON.stringify(value).replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029')
}

@Component
export struct TerminalPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  @Prop sessionId: string = ''
  client: DshClient = new DshClient()
  onClose: () => void = () => {}
  @State private tabs: TerminalInfo[] = []
  @State private selected: string = ''
  @State private working: boolean = false
  @State private available: boolean = false
  @State private writable: boolean = false
  @State private modifier: string = ''
  @State private error: string = ''
  @State private cwd: string = ''
  @State private editing: string = ''
  @State private titleDraft: string = ''
  @State private shells: TerminalShell[] = []
  @State private showShells: boolean = false
  private api?: TerminalApi
  private environment?: TerminalEnvironment
  private active: boolean = false
  private generation: number = -1
  private session: string = ''
  private revision: number = 0
  private webReady: boolean = false
  private controller: webview.WebviewController = new webview.WebviewController()
  private bridge: TerminalBridge = new TerminalBridge()
  private attach?: TerminalAttachment
  private retains: Map<string, DshSubscription> = new Map()
  private retaining: Set<string> = new Set()
  private cols: number = 80
  private rows: number = 24
  private scripts: Promise<void> = Promise.resolve()
  private renderBytes: number = 0
  private createId: string = ''
  private createShell?: string

  aboutToAppear(): void {
    this.active = true
    this.generation = this.client.connectionIdentity()
    this.session = this.sessionId
    this.api = new TerminalApi(this.client, this.session)
    this.bridge.onInput = (value: string, revision: number): void => {
      if (revision !== this.revision || !this.current() || !this.writable) return
      if (!this.attach?.write(value)) this.error = this.t("终端输入太长或正在等待主机确认，请分段重试。")
    }
    this.bridge.onSize = (cols: number, rows: number): void => {
      if (!this.current() || !Number.isSafeInteger(cols) || !Number.isSafeInteger(rows)) return
      this.cols = Math.max(2, Math.min(cols, this.environment?.maxCols ?? 500))
      this.rows = Math.max(1, Math.min(rows, this.environment?.maxRows ?? 200))
      this.attach?.resize(this.cols, this.rows)
    }
    this.bridge.onModifierUsed = (): void => { this.modifier = '' }
    this.bridge.onDisplayOverflow = (): void => this.displayFailed(this.t("终端输出过快，请重新连接以恢复画面。"))
    void this.reload()
  }

  aboutToDisappear(): void {
    this.active = false
    this.revision++
    this.attach?.close()
    this.retains.forEach((cancel: DshSubscription) => cancel())
    this.retains.clear()
    this.retaining.clear()
    try { this.controller.deleteJavaScriptRegister('terminalBridge') } catch { /* Web may already be detached. */ }
  }

  private current(): boolean {
    return this.active && this.session === this.sessionId && this.generation === this.client.connectionIdentity()
  }

  private async reload(): Promise<void> {
    const api = this.api
    if (this.working || !api || !this.current()) return
    this.working = true
    this.error = ''
    try {
      const environment = await api.environment()
      const tabs = await api.list()
      if (!this.current()) return
      this.environment = environment
      this.cwd = environment.cwd
      this.available = true
      this.tabs = tabs
      this.retains.forEach((cancel: DshSubscription, id: string) => {
        if (!tabs.some((tab: TerminalInfo) => tab.id === id)) { cancel(); this.retains.delete(id) }
      })
      for (const tab of tabs) void this.retain(tab.id)
      const selected = tabs.find((tab: TerminalInfo) => tab.id === this.selected) ??
        tabs.find((tab: TerminalInfo) => tab.state === 'running') ?? tabs[0]
      this.select(selected?.id ?? '')
    } catch (error) {
      if (this.current()) {
        const detail = error instanceof Error ? error.message : ''
        this.error = /404|terminal\/disabled|TERMINAL_DISABLED/i.test(detail) ?
          this.t("当前主机未启用交互终端。") : this.t("无法加载终端，请检查主机后重试。")
      }
    } finally { if (this.current()) this.working = false }
  }

  private async retain(id: string): Promise<void> {
    if (this.retains.has(id) || this.retaining.has(id)) return
    this.retaining.add(id)
    try {
      const cancel = await this.api?.retain(id)
      if (!this.current() || !this.tabs.some((tab: TerminalInfo) => tab.id === id)) cancel?.()
      else if (cancel) this.retains.set(id, cancel)
    } catch { /* Older hosts may allow attachment without a separate hold. */ }
    finally { this.retaining.delete(id) }
  }

  private select(id: string): void {
    const revision = ++this.revision
    this.attach?.close()
    this.attach = undefined
    this.writable = false
    this.modifier = ''
    this.selected = id
    this.editing = ''
    this.render('window.terminalDisplay.clear()')
    const environment = this.environment
    if (!this.webReady || !id || !environment || !this.current()) return
    const attachment = new TerminalAttachment(this.client, this.session, id, util.generateRandomUUID(), environment,
      (frame: TerminalFrame): void => {
        if (this.current() && revision === this.revision) this.receive(frame)
      }, (error?: string): void => {
        if (!this.current() || revision !== this.revision) return
        this.writable = false
        this.render('window.terminalDisplay.lock()')
        this.error = error || this.t("主机已结束终端连接，可刷新终端列表。")
      })
    this.attach = attachment
    void attachment.open()
  }

  private receive(frame: TerminalFrame): void {
    const info = frame.info
    if (info) {
      this.tabs = this.tabs.map((tab: TerminalInfo) => tab.id === info.id ? info : tab)
      this.writable = frame.writable === true
      if (frame.type === 'snapshot') {
        this.render(`window.terminalDisplay.snapshot(${info.cols},${info.rows},${scriptText(frame.screen ?? '')},${this.writable},${this.revision})`)
      } else {
        this.render(`window.terminalDisplay.state(${info.cols},${info.rows},${this.writable})`)
      }
      if (this.writable && (this.cols !== info.cols || this.rows !== info.rows)) this.attach?.resize(this.cols, this.rows)
    } else if (frame.type === 'output') {
      this.render(`window.terminalDisplay.output(${scriptText(frame.data ?? '')})`)
    } else if (frame.type === 'refused') {
      this.writable = false
      this.render('window.terminalDisplay.lock()')
      this.error = this.t("此终端当前为只读。刷新可重新接管输入。")
    }
  }

  private render(script: string): void {
    if (!this.webReady) return
    if (this.renderBytes + script.length > 4194304) {
      this.displayFailed(this.t("终端输出过快，请重新连接以恢复画面。"))
      return
    }
    const revision = this.revision
    this.renderBytes += script.length
    this.scripts = this.scripts.then(async () => {
      try {
        if (this.current() && this.webReady && revision === this.revision) await this.controller.runJavaScript(script)
      } catch { if (revision === this.revision) this.displayFailed(this.t("无法显示终端画面，请刷新后重试。")) }
      finally { this.renderBytes -= script.length }
    })
  }

  private displayFailed(message: string): void {
    if (!this.current()) return
    this.revision++
    this.attach?.close()
    this.writable = false
    this.modifier = ''
    this.error = message
  }

  private async loaded(): Promise<void> {
    try {
      this.webReady = (await this.controller.runJavaScript('typeof window.terminalDisplay === "object"')) === 'true'
      if (!this.current()) return
      if (!this.webReady) this.displayFailed(this.t("无法加载终端显示组件。"))
      else this.select(this.selected)
    } catch { this.displayFailed(this.t("无法加载终端显示组件。")) }
  }

  private async createTab(path?: string): Promise<void> {
    const api = this.api
    const environment = this.environment
    if (!api || !environment || this.working || !this.current()) return
    this.working = true
    this.error = ''
    this.showShells = false
    if (!this.createId || this.createShell !== path) this.createId = util.generateRandomUUID()
    this.createShell = path
    try {
      const info = await api.create(this.createId, Math.min(this.cols, environment.maxCols),
        Math.min(this.rows, environment.maxRows), path)
      if (!this.current()) return
      this.createId = ''
      this.tabs = this.tabs.filter((tab: TerminalInfo) => tab.id !== info.id).concat(info)
      void this.retain(info.id)
      this.select(info.id)
    } catch { if (this.current()) this.error = this.t("未能确认终端创建结果。可重试或刷新列表。") }
    finally { if (this.current()) this.working = false }
  }

  private async openShells(): Promise<void> {
    if (this.working || !this.current()) return
    if (this.showShells) { this.showShells = false; return }
    this.working = true
    this.error = ''
    try {
      const shells = await this.api?.shells()
      if (this.current()) { this.shells = shells ?? []; this.showShells = true }
    } catch { if (this.current()) this.error = this.t("无法读取主机可用的 Shell。") }
    finally { if (this.current()) this.working = false }
  }

  private async rename(): Promise<void> {
    const id = this.editing
    const title = this.titleDraft.trim()
    if (!this.current() || this.working || !id || !title) return
    this.working = true
    try {
      await this.api?.rename(id, title)
      if (!this.current()) return
      const renamed = await this.api?.list()
      if (this.current() && renamed) { this.tabs = renamed; this.editing = '' }
    } catch { if (this.current()) this.error = this.t("终端名称未能保存，请重试。") }
    finally { if (this.current()) this.working = false }
  }

  private confirmClose(id: string): void {
    this.getUIContext().showAlertDialog({ title: this.t("结束终端？"), message: this.t("主机会结束此 Shell 及其子进程。"),
      primaryButton: { value: this.t("取消"), action: () => {} },
      secondaryButton: { value: this.t("结束终端"), action: () => { void this.closeTab(id) } } })
  }

  private async closeTab(id: string): Promise<void> {
    if (!this.current() || this.working || this.selected !== id) return
    this.working = true
    try {
      await this.api?.close(id)
      if (!this.current()) return
      this.retains.get(id)?.()
      this.retains.delete(id)
      this.tabs = this.tabs.filter((tab: TerminalInfo) => tab.id !== id)
      if (this.selected === id) this.select(this.tabs[0]?.id ?? '')
      this.error = ''
    } catch { if (this.current()) this.error = this.t("未能确认终端关闭结果，请刷新列表。") }
    finally { if (this.current()) this.working = false }
  }

  private status(): string {
    const info = this.tabs.find((tab: TerminalInfo) => tab.id === this.selected)
    if (info?.state === 'exited') return info.exitCode === undefined ? this.t("Shell 已退出") : this.f("Shell 已退出（{0}）", [info.exitCode])
    if (info?.state === 'failed') return this.t("Shell 启动失败")
    if (info && !this.writable) return this.t("终端未取得输入控制")
    return info?.cwd || this.cwd
  }

  private toggleModifier(key: string): void {
    if (!this.writable) return
    this.modifier = this.modifier === key ? '' : key
    this.render(`window.terminalDisplay.modifier(${scriptText(this.modifier)})`)
  }

  private async paste(): Promise<void> {
    const revision = this.revision
    if (!this.writable || !this.current()) return
    try {
      const data = (await pasteboard.getSystemPasteboard().getData()).getPrimaryText()
      if (revision !== this.revision || !this.writable || !this.current() || !data) return
      if (data.length > 65520) { this.error = this.t("粘贴内容太长，请分段粘贴。"); return }
      this.modifier = ''
      this.render(`window.terminalDisplay.modifier(''); window.terminalDisplay.paste(${scriptText(data)})`)
    } catch { if (revision === this.revision && this.current()) this.error = this.t("无法读取剪贴板中的文本。") }
  }

  @Builder
  private terminalKey(key: string, label: string, accessible: string) {
    Button(label).height(44).constraintSize({ minWidth: 44 }).fontSize(13)
      .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).enabled(this.writable)
      .accessibilityText(accessible).onClick(() => this.render(`window.terminalDisplay.key(${scriptText(key)})`))
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Button(this.t("返回")).height(44).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).onClick(() => this.onClose())
        Column({ space: 3 }) {
          Text(this.t("终端")).fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.colors.text)
          if (this.status()) Text(this.status()).fontSize(12).fontColor(this.colors.muted).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button(this.t("刷新")).height(44).fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt)
          .enabled(!this.working).onClick(() => { void this.reload() })
      }.width('100%')
      if (this.error) Text(this.t(this.error)).width('100%').fontSize(13).fontColor(this.colors.danger)
      if (this.available) {
        Scroll() {
          Row({ space: 6 }) {
            Button(this.t("新建")).height(44).enabled(!this.working).fontColor(this.colors.onPrimary)
              .backgroundColor(this.colors.primary).onClick(() => { void this.createTab() })
            Button(this.t("选择 Shell")).height(44).enabled(!this.working).fontColor(this.colors.primary)
              .backgroundColor(this.colors.surfaceAlt).onClick(() => { void this.openShells() })
            ForEach(this.tabs, (tab: TerminalInfo) => {
              Button(tab.title.slice(0, 120)).height(44).constraintSize({ maxWidth: 180 }).fontSize(13)
                .fontColor(tab.id === this.selected ? this.colors.onPrimary : this.colors.text)
                .backgroundColor(tab.id === this.selected ? this.colors.primary : this.colors.surfaceAlt)
                .enabled(!this.working).onClick(() => { if (this.selected !== tab.id) { this.error = ''; this.select(tab.id) } })
            }, (tab: TerminalInfo) => `${tab.id}/${tab.title}`)
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      if (this.showShells) {
        Scroll() {
          Column({ space: 4 }) {
            ForEach(this.shells, (shell: TerminalShell) => {
              Button(`${shell.name}  ${shell.path}`).height(44).width('100%').fontColor(this.colors.text)
                .backgroundColor(this.colors.surfaceAlt).onClick(() => { void this.createTab(shell.path) })
            }, (shell: TerminalShell) => shell.path)
            if (!this.shells.length) Text(this.t("主机未列出其他 Shell。")).fontSize(13).fontColor(this.colors.muted)
          }.width('100%')
        }.width('100%').constraintSize({ maxHeight: 152 })
      }
      if (this.editing) {
        Row({ space: 6 }) {
          TextInput({ text: this.titleDraft, placeholder: this.t("终端名称") }).maxLength(120).layoutWeight(1)
            .onChange((value: string) => this.titleDraft = value)
          Button(this.t("保存")).height(44).enabled(!this.working && !!this.titleDraft.trim()).onClick(() => { void this.rename() })
          Button(this.t("取消")).height(44).enabled(!this.working).onClick(() => this.editing = '')
        }.width('100%')
      }
      if (this.selected && !this.editing) {
        Row({ space: 6 }) {
          Button(this.t("重命名")).height(44).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).enabled(!this.working)
            .onClick(() => {
              this.editing = this.selected
              this.titleDraft = this.tabs.find((tab: TerminalInfo) => tab.id === this.selected)?.title ?? ''
            })
          Button(this.t("结束终端")).height(44).fontColor(this.colors.danger).backgroundColor(this.colors.surfaceAlt).enabled(!this.working)
            .onClick(() => this.confirmClose(this.selected))
        }.width('100%')
      }
      Stack({ alignContent: Alignment.Center }) {
        Web({ src: TERMINAL_PAGE, controller: this.controller })
          .width('100%').height('100%').backgroundColor('#12161e')
          .javaScriptAccess(true).fileAccess(false).blockNetwork(true).domStorageAccess(false)
          .multiWindowAccess(false).zoomAccess(false).onlineImageAccess(false).mixedMode(MixedMode.None)
          .onOverrideUrlLoading((request: WebResourceRequest): boolean => request.getRequestUrl() !== TERMINAL_PAGE)
          .javaScriptProxy({ object: this.bridge, name: 'terminalBridge',
            methodList: ['input', 'size', 'modifierUsed', 'displayOverflow'], controller: this.controller })
          .onPageEnd((event: OnPageEndEvent): void => { if (event.url === TERMINAL_PAGE) void this.loaded() })
          .onRenderExited(() => { this.webReady = false; this.displayFailed(this.t("终端显示已退出。请返回后重新打开。")) })
        if (!this.selected) {
          if (this.working) LoadingProgress().width(28).height(28).color('#b8cdfb')
          else Text(this.available ? this.t("选择或新建终端") : this.t("终端不可用")).fontSize(14).fontColor('#e3e9f3')
        }
      }.width('100%').layoutWeight(1).borderRadius(14).clip(true)
      if (this.selected) {
        Scroll() {
          Row({ space: 6 }) {
            Button('Ctrl').height(44).constraintSize({ minWidth: 44 }).enabled(this.writable)
              .fontColor(this.modifier === 'ctrl' ? this.colors.onPrimary : this.colors.text)
              .backgroundColor(this.modifier === 'ctrl' ? this.colors.primary : this.colors.surfaceAlt)
              .accessibilityText(this.modifier === 'ctrl' ? this.t("取消 Ctrl 修饰键") : this.t("激活 Ctrl 修饰键"))
              .onClick(() => this.toggleModifier('ctrl'))
            Button('Alt').height(44).constraintSize({ minWidth: 44 }).enabled(this.writable)
              .fontColor(this.modifier === 'alt' ? this.colors.onPrimary : this.colors.text)
              .backgroundColor(this.modifier === 'alt' ? this.colors.primary : this.colors.surfaceAlt)
              .accessibilityText(this.modifier === 'alt' ? this.t("取消 Alt 修饰键") : this.t("激活 Alt 修饰键"))
              .onClick(() => this.toggleModifier('alt'))
            this.terminalKey('esc', 'Esc', this.t("退出键"))
            this.terminalKey('tab', 'Tab', this.t("制表键"))
            this.terminalKey('left', '←', this.t("左方向键"))
            this.terminalKey('up', '↑', this.t("上方向键"))
            this.terminalKey('down', '↓', this.t("下方向键"))
            this.terminalKey('right', '→', this.t("右方向键"))
            this.terminalKey('enter', '↵', this.t("回车键"))
            this.terminalKey('pipe', '|', this.t("竖线"))
            this.terminalKey('tilde', '~', this.t("波浪号"))
            this.terminalKey('slash', '/', this.t("斜杠"))
            this.terminalKey('dash', '-', this.t("连字符"))
            if (this.writable) {
              PasteButton({ icon: PasteIconStyle.LINES, text: PasteDescription.PASTE, buttonType: ButtonType.Capsule })
                .height(44).fontColor(this.colors.onPrimary).backgroundColor(this.colors.primary)
                .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
                  if (result === PasteButtonOnClickResult.SUCCESS) void this.paste()
                  else this.error = this.t("未能获得本次剪贴板访问授权。")
                })
            }
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
    }.width('100%').height('100%').padding(12).backgroundColor(this.colors.background)
  }
}
