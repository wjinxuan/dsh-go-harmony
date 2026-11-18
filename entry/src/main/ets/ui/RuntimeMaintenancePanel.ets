import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { bundledRuntimeVersion } from '../local/LocalEngine';
import { common } from '@kit.AbilityKit';
import { emptyRuntimeMaintenanceState, RuntimeMaintenanceState, readRuntimeMaintenance, requestRuntimeMode,
  readRuntimeLog, restoreGoodRuntimeProfile, probeRuntimeShell, requestRuntimeReset } from '../local/RuntimeMaintenance';
import { ThemeColors, themeColors } from './DshTheme';

@Component
export struct RuntimeMaintenancePanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors();
  @Prop running: boolean = false;
  @Prop busy: boolean = false;
  getAppContext: () => common.UIAbilityContext = () => { throw new Error(this.t("应用上下文不可用")); };
  onRestart: () => Promise<void> = async () => {};
  onStop: () => Promise<void> = async () => {};
  onWorkingChange: (working: boolean) => void = () => {};
  @State private resetOptions: boolean = false;
  @State private keepUiSkills: boolean = true;
  @State private keepPluginsSettings: boolean = false;
  @State private state: RuntimeMaintenanceState = emptyRuntimeMaintenanceState();
  @State private working: boolean = false;
  @State private error: string = '';
  @State private logs: string = '';
  @State private bundledVersion: string = '';
  @State private shell: string = '';
  private active: boolean = false;
  aboutToAppear(): void { this.active = true; void this.refresh(); }
  aboutToDisappear(): void { this.active = false; }
  private async refresh(): Promise<void> {
    try { const state = await readRuntimeMaintenance(this.getAppContext());
      const bundled = await bundledRuntimeVersion(this.getAppContext());
      if (this.active) { this.state = state; this.bundledVersion = bundled; } }
    catch { if (this.active) this.error = this.t("本机引擎状态未能读取。"); }
  }
  private async act(action: string): Promise<void> {
    if (this.busy || this.working) return;
    this.working = true; this.onWorkingChange(true); this.error = '';
    try {
      const context = this.getAppContext();
      if (action === 'logs') this.logs = await readRuntimeLog(context);
      else if (action === 'update') { await this.onStop(); await this.onRestart(); }
      else if (action === 'shell') this.shell = await probeRuntimeShell();
      else if (action === 'reset') {
        await this.onStop();
        await requestRuntimeReset(context, this.keepUiSkills, this.keepPluginsSettings);
        await this.onRestart(); this.resetOptions = false;
      }
      else if (action === 'restore') { await this.onStop(); await restoreGoodRuntimeProfile(context); await this.onRestart(); }
      else if (action === 'auto') {
        await requestRuntimeMode(context, '', !this.state.autoSafe);
        this.state = { phase: this.state.phase, mode: this.state.mode, safeState: this.state.safeState,
          autoSafe: !this.state.autoSafe, strikes: this.state.strikes, nodeVersion: this.state.nodeVersion,
          dshVersion: this.state.dshVersion, runtimeVersion: this.state.runtimeVersion, failure: this.state.failure, goodProfileAvailable: this.state.goodProfileAvailable };
        return;
      } else { await requestRuntimeMode(context, action, this.state.autoSafe); await this.onRestart(); }
      if (this.active) await this.refresh();
    } catch { if (this.active) this.error = this.t("引擎维护操作未完成，请检查引擎状态后重试。"); }
    finally { this.working = false; this.onWorkingChange(false); }
  }
  private confirmRestore(): void {
    AlertDialog.show({ title: this.t("恢复上次正常配置"), message: this.t("将停止引擎并恢复最近一次连续正常运行两分钟的配置。当前配置会保留备份，对话、工作区、账号和语音模型保持原样。"),
      primaryButton: { value: this.t("取消"), action: () => {} },
      secondaryButton: { value: this.t("恢复并重启"), action: () => { void this.act('restore'); } } });
  }
  private confirmReset(): void {
    AlertDialog.show({ title: this.t("确认删除并重置"),
      message: this.f("这会删除本机对话、工作区文件、已下载语音模型和账号授权。{0}{1}操作无法撤销。", [this.keepUiSkills ? this.t("保留界面设置和技能。") : this.t("界面设置和技能也会删除。"), this.keepPluginsSettings ? this.t("保留插件和引擎设置。") : this.t("插件和引擎设置也会删除。")]),
      primaryButton: { value: this.t("取消"), action: () => {} },
      secondaryButton: { value: this.t("删除并重置"), action: () => { void this.act('reset'); } } });
  }
  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.t("恢复与诊断")).fontSize(17).fontColor(this.colors.text).layoutWeight(1);
        Button(this.t("刷新")).height(32).fontSize(12).enabled(!this.working && !this.busy).onClick(() => { void this.refresh(); });
      }.width('100%');
      Text(`DSH ${this.state.dshVersion || this.t("待启动")} · Node ${this.state.nodeVersion || this.t("待启动")}`).fontSize(13).fontColor(this.colors.muted);
      if (this.bundledVersion) {
        Text(this.f("应用内引擎 {0}{1}", [this.bundledVersion.slice(0, 12), this.state.runtimeVersion ? this.t(" · 当前 ") + this.state.runtimeVersion.slice(0, 12) : ''])).fontSize(12).fontColor(this.colors.muted);
        if (this.running && this.state.runtimeVersion && this.state.runtimeVersion !== this.bundledVersion) {
          Button(this.t("应用更新并重启引擎")).height(36).fontSize(13).enabled(!this.working && !this.busy).onClick(() => { void this.act('update'); });
        }
      }
      Text(this.state.mode === 'safe' ? this.t("安全模式：使用干净配置启动，原配置保留。") : this.state.safeState === 'probation' ? this.t("正常模式试运行中。") : this.t("正常模式"))
        .fontSize(13).fontColor(this.colors.muted);
      if (this.state.failure) Text(this.state.failure).fontSize(12).fontColor(this.colors.danger).maxLines(5);
      Row({ space: 8 }) {
        Text(this.t("连续启动失败时自动进入安全模式")).fontSize(13).fontColor(this.colors.text).layoutWeight(1);
        Toggle({ type: ToggleType.Switch, isOn: this.state.autoSafe }).enabled(!this.working && !this.busy)
          .onChange((value: boolean) => { if (value !== this.state.autoSafe) void this.act('auto'); });
      }.width('100%');
      Text(this.t("自动恢复设置在下一次启动生效。")).fontSize(12).fontColor(this.colors.muted);
      Row({ space: 8 }) {
        Button(this.state.mode === 'safe' ? this.t("试用正常模式") : this.t("以安全模式重启")).height(36).fontSize(13)
          .enabled(!this.working && !this.busy).onClick(() => { void this.act(this.state.mode === 'safe' ? 'normal' : 'safe'); });
        Button(this.t("恢复正常配置")).height(36).fontSize(13).enabled(this.state.goodProfileAvailable && !this.working && !this.busy)
          .onClick(() => { this.confirmRestore(); });
      }
      Row({ space: 8 }) {
        Button(this.t("查看引擎日志")).height(36).fontSize(13).enabled(!this.working && !this.busy).onClick(() => { void this.act('logs'); });
        Button(this.t("检查本机 Shell")).height(36).fontSize(13).enabled(!this.working && !this.busy).onClick(() => { void this.act('shell'); });
      }
      Button(this.t("重置本机引擎")).height(36).fontSize(13).enabled(!this.working && !this.busy)
        .onClick(() => { this.resetOptions = !this.resetOptions; });
      if (this.resetOptions) {
        Text(this.t("将删除本机对话、工作区、模型和账号。请选择需要保留的项目。")).fontSize(13).fontColor(this.colors.danger);
        Row({ space: 8 }) {
          Checkbox({ name: 'keep-ui-skills' }).select(this.keepUiSkills).onChange((value: boolean) => { this.keepUiSkills = value; });
          Text(this.t("保留界面设置和技能")).fontSize(13).fontColor(this.colors.text);
        }
        Row({ space: 8 }) {
          Checkbox({ name: 'keep-plugins-settings' }).select(this.keepPluginsSettings).onChange((value: boolean) => { this.keepPluginsSettings = value; });
          Text(this.t("保留插件和引擎设置")).fontSize(13).fontColor(this.colors.text);
        }
        Button(this.t("继续重置…")).height(36).fontSize(13).enabled(!this.working && !this.busy).onClick(() => { this.confirmReset(); });
      }
      if (this.shell) Text(this.shell).fontSize(13).fontColor(this.colors.muted);
      if (this.logs) Text(this.logs).fontFamily('monospace').fontSize(11).fontColor(this.colors.muted).copyOption(CopyOptions.InApp).width('100%');
      if (this.error) Text(this.t(this.error)).fontSize(13).fontColor(this.colors.danger);
    }.alignItems(HorizontalAlign.Start).width('100%').padding(14).backgroundColor(this.colors.surface).borderRadius(14);
  }
}
