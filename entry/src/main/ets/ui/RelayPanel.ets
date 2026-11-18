import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util, url } from '@kit.ArkTS';
import { rcp } from '@kit.RemoteCommunicationKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { array, object, string, WireObject } from '../dsh/DshWire';
import { TransportControl, TransportEndpoint } from '../remote/TransportEndpoint';
import { ThemeColors, themeColors } from './DshTheme';

interface RelayProvider {
  id: string;
  name: string;
}

interface RelayHost {
  scope: string;
  id: string;
  name: string;
  online: boolean;
}

interface PairingDetails {
  id: string;
  name: string;
  origin: string;
  hostFingerprint: string;
  serverFingerprint: string;
}

const relayStore = 'dsh-remote-preferences';
const originKey = 'server-origin';
const defaultOrigin = 'https://dsh.r2049.cn';

class RelayError extends Error {
  readonly code: string;
  constructor(code: string) {
    super(relayError(code));
    this.code = code;
  }
}

function relayError(code: string): string {
  switch (code) {
    case 'SERVER_ORIGIN_INVALID': return '请输入有效的中继服务器地址。公网地址需要使用 HTTPS。';
    case 'PAIRING_SERVER_MISMATCH': return '二维码属于另一台中继服务器。核对二维码来源后，请先修改上方服务器地址。';
    case 'PAIRING_SCAN_INVALID': return '这不是有效的 DSHarness Remote 配对二维码。';
    case 'PAIRING_UNSUPPORTED': return '该中继服务器不支持这类设备配对。';
    case 'PAIRING_EXPIRED': return '配对或登录链接已过期，请重新开始。';
    case 'PAIRING_ACCOUNT_CONFLICT': return '此设备已在该服务器登录另一个账号。退出后可重新配对。';
    case 'PAIRING_IDENTITY_MISMATCH':
    case 'PEER_IDENTITY_MISMATCH': return '电脑或服务器的身份与已确认的指纹不符，连接已拒绝。';
    case 'PAIRING_FAILED': return '配对未完成，请在电脑上重新显示二维码。';
    case 'AUTH_INVALID':
    case 'AUTH_REQUIRED':
    case 'TOKEN_EXPIRED':
    case 'ACCOUNT_AUTH_REQUIRED': return '中继授权已失效，请重新登录或配对。';
    case 'HOST_OFFLINE': return '这台电脑当前离线。';
    case 'HOST_KEY_UNTRUSTED': return '请先在电脑上核对并确认主机指纹。';
    case 'HARNESS_VERSION_INCOMPATIBLE': return '电脑上的 DSHarness Remote 或 DeepSeek Harness 版本不兼容。';
    case 'SECURE_CHANNEL_FAILED': return '无法建立端到端加密连接，请核对电脑身份与中继服务。';
    case 'RATE_LIMITED': return '中继请求过多，请稍后再试。';
    case 'RELAY_STORAGE_FAILED': return '无法安全读取或保存中继凭据。';
    default: return '无法连接 DSHarness Remote，请检查网络和服务器状态。';
  }
}

async function relayRequest(control: TransportControl, path: string, args: WireObject): Promise<WireObject> {
  const address = /^http:\/\/127\.0\.0\.1:([1-9]\d{0,4})$/.exec(control.url);
  if (!address || Number(address[1]) > 65535 || !/^Bearer [A-Za-z0-9_-]{43}$/.test(control.authorization)) {
    throw new RelayError('INVALID_CONTROL');
  }
  const session = rcp.createSession({ requestConfiguration: { proxy: 'no-proxy',
    transfer: { autoRedirect: false, timeout: { connectMs: 3000, transferMs: path === 'connect' ? 100000 : 52000 } } } });
  let response: WireObject;
  try {
    const request = new rcp.Request(control.url + '/relay/' + path, 'POST',
      { authorization: control.authorization, 'content-type': 'application/json' }, JSON.stringify(args));
    const result = await session.fetch(request);
    if (result.statusCode !== 200 || !result.body || result.body.byteLength > 512 * 1024) throw new Error();
    response = object(JSON.parse(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(result.body))));
  } catch {
    throw new RelayError('CONNECTION_FAILED');
  } finally {
    session.close();
  }
  if (response['ok'] !== true) throw new RelayError(string(response['code']));
  return object(response['value']);
}

