import { DshClient } from '../dsh/DshClient';
import { DshPermissionOption, DshSessionProjections, WireObject, string } from '../dsh/DshWire';
import { ThemeColors, themeColors, DshGlyphs } from './DshTheme';
import { PermissionCopy, permissionConfirmation, permissionCopy } from './SessionPermissionCopy';

@Component
export struct SessionOptionsPanel {
  @Prop colors: ThemeColors = themeColors();
  client: DshClient = new DshClient();
  @Prop @Watch('sessionChanged') sessionId: string = '';
  @Prop local: boolean = false;
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
    this.busy = true; this.error = '';
    try {
      const permissions = await this.client.permissionPresets();
      const agents = await this.client.listAgentPresets();
      const projections = await this.client.sessionProjections(this.sessionId);
      if (generation !== this.generation) return;
      this.permissions = permissions.options;
      this.agents = agents;
      this.applyProjection(projections, permissions.defaultPreset);
    } catch { if (generation === this.generation) this.error = '对话选项加载失败，请重试。'; }
    finally { if (generation === this.generation) this.busy = false; }
  }

  private async select(value: string, permission: boolean): Promise<void> {
    if (!this.active || this.busy) return;
    const generation = this.generation;
    const session = this.sessionId;
    this.busy = true; this.error = '';
    try {
      if (permission) await this.client.setPermissionPreset(session, value);
      else await this.client.selectAgentPreset(session, value);
      if (generation !== this.generation) return;
      const projections = await this.client.sessionProjections(session);
      if (generation !== this.generation) return;
      if (projections) this.applyProjection(projections);
      if (!projections || (permission ? this.permission : this.agent) !== value) {
        this.error = '主机未确认所选预设。请检查当前状态后重试。';
      }
    } catch { if (generation === this.generation) this.error = '更改未能确认，请重试。'; }
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
      title: confirmation.title, message: confirmation.body,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: confirmation.action, action: () => {
        if (generation === this.generation) void this.select(value, true);
      } }
    });
  }

  @Builder
  private permissionRow(option: DshPermissionOption, copy: PermissionCopy) {
    this.choice(option.value, copy.title, copy.hint, true);
  }

  @Builder
  private choice(value: string, title: string, description: string, permission: boolean) {
    Row({ space: 10 }) {
      Column({ space: 6 }) {
        Text(title).fontSize(16).fontColor(this.colors.text);
        if (description) Text(description).fontSize(13).fontColor(this.colors.muted);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (value === (permission ? this.permission : this.agent)) {
        Text(DshGlyphs.check).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.primary);
      }
    }.width('100%').padding(16).backgroundColor(this.colors.surface).borderRadius(14)
      .enabled(!this.busy).onClick(() => this.requestSelect(value, permission));
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Button({ type: ButtonType.Circle }) {
          Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text);
        }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText('返回').onClick(this.onClose);
        Text('对话选项').fontSize(22).fontColor(this.colors.text);
      }.width('100%');
      if (this.busy) LoadingProgress().width(30).height(30).color(this.colors.primary);
      if (this.error) {
        Text(this.error).fontSize(14).fontColor(this.colors.danger);
        Button('重试').onClick(() => { void this.load(); });
      }
      Scroll() {
        Column({ space: 10 }) {
          Text('权限').fontSize(14).fontColor(this.colors.muted).width('100%');
          if (this.local) Text('本机文件访问始终限定在应用工作区，权限预设不会开放系统目录或 Shell。')
            .fontSize(13).fontColor(this.colors.muted).width('100%');
          ForEach(this.permissions, (option: DshPermissionOption) => {
            this.permissionRow(option, permissionCopy(option.value, option.name, option.description || '', this.local));
          }, (option: DshPermissionOption) => JSON.stringify(option));
          if (this.permission === 'custom') Text('当前用的是自定义权限，选预设会替换它')
            .fontSize(13).fontColor(this.colors.muted).width('100%');
          Text('智能体').fontSize(14).fontColor(this.colors.muted).width('100%').padding({ top: 16 });
          ForEach(this.agents, (agent: WireObject) => {
            this.choice(string(agent['id']), string(agent['title']) || string(agent['name']) || string(agent['id']),
              string(agent['description']), false);
          }, (agent: WireObject) => JSON.stringify([agent['id'], agent['title'], agent['name'], agent['description']]));
        }.width('100%');
      }.width('100%').layoutWeight(1);
    }.width('100%').height('100%').padding(16);
  }
}
