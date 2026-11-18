import { localizedSettingsText } from './SettingsLocale'
import { DshClient } from '../dsh/DshClient';
import { DshPermissionOption, DshSessionProjections, WireObject, string } from '../dsh/DshWire';
import { ThemeColors, themeColors, DshGlyphs } from './DshTheme';
import { PermissionCopy, permissionConfirmation, permissionCopy } from './SessionPermissionCopy';
import { newChatPresets, defaultNewChatPreset } from './NewChatOptionsData';

@Component
export struct SessionOptionsPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors();
  client: DshClient = new DshClient();
  @Prop @Watch('sessionChanged') sessionId: string = '';
  @Prop local: boolean = false;
  @Prop presetDraft: string = '';
  @Prop permissionDraft: string = '';
  onDraftChange: (preset: string, permission: string) => void = () => {};
  onClose: () => void = () => {};
  @State private permissions: DshPermissionOption[] = [];
  @State private agents: WireObject[] = [];
  @State private permission: string = '';
  @State private agent: string = '';
  @State private busy: boolean = true;
  @State private error: string = '';
  private generation: number = 0;
  private active: boolean = false;

  aboutToAppear(): void { this.active = true; void this.load(); }
  aboutToDisappear(): void { this.active = false; this.generation++; }

  private sessionChanged(): void {
    if (this.active) {
      this.permissions = [];
      this.agents = [];
      this.permission = '';
      this.agent = '';
      void this.load();
    }
  }

  private applyProjection(projections: DshSessionProjections | null, fallback: string = ''): void {
    this.permission = projections?.permissionPreset || fallback;
    this.agent = projections?.agentPreset || '';
  }

  private async load(): Promise<void> {
    const generation = ++this.generation;
    const connection = this.client.connectionIdentity();
    this.busy = true; this.error = '';
    try {
      const permissions = await this.client.permissionPresets();
      const agents = await this.client.listAgentPresets();
      const projections = this.sessionId ? await this.client.sessionProjections(this.sessionId) : null;
      if (generation !== this.generation || connection !== this.client.connectionIdentity()) return;
      this.permissions = permissions.options;
      this.agents = this.sessionId ? agents : newChatPresets(agents);
      if (this.sessionId) this.applyProjection(projections, permissions.defaultPreset);
      else {
        this.permission = permissions.options.some((option: DshPermissionOption) => option.value === this.permissionDraft)
          ? this.permissionDraft : permissions.defaultPreset;
        this.agent = this.agents.some((agent: WireObject) => agent['id'] === this.presetDraft && !agent['broken'])
          ? this.presetDraft : defaultNewChatPreset(this.agents);
      }
    } catch { if (generation === this.generation) this.error = this.t("对话选项加载失败，请重试。"); }
    finally { if (generation === this.generation) this.busy = false; }
  }

  private async select(value: string, permission: boolean): Promise<void> {
    if (!this.active || this.busy) return;
    if (!this.sessionId) {
      if (permission) this.permission = value;
      else this.agent = value;
      this.onDraftChange(this.agent, this.permission);
      return;
    }
    const generation = this.generation;
    const connection = this.client.connectionIdentity();
    const session = this.sessionId;
    this.busy = true; this.error = '';
    try {
      if (permission) await this.client.setPermissionPreset(session, value);
      else await this.client.selectAgentPreset(session, value);
      if (generation !== this.generation || connection !== this.client.connectionIdentity()) return;
      const projections = await this.client.sessionProjections(session);
      if (generation !== this.generation || connection !== this.client.connectionIdentity()) return;
      if (projections) this.applyProjection(projections);
      if (!projections || (permission ? this.permission : this.agent) !== value) {
        this.error = this.t("主机未确认所选预设。请检查当前状态后重试。");
      }
    } catch { if (generation === this.generation) this.error = this.t("更改未能确认，请重试。"); }
    finally { if (generation === this.generation) this.busy = false; }
  }

  private requestSelect(value: string, permission: boolean): void {
    if (!this.active || this.busy || value === (permission ? this.permission : this.agent)) return;
    const confirmation = permission ? permissionConfirmation(value, this.local) : undefined;
    if (!confirmation) {
      void this.select(value, permission);
      return;
    }
    const generation = this.generation;
    this.getUIContext().showAlertDialog({
      title: this.t(confirmation.title), message: this.t(confirmation.body),
      primaryButton: { value: this.t("取消"), action: () => {} },
      secondaryButton: { value: this.t(confirmation.action), action: () => {
        if (generation === this.generation) void this.select(value, true);
      } }
    });
  }

  @Builder
  private permissionRow(option: DshPermissionOption, copy: PermissionCopy) {
    this.choice(option.value, copy.title, copy.hint, true);
  }

  @Builder
  private choice(value: string, title: string, description: string, permission: boolean, enabled: boolean = true) {
    Row({ space: 10 }) {
      Column({ space: 6 }) {
        Text(this.t(title)).fontSize(16).fontColor(this.colors.text);
        if (description) Text(this.t(description)).fontSize(13).fontColor(this.colors.muted);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (value === (permission ? this.permission : this.agent)) {
        Text(DshGlyphs.check).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.primary);
      }
    }.width('100%').padding(16).backgroundColor(this.colors.surface).borderRadius(14)
      .enabled(!this.busy && enabled).opacity(enabled ? 1 : 0.5).onClick(() => this.requestSelect(value, permission));
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Button({ type: ButtonType.Circle }) {
          Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text);
        }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText(this.t("返回")).onClick(this.onClose);
        Text(this.sessionId ? this.t("对话选项") : this.t("新对话选项")).fontSize(22).fontColor(this.colors.text);
      }.width('100%');
      if (this.busy) LoadingProgress().width(30).height(30).color(this.colors.primary);
      if (this.error) {
        Text(this.t(this.error)).fontSize(14).fontColor(this.colors.danger);
        Button(this.t("重试")).onClick(() => { void this.load(); });
      }
      Scroll() {
        Column({ space: 10 }) {
          Text(this.t("权限")).fontSize(14).fontColor(this.colors.muted).width('100%');
          if (this.local) Text(this.t("本机文件访问始终限定在应用工作区，权限预设不会开放系统目录或 Shell。"))
            .fontSize(13).fontColor(this.colors.muted).width('100%');
          ForEach(this.permissions, (option: DshPermissionOption) => {
            this.permissionRow(option, permissionCopy(option.value, option.name, option.description || '', this.local));
          }, (option: DshPermissionOption) => JSON.stringify(option));
          if (this.permission === 'custom') Text(this.t("当前用的是自定义权限，选预设会替换它"))
            .fontSize(13).fontColor(this.colors.muted).width('100%');
          Text(this.t("智能体")).fontSize(14).fontColor(this.colors.muted).width('100%').padding({ top: 16 });
          ForEach(this.agents, (agent: WireObject) => {
            this.choice(string(agent['id']), string(agent['title']) || string(agent['name']) || string(agent['id']),
              agent['broken'] ? this.t("当前不可用") : string(agent['description']), false, !agent['broken']);
          }, (agent: WireObject) => JSON.stringify([agent['id'], agent['title'], agent['name'], agent['description']]));
        }.width('100%');
      }.width('100%').layoutWeight(1);
    }.width('100%').height('100%').padding(16);
  }
}
