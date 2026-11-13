import { common } from '@kit.AbilityKit'
import { DshClient, DshWorkspace } from '../dsh/DshClient'
import { ThemeColors, themeColors, DshGlyphs } from './DshTheme'
import { DirectoryPickerPanel } from './DirectoryPickerPanel'
import { directoryParent, recentDirectoryPaths, sessionActionError } from './SessionManagementData'
import { loadRecentDirectories, rememberRecentDirectory } from './WorkspaceDirectoryPreferences'

@Component
export struct WorkspacesPanel {
  @Prop colors: ThemeColors = themeColors()
  @Prop workspaces: DshWorkspace[] = []
  @Prop workingDir: string = ''
  @Prop @Watch('scopeChanged') hostScope: string = 'local'
  client: DshClient = new DshClient()
  onClose: () => void = () => {}
  onSelect: (id: string) => void = () => {}
  onBackHandler: (handler?: () => boolean) => void = () => {}
  @State private editing: boolean = false
  @State private picking: boolean = false
  @State private recentPaths: string[] = []
  @State private title: string = ''
  @State private working: boolean = false
  @State private error: string = ''
  @State private editingId: string = ''
  private active: boolean = false
  private pickerBack?: () => boolean
  private recentGeneration: number = 0

  aboutToAppear(): void {
    this.active = true
    this.onBackHandler(() => this.back())
    this.scopeChanged()
  }

  private scopeChanged(): void {
    if (!this.active) return
    const generation = ++this.recentGeneration
    this.recentPaths = []
    const context = this.getUIContext().getHostContext() as common.Context | undefined
    if (context) void loadRecentDirectories(context, this.hostScope).then((paths: string[]) => {
      if (this.active && generation === this.recentGeneration) this.recentPaths = paths
    })
  }

  aboutToDisappear(): void {
    this.active = false
    this.onBackHandler(undefined)
  }

  private back(): boolean {
    if (this.working) return true
    if (this.editing) { this.editing = false; return true }
    if (!this.picking) return false
    if (!this.pickerBack?.()) { this.picking = false; this.error = '' }
    return true
  }

  private async save(): Promise<void> {
    if (this.working) return
    this.working = true
    this.error = ''
    try {
      const result = await this.client.renameWorkspace(this.editingId, this.title.trim())
      if (result.id !== this.editingId) throw new Error('主机未确认工作区名称')
      this.editing = false
    } catch {
      this.error = this.editingId ? '无法保存工作区名称，请重试。' : '无法添加工作区，请检查目录是否存在并可访问。'
    } finally {
      this.working = false
    }
  }

  private async add(path: string): Promise<void> {
    if (this.working) return
    const connection = this.client.connectionIdentity()
    const scope = this.hostScope
    const context = this.getUIContext().getHostContext() as common.Context | undefined
    this.working = true
    this.error = ''
    try {
      const result = await this.client.createWorkspace(path)
      if (!result.id || !result.path) throw new Error('主机未确认工作区已添加')
      if (!this.active || connection !== this.client.connectionIdentity()) return
      const parent = directoryParent(result.path)
      if (parent) {
        this.recentGeneration++
        this.recentPaths = recentDirectoryPaths([parent].concat(this.recentPaths))
        if (context) void rememberRecentDirectory(context, scope, parent).catch(() => {})
      }
      this.picking = false
      this.onSelect(result.id)
    } catch (reason) {
      if (this.active && connection === this.client.connectionIdentity()) this.error = sessionActionError(reason, '没能添加工作区')
    } finally { if (this.active) this.working = false }
  }

  private async remove(id: string): Promise<void> {
    if (this.working) return
    this.working = true
    try { await this.client.deleteWorkspace(id) }
    catch { this.error = '无法移除工作区，请重试。' }
    finally { this.working = false }
  }

