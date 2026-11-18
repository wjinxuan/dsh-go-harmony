import { localizedSettingsText } from './SettingsLocale'
import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { fileIo, fileUri, picker } from '@kit.CoreFileKit'
import { PdfView, pdfViewManager, pdfService } from '@kit.PDFKit'
import { systemShare } from '@kit.ShareKit'
import { DshClient } from '../dsh/DshClient'
import { object, string, WireObject } from '../dsh/DshWire'
import { MediaItem } from '../dsh/MediaData'
import { cacheMediaFile, clearMediaFiles } from './MediaFiles'
import { MediaViewer } from './MediaViewer'
import { MessageBody } from './MessageBody'
import { artifactKind } from './SessionArtifacts'
import { ThemeColors, themeColors } from './DshTheme'

@Component
struct WorkspacePdfPreview {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  path: string = ''
  @Prop colors: ThemeColors = themeColors()
  @State private error: string = ''
  private controller: pdfViewManager.PdfController = new pdfViewManager.PdfController()
  private active: boolean = false
  aboutToDisappear(): void { this.active = false; this.controller.releaseDocument() }
  private async load(): Promise<void> {
    this.active = true
    try {
      const result = await this.controller.loadDocument(this.path)
      if (this.active && result !== pdfService.ParseResult.PARSE_SUCCESS) this.error = this.t("PDF 无法打开，可能已加密或文件损坏。")
    } catch { if (this.active) this.error = this.t("PDF 预览不可用，可保存或分享文件。") }
  }
  build() {
    Column({ space: 8 }) {
      if (this.error) Text(this.t(this.error)).fontColor(this.colors.danger).fontSize(14)
      PdfView({ controller: this.controller, pageLayout: pdfService.PageLayout.LAYOUT_SINGLE,
        isContinuous: true, showScroll: true, pageFit: pdfService.PageFit.FIT_WIDTH }).width('100%').layoutWeight(1)
        .onAppear(() => { void this.load() })
    }.width('100%').height('100%')
  }
}

@Component
export struct WorkspaceFileViewer {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  client: DshClient = new DshClient()
  sessionId: string = ''
  path: string = ''
  onClose: () => void = () => {}
  @State private text: string = ''
  @State private cachedPath: string = ''
  @State private pdfPath: string = ''
  @State private loading: boolean = false
  @State private working: boolean = false
  @State private eof: boolean = true
  @State private error: string = ''
  @State private notice: string = ''
  @State private media: MediaItem[] = []
  private active: boolean = false
  private generation: number = 0
  private connection: number = 0
  private textOffset: number = 1
  private version: string = ''
  private retained: string[] = []

