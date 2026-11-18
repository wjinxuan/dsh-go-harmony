import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { systemShare } from '@kit.ShareKit'
import { DshClient, DshSubscription } from '../dsh/DshClient'
import { ThemeColors, themeColors } from './DshTheme'
import { boundedPan, fittedSize, GalleryImage, GalleryLoadQueue } from './AttachmentGalleryData'

const thumbnailQueue = new GalleryLoadQueue()

async function clearExpiredGalleryFiles(root: string): Promise<void> {
  const cutoff = Date.now() / 1000 - 86400
  const names = await fileIo.listFile(root).catch((): string[] => [])
  for (const name of names) {
    if (!/^dsh-gallery-[a-f0-9-]{36}\.(jpg|png|webp|gif)$/i.test(name)) continue
    const path = `${root}/${name}`
    try {
      const stat = await fileIo.lstat(path)
      if (stat.isFile() && stat.mtime < cutoff) await fileIo.unlink(path)
    } catch { /* Cache entries may have been cleared. */ }
  }
}

async function decodeImage(item: GalleryImage, client: DshClient, session: string, edge: number,
  current: () => boolean, setCancel: (cancel: DshSubscription) => void): Promise<image.PixelMap> {
  if (!current()) throw new Error('图片请求已取消')
  const source = item.path ? image.createImageSource(item.path) :
    item.reference ? image.createImageSource(await client.readSessionImage(session, item.reference, setCancel, current)) : undefined
  if (!source) throw new Error('找不到图片')
  try {
    if (!current()) throw new Error('图片请求已取消')
    const info = await source.getImageInfo()
    if (!current()) throw new Error('图片请求已取消')
    const size = fittedSize(info.size.width, info.size.height, edge)
    return await source.createPixelMap({ desiredSize: { width: size[0], height: size[1] } })
  } finally { await source.release().catch(() => {}) }
}

@Component
export struct AttachmentThumbnail {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  @Prop edge: number = 84
  @Prop item: GalleryImage = { key: '', name: '' }
  @Prop @Watch('reset') scope: string = ''
  sessionId: string = ''
  client: DshClient = new DshClient()
  onOpen: () => void = () => {}
  @State private picture: image.PixelMap | undefined = undefined
  @State private failed: boolean = false
  private visible: boolean = false
  private generation: number = 0
  private cancel?: DshSubscription

  aboutToDisappear(): void { this.visible = false; this.reset() }

  private reset(): void {
    this.generation++
    this.cancel?.()
    this.cancel = undefined
    const picture = this.picture
    this.picture = undefined
    this.failed = false
    if (picture) void picture.release().catch(() => {})
    if (this.visible) void this.load()
  }

  private async load(): Promise<void> {
    const generation = this.generation
    const connection = this.client.connectionIdentity()
    const current = (): boolean => this.visible && generation === this.generation && connection === this.client.connectionIdentity()
    try {
      const picture = await thumbnailQueue.run(current, () => decodeImage(this.item, this.client, this.sessionId, 420,
        current, (cancel: DshSubscription) => { if (current()) this.cancel = cancel; else cancel() }))
      if (current()) this.picture = picture
      else await picture.release()
    } catch { if (current()) this.failed = true }
    finally { if (current()) this.cancel = undefined }
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      if (this.picture) {
        Image(this.picture).width('100%').height('100%').objectFit(this.edge > 100 ? ImageFit.Contain : ImageFit.Cover)
      } else if (this.failed) {
        Text(this.t("查看图片")).fontSize(12).fontColor(this.colors.primary).maxLines(1)
      } else {
        LoadingProgress().width(18).height(18).color(this.colors.muted)
      }
    }.width(this.edge).height(this.edge).padding(0).borderRadius(12).clip(true)
      .backgroundColor(this.colors.surfaceAlt).accessibilityText(this.f("查看图片 {0}", [this.item.name])).onClick(this.onOpen)
      .onVisibleAreaChange([0.0], (visible: boolean) => {
        if (this.visible !== visible) { this.visible = visible; this.reset() }
      })
  }
}

