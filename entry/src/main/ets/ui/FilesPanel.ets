import { localizedSettingsText } from './SettingsLocale'
import { DshClient } from '../dsh/DshClient'
import { DshWorkspaceEntry } from '../dsh/DshWire'
import { ThemeColors, themeColors, DshGlyphs } from './DshTheme'
import { WorkspaceFileViewer } from './WorkspaceFileViewer'

@Component
export struct FilesPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  client: DshClient = new DshClient()
  sessionId: string = ''
  initialPath: string = ''
  onClose: () => void = () => {}
  onBackHandler?: (handler: (() => boolean) | undefined) => void
  @State private path: string = ''
  @State private entries: DshWorkspaceEntry[] = []
  @State private filePath: string = ''
  @State private busy: boolean = false
  @State private error: string = ''
  @State private truncated: boolean = false
  private generation: number = 0
  private opening: boolean = false

  aboutToAppear(): void {
    this.onBackHandler?.(() => this.back())
    if (this.initialPath) this.filePath = this.initialPath
    else void this.load('')
  }
  aboutToDisappear(): void {
    this.onBackHandler?.(undefined)
    this.generation++
  }

  private async load(path: string, subpage: boolean = false): Promise<void> {
    const generation = ++this.generation
    this.opening = subpage
    this.busy = true
    this.error = ''
    this.filePath = ''
    try {
      const listing = await this.client.listWorkspace(this.sessionId, path)
      if (generation !== this.generation) return
      this.path = path
      this.entries = listing.entries
      this.truncated = listing.truncated
    } catch {
      if (generation === this.generation) this.error = this.t("无法读取目录，请检查会话工作区和访问权限。")
    } finally {
      if (generation === this.generation) { this.busy = false; this.opening = false }
    }
  }

  private async open(entry: DshWorkspaceEntry): Promise<void> {
    const path = this.path ? `${this.path}/${entry.name}` : entry.name
    if (entry.type === 'directory') { await this.load(path, true); return }
    this.filePath = path
  }

  private back(): boolean {
    if (this.opening) {
      this.generation++
      this.opening = false; this.busy = false; this.error = ''
      return true
    }
    if (this.filePath) {
      this.filePath = ''
      if (this.initialPath) this.onClose()
      return true
    }
    if (!this.path) return false
    void this.load(this.path.split('/').slice(0, -1).join('/'))
    return true
  }

  build() {
    if (this.filePath) {
      WorkspaceFileViewer({ colors: this.colors, client: this.client, sessionId: this.sessionId, path: this.filePath,
        onClose: () => { this.back() } })
    } else {
      Column({ space: 14 }) {
      Row({ space: 12 }) {
        Button({ type: ButtonType.Circle }) {
          Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text)
        }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText(this.t("返回"))
          .onClick(() => { if (!this.back()) this.onClose() })
        Column({ space: 3 }) {
          Text(this.filePath ? this.filePath.split('/').pop() : this.t("工作区文件")).fontSize(21).fontColor(this.colors.text)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.filePath || this.path || '/').fontSize(12).fontColor(this.colors.muted).maxLines(1)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%')
      if (this.error) { Text(this.t(this.error)).fontSize(14).fontColor(this.colors.danger) }
      if (this.busy) { LoadingProgress().width(36).height(36).color(this.colors.primary) }
        List({ space: 3 }) {
          ForEach(this.entries, (entry: DshWorkspaceEntry) => {
            ListItem() {
              Row({ space: 12 }) {
                Text(entry.type === 'directory' ? DshGlyphs.folder : DshGlyphs.file)
                  .fontFamily(DshGlyphs.family).fontSize(23).fontColor(this.colors.primary)
                Text(entry.name).fontSize(15).fontColor(this.colors.text).layoutWeight(1).maxLines(2)
                Text(entry.type === 'directory' ? '›' : `${entry.size ?? 0} B`).fontSize(12).fontColor(this.colors.hint)
              }.width('100%').padding(16).backgroundColor(this.colors.surface).borderRadius(12)
                .onClick(() => { if (!this.busy) void this.open(entry) })
            }
          }, (entry: DshWorkspaceEntry) => `${this.path}/${entry.name}|${entry.type}|${entry.size}`)
          if (!this.busy && this.entries.length === 0) {
            ListItem() { Text(this.t("文件夹为空")).fontSize(15).fontColor(this.colors.muted).padding(30) }
          }
          if (this.truncated) { ListItem() { Text(this.t("目录内容较多，当前只显示部分项目。")).fontColor(this.colors.muted) } }
        }.layoutWeight(1).width('100%')
      }.padding(16).width('100%').height('100%').backgroundColor(this.colors.background)
    }
  }
}
