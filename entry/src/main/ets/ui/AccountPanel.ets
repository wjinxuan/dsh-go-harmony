import { bundleManager } from '@kit.AbilityKit';
import { DshClient } from '../dsh/DshClient';
import { WireObject } from '../dsh/DshWire';
import { AccountClientMetadata, AccountOverview, loadAccountOverview } from './AccountData';
import { DshGlyphs, ThemeColors, themeColors } from './DshTheme';

@Component
export struct AccountPanel {
  @Prop colors: ThemeColors = themeColors();
  @Prop @Watch('connectionChanged') connected: boolean = false;
  @Prop @Watch('identityChanged') connectionIdentity: number = 0;
  @Prop local: boolean = true;
  client: DshClient = new DshClient();
  onOpenModels: () => void = () => {};
  @State private overview: AccountOverview = { status: 'loading' };
  @State private refreshing: boolean = false;
  private generation: number = 0;

  aboutToAppear(): void {
    this.connectionChanged();
  }

  aboutToDisappear(): void {
    this.generation++;
  }

  private identityChanged(): void {
    this.connectionChanged();
  }

  private connectionChanged(): void {
    this.generation++;
    this.overview = { status: 'loading' };
    this.refreshing = false;
    if (this.connected) {
      const generation = this.generation;
      Promise.resolve().then(() => {
        if (generation === this.generation) void this.load();
      });
    }
  }

  private async load(): Promise<void> {
    if (!this.connected || this.refreshing) return;
    const generation = ++this.generation;
    const connection = this.client.connectionIdentity();
    const current = (): boolean => this.connected && generation === this.generation &&
      connection === this.client.connectionIdentity();
    this.refreshing = true;
    this.overview = { status: 'loading' };
    try {
      const bundle = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      if (!current()) return;
      const metadata: AccountClientMetadata = { version: bundle.versionName, locale: 'zh-CN',
        timezoneOffsetSeconds: -new Date().getTimezoneOffset() * 60 };
      await loadAccountOverview((method: string, args: WireObject, timeoutMs?: number) =>
        this.client.request(method, args, timeoutMs), metadata, current,
        (view: AccountOverview): void => { this.overview = view; });
    } catch {
      if (current()) this.overview = { status: 'error' };
    } finally {
      if (current()) this.refreshing = false;
    }
  }

  @Builder
  private wallet(title: string, lines: () => string[] | undefined) {
    Column({ space: 5 }) {
      Text(title).fontSize(13).fontColor(this.colors.muted);
      if (lines()) {
        ForEach(lines() ?? [], (line: string) => {
          Text(line).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.colors.text)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
        }, (line: string) => line);
      } else {
        Text('—').fontSize(18).fontColor(this.colors.muted);
      }
    }.layoutWeight(1).alignItems(HorizontalAlign.Start);
  }

  private description(): string {
    if (!this.connected) return '连接主机后可查看 DeepSeek 账号。';
    if (this.overview.status === 'unsupported') return '当前主机未提供 DeepSeek 账号功能。';
    if (this.overview.status === 'error') return '无法读取当前主机的账号状态。';
    return this.local ? '本机暂不支持账号登录。可在模型与服务商中配置 API Key。' :
      '当前主机没有保存 DeepSeek 账号授权。请在电脑上的 DeepSeek Harness 登录。';
  }

  build() {
    Column({ space: 14 }) {
      if (this.connected) {
        Row() {
          Text(this.local ? '本机' : '远程主机').fontSize(13).fontColor(this.colors.muted).layoutWeight(1);
          Button({ type: ButtonType.Circle }) {
            Text(DshGlyphs.refresh).fontFamily(DshGlyphs.family).fontSize(19).fontColor(this.colors.text);
          }.width(44).height(44).backgroundColor(this.colors.surface).enabled(!this.refreshing)
            .accessibilityText('刷新账号资料和余额').onClick(() => { void this.load(); });
        }.width('100%');
      }
      if (this.connected && this.overview.status === 'loading') {
        Row({ space: 12 }) {
          LoadingProgress().width(26).height(26).color(this.colors.primary);
          Text('正在读取账号状态…').fontSize(14).fontColor(this.colors.muted);
        }.width('100%').padding(16);
      } else if (this.connected && this.overview.status === 'credential-stored') {
        Column({ space: 6 }) {
          Text(this.overview.profile?.name || this.overview.profile?.contact || 'DeepSeek 账号')
            .fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%');
          if (this.overview.profile?.name && this.overview.profile?.contact &&
            this.overview.profile?.contact !== this.overview.profile?.name) {
            Text(this.overview.profile?.contact || '').fontSize(14).fontColor(this.colors.muted).width('100%');
          }
          Text(this.overview.profileFailed ? '主机已保存账号授权，暂时无法读取资料。' : '主机已保存账号授权')
            .fontSize(14).fontColor(this.overview.profileFailed ? this.colors.warning : this.colors.muted).width('100%');
        }.width('100%').padding(16).borderRadius(14).backgroundColor(this.colors.surface);
        Column({ space: 10 }) {
          Text('余额').fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%');
          if (this.overview.balanceFailed) {
            Text('暂时无法读取余额，可刷新重试。').fontSize(14).fontColor(this.colors.warning).width('100%');
          } else {
            Row({ space: 12 }) {
              this.wallet('充值余额', () => this.overview.recharge);
              this.wallet('赠送余额', () => this.overview.bonus);
            }.width('100%').alignItems(VerticalAlign.Top);
          }
        }.width('100%').padding(16).borderRadius(14).backgroundColor(this.colors.surface);
      } else {
        Column({ space: 8 }) {
          if (this.connected && this.overview.status === 'signed-out') {
            Text('未登录').fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%');
          }
          Text(this.description()).fontSize(14).fontColor(this.colors.muted).lineHeight(21).width('100%');
        }.width('100%').padding(16).borderRadius(14).backgroundColor(this.colors.surface);
      }
      if (this.connected) {
        Button('模型与服务商').width('100%').height(44).fontColor(this.colors.text)
          .backgroundColor(this.colors.surfaceAlt).onClick(this.onOpenModels);
      }
    }.width('100%');
  }
}
