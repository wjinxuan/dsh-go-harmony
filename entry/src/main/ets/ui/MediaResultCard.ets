import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { DshClient, DshSubscription } from '../dsh/DshClient'
import { string, WireObject } from '../dsh/DshWire'
import { MediaItem, MediaMeta } from '../dsh/MediaData'
import { AttachmentThumbnail } from './AttachmentGallery'
import { GalleryLoadQueue } from './AttachmentGalleryData'
import { cacheMediaFile, clearMediaFiles } from './MediaFiles'
import { ThemeColors, themeColors } from './DshTheme'
import { jobLive, jobStatus } from './EngineFeatureData'

const mediaThumbnailQueue = new GalleryLoadQueue()

@Component
export struct MediaResultCard {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  client: DshClient = new DshClient()
  @Prop @Watch('reset') sessionId: string = ''
  @Prop @Watch('reset') meta: MediaMeta = { kind: 'image', status: 'done', rid: '', job: '', items: [], request: {},
    prompt: '', revisedPrompt: '', error: {}, cost: {} }
  onOpen: (items: MediaItem[], index: number) => void = () => {}
  onRegenerate: (meta: MediaMeta) => void = () => {}
  onSettings: () => void = () => {}
  @State private paths: string[] = []
  @State private progress: string = ''
  @State private jobState: string = ''
  @State private error: string = ''
  @State private cancelling: boolean = false
  private active: boolean = false
  private visible: boolean = false
  private generation: number = 0
  private stop?: DshSubscription

