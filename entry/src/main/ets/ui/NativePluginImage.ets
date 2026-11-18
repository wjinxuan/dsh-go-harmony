import { localizedSettingsText } from './SettingsLocale'
import { image } from '@kit.ImageKit'
import { util } from '@kit.ArkTS'
import { window } from '@kit.ArkUI'
import { DshClient } from '../dsh/DshClient'
import { ThemeColors, themeColors } from './DshTheme'
import { boundedPan } from './AttachmentGalleryData'

@Component
export struct NativePluginImage {
  @StorageProp('dshLanguage') language: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.language) }
  @Prop colors: ThemeColors = themeColors()
  @Prop @Watch('load') source: string = ''
  @Prop description: string = ''
  @Prop @Watch('load') pkg: string = ''
  client?: DshClient
  @State private pixels: image.PixelMap | undefined = undefined
  @State private fullscreen: boolean = false
  @State private zoom: number = 1
  @State private offsetX: number = 0
  @State private offsetY: number = 0
  private zoomStart: number = 1
  private panX: number = 0
  private panY: number = 0
  private viewportWidth: number = 0
  private viewportHeight: number = 0
  private setTransform(zoom: number, x: number, y: number): void { this.zoom = Math.max(1, Math.min(8, zoom)); this.offsetX = boundedPan(x, this.viewportWidth, this.zoom); this.offsetY = boundedPan(y, this.viewportHeight, this.zoom) }
  private resetView(): void { this.zoom = 1; this.offsetX = 0; this.offsetY = 0 }
  @State private failed: boolean = false
  @State private safeInsets: Padding = { top: 0, right: 0, bottom: 0, left: 0 }
  private targetWindow: window.Window | undefined = undefined
  private avoidChanged: (options: window.AvoidAreaOptions) => void = (_options: window.AvoidAreaOptions): void => {
    this.updateSafeInsets()
  }
  private generation: number = 0
  aboutToAppear(): void {
    try {
      const name = this.getUIContext().getWindowName()
      if (name) {
        this.targetWindow = window.findWindow(name)
        this.updateSafeInsets()
        this.targetWindow.on('avoidAreaChange', this.avoidChanged)
      }
    } catch { /* The window may already be closing. */ }
    void this.load()
  }
  aboutToDisappear(): void {
    try { this.targetWindow?.off('avoidAreaChange', this.avoidChanged) } catch { /* The window may have closed. */ }
    this.targetWindow = undefined
    this.generation++; this.fullscreen = false; this.pixels?.release(); this.pixels = undefined
  }
  private updateSafeInsets(): void {
    const target = this.targetWindow
    if (!target) return
    let top = 0; let right = 0; let bottom = 0; let left = 0
    for (const type of [window.AvoidAreaType.TYPE_SYSTEM, window.AvoidAreaType.TYPE_CUTOUT,
      window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR]) {
      try {
        const area = target.getWindowAvoidArea(type)
        top = Math.max(top, area.topRect.height); right = Math.max(right, area.rightRect.width)
        bottom = Math.max(bottom, area.bottomRect.height); left = Math.max(left, area.leftRect.width)
      } catch { /* Some window types do not expose every avoid-area category. */ }
    }
    const ui = this.getUIContext()
    this.safeInsets = { top: ui.px2vp(top), right: ui.px2vp(right), bottom: ui.px2vp(bottom), left: ui.px2vp(left) }
  }
  private async load(): Promise<void> {
    const generation = ++this.generation; this.fullscreen = false; this.resetView(); this.failed = false; this.pixels?.release(); this.pixels = undefined
    let source: image.ImageSource | undefined
    try {
      let bytes: Uint8Array
      if (/^data:image\/(?:png|jpe?g|webp|gif);base64,/i.test(this.source) && this.source.length <= 65536) {
        bytes = new util.Base64Helper().decodeSync(this.source.slice(this.source.indexOf(',') + 1))
      } else if (this.client && /^(?:@[a-z0-9._~-]+\/)?[a-z0-9._~-]+$/.test(this.pkg) && this.source.length <= 512 &&
        /^asset:([A-Za-z0-9_~-][A-Za-z0-9._~-]*(\/[A-Za-z0-9_~-][A-Za-z0-9._~-]*)*)\.(png|jpe?g|webp|gif)$/i.test(this.source)) {
        bytes = await this.client.pluginAsset(this.pkg, this.source.slice(6), () => generation === this.generation)
      } else throw new Error('插件图片来源无效')
      source = image.createImageSource(bytes.buffer)
      const info = await source.getImageInfo()
      if (info.size.width > 4096 || info.size.height > 4096 || info.size.width * info.size.height > 4000000) throw new Error('插件图片过大')
      const pixels = await source.createPixelMap()
      if (generation !== this.generation) pixels.release(); else this.pixels = pixels
    } catch { if (generation === this.generation) this.failed = true }
    finally { source?.release() }
  }
  @Builder private viewer() {
    Column({ space: 8 }) {
      Row() { Button(this.t('返回')).onClick(() => { this.fullscreen = false }); Text(this.description).fontColor(this.colors.text).layoutWeight(1); Button(this.t('重置')).onClick(() => this.resetView()) }.height(56).padding({ left: 12, right: 12 }).width('100%')
      Stack() {
        if (this.pixels) Image(this.pixels).objectFit(ImageFit.Contain).width('100%').height('100%').scale({ x: this.zoom, y: this.zoom }).offset({ x: this.offsetX, y: this.offsetY }).accessibilityText(this.description)
          .gesture(GestureGroup(GestureMode.Parallel,
            PinchGesture().onActionStart(() => { this.zoomStart = this.zoom }).onActionUpdate((event: GestureEvent) => { this.setTransform(this.zoomStart * event.scale, this.offsetX, this.offsetY) }),
            PanGesture().onActionStart(() => { this.panX = this.offsetX; this.panY = this.offsetY }).onActionUpdate((event: GestureEvent) => { if (this.zoom > 1) this.setTransform(this.zoom, this.panX + event.offsetX, this.panY + event.offsetY) }),
            TapGesture({ count: 2 }).onAction(() => { if (this.zoom > 1) this.resetView(); else this.zoom = 2 })
          ))
      }.layoutWeight(1).width('100%').clip(true).onAreaChange((_old: Area, current: Area) => { this.viewportWidth = Number(current.width); this.viewportHeight = Number(current.height); this.setTransform(this.zoom, this.offsetX, this.offsetY) })
    }.width('100%').height('100%').safeAreaPadding(this.safeInsets).backgroundColor(this.colors.background)
  }
  build() {
    if (this.pixels) Image(this.pixels).objectFit(ImageFit.Contain).width('100%').constraintSize({ maxHeight: 320 }).accessibilityText(this.description).onClick(() => { this.resetView(); this.fullscreen = true })
      .bindContentCover($$this.fullscreen, this.viewer(), { modalTransition: ModalTransition.DEFAULT })
    else if (this.failed) Text(this.description || this.t('图片无法显示')).fontSize(13).fontColor(this.colors.muted)
    else LoadingProgress().width(24).height(24)
  }
}
