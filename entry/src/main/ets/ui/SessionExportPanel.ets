import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { fileIo, fileUri, picker } from '@kit.CoreFileKit'
import { systemShare } from '@kit.ShareKit'
import { DshClient, DshSubscription } from '../dsh/DshClient'
import { DshGlyphs, ThemeColors, themeColors } from './DshTheme'
import { isStaleExportFolder, sessionArchiveName, SESSION_ARCHIVE_UTD } from './SessionExportData'

async function clearExportFolder(path: string): Promise<void> {
  try { await fileIo.rmdir(path) } catch { /* The app cache may already have been cleared. */ }
}

async function clearExpiredExports(root: string): Promise<void> {
  const now = Date.now() / 1000
  try {
    const names = await fileIo.listFile(root)
    for (const name of names) {
      if (!/^export-[a-f0-9-]{36}$/i.test(name)) continue
      const path = `${root}/${name}`
      try {
        const stat = await fileIo.lstat(path)
        if (stat.isDirectory() && isStaleExportFolder(name, stat.mtime, now)) await clearExportFolder(path)
      } catch { /* One cache entry must not block another. */ }
    }
  } catch { /* The cache root is created on demand. */ }
}

async function writeArchive(sourcePath: string, targetUri: string): Promise<void> {
  const source = await fileIo.open(sourcePath, fileIo.OpenMode.READ_ONLY)
  try {
    const destination = await fileIo.open(targetUri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
    try {
      await fileIo.copyFile(source.fd, destination.fd)
      if ((await fileIo.stat(source.fd)).size !== (await fileIo.stat(destination.fd)).size) {
        throw new Error('导出的文件未完整写入')
      }
      await fileIo.fsync(destination.fd)
    } finally { await fileIo.close(destination) }
  } finally { await fileIo.close(source) }
}

@Component
export struct SessionExportPanel {
  @Prop colors: ThemeColors = themeColors()
  @Prop sessionId: string = ''
  client: DshClient = new DshClient()
  onClose: () => void = () => {}
  onBackHandler: (handler?: () => boolean) => void = () => {}
  @State private action: string = ''
  @State private stage: string = ''
  @State private cancelling: boolean = false
  @State private error: string = ''
  @State private notice: string = ''
  private active: boolean = false
  private cancelled: boolean = false
  private cancelDownload?: DshSubscription
  private shareController?: systemShare.ShareController
  private completed?: (result: systemShare.ShareOperationResult) => void
  private dismissed?: () => void

  aboutToAppear(): void {
    this.active = true
    this.onBackHandler(() => this.back())
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined
    if (context) void clearExpiredExports(`${context.cacheDir}/session-exports`)
  }

  aboutToDisappear(): void {
    this.active = false
    this.cancelled = true
    this.cancelDownload?.()
    this.releaseShareListeners()
    this.onBackHandler(undefined)
  }

  private back(): boolean {
    if (this.stage === 'download') {
      if (this.cancelling) return true
      this.cancelled = true
      this.cancelling = true
      this.cancelDownload?.()
      this.notice = '正在取消导出…'
      return true
    }
    return !!this.action
  }

  private releaseShareListeners(): void {
    const controller = this.shareController
    if (!controller) return
    if (this.completed) {
      try { controller.off('shareCompleted', this.completed) } catch { /* Older phones omit this event. */ }
    }
    if (this.dismissed) {
      try { controller.off('dismiss', this.dismissed) } catch { /* The panel may already be gone. */ }
    }
    this.shareController = undefined
    this.completed = undefined
    this.dismissed = undefined
  }

  private errorText(error: Object): string {
    const message = error instanceof Error ? error.message : ''
    if (/HTTP 404|session-export\/http-404|找不到这个对话/.test(message)) return '找不到这个对话了'
    if (/找不到会话或导出服务/.test(message)) return '主机上找不到对话或导出服务'
    if (/HTTP 401|HTTP 403/.test(message)) return '主机拒绝导出此对话'
    if (this.stage === 'save') return '没能写入所选文件，请检查文件位置后再试。'
    if (this.stage === 'share') return '没能打开系统分享面板。'
    if (this.stage === 'picker') return '没能打开文件保存窗口。'
    return '没能导出，请检查与当前主机的连接后再试。'
  }

  private async begin(action: string): Promise<void> {
    if (!this.active || this.action || !this.sessionId) return
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined
    if (!context) { this.error = '当前窗口无法导出对话'; return }
    const sessionId = this.sessionId
    const connection = this.client.connectionIdentity()
    const cache = `${context.cacheDir}/session-exports`
    const folder = `${cache}/export-${util.generateRandomUUID()}`
    this.releaseShareListeners()
    this.action = action
    this.stage = 'download'
    this.cancelled = false
    this.cancelling = false
    this.notice = ''
    this.error = ''
    let owned = false
    let handedOff = false
    try {
      const name = sessionArchiveName(sessionId)
      await fileIo.mkdir(folder, true)
      owned = true
      if (this.cancelled || !this.active) return
      const path = `${folder}/${name}`
      await this.client.exportSessionLog(sessionId, path, (cancel: DshSubscription) => {
        this.cancelDownload = cancel
        if (this.cancelled || !this.active) cancel()
      })
      this.cancelDownload = undefined
      if (this.cancelled || !this.active || sessionId !== this.sessionId || connection !== this.client.connectionIdentity()) return
      if (action === 'save') await this.save(context, path, name)
      else handedOff = await this.share(context, path, name)
    } catch (error) {
      if (this.active && !this.cancelled) this.error = this.errorText(error)
    } finally {
      if (owned && !handedOff) await clearExportFolder(folder)
      this.cancelDownload = undefined
      if (this.active) {
        if (this.cancelled) this.notice = '已取消导出'
        this.action = ''
        this.stage = ''
        this.cancelling = false
      }
    }
  }

  private async save(context: common.UIAbilityContext, path: string, name: string): Promise<void> {
    this.stage = 'picker'
    const options: picker.DocumentSaveOptions = { newFileNames: [name] }
    const destinations = await new picker.DocumentViewPicker(context).save(options)
    if (!destinations.length || !destinations[0]) {
      if (this.active) this.notice = '已取消保存'
      return
    }
    if (!this.active) return
    this.stage = 'save'
    await writeArchive(path, destinations[0])
    if (this.active) this.notice = '已保存对话日志'
  }

  private async share(context: common.UIAbilityContext, path: string, name: string): Promise<boolean> {
    this.stage = 'share'
    const record: systemShare.SharedRecord = { utd: SESSION_ARCHIVE_UTD, uri: fileUri.getUriFromPath(path), title: name }
    const controller = new systemShare.ShareController(new systemShare.SharedData(record))
    let completed = false
    let dismissed = false
    this.shareController = controller
    this.completed = (_result: systemShare.ShareOperationResult): void => {
      completed = true
      if (this.active && this.shareController === controller) this.notice = '系统已确认分享完成'
    }
    this.dismissed = (): void => {
      dismissed = true
      if (this.active && this.shareController === controller && !completed) this.notice = '分享面板已关闭'
    }
    try { controller.on('shareCompleted', this.completed) } catch { /* Completion is optional on older devices. */ }
    try { controller.on('dismiss', this.dismissed) } catch { /* Opening still works without dismiss events. */ }
    try {
      await controller.show(context, { selectionMode: systemShare.SelectionMode.SINGLE, previewMode: systemShare.SharePreviewMode.DEFAULT })
      if (this.active && !completed && !dismissed) this.notice = '已打开系统分享面板'
      // A receiver can still be opening the URI after dismiss/shareCompleted.
      // Keep handed-off archives in private cache until the next expiry sweep.
      return true
    } catch {
      if (completed || dismissed) return true
      this.releaseShareListeners()
      throw new Error('系统未能打开分享面板')
    }
  }

  @Builder
  private item(glyph: string, title: string, subtitle: string, action: string) {
    Row({ space: 14 }) {
      Text(glyph).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.primary)
      Column({ space: 4 }) {
        Text(title).fontSize(16).fontColor(this.colors.text).width('100%')
        Text(subtitle).fontSize(13).fontColor(this.colors.muted).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.action === action) LoadingProgress().width(22).height(22).color(this.colors.primary)
      else Text(DshGlyphs.disclosure).fontFamily(DshGlyphs.family).fontSize(14).fontColor(this.colors.hint)
    }.width('100%').padding(16).onClick(() => { void this.begin(action) })
      .enabled(!this.action && !!this.sessionId).accessibilityText(title)
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Button({ type: ButtonType.Circle }) {
          Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.text)
        }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText('返回')
          .enabled(!this.action || this.stage === 'download').onClick(() => { if (!this.back()) this.onClose() })
        Text('导出对话日志').fontSize(22).fontWeight(FontWeight.Medium).fontColor(this.colors.text).layoutWeight(1)
      }.width('100%')
      Text('打包成一个 ZIP，用于反馈或备份').fontSize(14).fontColor(this.colors.muted).width('100%')
      if (!this.sessionId) {
        Text('请先打开一个对话').fontSize(15).fontColor(this.colors.muted).width('100%').padding(16)
      } else {
        Column() {
          this.item(DshGlyphs.openExternal, '分享', '附在问题反馈里，或发给自己', 'share')
          Divider().color(this.colors.border)
          this.item(DshGlyphs.file, '保存到文件', '选择保存 ZIP 的位置', 'save')
        }.width('100%').backgroundColor(this.colors.surface).borderRadius(14)
        Text('含这个对话和子代理的全部记录与附件').fontSize(13).fontColor(this.colors.muted).width('100%')
      }
      if (this.stage === 'download' && this.action) {
        Button(this.cancelling ? '正在取消…' : '取消导出').fontColor(this.colors.primary)
          .backgroundColor(this.colors.surface).enabled(!this.cancelling).onClick(() => { this.back() })
      }
      if (this.notice) Text(this.notice).fontSize(14).fontColor(this.colors.muted).width('100%')
      if (this.error) Text(this.error).fontSize(14).fontColor(this.colors.danger).width('100%')
    }.width('100%').height('100%').padding(16).backgroundColor(this.colors.background)
  }
}
