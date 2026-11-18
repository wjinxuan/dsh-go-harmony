import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { normalizeProviderKey } from '../dsh/DshWire';
import { ACCENTS, DshAccent, DshGlyphs, ThemeColors, themeColors } from './DshTheme';

const KEY_PORTAL: string = 'https://platform.deepseek.com/api_keys';

@Component
export struct OnboardingPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors();
  @Prop accentId: string = 'mist';
  @Prop themeMode: string = 'system';
  @Prop fontSize: number = 16;
  @Prop engineBusy: boolean = false;
  @Prop engineReady: boolean = false;
  @Prop stageText: string = '';
  @Prop errorText: string = '';
  onThemeChange: (accentId: string, mode: string) => void = () => {};
  onFontSizeChange: (size: number) => void = () => {};
  onPrepareLocal: () => void = () => {};
  onConnectLocal: (key: string, remember: boolean) => Promise<boolean> = async () => false;
  onConnectAccount: () => void = () => {};
  onFinish: () => void = () => {};
  onRemote: () => void = () => {};
  onOpenPrivacy?: () => void;
  @State private notificationsAllowed: boolean = false;
  @State private permissionBusy: boolean = false;
  onBackHandler?: (handler: (() => boolean) | undefined) => void;
  @State private step: string = 'welcome';
  @State private target: string = 'local';
  @State private keyEntry: boolean = false;
  @State private keyDraft: string = '';
  @State private remember: boolean = false;
  @State private saving: boolean = false;
  @State private finished: boolean = false;
  @State private validation: string = '';
  private active: boolean = false;
  private finishTimer: number = -1;

  aboutToAppear(): void {
    this.active = true;
    void notificationManager.isNotificationEnabled().then((enabled: boolean) => { if (this.active) this.notificationsAllowed = enabled; }).catch(() => {});
    this.onBackHandler?.(() => this.back());
  }

  aboutToDisappear(): void {
    this.active = false;
    this.onBackHandler?.(undefined);
    clearTimeout(this.finishTimer);
    this.keyDraft = '';
  }

  private stepNumber(): number {
    return ['runtime', 'appearance', 'access', 'apiKey'].indexOf(this.step) + 1;
  }

  private advance(step: string): void {
    this.validation = '';
    this.step = step;
  }

  private back(): boolean {
    if (this.saving || this.finished) return true;
    if (this.step === 'welcome') return false;
    if (this.step === 'apiKey' && this.keyEntry) {
      this.keyDraft = '';
      this.keyEntry = false;
      this.validation = '';
      return true;
    }
    const previous: Record<string, string> = {
      'runtime': 'welcome', 'appearance': 'runtime', 'access': 'appearance', 'apiKey': 'access'
    };
    this.advance(previous[this.step] || 'welcome');
    return true;
  }

  private chooseRuntime(): void {
    if (this.target === 'remote') {
      this.onRemote();
      return;
    }
    this.onPrepareLocal();
    this.advance('appearance');
  }

  private async openPlatform(): Promise<void> {
    this.validation = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await context.openLink(KEY_PORTAL);
    } catch {
      this.validation = this.t("没能打开浏览器，请在 DeepSeek 开放平台创建 API Key。");
    }
  }

  private async submit(): Promise<void> {
    if (this.saving || this.finished || this.engineBusy) return;
    let key: string;
    try {
      key = normalizeProviderKey(this.keyDraft);
    } catch (error) {
      this.validation = (error as Error).message;
      return;
    }
    this.saving = true;
    this.advance('finishing');
    try {
      if (!await this.onConnectLocal(key, this.remember)) {
        if (this.active) {
          this.advance('apiKey');
          this.validation = this.t("连接未完成，可以重新输入或重试。");
        }
        return;
      }
      if (this.active) {
        this.finished = true;
        this.keyDraft = '';
        this.finishTimer = setTimeout(() => {
          if (this.active) this.onFinish();
        }, 420);
      }
    } catch {
      if (this.active) {
        this.advance('apiKey');
        this.validation = this.t("连接未完成，可以重新输入或重试。");
      }
    } finally {
      if (this.active) this.saving = false;
    }
  }

  private async notificationPermission(): Promise<void> {
    if (this.permissionBusy) return;
    this.permissionBusy = true;
    try {
      await notificationManager.requestEnableNotification(this.getUIContext().getHostContext() as common.UIAbilityContext);
      const enabled = await notificationManager.isNotificationEnabled();
      if (this.active) this.notificationsAllowed = enabled;
    } catch { if (this.active) this.validation = this.t("可以稍后在设置中开启通知。"); }
    finally { if (this.active) this.permissionBusy = false; }
  }

  @Builder
  private primary(label: string, action: () => void) {
    Button(label).height(48).width('100%').fontSize(16).fontColor(this.colors.onPrimary)
      .backgroundColor(this.colors.primary).onClick(action);
  }

  @Builder
  private secondary(label: string, action: () => void) {
    Button(label).height(45).width('100%').fontSize(15).fontColor(this.colors.primary)
      .backgroundColor(this.colors.surface).onClick(action);
  }

  @Builder
  private centerText(value: string) {
    Text(value).fontColor(this.colors.muted).fontSize(15).lineHeight(23).width('100%').textAlign(TextAlign.Center);
  }

  @Builder
  private header(icon: string, title: string, description: string) {
    Column({ space: 12 }) {
      Text(icon).fontFamily(DshGlyphs.family).fontSize(26).fontColor(this.colors.primary)
        .width(54).height(54).textAlign(TextAlign.Center).backgroundColor(this.colors.primaryContainer).borderRadius(17);
      Text(title).fontSize(26).fontWeight(FontWeight.Medium).fontColor(this.colors.text)
        .width('100%').textAlign(TextAlign.Center);
      if (description) this.centerText(description);
    }.width('100%').padding({ top: 12, bottom: 10 });
  }

  @Builder
  private progress() {
    Row({ space: 12 }) {
      Button({ type: ButtonType.Circle }) {
        Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text);
      }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText(this.t("返回")).onClick(() => { this.back(); });
      Column({ space: 7 }) {
        Text(this.f("第 {0} 步，共 4 步", [this.stepNumber()])).fontColor(this.colors.muted).fontSize(13).width('100%');
        Progress({ value: this.stepNumber(), total: 4, type: ProgressType.Linear })
          .color(this.colors.primary).backgroundColor(this.colors.surfaceAlt).width('100%');
      }.layoutWeight(1);
    }.width('100%');
  }

  @Builder
  private welcome() {
    Column({ space: 20 }) {
      Blank().height(54);
      Image($r('app.media.app_icon')).width(110).height(110).objectFit(ImageFit.Contain).borderRadius(24);
      Text($r('app.string.app_name')).fontSize(41).fontWeight(FontWeight.Bold).fontColor(this.colors.text);
      Text(this.t("在鸿蒙上运行或连接\nDeepSeek Harness")).fontSize(23).lineHeight(31).fontColor(this.colors.muted)
        .textAlign(TextAlign.Center);
      Blank().height(66);
      this.primary(this.t("开始"), () => this.advance('runtime'));
    }.width('100%');
  }

  @Builder
  private runtimeOption(id: string, icon: string, label: string, description: string) {
    Row({ space: 14 }) {
      Text(icon).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.primary).width(37);
      Column({ space: 4 }) {
        Text(label).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%');
        Text(description).fontSize(13).fontColor(this.colors.muted).width('100%');
      }.layoutWeight(1);
      Text(this.target === id ? '◉' : '○').fontSize(20)
        .fontColor(this.target === id ? this.colors.primary : this.colors.muted);
    }.width('100%').padding(16).borderRadius(16).backgroundColor(this.colors.surface)
      .border({ width: 2, color: this.target === id ? this.colors.primary : this.colors.border })
      .accessibilityText(this.target === id ? this.f("{0}，已选择", [label]) : label)
      .onClick(() => { this.target = id; });
  }

  @Builder
  private runtimeChoice() {
    Column({ space: 12 }) {
      this.header(DshGlyphs.host, this.t("DSH 在哪里运行？"), this.t("之后可以在设置里更改"));
      this.runtimeOption('local', DshGlyphs.host, this.t("本机"), this.t("在这台手机准备并运行 DeepSeek Harness"));
      this.runtimeOption('remote', DshGlyphs.switchHost, this.t("远程主机"), this.t("连接电脑或服务器上的 DSH"));
      Blank().height(16);
      this.primary(this.t("继续"), () => this.chooseRuntime());
    }.width('100%');
  }

  @Builder
  private appearance() {
    Column({ space: 13 }) {
      this.header(DshGlyphs.settings, this.t("选择外观"), this.t("随时可以在设置里更改"));
      Column({ space: 15 }) {
        Row({ space: 6 }) {
          ForEach(['light', 'dark', 'system'], (mode: string) => {
            Button(mode === 'light' ? this.t("浅色") : mode === 'dark' ? this.t("深色") : this.t("跟随系统"))
              .fontSize(13).height(41).layoutWeight(1)
              .backgroundColor(this.themeMode === mode ? this.colors.primaryContainer : this.colors.surfaceAlt)
              .fontColor(this.themeMode === mode ? this.colors.onPrimaryContainer : this.colors.text)
              .onClick(() => this.onThemeChange(this.accentId, mode));
          }, (mode: string) => mode);
        }.width('100%');
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(ACCENTS, (accent: DshAccent) => {
            Column({ space: 5 }) {
              Row({ space: 3 }) {
                Blank().width(17).height(17).borderRadius(9).backgroundColor(accent.light);
                Blank().width(17).height(17).borderRadius(9).backgroundColor(accent.dark);
              }
              Text(this.t(accent.name)).fontSize(13).fontColor(this.colors.text);
            }.padding(7).width('31%').margin({ bottom: 4 }).borderRadius(11)
              .backgroundColor(this.accentId === accent.id ? this.colors.primaryContainer : this.colors.surface)
              .accessibilityText(this.accentId === accent.id ? this.f("{0}，已选择", [accent.name]) : accent.name)
              .onClick(() => this.onThemeChange(accent.id, this.themeMode));
          }, (accent: DshAccent) => accent.id);
        }.width('100%');
      }.padding(14).width('100%').borderRadius(16).backgroundColor(this.colors.surface);
      Blank().height(12);
      this.primary(this.t("继续"), () => this.advance('access'));
    }.width('100%');
  }

  @Builder
  private access() {
    Column({ space: 12 }) {
      this.header(DshGlyphs.folder, this.t("想让 Harness Pocket 帮你做哪些事"), this.t("在鸿蒙上使用工作区内的文件"));
      Column({ space: 9 }) {
        Text(this.t("工作区文件")).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%');
        Text(this.t("本机引擎可以读写应用工作区。此步骤无需开启系统权限。")).fontSize(14).lineHeight(21)
          .fontColor(this.colors.muted).width('100%');
      }.padding(16).width('100%').borderRadius(16).backgroundColor(this.colors.surface);
      Column({ space: 9 }) {
        Text(this.t("对话提醒")).fontSize(17).fontColor(this.colors.text).width('100%');
        Text(this.t("对话完成、出错或等待你确认时发送通知。可选，稍后仍可在设置中更改。")).fontSize(14).fontColor(this.colors.muted).width('100%');
        Button(this.notificationsAllowed ? this.t("通知已开启") : this.t("开启通知")).height(44).width('100%')
          .fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt).enabled(!this.notificationsAllowed && !this.permissionBusy)
          .onClick(() => { void this.notificationPermission(); });
      }.padding(16).width('100%').borderRadius(16).backgroundColor(this.colors.surface);
      if (this.onOpenPrivacy) { this.secondary(this.t("隐私与分享"), () => this.onOpenPrivacy?.()); }
      if (this.validation) { Text(this.t(this.validation)).fontColor(this.colors.muted).width('100%'); }
      Blank().height(15);
      this.primary(this.t("继续"), () => this.advance('apiKey'));
    }.width('100%');
  }

  @Builder
  private connectionChoice() {
    Column({ space: 12 }) {
      this.header(DshGlyphs.model, this.t("连接 DeepSeek"), this.t("登录 DeepSeek 账号或使用开放平台 API Key"));
      Button(this.t("使用 DeepSeek 账号")).height(48).width('100%').fontSize(16).fontColor(this.colors.onPrimary)
        .backgroundColor(this.colors.primary).enabled(!this.engineBusy).onClick(this.onConnectAccount);
      this.secondary(this.t("使用 API Key"), () => { this.keyEntry = true; this.validation = ''; });
      this.secondary(this.t("使用远程主机"), this.onRemote);
      if (this.errorText) Text(this.t(this.errorText)).width('100%').fontSize(14).fontColor(this.colors.danger);
    }.width('100%');
  }

  @Builder
  private keyForm() {
    Column({ space: 13 }) {
      this.header(DshGlyphs.model, this.t("输入 API Key"), this.t("费用由 DeepSeek 开放平台按量结算"));
      Column({ space: 10 }) {
        TextInput({ text: this.keyDraft, placeholder: this.t("输入 DeepSeek API Key") }).type(InputType.Password)
          .fontColor(this.colors.text).placeholderColor(this.colors.hint).backgroundColor(this.colors.surfaceAlt)
          .width('100%').height(48).enableAutoFill(false).maxLength(1024).enabled(!this.saving)
          .onChange((value: string) => { this.keyDraft = value; this.validation = ''; })
          .onSubmit(() => { void this.submit(); });
        Row({ space: 10 }) {
          Column({ space: 4 }) {
            Text(this.t("记住 API Key")).fontSize(16).fontColor(this.colors.text).width('100%');
            Text(this.t("加密保存在本机，重启引擎时可以继续使用。")).fontSize(13).fontColor(this.colors.muted).width('100%');
          }.layoutWeight(1);
          Toggle({ type: ToggleType.Switch, isOn: this.remember }).selectedColor(this.colors.primary)
            .accessibilityText(this.t("记住 API Key")).onChange((value: boolean) => { this.remember = value; });
        }.width('100%');
      }.width('100%').padding(14).borderRadius(16).backgroundColor(this.colors.surface);
      if (this.validation) {
        Text(this.t(this.validation)).width('100%').fontSize(14).fontColor(this.colors.danger);
      }
      if (this.errorText) {
        Text(this.t(this.errorText)).width('100%').fontSize(14).fontColor(this.colors.danger);
      }
      Button(this.t("保存并继续")).height(48).width('100%').fontSize(16).fontColor(this.colors.onPrimary)
        .backgroundColor(this.colors.primary).enabled(!this.saving && !this.engineBusy && this.keyDraft.trim().length > 0)
        .onClick(() => { void this.submit(); });
      this.secondary(this.t("获取 API Key"), () => { void this.openPlatform(); });
    }.width('100%');
  }

  @Builder
  private runtimeCapsule() {
    if (this.engineBusy || this.engineReady || this.stageText) {
      Row({ space: 10 }) {
        if (this.engineBusy) {
          LoadingProgress().width(20).height(20).color(this.colors.primary);
        } else if (this.engineReady) {
          Text(DshGlyphs.check).fontFamily(DshGlyphs.family).fontSize(19).fontColor(this.colors.success);
        }
        Text(this.stageText || (this.engineReady ? this.t("运行环境已就绪") : this.t("准备运行环境")))
          .fontSize(13).fontColor(this.colors.muted).layoutWeight(1);
      }.padding(12).width('100%').borderRadius(18).backgroundColor(this.colors.surface);
    }
  }

  @Builder
  private finishing() {
    Column({ space: 14 }) {
      Blank().height(64);
      if (this.finished) {
        this.header(DshGlyphs.check, this.t("准备就绪"), this.t("即将继续"));
      } else {
        this.header(DshGlyphs.host, this.t("正在准备运行环境"), this.t("完成后自动进入"));
        LoadingProgress().width(38).height(38).color(this.colors.primary);
        if (this.stageText) {
          Text(this.t(this.stageText)).fontColor(this.colors.muted).fontSize(15).lineHeight(23)
            .width('100%').textAlign(TextAlign.Center);
        }
      }
    }.width('100%');
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        if (this.stepNumber() > 0) this.progress();
        if (this.step === 'welcome') this.welcome();
        else if (this.step === 'runtime') this.runtimeChoice();
        else if (this.step === 'appearance') this.appearance();
        else if (this.step === 'access') this.access();
        else if (this.step === 'apiKey') {
          if (this.keyEntry) this.keyForm();
          else this.connectionChoice();
        } else this.finishing();
        if (this.step === 'appearance' || this.step === 'access' || this.step === 'apiKey') this.runtimeCapsule();
      }.width('100%').constraintSize({ maxWidth: 560 }).padding(24);
    }.width('100%').height('100%').align(Alignment.Top).backgroundColor(this.colors.background);
  }
}
