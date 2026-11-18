import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { common } from '@kit.AbilityKit'
import { DshClient, DshWorkspace } from '../dsh/DshClient'
import { ThemeColors, themeColors, DshGlyphs } from './DshTheme'
import { DirectoryPickerPanel } from './DirectoryPickerPanel'
import { directoryParent, recentDirectoryPaths, sessionActionError } from './SessionManagementData'
import { loadRecentDirectories, rememberRecentDirectory } from './WorkspaceDirectoryPreferences'
import { WorkspaceViewPreferences, WorkspaceViewSection, workspaceViewPreferences, workspaceSections,
  workspaceDisplayTitle, workspaceMoveRequest, workspaceMoveResult } from './WorkspaceViewData'
import { loadWorkspaceView, changeWorkspaceView } from './WorkspaceViewPreferences'

@Component
export struct WorkspacesPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  @Prop workspaces: DshWorkspace[] = []
  @Prop workingDir: string = ''
  @Prop @Watch('scopeChanged') hostScope: string = 'local'
  client: DshClient = new DshClient()
  onClose: () => void = () => {}
  onSelect: (id: string) => void = () => {}
  onNew: (id: string) => void = () => {}
  onBackHandler: (handler?: () => boolean) => void = () => {}
  @State private editing: boolean = false
  @State private picking: boolean = false
  @State private recentPaths: string[] = []
  @State private title: string = ''
  @State private working: boolean = false
  @State private error: string = ''
  @State private editingId: string = ''
  @State private groupEditing: boolean = false
  @State private groupName: string = ''
  @State private view: WorkspaceViewPreferences = workspaceViewPreferences()
  @State private order: string[] = []
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
    this.recentPaths = []; this.order = []; this.view = workspaceViewPreferences()
    this.editing = false; this.groupEditing = false; this.picking = false; this.working = false
    const context = this.getUIContext().getHostContext() as common.Context | undefined
    if (context) void loadRecentDirectories(context, this.hostScope).then((paths: string[]) => {
      if (this.active && generation === this.recentGeneration) this.recentPaths = paths
    })
    if (context) void loadWorkspaceView(context, this.hostScope).then((value: WorkspaceViewPreferences) => {
      if (this.active && generation === this.recentGeneration) this.view = value
    })
  }

  aboutToDisappear(): void {
    this.active = false
    this.onBackHandler(undefined)
  }

  private back(): boolean {
    if (this.working) return true
    if (this.groupEditing) { this.groupEditing = false; this.editing = false; return true }
    if (this.editing) { this.editing = false; return true }
    if (!this.picking) return false
    if (!this.pickerBack?.()) { this.picking = false; this.error = '' }
    return true
  }

  private async save(): Promise<void> {
    if (this.working) return
    const connection = this.client.connectionIdentity()
    const id = this.editingId
    this.working = true
    this.error = ''
    try {
      const result = await this.client.renameWorkspace(id, this.title.trim())
      if (!this.active || connection !== this.client.connectionIdentity()) return
      if (result.id !== id) throw new Error(this.t("主机未确认工作区名称"))
      this.editing = false
    } catch {
      if (!this.active || connection !== this.client.connectionIdentity()) return
      this.error = this.editingId ? this.t("无法保存工作区名称，请重试。") : this.t("无法添加工作区，请检查目录是否存在并可访问。")
    } finally {
      if (this.active && connection === this.client.connectionIdentity()) this.working = false
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
      if (!result.id || !result.path) throw new Error(this.t("主机未确认工作区已添加"))
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
      if (this.active && connection === this.client.connectionIdentity()) this.error = sessionActionError(reason, this.t("没能添加工作区"))
    } finally { if (this.active && connection === this.client.connectionIdentity()) this.working = false }
  }

  private async remove(id: string): Promise<void> {
    if (this.working) return
    this.working = true
    const connection = this.client.connectionIdentity(), scope = this.hostScope
    const context = this.getUIContext().getHostContext() as common.Context | undefined
    try {
      await this.client.deleteWorkspace(id)
      if (!this.active || connection !== this.client.connectionIdentity()) return
      if (context) { const view = await changeWorkspaceView(context, scope, id, 'forget'); if (this.active && connection === this.client.connectionIdentity() && scope === this.hostScope) this.view = view }
    }
    catch { if (this.active && connection === this.client.connectionIdentity()) this.error = this.t("无法移除工作区，请重试。") }
    finally { if (this.active && connection === this.client.connectionIdentity()) this.working = false }
  }

  private ordered(): DshWorkspace[] {
    if (!this.order.length) return this.workspaces
    const first: DshWorkspace[] = []
    for (const id of this.order) {
      const workspace = this.workspaces.find((row: DshWorkspace) => row.id === id)
      if (workspace) first.push(workspace)
    }
    return first.concat(this.workspaces.filter((workspace: DshWorkspace) => !this.order.includes(workspace.id)))
  }

  private sectionItems(kind: string, title: string): DshWorkspace[] {
    return workspaceSections(this.ordered(), this.view)
      .find((section: WorkspaceViewSection) => section.kind === kind && section.title === title)?.items || []
  }

  private async preference(id: string, action: string, value: string = ''): Promise<void> {
    if (this.working) return
    const context = this.getUIContext().getHostContext() as common.Context | undefined
    if (!context) return
    const scope = this.hostScope, connection = this.client.connectionIdentity()
    this.working = true; this.error = ''
    try {
      const view = await changeWorkspaceView(context, scope, id, action, value)
      if (!this.active || connection !== this.client.connectionIdentity() || scope !== this.hostScope) return
      this.view = view; this.groupEditing = false; this.editing = false
      if (action === 'select') this.onSelect(id)
    } catch { if (this.active && connection === this.client.connectionIdentity()) this.error = this.t("工作区偏好未能保存，请重试。") }
    finally { if (this.active && connection === this.client.connectionIdentity()) this.working = false }
  }

  private async move(id: string, direction: number): Promise<void> {
    if (this.working) return
    const connection = this.client.connectionIdentity(), ids = this.ordered().map((workspace: DshWorkspace) => workspace.id)
    this.working = true; this.error = ''
    try {
      const result = await this.client.request('workspace/insertBefore', workspaceMoveRequest(ids, id, direction))
      if (!this.active || connection !== this.client.connectionIdentity()) return
      this.order = workspaceMoveResult(result, ids, id, direction)
    } catch (reason) { if (this.active && connection === this.client.connectionIdentity()) this.error = sessionActionError(reason, this.t("工作区排序未能保存。")) }
    finally { if (this.active && connection === this.client.connectionIdentity()) this.working = false }
  }

  @Builder
  private groupEditor() {
    Column({ space: 12 }) {
      Text(this.t("工作区分组")).fontSize(22).fontColor(this.colors.text)
      TextInput({ text: this.groupName, placeholder: this.t("新分组名称，留空取消分组") }).maxLength(200)
        .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).onChange((value: string) => { this.groupName = value })
      ForEach(Array.from(new Set(Object.values(this.view.groups))), (group: string) => {
        Button(group).width('100%').enabled(!this.working).onClick(() => { void this.preference(this.editingId, 'group', group) })
      }, (group: string) => group)
      if (this.error) Text(this.t(this.error)).fontColor(this.colors.danger)
      Button(this.t("保存分组")).width('100%').enabled(!this.working).onClick(() => { void this.preference(this.editingId, 'group', this.groupName) })
      Button(this.t("不分组")).width('100%').enabled(!this.working).onClick(() => { void this.preference(this.editingId, 'group') })
    }.padding(24).width('100%').backgroundColor(this.colors.surface)
  }

  @Builder
  private workspaceRow(item: DshWorkspace) {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Text(DshGlyphs.folder).fontFamily(DshGlyphs.family).fontSize(23).fontColor(this.colors.primary)
        Column({ space: 4 }) {
          Text(workspaceDisplayTitle(item)).fontSize(17).fontColor(this.colors.text)
          Text(item.path).fontSize(13).fontColor(this.colors.muted).maxLines(2)
          Text(this.f("{0} 个对话", [item.sessionIds.length])).fontSize(12).fontColor(this.colors.hint)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%').enabled(!this.working).onClick(() => { void this.preference(item.id, 'select') })
      Flex({ wrap: FlexWrap.Wrap }) {
        Button(this.t("新对话")).backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.primary).margin(3)
          .enabled(!this.working).onClick(() => this.onNew(item.id))
        Button(this.view.pinned.includes(item.id) ? this.t("取消置顶") : this.t("置顶")).backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.primary).margin(3)
          .enabled(!this.working).onClick(() => { void this.preference(item.id, this.view.pinned.includes(item.id) ? 'unpin' : 'pin') })
        Button(this.t("分组")).backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.primary).margin(3).enabled(!this.working)
          .onClick(() => { this.editingId = item.id; this.groupName = this.view.groups[item.id] || ''; this.error = ''; this.groupEditing = true; this.editing = true })
        Button(this.t("重命名")).backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.primary).margin(3).enabled(!this.working)
          .onClick(() => { this.editingId = item.id; this.title = item.title; this.error = ''; this.groupEditing = false; this.editing = true })
        Button(this.t("上移")).backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.primary).margin(3)
          .enabled(!this.working && this.ordered()[0]?.id !== item.id).onClick(() => { void this.move(item.id, -1) })
        Button(this.t("下移")).backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.primary).margin(3)
          .enabled(!this.working && this.ordered()[this.ordered().length - 1]?.id !== item.id).onClick(() => { void this.move(item.id, 1) })
        Button(this.t("移除")).backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.danger).margin(3).enabled(!this.working)
          .onClick(() => this.getUIContext().showAlertDialog({
            title: this.f("移除「{0}」？", [workspaceDisplayTitle(item)]), message: this.t("文件夹和对话都会保留"),
            primaryButton: { value: this.t("取消"), action: () => {} },
            secondaryButton: { value: this.t("移除"), action: () => { void this.remove(item.id) } }
          }))
      }.width('100%')
    }.padding(18).borderRadius(18).backgroundColor(this.colors.surface)
  }

  @Builder
  private editor() {
    Column({ space: 16 }) {
      Text(this.t("重命名工作区")).fontSize(22).fontColor(this.colors.text)
      TextInput({ text: this.title, placeholder: this.t("工作区名称") }).maxLength(200)
        .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
        .onChange((value: string) => this.title = value)
      if (this.error) { Text(this.t(this.error)).fontColor(this.colors.danger).fontSize(14) }
      Button(this.working ? this.t("保存中…") : this.t("保存")).width('100%')
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
        }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText(this.t("返回")).onClick(this.onClose)
        Text(this.t("工作区")).fontSize(23).fontWeight(FontWeight.Medium).fontColor(this.colors.text).layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          Text(DshGlyphs.add).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text)
        }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText(this.t("添加工作区"))
          .onClick(() => { this.error = ''; this.picking = true })
      }.width('100%')
      if (this.error && !this.editing) { Text(this.t(this.error)).fontSize(14).fontColor(this.colors.danger) }
      List({ space: 10 }) {
        if (this.workspaces.length === 0) {
          ListItem() {
            Column({ space: 8 }) {
              Text(this.t("还没有工作区")).fontColor(this.colors.text).fontSize(16)
              Text(this.t("把常用的文件夹加进来")).fontColor(this.colors.muted).fontSize(13)
              Button(this.t("添加工作区")).fontColor(this.colors.onPrimary).backgroundColor(this.colors.primary)
                .onClick(() => { this.error = ''; this.picking = true })
            }.padding(24).width('100%')
          }
        }
        ForEach(workspaceSections(this.ordered(), this.view), (section: WorkspaceViewSection) => {
          ListItemGroup({ header: this.sectionTitle(section.title) }) {
            ForEach(this.sectionItems(section.kind, section.title), (item: DshWorkspace) => {
              ListItem() { this.workspaceRow(item) }
            }, (item: DshWorkspace) => `${item.id}|${item.path}|${item.title}|${item.sessionIds.length}`)
          }
        }, (section: WorkspaceViewSection) => `${section.kind}|${section.title}`)
      }.layoutWeight(1).width('100%')
    }.padding(16).width('100%').height('100%').backgroundColor(this.colors.background)
      .bindSheet($$this.editing, this.activeEditor(), { height: SheetSize.FIT_CONTENT, showClose: true })
  }

  @Builder
  private activeEditor() {
    if (this.groupEditing) this.groupEditor()
    else this.editor()
  }

  @Builder
  private sectionTitle(title: string) {
    if (title) Text(title).fontSize(14).fontColor(this.colors.muted).width('100%').padding({ top: 12, bottom: 8 })
  }

  build() {
    if (this.picking) {
      DirectoryPickerPanel({ colors: this.colors, client: this.client, workingDir: this.workingDir,
        titleText: this.t("添加工作区"), confirmLabel: this.t("添加"),
        onBackHandler: (handler?: () => boolean) => { this.pickerBack = handler },
        recentPaths: this.recentPaths, submitting: this.working, submitError: this.error,
        onClose: () => { this.picking = false; this.error = '' }, onPick: (path: string) => { void this.add(path) } })
    } else this.workspacesPage()
  }
}
