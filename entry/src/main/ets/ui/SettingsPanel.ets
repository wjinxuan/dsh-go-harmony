import { bundleManager, common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { DshClient } from '../dsh/DshClient';
import { hasLocalApiKey, removeLocalApiKey, saveLocalApiKey } from '../local/LocalKeyStore';
import {
  DshModelInfo, DshModelSelection, DshProviderGroup, DshReasoningEffort, DshSettingsOp, object, string
} from '../dsh/DshWire';
import { ACCENTS, DshAccent, DshGlyphs, ThemeColors, themeColors } from './DshTheme';
import {
  editableField, fieldInput, fieldText, parseSettings, SettingsField, SettingsSection
} from './settings/SettingsSchema';
import { ProviderSettings } from './settings/ProviderSettings';
import { AccountPanel } from './AccountPanel';

const DEFAULT_MODEL: string = 'agent-default-model';
const DEEPSEEK_KEY: string = 'DEEPSEEK_API_KEY';
const UPSTREAM_PROJECT: string = 'https://github.com/ccch1mneyyy/dsh-Go';

@Component
export struct SettingsPanel {
  @Prop colors: ThemeColors = themeColors();
  @Prop @Watch('connectionChanged') connected: boolean = false;
  @Prop connectionIdentity: number = 0;
  @Prop local: boolean = true;
  @Prop @Watch('savedLocalKeyChanged') savedLocalKey: boolean = false;
  @Prop engineStatus: string = '未启动';
  @Prop engineRunning: boolean = false;
  @Prop engineBusy: boolean = false;
  @Prop accentId: string = 'mist';
  @Prop themeMode: string = 'system';
  @Prop fontSize: number = 16;
  client: DshClient = new DshClient();
  @Prop initialPage: string = 'home';
  onClose: () => void = () => {};
  onBackHandler?: (handler: (() => boolean) | undefined) => void;
  onThemeChange: (accentId: string, mode: string) => void = () => {};
  onFontSizeChange: (size: number) => void = () => {};
  onStartEngine: () => void = () => {};
  onStopEngine: () => void = () => {};
  onRestartEngine?: () => void;
  onOpenHosts: () => void = () => {};
  onOpenPlugins?: () => void;
  onLocalKeyStored: (stored: boolean) => void = () => {};

  @State private page: string = 'home';
  @Prop @Watch('requestedPageChanged') requestVersion: number = 0;
  @State private query: string = '';
  @State private sections: SettingsSection[] = [];
  @State private sectionId: string = '';
  @State private loadingSettings: boolean = false;
  @State private loadingModels: boolean = false;
  @State private loadingCredential: boolean = false;
  @State private working: boolean = false;
  @State private settingsError: string = '';
  @State private modelError: string = '';
  @State private credentialError: string = '';
  @State private success: string = '';
  @State private failed: string = '';
  @State private groups: DshProviderGroup[] = [];
  @State private catalogFailures: string[] = [];
  @State private selectedProvider: string = '';
  @State private selectedModel: string = '';
  @State private selectedEffort: string = '';
  @State private rememberModel: boolean = false;
  @State private credentialConfigured: boolean = false;
  @State private credentialWritable: boolean = false;
  @State private keyInput: string = '';
  @State private rememberLocalKey: boolean = false;
  @State private editField: SettingsField | undefined = undefined;
  @State private editText: string = '';
  @State private editError: string = '';
  @State private version: string = '';
  private generation: number = 0;
  private catalogDefault?: DshModelSelection;
  private modelsBack?: () => boolean;
  private parents: string[] = [];

  aboutToAppear(): void {
    this.onBackHandler?.(() => this.back());
    this.savedLocalKeyChanged();
    this.open(this.initialPage);
  }

  private savedLocalKeyChanged(): void {
    this.rememberLocalKey = this.savedLocalKey;
  }

  private requestedPageChanged(): void {
    this.open(this.initialPage);
  }

  aboutToDisappear(): void {
    this.onBackHandler?.(undefined);
    this.generation += 1;
    this.keyInput = '';
  }

  private connectionChanged(): void {
    this.generation += 1;
    this.sections = [];
    this.groups = [];
    this.catalogFailures = [];
    this.catalogDefault = undefined;
    this.selectedProvider = '';
    this.selectedModel = '';
    this.selectedEffort = '';
    this.credentialConfigured = false;
    this.credentialWritable = false;
    this.keyInput = '';
    this.editField = undefined;
    this.loadingSettings = false;
    this.loadingModels = false;
    this.loadingCredential = false;
    this.working = false;
    this.settingsError = '';
    this.modelError = '';
    this.credentialError = '';
    this.clearFeedback();
    if (this.connected) {
      this.refresh(this.page);
    }
  }

  private clearFeedback(): void {
    this.failed = '';
    this.success = '';
  }

  private open(page: string, from?: string): void {
    this.parents = from === undefined ? [] : this.parents.concat(from);
    this.show(page);
  }

  private show(page: string): void {
    this.page = page;
    this.editField = undefined;
    this.keyInput = '';
    this.savedLocalKeyChanged();
    this.clearFeedback();
    this.refresh(page);
    if ((page === 'about' || page === 'diagnostics') && !this.version) {
      void this.readVersion();
    }
  }

  private refresh(page: string): void {
    if (!this.connected) {
      return;
    }
    if (page === 'models') {
      void this.loadSettings(true);
      void this.loadModels();
      void this.loadCredential();
    } else if (['parameters', 'permission', 'search', 'section'].includes(page)) {
      void this.loadSettings(false);
    }
  }

  private back(): boolean {
    if (this.working || (this.page === 'engine' && this.engineBusy)) return true;
    if (this.page === 'models' && this.modelsBack?.()) return true;
    if (this.editField) {
      this.editField = undefined;
      this.editText = '';
      this.editError = '';
    } else if (this.page === 'home') {
      return false;
    } else {
      const previous = this.parents.pop();
      this.show(previous || 'home');
    }
    return true;
  }

  private title(): string {
    if (this.page === 'section') {
      return this.section(this.sectionId)?.title || '引擎参数';
    }
    const names: Record<string, string> = {
      'home': '设置', 'models': '模型与服务商', 'engine': '本机引擎', 'parameters': '引擎参数',
      'appearance': '主题与配色', 'permission': '权限', 'search': '联网搜索', 'about': '关于 Harness Pocket',
      'diagnostics': '诊断', 'account': 'DeepSeek 账号'
    };
    return names[this.page] || '设置';
  }

  private section(id: string): SettingsSection | undefined {
    return this.sections.find((item: SettingsSection) => item.id === id);
  }

  private selectSavedModel(): void {
    const current = this.section(DEFAULT_MODEL)?.value;
    const provider = string(current?.['provider']);
    const model = string(current?.['model']);
    const saved = provider.length > 0 && model.length > 0;
    this.selectedProvider = saved ? provider : (this.catalogDefault?.provider || '');
    this.selectedModel = saved ? model : (this.catalogDefault?.model || '');
    this.selectedEffort = saved ? string(current?.['reasoningEffort']) : (this.catalogDefault?.reasoningEffort || '');
    this.rememberModel = current?.['rememberLastSelection'] !== false;
  }

  private async loadSettings(selectModel: boolean): Promise<void> {
    if (this.loadingSettings) {
      return;
    }
    const generation = this.generation;
    this.loadingSettings = true;
    this.settingsError = '';
    try {
      const raw = await this.client.describeSettings();
      if (generation === this.generation) {
        this.sections = parseSettings(raw);
        if (selectModel) {
          this.selectSavedModel();
        }
      }
    } catch {
      if (generation === this.generation) {
        this.settingsError = '无法读取当前主机的引擎设置。';
      }
    } finally {
      if (generation === this.generation) {
        this.loadingSettings = false;
      }
    }
  }

  private async loadModels(): Promise<void> {
    if (this.loadingModels) {
      return;
    }
    const generation = this.generation;
    this.loadingModels = true;
    this.modelError = '';
    try {
      const catalog = await this.client.listModels();
      if (generation === this.generation) {
        this.groups = catalog.groups;
        this.catalogFailures = catalog.failures.map((item) => item.name || item.provider);
        this.catalogDefault = catalog.defaultSelection;
        if (!this.selectedProvider) {
          this.selectSavedModel();
        }
      }
    } catch {
      if (generation === this.generation) {
        this.modelError = '无法读取当前主机的模型目录。';
      }
    } finally {
      if (generation === this.generation) {
        this.loadingModels = false;
      }
    }
  }

  private async loadCredential(): Promise<void> {
    if (this.loadingCredential) {
      return;
    }
    const generation = this.generation;
    this.loadingCredential = true;
    this.credentialError = '';
    try {
      const refs = await this.client.describeCredentials([DEEPSEEK_KEY]);
      if (generation === this.generation) {
        const status = object(refs[DEEPSEEK_KEY]);
        this.credentialConfigured = status['configured'] === true;
        this.credentialWritable = status['writable'] === true;
      }
    } catch {
      if (generation === this.generation) {
        this.credentialWritable = false;
        this.credentialError = '无法读取 DeepSeek API Key 的状态。';
      }
    } finally {
      if (generation === this.generation) {
        this.loadingCredential = false;
      }
    }
  }

  private group(): DshProviderGroup | undefined {
    return this.groups.find((item: DshProviderGroup) => item.id === this.selectedProvider);
  }

  private model(): DshModelInfo | undefined {
    return this.group()?.models.find((item: DshModelInfo) => item.id === this.selectedModel);
  }

  private effortOptions(): SelectOption[] {
    const defaults: SelectOption[] = [{ value: '模型默认' }];
    return defaults.concat(this.model()?.efforts.map((item: DshReasoningEffort): SelectOption =>
      ({ value: item.name || item.id })) || []);
  }

  private modelFieldsWritable(): boolean {
    const current = this.section(DEFAULT_MODEL);
    return current?.writable === true && ['provider', 'model', 'reasoningEffort'].every((key: string) =>
      current.fields.some((field: SettingsField) => field.path.length === 1 && field.path[0] === key &&
        field.kind === 'string' && !field.disabled));
  }

  private rememberField(): SettingsField | undefined {
    return this.section(DEFAULT_MODEL)?.fields.find((field: SettingsField) =>
      field.path.length === 1 && field.path[0] === 'rememberLastSelection' && field.kind === 'boolean');
  }

  private async saveDefaultModel(): Promise<void> {
    const section = this.section(DEFAULT_MODEL);
    const model = this.model();
    if (!this.connected || !section || !model || this.working || !this.modelFieldsWritable()) {
      return;
    }
    const provider = this.selectedProvider;
    const modelId = this.selectedModel;
    const effort = this.selectedEffort;
    const remember = this.rememberModel;
    if (effort && !model.efforts.some((item: DshReasoningEffort) => item.id === effort)) {
      this.failed = '所选思考深度当前不可用，请重新选择。';
      return;
    }
    const inheritedEffort = section.fields.find((field: SettingsField) =>
      field.path.length === 1 && field.path[0] === 'reasoningEffort')?.inherited;
    if (!effort && string(inheritedEffort)) {
      this.failed = '主机配置继承了思考深度，请选择具体的思考深度。';
      return;
    }
    const ops: DshSettingsOp[] = [
      { op: 'set', path: ['provider'], value: provider },
      { op: 'set', path: ['model'], value: modelId },
      effort ? { op: 'set', path: ['reasoningEffort'], value: effort } : { op: 'unset', path: ['reasoningEffort'] }
    ];
    const rememberField = this.rememberField();
    if (rememberField && !rememberField.disabled) {
      ops.push({ op: 'set', path: ['rememberLastSelection'], value: remember });
    }
    const updated = await this.write(section, ops);
    if (!updated) {
      return;
    }
    const current = updated.value;
    if (current['provider'] !== provider || current['model'] !== modelId ||
      string(current['reasoningEffort']) !== effort ||
      (rememberField && !rememberField.disabled && current['rememberLastSelection'] !== remember)) {
      this.failed = '主机当前生效的模型设置与所选值不同，请查看已读取的设置。';
    } else {
      this.success = '新对话默认模型已保存。';
    }
    this.selectSavedModel();
  }

  private async saveKey(clear: boolean): Promise<void> {
    if (!this.connected || this.working || this.loadingCredential || !this.credentialWritable ||
      (!clear && !this.keyInput.trim())) {
      return;
    }
    const generation = this.generation;
    const local = this.local;
    const remember = local && !clear && this.rememberLocalKey;
    const key = this.keyInput.trim();
    this.working = true;
    this.clearFeedback();
    try {
      if (clear) {
        await this.client.clearProviderKey(DEEPSEEK_KEY);
      } else {
        await this.client.setProviderKey(key, DEEPSEEK_KEY);
      }
      if (generation !== this.generation) {
        return;
      }
      this.keyInput = '';
      if (local && !await this.updateSavedLocalKey(remember, key, clear, generation)) {
        if (generation === this.generation) {
          await this.loadCredential();
          if (generation === this.generation) void this.loadModels();
        }
        return;
      }
      await this.loadCredential();
      if (generation === this.generation) {
        if (!this.credentialError && this.credentialConfigured !== clear) {
          this.success = clear ? 'DeepSeek API Key 已移除。' : remember ? 'DeepSeek API Key 已安全保存。' :
            local ? 'DeepSeek API Key 已更新，本次引擎运行期间可用。' : 'DeepSeek API Key 已保存。';
        } else {
          this.failed = '无法确认当前主机的 API Key 状态。';
        }
        void this.loadModels();
      }
    } catch {
      if (generation === this.generation) {
        this.failed = clear ? '主机未能移除 API Key。' : '主机未能保存 API Key。';
      }
    } finally {
      if (generation === this.generation) {
        this.working = false;
      }
    }
  }

  private async updateSavedLocalKey(remember: boolean, key: string, clear: boolean,
    generation: number): Promise<boolean> {
    try {
      if (remember) await saveLocalApiKey(key);
      else await removeLocalApiKey();
      const stored = await hasLocalApiKey();
      if (generation !== this.generation) return false;
      if (stored !== remember) throw new Error('安全存储状态未确认');
      this.onLocalKeyStored(stored);
      return true;
    } catch {
      if (generation === this.generation) {
        this.failed = clear ? '运行中的 API Key 已移除，安全存储未能确认删除。请解锁手机后重试。' :
          '运行中的 API Key 已更新，安全存储未能确认更新。请解锁手机后重试。';
      }
      return false;
    }
  }

  private async write(section: SettingsSection, ops: DshSettingsOp[]): Promise<SettingsSection | undefined> {
    if (!this.connected || !section.writable || this.working) {
      return undefined;
    }
    const generation = this.generation;
    this.working = true;
    this.clearFeedback();
    try {
      await this.client.mutateSettings(section.id, ops, section.revision);
    } catch {
      if (generation === this.generation) {
        this.failed = '主机拒绝修改，设置可能已被其他客户端更新。';
        await this.loadSettings(false);
        this.working = false;
      }
      return undefined;
    }
    if (generation !== this.generation) {
      return undefined;
    }
    try {
      const raw = await this.client.describeSettings();
      if (generation === this.generation) {
        this.sections = parseSettings(raw);
        return this.section(section.id);
      }
    } catch {
      if (generation === this.generation) {
        this.failed = '主机已接收请求，无法读取最新设置。';
      }
    } finally {
      if (generation === this.generation) {
        this.working = false;
      }
    }
    return undefined;
  }

  private async changeField(section: SettingsSection, field: SettingsField, value: Object | null,
    unset: boolean = false): Promise<void> {
    const op: DshSettingsOp = unset ? { op: 'unset', path: field.path } :
      { op: 'set', path: field.path, value: value };
    const updated = await this.write(section, [op]);
    if (!updated) {
      return;
    }
    const path = JSON.stringify(field.path);
    const actual = updated.fields.find((item: SettingsField) => JSON.stringify(item.path) === path);
    if (actual && (unset ? !actual.overridden : actual.kind === 'secret' ? actual.secretSet :
      JSON.stringify(actual.current) === JSON.stringify(value))) {
      this.success = unset ? '已恢复继承值。' : '设置已保存。';
      this.editField = undefined;
      this.editText = '';
      this.editError = '';
    } else {
      this.failed = '主机当前生效的设置与提交值不同，请查看已读取的设置。';
    }
  }

  private edit(section: SettingsSection, field: SettingsField): void {
    if (!this.working && section.writable && editableField(field)) {
      this.clearFeedback();
      this.editField = field;
      this.editText = field.kind === 'secret' ? '' : fieldText(field);
      this.editError = '';
    }
  }

  private saveEdit(section: SettingsSection, field: SettingsField): void {
    this.editError = '';
    try {
      const value = fieldInput(field, this.editText);
      void this.changeField(section, field, value);
    } catch (error) {
      this.editError = (error as Error).message || '请输入有效值。';
    }
  }

  private match(text: string): boolean {
    return text.toLowerCase().includes(this.query.trim().toLowerCase());
  }

  private themeModeLabel(): string {
    return this.themeMode === 'dark' ? '深色' : this.themeMode === 'light' ? '浅色' : '跟随系统';
  }

  private accentName(): string {
    return ACCENTS.find((item: DshAccent) => item.id === this.accentId)?.name || '雾蓝';
  }

  private visibleSections(): SettingsSection[] {
    if (this.page === 'permission') {
      return this.sections.filter((item: SettingsSection) => item.id === 'permission');
    }
    if (this.page === 'search') {
      return this.sections.filter((item: SettingsSection) =>
        ['web', 'web-search-deepseek', 'web-deepseek-api'].includes(item.id));
    }
    return this.sections.filter((item: SettingsSection) => item.autoGenerate && item.fields.length > 0 &&
      ![DEFAULT_MODEL, 'llm-pi-ai', 'llm-deepseek', 'llm-deepseek-account', 'ui-theme', 'locale'].includes(item.id));
  }

  private openSection(section: SettingsSection): void {
    this.sectionId = section.id;
    this.open('section', this.page);
  }

  private async readVersion(): Promise<void> {
    try {
      const bundle = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.version = `${bundle.versionName} (${bundle.versionCode})`;
    } catch {
      this.version = '版本信息不可用';
    }
  }

  private async openExternal(address: string): Promise<void> {
    this.clearFeedback();
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await context.openLink(address);
    } catch {
      this.failed = '无法打开链接。';
    }
  }

  private async copyDiagnostics(): Promise<void> {
    this.clearFeedback();
    const report = [
      `Harness Pocket ${this.version}`, '平台 HarmonyOS', `主机 ${this.local ? '本机' : '远程主机'}`,
      `连接 ${this.connected ? '已连接' : '未连接'}`,
      `本机引擎 ${this.engineRunning ? '运行中' : this.engineBusy ? '正在处理' : '未运行'}`,
      `主题 ${this.themeModeLabel()} · ${this.accentName()}`, `对话字号 ${this.fontSize}`
    ].join('\n');
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, report));
      this.success = '已复制诊断信息。';
    } catch {
      this.failed = '无法复制诊断信息。';
    }
  }

  @Builder
  private iconButton(glyph: string, label: () => string, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      Text(glyph).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text);
    }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText(label()).onClick(action);
  }

  @Builder
  private groupTitle(label: string) {
    Text(label).fontColor(this.colors.muted).fontSize(13).fontWeight(FontWeight.Medium)
      .width('100%').padding({ left: 4, top: 7 });
  }

  @Builder
  private row(icon: string, title: string, detail: string, value: () => string, action: () => void) {
    Row({ space: 12 }) {
      if (icon) {
        Text(icon).fontFamily(DshGlyphs.family).fontSize(19).fontColor(this.colors.primary)
          .width(36).height(36).textAlign(TextAlign.Center).borderRadius(11)
          .backgroundColor(this.colors.primaryContainer);
      }
      Column({ space: 4 }) {
        Text(title).fontSize(16).fontColor(this.colors.text).fontWeight(FontWeight.Medium).width('100%');
        if (detail) {
          Text(detail).fontSize(13).fontColor(this.colors.muted).width('100%');
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (value()) {
        Text(value()).fontSize(13).fontColor(this.colors.muted).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 120 });
      }
      Text(DshGlyphs.disclosure).fontFamily(DshGlyphs.family).fontSize(15).fontColor(this.colors.hint);
    }.width('100%').padding(13).borderRadius(14).backgroundColor(this.colors.surface).onClick(action)
      .accessibilityText(value() ? `${title}，${value()}` : title);
  }

  @Builder
  private bodyText(text: () => string, color?: () => string) {
    Text(text()).fontSize(14).fontColor(color ? color() : this.colors.muted).lineHeight(21).width('100%');
  }

  @Builder
  private filledButton(label: () => string, enabled: () => boolean, action: () => void) {
    Button(label()).fontSize(15).fontColor(this.colors.onPrimary).backgroundColor(this.colors.primary)
      .width('100%').height(46).enabled(enabled()).onClick(action);
  }

  @Builder
  private secondaryButton(label: () => string, enabled: () => boolean, action: () => void) {
    Button(label()).fontSize(15).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
      .width('100%').height(44).enabled(enabled()).onClick(action);
  }

  @Builder
  private home() {
    Column({ space: 10 }) {
      TextInput({ text: this.query, placeholder: '搜索设置' }).fontSize(15).fontColor(this.colors.text)
        .placeholderColor(this.colors.hint).backgroundColor(this.colors.surface).height(46)
        .onChange((value: string) => { this.query = value; });
      if (!this.query.trim()) {
        Row({ space: 12 }) {
          Text(DshGlyphs.host).fontFamily(DshGlyphs.family).fontSize(24).fontColor(this.colors.primary);
          Column({ space: 5 }) {
            Text(this.local ? '本机' : '远程主机').fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.colors.text);
            Text(this.local ? this.engineStatus : (this.connected ? '已连接' : '未连接'))
              .fontSize(13).fontColor(this.connected ? this.colors.success : this.colors.muted);
          }.layoutWeight(1).alignItems(HorizontalAlign.Start);
          Text(DshGlyphs.disclosure).fontFamily(DshGlyphs.family).fontSize(15).fontColor(this.colors.hint);
        }.width('100%').padding(16).borderRadius(14).backgroundColor(this.colors.surface)
          .onClick(() => this.local ? this.open('engine') : this.onOpenHosts());
      }
      if (this.match('模型与服务商 权限 AI api deepseek 新对话 账号 账户 余额 登录')) {
        this.groupTitle('AI');
      }
      if (this.match('模型与服务商 AI api deepseek 新对话 默认模型')) {
        this.row(DshGlyphs.model, '模型与服务商', '配置 API Key 和新对话默认模型', () => '', () => this.open('models'));
      }
      if (this.match('DeepSeek 账号 账户 余额 登录')) {
        this.row(DshGlyphs.model, 'DeepSeek 账号', '查看当前主机的账号与余额', () => '', () => this.open('account'));
      }
      if (this.match('权限 AI 安全')) {
        this.row(DshGlyphs.settings, '权限', '查看和设置主机的默认权限', () => '', () => this.open('permission'));
      }
      if (this.match('能力 联网搜索 网页 插件')) {
        this.groupTitle('能力');
      }
      if (this.match('能力 联网搜索 网页')) {
        this.row(DshGlyphs.web, '联网搜索', '查看当前主机的搜索服务设置', () => '', () => this.open('search'));
      }
      if (this.onOpenPlugins && this.match('能力 插件')) {
        this.row(DshGlyphs.plugin, '插件', '查看当前主机提供的插件', () => '', () => this.onOpenPlugins?.());
      }
      if (this.match('外观 主题 配色 深色 字号 字体')) {
        this.groupTitle('外观');
        this.row(DshGlyphs.settings, '主题与配色', '选择界面外观和强调色', () => this.accentName(), () => this.open('appearance'));
        this.fontControls();
      }
      if (this.match('主机 引擎 本机 启动 停止 远程 连接 参数')) {
        this.groupTitle('主机');
      }
      if (this.match('主机 引擎 本机 启动 停止')) {
        this.row(DshGlyphs.host, '本机引擎', '启动、停止和查看引擎状态', () => this.engineStatus, () => this.open('engine'));
      }
      if (this.match('主机 远程 连接')) {
        this.row(DshGlyphs.switchHost, '主机管理', '选择本机或连接远程主机', () => this.local ? '本机' : '远程', this.onOpenHosts);
      }
      if (this.match('主机 引擎 参数')) {
        this.row(DshGlyphs.settings, '引擎参数', '查看和修改当前主机的配置', () => '', () => this.open('parameters'));
      }
      if (this.match('帮助与关于 Harness Pocket 诊断')) {
        this.groupTitle('帮助与关于');
      }
      if (this.match('帮助与关于 诊断')) {
        this.row('', '诊断', '查看和复制运行状态', () => '', () => this.open('diagnostics'));
      }
      if (this.match('帮助与关于 Harness Pocket 版本 开源 致谢')) {
        this.row('', '关于 Harness Pocket', '', () => this.version, () => this.open('about'));
      }
    }.width('100%');
  }

  @Builder
  private fontControls() {
    Column({ space: 10 }) {
      Text('对话字号').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%');
      Row({ space: 6 }) {
        ForEach([14, 16, 18, 20], (size: number) => {
          Button(size === 14 ? '小' : size === 16 ? '标准' : size === 18 ? '大' : '特大')
            .fontSize(14).height(38).layoutWeight(1)
            .fontColor(size === this.fontSize ? this.colors.onPrimaryContainer : this.colors.muted)
            .backgroundColor(size === this.fontSize ? this.colors.primaryContainer : this.colors.surfaceAlt)
            .onClick(() => this.onFontSizeChange(size));
        }, (size: number) => String(size));
      }.width('100%');
    }.padding(14).width('100%').borderRadius(14).backgroundColor(this.colors.surface);
  }

  @Builder
  private appearance() {
    Column({ space: 12 }) {
      this.groupTitle('外观模式');
      Column({ space: 6 }) {
        this.row('', '跟随系统', '', () => this.themeMode === 'system' ? '已选' : '',
          () => this.onThemeChange(this.accentId, 'system'));
        this.row('', '浅色', '', () => this.themeMode === 'light' ? '已选' : '',
          () => this.onThemeChange(this.accentId, 'light'));
        this.row('', '深色', '', () => this.themeMode === 'dark' ? '已选' : '',
          () => this.onThemeChange(this.accentId, 'dark'));
      }.width('100%');
      this.groupTitle('强调色');
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(ACCENTS, (accent: DshAccent) => {
          Button({ type: ButtonType.Normal }) {
            Column({ space: 8 }) {
              Row({ space: 3 }) {
                Blank().width(21).height(21).borderRadius(11).backgroundColor(accent.light);
                Blank().width(21).height(21).borderRadius(11).backgroundColor(accent.dark);
              };
              Text(accent.name).fontSize(14).fontColor(this.colors.text);
            }.padding(8);
          }.width('31%').height(76).margin({ bottom: 8 }).borderRadius(14)
            .backgroundColor(accent.id === this.accentId ? this.colors.primaryContainer : this.colors.surface)
            .accessibilityText(accent.id === this.accentId ? `${accent.name}，已选` : accent.name)
            .onClick(() => this.onThemeChange(accent.id, this.themeMode));
        }, (accent: DshAccent) => accent.id);
      }.width('100%');
      this.fontControls();
    }.width('100%');
  }

  @Builder
  private engine() {
    Column({ space: 12 }) {
      Column({ space: 10 }) {
        Text('本机 DeepSeek Harness').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%');
        this.bodyText(() => this.engineStatus, () => this.engineRunning ? this.colors.success : this.colors.muted);
        if (this.engineRunning) {
          if (this.onRestartEngine) {
            this.secondaryButton(() => this.local ? '重启引擎' : '重启并切回本机', () => !this.engineBusy, () => this.onRestartEngine?.());
          }
          this.secondaryButton(() => '停止引擎', () => !this.engineBusy, this.onStopEngine);
        } else {
          this.filledButton(() => this.engineBusy ? '正在处理…' : this.local ? '启动引擎' : '启动并切回本机', () => !this.engineBusy, this.onStartEngine);
        }
      }.width('100%').padding(16).borderRadius(14).backgroundColor(this.colors.surface);
      this.row(DshGlyphs.switchHost, '主机管理', '', () => this.local ? '本机' : '远程', this.onOpenHosts);
      this.row(DshGlyphs.settings, '引擎参数', '', () => '', () => this.open('parameters', 'engine'));
    }.width('100%');
  }

  @Builder
  private models() {
    Column({ space: 12 }) {
      if (!this.connected) {
        this.bodyText(() => '连接主机后可查看模型和服务商。');
      } else {
        this.groupTitle('新对话默认模型');
        Column({ space: 10 }) {
          if (this.loadingSettings || this.loadingModels) {
            this.bodyText(() => '正在读取模型设置…');
          }
          if (this.settingsError) {
            this.bodyText(() => this.settingsError, () => this.colors.danger);
          }
          if (this.modelError) {
            this.bodyText(() => this.modelError, () => this.colors.danger);
          }
          if (this.groups.length > 0) {
            Text('服务商').fontSize(13).fontColor(this.colors.muted).width('100%');
            Select(this.groups.map((item: DshProviderGroup): SelectOption => ({ value: item.name || item.id })))
              .value(this.group()?.name || this.selectedProvider || '选择服务商').width('100%')
              .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
              .enabled(!this.working && this.modelFieldsWritable())
              .onSelect((index: number) => {
                if (!this.groups[index]) return;
                this.selectedProvider = this.groups[index].id;
                this.selectedModel = '';
                this.selectedEffort = '';
                this.clearFeedback();
              });
            if ((this.group()?.models.length ?? 0) > 0) {
              Text('模型').fontSize(13).fontColor(this.colors.muted).width('100%');
              Select(this.group()?.models.map((item: DshModelInfo): SelectOption => ({ value: item.name || item.id })) || [])
                .value(this.model()?.name || this.selectedModel || '选择模型').width('100%')
                .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
                .enabled(!this.working && this.modelFieldsWritable())
                .onSelect((index: number) => {
                  this.selectedModel = this.group()?.models[index]?.id || '';
                  this.selectedEffort = '';
                  this.clearFeedback();
                });
            }
            if ((this.model()?.efforts.length ?? 0) > 0) {
              Text('思考深度').fontSize(13).fontColor(this.colors.muted).width('100%');
              Select(this.effortOptions())
                .value(this.model()?.efforts.find((item: DshReasoningEffort) => item.id === this.selectedEffort)?.name ||
                  this.selectedEffort || '模型默认').width('100%')
                .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
                .enabled(!this.working && this.modelFieldsWritable())
                .onSelect((index: number) => {
                  this.selectedEffort = index > 0 ? (this.model()?.efforts[index - 1]?.id || '') : '';
                  this.clearFeedback();
                });
            }
            if (this.rememberField()) {
              Row({ space: 10 }) {
                Text('记住上次选择').fontSize(15).fontColor(this.colors.text).layoutWeight(1);
                Toggle({ type: ToggleType.Switch, isOn: this.rememberModel }).selectedColor(this.colors.primary)
                  .enabled(!this.working && this.modelFieldsWritable() && !this.rememberField()?.disabled)
                  .onChange((value: boolean) => { this.rememberModel = value; });
              }.width('100%');
            }
            if (!this.loadingSettings && !this.modelFieldsWritable()) {
              this.bodyText(() => '当前主机未开放修改默认模型。');
            } else {
              this.filledButton(() => '保存默认模型', () => !this.working && !this.loadingSettings &&
                this.modelFieldsWritable() && this.model() !== undefined, () => { void this.saveDefaultModel(); });
            }
          } else if (!this.loadingModels && !this.modelError) {
            this.bodyText(() => '当前主机没有返回可选择的模型。');
          }
          if (this.catalogFailures.length > 0) {
            this.bodyText(() => `以下服务商的模型目录无法读取：${this.catalogFailures.join('、')}`, () => this.colors.warning);
          }
        }.width('100%').padding(15).borderRadius(14).backgroundColor(this.colors.surface);
        this.row(DshGlyphs.model, 'DeepSeek 账号', '查看账号授权与余额', () => '', () => this.open('account', 'models'));
        this.groupTitle('DeepSeek 官方 API');
        this.credential();
        this.groupTitle('自定义渠道');
        ProviderSettings({ colors: this.colors, client: this.client, onChange: () => { void this.loadModels(); },
          onBackHandler: (handler: (() => boolean) | undefined) => { this.modelsBack = handler; } });
      }
    }.width('100%');
  }

  @Builder
  private credential() {
    Column({ space: 10 }) {
      if (this.loadingCredential) {
        this.bodyText(() => '正在读取凭据状态…');
      } else if (this.credentialError) {
        this.bodyText(() => this.credentialError, () => this.colors.danger);
      } else {
        this.bodyText(() => this.credentialConfigured ? 'API Key 已配置' : 'API Key 未配置');
        if (this.credentialWritable) {
          TextInput({ text: this.keyInput, placeholder: '输入 DeepSeek API Key' }).type(InputType.Password)
            .fontColor(this.colors.text).placeholderColor(this.colors.hint).backgroundColor(this.colors.surfaceAlt)
            .width('100%').enableAutoFill(false).enabled(!this.working)
            .onChange((value: string) => { this.keyInput = value; });
          if (this.local) {
            Row({ space: 10 }) {
              Column({ space: 4 }) {
                Text('安全保存 API Key').fontSize(15).fontColor(this.colors.text).width('100%');
                Text('勾选后加密保存，重启本机引擎时可继续使用。').fontSize(13)
                  .fontColor(this.colors.muted).width('100%');
              }.layoutWeight(1);
              Toggle({ type: ToggleType.Switch, isOn: this.rememberLocalKey }).selectedColor(this.colors.primary)
                .enabled(!this.working).accessibilityText('安全保存 API Key')
                .onChange((selected: boolean) => { this.rememberLocalKey = selected; });
            }.width('100%');
            this.bodyText(() => this.savedLocalKey ? '本机安全存储已保存 Key。' : '本机安全存储未保存 Key。');
          }
          this.filledButton(() => '保存 API Key', () => !this.working && this.keyInput.trim().length > 0,
            () => { void this.saveKey(false); });
          if (this.credentialConfigured || (this.local && this.savedLocalKey)) {
            this.secondaryButton(() => '移除 API Key', () => !this.working, () => {
              const generation = this.generation;
              this.getUIContext().showAlertDialog({
                title: '移除 DeepSeek API Key', message: this.local ?
                  '移除运行中的 Key 和本机安全存储中的 Key。再次使用时需要重新配置。' :
                  '移除后，使用该凭据的模型请求将需要重新配置 API Key。',
                primaryButton: { value: '取消', action: () => {} },
                secondaryButton: { value: '移除', action: () => {
                  if (generation === this.generation) void this.saveKey(true);
                } }
              });
            });
          }
        } else if (this.credentialConfigured) {
          this.bodyText(() => '此凭据由主机提供。');
        }
      }
    }.width('100%').padding(15).borderRadius(14).backgroundColor(this.colors.surface);
  }

  @Builder
  private parameters() {
    Column({ space: 10 }) {
      if (!this.connected) {
        this.bodyText(() => '连接主机后可查看此主机的设置。');
      } else if (this.loadingSettings && this.visibleSections().length === 0) {
        this.bodyText(() => '正在读取引擎参数…');
      } else if (this.settingsError) {
        this.bodyText(() => this.settingsError, () => this.colors.danger);
      } else if (this.visibleSections().length === 0) {
        this.bodyText(() => '当前主机未提供此设置。');
      } else {
        ForEach(this.visibleSections(), (section: SettingsSection) => {
          this.row(DshGlyphs.settings, section.title, section.description, () => section.writable ? '' : '只读',
            () => this.openSection(section));
        }, (section: SettingsSection) =>
          JSON.stringify([section.id, section.revision, section.title, section.description, section.writable]));
      }
    }.width('100%');
  }

  @Builder
  private field(section: SettingsSection, field: SettingsField) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text(field.title).fontSize(16).fontColor(this.colors.text).width('100%');
          if (field.description) {
            this.bodyText(() => field.description);
          }
        }.layoutWeight(1);
        if (field.kind === 'boolean') {
          Toggle({ type: ToggleType.Switch, isOn: field.current === true }).selectedColor(this.colors.primary)
            .enabled(section.writable && editableField(field) && !this.working)
            .onChange((value: boolean) => { void this.changeField(section, field, value); });
        }
      }.width('100%');
      if (field.kind === 'enum') {
        Select(field.choices.map((choice: Object): SelectOption => ({ value: String(choice) })))
          .value(fieldText(field) || '未设置').width('100%').fontColor(this.colors.text)
          .backgroundColor(this.colors.surfaceAlt).enabled(section.writable && editableField(field) && !this.working)
          .onSelect((index: number) => { void this.changeField(section, field, field.choices[index]); });
      } else if (field.kind !== 'boolean') {
        Text(fieldText(field) || '未设置').fontSize(14).fontColor(this.colors.muted).maxLines(5)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        if (section.writable && editableField(field)) {
          this.secondaryButton(() => field.kind === 'secret' ? '设置凭据' : '编辑', () => !this.working,
            () => this.edit(section, field));
        }
      }
      if (section.writable && editableField(field) && field.overridden) {
        Button('恢复继承值', { type: ButtonType.Normal }).fontSize(13).fontColor(this.colors.primary)
          .backgroundColor(Color.Transparent).height(34).enabled(!this.working).onClick(() => {
            this.getUIContext().showAlertDialog({
              title: '恢复继承值', message: `移除「${field.title}」的当前覆盖设置。`,
              primaryButton: { value: '取消', action: () => {} },
              secondaryButton: { value: '恢复', action: () => { void this.changeField(section, field, null, true); } }
            });
          });
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(14).borderRadius(14).backgroundColor(this.colors.surface);
  }

  @Builder
  private sectionContent(section: SettingsSection) {
    Column({ space: 10 }) {
      if (section.description) {
        this.bodyText(() => section.description);
      }
      if (!section.writable) {
        this.bodyText(() => '当前主机设置为只读。', () => this.colors.warning);
      }
      if (section.fields.length === 0) {
        this.bodyText(() => '当前主机未提供可显示的设置字段。');
      }
      ForEach(section.fields, (field: SettingsField) => {
        this.field(section, field);
      }, (field: SettingsField) => this.fieldRowKey(section, field));
    }.width('100%');
  }

  private fieldRowKey(section: SettingsSection, field: SettingsField): string {
    const scope: string = `${section.id}|${section.revision}|${section.writable}`;
    return `${scope}|${JSON.stringify(field)}`;
  }

  @Builder
  private editor(section: SettingsSection, field: SettingsField) {
    Column({ space: 12 }) {
      Text(field.title).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%');
      if (field.description) {
        this.bodyText(() => field.description);
      }
      if (['array', 'tuple', 'dict'].includes(field.kind)) {
        TextArea({ text: this.editText, placeholder: field.kind === 'dict' ? '{}' : '[]' })
          .height(160).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
          .onChange((value: string) => { this.editText = value; });
      } else {
        TextInput({ text: this.editText, placeholder: field.title })
          .type(field.kind === 'secret' ? InputType.Password : InputType.Normal)
          .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
          .onChange((value: string) => { this.editText = value; });
      }
      if (this.editError) {
        this.bodyText(() => this.editError, () => this.colors.danger);
      }
      this.filledButton(() => '保存', () => !this.working, () => this.saveEdit(section, field));
      this.secondaryButton(() => '取消', () => !this.working, () => this.back());
    }.width('100%').padding(14).borderRadius(14).backgroundColor(this.colors.surface);
  }

  @Builder
  private about() {
    Column({ space: 10 }) {
      Column({ space: 8 }) {
        Text($r('app.string.app_name')).fontSize(24).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%');
        this.bodyText(() => this.version || '正在读取版本…');
        this.bodyText(() => '以 dsh-Go v1.0.15 为基线的 HarmonyOS 社区移植');
        this.bodyText(() => '基于 DeepSeek Harness 构建 · 非 DeepSeek 官方应用');
      }.width('100%').padding(18).borderRadius(14).backgroundColor(this.colors.surface);
      this.groupTitle('致谢 · 原版作者 Chimney（ccch1mneyyy）');
      this.row(DshGlyphs.openExternal, '原项目 dsh-Go', '在 GitHub 查看并支持原项目', () => '',
        () => { void this.openExternal(UPSTREAM_PROJECT); });
      this.row(DshGlyphs.openExternal, '开源许可', 'GNU AGPL v3', () => '',
        () => { void this.openExternal('https://github.com/wjinxuan/dsh-go-harmony/blob/main/LICENSE'); });
      this.row(DshGlyphs.openExternal, '第三方许可', '', () => '',
        () => { void this.openExternal('https://github.com/wjinxuan/dsh-go-harmony/blob/main/THIRD_PARTY_NOTICES.md'); });
      this.row(DshGlyphs.openExternal, 'Bilibili', 'ccchimneyyy', () => '',
        () => { void this.openExternal('https://b23.tv/9WBns6Y'); });
      this.row(DshGlyphs.openExternal, 'X', '@cccch1mneyyyy', () => '',
        () => { void this.openExternal('https://x.com/cccch1mneyyyy'); });
      this.row(DshGlyphs.openExternal, 'GitHub', '@ccch1mneyyy', () => '',
        () => { void this.openExternal('https://github.com/ccch1mneyyy'); });
    }.width('100%');
  }

  @Builder
  private diagnostics() {
    Column({ space: 10 }) {
      this.groupTitle('运行状态');
      Column({ space: 10 }) {
        this.bodyText(() => `版本 ${this.version || '正在读取…'}`);
        this.bodyText(() => `主机 ${this.local ? '本机' : '远程主机'}`);
        this.bodyText(() => `连接 ${this.connected ? '已连接' : '未连接'}`);
        this.bodyText(() => `本机引擎 ${this.engineRunning ? '运行中' : this.engineBusy ? '正在处理' : '未运行'}`);
      }.width('100%').padding(16).borderRadius(14).backgroundColor(this.colors.surface);
      this.secondaryButton(() => '复制诊断信息', () => true, () => { void this.copyDiagnostics(); });
      this.row(DshGlyphs.settings, '引擎参数', '', () => '', () => this.open('parameters', 'diagnostics'));
    }.width('100%');
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        this.iconButton(DshGlyphs.back, () => this.page === 'home' ? '关闭设置' : '返回', () => {
          if (!this.back()) this.onClose();
        });
        Text(this.title()).fontSize(23).fontWeight(FontWeight.Bold).fontColor(this.colors.text).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        if (this.connected && ['models', 'parameters', 'search', 'permission', 'section'].includes(this.page)) {
          this.iconButton(DshGlyphs.refresh, () => '刷新', () => this.refresh(this.page));
        }
      }.width('100%').padding({ top: 8 });
      Scroll() {
        Column({ space: 12 }) {
          if (this.failed) {
            this.bodyText(() => this.failed, () => this.colors.danger);
          }
          if (this.success) {
            this.bodyText(() => this.success, () => this.colors.success);
          }
          if (this.page === 'home') {
            this.home();
          } else if (this.page === 'appearance') {
            this.appearance();
          } else if (this.page === 'engine') {
            this.engine();
          } else if (this.page === 'models') {
            this.models();
          } else if (this.page === 'account') {
            AccountPanel({ colors: this.colors, client: this.client, connected: this.connected, local: this.local,
              connectionIdentity: this.connectionIdentity,
              onOpenModels: () => {
                if (this.parents[this.parents.length - 1] === 'models') this.back();
                else this.open('models', 'account');
              } });
          } else if (this.page === 'section' && this.section(this.sectionId)) {
            if (this.editField) {
              this.editor(this.section(this.sectionId)!, this.editField);
            } else {
              this.sectionContent(this.section(this.sectionId)!);
            }
          } else if (this.page === 'about') {
            this.about();
          } else if (this.page === 'diagnostics') {
            this.diagnostics();
          } else {
            this.parameters();
          }
        }.width('100%').padding({ bottom: 24 });
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top);
    }.width('100%').height('100%').padding({ left: 16, right: 16 }).backgroundColor(this.colors.background);
  }
}
