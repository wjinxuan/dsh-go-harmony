import { localizedSettingsText } from './SettingsLocale'
import { connection } from '@kit.NetworkKit';
import { SenseVoiceModelClient, SenseVoiceModelState, emptySenseVoiceState, senseVoiceBusy, senseVoiceFailure } from '../local/SenseVoiceModel';
import { TransportControl } from '../remote/TransportEndpoint';
import { speechPhaseLabel } from '../dsh/SpeechData';
import { ThemeColors, themeColors } from './DshTheme';

@Component
export struct SenseVoiceModelPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors();
  getControl: () => Promise<TransportControl> = async () => { throw new Error(this.t("本机引擎尚未启动")); };
  onChanged: () => void = () => {};
  @State private state: SenseVoiceModelState = emptySenseVoiceState();
  @State private error: string = '';
  @State private busy: boolean = false;
  private active: boolean = false;
  private generation: number = 0;
  private timer: number = -1;
  private client?: SenseVoiceModelClient;

  aboutToAppear(): void { this.active = true; void this.refresh(true); }
  aboutToDisappear(): void { this.active = false; this.generation++; this.clearTimer(); }
  private clearTimer(): void { if (this.timer !== -1) clearTimeout(this.timer); this.timer = -1; }
  private async refresh(reconnect: boolean = false): Promise<void> {
    this.clearTimer(); const generation = ++this.generation;
    try {
      if (!this.client || reconnect) this.client = new SenseVoiceModelClient(await this.getControl());
      const state = await this.client.request();
      if (!this.active || generation !== this.generation) return;
      this.state = state; this.error = '';
      if (senseVoiceBusy(state.phase)) this.timer = setTimeout(() => { void this.refresh(); }, 1000);
    } catch {
      if (this.active && generation === this.generation) this.error = this.t("无法读取本机模型状态，请启动本机引擎后重试。");
    }
  }
  private async act(action: string): Promise<void> {
    if (this.busy || !this.active) return;
    this.busy = true; this.error = ''; this.clearTimer();
    const generation = ++this.generation;
    try {
      if (!this.client) this.client = new SenseVoiceModelClient(await this.getControl());
      const state = await this.client.request(action);
      if (!this.active || generation !== this.generation) return;
      this.state = state;
      this.onChanged();
      await this.refresh();
    } catch { if (this.active && generation === this.generation) this.error = this.t("本机模型操作未能确认，请刷新后检查。"); }
    finally { if (this.active) this.busy = false; }
  }
  private async confirmDownload(again: boolean): Promise<void> {
    let cellular = false;
    try {
      const capabilities = await connection.getNetCapabilities(await connection.getDefaultNet());
      cellular = capabilities.bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR);
    } catch {}
    if (!this.active) return;
    AlertDialog.show({ title: again ? this.t("重新下载本机模型") : this.t("下载本机语音模型"),
      message: `${cellular ? this.t("当前使用移动网络，下载会消耗约 241 MB 流量。") : this.t("模型约 241 MB，下载完成后可在本机离线识别。")}${again ? this.t("下载失败或取消时会保留现有模型。") : ''}`,
      primaryButton: { value: this.t("取消"), action: () => {} },
      secondaryButton: { value: again ? this.t("重新下载") : this.t("下载"), action: () => { void this.act(again ? 'redownload' : 'download'); } } });
  }
  private confirmDelete(): void {
    AlertDialog.show({ title: this.t("删除本机语音模型"), message: this.t("将删除模型和未完成的下载，释放本机存储空间。需要时可以重新下载。"),
      primaryButton: { value: this.t("取消"), action: () => {} },
      secondaryButton: { value: this.t("删除"), action: () => { void this.act('delete'); } } });
  }
  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.t("本机语音模型")).fontSize(16).fontColor(this.colors.text).layoutWeight(1);
        Button(this.t("刷新")).height(32).fontSize(12).enabled(!this.busy).onClick(() => { void this.refresh(true); });
      }.width('100%');
      Text(this.t("SenseVoiceSmall · 中 / 英 / 日 / 韩 / 粤语")).fontSize(13).fontColor(this.colors.muted);
      Text(this.state.phase === 'waiting' ? this.t("正在读取模型状态…") : speechPhaseLabel(this.state.phase)).fontSize(13).fontColor(this.colors.muted);
      if (senseVoiceBusy(this.state.phase)) {
        Progress({ value: Math.min(this.state.completedBytes, this.state.totalBytes), total: this.state.totalBytes, type: ProgressType.Linear }).width('100%');
        Text(`${Math.floor(this.state.completedBytes / 1000000)} / ${Math.ceil(this.state.totalBytes / 1000000)} MB`).fontSize(12).fontColor(this.colors.muted);
      }
      if (this.state.failure) Text(senseVoiceFailure(this.state.failure, this.state.neededBytes)).fontSize(13).fontColor(this.colors.danger);
      if (this.error) Text(this.t(this.error)).fontSize(13).fontColor(this.colors.danger);
      Row({ space: 8 }) {
        if (senseVoiceBusy(this.state.phase)) {
          Button(this.state.phase === 'cancelling' ? this.t("正在取消…") : this.t("取消下载")).height(36).fontSize(13)
            .enabled(!this.busy && this.state.phase !== 'cancelling').onClick(() => { void this.act('cancel'); });
        } else if (this.state.loaded) {
          Button(this.t("重新下载")).height(36).fontSize(13).enabled(!this.busy).onClick(() => { void this.confirmDownload(true); });
          Button(this.t("删除模型")).height(36).fontSize(13).enabled(!this.busy).onClick(() => { this.confirmDelete(); });
        } else {
          Button(this.state.phase === 'failed' ? this.t("重试下载") : this.t("下载模型 · 241 MB")).height(36).fontSize(13)
            .enabled(!this.busy && this.state.phase !== 'waiting' && this.state.nativeAvailable).onClick(() => { void this.confirmDownload(false); });
          if (this.state.completedBytes > 0) Button(this.t("删除下载")).height(36).fontSize(13).enabled(!this.busy).onClick(() => { this.confirmDelete(); });
        }
      }
    }.alignItems(HorizontalAlign.Start).width('100%').padding(14).backgroundColor(this.colors.surface).borderRadius(14);
  }
}
