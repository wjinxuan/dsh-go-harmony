import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { DshClient, DshSubscription } from '../dsh/DshClient';
import {
  array, DshGoal, DshGoalRef, DshSessionDetail, DshSessionProjections, DshSessionRecord, DshTodo, DshTraceSpan,
  DshTurnTrace, goalView, number, object, sessionProjections, string, turnTraces, WireObject
} from '../dsh/DshWire';
import { DshGlyphs, DshType, ThemeColors, themeColors } from './DshTheme';
import { MessageBody } from './MessageBody';
import { goalRoundCap, sessionFileChanges, SessionDiffLine, SessionFileChange, turnTotalTokens } from './SessionDetailData';

interface DetailTab {
  id: string;
  title: string;
}

@Component
export struct SessionDetailPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors();
  @Prop @Watch('sessionChanged') sessionId: string = '';
  @Prop title: string = '';
  @Prop initialTab: string = 'trajectory';
  @Prop pluginTabs: string[] = [];
  @Prop hasSubagents: boolean = false;
  client: DshClient = new DshClient();
  onClose: () => void = () => {};
  onBackHandler?: (handler: (() => boolean) | undefined) => void;
  onFiles: () => void = () => {};
  onAgents: () => void = () => {};
  onPlugins: () => void = () => {};
  onFork: () => void = () => {};
  @State private tab: string = 'trajectory';
  @State private snapshot: DshSessionDetail | undefined = undefined;
  @State private projections: DshSessionProjections | undefined = undefined;
  @State private records: DshSessionRecord[] = [];
  @State private turns: DshTurnTrace[] = [];
  @State private changes: SessionFileChange[] = [];
  @State private selectedPath: string = '';
  @State private shownDiffLines: number = 300;
  @State private expandedTurn: number = -1;
  @State private loading: boolean = true;
  @State private loadingOlder: boolean = false;
  @State private hasMore: boolean = false;
  @State private error: string = '';
  @State private goal: DshGoal | undefined = undefined;
  @State private goalEditing: boolean = false;
  @State private editingExistingGoal: boolean = false;
  @State private objective: string = '';
  @State private roundDraft: string = '';
  @State private working: boolean = false;
  private active: boolean = false;
  private generation: number = 0;
  private beforeSeq?: number;
  private cursor?: number;
  private projectionSequence: Map<string, number> = new Map();
  private controlGeneration: number = 0;
  private controlStop?: DshSubscription;
  private hostStop?: DshSubscription;
  private editRef?: DshGoalRef;
  private initialObjective: string = '';
  private initialRound: string = '';

  aboutToAppear(): void {
    this.active = true;
    this.onBackHandler?.(() => this.back());
    this.sessionChanged();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.onBackHandler?.(undefined);
    this.generation++;
    this.controlGeneration++;
    this.controlStop?.();
    this.hostStop?.();
    this.controlStop = undefined;
    this.hostStop = undefined;
  }

  private sessionChanged(): void {
    if (!this.active) return;
    this.tab = ['trajectory', 'changes', 'progress', 'context'].includes(this.initialTab) ? this.initialTab : 'trajectory';
    this.snapshot = undefined;
    this.projections = undefined;
    this.projectionSequence.clear();
    this.records = [];
    this.turns = [];
    this.changes = [];
    this.goal = undefined;
    this.goalEditing = false;
    this.working = false;
    this.loadingOlder = false;
    this.selectedPath = '';
    this.expandedTurn = -1;
    this.controlStop?.();
    this.hostStop?.();
    this.controlStop = undefined;
    this.hostStop = undefined;
    void this.watchControl(this.sessionId);
    void this.refresh();
  }

  private async watchControl(id: string): Promise<void> {
    if (!id) return;
    const generation = ++this.controlGeneration;
    this.hostStop = this.client.onHostEvent((event: WireObject) => {
      if (event['type'] === 'emit' && event['event'] === 'goal/activation-changed') {
        const payload = object(array(event['args'])[0]);
        if (payload['sessionId'] === id && this.goal && !this.working) void this.readLiveGoal(id);
      }
    });
    try {
      const stop = await this.client.openStream('session/control', {}, (event: WireObject) => {
        if (!this.active || this.sessionId !== id || this.controlGeneration !== generation) return;
        if (event['type'] === 'baseline') {
          const value = object(object(event['value'])['projections'])[id];
          if (value) this.applyProjections(sessionProjections(value));
        } else if (event['sessionId'] === id) {
          const values: WireObject = {};
          const sequence = number(event['seq'], -1);
          if (Array.isArray(event['changes'])) {
            for (const raw of array(event['changes'])) {
              const change = object(raw);
              values[string(change['key'])] = change['val'];
            }
          } else {
            values[string(event['key'])] = event['value'];
          }
          this.applyProjections({ asOfSeq: sequence, values: values });
        }
      }, () => {});
      if (this.active && this.sessionId === id && this.controlGeneration === generation) this.controlStop = stop;
      else stop();
    } catch {
      // A refresh still works on hosts that do not expose session/control.
    }
  }

  private applyProjections(next: DshSessionProjections): void {
    if (next.asOfSeq < 0) return;
    const current = this.projections;
    const values: WireObject = {};
    if (current) {
      for (const key of Object.keys(current.values)) values[key] = current.values[key];
    }
    for (const key of ['goal', 'plan', 'todos', 'tokenUsage', 'contextPressure', 'contextBreakdown', 'sessionStats']) {
      if (next.values[key] !== undefined && next.asOfSeq > (this.projectionSequence.get(key) ?? -1)) {
        this.projectionSequence.set(key, next.asOfSeq);
        values[key] = next.values[key];
        if (key === 'goal' && !this.working) {
          const projected = goalView(values['goal']);
          if (projected && this.goal && projected.id === this.goal.id) projected.activation = this.goal.activation;
          this.goal = projected;
        }
      }
    }
    const wire: WireObject = {};
    wire['values'] = values;
    wire['asOfSeq'] = Math.max(current?.asOfSeq ?? -1, next.asOfSeq);
    this.projections = sessionProjections(wire);
  }

  private async readLiveGoal(id: string): Promise<void> {
    const observed = this.goal;
    const generation = this.generation;
    try {
      const current = await this.client.readGoal(id);
      if (this.active && generation === this.generation && this.sessionId === id && !this.working &&
        this.goal?.id === observed?.id && this.goal?.revision === observed?.revision) {
        this.goal = current || undefined;
      }
    } catch {
      // Retain the projection on a host without the goal RPC.
    }
  }

  private setRecords(records: DshSessionRecord[]): void {
    this.records = records;
    this.turns = turnTraces(records).reverse();
    this.changes = sessionFileChanges(records);
    if (this.expandedTurn < 0 && this.turns.length) this.expandedTurn = this.turns[0].startSeq;
  }

  private async refresh(): Promise<void> {
    if (!this.sessionId) return;
    const generation = ++this.generation;
    this.loading = true;
    this.loadingOlder = false;
    this.error = '';
    try {
      const detail = await this.client.sessionDetail(this.sessionId);
      if (generation !== this.generation) return;
      this.snapshot = detail;
      if (detail.projections) this.applyProjections(detail.projections);
      if (detail.goalSupported) void this.readLiveGoal(this.sessionId);
      this.beforeSeq = detail.history.beforeSeq;
      this.cursor = detail.history.cursor;
      this.hasMore = detail.history.hasMore && this.beforeSeq !== undefined;
      this.setRecords(detail.history.records);
    } catch {
      if (generation === this.generation) this.error = this.t("无法读取对话详情。");
    } finally {
      if (generation === this.generation) this.loading = false;
    }
  }

  private async older(): Promise<void> {
    const before = this.beforeSeq;
    if (!this.hasMore || before === undefined || this.loading || this.loadingOlder) return;
    const generation = this.generation;
    this.loadingOlder = true;
    this.error = '';
    try {
      const page = await this.client.sessionPage(this.sessionId, before, 80, this.cursor);
      if (generation !== this.generation) return;
      this.setRecords(page.records.filter((record: DshSessionRecord) => record.seq < before).concat(this.records));
      this.beforeSeq = page.beforeSeq;
      this.hasMore = page.hasMore && this.beforeSeq !== undefined && this.beforeSeq < before;
    } catch {
      if (generation === this.generation) this.error = this.t("无法读取更早的对话记录。");
    } finally {
      if (generation === this.generation) this.loadingOlder = false;
    }
  }

  private async updateGoal(action: string): Promise<void> {
    if (this.working || !this.goalSupported()) return;
    const current = this.goal;
    if (action === 'edit' && (!current || !this.editRef || current.id !== this.editRef.id ||
      current.revision !== this.editRef.revision)) {
      this.error = this.t("目标已被其他操作更新。请重新打开编辑。");
      return;
    }
    if (action !== 'create' && !current) return;
    const generation = this.generation;
    const session = this.sessionId;
    this.working = true;
    this.error = '';
    try {
      if (action === 'create' || action === 'edit') {
        const objective = this.objective.trim();
        if (!objective) throw new Error(this.t("请输入目标。"));
        const cap = goalRoundCap(this.roundDraft);
        if (current && action === 'edit') {
          const ref: DshGoalRef = { id: current.id, revision: current.revision };
          await this.client.editGoal(session, ref, objective, cap);
        } else {
          await this.client.createGoal(session, objective, cap);
        }
      } else if (current) {
        const ref: DshGoalRef = { id: current.id, revision: current.revision };
        if (action === 'pause') await this.client.pauseGoal(session, ref);
        else if (action === 'resume') await this.client.resumeGoal(session, ref);
        else if (action === 'complete') await this.client.completeGoal(session, ref);
        else if (action === 'clear') await this.client.clearGoal(session, ref);
      }
      if (generation !== this.generation) return;
      const confirmed = await this.client.readGoal(session);
      if (generation === this.generation) {
        this.goal = confirmed || undefined;
        this.goalEditing = false;
      }
    } catch (error) {
      if (generation === this.generation) {
        const message = (error as Error).message;
        this.error = message === '请输入目标。' || message === '回合上限必须为正整数。' ? message :
          this.t("主机未确认目标更新。请核对当前状态后重试。");
        try {
          const latest = await this.client.readGoal(session);
          if (generation === this.generation) this.goal = latest || undefined;
        } catch {
          // Keep the last confirmed revision while the host is unavailable.
        }
      }
    } finally {
      if (generation === this.generation) this.working = false;
    }
  }

  private tabs(): DetailTab[] {
    const tabs: DetailTab[] = [{ id: 'trajectory', title: this.t("轨迹") }, { id: 'changes', title: this.t("改动") },
      { id: 'files', title: this.t("文件") }, { id: 'progress', title: this.t("进度") }, { id: 'context', title: this.t("上下文") }];
    if (this.hasSubagents || this.turns.some((turn: DshTurnTrace) =>
      turn.spans.some((span: DshTraceSpan) => span.toolName === 'subagent' || span.toolName === 'subagent_fork'))) {
      tabs.push({ id: 'subagents', title: this.t("子代理") });
    }
    if (this.pluginTabs.length) tabs.push({ id: 'plugins', title: this.t("插件") });
    return tabs;
  }

  private choose(tab: string): void {
    if (this.working || tab === this.tab) return;
    this.leaveGoalEditor(() => this.switchTab(tab));
  }

  private switchTab(tab: string): void {
    if (tab === 'files') this.onFiles();
    else if (tab === 'subagents') this.onAgents();
    else if (tab === 'plugins') this.onPlugins();
    else {
      this.tab = tab;
      this.selectedPath = '';
      this.error = '';
    }
  }

  private back(): boolean {
    if (this.working) return true;
    if (this.goalEditing) {
      this.leaveGoalEditor(() => {});
      return true;
    }
    if (!this.selectedPath) return false;
    this.selectedPath = '';
    return true;
  }

  private leaveGoalEditor(next: () => void): void {
    if (!this.goalEditing) {
      next();
      return;
    }
    if (this.working) return;
    const discard = (): void => {
      this.goalEditing = false;
      this.editRef = undefined;
      this.objective = '';
      this.roundDraft = '';
      this.error = '';
      next();
    };
    if (this.objective === this.initialObjective && this.roundDraft === this.initialRound) {
      discard();
      return;
    }
    const generation = this.generation;
    this.getUIContext().showAlertDialog({
      title: this.t("放弃更改？"), message: this.t("还没有保存目标更改。"),
      primaryButton: { value: this.t("继续编辑"), action: () => {} },
      secondaryButton: { value: this.t("放弃"), action: () => {
        if (generation === this.generation && this.goalEditing && !this.working) discard();
      } }
    });
  }

  private date(time: number): string {
    return time > 0 ? new Date(time).toLocaleString() : '';
  }

  private duration(value: number | undefined): string {
    if (value === undefined || !Number.isFinite(value) || value < 0) return '';
    return value < 1000 ? this.f("{0} 毫秒", [Math.round(value)]) : this.f("{0} 秒", [(value / 1000).toFixed(1)]);
  }

  private spanTitle(span: DshTraceSpan): string {
    if (span.kind === 'model') return [span.provider, span.model].filter((part: string | undefined) => !!part).join(' / ') || this.t("模型");
    if (span.kind === 'tool') return span.toolName || this.t("工具");
    return span.kind === 'approval' ? this.t("审批") : this.t("提问");
  }

  private goalPhase(goal: DshGoal): string {
    if (goal.phase === 'active') return this.t("进行中");
    if (goal.phase === 'paused') return this.t("已暂停");
    if (goal.phase === 'complete') return this.t("已完成");
    return goal.blockedReason ? this.f("受阻 · {0}", [goal.blockedReason]) : this.t("受阻");
  }

  private todoState(todo: DshTodo): string {
    if (todo.status === 'completed') return this.t("已完成");
    if (todo.status === 'in_progress') return this.t("进行中");
    return this.t("未开始");
  }

  private todos(): DshTodo[] {
    return this.projections?.todos || this.snapshot?.todos || [];
  }

  private goalSupported(): boolean {
    return this.snapshot?.goalSupported === true || this.projections?.values['goal'] !== undefined;
  }

  private todoDone(): number {
    return this.todos().filter((todo: DshTodo) => todo.status === 'completed').length;
  }

  private selectedChange(): SessionFileChange | undefined {
    return this.changes.find((change: SessionFileChange) => change.path === this.selectedPath);
  }

  private startEdit(goal?: DshGoal): void {
    this.goalEditing = true;
    this.editingExistingGoal = goal !== undefined;
    this.editRef = goal ? { id: goal.id, revision: goal.revision } : undefined;
    this.objective = goal?.objective || '';
    this.roundDraft = goal?.maxGoalRounds === undefined ? '' : String(goal.maxGoalRounds);
    this.initialObjective = this.objective;
    this.initialRound = this.roundDraft;
  }

  private goalAction(action: string, title: string): void {
    if (action === 'clear' || action === 'complete') {
      this.getUIContext().showAlertDialog({
        title: title, message: action === 'clear' ? this.t("清除当前目标。已保存的对话记录会保留。") : this.t("将当前目标标为完成。"),
        primaryButton: { value: this.t("取消"), action: () => {} },
        secondaryButton: { value: title, action: () => { void this.updateGoal(action); } }
      });
    } else {
      void this.updateGoal(action);
    }
  }

  @Builder
  private action(label: () => string, enabled: () => boolean, handler: () => void) {
    Button(label()).height(42).fontSize(14).fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt)
      .enabled(enabled()).onClick(handler);
  }

  @Builder
  private icon(glyph: string, label: string, handler: () => void) {
    Button({ type: ButtonType.Circle }) {
      Text(glyph).fontFamily(DshGlyphs.family).fontSize(21).fontColor(this.colors.text);
    }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText(label).onClick(handler);
  }

  @Builder
  private note(text: () => string) {
    Text(text()).fontSize(13).fontColor(this.colors.muted).width('100%');
  }

  @Builder
  private metric(label: string, raw: () => Object | null | undefined, unit: string = '') {
    if (typeof raw() === 'number') {
      Row({ space: 12 }) {
        Text(label).fontSize(14).fontColor(this.colors.muted).layoutWeight(1);
        Text(`${raw()}${unit}`).fontSize(14).fontColor(this.colors.text);
      }.width('100%');
    }
  }

  @Builder
  private overview() {
    Column({ space: 9 }) {
      Text(this.title || this.t("对话详情")).fontSize(25).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%');
      Row({ space: 12 }) {
        Text(this.f("{0} 轮", [this.turns.length])).fontSize(13).fontColor(this.colors.muted);
        Text(this.f("{0} 个变更文件", [this.changes.length])).fontSize(13).fontColor(this.colors.muted);
        if (this.todos().length > 0) Text(this.f("待办 {0} / {1}", [this.todoDone(), this.todos().length]))
          .fontSize(13).fontColor(this.colors.muted);
      }.width('100%');
    }.width('100%').padding(16).backgroundColor(this.colors.surface).borderRadius(16);
  }

  @Builder
  private tabBar() {
    Scroll() {
      Row({ space: 7 }) {
        ForEach(this.tabs(), (tab: DetailTab) => {
          Button(tab.title).height(39).fontSize(14)
            .backgroundColor(this.tab === tab.id ? this.colors.primaryContainer : this.colors.surface)
            .fontColor(this.tab === tab.id ? this.colors.onPrimaryContainer : this.colors.text)
            .enabled(!this.working)
            .onClick(() => this.choose(tab.id));
        }, (tab: DetailTab) => tab.id);
      }.padding({ right: 4 });
    }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%');
  }

  @Builder
  private turnRow(turn: DshTurnTrace) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Column({ space: 5 }) {
          Text(this.f("第 {0} 轮", [turn.turn])).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%');
          Text(this.date(turn.start)).fontSize(13).fontColor(this.colors.muted).width('100%');
        }.layoutWeight(1);
        Text(turn.end === undefined ? this.t("进行中") : this.duration(turn.end - turn.start))
          .fontColor(this.colors.muted).fontSize(13);
        Text(this.expandedTurn === turn.startSeq ? '⌃' : '⌄').fontColor(this.colors.hint).fontSize(16);
      }.width('100%').onClick(() => this.expandedTurn = this.expandedTurn === turn.startSeq ? -1 : turn.startSeq);
      if (this.expandedTurn === turn.startSeq) {
        this.note(() => this.f("{0} 个步骤 · {1} 个事件", [turn.steps, turn.spans.length]));
        ForEach(turn.spans, (span: DshTraceSpan) => {
          Column({ space: 5 }) {
            Row({ space: 9 }) {
              Text(this.spanTitle(span)).fontSize(15).fontColor(this.colors.text).layoutWeight(1);
              if (span.failed) Text(this.t("失败")).fontSize(13).fontColor(this.colors.danger);
              else if (span.cutShort) Text(this.t("中断")).fontSize(13).fontColor(this.colors.warning);
              if (span.end !== undefined) Text(this.duration(span.end - span.start)).fontSize(13).fontColor(this.colors.muted);
            }.width('100%');
            if (span.usage) this.metric(this.t("令牌"), () => span.usage?.totalTokens ??
              (span.usage?.inputTokens ?? 0) + (span.usage?.outputTokens ?? 0));
            if (span.outcome) this.note(() => span.outcome || '');
          }.width('100%').padding(10).borderRadius(11).backgroundColor(this.colors.surfaceAlt);
        }, (span: DshTraceSpan, index: number) => `${span.kind}|${span.seq}|${index}|${span.end}|${span.failed}`);
      }
    }.width('100%').padding(15).borderRadius(15).backgroundColor(this.colors.surface);
  }

  @Builder
  private trajectory() {
    if (this.turns.length === 0 && !this.loading) {
      this.note(() => this.t("还没有完整的一轮。每一轮的步骤和用时会排在这里。"));
    }
    ForEach(this.turns, (turn: DshTurnTrace) => {
      this.turnRow(turn);
    }, (turn: DshTurnTrace) => JSON.stringify(turn));
    this.historyButton();
  }

  @Builder
  private historyButton() {
    if (this.hasMore) this.action(() => this.loadingOlder ? this.t("正在加载…") : this.t("加载更早的记录"), () => !this.loadingOlder && !this.loading,
      () => { void this.older(); });
  }

  @Builder
  private diffContent(change: SessionFileChange) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        this.action(() => this.t("返回变更列表"), () => true, () => this.selectedPath = '');
        Text(`+${change.added}`).fontSize(14).fontColor(this.colors.success);
        Text(`−${change.removed}`).fontSize(14).fontColor(this.colors.danger);
      }.width('100%');
      Text(change.path).fontSize(15).fontColor(this.colors.text).width('100%').copyOption(CopyOptions.LocalDevice);
      ForEach(change.lines.slice(0, this.shownDiffLines), (line: SessionDiffLine) => {
        Row({ space: 8 }) {
          Text(line.oldLine === undefined ? '' : String(line.oldLine)).width(34).fontSize(11).fontColor(this.colors.hint)
            .fontFamily(DshType.monoFamily).textAlign(TextAlign.End);
          Text(line.newLine === undefined ? '' : String(line.newLine)).width(34).fontSize(11).fontColor(this.colors.hint)
            .fontFamily(DshType.monoFamily).textAlign(TextAlign.End);
          Text(`${line.marker === '@' ? '' : line.marker}${line.text}`)
            .fontSize(13).fontFamily(DshType.monoFamily).layoutWeight(1).copyOption(CopyOptions.LocalDevice)
            .fontColor(line.marker === '+' ? this.colors.success : line.marker === '-' ? this.colors.danger : this.colors.muted);
        }.width('100%').alignItems(VerticalAlign.Top);
      }, (line: SessionDiffLine, index: number) => `${index}|${line.marker}|${line.text}`);
      if (change.lines.length > this.shownDiffLines) {
        this.action(() => this.f("继续显示（{0} / {1} 行）", [this.shownDiffLines, change.lines.length]), () => true,
          () => { this.shownDiffLines = Math.min(change.lines.length, this.shownDiffLines + 500); });
      }
    }.padding(12).width('100%').backgroundColor(this.colors.codeSurface).borderRadius(14);
  }

  @Builder
  private changeList() {
    if (this.selectedChange()) {
      this.diffContent(this.selectedChange()!);
    } else {
      if (this.changes.length === 0 && !this.loading) this.note(() => this.t("还没有改过文件。"));
      ForEach(this.changes, (change: SessionFileChange) => {
        Row({ space: 8 }) {
          Text(DshGlyphs.file).fontFamily(DshGlyphs.family).fontSize(20)
            .fontColor(change.created ? this.colors.success : this.colors.primary);
          Column({ space: 5 }) {
            Text(change.path).fontSize(15).fontColor(this.colors.text).width('100%');
            Text(this.f("第 {0} 轮 · {1} 次变更", [change.turn, change.edits])).fontSize(13).fontColor(this.colors.muted).width('100%');
          }.layoutWeight(1);
          Text(`+${change.added}`).fontSize(13).fontColor(this.colors.success);
          Text(`−${change.removed}`).fontSize(13).fontColor(this.colors.danger);
        }.padding(13).width('100%').backgroundColor(this.colors.surface).borderRadius(14)
          .onClick(() => { this.shownDiffLines = 300; this.selectedPath = change.path; });
      }, (change: SessionFileChange) => `${change.path}|${change.created}|${change.turn}|${change.edits}|${change.added}|${change.removed}`);
      this.note(() => this.t("只统计已加载的记录里，用写入和编辑工具做的改动。"));
      this.historyButton();
    }
  }

  @Builder
  private goalForm() {
    Column({ space: 10 }) {
      Text(this.editingExistingGoal ? this.t("编辑目标") : this.t("新建目标")).fontSize(17).fontWeight(FontWeight.Medium)
        .fontColor(this.colors.text).width('100%');
      TextArea({ text: this.objective, placeholder: this.t("想要完成什么？") }).height(110)
        .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).enabled(!this.working)
        .onChange((value: string) => { this.objective = value; });
      TextInput({ text: this.roundDraft, placeholder: this.t("回合上限（选填）") }).type(InputType.Number)
        .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).enabled(!this.working)
        .onChange((value: string) => { this.roundDraft = value; });
      Row({ space: 8 }) {
        this.action(() => this.t("取消"), () => !this.working, () => { this.back(); });
        this.action(() => this.working ? this.t("保存中…") : this.t("保存"), () => !this.working && !!this.objective.trim(),
          () => { void this.updateGoal(this.editingExistingGoal ? 'edit' : 'create'); });
      }.width('100%');
    }.padding(14).width('100%').backgroundColor(this.colors.surface).borderRadius(14);
  }

  @Builder
  private goalCard() {
    Column({ space: 10 }) {
      Text(this.t("目标")).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%');
      MessageBody({ text: this.goal?.objective || '', colors: this.colors });
      this.note(() => this.goalSummary());
      if (this.goalSupported()) {
        Flex({ wrap: FlexWrap.Wrap }) {
          this.action(() => this.t("编辑"), () => !this.working, () => { if (this.goal) this.startEdit(this.goal); });
          if (this.goal?.phase === 'active' && this.goal?.activation !== 'disarmed') {
            this.action(() => this.t("暂停"), () => !this.working, () => this.goalAction('pause', this.t("暂停目标")));
          } else if (this.goal?.phase !== 'complete') {
            this.action(() => this.t("恢复"), () => !this.working, () => this.goalAction('resume', this.t("恢复目标")));
          }
          if (this.goal?.phase !== 'complete') {
            this.action(() => this.t("完成"), () => !this.working, () => this.goalAction('complete', this.t("完成目标")));
          }
          else this.action(() => this.t("新建目标"), () => !this.working, () => this.startEdit());
          this.action(() => this.t("清除"), () => !this.working, () => this.goalAction('clear', this.t("清除目标")));
        }.width('100%');
      }
    }.width('100%').padding(14).backgroundColor(this.colors.surface).borderRadius(14);
  }

  private goalSummary(): string {
    const goal = this.goal;
    if (!goal) return '';
    const round = goal.maxGoalRounds === undefined ? this.f("第 {0} 轮", [goal.roundsStarted]) :
      this.f("{0} / {1} 轮", [goal.roundsStarted, goal.maxGoalRounds]);
    return `${this.goalPhase(goal)} · ${round}`;
  }

  @Builder
  private progress() {
    if (this.goalEditing) this.goalForm();
    else if (this.goal) this.goalCard();
    else if (this.goalSupported()) this.action(() => this.t("新建目标"), () => !this.working, () => this.startEdit());
    if (object(this.projections?.values['plan'])['active'] === true) {
      this.note(() => this.t("计划模式 · 当前对话正在制定计划。"));
    } else if (object(this.projections?.values['plan'])['pending'] === true) {
      this.note(() => this.t("正在切换计划模式。"));
    }
    if (this.todos().length > 0) {
      Column({ space: 9 }) {
        Text(this.f("待办 · {0} / {1}", [this.todoDone(), this.todos().length])).fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor(this.colors.text).width('100%');
        Progress({ value: this.todoDone(), total: this.todos().length, type: ProgressType.Linear })
          .color(this.colors.primary).width('100%');
        ForEach(this.todos(), (todo: DshTodo) => {
          Row({ space: 10 }) {
            Text(todo.content).fontColor(this.colors.text).fontSize(15).layoutWeight(1);
            Text(this.todoState(todo)).fontColor(todo.status === 'completed' ? this.colors.success : this.colors.muted)
              .fontSize(13);
          }.width('100%').padding({ top: 5, bottom: 5 });
        }, (todo: DshTodo, index: number) => `${index}|${todo.content}|${todo.status}`);
      }.width('100%').padding(14).backgroundColor(this.colors.surface).borderRadius(14);
    } else if (!this.goal && !this.goalEditing && !this.loading) {
      this.note(() => this.t("还没有目标或待办。复杂任务里 AI 会列出待办，进度在这里看。"));
    }
  }

  private usageValue(group: string, field: string): Object | null | undefined {
    return object(this.projections?.values[group])[field];
  }

  private hasUsage(): boolean {
    return ['tokenUsage', 'contextPressure', 'contextBreakdown', 'sessionStats'].some((group: string) =>
      Object.keys(object(this.projections?.values[group])).length > 0);
  }

  @Builder
  private usage() {
    Column({ space: 11 }) {
      Text(this.t("令牌用量")).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%');
      this.metric(this.t("未缓存输入"), () => this.usageValue('tokenUsage', 'uncachedInputTokens'));
      this.metric(this.t("缓存命中"), () => this.usageValue('tokenUsage', 'cacheReadTokens'));
      this.metric(this.t("缓存写入"), () => this.usageValue('tokenUsage', 'cacheWriteTokens'));
      this.metric(this.t("输出"), () => this.usageValue('tokenUsage', 'outputTokens'));
      this.metric(this.t("当前占用"), () => this.usageValue('contextPressure', 'projectedTokens') ?? this.usageValue('contextPressure', 'pressureTokens'));
      this.metric(this.t("上下文窗口"), () => this.usageValue('contextPressure', 'contextWindow'));
      this.metric(this.t("系统指令"), () => this.usageValue('contextBreakdown', 'systemTokens'));
      this.metric(this.t("工具"), () => this.usageValue('contextBreakdown', 'toolsTokens'));
      this.metric(this.t("消息"), () => this.usageValue('contextBreakdown', 'messageTokens'));
      this.metric(this.t("回合"), () => this.usageValue('sessionStats', 'turns'));
      this.metric(this.t("模型耗时"), () => this.usageValue('sessionStats', 'llmMs'), this.t(" 毫秒"));
      this.metric(this.t("工具耗时"), () => this.usageValue('sessionStats', 'toolMs'), this.t(" 毫秒"));
      if (!this.hasUsage()) this.note(() => this.t("当前对话还没有可显示的上下文用量。"));
    }.width('100%').padding(14).backgroundColor(this.colors.surface).borderRadius(14);
  }

  @Builder
  private contextTab() {
    this.usage();
    ForEach(this.turns.filter((turn: DshTurnTrace) => turnTotalTokens(turn) > 0).slice(0, 12), (turn: DshTurnTrace) => {
      Row({ space: 9 }) {
        Text(this.f("第 {0} 轮", [turn.turn])).fontSize(14).fontColor(this.colors.text).layoutWeight(1);
        Text(this.f("{0} 令牌", [turnTotalTokens(turn)])).fontSize(13).fontColor(this.colors.muted);
      }.width('100%').padding(12).backgroundColor(this.colors.surface).borderRadius(12);
    }, (turn: DshTurnTrace) => `${turn.startSeq}|${turnTotalTokens(turn)}`);
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 9 }) {
        this.icon(DshGlyphs.back, this.t("返回"), () => { if (!this.back()) this.onClose(); });
        Text(this.t("对话详情")).fontSize(22).fontWeight(FontWeight.Medium).fontColor(this.colors.text).layoutWeight(1);
        this.icon(DshGlyphs.refresh, this.t("刷新详情"), () => { if (!this.working) void this.refresh(); });
        if (this.sessionId) this.action(() => this.t("分支"), () => !this.working, () => this.leaveGoalEditor(this.onFork));
      }.width('100%');
      this.tabBar();
      Scroll() {
        Column({ space: 12 }) {
          this.overview();
          if (this.error) Text(this.t(this.error)).fontSize(14).fontColor(this.colors.danger).width('100%');
          if (this.loading) LoadingProgress().width(24).height(24).color(this.colors.primary);
          if (this.tab === 'trajectory') this.trajectory();
          else if (this.tab === 'changes') this.changeList();
          else if (this.tab === 'progress') this.progress();
          else if (this.tab === 'context') this.contextTab();
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: 20 });
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top);
    }.width('100%').height('100%').padding({ left: 16, right: 16, top: 7 }).backgroundColor(this.colors.background);
  }
}
