import { DshClient, DshSession, DshSessionSearchHit } from '../dsh/DshClient'
import { DshGlyphs, ThemeColors, themeColors } from './DshTheme'
import { deletionOutcomeUnknown, searchSpans, SearchSpan, sessionActionError, sessionFolder, sessionSearchRows,
  SessionSearchResult } from './SessionManagementData'

const PAGE_SIZE: number = 12

@Component
export struct SessionSearchPanel {
  @Prop colors: ThemeColors = themeColors()
  @Prop host: string = '本机'
  @Prop archivedOnly: boolean = false
  @Prop deletionLocked: boolean = false
  client: DshClient = new DshClient()
  onClose: () => void = () => {}
  onSelect: (id: string, title: string) => void = () => {}
  onRestore: () => void = () => {}
  onDeleted: (ids: string[]) => void = () => {}
  beginDelete: (connection: number) => boolean = () => true
  endDelete: (connection: number) => void = () => {}
  onDeletionLock: (locked: boolean, connection: number) => void = () => {}
  onBackHandler: (handler?: () => boolean) => void = () => {}
  @State private sessions: DshSession[] = []
  @State private query: string = ''
  @State private hits: DshSessionSearchHit[] = []
  @State private hasMore: boolean = false
  @State private limit: number = PAGE_SIZE
  @State private loading: boolean = true
  @State private status: string = 'idle'
  @State private error: string = ''
  @State private busy: boolean = false
  @State private canDelete: boolean = false
  @State private selecting: boolean = false
  @State private chosen: string[] = []
  private searchVersion: number = 0
  private listVersion: number = 0
  private timer: number = -1
  private active: boolean = false
  private contentUnsupported: boolean = false
  private cancelSearch?: () => void

  aboutToAppear(): void {
    this.active = true
    this.onBackHandler(() => this.back())
    void this.reload()
  }

  aboutToDisappear(): void {
    this.active = false
    this.listVersion++
    this.retireSearch()
    this.onBackHandler(undefined)
  }

  private back(): boolean {
    if (this.busy) return true
    if (!this.selecting) return false
    this.selecting = false
    this.chosen = []
    return true
  }

  private retireSearch(): number {
    clearTimeout(this.timer)
    this.searchVersion++
    const cancel = this.cancelSearch
    this.cancelSearch = undefined
    cancel?.()
    return this.searchVersion
  }

  private async reload(): Promise<void> {
    const version = ++this.listVersion
    const connection = this.client.connectionIdentity()
    this.loading = true
    this.error = ''
    this.canDelete = false
    void this.client.sessionDeletionAvailable().then((supported: boolean) => {
      if (this.active && version === this.listVersion && connection === this.client.connectionIdentity()) this.canDelete = supported
    }).catch(() => {})
    try {
      const sessions = await this.client.listSessions(true)
      if (this.active && version === this.listVersion && connection === this.client.connectionIdentity()) this.sessions = sessions
    } catch (reason) {
      if (this.active && version === this.listVersion) this.error = sessionActionError(reason, '对话列表加载失败')
    } finally {
      if (this.active && version === this.listVersion) this.loading = false
    }
  }

  private updateQuery(value: string, composing: boolean = false): void {
    if (composing) {
      this.retireSearch()
      if (this.status === 'pending') this.status = 'idle'
      return
    }
    if (value !== this.query && this.selecting) this.chosen = []
    this.query = value
    this.limit = PAGE_SIZE
    this.hits = []
    this.hasMore = false
    const version = this.retireSearch()
    const query = value.trim()
    if (!query) { this.status = 'idle'; return }
    if (this.contentUnsupported) { this.status = 'unsupported'; return }
    this.status = 'pending'
    this.timer = setTimeout(() => { void this.search(query, version) }, 250)
  }