  aboutToAppear(): void { this.active = true; this.reset() }
  aboutToDisappear(): void { this.active = false; this.visible = false; this.reset() }
  private reset(): void {
    const paths = this.paths; this.paths = []; void clearMediaFiles(paths.filter((path: string) => !!path))
    this.generation++; this.stop?.(); this.stop = undefined; this.progress = ''; this.jobState = ''; this.error = ''; this.cancelling = false
    if (this.active && this.meta.status === 'running' && this.meta.job) void this.watchJob()
    if (this.active && this.visible) void this.load()
  }
  private async watchJob(): Promise<void> {
    const generation = this.generation; const connection = this.client.connectionIdentity()
    const sessionId = this.sessionId; const jobId = this.meta.job
    const current = (): boolean => this.active && generation === this.generation && connection === this.client.connectionIdentity() &&
      sessionId === this.sessionId && jobId === this.meta.job
    try {
      const stop = await this.client.watchJobs(sessionId, (jobs: WireObject[]) => {
        if (!current()) return
        const job = jobs.find((j: WireObject) => string(j['id']) === jobId)
        if (!job || !['running', 'stopping', 'completed', 'killed', 'failed'].includes(string(job['status']))) return
        if (this.jobState === 'stopping' && job['status'] === 'running') return
        if (this.jobFinished() && (this.jobState !== 'ended' || jobLive(job))) return
        this.jobState = string(job['status'])
        this.progress = jobLive(job) ? string(job['progress']) : ''
        if (this.jobFinished()) { this.cancelling = false; this.stop?.(); this.stop = undefined }
      }, () => {})
      if (current() && !this.jobFinished()) this.stop = stop; else stop()
    } catch { /* The tool result still provides authoritative generation state. */ }
  }
  private jobFinished(): boolean {
    return ['completed', 'killed', 'failed', 'ended'].includes(this.jobState)
  }
  private jobProgress(): string {
    if (this.jobState === 'ended') return this.t("任务已结束，等待结果更新")
    const job: WireObject = { 'status': this.jobState }
    return this.jobFinished() || this.jobState === 'stopping' ? this.t(jobStatus(job)) : this.progress || this.t("生成中…")
  }
  private async load(): Promise<void> {
    const generation = this.generation; const connection = this.client.connectionIdentity()
    const current = (): boolean => this.active && this.visible && generation === this.generation && connection === this.client.connectionIdentity()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    for (let index = 0; index < this.meta.items.length; index++) {
      const item = this.meta.items[index]; const remote = item.mime.startsWith('video/') || this.meta.kind === 'video' ? item.poster : item.path
      if (!remote || this.paths[index]) continue
      try {
        const path = await mediaThumbnailQueue.run(current, () => cacheMediaFile(this.client, this.sessionId, remote, context.cacheDir, false, current))
        if (!current()) { await clearMediaFiles([path]); return }
        const paths = this.paths.slice(); paths[index] = path; this.paths = paths
      } catch { if (current()) this.error = this.t("预览读取失败，点按结果可重试。") }
    }
  }
  private async cancel(): Promise<void> {
    if (!this.active || this.meta.status !== 'running' || !this.meta.job || this.cancelling || this.jobFinished() || this.jobState === 'stopping') return
    const generation = this.generation; const connection = this.client.connectionIdentity()
    const sessionId = this.sessionId; const jobId = this.meta.job
    const current = (): boolean => this.active && generation === this.generation && connection === this.client.connectionIdentity() &&
      sessionId === this.sessionId && jobId === this.meta.job
    this.cancelling = true; this.error = ''
    try {
      const cancelled = await this.client.killJob(sessionId, jobId)
      if (current() && !this.jobFinished()) {
        // already-finished proves termination, but does not identify its outcome.
        this.jobState = cancelled ? 'stopping' : 'ended'
        this.progress = ''
      }
    } catch { if (current() && !this.jobFinished()) this.error = this.t("取消失败，请重试。") }
    finally { if (current()) this.cancelling = false }
  }
  private failure(): string {
    const code = string(this.meta.error['code'])
    const messages: Record<string, string> = { 'cancelled': this.t("已取消生成"), 'policy': this.t("内容未通过服务商审核，请修改描述"),
      'policy-input': this.t("描述未通过服务商审核"), 'policy-output': this.t("生成结果未通过服务商审核"), 'auth': this.t("API Key 无效，请检查服务设置"),
      'unauthorized': this.t("API Key 无效，请检查服务设置"), 'balance': this.t("服务余额不足"), 'quota': this.t("已达到服务额度"),
      'daily-limit': this.t("已达到今日额度"), 'expired': this.t("生成任务已过期"), 'unavailable': this.t("媒体服务暂时不可用") }
    return messages[code] || this.t("生成失败，请重试或检查服务设置")
  }
  private copy(): void {
    const prompt = this.meta.prompt || this.meta.revisedPrompt
    void pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, prompt))
      .catch(() => { this.error = this.t("提示词复制失败。") })
  }

  build() {
    Column({ space: 8 }) {
      if (this.meta.status === 'running') {
        Column({ space: 10 }) {
          if (!this.jobFinished()) LoadingProgress().width(26).height(26).color(this.colors.primary)
          Text(this.jobProgress()).fontSize(14).fontColor(this.colors.muted)
          if (this.meta.job && !this.jobFinished()) Button(this.cancelling ? this.t("正在取消…") : this.t("取消生成")).enabled(!this.cancelling && this.jobState !== 'stopping')
            .fontColor(this.colors.primary).backgroundColor(this.colors.surface).onClick(() => { void this.cancel() })
        }.width('100%').padding(30).backgroundColor(this.colors.surfaceAlt).borderRadius(14)
      } else if (this.meta.status === 'failed') {
        Text(this.t(this.failure())).width('100%').padding(24).fontColor(this.colors.muted).backgroundColor(this.colors.surfaceAlt).borderRadius(14)
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.meta.items, (item: MediaItem, index: number) => {
            if (this.paths[index]) {
              AttachmentThumbnail({ colors: this.colors, edge: this.meta.items.length > 1 ? 140 : 240,
                item: { key: item.path, name: item.name, path: this.paths[index] }, scope: `${this.generation}/${index}`,
                client: this.client, sessionId: this.sessionId, onOpen: () => this.onOpen(this.meta.items, index) })
            } else {
              Button(this.meta.kind === 'video' ? this.t("▶ 查看视频") : this.t("查看图片")).height(140).width(this.meta.items.length > 1 ? 140 : '100%')
                .fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt).onClick(() => this.onOpen(this.meta.items, index))
            }
          }, (item: MediaItem) => item.path)
        }
      }
      Text(`${this.meta.status === 'done' ? this.t("AI 生成 · ") : ''}${string(this.meta.request['label']) || string(this.meta.request['model']) ||
        (this.meta.kind === 'image' ? this.t("图像") : this.t("视频"))}${this.meta.items.length ? this.f(" · {0} 项", [this.meta.items.length]) : ''}`)
        .fontSize(13).fontColor(this.colors.muted).width('100%')
      if (this.meta.status !== 'running') {
        Row({ space: 8 }) {
          Button(this.t("重新生成")).fontColor(this.colors.primary).backgroundColor(this.colors.surface).enabled(!!this.meta.prompt)
            .onClick(() => this.onRegenerate(this.meta))
          if (this.meta.prompt || this.meta.revisedPrompt) Button(this.t("复制提示词")).fontColor(this.colors.primary).backgroundColor(this.colors.surface)
            .onClick(() => this.copy())
          if (this.meta.status === 'failed') Button(this.t("服务设置")).fontColor(this.colors.primary).backgroundColor(this.colors.surface).onClick(this.onSettings)
        }
      }
      if (this.error) Text(this.t(this.error)).fontSize(12).fontColor(this.colors.danger)
    }.width('100%').alignItems(HorizontalAlign.Start).onVisibleAreaChange([0.0], (visible: boolean) => {
      if (this.visible === visible) return
      this.visible = visible
      if (visible) void this.load()
    })
  }
}
