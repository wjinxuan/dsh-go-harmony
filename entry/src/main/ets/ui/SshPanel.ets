import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { SshBridge, SshBridgeError, SSH_FINGERPRINT } from '../remote/SshBridge';
import { listSshHosts, SshHost, updateSshHosts, validateSshHost } from '../remote/SshHosts';
import { TransportControl, TransportEndpoint } from '../remote/TransportEndpoint';
import { ThemeColors, themeColors } from './DshTheme';

@Component
export struct SshPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors();
  @Prop errorText: string = '';
  @Prop initialHostId: string = '';
  openControl: () => Promise<TransportControl> = async () => { throw new Error(this.t("SSH 连接服务不可用。")); };
  onConnect: (endpoint: TransportEndpoint) => Promise<boolean> = async () => false;
  onClose: () => void = () => {};
  onBackHandler?: (handler: (() => boolean) | undefined) => void;
  @State private hosts: SshHost[] = [];
  @State private editing: boolean = false;
  @State private busy: boolean = false;
  @State private handingOff: boolean = false;
  @State private notice: string = '';
  @State private fingerprint: string = '';
  @State private name: string = '';
  @State private address: string = '';
  @State private port: string = '22';
  @State private user: string = '';
  @State private useKey: boolean = false;
  @State private secret: string = '';
  @State private passphrase: string = '';
  @State private command: string = 'dsh web';
  @State private directory: string = '';
  @State private advanced: boolean = false;
  @State private saved: boolean = false;
  @State private storedId: string = '';
  private existing?: SshHost;
  private pendingHost?: SshHost;
  private bridge?: SshBridge;
  private generation: number = 0;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.onBackHandler?.(() => this.back());
    const generation = this.generation;
    listSshHosts(this.context()).then((hosts: SshHost[]) => {
      if (this.owns(generation)) {
        this.hosts = hosts;
        if (this.initialHostId) {
          const id = this.initialHostId.replace(/^ssh:/, '');
          const host = hosts.find((item: SshHost) => item.id === id);
          if (host) { this.edit(host); this.notice = this.t("已选中上次 SSH 主机，请输入未保存的登录凭据后连接。"); }
          else this.notice = this.t("上次 SSH 主机已不存在，请选择主机。");
        }
      }
    }).catch(() => {
      if (this.owns(generation)) this.notice = this.t("无法读取已保存的 SSH 主机。");
    });
  }

  aboutToDisappear(): void {
    this.active = false;
    this.onBackHandler?.(undefined);
    this.abort();
    this.secret = '';
    this.passphrase = '';
  }

  private owns(generation: number): boolean {
    return this.active && generation === this.generation;
  }

  private back(): boolean {
    if (this.handingOff) return true;
    if (!this.editing) return false;
    this.abort();
    this.secret = '';
    this.passphrase = '';
    this.editing = false;
    return true;
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private abort(): void {
    this.generation++;
    void this.bridge?.close();
    this.bridge = undefined;
    this.busy = false;
    this.fingerprint = '';
    this.pendingHost = undefined;
    this.notice = '';
  }

  private edit(host?: SshHost): void {
    this.abort();
    this.existing = host;
    this.storedId = host?.id || '';
    this.name = host?.name || '';
    this.address = host?.host || '';
    this.port = String(host?.port || 22);
    this.user = host?.user || '';
    this.useKey = host?.auth === 'key';
    this.secret = '';
    this.passphrase = '';
    this.command = host?.command || 'dsh web';
    this.directory = host?.directory || '';
    this.advanced = !!this.directory || this.command !== 'dsh web';
    this.saved = true;
    this.editing = true;
  }

  private draft(): SshHost {
    const address = this.address.trim().replace(/^\[([^\]]+)\]$/, '$1').toLowerCase();
    const port = /^\d{1,5}$/.test(this.port.trim()) ? Number(this.port.trim()) : 0;
    const existing = this.existing;
    const sameHost = existing?.host === address && existing.port === port;
    const result: SshHost = { id: existing?.id || util.generateRandomUUID(), name: this.name.trim() || address,
      host: address, port: port, user: this.user.trim(), auth: this.useKey ? 'key' : 'password',
      fingerprint: sameHost ? existing?.fingerprint || '' : '', command: this.command.trim() || 'dsh web',
      directory: this.directory.trim() };
    validateSshHost(result);
    return result;
  }

  private async connect(trusted: boolean = false): Promise<void> {
    if (this.busy) return;
    let host: SshHost;
    try {
      if (trusted) {
        const pending = this.pendingHost;
        if (!pending || !SSH_FINGERPRINT.test(this.fingerprint)) return;
        pending.fingerprint = this.fingerprint;
        host = pending;
        this.existing = pending;
      } else {
        host = this.draft();
      }
      if (!this.secret || this.secret.length > (host.auth === 'key' ? 32768 : 4096) || this.passphrase.length > 4096) {
        throw new Error(host.auth === 'key' ? this.t("请输入有效的 SSH 私钥。") : this.t("请输入有效的 SSH 密码。"));
      }
    } catch (error) {
      this.notice = error instanceof Error ? error.message : this.t("SSH 配置无效。");
      return;
    }
    const generation = ++this.generation;
    const secret = this.secret;
    const passphrase = this.passphrase;
    this.busy = true;
    this.fingerprint = '';
    this.notice = this.t("正在连接 SSH 并检查远程 DSH…");
    let endpoint: TransportEndpoint | undefined;
    let handedOff = false;
    try {
      const control = await this.openControl();
      if (!this.owns(generation)) return;
      const bridge = new SshBridge(control);
      this.bridge = bridge;
      endpoint = await bridge.connect(host, secret, passphrase);
      if (!this.owns(generation)) return;
      if (this.saved) {
        this.hosts = await updateSshHosts(this.context(), host.id, host);
        if (!this.owns(generation)) return;
        this.existing = host;
      }
      this.notice = this.t("SSH 已连接，正在登录远程 DSH…");
      this.bridge = undefined;
      this.handingOff = true;
      handedOff = await this.onConnect(endpoint);
      if (!handedOff && this.owns(generation)) this.notice = this.errorText || this.t("无法登录远程 DSH，请检查主机状态后重试。");
    } catch (error) {
      if (this.owns(generation)) {
        if (error instanceof SshBridgeError && error.code === 'host-key-required' && error.fingerprint) {
          this.pendingHost = host;
          this.fingerprint = error.fingerprint;
        } else if (error instanceof SshBridgeError && error.code === 'host-key-mismatch' && error.fingerprint) {
          this.notice = this.f("{0}\n已保存：{1}\n本次收到：{2}", [error.message, host.fingerprint, error.fingerprint]);
        } else {
          this.notice = error instanceof Error ? error.message : this.t("无法连接 SSH 主机。");
        }
      }
    } finally {
      if (!handedOff) await endpoint?.close();
      if (this.owns(generation)) {
        if (this.fingerprint) this.notice = '';
        this.bridge = undefined;
        this.busy = false;
        this.handingOff = false;
      }
    }
  }

  private async forget(): Promise<void> {
    const host = this.existing;
    if (!host || this.busy) return;
    this.busy = true;
    try {
      this.hosts = await updateSshHosts(this.context(), host.id);
      this.abort();
      this.secret = '';
      this.passphrase = '';
      this.editing = false;
    } catch {
      this.notice = this.t("无法删除 SSH 主机。");
    } finally {
      this.busy = false;
    }
  }

  @Builder
  private field(label: string, value: string, edit: (value: string) => void, secret: boolean = false) {
    Column({ space: 5 }) {
      Text(label).fontSize(13).fontColor(this.colors.muted).width('100%');
      TextInput({ text: value, placeholder: label }).width('100%').height(44).fontColor(this.colors.text)
        .backgroundColor(this.colors.surfaceAlt).placeholderColor(this.colors.hint).enabled(!this.busy && !this.fingerprint)
        .type(secret ? InputType.Password : InputType.Normal).enableAutoFill(!secret).accessibilityText(label).onChange(edit);
    }.width('100%');
  }

  @Builder
  private form() {
    this.field(this.t("主机名称"), this.name, (value: string) => { this.name = value; });
    Row({ space: 10 }) {
      Column() { this.field(this.t("主机地址"), this.address, (value: string) => { this.address = value; }); }.layoutWeight(1);
      Column() { this.field(this.t("端口"), this.port, (value: string) => { this.port = value; }); }.width(82);
    }.width('100%');
    this.field(this.t("SSH 用户名"), this.user, (value: string) => { this.user = value; });
    Row({ space: 8 }) {
      Text(this.t("认证方式")).fontSize(14).fontColor(this.colors.muted).layoutWeight(1);
      Button(this.t("密码")).fontColor(this.useKey ? this.colors.text : this.colors.onPrimary)
        .backgroundColor(this.useKey ? this.colors.surfaceAlt : this.colors.primary).enabled(!this.busy && !this.fingerprint)
        .onClick(() => { if (this.useKey) { this.useKey = false; this.secret = ''; this.passphrase = ''; } });
      Button(this.t("私钥")).fontColor(this.useKey ? this.colors.onPrimary : this.colors.text)
        .backgroundColor(this.useKey ? this.colors.primary : this.colors.surfaceAlt).enabled(!this.busy && !this.fingerprint)
        .onClick(() => { if (!this.useKey) { this.useKey = true; this.secret = ''; } });
    }.width('100%');
    if (this.useKey) {
      TextArea({ text: this.secret, placeholder: this.t("粘贴 OpenSSH 私钥") }).height(100).width('100%')
        .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).enabled(!this.busy && !this.fingerprint)
        .accessibilityText(this.t("SSH 私钥")).onChange((value: string) => { this.secret = value; });
      this.field(this.t("私钥口令（可选）"), this.passphrase, (value: string) => { this.passphrase = value; }, true);
    } else {
      this.field(this.t("SSH 密码"), this.secret, (value: string) => { this.secret = value; }, true);
    }
    Button(this.advanced ? this.t("收起远程启动设置") : this.t("远程启动设置")).fontColor(this.colors.primary)
      .backgroundColor(this.colors.surfaceAlt).onClick(() => { this.advanced = !this.advanced; });
    if (this.advanced) {
      this.field(this.t("DSH 启动命令"), this.command, (value: string) => { this.command = value; });
      this.field(this.t("远程工作目录（可选）"), this.directory, (value: string) => { this.directory = value; });
    }
    if (!this.storedId) {
      Row() {
        Text(this.t("保存主机与指纹")).fontSize(14).fontColor(this.colors.text).layoutWeight(1);
        Toggle({ type: ToggleType.Switch, isOn: this.saved }).enabled(!this.busy && !this.fingerprint)
          .onChange((value: boolean) => { this.saved = value; });
      }.width('100%');
    }
    Text(this.t("每次连接需输入密码或私钥。")).fontSize(12).fontColor(this.colors.hint).width('100%');
    if (this.fingerprint) {
      Text(this.t("请与主机管理员提供的 SSH 指纹核对。")).fontSize(14).fontColor(this.colors.text).width('100%');
      Text(this.fingerprint).fontSize(14).fontColor(this.colors.primary).width('100%').copyOption(CopyOptions.LocalDevice);
      Row({ space: 8 }) {
        Button(this.t("确认指纹并连接")).backgroundColor(this.colors.primary).fontColor(this.colors.onPrimary)
          .onClick(() => { void this.connect(true); });
        Button(this.t("取消")).backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.text).onClick(() => this.abort());
      }.width('100%');
    } else if (this.busy && !this.handingOff) {
      Button(this.t("取消连接")).backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.text).onClick(() => this.abort());
    } else if (!this.busy) {
      Row({ space: 8 }) {
        Button(this.t("连接")).backgroundColor(this.colors.primary).fontColor(this.colors.onPrimary).onClick(() => { void this.connect(); });
        if (this.storedId) {
          Button(this.t("删除主机")).backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.danger)
            .onClick(() => { void this.forget(); });
        }
      }.width('100%');
    }
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Button(this.t("返回")).backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.text).enabled(!this.handingOff).onClick(() => {
          if (!this.back()) this.onClose();
        });
        Text(this.t("SSH 主机")).fontSize(22).fontWeight(FontWeight.Medium).fontColor(this.colors.text).layoutWeight(1);
      }.width('100%').padding({ left: 14, right: 14, top: 10 });
      Scroll() {
        Column({ space: 12 }) {
          if (this.notice) Text(this.notice).fontSize(14).fontColor(this.busy ? this.colors.muted : this.colors.danger).width('100%');
          if (this.editing) {
            this.form();
          } else {
            ForEach(this.hosts, (host: SshHost) => {
              Button({ type: ButtonType.Normal }) {
                Column({ space: 4 }) {
                  Text(host.name).fontSize(16).fontColor(this.colors.text).width('100%');
                  Text(`${host.user}@${host.host} · ${host.port}`).fontSize(13).fontColor(this.colors.muted).width('100%');
                }.width('100%').padding(10);
              }.width('100%').backgroundColor(this.colors.surfaceAlt).borderRadius(12).onClick(() => this.edit(host));
            }, (host: SshHost) => `${host.id}/${host.name}/${host.host}/${host.port}/${host.user}`);
            Button(this.t("添加 SSH 主机")).backgroundColor(this.colors.primary).fontColor(this.colors.onPrimary)
              .width('100%').onClick(() => this.edit());
          }
        }.width('100%').padding(14);
      }.width('100%').layoutWeight(1);
    }.width('100%').height('100%').backgroundColor(this.colors.background);
  }
}