  private async search(query: string, version: number): Promise<void> {
    const connection = this.client.connectionIdentity()
    try {
      const value = await this.client.searchSessions(query, (cancel: () => void) => {
        if (this.active && version === this.searchVersion) this.cancelSearch = cancel
        else cancel()
      })
      if (!this.active || version !== this.searchVersion || connection !== this.client.connectionIdentity()) return
      this.hits = value.items
      this.hasMore = value.hasMore
      this.status = 'ready'
    } catch (reason) {
      if (!this.active || version !== this.searchVersion || connection !== this.client.connectionIdentity()) return
      const message = sessionActionError(reason, '')
      this.status = /gateway\/(method|service|lookup)-unavailable|HTTP (404|405|501)|搜索未启用|仅支持按标题搜索|search (is disabled|is unavailable)/i
        .test(message) ? 'unsupported' : 'failed'
      this.contentUnsupported = this.status === 'unsupported'
    } finally { if (version === this.searchVersion) this.cancelSearch = undefined }
  }

  private results(archived: boolean): SessionSearchResult[] {
    if ((!this.archivedOnly && !this.query.trim()) || (this.archivedOnly && !archived)) return []
    return sessionSearchRows(this.sessions, this.query, this.hits, this.archivedOnly)
      .filter((row: SessionSearchResult) => row.archived === archived)
  }

  private shown(archived: boolean): SessionSearchResult[] {
    return this.results(archived).slice(0, archived ? Math.max(0, this.limit - this.results(false).length) : this.limit)
  }

  private toggle(id: string): void {
    this.chosen = this.chosen.includes(id) ? this.chosen.filter((value: string) => value !== id) : this.chosen.concat([id])
  }

