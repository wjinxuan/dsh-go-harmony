import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { connection } from '@kit.NetworkKit';
import { DshClient } from '../dsh/DshClient';
import { ThemeColors, themeColors } from './DshTheme';
@Component
export struct NetworkDiagnosticsPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors();
  @Prop connected: boolean = false;
  client: DshClient = new DshClient();
  @State private busy: boolean = false;
  @State private result: string = '';
  private active: boolean = false;
  aboutToAppear(): void { this.active = true; }
  aboutToDisappear(): void { this.active = false; }
  private async diagnose(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    const generation = this.client.connectionIdentity();
    const lines: string[] = [];
    try {
      try {
        const net = await connection.getDefaultNet();
        if (net.netId === 0) lines.push(this.t("系统网络：未连接"));
        else {
          const capabilities = await connection.getNetCapabilities(net);
          const names: string[] = [];
          if (capabilities.bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) names.push('Wi-Fi');
          if (capabilities.bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR)) names.push(this.t("移动网络"));
          if (capabilities.bearerTypes.includes(connection.NetBearType.BEARER_ETHERNET)) names.push(this.t("以太网"));
          if (capabilities.bearerTypes.includes(connection.NetBearType.BEARER_VPN)) names.push('VPN');
          lines.push(this.t("系统网络：") + (names.join(' / ') || this.t("已连接")));
        }
      } catch { lines.push(this.t("系统网络：状态不可用")); }
      if (!this.connected) lines.push(this.t("DSH 主机：尚未连接"));
      else {
        const session = this.client.webSession();
        lines.push(this.t("当前服务：") + session.baseUrl);
        const start = Date.now();
        try { await this.client.engineCapabilities(); lines.push(this.f("认证请求：成功（{0} ms）", [Date.now() - start])); }
        catch { lines.push(this.t("认证请求：失败，请检查主机、网络和凭据")); }
        if (generation !== this.client.connectionIdentity()) lines.push(this.t("连接已切换，请重新检查"));
        else lines.push(this.t("实时连接：已建立"));
      }
      if (this.active) this.result = lines.join('\n');
    } catch { if (this.active) this.result = this.t("当前连接已关闭，请连接主机后重试。"); }
    finally { if (this.active) this.busy = false; }
  }
  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.t("网络诊断")).fontSize(17).fontColor(this.colors.text).layoutWeight(1);
        Button(this.busy ? this.t("检查中…") : this.t("开始检查")).height(34).fontSize(13).enabled(!this.busy).onClick(() => { void this.diagnose(); });
      }.width('100%');
      Text(this.t("检查系统网络与当前主机的认证请求。不会向其他诊断服务发送连接凭据。")).fontSize(12).fontColor(this.colors.muted);
      if (this.result) Text(this.result).fontSize(13).fontColor(this.colors.text).copyOption(CopyOptions.InApp).width('100%');
    }.alignItems(HorizontalAlign.Start).width('100%').padding(14).backgroundColor(this.colors.surface).borderRadius(14);
  }
}