@Component
export struct RelayPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors();
  @Prop initialHostId: string = '';
  @Prop autoRestore: boolean = false;
  private initialAttempted: boolean = false;
  openControl: () => Promise<TransportControl> = async () => { throw new Error(this.t("中继连接服务不可用。")); };
  onConnect: (endpoint: TransportEndpoint) => Promise<boolean> = async () => false;
  onClose: () => void = () => {};

  @State private origin: string = defaultOrigin;
  @State private scanValue: string = '';
  @State private providers: RelayProvider[] = [];
  @State private hosts: RelayHost[] = [];
  @State private signedIn: boolean = false;
  @State private passwordForm: boolean = false;
  @State private email: string = '';
  @State private password: string = '';
  @State private pairing: PairingDetails | undefined = undefined;
  @State private code: string = '';
  @State private stage: string = '';
  @State private failure: string = '';
  @State private busy: boolean = false;
  private control?: TransportControl;
  private operationId: string = '';
  private browserLink: string = '';
  private generation: number = 0;
  private active: boolean = false;
  private readonly retryable: string[] = ['RATE_LIMITED', 'CONNECTION_FAILED', 'RELAY_STORAGE_FAILED'];

  aboutToAppear(): void {
    this.active = true;
    void this.restoreOrigin();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.retire();
  }

  private current(generation: number): boolean {
    return this.active && generation === this.generation;
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async restoreOrigin(): Promise<void> {
    const generation = ++this.generation;
    this.busy = true;
    try {
      const store = await preferences.getPreferences(this.context(), relayStore);
      if (this.current(generation)) this.origin = store.getSync(originKey, defaultOrigin) as string;
    } catch {}
    if (this.current(generation)) {
      this.busy = false;
      await this.reload();
    }
  }

  private async rememberOrigin(origin: string, generation: number): Promise<void> {
    if (!origin || origin.length > 2048) return;
    try {
      const store = await preferences.getPreferences(this.context(), relayStore);
      if (!this.current(generation)) return;
      store.putSync(originKey, origin);
      await store.flush();
    } catch {}
  }

  private retire(): void {
    this.generation++;
    const id = this.operationId;
    const control = this.control;
    if (id && control) void relayRequest(control, 'cancel', { 'id': id }).catch(() => {});
    this.operationId = '';
    this.browserLink = '';
    this.scanValue = '';
    this.password = '';
    this.code = '';
    this.stage = '';
    this.pairing = undefined;
    this.busy = false;
  }

  private async request(path: string, args: WireObject, generation: number): Promise<WireObject> {
    const control = this.control ?? await this.openControl();
    if (!this.current(generation)) throw new Error(this.t("连接已取消。"));
    this.control = control;
    args['origin'] = this.origin.trim();
    const response = await relayRequest(control, path, args);
    if (!this.current(generation)) {
      const id = string(response['id']);
      if (id && path === 'connect') void relayRequest(control, 'disconnect', { 'id': id }).catch(() => {});
      if (id && (path === 'pair/resolve' || path === 'browser/start')) {
        void relayRequest(control, 'cancel', { 'id': id }).catch(() => {});
      }
      throw new Error(this.t("连接已取消。"));
    }
    return response;
  }

  private fail(error: Error, generation: number): void {
    if (this.current(generation)) this.failure = error.message || this.t("中继请求失败。");
  }

  private async reload(): Promise<void> {
    if (this.busy) return;
    const generation = ++this.generation;
    this.busy = true;
    this.failure = '';
    try {
      const result = await this.request('hosts', {}, generation);
      void this.rememberOrigin(string(result['origin']), generation);
      this.signedIn = result['signedIn'] === true;
      this.hosts = array(result['hosts']).map((item: Object): RelayHost => {
        const row = object(item);
        return { id: string(row['id']), scope: string(row['scope']), name: string(row['name']), online: row['online'] === true };
      });
      if (!this.signedIn) {
        const login = await this.request('providers', {}, generation);
        this.providers = array(login['items']).map((item: Object): RelayProvider => {
          const row = object(item);
          return { id: string(row['id']), name: string(row['name']) };
        });
      }
    } catch (error) { this.fail(error as Error, generation); }
    finally { if (this.current(generation)) this.busy = false; }
    if (this.current(generation) && this.autoRestore && this.initialHostId && !this.initialAttempted) {
      this.initialAttempted = true;
      const host = this.hosts.find((item: RelayHost) => item.scope === this.initialHostId);
      if (!this.signedIn) this.failure = this.t("上次中继账号已退出，请重新登录后连接。");
      else if (!host) this.failure = this.t("上次中继主机已不存在或服务器已更改，请选择主机。");
      else if (!host.online) this.failure = this.t("上次连接的电脑当前离线。");
      else await this.connect(host, '', true);
    }
  }

  private async scan(): Promise<void> {
    if (this.busy) return;
    const generation = ++this.generation;
    this.busy = true;
    this.failure = '';
    try {
      const result = await scanBarcode.startScanForResult(this.context(), { scanTypes: [scanCore.ScanType.QR_CODE] });
      if (!this.current(generation)) return;
      this.scanValue = result.originalValue.slice(0, 4096);
    } catch {
      if (this.current(generation)) this.failure = this.t("未取得二维码，可以粘贴电脑显示的配对链接。");
    } finally { if (this.current(generation)) this.busy = false; }
    if (this.current(generation) && this.scanValue) await this.resolvePairing();
  }

  private async resolvePairing(): Promise<void> {
    if (this.busy || !this.scanValue.trim()) return;
    const generation = ++this.generation;
    this.busy = true;
    this.failure = '';
    try {
      const reply = await this.request('pair/resolve', { 'scan': this.scanValue }, generation);
      this.scanValue = '';
      this.operationId = string(reply['id']);
      this.pairing = { id: this.operationId, name: string(reply['host']), origin: string(reply['origin']),
        hostFingerprint: string(reply['hostFingerprint']), serverFingerprint: string(reply['serverFingerprint']) };
    } catch (error) { this.fail(error as Error, generation); }
    finally { if (this.current(generation)) this.busy = false; }
  }

  private async claim(): Promise<void> {
    const pairing = this.pairing;
    if (this.busy || !pairing) return;
    const generation = this.generation;
    this.busy = true;
    this.failure = '';
    try {
      const result = await this.request('pair/claim', { 'id': pairing.id }, generation);
      this.code = string(result['code']);
      const expiresAt = Number(result['expiresAt']);
      if (!/^[0-9]{8}$/.test(this.code) || !Number.isFinite(expiresAt)) throw new Error(relayError('PAIRING_FAILED'));
      this.stage = this.t("在电脑上输入验证码，完成后返回此页。");
      await this.poll('pair/status', pairing.id, expiresAt + 300000, generation);
    } catch (error) { this.fail(error as Error, generation); }
    finally {
      if (this.current(generation)) {
        this.busy = false;
        this.code = '';
        this.stage = '';
        if (!this.operationId) this.pairing = undefined;
      }
    }
    if (this.current(generation) && !this.operationId) await this.reload();
  }

  private async openBrowser(): Promise<void> {
    const generation = this.generation;
    if (!this.browserLink) return;
    try {
      const address = url.URL.parseURL(this.browserLink);
      if ((address.protocol !== 'http:' && address.protocol !== 'https:') || address.username || address.password ||
        address.hash || !address.pathname.startsWith('/api/v1/auth/')) throw new Error();
      await this.context().openLink(this.browserLink);
    } catch {
      if (this.current(generation)) this.failure = this.t("无法打开登录页面，可以重试打开浏览器。");
    }
  }

  private async login(provider: RelayProvider): Promise<void> {
    if (this.busy) return;
    const generation = ++this.generation;
    this.busy = true;
    this.failure = '';
    try {
      const result = await this.request('browser/start', { 'provider': provider.id }, generation);
      this.operationId = string(result['id']);
      this.browserLink = string(result['url']);
      this.stage = this.t("请在浏览器完成登录，然后返回此页。");
      void this.openBrowser();
      await this.poll('browser/status', this.operationId, Number(result['expiresAt']), generation);
    } catch (error) { this.fail(error as Error, generation); }
    finally {
      if (this.current(generation)) {
        this.busy = false;
        if (!this.operationId) {
          this.browserLink = '';
          this.stage = '';
        }
      }
    }
    if (this.current(generation) && !this.operationId && !this.failure) await this.reload();
  }

  private async loginWithPassword(): Promise<void> {
    if (this.busy || !this.email.trim() || !this.password) return;
    const generation = ++this.generation;
    const secret = this.password;
    this.password = '';
    this.busy = true;
    this.failure = '';
    try {
      await this.request('password', { 'email': this.email.trim(), 'password': secret }, generation);
      this.passwordForm = false;
      this.email = '';
    } catch (error) {
      if (this.current(generation) && error instanceof RelayError && error.code === 'AUTH_INVALID') {
        this.failure = this.t("中继服务器拒绝登录，请核对账号与密码。");
      } else this.fail(error as Error, generation);
    } finally { if (this.current(generation)) this.busy = false; }
    if (this.current(generation) && !this.failure) await this.reload();
  }

  private async poll(path: string, id: string, expiresAt: number, generation: number): Promise<void> {
    let delay = 1500;
    while (this.current(generation) && Date.now() < expiresAt) {
      let reply: WireObject;
      try {
        reply = await this.request(path, { 'id': id }, generation);
        delay = 1500;
      } catch (error) {
        if (!this.current(generation) || !(error instanceof RelayError) || !this.retryable.includes(error.code)) throw error as Error;
        await new Promise<void>(resolve => { setTimeout(resolve, delay); });
        delay = Math.min(15000, delay * 2);
        continue;
      }
      const state = string(reply['state']);
      if (state === 'completed') {
        this.operationId = '';
        return;
      }
      if (state === 'failed' || state === 'cancelled' || state === 'expired') {
        this.operationId = '';
        throw new Error(relayError(state === 'expired' ? 'PAIRING_EXPIRED' : 'PAIRING_FAILED'));
      }
      await new Promise<void>(resolve => { setTimeout(resolve, delay); });
    }
    if (this.current(generation)) {
      this.retire();
      this.failure = relayError('PAIRING_EXPIRED');
    }
  }

  private async connect(host: RelayHost, accepted: string = '', trustedOnly: boolean = false): Promise<void> {
    if (this.busy || !host.online) return;
    const generation = ++this.generation;
    this.busy = true;
    this.failure = '';
    this.stage = this.t("正在验证主机身份…");
    let endpoint: TransportEndpoint | undefined;
    try {
      if (!accepted) {
        const peer = await this.request('peer', { 'hostId': host.id }, generation);
        const fingerprint = string(peer['fingerprint']);
        if (!/^[a-f0-9]{64}$/.test(fingerprint)) throw new Error(relayError('PEER_IDENTITY_MISMATCH'));
        if (peer['trusted'] !== true) {
          if (trustedOnly) throw new Error(this.t("上次主机的身份尚未确认或发生变化，请手动核对指纹后连接。"));
          this.getUIContext().showAlertDialog({
            title: this.t("确认电脑指纹"),
            message: this.t("请核对电脑上 DSHarness Remote 显示的身份指纹。\n") + fingerprint,
            primaryButton: { value: this.t("取消"), action: () => {} },
            secondaryButton: { value: this.t("指纹一致，连接"), action: () => {
              if (this.current(generation)) void this.connect(host, fingerprint);
            } }
          });
          return;
        }
        accepted = fingerprint;
      }
      this.stage = this.t("正在建立端到端加密连接…");
      const result = await this.request('connect', { 'hostId': host.id, 'fingerprint': accepted }, generation);
      const control = this.control!;
      const id = string(result['id']);
      const launchUrl = string(result['launchUrl']);
      const match = /^http:\/\/127\.0\.0\.1:([1-9]\d{0,4})\/\?token=[A-Za-z0-9_-]{43}$/.exec(launchUrl);
      const close = async (): Promise<void> => {
        if (id) await relayRequest(control, 'disconnect', { 'id': id }).catch(() => {});
      };
      if (!id || !match || Number(match[1]) > 65535) { await close(); throw new Error(relayError('INVALID_CONTROL')); }
      const route = string(result['transport']);
      endpoint = { launchUrl: launchUrl, name: string(result['name']) || host.name, scope: string(result['scope']),
        route: ['lan', 'p2p', 'turn', 'relay'].includes(route) ? route : 'relay', close: close };
      if (await this.onConnect(endpoint)) endpoint = undefined;
      else if (this.current(generation)) this.failure = this.t("加密连接已建立，但未能打开 DSH 会话。");
    } catch (error) { this.fail(error as Error, generation); }
    finally {
      await endpoint?.close();
      if (this.current(generation)) { this.busy = false; this.stage = ''; }
    }
  }

  private async logout(): Promise<void> {
    if (this.busy) return;
    const generation = ++this.generation;
    this.busy = true;
    this.failure = '';
    try {
      await this.request('logout', {}, generation);
      this.hosts = [];
      this.signedIn = false;
    } catch (error) { this.fail(error as Error, generation); }
    finally { if (this.current(generation)) this.busy = false; }
    if (this.current(generation) && !this.failure) await this.reload();
  }

  @Builder
  private pairCard() {
    Column({ space: 10 }) {
      Text(this.t("确认电脑")).fontWeight(FontWeight.Medium).fontSize(18).fontColor(this.colors.text).width('100%');
      Text(this.pairing?.name || '').fontSize(15).fontColor(this.colors.text).width('100%');
      Text(this.pairing?.origin || '').fontSize(13).fontColor(this.colors.muted).width('100%');
      Text(this.t("电脑指纹")).fontSize(13).fontColor(this.colors.muted).width('100%');
      Text(this.pairing?.hostFingerprint || '').fontSize(13).fontColor(this.colors.text).width('100%').copyOption(CopyOptions.None);
      Text(this.t("服务器指纹")).fontSize(13).fontColor(this.colors.muted).width('100%');
      Text(this.pairing?.serverFingerprint || '').fontSize(13).fontColor(this.colors.text).width('100%').copyOption(CopyOptions.None);
      if (this.code) {
        Text(this.code).fontSize(32).fontWeight(FontWeight.Medium).fontColor(this.colors.text).letterSpacing(4)
          .copyOption(CopyOptions.None).accessibilityText(this.t("电脑配对验证码 ") + this.code);
      } else {
        Button(this.t("指纹一致，开始配对")).width('100%').enabled(!this.busy).onClick(() => { void this.claim(); });
      }
      Button(this.t("取消配对")).width('100%').fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
        .onClick(() => this.retire());
    }.width('100%').padding(16).backgroundColor(this.colors.surface).borderRadius(14);
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Button(this.t("返回")).height(44).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).onClick(this.onClose);
        Text('DSHarness Remote').fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.colors.text).layoutWeight(1);
      }.width('100%').padding(12);
      Scroll() {
        Column({ space: 12 }) {
          TextInput({ placeholder: this.t("中继服务器地址"), text: this.origin }).enabled(!this.busy && !this.pairing && !this.operationId)
            .backgroundColor(this.colors.surface).fontColor(this.colors.text).width('100%').onChange((value: string) => {
              this.origin = value;
              this.hosts = [];
              this.providers = [];
              this.signedIn = false;
            });
          if (this.failure) {
            Text(this.t(this.failure)).fontSize(14).fontColor(this.colors.warning).width('100%').lineHeight(21);
          }
          if (this.stage || this.busy) {
            Text(this.stage || this.t("正在读取中继状态…")).fontSize(14).fontColor(this.colors.muted).width('100%').lineHeight(21);
          }
          if (this.pairing) {
            this.pairCard();
          } else if (this.operationId && this.browserLink) {
            Button(this.t("重新打开浏览器")).width('100%').onClick(() => { void this.openBrowser(); });
            Button(this.t("取消登录")).width('100%').fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
              .onClick(() => this.retire());
          } else {
            if (this.signedIn) {
              Text(this.t("电脑")).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%');
              if (!this.hosts.length) Text(this.t("该账号暂无可连接的电脑。")).fontSize(14).fontColor(this.colors.muted).width('100%');
              ForEach(this.hosts, (host: RelayHost) => {
                Button(host.name + (host.online ? '' : this.t(" · 离线"))).width('100%').height(48).enabled(host.online && !this.busy)
                  .fontColor(this.colors.text).backgroundColor(this.colors.surface).onClick(() => { void this.connect(host); });
              }, (host: RelayHost) => host.id);
              Button(this.t("退出中继账号")).width('100%').height(44).fontColor(this.colors.danger).backgroundColor(this.colors.surfaceAlt)
                .enabled(!this.busy).onClick(() => {
                  const generation = this.generation;
                  this.getUIContext().showAlertDialog({
                    title: this.t("退出中继账号？"), message: this.t("这将撤销本机在该中继服务器的设备授权。"),
                    primaryButton: { value: this.t("取消"), action: () => {} },
                    secondaryButton: { value: this.t("退出"), action: () => {
                      if (this.current(generation)) void this.logout();
                    } }
                  });
                });
            } else {
              ForEach(this.providers, (provider: RelayProvider) => {
                Button(this.f("使用 {0} 登录", [provider.name])).width('100%').height(44).enabled(!this.busy)
                  .onClick(() => { void this.login(provider); });
              }, (provider: RelayProvider) => provider.id);
              if (this.passwordForm) {
                TextInput({ placeholder: this.t("中继账号邮箱"), text: this.email }).maxLength(254).enabled(!this.busy)
                  .backgroundColor(this.colors.surface).fontColor(this.colors.text).width('100%')
                  .onChange((value: string) => { this.email = value; });
                TextInput({ placeholder: this.t("中继账号密码"), text: this.password }).maxLength(1024).type(InputType.Password).enableAutoFill(false)
                  .enabled(!this.busy).backgroundColor(this.colors.surface).fontColor(this.colors.text).width('100%')
                  .onChange((value: string) => { this.password = value; });
                Button(this.t("登录中继账号")).width('100%').height(44).enabled(!this.busy && !!this.email.trim() && !!this.password)
                  .onClick(() => { void this.loginWithPassword(); });
              } else {
                Button(this.t("使用邮箱和密码登录")).width('100%').height(44).enabled(!this.busy)
                  .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
                  .onClick(() => { this.passwordForm = true; });
              }
            }
            Button(this.t("刷新服务器状态")).width('100%').height(44).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
              .enabled(!this.busy).onClick(() => { void this.reload(); });
            Button(this.t("扫描电脑配对二维码")).width('100%').height(44).enabled(!this.busy).onClick(() => { void this.scan(); });
            TextInput({ placeholder: this.t("或粘贴电脑的配对链接"), text: this.scanValue }).type(InputType.Password)
              .maxLength(4096).enabled(!this.busy).backgroundColor(this.colors.surface).fontColor(this.colors.text).width('100%')
              .onChange((value: string) => { this.scanValue = value; });
            Button(this.t("核对配对设备")).width('100%').height(44).enabled(!this.busy && !!this.scanValue.trim())
              .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).onClick(() => { void this.resolvePairing(); });
          }
        }.width('100%').padding(16);
      }.layoutWeight(1).width('100%').scrollable(ScrollDirection.Vertical);
    }.width('100%').height('100%').backgroundColor(this.colors.background);
  }
}