  private confirmRestore(item: SessionSearchResult): void {
    const connection = this.client.connectionIdentity()
    this.getUIContext().showAlertDialog({ title: item.title, message: '已归档的对话需先恢复，才能打开',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '恢复并打开', action: () => {
        if (connection === this.client.connectionIdentity()) void this.restore([item.id], item)
      } }
    })
  }

  private async restore(ids: string[], open?: SessionSearchResult): Promise<void> {
    if (!this.active || this.busy || !ids.length) return
    const connection = this.client.connectionIdentity()
    this.busy = true
    this.error = ''
    const restored: string[] = []
    try {
      for (const id of ids) {
        if (!this.active || connection !== this.client.connectionIdentity()) break
        try {
          if ((await this.client.restoreSession(id)).includes(id)) break
          restored.push(id)
        } catch { break }
      }
      if (!this.active || connection !== this.client.connectionIdentity()) return
      await this.reload()
      this.chosen = ids.filter((id: string) => !restored.includes(id))
      if (this.chosen.length === 0) this.selecting = false
      if (restored.length > 0) this.onRestore()
      if (restored.length < ids.length) this.error = `已恢复 ${restored.length} 个。其余未确认，请刷新后再操作。`
      if (open && restored.includes(open.id) && this.active) this.onSelect(open.id, open.title)
    } finally { if (this.active) this.busy = false }
  }

  private confirmDelete(ids: string[]): void {
    if (!this.canDelete || this.deletionLocked || this.busy || ids.length === 0) return
    const connection = this.client.connectionIdentity()
    const session = this.sessions.find((row: DshSession) => row.id === ids[0])
    this.getUIContext().showAlertDialog({ title: ids.length === 1 ? `永久删除「${session?.title || ids[0]}」？` :
      `永久删除 ${ids.length} 个对话？`,
      message: '将从此主机永久删除所选对话记录，无法撤销。工作目录、生成的文件、分叉对话、共享附件和已发布的云端分享都会保留。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '永久删除', fontColor: this.colors.danger, action: () => {
        if (this.active && connection === this.client.connectionIdentity()) void this.delete(ids, connection)
      } }
    })
  }

  private async delete(ids: string[], connection: number): Promise<void> {
    if (this.busy || this.deletionLocked || !this.active || connection !== this.client.connectionIdentity() ||
        !this.beginDelete(connection)) return
    this.busy = true
    const deleted: string[] = []
    let failure = ''
    try {
      for (const id of ids) {
        if (!this.active || connection !== this.client.connectionIdentity()) return
        try { await this.client.deleteSessionPermanently(id); deleted.push(id) }
        catch (reason) {
          failure = sessionActionError(reason, '删除结果未确认，请刷新对话列表后再操作。')
          if (deletionOutcomeUnknown(reason)) {
            this.onDeletionLock(true, connection)
            failure = '删除结果未确认，请刷新对话列表后再操作。'
            break
          }
        }
      }
      if (!this.active || connection !== this.client.connectionIdentity()) return
      await this.reload()
      this.chosen = []
      this.selecting = false
      this.error = failure ? `已删除 ${deleted.length} 个，未完成 ${ids.length - deleted.length} 个。${failure}` : ''
      if (deleted.length > 0) this.onDeleted(deleted)
    } finally {
      this.endDelete(connection)
      if (this.active) this.busy = false
    }
  }

  @Builder
  private highlighted(value: string, size: number, color: () => string, lines: number, excerpt: boolean) {
    Text() {
      ForEach(searchSpans(value, this.query, excerpt), (part: SearchSpan) => {
        Span(part.text).fontColor(part.highlighted ? this.colors.primary : color())
          .fontWeight(part.highlighted ? FontWeight.Medium : FontWeight.Normal)
      })
    }.fontSize(size).width('100%').maxLines(lines).textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  private result(row: SessionSearchResult) {
    Row({ space: 10 }) {
      if (this.selecting) {
        Checkbox({ name: row.id }).select(this.chosen.includes(row.id)).selectedColor(this.colors.primary)
          .hitTestBehavior(HitTestMode.None)
      }
      Column({ space: 5 }) {
        this.highlighted(row.title || '新对话', 16, () => this.colors.text, 1, false)
        if (row.cwd && this.showFolders()) this.highlighted(sessionFolder(row.cwd), 12, () => this.colors.hint, 1, false)
        if (row.snippet) this.highlighted(row.snippet, 13, () => this.colors.muted, 2, true)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (row.archived && !this.selecting) {
        Button({ type: ButtonType.Circle }) {
          Text(DshGlyphs.more).fontFamily(DshGlyphs.family).fontSize(18).fontColor(this.colors.muted)
        }.width(38).height(40).backgroundColor(Color.Transparent).accessibilityText('对话操作')
          .bindMenu(this.archivedMenu(row))
      }
    }.width('100%').padding(14).borderRadius(14).backgroundColor(this.colors.surface).onClick(() => {
      if (this.busy) return
      if (this.selecting) this.toggle(row.id)
      else if (row.archived) this.confirmRestore(row)
      else this.onSelect(row.id, row.title)
    })
  }

  private showFolders(): boolean {
    return new Set(this.sessions.map((row: DshSession) => sessionFolder(row.cwd))).size > 1
  }

  @Builder
  private archivedMenu(row: SessionSearchResult) {
    Menu() {
      MenuItem({ content: '恢复' }).onClick(() => { void this.restore([row.id]) })
      if (this.canDelete) MenuItem({ content: '永久删除' }).enabled(!this.deletionLocked).onClick(() => this.confirmDelete([row.id]))
    }
  }

  @Builder
  private batch() {
    Flex({ wrap: FlexWrap.Wrap }) {
      Text(`已选 ${this.chosen.length} 个`).fontColor(this.colors.muted).fontSize(13).padding(8)
      Button(this.chosen.length > 0 && this.chosen.length === this.results(true).length ? '取消全选' : '全选')
        .fontSize(12).fontColor(this.colors.text).backgroundColor(this.colors.surface).enabled(!this.busy && this.results(true).length > 0)
        .onClick(() => { this.chosen = this.chosen.length === this.results(true).length ? [] :
          this.results(true).map((row: SessionSearchResult) => row.id) })
      Button('恢复').fontSize(12).fontColor(this.colors.primary).backgroundColor(this.colors.surface).enabled(!this.busy && this.chosen.length > 0)
        .onClick(() => { void this.restore(this.chosen.slice()) })
      if (this.canDelete) {
        Button('永久删除').fontSize(12).fontColor(this.colors.danger).backgroundColor(this.colors.surface)
          .enabled(!this.busy && !this.deletionLocked && this.chosen.length > 0).onClick(() => this.confirmDelete(this.chosen.slice()))
      }
    }.width('100%')
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle }) {
          Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.text)
        }.height(44).width(44).backgroundColor(this.colors.surface).accessibilityText('返回').enabled(!this.busy)
          .onClick(() => { if (!this.back()) this.onClose() })
        Text(this.archivedOnly ? '已归档' : '搜索对话').fontSize(20).fontColor(this.colors.text).layoutWeight(1)
        if (this.archivedOnly) {
          Button(this.selecting ? '完成' : '选择对话').fontColor(this.colors.primary).backgroundColor(this.colors.surface)
            .enabled(!this.busy).onClick(() => { this.selecting = !this.selecting; this.chosen = [] })
        }
      }.width('100%')
      TextInput({ text: this.query, placeholder: this.archivedOnly ? '搜索已归档的对话' : `搜索「${this.host}」上的对话` })
        .height(44).maxLength(500).fontColor(this.colors.text).backgroundColor(this.colors.surface)
        .defaultFocus(!this.archivedOnly).enabled(!this.busy)
        .onChange((value: string, preview?: PreviewText) => this.updateQuery(value, !!preview?.value))
      if (this.selecting) this.batch()
      if (this.error) Text(this.error).fontSize(13).fontColor(this.colors.danger).width('100%')
      if (this.deletionLocked) {
        Button('刷新对话').fontColor(this.colors.primary).backgroundColor(this.colors.surface).enabled(!this.busy)
          .onClick(() => {
            const connection = this.client.connectionIdentity()
            void this.reload().then(() => {
              if (this.active && !this.error && connection === this.client.connectionIdentity()) this.onDeletionLock(false, connection)
            })
          })
      }
      if (this.loading || this.busy) LoadingProgress().width(24).height(24).color(this.colors.primary)
      if (this.error && this.sessions.length === 0) {
        Button('重试').backgroundColor(this.colors.surface).fontColor(this.colors.primary).onClick(() => { void this.reload() })
      }
      List({ space: 6 }) {
        if (!this.query.trim() && !this.archivedOnly) {
          ListItem() { Text('按标题和内容查找，含已归档的对话').fontSize(13).fontColor(this.colors.muted).padding(12) }
        }
        ForEach(this.shown(false), (row: SessionSearchResult) => {
          ListItem() { this.result(row) }
        }, (row: SessionSearchResult) => `${JSON.stringify(row)}|${this.query}`)
        if (this.shown(true).length > 0 && !this.archivedOnly) {
          ListItem() { Text('已归档').fontSize(13).fontColor(this.colors.muted).padding(8) }
        }
        ForEach(this.shown(true), (row: SessionSearchResult) => {
          ListItem() { this.result(row) }
        }, (row: SessionSearchResult) => `${JSON.stringify(row)}|${this.query}`)
        if (this.shown(false).length + this.shown(true).length < this.results(false).length + this.results(true).length) {
          ListItem() {
            Button('显示更多').fontColor(this.colors.primary).backgroundColor(this.colors.surface)
              .onClick(() => { this.limit += PAGE_SIZE })
          }
        }
        if (!this.loading && this.status !== 'pending' && !this.error && (this.query.trim() || this.archivedOnly) &&
            this.shown(false).length === 0 && this.shown(true).length === 0) {
          ListItem() { Text(this.query.trim() ? '没有相关对话' : '暂无对话').fontColor(this.colors.muted).padding(14) }
        }
        if (this.status === 'pending') {
          ListItem() { Text('正在搜索消息内容…').fontSize(13).fontColor(this.colors.muted).padding(10) }
        } else if (this.status === 'unsupported' && this.query.trim()) {
          ListItem() { Text('这台主机仅支持按标题搜索').fontSize(13).fontColor(this.colors.muted).padding(10) }
        } else if (this.status === 'failed') {
          ListItem() {
            Row({ space: 8 }) {
              Text('内容搜索失败，仅显示标题匹配').fontSize(13).fontColor(this.colors.muted).layoutWeight(1)
              Button('重试').fontColor(this.colors.primary).backgroundColor(this.colors.surface)
                .onClick(() => this.updateQuery(this.query))
            }.width('100%')
          }
        } else if (this.hasMore) {
          ListItem() { Text('内容匹配仅列出最相关的 20 个对话').fontSize(13).fontColor(this.colors.muted).padding(10) }
        }
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.padding(14).width('100%').height('100%').backgroundColor(this.colors.background)
  }
}
