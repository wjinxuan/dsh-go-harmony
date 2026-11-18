import { localizedSettingsText, settingsLanguage } from './SettingsLocale'
import { bundleManager, common } from '@kit.AbilityKit';
import { DshClient } from '../dsh/DshClient';
import { object, WireObject } from '../dsh/DshWire';
import { accountCallbackOrigin, accountPlatformUrl, AccountClientMetadata, AccountOverview, AccountSignInAttempt, loadAccountOverview,
  runAccountSignIn } from './AccountData';
import { DshGlyphs, ThemeColors, themeColors } from './DshTheme';

@Component
export struct AccountPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors();
  @Prop @Watch('connectionChanged') connected: boolean = false;
  @Prop @Watch('identityChanged') connectionIdentity: number = 0;
  @Prop local: boolean = true;
  client: DshClient = new DshClient();
  onOpenModels: () => void = () => {};
  onOpenSubscriptions?: () => void;
  @StorageProp('dshForeground') @Watch('foregroundChanged') private foreground: boolean = true;
  @State private overview: AccountOverview = { status: 'loading' };
  @State private refreshing: boolean = false;
  @State private signingIn: boolean = false;
  @State private cancelling: boolean = false;
  @State private signingOut: boolean = false;
  @State private signInPhase: string = '';
  @State private browserAvailable: boolean = false;
  @State private feedback: string = '';
  private browserUrl: string = '';
  private cancelLogin?: () => void;
  private generation: number = 0;
  private refreshOnResume: boolean = false;

  aboutToAppear(): void {
    this.connectionChanged();
  }

  aboutToDisappear(): void {
    this.generation++;
    this.cancelLogin = undefined;
    this.browserUrl = '';
  }

  private identityChanged(): void {
    this.connectionChanged();
  }

  private foregroundChanged(): void {
    if (this.foreground && this.refreshOnResume) { this.refreshOnResume = false; void this.load(); }
  }

  private async openPlatform(value: string): Promise<void> {
    const address = accountPlatformUrl(value);
    if (!address || !this.connected) return;
    try {
      this.refreshOnResume = true;
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await context.openLink(address);
    } catch { this.refreshOnResume = false; this.feedback = this.t("无法打开 DeepSeek 平台页面，请重试。"); }
  }

  private connectionChanged(): void {
    this.generation++;
    this.overview = { status: 'loading' };
    this.refreshing = false;
    this.signingIn = false;
    this.cancelling = false;
    this.signingOut = false;
    this.feedback = '';
    this.cancelLogin = undefined;
    this.browserUrl = '';
    this.browserAvailable = false;
    if (this.connected) {
      const generation = this.generation;
      Promise.resolve().then(() => {
        if (generation === this.generation) void this.load();
      });
    }
  }

  private async metadata(): Promise<AccountClientMetadata> {
    const bundle = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    return { version: bundle.versionName, locale: settingsLanguage(this.localeLanguage).toLowerCase().startsWith('zh') ? 'zh-CN' : 'en-US', timezoneOffsetSeconds: -new Date().getTimezoneOffset() * 60 };
  }

  private accountActionsAvailable(): boolean {
    return this.connected && this.local && !!accountCallbackOrigin(this.client.localAccountCallbackOrigin());
  }

  private async load(): Promise<void> {
    if (!this.connected || this.refreshing || this.signingIn || this.signingOut) return;
    const generation = ++this.generation;
    const connection = this.client.connectionIdentity();
    const current = (): boolean => this.connected && generation === this.generation &&
      connection === this.client.connectionIdentity();
    this.refreshing = true;
    this.overview = { status: 'loading' };
    try {
      const metadata = await this.metadata();
      if (!current()) return;
      await loadAccountOverview((method: string, args: WireObject, timeoutMs?: number) =>
        this.client.request(method, args, timeoutMs), metadata, current,
        (view: AccountOverview): void => { this.overview = view; });
    } catch {
      if (current()) this.overview = { status: 'error' };
    } finally {
      if (current()) this.refreshing = false;
    }
  }

  private async openBrowser(current: () => boolean): Promise<void> {
    if (!current() || this.cancelling || !this.browserUrl) return;
    try {
      this.feedback = '';
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await context.openLink(this.browserUrl);
    } catch {
      if (current() && !this.cancelling) this.feedback = this.t("无法打开浏览器，请重试。");
    }
  }

  private async initializeAccountModel(current: () => boolean): Promise<void> {
    try {
      const catalog = await this.client.listModels();
      const selected = catalog.defaultSelection;
      if (!current() || (selected && catalog.groups.some(group => group.id === selected.provider &&
        group.models.some(model => model.id === selected.model)))) return;
      await this.client.request('session/initializeDefaultModel');
    } catch {
      if (current()) this.feedback = this.t("已登录。可在模型与服务商中选择账号模型。");
    }
  }

  private async signIn(): Promise<void> {
    if (!this.accountActionsAvailable() || this.refreshing || this.signingIn || this.signingOut ||
      this.overview.status !== 'signed-out') return;
    const connection = this.client.connectionIdentity();
    const generation = ++this.generation;
    const sameConnection = (): boolean => this.connected && this.local && connection === this.client.connectionIdentity();
    const current = (): boolean => sameConnection() && generation === this.generation;
    let cancelRequested = false;
    this.cancelLogin = () => { cancelRequested = true; this.cancelling = true; };
    this.signingIn = true;
    this.signInPhase = 'initializing';
    this.feedback = '';
    try {
      const metadata = await this.metadata();
      if (!current() || cancelRequested) return;
      const outcome = await runAccountSignIn((method: string, args: WireObject) => this.client.request(method, args),
        metadata, this.client.localAccountCallbackOrigin(), () => current() && !cancelRequested,
        (attempt: AccountSignInAttempt): Promise<void> => {
          this.signInPhase = attempt.phase;
          this.browserUrl = attempt.authorizeUrl;
          this.browserAvailable = !!this.browserUrl;
          // Polling must continue while the system browser is active.
          if (this.browserAvailable) void this.openBrowser(current);
          return Promise.resolve();
        }, () => new Promise<void>(resolve => { setTimeout(resolve, 1200); }),
        () => cancelRequested && sameConnection());
      if (!current()) return;
      if (outcome === 'signed-in') await this.initializeAccountModel(current);
      else if (outcome === 'expired') this.feedback = this.t("登录链接已过期，请重新登录。");
      else if (outcome === 'unsafe-url') this.feedback = this.t("主机返回了无效的 DeepSeek 登录链接。");
      else if (outcome === 'failed') this.feedback = this.t("DeepSeek 登录失败，请重试。");
    } catch {
      if (current()) this.feedback = cancelRequested ? this.t("未能确认取消，请刷新账号状态。") : this.t("无法完成登录，请重试。");
    } finally {
      if (current()) {
        this.signingIn = false;
        this.cancelling = false;
        this.cancelLogin = undefined;
        this.browserUrl = '';
        this.browserAvailable = false;
        void this.load();
      }
    }
  }

  private reopenBrowser(): void {
    const generation = this.generation;
    const connection = this.client.connectionIdentity();
    void this.openBrowser(() => this.signingIn && this.connected && generation === this.generation &&
      connection === this.client.connectionIdentity());
  }

  private async confirmSignOut(): Promise<void> {
    if (!this.accountActionsAvailable() || this.signingIn || this.signingOut ||
      this.overview.status !== 'credential-stored') return;
    const generation = this.generation;
    const connection = this.client.connectionIdentity();
    const current = (): boolean => this.accountActionsAvailable() && generation === this.generation &&
      connection === this.client.connectionIdentity();
    this.signingOut = true;
    let running: Object | null | undefined;
    try {
      running = await this.client.request('account/hasRunningAccountTasks');
    } catch {
      running = undefined;
    }
    if (!current()) return;
    this.signingOut = false;
    this.getUIContext().showAlertDialog({
      title: this.t("退出 DeepSeek 账号？"),
      message: this.t("退出将撤销本机引擎使用的账号授权。") + (running === true ? this.t("正在使用此账号的任务会中止。") :
        running === false ? '' : this.t("当前无法确认是否有任务正在使用此账号。")),
      primaryButton: { value: this.t("取消"), action: () => {} },
      secondaryButton: { value: this.t("退出账号"), action: () => { if (current()) void this.signOut(current); } }
    });
  }

  private async signOut(current: () => boolean): Promise<void> {
    if (!current() || this.signingOut) return;
    this.signingOut = true;
    this.feedback = '';
    try {
      const metadata = await this.metadata();
      if (!current()) return;
      const args: WireObject = {};
      args['client'] = metadata;
      const view = object(await this.client.request('account/signOut', args));
      if (view['status'] !== 'signed-out') throw new Error(this.t("账号退出状态无效"));
    } catch {
      if (current()) this.feedback = this.t("无法确认退出，账号状态将重新读取。");
    } finally {
      if (current()) {
        this.signingOut = false;
        void this.load();
      }
    }
  }

  private signInDescription(): string {
    if (this.cancelling) return this.t("正在取消登录…");
    if (this.signInPhase === 'waiting-browser') return this.t("请在浏览器完成 DeepSeek 登录，然后返回此应用。");
    if (this.signInPhase === 'exchanging' || this.signInPhase === 'committing') return this.t("正在保存 DeepSeek 账号授权…");
    return this.t("正在准备登录…");
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
    if (!this.connected) return this.t("连接主机后可查看 DeepSeek 账号。");
    if (this.overview.status === 'unsupported') return this.t("当前主机未提供 DeepSeek 账号功能。");
    if (this.overview.status === 'error') return this.t("无法读取当前主机的账号状态。");
    return this.local ? this.t("通过浏览器登录 DeepSeek，或在模型与服务商中配置 API Key。") :
      this.t("当前主机没有保存 DeepSeek 账号授权。请在电脑上的 DeepSeek Harness 登录。");
  }

  build() {
    Column({ space: 14 }) {
      if (this.connected) {
        Row() {
          Text(this.local ? this.t("本机") : this.t("远程主机")).fontSize(13).fontColor(this.colors.muted).layoutWeight(1);
          Button({ type: ButtonType.Circle }) {
            Text(DshGlyphs.refresh).fontFamily(DshGlyphs.family).fontSize(19).fontColor(this.colors.text);
          }.width(44).height(44).backgroundColor(this.colors.surface)
            .enabled(!this.refreshing && !this.signingIn && !this.signingOut)
            .accessibilityText(this.t("刷新账号资料和余额")).onClick(() => { this.feedback = ''; void this.load(); });
        }.width('100%');
      }
      if (this.connected && this.signingIn) {
        Column({ space: 10 }) {
          Row({ space: 12 }) {
            LoadingProgress().width(26).height(26).color(this.colors.primary);
            Text(this.signInDescription()).fontSize(14).fontColor(this.colors.muted).layoutWeight(1);
          }.width('100%');
          if (this.browserAvailable && !this.cancelling) {
            Button(this.t("重新打开浏览器")).width('100%').height(44).onClick(() => this.reopenBrowser());
          }
          Button(this.t("取消登录")).width('100%').height(44).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
            .enabled(!this.cancelling).onClick(() => { this.cancelLogin?.(); });
        }.width('100%').padding(16).borderRadius(14).backgroundColor(this.colors.surface);
      } else if (this.connected && this.overview.status === 'loading') {
        Row({ space: 12 }) {
          LoadingProgress().width(26).height(26).color(this.colors.primary);
          Text(this.t("正在读取账号状态…")).fontSize(14).fontColor(this.colors.muted);
        }.width('100%').padding(16);
      } else if (this.connected && this.overview.status === 'credential-stored') {
        Column({ space: 6 }) {
          Text(this.overview.profile?.name || this.overview.profile?.contact || this.t("DeepSeek 账号"))
            .fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%');
          if (this.overview.profile?.name && this.overview.profile?.contact &&
            this.overview.profile?.contact !== this.overview.profile?.name) {
            Text(this.overview.profile?.contact || '').fontSize(14).fontColor(this.colors.muted).width('100%');
          }
          Text(this.overview.profileFailed ? this.t("主机已保存账号授权，暂时无法读取资料。") :
            this.local ? this.t("本机已保存账号授权") : this.t("账号登录与退出由远程电脑管理。"))
            .fontSize(14).fontColor(this.overview.profileFailed ? this.colors.warning : this.colors.muted).width('100%');
        }.width('100%').padding(16).borderRadius(14).backgroundColor(this.colors.surface);
        Column({ space: 10 }) {
          Text(this.t("余额")).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%');
          if (this.overview.balanceFailed) {
            Text(this.t("暂时无法读取余额，可刷新重试。")).fontSize(14).fontColor(this.colors.warning).width('100%');
          } else {
            Row({ space: 12 }) {
              this.wallet(this.t("充值余额"), () => this.overview.recharge);
              this.wallet(this.t("赠送余额"), () => this.overview.bonus);
            }.width('100%').alignItems(VerticalAlign.Top);
          }
        }.width('100%').padding(16).borderRadius(14).backgroundColor(this.colors.surface);
        if (this.overview.usageUrl || this.overview.topUpUrl) {
          Row({ space: 10 }) {
            if (this.overview.usageUrl) Button(this.t("查看用量")).layoutWeight(1).onClick(() => { void this.openPlatform(this.overview.usageUrl || ''); });
            if (this.overview.topUpUrl) Button(this.t("充值")).layoutWeight(1).onClick(() => { void this.openPlatform(this.overview.topUpUrl || ''); });
          }.width('100%');
        }
        if (this.accountActionsAvailable()) {
          Button(this.signingOut ? this.t("正在处理…") : this.t("退出账号")).width('100%').height(44)
            .fontColor(this.colors.danger).backgroundColor(this.colors.surfaceAlt).enabled(!this.signingOut)
            .onClick(() => { void this.confirmSignOut(); });
        }
      } else {
        Column({ space: 8 }) {
          if (this.connected && this.overview.status === 'signed-out') {
            Text(this.t("未登录")).fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%');
          }
          Text(this.description()).fontSize(14).fontColor(this.colors.muted).lineHeight(21).width('100%');
          if (this.overview.status === 'signed-out' && this.accountActionsAvailable()) {
            Button(this.t("登录 DeepSeek")).width('100%').height(44).backgroundColor(this.colors.primary)
              .enabled(!this.refreshing).onClick(() => { void this.signIn(); });
          }
        }.width('100%').padding(16).borderRadius(14).backgroundColor(this.colors.surface);
      }
      if (this.feedback) {
        Text(this.t(this.feedback)).fontSize(14).fontColor(this.colors.warning).width('100%');
      }
      if (this.connected && !this.signingIn && !this.signingOut) {
        Button(this.t("模型与服务商")).width('100%').height(44).fontColor(this.colors.text)
          .backgroundColor(this.colors.surfaceAlt).onClick(this.onOpenModels);
        if (this.onOpenSubscriptions) Button(this.t("ChatGPT / Claude 订阅")).width('100%').height(44)
          .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).onClick(() => this.onOpenSubscriptions?.());
      }
    }.width('100%');
  }
}