@Component
export struct AttachmentGallery {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  items: GalleryImage[] = []
  initialIndex: number = 0
  sessionId: string = ''
  client: DshClient = new DshClient()
  onClose: () => void = () => {}
  @State private index: number = 0
  @State private picture: image.PixelMap | undefined = undefined
  @State private failure: string = ''
  @State private notice: string = ''
  @State private action: boolean = false
  @State private zoom: number = 1
  @State private x: number = 0
  @State private y: number = 0
  private viewportWidth: number = 0
  private viewportHeight: number = 0
  private startScale: number = 1
  private startX: number = 0
  private startY: number = 0
  private active: boolean = false
  private generation: number = 0
  private cancel?: DshSubscription

  aboutToAppear(): void {
    this.active = true
    this.index = Math.max(0, Math.min(this.items.length - 1, this.initialIndex))
    void this.load()
  }

  aboutToDisappear(): void { this.active = false; this.release() }

  private release(): void {
    this.generation++
    this.cancel?.()
    this.cancel = undefined
    const picture = this.picture
    this.picture = undefined
    if (picture) void picture.release().catch(() => {})
  }

  private async load(): Promise<void> {
    const item = this.items[this.index]
    this.release()
    this.failure = ''; this.notice = ''; this.zoom = 1; this.x = 0; this.y = 0
    if (!item) { this.failure = this.t("找不到图片。"); return }
    const generation = this.generation
    const connection = this.client.connectionIdentity()
    const current = (): boolean => this.active && generation === this.generation && connection === this.client.connectionIdentity()
    try {
      const picture = await decodeImage(item, this.client, this.sessionId, 2048, current,
        (cancel: DshSubscription) => { if (current()) this.cancel = cancel; else cancel() })
      if (current()) this.picture = picture
      else await picture.release()
    } catch { if (current()) this.failure = this.t("无法读取这张图片。") }
    finally { if (current()) this.cancel = undefined }
  }

  private turn(delta: number): void {
    const index = this.index + delta
    if (this.action || index < 0 || index >= this.items.length) return
    this.index = index
    void this.load()
  }

  private setTransform(scale: number, x: number, y: number): void {
    this.zoom = Math.min(8, Math.max(1, scale))
    this.x = boundedPan(x, this.viewportWidth, this.zoom)
    this.y = boundedPan(y, this.viewportHeight, this.zoom)
  }

