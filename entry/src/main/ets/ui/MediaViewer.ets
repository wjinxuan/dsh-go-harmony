import { localizedSettingsText } from './SettingsLocale'
import { common } from '@kit.AbilityKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { systemShare } from '@kit.ShareKit'
import { DshClient } from '../dsh/DshClient'
import { MediaItem } from '../dsh/MediaData'
import { AttachmentGallery } from './AttachmentGallery'
import { GalleryImage } from './AttachmentGalleryData'
import { cacheMediaFile, clearMediaFiles } from './MediaFiles'
import { ThemeColors, themeColors } from './DshTheme'

@Component
export struct MediaViewer {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  client: DshClient = new DshClient()
  sessionId: string = ''
  items: MediaItem[] = []
  initialIndex: number = 0
  onClose: () => void = () => {}
  @State private index: number = 0
  @State private gallery: GalleryImage[] = []
  @State private videoPath: string = ''
  @State private error: string = ''
  @State private notice: string = ''
  @State private loading: boolean = false
  @State private working: boolean = false
  private active: boolean = false
  private generation: number = 0
  private cached: string[] = []
  private retained: string[] = []

  aboutToAppear(): void {
    this.active = true; this.index = Math.max(0, Math.min(this.items.length - 1, this.initialIndex)); void this.load()
  }
  aboutToDisappear(): void {
    this.active = false; this.generation++
    void clearMediaFiles(this.cached.filter((path: string) => !this.retained.includes(path)))
  }
  private async load(): Promise<void> {
    const generation = ++this.generation; const connection = this.client.connectionIdentity()
    const current = (): boolean => this.active && generation === this.generation && connection === this.client.connectionIdentity()
    const item = this.items[this.index]; if (!item) { this.error = this.t("找不到媒体"); return }
    this.loading = true; this.error = ''; this.notice = ''; this.videoPath = ''; this.gallery = []
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    try {
      const video = item.mime.startsWith('video/') || /\.(mp4|mov|webm|m4v)$/i.test(item.path)
      const targets = video ? [item] : this.items.filter((i: MediaItem) => !i.mime.startsWith('video/'))
      const gallery: GalleryImage[] = []
      for (const target of targets) {
        const path = await cacheMediaFile(this.client, this.sessionId, target.path, context.cacheDir, video, current)
        if (!current()) { await clearMediaFiles([path]); return }
        this.cached.push(path)
        if (video) this.videoPath = path
        else gallery.push({ key: target.path, name: target.name, path: path })
      }
      if (current()) this.gallery = gallery
    } catch (error) { if (current()) this.error = error instanceof Error ? error.message : this.t("无法读取媒体文件") }
    finally { if (current()) this.loading = false }
  }
  private async exportVideo(share: boolean): Promise<void> {
    if (!this.videoPath || this.working) return
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    const path = this.videoPath; const generation = this.generation
    this.working = true; this.notice = ''
    try {
      const uri = fileUri.getUriFromPath(path)
      if (share) {
        const record: systemShare.SharedRecord = { utd: 'general.video', uri: uri, title: this.items[this.index]?.name || this.t("AI 生成视频") }
        this.retained.push(path)
        await new systemShare.ShareController(new systemShare.SharedData(record)).show(context,
          { selectionMode: systemShare.SelectionMode.SINGLE, previewMode: systemShare.SharePreviewMode.DEFAULT })
      } else {
        const config: photoAccessHelper.PhotoCreationConfig = { fileNameExtension: path.split('.').pop() || 'mp4', photoType: photoAccessHelper.PhotoType.VIDEO }
        const targets = await photoAccessHelper.getPhotoAccessHelper(context).showAssetsCreationDialog([uri], [config])
        if (targets[0]) {
          const output = await fileIo.open(targets[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
          try {
            await fileIo.copyFile(path, output.fd)
            if ((await fileIo.stat(path)).size !== (await fileIo.stat(output.fd)).size) throw new Error(this.t("视频未完整保存"))
            await fileIo.fsync(output.fd)
          } finally { await fileIo.close(output) }
          if (this.active && generation === this.generation) this.notice = this.t("已保存到相册")
        }
      }
    } catch { if (this.active && generation === this.generation) this.notice = share ? this.t("无法打开系统分享") : this.t("视频保存失败") }
    finally { if (this.active && generation === this.generation) this.working = false }
  }
  build() {
    if (this.gallery.length) {
      AttachmentGallery({ colors: this.colors, client: this.client, sessionId: this.sessionId, items: this.gallery,
        initialIndex: Math.max(0, this.gallery.findIndex((i: GalleryImage) => i.key === this.items[this.index]?.path)), onClose: this.onClose })
    } else {
      Column({ space: 14 }) {
        Row() {
          Button(this.t("返回")).fontColor(this.colors.primary).backgroundColor(this.colors.surface).onClick(this.onClose)
          Text(this.items[this.index]?.name || this.t("媒体")).fontColor(this.colors.text).fontSize(18).layoutWeight(1).maxLines(1)
        }.width('100%')
        if (this.loading) {
          LoadingProgress().width(30).height(30)
          Text(this.t("正在读取媒体…")).fontColor(this.colors.muted)
        } else if (this.error) {
          Text(this.t(this.error)).fontColor(this.colors.danger)
          Button(this.t("重试")).onClick(() => { void this.load() })
        } else if (this.videoPath) {
          Video({ src: fileUri.getUriFromPath(this.videoPath) }).width('100%').layoutWeight(1)
            .controls(true).autoPlay(false).objectFit(ImageFit.Contain)
            .onError(() => { this.notice = this.t("此设备无法播放该编码，可保存或分享后在其他播放器打开。") })
          Text(this.t("AI 生成")).fontColor(this.colors.muted).fontSize(13)
          Row({ space: 12 }) {
            Button(this.t("保存视频")).enabled(!this.working).onClick(() => { void this.exportVideo(false) })
            Button(this.t("分享视频")).enabled(!this.working).onClick(() => { void this.exportVideo(true) })
          }
        }
        if (this.notice) Text(this.notice).fontSize(13).fontColor(this.colors.muted)
      }.padding(16).width('100%').height('100%').backgroundColor(this.colors.surface)
    }
  }
}