  aboutToAppear(): void { this.active = true; this.connection = this.client.connectionIdentity(); void this.load() }
  aboutToDisappear(): void {
    this.active = false; this.generation++
    void clearMediaFiles([this.cachedPath, this.pdfPath].filter((path: string) => !!path && !this.retained.includes(path)))
  }
  private current(generation: number): boolean {
    return this.active && generation === this.generation && this.connection === this.client.connectionIdentity()
  }
  private async cached(generation: number): Promise<string> {
    if (this.cachedPath) return this.cachedPath
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    const path = await cacheMediaFile(this.client, this.sessionId, this.path, context.cacheDir, true, () => this.current(generation))
    if (!this.current(generation)) { await clearMediaFiles([path]); throw new Error(this.t("文件读取已取消")) }
    this.cachedPath = path; return path
  }
  private async load(): Promise<void> {
    const generation = ++this.generation; this.error = ''; this.loading = true
    const kind = artifactKind(this.path)
    try {
      if (kind === 'image' || kind === 'video') {
        this.media = [{ path: this.path, name: this.path.split(/[\\/]/).pop() || this.t("媒体"),
          mime: kind === 'video' ? 'video/mp4' : 'image/png', width: 0, height: 0, bytes: 0, duration: 0, poster: '', codec: '' }]
      } else if (kind === 'pdf') this.pdfPath = await this.cached(generation)
      else if (kind === 'audio') await this.cached(generation)
      else if (/\.(docx?|xlsx?|pptx?)$/i.test(this.path)) {
        const args: WireObject = { 'workspaceFileScopeId': this.sessionId, 'path': this.path, 'priority': 'foreground' }
        const response = object(await this.client.request('officeToPdf/render', args, 180000))
        if (!this.current(generation)) return
        const raw = response['data']
        const bytes = raw instanceof Uint8Array ? raw : typeof raw === 'string' ? new util.Base64Helper().decodeSync(raw) : undefined
        if (!bytes || bytes.length > 64 * 1024 * 1024 || bytes[0] !== 37 || bytes[1] !== 80 || bytes[2] !== 68 || bytes[3] !== 70) {
          throw new Error(this.t("主机没有返回有效的 PDF 预览"))
        }
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext
        const path = `${context.cacheDir}/dsh-media-${util.generateRandomUUID()}.pdf`
        const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY)
        try {
          if (await fileIo.write(file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer) !== bytes.byteLength) {
            throw new Error(this.t("PDF 预览未完整缓存"))
          }
        } catch (error) { await fileIo.unlink(path).catch(() => {}); throw error as Error }
        finally { await fileIo.close(file) }
        if (this.current(generation)) this.pdfPath = path; else await clearMediaFiles([path])
        if (Array.isArray(response['missingFonts']) && (response['missingFonts'] as Object[]).length) this.notice = this.t("主机缺少部分字体，排版可能不同。")
      } else if (!['archive', 'document', 'slides', 'spreadsheet', 'contact'].includes(kind) || /\.(csv|tsv)$/i.test(this.path)) {
        const result = await this.client.readWorkspaceText(this.sessionId, this.path, 1, 500)
        if (!this.current(generation)) return
        this.text = result.text; this.eof = result.eof; this.textOffset = result.offset + result.lines; this.version = result.version
      } else this.notice = this.t("可保存文件，或通过系统分享在其他应用中打开。")
    } catch { if (this.current(generation)) this.error = this.t("此文件无法直接预览。可重试，或保存、分享原文件。") }
    finally { if (this.current(generation)) this.loading = false }
  }
  private async more(): Promise<void> {
    if (this.loading || this.eof) return
    const generation = this.generation; this.loading = true; this.error = ''
    try {
      const result = await this.client.readWorkspaceText(this.sessionId, this.path, this.textOffset, 500)
      if (!this.current(generation)) return
      if (this.version && result.version && result.version !== this.version) throw new Error(this.t("文件已变化"))
      this.text += `${this.text && result.text ? '\n' : ''}${result.text}`
      this.eof = result.eof || result.lines === 0; this.textOffset = result.offset + result.lines
    } catch { if (this.current(generation)) this.error = this.t("无法继续读取，文件可能已变化。请重新打开。") }
    finally { if (this.current(generation)) this.loading = false }
  }
  private async exportFile(share: boolean): Promise<void> {
    if (this.working) return
    const generation = this.generation; this.working = true; this.notice = ''
    try {
      const path = await this.cached(generation); if (!this.current(generation)) return
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const name = this.path.split(/[\\/]/).pop() || this.t("文件"); const uri = fileUri.getUriFromPath(path)
      if (share) {
        const record: systemShare.SharedRecord = { utd: 'general.file', uri: uri, title: name }
        this.retained.push(path)
        await new systemShare.ShareController(new systemShare.SharedData(record)).show(context,
          { selectionMode: systemShare.SelectionMode.SINGLE, previewMode: systemShare.SharePreviewMode.DEFAULT })
      } else {
        const options = new picker.DocumentSaveOptions(); options.newFileNames = [name]
        const paths = await new picker.DocumentViewPicker(context).save(options)
        if (paths[0]) {
          const file = await fileIo.open(paths[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
          try {
            await fileIo.copyFile(path, file.fd)
            if ((await fileIo.stat(file.fd)).size !== (await fileIo.stat(path)).size) throw new Error(this.t("文件未完整保存"))
            await fileIo.fsync(file.fd)
          } finally { await fileIo.close(file) }
          if (this.current(generation)) this.notice = this.t("文件已保存")
        }
      }
    } catch { if (this.current(generation)) this.notice = share ? this.t("无法分享文件") : this.t("无法保存文件") }
    finally { if (this.current(generation)) this.working = false }
  }
  build() {
    if (this.media.length) {
      MediaViewer({ colors: this.colors, client: this.client, sessionId: this.sessionId, items: this.media, onClose: this.onClose })
    } else {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Button(this.t("返回")).fontColor(this.colors.primary).backgroundColor(this.colors.surface).onClick(this.onClose)
          Text(this.path.split(/[\\/]/).pop() || this.t("文件")).fontSize(18).fontColor(this.colors.text).maxLines(1).layoutWeight(1)
          Button(this.t("分享")).enabled(!this.working).onClick(() => { void this.exportFile(true) })
          Button(this.t("保存")).enabled(!this.working).onClick(() => { void this.exportFile(false) })
        }.width('100%')
        if (this.loading) LoadingProgress().width(26).height(26)
        if (this.error) {
          Text(this.t(this.error)).fontColor(this.colors.danger).fontSize(13)
          Button(this.t("重试预览")).enabled(!this.loading).onClick(() => { void this.load() })
        }
        if (this.notice) Text(this.notice).fontColor(this.colors.muted).fontSize(13)
        if (this.pdfPath) WorkspacePdfPreview({ colors: this.colors, path: this.pdfPath }).layoutWeight(1)
        else if (this.cachedPath && artifactKind(this.path) === 'audio') {
          Video({ src: fileUri.getUriFromPath(this.cachedPath) }).controls(true).autoPlay(false).width('100%').height(220)
            .onError(() => { this.notice = this.t("设备不支持此音频格式，可保存或分享后打开。") })
        } else {
          Scroll() {
            Column({ space: 10 }) {
              if (artifactKind(this.path) === 'markdown') MessageBody({ text: this.text, colors: this.colors })
              else Text(this.text).fontFamily('JetBrainsMono').fontSize(13).fontColor(this.colors.text)
                .copyOption(CopyOptions.LocalDevice).width('100%')
              if (!this.eof) Button(this.t("继续读取")).enabled(!this.loading).onClick(() => { void this.more() })
            }.width('100%')
          }.layoutWeight(1).width('100%').align(Alignment.TopStart)
        }
      }.width('100%').height('100%').padding(16).backgroundColor(this.colors.background)
    }
  }
}
