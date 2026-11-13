import { DshClient } from '../dsh/DshClient'
import { DshWorkspaceEntry } from '../dsh/DshWire'
import { ThemeColors, themeColors, DshGlyphs } from './DshTheme'
import { MessageBody } from './MessageBody'

@Component
export struct FilesPanel {
  @Prop colors: ThemeColors = themeColors()
  client: DshClient = new DshClient()
  sessionId: string = ''
  onClose: () => void = () => {}
  onBackHandler?: (handler: (() => boolean) | undefined) => void
  @State private path: string = ''
  @State private entries: DshWorkspaceEntry[] = []
  @State private filePath: string = ''
  @State private text: string = ''
  @State private busy: boolean = false
  @State private error: string = ''
  @State private truncated: boolean = false
  @State private eof: boolean = true
  private generation: number = 0
  private opening: boolean = false

  aboutToAppear(): void {
    this.onBackHandler?.(() => this.back())
    void this.load('')
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
      if (generation === this.generation) this.error = '无法读取目录，请检查会话工作区和访问权限。'
    } finally {
      if (generation === this.generation) { this.busy = false; this.opening = false }
    }
  }

  private async open(entry: DshWorkspaceEntry): Promise<void> {
    const path = this.path ? `${this.path}/${entry.name}` : entry.name
    if (entry.type === 'directory') { await this.load(path, true); return }
    const generation = ++this.generation
    this.opening = true
    this.busy = true
    this.error = ''
    try {
      const result = await this.client.readWorkspaceText(this.sessionId, path)
      if (generation !== this.generation) return
      this.text = result.text
      this.eof = result.eof
      this.filePath = path
    } catch {
      if (generation === this.generation) this.error = '无法预览这个文件，可能是二进制格式或没有读取权限。'
    } finally {
      if (generation === this.generation) { this.busy = false; this.opening = false }
    }
  }

  private back(): boolean {
    if (this.opening) {
      this.generation++
      this.opening = false; this.busy = false; this.error = ''
      return true
    }
    if (this.filePath) { this.filePath = ''; this.text = ''; return true }
    if (!this.path) return false
    void this.load(this.path.split('/').slice(0, -1).join('/'))
    return true
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Button({ type: ButtonType.Circle }) {
          Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text)
        }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText('返回')
          .onClick(() => { if (!this.back()) this.onClose() })
        Column({ space: 3 }) {
          Text(this.filePath ? this.filePath.split('/').pop() : '工作区文件').fontSize(21).fontColor(this.colors.text)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.filePath || this.path || '/').fontSize(12).fontColor(this.colors.muted).maxLines(1)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%')
      if (this.error) { Text(this.error).fontSize(14).fontColor(this.colors.danger) }
      if (this.busy) { LoadingProgress().width(36).height(36).color(this.colors.primary) }
      if (this.filePath) {
        Scroll() {
          Column({ space: 12 }) {
            if (this.filePath.toLowerCase().endsWith('.md')) {
              MessageBody({ text: this.text, colors: this.colors })
            } else {
              Text(this.text).fontFamily('JetBrainsMono').fontSize(13).fontColor(this.colors.text)
                .copyOption(CopyOptions.LocalDevice).width('100%')
            }
            if (!this.eof) { Text('当前显示文件开头 500 行').fontSize(13).fontColor(this.colors.muted) }
          }.width('100%').padding(14)
        }.layoutWeight(1).width('100%').align(Alignment.TopStart).backgroundColor(this.colors.surface).borderRadius(14)
      } else {
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
            ListItem() { Text('文件夹为空').fontSize(15).fontColor(this.colors.muted).padding(30) }
          }
          if (this.truncated) { ListItem() { Text('目录内容较多，当前只显示部分项目。').fontColor(this.colors.muted) } }
        }.layoutWeight(1).width('100%')
      }
    }.padding(16).width('100%').height('100%').backgroundColor(this.colors.background)
  }
}
