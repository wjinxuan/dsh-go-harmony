import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { DshClient } from '../dsh/DshClient';
import { DshQuestion, DshQuestionRequest, DshQuestionOption } from '../dsh/DshWire';
import { QuestionDraft, QuestionDrafts, toggleQuestion, questionAnswers } from './QuestionDrafts';
import { ThemeColors, themeColors } from './DshTheme';

@Component
export struct QuestionCard {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors();
  @Prop request: DshQuestionRequest;
  client: DshClient = new DshClient();
  draftStore: QuestionDrafts = new QuestionDrafts();
  @State private drafts: QuestionDraft[] = [];
  @State private busy: boolean = false;
  @State private settled: boolean = false;
  @State private error: string = '';
  @State private remaining: number = 0;
  private active: boolean = false;
  private timer: number = -1;

  aboutToAppear(): void {
    this.active = true; this.drafts = this.draftStore.read(this.request);
    const deadline = Date.now() + (this.request.remainingMs || 0);
    this.remaining = Math.ceil((this.request.remainingMs || 0) / 1000);
    if (this.request.timed && !this.request.continued && this.remaining > 0) {
      this.timer = setInterval(() => { this.remaining = Math.max(0, Math.ceil((deadline - Date.now()) / 1000)); }, 1000);
    }
  }
  aboutToDisappear(): void { this.active = false; clearInterval(this.timer); }

  private draft(question: DshQuestion): QuestionDraft {
    return this.drafts.find((draft) => draft.id === question.id) ||
      { id: question.id, selected: [], custom: '', customOpen: question.options.length === 0 };
  }

  private update(draft: QuestionDraft): void {
    this.drafts = this.drafts.map((item) => item.id === draft.id ? draft : item);
    this.draftStore.save(this.request, this.drafts);
  }

  private async respond(reject: boolean): Promise<void> {
    if (this.busy || this.settled) return;
    const answers = questionAnswers(this.request, this.drafts);
    if (!reject && !answers) return;
    this.busy = true;
    this.error = '';
    try {
      if (reject) await this.client.rejectQuestion(this.request);
      else if (answers) await this.client.answerQuestion(this.request, answers);
      this.draftStore.remove(this.request);
      if (this.active) this.settled = true;
    } catch {
      if (this.active) this.error = this.t("提交未能确认，请检查连接。已填写的答案仍保留。");
    } finally { if (this.active) this.busy = false; }
  }

  @Builder
  private questionBlock(question: DshQuestion) {
    Column({ space: 10 }) {
      if (question.header) Text(question.header).fontSize(12).fontColor(this.colors.muted);
      Text(question.question).fontSize(16).fontColor(this.colors.text);
      if (question.detail) Text(question.detail).fontSize(14).fontColor(this.colors.muted);
      ForEach(question.options, (option: DshQuestionOption) => {
        Row({ space: 10 }) {
          Text(this.draft(question).selected.includes(option.label) ? '●' : '○').fontColor(this.colors.primary);
          Column({ space: 4 }) {
            Text(option.label).fontSize(15).fontColor(this.colors.text);
            if (option.description) Text(option.description).fontSize(13).fontColor(this.colors.muted);
          }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        }.width('100%').padding(12).backgroundColor(this.colors.surfaceAlt).borderRadius(12)
          .enabled(!this.busy).onClick(() => this.update(toggleQuestion(this.draft(question), question, option.label)));
      }, (option: DshQuestionOption) => option.label);
      if (question.options.length) {
        Button(this.t("自己填写")).fontColor(this.colors.primary).backgroundColor(Color.Transparent).enabled(!this.busy)
          .onClick(() => {
            const draft = this.draft(question);
            this.update({ id: draft.id, selected: question.multiSelect ? draft.selected : [],
              custom: draft.custom, customOpen: !draft.customOpen });
          });
      }
      if (this.draft(question).customOpen) {
        TextArea({ text: this.draft(question).custom, placeholder: this.t("输入你的回答…") })
          .height(80).fontSize(15).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
          .enabled(!this.busy).onChange((value: string) => {
            const draft = this.draft(question);
            this.update({ id: draft.id, selected: draft.selected, custom: value, customOpen: true });
          });
      }
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  build() {
    Column({ space: 16 }) {
      Text(this.request.questions.length > 1 ? this.f("有 {0} 个问题想问你", [this.request.questions.length]) : this.t("有个问题想问你"))
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.colors.primary);
      if (this.settled) Text(this.t("已提交")).fontColor(this.colors.muted);
      else {
        if (this.request.continued) Text(this.t("任务已继续，你仍可以补充回答。")).fontSize(12).fontColor(this.colors.muted);
        else if (this.request.timed) Text(this.remaining > 0 ? this.f("{0} 秒后继续任务", [this.remaining]) : this.t("正在继续任务…"))
          .fontSize(12).fontColor(this.colors.muted);
        ForEach(this.request.questions, (question: DshQuestion) => { this.questionBlock(question); },
          (question: DshQuestion) => question.id);
        if (this.error) Text(this.t(this.error)).fontSize(13).fontColor(this.colors.danger);
        Row({ space: 12 }) {
          if (!this.request.continued) {
            Button(this.t("不回答")).layoutWeight(1).height(44).fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt)
              .enabled(!this.busy).onClick(() => { void this.respond(true); });
          }
          Button(this.busy ? this.t("提交中…") : this.t("提交")).layoutWeight(1).height(44).fontColor(this.colors.onPrimary)
            .backgroundColor(this.colors.primary).enabled(!this.busy && !!questionAnswers(this.request, this.drafts))
            .onClick(() => { void this.respond(false); });
        }.width('100%');
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(16).backgroundColor(this.colors.surface).borderRadius(16)
      .border({ width: 1, color: this.colors.border });
  }
}