  private async sendImage(share: boolean): Promise<void> {
    const item = this.items[this.index]
    if (!item || !this.picture || this.action) return
    const generation = this.generation
    const connection = this.client.connectionIdentity()
    const current = (): boolean => this.active && generation === this.generation && connection === this.client.connectionIdentity()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    this.action = true
    this.notice = ''
    let staged = ''
    let keep = false
    try {
      await clearExpiredGalleryFiles(context.cacheDir)
      const bytes = item.path ? undefined : item.reference ? await this.client.readSessionImage(this.sessionId, item.reference,
        (cancel: DshSubscription) => { if (current()) this.cancel = cancel; else cancel() }, current) : undefined
      if (!current()) return
      const source = item.path ? image.createImageSource(item.path) : bytes ? image.createImageSource(bytes) : undefined
      if (!source) throw new Error(this.t("图片不可用"))
      let format: string
      try { format = (await source.getImageInfo()).mimeType } finally { await source.release() }
      const extension = format === 'image/jpeg' ? 'jpg' : format === 'image/png' ? 'png' :
        format === 'image/webp' ? 'webp' : format === 'image/gif' ? 'gif' : ''
      if (!extension || !current()) throw new Error(this.t("不支持保存此图片格式"))
      staged = `${context.cacheDir}/dsh-gallery-${util.generateRandomUUID()}.${extension}`
      if (item.path) await fileIo.copyFile(item.path, staged)
      else if (bytes) {
        const file = await fileIo.open(staged, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY)
        try {
          if (await fileIo.write(file.fd, bytes) !== bytes.byteLength) throw new Error(this.t("图片未完整写入"))
        } finally { await fileIo.close(file) }
      }
      if (!current()) return
      const uri = fileUri.getUriFromPath(staged)
      if (share) {
        const record: systemShare.SharedRecord = { utd: 'general.image', uri: uri, title: item.name }
        await new systemShare.ShareController(new systemShare.SharedData(record)).show(context,
          { selectionMode: systemShare.SelectionMode.SINGLE, previewMode: systemShare.SharePreviewMode.DEFAULT })
        keep = true
      } else {
        const config: photoAccessHelper.PhotoCreationConfig = { fileNameExtension: extension,
          photoType: photoAccessHelper.PhotoType.IMAGE }
        const targets = await photoAccessHelper.getPhotoAccessHelper(context).showAssetsCreationDialog([uri], [config])
        if (targets[0]) {
          const target = await fileIo.open(targets[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
          try {
            await fileIo.copyFile(staged, target.fd)
            if ((await fileIo.stat(staged)).size !== (await fileIo.stat(target.fd)).size) throw new Error(this.t("图片未完整写入"))
            await fileIo.fsync(target.fd)
          } finally { await fileIo.close(target) }
          if (current()) this.notice = this.t("已保存到相册")
        }
      }
    } catch { if (current()) this.notice = share ? this.t("没能打开系统分享。") : this.t("没能保存图片。") }
    finally {
      if (staged && !keep) await fileIo.unlink(staged).catch(() => {})
      if (current()) { this.action = false; this.cancel = undefined }
    }
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Button(this.t("返回")).height(44).fontColor(this.colors.primary).backgroundColor(this.colors.surface)
          .onClick(this.onClose)
        Column({ space: 4 }) {
          Text(this.items[this.index]?.name || this.t("图片")).fontSize(17).fontColor(this.colors.text)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          if (this.items.length > 1) Text(`${this.index + 1} / ${this.items.length}`).fontSize(13).fontColor(this.colors.muted)
        }.layoutWeight(1)
      }.width('100%')
      Stack() {
        if (this.picture) {
          Image(this.picture).width('100%').height('100%').objectFit(ImageFit.Contain)
            .scale({ x: this.zoom, y: this.zoom }).translate({ x: this.x, y: this.y })
            .accessibilityText(this.items[this.index]?.name || this.t("图片"))
        } else if (this.failure) {
          Column({ space: 8 }) {
            Text(this.t(this.failure)).fontColor(this.colors.danger)
            Button(this.t("重试")).height(44).onClick(() => { void this.load() })
          }
        } else { LoadingProgress().width(32).height(32).color(this.colors.primary) }
      }.width('100%').layoutWeight(1).clip(true)
        .onAreaChange((_previous: Area, next: Area) => {
          this.viewportWidth = Number(next.width); this.viewportHeight = Number(next.height)
          this.setTransform(this.zoom, this.x, this.y)
        })
        .gesture(GestureGroup(GestureMode.Parallel,
          TapGesture({ count: 2 }).onAction(() => { if (this.picture) this.setTransform(this.zoom > 1 ? 1 : 2.5, 0, 0) }),
          PinchGesture({ fingers: 2 }).onActionStart(() => { this.startScale = this.zoom })
            .onActionUpdate((event: GestureEvent) => {
              if (this.picture) this.setTransform(this.startScale * event.scale, this.x, this.y)
            }),
          PanGesture({ fingers: 1, direction: PanDirection.All }).onActionStart(() => {
            this.startX = this.x; this.startY = this.y
          }).onActionUpdate((event: GestureEvent) => {
            if (this.zoom > 1) this.setTransform(this.zoom, this.startX + event.offsetX, this.startY + event.offsetY)
          }).onActionEnd((event: GestureEvent) => {
            if (this.zoom === 1 && Math.abs(event.offsetX) >= 42 && Math.abs(event.offsetX) > Math.abs(event.offsetY)) {
              this.turn(event.offsetX < 0 ? 1 : -1)
            }
          })))
      if (this.notice) Text(this.notice).fontSize(13).fontColor(this.colors.muted)
      Row({ space: 8 }) {
        if (this.items.length > 1) {
          Button(this.t("上一张")).height(44).enabled(this.index > 0 && !this.action).onClick(() => this.turn(-1))
          Button(this.t("下一张")).height(44).enabled(this.index + 1 < this.items.length && !this.action).onClick(() => this.turn(1))
        }
        Blank()
        Button(this.t("保存")).height(44).enabled(!!this.picture && !this.action).onClick(() => { void this.sendImage(false) })
        Button(this.t("分享")).height(44).enabled(!!this.picture && !this.action).onClick(() => { void this.sendImage(true) })
      }.width('100%')
    }.width('100%').height('100%').padding(12).backgroundColor(this.colors.background)
  }
}
