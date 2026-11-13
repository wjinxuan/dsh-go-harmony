import { DshClient } from '../dsh/DshClient'
import { string, WireObject } from '../dsh/DshWire'
import { DshGlyphs, ThemeColors, themeColors } from './DshTheme'
import { absoluteHostPath, directoryLevel, directoryNameProblem, HostDirectoryEntry, HostDirectoryLevel,
  sessionActionError } from './SessionManagementData'

@Component
export struct DirectoryPickerPanel {
  @Prop colors: ThemeColors = themeColors()
  @Prop workingDir: string = ''
  @Prop titleText: string = '选择文件夹'
  @Prop confirmLabel: string = '选择'
  @Prop recentPaths: string[] = []
  @Prop submitting: boolean = false
  @Prop submitError: string = ''
  client: DshClient = new DshClient()
  onClose: () => void = () => {}
  onPick: (path: string) => void = () => {}
  onBackHandler: (handler?: () => boolean) => void = () => {}
  @State private level: HostDirectoryLevel | undefined = undefined
  @State private showingPlaces: boolean = true
  @State private showHidden: boolean = false
  @State private pathInput: string = ''
  @State private folderName: string = ''
  @State private editor: string = ''
  @State private busy: boolean = false
  @State private error: string = ''
  @State private noBrowser: boolean = false
  @State private canCreate: boolean = true
  private stack: string[] = []
  private generation: number = 0
  private active: boolean = false

  aboutToAppear(): void {
    this.active = true
    this.onBackHandler(() => this.back())
  }

  aboutToDisappear(): void {
    this.active = false
    this.generation++
    this.onBackHandler(undefined)
  }

  private async open(path?: string, back: boolean = false): Promise<void> {
    if (this.busy || this.submitting) return
    const generation = ++this.generation
    const connection = this.client.connectionIdentity()
    this.busy = true
    this.error = ''
    try {
      const next = directoryLevel(await this.client.listDirectory(path))
      if (!this.active || generation !== this.generation || connection !== this.client.connectionIdentity()) return
      if (back) this.stack.pop()
      else if (this.level && this.level.path !== next.path) this.stack.push(this.level.path)
      this.level = next
      this.showingPlaces = false
      this.showHidden = false
      this.editor = ''
    } catch (reason) {
      if (!this.active || generation !== this.generation || connection !== this.client.connectionIdentity()) return
      const message = sessionActionError(reason, '')
      this.noBrowser = /directory-picker\/unavailable|gateway\/(method|service|lookup)-unavailable|HTTP (404|405|501)/.test(message)
      this.error = this.noBrowser ? '这台主机不能在这里浏览文件夹' : `打不开这个文件夹${message ? `（${message}）` : ''}`
    } finally {
      if (this.active && generation === this.generation) this.busy = false
    }
  }

  private back(): boolean {
    if (this.busy || this.submitting) return true
    if (this.editor) { this.editor = ''; this.error = ''; return true }
    if (this.stack.length > 0) { void this.open(this.stack[this.stack.length - 1], true); return true }
    if (!this.showingPlaces) {
      this.showingPlaces = true
      this.level = undefined
      this.error = ''
      return true
    }
    return false
  }

  private enterPath(): void {
    const path = this.pathInput.trim()
    if (!absoluteHostPath(path)) { this.error = '请输入主机上的绝对路径'; return }
    if (this.noBrowser) this.onPick(path)
    else void this.open(path)
  }

  private async createFolder(): Promise<void> {
    if (this.busy || !this.level || !this.canCreate) return
    const error = directoryNameProblem(this.folderName)
    if (error) { this.error = error; return }
    const generation = ++this.generation
    const connection = this.client.connectionIdentity()
    const args: WireObject = { 'path': this.level.path, 'name': this.folderName.trim() }
    this.busy = true
    this.error = ''
    let created = ''
    try {
      created = string(await this.client.request('directoryPicker/createDirectory', args))
      if (!created) throw new Error('主机没有确认新文件夹的路径')
    } catch (reason) {
      if (!this.active || generation !== this.generation || connection !== this.client.connectionIdentity()) return
      const message = sessionActionError(reason, '没能新建文件夹')
      this.canCreate = !/directory-picker\/unavailable|gateway\/(method|service|lookup)-unavailable|HTTP (404|405|501)/.test(message)
      this.error = /directory-picker\/exists/.test(message) ? '已经有同名的文件夹' : message
    } finally {
      if (this.active && generation === this.generation) this.busy = false
    }
    if (created && this.active && generation === this.generation && connection === this.client.connectionIdentity()) {
      this.editor = ''
      await this.open(created)
    }
  }

  private title(): string {
    if (!this.level) return this.titleText
    return this.level.crumbs[this.level.crumbs.length - 1]?.name || this.level.path
  }

  private folders(): HostDirectoryEntry[] {
    return (this.level?.entries || []).filter((entry: HostDirectoryEntry) => this.showHidden || !entry.hidden)
  }

  private hiddenCount(): number {
    return (this.level?.entries || []).filter((entry: HostDirectoryEntry) => entry.hidden).length
  }

