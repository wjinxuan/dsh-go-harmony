import { localizedSettingsText } from './SettingsLocale'
import { common } from '@kit.AbilityKit';
import { StartupSettings, loadStartupSettings, saveStartupOptions } from './StartupPreferences';
import { ThemeColors, themeColors } from './DshTheme';
@Component
export struct StartupPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors();
  getAppContext: () => common.UIAbilityContext = () => { throw new Error(this.t("应用上下文不可用")); };
  onChanged: (settings: StartupSettings) => void = () => {};
  @State private settings: StartupSettings = { autoStartLocal: true, restoreLastHost: true };
  @State private busy: boolean = true;
  @State private error: string = '';
  private active: boolean = false;
  aboutToAppear(): void { this.active = true; void this.load(); }
  aboutToDisappear(): void { this.active = false; }
  private async load(): Promise<void> {
    try { const value = await loadStartupSettings(this.getAppContext()); if (this.active) this.settings = value; }
    catch { if (this.active) this.error = this.t("启动设置未能读取。"); }
    finally { if (this.active) this.busy = false; }
  }
  private async save(local: boolean, restore: boolean): Promise<void> {
    if (this.busy) return;
    this.busy = true; this.error = '';
    try { const value = await saveStartupOptions(this.getAppContext(), local, restore);
      this.onChanged(value); if (this.active) this.settings = value;
    } catch { if (this.active) this.error = this.t("启动设置未能保存，请重试。"); }
    finally { if (this.active) this.busy = false; }
  }
  build() {
    Column({ space: 10 }) {
      Text(this.t("应用启动")).fontSize(17).fontColor(this.colors.text);
      Row({ space: 8 }) {
        Text(this.t("打开应用时启动本机引擎")).fontSize(13).fontColor(this.colors.text).layoutWeight(1);
        Toggle({ type: ToggleType.Switch, isOn: this.settings.autoStartLocal }).enabled(!this.busy)
          .onChange((value: boolean) => { if (value !== this.settings.autoStartLocal) void this.save(value, this.settings.restoreLastHost); });
      }.width('100%');
      Row({ space: 8 }) {
        Text(this.t("启动时恢复上次远程主机")).fontSize(13).fontColor(this.colors.text).layoutWeight(1);
        Toggle({ type: ToggleType.Switch, isOn: this.settings.restoreLastHost }).enabled(!this.busy)
          .onChange((value: boolean) => { if (value !== this.settings.restoreLastHost) void this.save(this.settings.autoStartLocal, value); });
      }.width('100%');
      Text(this.t("上次远程主机优先恢复；凭据失效时停留在连接页。设置从下次打开应用生效。")).fontSize(12).fontColor(this.colors.muted);
      if (this.error) Text(this.t(this.error)).fontSize(13).fontColor(this.colors.danger);
    }.alignItems(HorizontalAlign.Start).width('100%').padding(14).backgroundColor(this.colors.surface).borderRadius(14);
  }
}
