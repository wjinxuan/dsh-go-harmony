import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale'
import { DshClient } from '../dsh/DshClient';
import { DshQueuedPrompt, DshQueueAction, DshQueueMoveResult, DshRpcError } from '../dsh/DshWire';
import { ThemeColors, themeColors } from './DshTheme';

@Component
export struct ChatActivityPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors();
  @Prop @Watch('reset') sessionId: string = '';
  @Prop queue: DshQueuedPrompt[] = [];
  @Prop attachmentRequests: string[] = [];
  @Prop attachmentBusy: boolean = false;
  client: DshClient = new DshClient();
  onRecover: (sessionId: string, connection: number, items: DshQueuedPrompt[]) => void = () => {};
  onWithdrawAttachment: (sessionId: string, connection: number, item: DshQueuedPrompt) => Promise<void> = async () => {};
  onSendNow: (sessionId: string, connection: number, item: DshQueuedPrompt) => Promise<DshQueueMoveResult> =
    async (sessionId: string, _connection: number, item: DshQueuedPrompt) => this.client.sendQueuedNow(sessionId, item.id);
  @State private expanded: boolean = false;
  @State private editing: string = '';
  @State private draft: string = '';
  @State private busy: string = '';
  @State private error: string = '';
  private generation: number = 0;

  aboutToDisappear(): void { this.generation++; }
  private reset(): void {
    this.generation++; this.editing = ''; this.draft = ''; this.busy = ''; this.error = '';
  }

  private async act(item: DshQueuedPrompt, action: DshQueueAction | 'now'): Promise<void> {
    if (this.busy || item.automatic || (action === 'remove' && item.hasAttachments && this.attachmentBusy) ||
      (action === 'now' && (this.attachmentBusy || !this.canWithdraw(item)))) return;
    const generation = this.generation;
    const sessionId = this.sessionId;
    const connection = this.client.connectionIdentity();
    const recoverable = this.canWithdraw(item);
    this.busy = item.id;
    this.error = '';
    try {
      if (action === 'now') {
        const result = await this.onSendNow(sessionId, connection, item);
        // Recover locally before a route disappears; the host may already have removed these items.
        if (result.recoverable.length) this.onRecover(sessionId, connection, result.recoverable);
        if (generation === this.generation && result.error) this.error = result.error;
      } else if (action === 'remove' && item.hasAttachments && recoverable) {
        await this.onWithdrawAttachment(sessionId, connection, item);
      } else {
        await this.client.updateQueue(sessionId, item.id, action, action === 'edit' ? this.draft.trim() : undefined);
        if (action === 'remove' && recoverable) this.onRecover(sessionId, connection, [item]);
      }
      if (generation === this.generation) this.editing = '';
    } catch (error) {
      if (generation === this.generation) {
        this.error = action === 'remove' && error instanceof DshRpcError && error.code === 'session/queue-item-not-found' ?
          this.t("来不及了，AI 已经读到这条消息") : this.t("队列操作未能确认，请刷新后检查。编辑内容仍保留。");
      }
    } finally { if (generation === this.generation) this.busy = ''; }
  }

  private canWithdraw(item: DshQueuedPrompt): boolean {
    return item.resendable || (item.hasAttachments === true && this.attachmentRequests.includes(item.requestId || ''));
  }

  build() {
    Column({ space: 8 }) {
      if (this.queue.length) {
        Row() {
          Text(this.f("{0} 条排队消息", [this.queue.length])).fontSize(13).fontColor(this.colors.muted).layoutWeight(1);
          Button(this.expanded ? this.t("收起") : this.t("展开")).fontSize(13).height(32).fontColor(this.colors.primary)
            .backgroundColor(Color.Transparent).onClick(() => this.expanded = !this.expanded);
        }.width('100%');
        if (this.expanded) {
          Scroll() {
            Column({ space: 10 }) {
              ForEach(this.queue, (item: DshQueuedPrompt) => {
                Column({ space: 8 }) {
                  Text(item.target === 'next-step' ? this.t("下一步发送") : this.t("排队中 · 本轮结束后发送"))
                    .fontSize(11).fontColor(this.colors.muted);
                  if (this.editing === item.id) {
                    TextArea({ text: this.draft, placeholder: this.t("编辑排队消息") }).height(80)
                      .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
                      .enabled(!this.busy).onChange((text: string) => this.draft = text);
                    Row({ space: 8 }) {
                      Button(this.t("取消")).height(32).fontSize(12).fontColor(this.colors.muted).backgroundColor(Color.Transparent)
                        .enabled(!this.busy).onClick(() => this.editing = '');
                      Button(this.t("保存")).height(32).fontSize(12).fontColor(this.colors.onPrimary).backgroundColor(this.colors.primary)
                        .enabled(!this.busy && !!this.draft.trim()).onClick(() => { void this.act(item, 'edit'); });
                    }
                  } else {
                    Text(item.text || this.t("附件消息")).fontSize(14).fontColor(this.colors.text).maxLines(3)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });
                    if (!item.automatic) {
                      Row({ space: 4 }) {
                        Button(this.t("编辑")).fontSize(12).height(32).fontColor(this.colors.primary).backgroundColor(Color.Transparent)
                          .enabled(!this.busy && item.resendable).onClick(() => { this.editing = item.id; this.draft = item.text; });
                        Button(this.canWithdraw(item) ? this.t("撤回") : this.t("移除")).fontSize(12).height(32).fontColor(this.colors.muted).backgroundColor(Color.Transparent)
                          .enabled(!this.busy && (!item.hasAttachments || !this.attachmentBusy))
                          .onClick(() => { void this.act(item, 'remove'); });
                        if (item.target === 'next-turn') {
                          Button(this.t("插入引导")).fontSize(12).height(32).fontColor(this.colors.primary).backgroundColor(Color.Transparent)
                            .enabled(!this.busy).onClick(() => { void this.act(item, 'steer'); });
                        }
                        Button(this.t("立即发送")).fontSize(12).height(32).fontColor(this.colors.primary).backgroundColor(Color.Transparent)
                          .enabled(!this.busy && !this.attachmentBusy && this.canWithdraw(item))
                          .onClick(() => { void this.act(item, 'now'); });
                      }.width('100%');
                    }
                  }
                }.alignItems(HorizontalAlign.Start).width('100%').padding(10).backgroundColor(this.colors.surface).borderRadius(12);
              }, (item: DshQueuedPrompt) => `${item.id}/${item.target}/${item.text}/${item.automatic}/${item.resendable}/${item.hasAttachments}`);
            }.width('100%');
          }.width('100%').constraintSize({ maxHeight: 200 });
        }
      }
      if (this.error) Text(this.t(this.error)).fontSize(13).fontColor(this.colors.danger);
    }.width('100%');
  }
}