  @Builder
  private row(title: string, subtitle: () => string, action: () => void) {
    Row({ space: 10 }) {
      Text(DshGlyphs.folder).fontFamily(DshGlyphs.family).fontSize(19).fontColor(this.colors.primary)
      Column({ space: 4 }) {
        Text(title).fontSize(15).fontColor(this.colors.text).width('100%').maxLines(2)
        if (subtitle()) Text(subtitle()).fontSize(12).fontColor(this.colors.muted).width('100%').maxLines(2)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(DshGlyphs.disclosure).fontFamily(DshGlyphs.family).fontSize(14).fontColor(this.colors.hint)
    }.padding(14).width('100%').borderRadius(12).backgroundColor(this.colors.surface).onClick(() => {
      if (!this.busy && !this.submitting) action()
    })
  }

  @Builder
  private places() {
    Column({ space: 8 }) {
      Text('位置').fontSize(13).fontColor(this.colors.muted).width('100%')
      if (!this.noBrowser) {
        this.row('主目录', () => '~', () => { void this.open() })
        if (this.workingDir) this.row('默认工作目录', () => this.workingDir, () => { void this.open(this.workingDir) })
        if (this.recentPaths.length > 0) Text('最近').fontSize(13).fontColor(this.colors.muted).width('100%')
        ForEach(this.recentPaths, (path: string) => {
          this.row(path, () => '', () => { void this.open(path) })
        }, (path: string) => path)
      } else {
        this.row('重试浏览主目录', () => '', () => { void this.open() })
      }
      this.row('输入路径', () => '', () => { this.editor = 'path'; this.error = '' })
    }.width('100%')
  }

  @Builder
  private input() {
    Column({ space: 8 }) {
      if (this.editor === 'path') {
        TextInput({ text: this.pathInput, placeholder: '输入主机上的绝对路径' }).fontColor(this.colors.text)
          .backgroundColor(this.colors.surface).onChange((value: string) => { this.pathInput = value })
        Button(this.noBrowser ? this.confirmLabel : '前往').width('100%').fontColor(this.colors.onPrimary).backgroundColor(this.colors.primary)
          .enabled(!this.busy && !this.submitting && !!this.pathInput.trim()).onClick(() => this.enterPath())
      } else {
        Text(`在「${this.title()}」里`).fontColor(this.colors.muted).fontSize(13).width('100%')
        TextInput({ text: this.folderName, placeholder: '文件夹名称' }).maxLength(120).fontColor(this.colors.text)
          .backgroundColor(this.colors.surface).onChange((value: string) => { this.folderName = value })
        Button('创建').width('100%').fontColor(this.colors.onPrimary).backgroundColor(this.colors.primary)
          .enabled(!this.busy && !!this.folderName.trim()).onClick(() => { void this.createFolder() })
      }
    }.width('100%')
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle }) {
          Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.text)
        }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText('返回')
          .enabled(!this.busy && !this.submitting).onClick(() => { if (!this.back()) this.onClose() })
        Text(this.editor === 'folder' ? '新建文件夹' : this.editor === 'path' ? '输入路径' : this.title())
          .fontColor(this.colors.text).fontSize(21).layoutWeight(1).maxLines(1)
        if (!this.showingPlaces && !this.editor && this.canCreate) {
          Button({ type: ButtonType.Circle }) {
            Text(DshGlyphs.add).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.text)
          }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText('新建文件夹').enabled(!this.busy && !this.submitting)
            .onClick(() => { this.editor = 'folder'; this.folderName = ''; this.error = '' })
        }
      }.width('100%')
      if (this.error || this.submitError) Text(this.error || this.submitError).fontSize(13).fontColor(this.colors.danger).width('100%')
      if (this.busy || this.submitting) LoadingProgress().width(26).height(26).color(this.colors.primary)
      if (this.editor) this.input()
      else if (this.showingPlaces) this.places()
      else if (this.level) {
        Scroll() {
          Row({ space: 5 }) {
            ForEach(this.level.crumbs, (crumb: HostDirectoryEntry) => {
              Button(crumb.path === this.level?.home ? '主目录' : crumb.name).height(34).fontSize(13)
                .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
                .enabled(!this.busy && !this.submitting && crumb.path !== this.level?.path)
                .onClick(() => { void this.open(crumb.path) })
            }, (crumb: HostDirectoryEntry) => `${crumb.path}|${crumb.name}`)
          }
        }.scrollable(ScrollDirection.Horizontal).width('100%').scrollBar(BarState.Off)
        List({ space: 7 }) {
          ForEach(this.folders(), (entry: HostDirectoryEntry) => {
            ListItem() { this.row(entry.name, () => '', () => { void this.open(entry.path) }) }
          }, (entry: HostDirectoryEntry) => `${entry.path}|${entry.name}`)
          if (this.folders().length === 0) {
            ListItem() { Text('这里没有子文件夹').fontSize(14).fontColor(this.colors.muted).padding(12) }
          }
          if (this.hiddenCount() > 0) {
            ListItem() {
              Button(this.showHidden ? '收起隐藏文件夹' : `显示 ${this.hiddenCount()} 个隐藏文件夹`)
                .fontColor(this.colors.primary).backgroundColor(this.colors.surface).onClick(() => { this.showHidden = !this.showHidden })
            }
          }
          if (this.level.truncated) {
            ListItem() { Text('文件夹太多，只列出了前面一部分').fontSize(13).fontColor(this.colors.muted).padding(8) }
          }
        }.layoutWeight(1).width('100%')
        Button(`${this.confirmLabel}「${this.title()}」`).height(46).width('100%').fontColor(this.colors.onPrimary).backgroundColor(this.colors.primary)
          .enabled(!this.busy && !this.submitting).onClick(() => { if (this.level) this.onPick(this.level.path) })
      }
    }.width('100%').height('100%').padding(16).backgroundColor(this.colors.background)
  }
}
