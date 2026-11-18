import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { DshClient, DshSession, DshWorkspace } from '../dsh/DshClient'
import { ThemeColors, themeColors, DshGlyphs } from './DshTheme'
import { SessionSearchPanel } from './SessionSearchPanel'
import { deletionOutcomeUnknown, sessionActionError, SessionDeletionGate } from './SessionManagementData'
import { common } from '@kit.AbilityKit'
import { WorkspaceViewPreferences, WorkspaceViewSection, workspaceViewPreferences, workspaceSections, workspaceDisplayTitle } from './WorkspaceViewData'
import { loadWorkspaceView, changeWorkspaceView } from './WorkspaceViewPreferences'

// Both drawer layouts and its search/archives share one recovery gate per connection.
const DELETION_GATES: WeakMap<DshClient, SessionDeletionGate> = new WeakMap()

@Component
export struct SessionsPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  client: DshClient = new DshClient()
  @Prop @Watch('searchRequested') searchRequest: number = 0
  @Prop excludedIds: string[] = []
  onSearchConsumed: () => void = () => {}
  private searchRequested(): void { if (this.active && this.searchRequest > 0) { this.section = 'search'; this.onSearchConsumed() } }
  @Prop sessions: DshSession[] = []
  @Prop workspaces: DshWorkspace[] = []
  @Prop workspaceId: string = ''
  @Prop selectedId: string = ''
  @Prop host: string = this.t("本机")
  @Prop @Watch('scopeChanged') hostScope: string = 'local'
  @Prop refreshing: boolean = false
  onSelect: (id: string, title: string) => void = () => {}
  onNew: () => void = () => {}
  onRefresh: () => void = () => {}
  onWorkspaceSelect: (id: string) => void = () => {}
  onSettings: () => void = () => {}
  onFeatures: () => void = () => {}
  onHost: () => void = () => {}
  onManageWorkspaces: () => void = () => {}
  onClose: () => void = () => {}
  onDeleted: (ids: string[]) => void = () => {}
  onBackHandler: (handler?: () => boolean) => void = () => {}
  @State private error: string = ''
  @State private working: boolean = false
  @State private editing: boolean = false
  @State private editingTitle: string = ''
  @State private section: string = ''
  @State private selecting: boolean = false
  @State private chosen: string[] = []
  @State private canDelete: boolean = false
  @State private deletionLocked: boolean = false
  @State private workspaceView: WorkspaceViewPreferences = workspaceViewPreferences()
  private workspaceGeneration: number = 0
  private editingId: string = ''
  private active: boolean = false
  private searchBack?: () => boolean
  private deletionGate: SessionDeletionGate = new SessionDeletionGate()

  aboutToAppear(): void {
    this.active = true
    this.scopeChanged()
    this.searchRequested()
    this.onBackHandler(() => this.back())
    const connection = this.client.connectionIdentity()
    const existing = DELETION_GATES.get(this.client)
    if (existing) this.deletionGate = existing
    else DELETION_GATES.set(this.client, this.deletionGate)
    this.deletionLocked = this.deletionGate.blocked(connection)
    void this.client.sessionDeletionAvailable().then((supported: boolean) => {
      if (this.active && connection === this.client.connectionIdentity()) this.canDelete = supported
    }).catch(() => {})
  }

  private scopeChanged(): void {
    if (!this.active) return
    const generation = ++this.workspaceGeneration
    this.workspaceView = workspaceViewPreferences()
    const context = this.getUIContext().getHostContext() as common.Context | undefined
    if (context) void loadWorkspaceView(context, this.hostScope).then((view: WorkspaceViewPreferences) => {
      if (this.active && generation === this.workspaceGeneration) this.workspaceView = view
    })
  }

  private setDeletionLock(locked: boolean, connection: number): void {
    if (locked) this.deletionGate.markUnknown(connection)
    else this.deletionGate.reconcile(connection)
    this.deletionLocked = this.deletionGate.blocked(this.client.connectionIdentity())
  }

  aboutToDisappear(): void {
    this.active = false
    this.onBackHandler(undefined)
  }

  private back(): boolean {
    if (this.working) return true
    if (this.editing) { this.editing = false; return true }
    if (this.section) {
      if (this.searchBack?.()) return true
      this.section = ''
      return true
    }
    if (this.selecting) { this.selecting = false; this.chosen = []; return true }
    return false
  }

  private visible(): DshSession[] {
    const workspace = this.workspaces.find((item: DshWorkspace) => item.id === this.workspaceId)
    return this.sessions.filter((item: DshSession) =>
      !workspace || workspace.sessionIds.includes(item.id))
      .sort((a: DshSession, b: DshSession) =>
        Number(b.pinned === true) - Number(a.pinned === true) || b.updatedAt - a.updatedAt)
  }

  private dateLabel(value: number): string {
    if (!value) return ''
    const date = new Date(value)
    const today = new Date()
    const midnight = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime()
    if (date.getTime() >= midnight) return this.t("今天")
    if (date.getTime() >= midnight - 86400000) return this.t("昨天")
    return this.f("{0}月{1}日", [date.getMonth() + 1, date.getDate()])
  }

  private workspaceOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: this.t("全部对话") }]
    workspaceSections(this.workspaces, this.workspaceView).forEach((section: WorkspaceViewSection) =>
      section.items.forEach((item: DshWorkspace) => options.push({ value: `${section.title ? `${section.title} · ` : ''}${workspaceDisplayTitle(item)}` })))
    return options
  }

  private workspaceRows(): DshWorkspace[] {
    const rows: DshWorkspace[] = []
    workspaceSections(this.workspaces, this.workspaceView).forEach((section: WorkspaceViewSection) => rows.push(...section.items))
    return rows
  }

  private async rename(): Promise<void> {
    const title = this.editingTitle.trim()
    if (!title || this.working) return
    this.working = true
    this.error = ''
    try {
      await this.client.renameSession(this.editingId, title)
      this.editing = false
      this.onRefresh()
    } catch {
      this.error = this.t("重命名失败，请重试。")
    } finally {
      this.working = false
    }
  }

  private async updateSelection(ids: string[], action: string, connection: number): Promise<void> {
    if (!this.active || this.working || !ids.length || connection !== this.client.connectionIdentity()) return
    if (action === 'delete' && !this.deletionGate.begin(connection)) return
    this.working = true
    this.error = ''
    const confirmed: string[] = []
    let failure = ''
    try {
      // Each pin is inserted at the head of the Host's pin list.
      const ordered = action === 'pin' ? ids.slice().reverse() : ids
      for (const id of ordered) {
        if (!this.active || connection !== this.client.connectionIdentity()) return
        try {
          if (action === 'delete') await this.client.deleteSessionPermanently(id)
          else if (action === 'archive') {
            if (!(await this.client.archiveSession(id, true)).includes(id)) throw new Error(this.t("主机未确认归档"))
          } else {
            const pinned = action === 'pin'
            const current = this.sessions.find((row: DshSession) => row.id === id)
            if (current && (current.pinned === true) === pinned) {
              confirmed.push(id)
              continue
            }
            if ((await this.client.pinSession(id, pinned)).includes(id) !== pinned) throw new Error(this.t("主机未确认置顶状态"))
          }
          confirmed.push(id)
        } catch (reason) {
          failure = sessionActionError(reason, this.t("主机未确认操作，请刷新对话列表后再操作。"))
          if (action !== 'delete' || deletionOutcomeUnknown(reason)) {
            if (action === 'delete') {
              this.setDeletionLock(true, connection)
              failure = this.t("删除结果未确认，请刷新对话列表后再操作。")
            }
            break
          }
        }
      }
      if (!this.active || connection !== this.client.connectionIdentity()) return
      if (failure) this.error = this.f("已完成 {0} 个，未完成 {1} 个。{2}", [confirmed.length, ids.length - confirmed.length, failure])
      this.chosen = action === 'delete' ? [] : this.chosen.filter((id: string) => !confirmed.includes(id))
      if (this.chosen.length === 0) this.selecting = false
      this.onRefresh()
      if (action === 'delete' && confirmed.length > 0) this.onDeleted(confirmed)
      if (action === 'archive' && confirmed.includes(this.selectedId)) this.onNew()
    } finally {
      if (action === 'delete') this.deletionGate.end(connection)
      if (this.active) {
        this.deletionLocked = this.deletionGate.blocked(this.client.connectionIdentity())
        this.working = false
      }
    }
  }

  private confirm(ids: string[], action: string): void {
    const connection = this.client.connectionIdentity()
    if (this.working || !ids.length || (action === 'delete' && (!this.canDelete || this.deletionGate.blocked(connection)))) return
    const deleting = action === 'delete'
    const row = this.sessions.find((session: DshSession) => session.id === ids[0])
    const noun = ids.length === 1 ? `「${row?.title || ids[0]}」` : this.f("{0} 个对话", [ids.length])
    this.getUIContext().showAlertDialog({
      title: `${deleting ? this.t("永久删除") : this.t("归档")}${noun}？`,
      message: deleting ? this.t("将从此主机永久删除所选对话记录，无法撤销。工作目录、生成的文件、分叉对话、共享附件和已发布的云端分享都会保留。") : this.t("进行中的一轮会停止。对话记录会保留。"),
      primaryButton: { value: this.t("取消"), action: () => {} },
      secondaryButton: { value: deleting ? this.t("永久删除") : this.t("归档"), fontColor: deleting ? this.colors.danger : this.colors.primary,
        action: () => { void this.updateSelection(ids, action, connection) } }
    })
  }

  private toggle(id: string): void {
    if (this.chosen.includes(id)) this.chosen = this.chosen.filter((value: string) => value !== id)
    else this.chosen = this.chosen.concat([id])
  }

  private chooseWorkspace(id: string): void {
    const context = this.getUIContext().getHostContext() as common.Context | undefined
    const generation = this.workspaceGeneration
    if (context) void changeWorkspaceView(context, this.hostScope, id, 'select').then((view: WorkspaceViewPreferences) => {
      if (this.active && generation === this.workspaceGeneration) this.workspaceView = view
    }).catch(() => { if (this.active) this.error = this.t("工作区选择未能保存，下次启动需重新选择。") })
    if (this.working) return
    this.chosen = []
    this.onWorkspaceSelect(id)
  }

  private pinnedSelection(): boolean {
    if (!this.chosen.length) return false
    return this.chosen.every((id: string) => this.sessions.some((item: DshSession) => item.id === id && item.pinned === true))
  }

  private async refresh(): Promise<void> {
    if (this.working) return
    const connection = this.client.connectionIdentity()
    if (!this.deletionGate.blocked(connection)) { this.onRefresh(); return }
    this.working = true
    try {
      await this.client.listSessions(true)
      if (!this.active || connection !== this.client.connectionIdentity()) return
      this.setDeletionLock(false, connection)
      this.error = ''
      this.onRefresh()
    } catch {
      if (this.active) this.error = this.t("没能核对删除结果，请刷新对话列表后再操作。")
    } finally { if (this.active) this.working = false }
  }

  @Builder
  private selectionActions() {
    Flex({ wrap: FlexWrap.Wrap }) {
      Button(this.chosen.length > 0 && this.chosen.length === this.visible().length ? this.t("取消全选") : this.t("全选")).fontSize(12)
        .backgroundColor(this.colors.surface).fontColor(this.colors.text).enabled(!this.working && this.visible().length > 0)
        .onClick(() => {
          this.chosen = this.chosen.length === this.visible().length ? [] : this.visible().map((item: DshSession) => item.id)
        })
      Button(this.pinnedSelection() ? this.t("取消置顶") : this.t("置顶")).fontSize(12).backgroundColor(this.colors.surface).fontColor(this.colors.primary)
        .enabled(!this.working && this.chosen.length > 0).onClick(() => {
          void this.updateSelection(this.chosen.slice(), this.pinnedSelection() ? 'unpin' : 'pin', this.client.connectionIdentity())
        })
      Button(this.t("归档")).fontSize(12).backgroundColor(this.colors.surface).fontColor(this.colors.primary)
        .enabled(!this.working && this.chosen.length > 0).onClick(() => this.confirm(this.chosen.slice(), 'archive'))
      if (this.canDelete) {
        Button(this.t("永久删除")).fontSize(12).backgroundColor(this.colors.surface).fontColor(this.colors.danger)
          .enabled(!this.working && !this.deletionLocked && this.chosen.length > 0).onClick(() => this.confirm(this.chosen.slice(), 'delete'))
      }
    }.width('100%')
  }

  @Builder
  private headerActions() {
    if (this.selecting) {
      Text(this.f("已选 {0} 个", [this.chosen.length])).fontSize(18).fontColor(this.colors.text).layoutWeight(1)
      Button(this.t("完成")).backgroundColor(this.colors.surface).fontColor(this.colors.primary).enabled(!this.working)
        .onClick(() => { this.selecting = false; this.chosen = [] })
    } else {
      Text($r('app.string.app_name')).fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.colors.text).layoutWeight(1)
      this.roundButton(DshGlyphs.add, this.t("新对话"), this.onNew)
      Button({ type: ButtonType.Circle }) {
        Text(DshGlyphs.more).fontFamily(DshGlyphs.family).fontSize(21).fontColor(this.colors.text)
      }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText(this.t("会话管理"))
        .enabled(!this.working).bindMenu(this.managementMenu())
      this.roundButton(DshGlyphs.close, this.t("关闭会话列表"), this.onClose)
    }
  }

  @Builder
  private managementMenu() {
    Menu() {
      MenuItem({ content: this.t("选择对话") }).onClick(() => { this.selecting = true; this.chosen = [] })
      MenuItem({ content: this.t("已归档") }).onClick(() => { this.section = 'archive' })
    }
  }

  @Builder
  private roundButton(glyph: string, label: string, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      Text(glyph).fontFamily(DshGlyphs.family).fontSize(21).fontColor(this.colors.text)
    }.width(44).height(44).backgroundColor(this.colors.surface)
      .accessibilityText(label).onClick(action)
  }

  @Builder
  private actions(item: DshSession) {
    Menu() {
      MenuItem({ content: item.pinned ? this.t("取消置顶") : this.t("置顶") }).onClick(() => {
        void this.updateSelection([item.id], item.pinned ? 'unpin' : 'pin', this.client.connectionIdentity())
      })
      MenuItem({ content: this.t("重命名") }).onClick(() => {
        this.editingId = item.id
        this.editingTitle = item.title
        this.error = ''
        this.editing = true
      })
      MenuItem({ content: this.t("归档") }).onClick(() => this.confirm([item.id], 'archive'))
      MenuItem({ content: this.t("选择对话") }).onClick(() => { this.selecting = true; this.chosen = [item.id] })
      if (this.canDelete) MenuItem({ content: this.t("永久删除") }).enabled(!this.deletionLocked).onClick(() => this.confirm([item.id], 'delete'))
    }
  }

  @Builder
  private renameSheet() {
    Column({ space: 18 }) {
      Text(this.t("重命名对话")).fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.colors.text)
      TextInput({ text: this.editingTitle, placeholder: this.t("对话名称") })
        .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).maxLength(200)
        .onChange((value: string) => this.editingTitle = value)
      if (this.error) { Text(this.t(this.error)).fontColor(this.colors.danger).fontSize(14) }
      Button(this.working ? this.t("保存中…") : this.t("保存")).width('100%')
        .backgroundColor(this.colors.primary).fontColor(this.colors.onPrimary)
        .enabled(!this.working && this.editingTitle.trim().length > 0)
        .onClick(() => { void this.rename() })
    }.width('100%').padding(24).backgroundColor(this.colors.surface)
  }

  @Builder
  private drawerContent() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        this.headerActions()
      }.width('100%').padding({ top: 8 })
      if (this.selecting) {
        this.selectionActions()
      } else {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 10 }) {
            Text(DshGlyphs.search).fontFamily(DshGlyphs.family).fontSize(18).fontColor(this.colors.muted)
            Text(this.t("搜索对话")).fontSize(15).fontColor(this.colors.muted)
            Blank()
          }.padding({ left: 14, right: 14 }).width('100%')
        }.height(44).width('100%').backgroundColor(this.colors.surface).borderRadius(22).accessibilityText(this.t("搜索对话"))
          .enabled(!this.working).onClick(() => { this.section = 'search' })
      }
      Row({ space: 8 }) {
        Select(this.workspaceOptions())
          .value(this.workspaces.find((item: DshWorkspace) => item.id === this.workspaceId)?.title || this.t("全部对话"))
          .fontColor(this.colors.text).backgroundColor(this.colors.surface).layoutWeight(1)
          .onSelect((index: number) => {
            if (index === 0) this.chooseWorkspace('')
            else if (this.workspaceRows()[index - 1]) this.chooseWorkspace(this.workspaceRows()[index - 1].id)
          })
        this.roundButton(DshGlyphs.folder, this.t("工作区"), this.onManageWorkspaces)
        this.roundButton(DshGlyphs.refresh, this.t("刷新对话"), () => { void this.refresh() })
      }.width('100%')
      if (this.error && !this.editing) {
        Text(this.t(this.error)).fontColor(this.colors.danger).fontSize(14).width('100%')
      }
      if (this.working && !this.editing) LoadingProgress().width(24).height(24).color(this.colors.primary)
      List({ space: 4 }) {
        if (this.visible().length === 0) {
          ListItem() {
            Column({ space: 12 }) {
              Text(this.refreshing ? this.t("正在加载对话…") : this.t("开始你的第一段对话"))
                .fontSize(16).fontColor(this.colors.muted)
              if (!this.refreshing) {
                Button(this.t("新对话")).backgroundColor(this.colors.primary).fontColor(this.colors.onPrimary)
                  .onClick(this.onNew)
              }
            }.width('100%').padding({ top: 56 })
          }
        }
        ForEach(this.visible(), (item: DshSession) => {
          ListItem() {
            Row({ space: 10 }) {
              if (this.selecting) {
                Checkbox({ name: item.id }).select(this.chosen.includes(item.id)).selectedColor(this.colors.primary)
                  .hitTestBehavior(HitTestMode.None)
              }
              if (item.pinned) {
                Text(DshGlyphs.pin).fontFamily(DshGlyphs.family).fontSize(16).fontColor(this.colors.primary)
              }
              Column({ space: 6 }) {
                Text(item.title || this.t("新对话")).fontSize(15).fontColor(this.colors.text)
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.dateLabel(item.updatedAt)).fontSize(12).fontColor(this.colors.muted)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              if (!this.selecting) {
                Button({ type: ButtonType.Circle }) {
                  Text(DshGlyphs.more).fontFamily(DshGlyphs.family).fontSize(21).fontColor(this.colors.muted)
                }.width(40).height(44).backgroundColor(Color.Transparent).accessibilityText(this.t("对话操作"))
                  .enabled(!this.working).bindMenu(this.actions(item))
              }
            }.width('100%').padding({ left: 14, right: 4, top: 10, bottom: 10 }).borderRadius(14)
              .backgroundColor(item.id === this.selectedId ? this.colors.primaryContainer : Color.Transparent)
              .onClick(() => {
                if (this.working) return
                if (this.selecting) this.toggle(item.id)
                else this.onSelect(item.id, item.title)
              })
              .bindContextMenu(this.actions(item), ResponseType.LongPress)
          }
        }, (item: DshSession) => `${item.id}|${item.title}|${item.pinned}|${item.updatedAt}`)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 8 }) {
            Text(DshGlyphs.host).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.text)
            Text(this.host).fontSize(14).fontColor(this.colors.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            Text('⌄').fontSize(16).fontColor(this.colors.muted)
          }.padding({ left: 12, right: 12 })
        }.height(44).borderRadius(22).backgroundColor(this.colors.surface).layoutWeight(1).onClick(this.onHost)
        this.roundButton(DshGlyphs.features, this.t("全部功能"), this.onFeatures)
        this.roundButton(DshGlyphs.settings, this.t("设置"), this.onSettings)
      }.width('100%').padding({ bottom: 8 })
    }.padding({ left: 16, right: 16 }).width('100%').height('100%').backgroundColor(this.colors.background)
      .bindSheet($$this.editing, this.renameSheet(), { height: SheetSize.FIT_CONTENT, showClose: true })
  }

  build() {
    if (this.section) {
      SessionSearchPanel({ excludedIds: this.excludedIds, colors: this.colors, client: this.client, host: this.host, archivedOnly: this.section === 'archive',
        deletionLocked: this.deletionLocked, beginDelete: (connection: number) => this.deletionGate.begin(connection),
        endDelete: (connection: number) => {
          this.deletionGate.end(connection)
          if (this.active) this.deletionLocked = this.deletionGate.blocked(this.client.connectionIdentity())
        },
        onDeletionLock: (locked: boolean, connection: number) => this.setDeletionLock(locked, connection),
        onBackHandler: (handler?: () => boolean) => { this.searchBack = handler },
        onClose: () => { this.section = '' }, onSelect: (id: string, title: string) => {
          this.section = ''; this.onSelect(id, title)
        }, onRestore: this.onRefresh, onDeleted: (ids: string[]) => {
          this.onRefresh(); this.onDeleted(ids)
        } })
    } else this.drawerContent()
  }
}