  @Builder
  private editor() {
    Column({ space: 16 }) {
      Text('重命名工作区').fontSize(22).fontColor(this.colors.text)
      TextInput({ text: this.title, placeholder: '工作区名称' }).maxLength(200)
        .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
        .onChange((value: string) => this.title = value)
      if (this.error) { Text(this.error).fontColor(this.colors.danger).fontSize(14) }
      Button(this.working ? '保存中…' : '保存').width('100%')
        .backgroundColor(this.colors.primary).fontColor(this.colors.onPrimary)
        .enabled(!this.working && this.title.trim().length > 0)
        .onClick(() => { void this.save() })
    }.padding(24).width('100%').backgroundColor(this.colors.surface)
  }

  @Builder
  private workspacesPage() {
    Column({ space: 18 }) {
      Row({ space: 12 }) {
        Button({ type: ButtonType.Circle }) {
          Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text)
        }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText('返回').onClick(this.onClose)
        Text('工作区').fontSize(23).fontWeight(FontWeight.Medium).fontColor(this.colors.text).layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          Text(DshGlyphs.add).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text)
        }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText('添加工作区')
          .onClick(() => { this.error = ''; this.picking = true })
      }.width('100%')
      if (this.error && !this.editing) { Text(this.error).fontSize(14).fontColor(this.colors.danger) }
      List({ space: 10 }) {
        if (this.workspaces.length === 0) {
          ListItem() {
            Column({ space: 8 }) {
              Text('还没有工作区').fontColor(this.colors.text).fontSize(16)
              Text('把常用的文件夹加进来').fontColor(this.colors.muted).fontSize(13)
              Button('添加工作区').fontColor(this.colors.onPrimary).backgroundColor(this.colors.primary)
                .onClick(() => { this.error = ''; this.picking = true })
            }.padding(24).width('100%')
          }
        }
        ForEach(this.workspaces, (item: DshWorkspace) => {
          ListItem() {
            Column({ space: 12 }) {
              Row({ space: 12 }) {
                Text(DshGlyphs.folder).fontFamily(DshGlyphs.family).fontSize(23).fontColor(this.colors.primary)
                Column({ space: 4 }) {
                  Text(item.title || item.path).fontSize(17).fontColor(this.colors.text)
                  Text(item.path).fontSize(13).fontColor(this.colors.muted).maxLines(2)
                  Text(`${item.sessionIds.length} 个对话`).fontSize(12).fontColor(this.colors.hint)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              }.width('100%').onClick(() => this.onSelect(item.id))
              Row({ space: 10 }) {
                Button('重命名').backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.primary)
                  .onClick(() => { this.editingId = item.id; this.title = item.title; this.error = ''; this.editing = true })
                Button('移除').backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.danger)
                  .enabled(!this.working).onClick(() => this.getUIContext().showAlertDialog({
                    title: `移除「${item.title || item.path}」？`, message: '文件夹和对话都会保留',
                    primaryButton: { value: '取消', action: () => {} },
                    secondaryButton: { value: '移除', action: () => { void this.remove(item.id) } }
                  }))
              }.width('100%')
            }.padding(18).borderRadius(18).backgroundColor(this.colors.surface)
          }
        }, (item: DshWorkspace) => `${item.id}|${item.path}|${item.title}|${item.sessionIds.length}`)
      }.layoutWeight(1).width('100%')
    }.padding(16).width('100%').height('100%').backgroundColor(this.colors.background)
      .bindSheet($$this.editing, this.editor(), { height: SheetSize.FIT_CONTENT, showClose: true })
  }

  build() {
    if (this.picking) {
      DirectoryPickerPanel({ colors: this.colors, client: this.client, workingDir: this.workingDir,
        titleText: '添加工作区', confirmLabel: '添加',
        onBackHandler: (handler?: () => boolean) => { this.pickerBack = handler },
        recentPaths: this.recentPaths, submitting: this.working, submitError: this.error,
        onClose: () => { this.picking = false; this.error = '' }, onPick: (path: string) => { void this.add(path) } })
    } else this.workspacesPage()
  }
}
