import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { TransportControl } from '../remote/TransportEndpoint';
import { SenseVoiceModelPanel } from './SenseVoiceModelPanel';
import { DshClient } from '../dsh/DshClient';
import { SpeechCatalog, SpeechMode, SpeechProvider, speechPhaseLabel, speechPreparing,
  speechProviderUsable, speechMaxSeconds } from '../dsh/SpeechData';
import { DshGlyphs, ThemeColors, themeColors } from './DshTheme';

@Component
export struct SpeechPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors();
  @Prop mode: SpeechMode = 'auto';
  @Prop @Watch('scopeChanged') scope: string = '';
  @Prop connected: boolean = false;
  @Prop local: boolean = false;
  client: DshClient = new DshClient();
  getLocalControl?: () => Promise<TransportControl>;
  onModeChange: (mode: SpeechMode) => Promise<void> = async () => {};
  onClose: () => void = () => {};
  @State private catalog: SpeechCatalog | undefined = undefined;
  @State private loading: boolean = false;
  @State private busy: boolean = false;
  @State private saving: boolean = false;
  @State private error: string = '';
  private generation: number = 0;
  private active: boolean = false;
  private timer: number = -1;

  aboutToAppear(): void { this.active = true; void this.load(); }
  aboutToDisappear(): void { this.active = false; this.generation++; this.clearTimer(); }

  private scopeChanged(): void {
    this.generation++; this.clearTimer(); this.catalog = undefined; this.busy = false;
    if (this.active) void this.load();
  }

  private clearTimer(): void {
    if (this.timer !== -1) clearTimeout(this.timer);
    this.timer = -1;
  }

  private current(generation: number, connection: number): boolean {
    return this.active && generation === this.generation && connection === this.client.connectionIdentity();
  }

  private async load(quiet: boolean = false): Promise<void> {
    this.clearTimer();
    const generation = ++this.generation;
    const connection = this.client.connectionIdentity();
    if (!this.connected) { this.catalog = undefined; this.loading = false; return; }
    if (!quiet) this.loading = true;
    this.error = '';
    try {
      const catalog = await this.client.speechCatalog();
      if (!this.current(generation, connection)) return;
      this.catalog = catalog;
      if (catalog?.providers.some((provider: SpeechProvider) => speechPreparing(provider))) {
        this.timer = setTimeout(() => {
          if (this.current(generation, connection) && !this.busy) void this.load(true);
        }, 1500);
      }
    } catch { if (this.current(generation, connection)) this.error = this.t("无法读取语音服务，请检查连接后重试。"); }
    finally { if (this.current(generation, connection)) this.loading = false; }
  }

  private async selectMode(mode: SpeechMode): Promise<void> {
    if (this.saving || this.mode === mode) return;
    const generation = this.generation;
    this.saving = true; this.error = '';
    try { await this.onModeChange(mode); }
    catch { if (this.active && generation === this.generation) this.error = this.t("语音模式未能保存，请重试。"); }
    finally { if (this.active) this.saving = false; }
  }

  private async act(provider: SpeechProvider, action: string, source?: string): Promise<void> {
    if (!this.active || !this.connected || this.busy || this.loading ||
      !this.catalog?.providers.some((item: SpeechProvider) => item.id === provider.id)) return;
    if (action !== 'select' && !provider.preparable) return;
    const generation = this.generation;
    const connection = this.client.connectionIdentity();
    this.clearTimer(); this.busy = true; this.error = '';
    try {
      if (action === 'select') {
        const language = provider.languages.includes(this.catalog.language || '') ? this.catalog.language : provider.languages[0];
        await this.client.configureSpeech(provider.id, language);
      } else if (action === 'cancel') await this.client.cancelSpeechPreparation(provider.id);
      else await this.client.prepareSpeech(provider.id, source);
      if (this.current(generation, connection)) {
        this.busy = false;
        await this.load();
      }
    } catch {
      if (this.current(generation, connection)) this.error = this.t("语音设置操作未能确认，请刷新后检查。");
    } finally { if (this.current(generation, connection)) this.busy = false; }
  }

  @Builder
  private modeChoice(mode: SpeechMode, title: string, detail: string) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(title).fontSize(16).fontColor(this.colors.text);
        Text(detail).fontSize(13).fontColor(this.colors.muted);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      if (this.mode === mode) Text(DshGlyphs.check).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.primary);
    }.width('100%').padding(14).backgroundColor(this.colors.surface).borderRadius(14)
      .enabled(!this.saving).onClick(() => { void this.selectMode(mode); });
  }

  @Builder
  private providerCard(provider: SpeechProvider) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(provider.name).fontSize(16).fontColor(this.colors.text).layoutWeight(1);
        Text(speechPhaseLabel(provider.phase)).fontSize(12).fontColor(this.colors.muted);
      }.width('100%');
      Text(provider.location === 'cloud' ? this.t("云端识别服务") : this.local ? this.t("本机引擎识别服务") : this.t("远程主机识别服务"))
        .fontSize(13).fontColor(this.colors.muted);
      if (provider.totalBytes && provider.totalBytes > 0 && provider.completedBytes !== undefined) {
        Text(`${Math.min(100, Math.max(0, Math.floor(provider.completedBytes / provider.totalBytes * 100)))}%`)
          .fontSize(13).fontColor(this.colors.muted);
      }
      if (provider.languages.length) Text(provider.languages.join(' · ')).fontSize(12).fontColor(this.colors.muted);
      Row({ space: 8 }) {
        Button(this.catalog?.providerId === provider.id ? this.t("已选择") : this.t("选择")).height(36).fontSize(13)
          .enabled(!this.busy && !this.loading && this.catalog?.providerId !== provider.id && speechProviderUsable(provider))
          .onClick(() => { void this.act(provider, 'select'); });
        if (provider.preparable && speechPreparing(provider)) {
          Button(this.t("取消准备")).height(36).fontSize(13).enabled(!this.busy && provider.phase !== 'cancelling')
            .onClick(() => { void this.act(provider, 'cancel'); });
        } else if (provider.preparable && ['unprepared', 'failed', 'cancelled'].includes(provider.phase)) {
          if (provider.downloadSources.length) {
            ForEach(provider.downloadSources, (source: string) => {
              Button(this.f("准备 · {0}", [source])).height(36).fontSize(13).enabled(!this.busy)
                .onClick(() => { void this.act(provider, 'prepare', source); });
            }, (source: string) => source);
          } else {
            Button(this.t("准备语音服务")).height(36).fontSize(13).enabled(!this.busy)
              .onClick(() => { void this.act(provider, 'prepare'); });
          }
        }
      }
    }.alignItems(HorizontalAlign.Start).width('100%').padding(14).backgroundColor(this.colors.surface).borderRadius(14);
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Button({ type: ButtonType.Circle }) {
          Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text);
        }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText(this.t("返回")).onClick(this.onClose);
        Text(this.t("语音输入")).fontSize(22).fontColor(this.colors.text).layoutWeight(1);
        Button(this.t("刷新")).height(36).fontSize(13).enabled(this.connected && !this.busy && !this.loading)
          .onClick(() => { void this.load(); });
      }.width('100%');
      Scroll() {
        Column({ space: 10 }) {
          this.modeChoice('auto', this.t("自动"), this.t("优先使用已就绪的本机语音模型，否则使用手机系统识别；系统服务失败时尝试引擎识别。"));
          this.modeChoice('system', this.t("系统"), this.t("使用手机的语音识别服务。"));
          this.modeChoice('engine', this.t("引擎"), this.t("录音后交给当前 DSH 主机的语音服务转写。"));
          if (this.error) Text(this.t(this.error)).fontSize(13).fontColor(this.colors.danger).width('100%');
          if (this.local && this.getLocalControl) {
            SenseVoiceModelPanel({ colors: this.colors, getControl: this.getLocalControl, onChanged: () => { void this.load(); } });
          }
          Text(this.t("当前主机的语音服务")).fontSize(14).fontColor(this.colors.muted).width('100%').padding({ top: 12 });
          if (this.loading) LoadingProgress().width(28).height(28).color(this.colors.primary);
          else if (!this.connected) Text(this.t("连接主机后可查看引擎语音服务。")).fontSize(13).fontColor(this.colors.muted).width('100%');
          else if (!this.catalog && !this.error) Text(this.t("当前主机未提供语音服务，可选择手机系统识别。"))
            .fontSize(13).fontColor(this.colors.muted).width('100%');
          else if (this.catalog) {
            if (!this.catalog.providers.length) Text(this.t("当前主机没有可用的语音识别服务。")).fontSize(13).fontColor(this.colors.muted);
            ForEach(this.catalog.providers, (provider: SpeechProvider) => { this.providerCard(provider); },
              (provider: SpeechProvider) => JSON.stringify(provider));
            Text(this.f("单次录音最多 {0} 秒", [speechMaxSeconds(this.catalog)])).fontSize(12).fontColor(this.colors.muted).width('100%');
          }
        }.width('100%');
      }.width('100%').layoutWeight(1);
    }.padding(16).width('100%').height('100%').backgroundColor(this.colors.background);
  }
}
