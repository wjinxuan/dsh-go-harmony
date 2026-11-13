import { DshClient } from '../dsh/DshClient';
import { DshQueuedPrompt, DshQueueAction } from '../dsh/DshWire';
import { ThemeColors, themeColors } from './DshTheme';

@Component
export struct ChatActivityPanel {
  @Prop colors: ThemeColors = themeColors();
  @Prop @Watch('reset') sessionId: string = '';
  @Prop queue: DshQueuedPrompt[] = [];
  client: DshClient = new DshClient();
  onRecover: (sessionId: string, connection: number, text: string) => void = () => {};
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
    if (this.busy || item.automatic) return;
    const generation = this.generation;
    const sessionId = this.sessionId;
    const connection = this.client.connectionIdentity();
    this.busy = item.id;
    this.error = '';
    try {
      if (action === 'now') {
        const result = await this.client.sendQueuedNow(sessionId, item.id);
        // Recover locally before a route disappears; the host may already have removed these items.
        if (result.recoverable.length) this.onRecover(sessionId, connection, result.recoverable.map((entry) => entry.text).join('\n\n'));
        if (generation === this.generation && result.error) this.error = result.error;
      } else {
        await this.client.updateQueue(sessionId, item.id, action, action === 'edit' ? this.draft.trim() : undefined);
        if (action === 'remove' && item.resendable) this.onRecover(sessionId, connection, item.text);
      }
      if (generation === this.generation) this.editing = '';
    } catch {
      if (generation === this.generation) this.error = '队列操作未能确认，请刷新后检查。编辑内容仍保留。';
    } finally { if (generation === this.generation) this.busy = ''; }
  }

  build() {
    Column({ space: 8 }) {
      if (this.queue.length) {
        Row() {
          Text(`${this.queue.length} 条排队消息`).fontSize(13).fontColor(this.colors.muted).layoutWeight(1);
          Button(this.expanded ? '收起' : '展开').fontSize(13).height(32).fontColor(this.colors.primary)
            .backgroundColor(Color.Transparent).onClick(() => this.expanded = !this.expanded);
        }.width('100%');
        if (this.expanded) {
          Scroll() {
            Column({ space: 10 }) {
              ForEach(this.queue, (item: DshQueuedPrompt) => {
                Column({ space: 8 }) {
                  Text(item.target === 'next-step' ? '下一步发送' : '排队中 · 本轮结束后发送')
                    .fontSize(11).fontColor(this.colors.muted);
                  if (this.editing === item.id) {
                    TextArea({ text: this.draft, placeholder: '编辑排队消息' }).height(80)
                      .fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
                      .enabled(!this.busy).onChange((text: string) => this.draft = text);
                    Row({ space: 8 }) {
                      Button('取消').height(32).fontSize(12).fontColor(this.colors.muted).backgroundColor(Color.Transparent)
                        .enabled(!this.busy).onClick(() => this.editing = '');
                      Button('保存').height(32).fontSize(12).fontColor(this.colors.onPrimary).backgroundColor(this.colors.primary)
                        .enabled(!this.busy && !!this.draft.trim()).onClick(() => { void this.act(item, 'edit'); });
                    }
                  } else {
                    Text(item.text || '附件消息').fontSize(14).fontColor(this.colors.text).maxLines(3)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });
                    if (!item.automatic) {
                      Row({ space: 4 }) {
                        Button('编辑').fontSize(12).height(32).fontColor(this.colors.primary).backgroundColor(Color.Transparent)
                          .enabled(!this.busy && item.resendable).onClick(() => { this.editing = item.id; this.draft = item.text; });
                        Button(item.resendable ? '撤回' : '移除').fontSize(12).height(32).fontColor(this.colors.muted).backgroundColor(Color.Transparent)
                          .enabled(!this.busy).onClick(() => { void this.act(item, 'remove'); });
                        if (item.target === 'next-turn') {
                          Button('插入引导').fontSize(12).height(32).fontColor(this.colors.primary).backgroundColor(Color.Transparent)
                            .enabled(!this.busy).onClick(() => { void this.act(item, 'steer'); });
                        }
                        Button('立即发送').fontSize(12).height(32).fontColor(this.colors.primary).backgroundColor(Color.Transparent)
                          .enabled(!this.busy && item.resendable).onClick(() => { void this.act(item, 'now'); });
                      }.width('100%');
                    }
                  }
                }.alignItems(HorizontalAlign.Start).width('100%').padding(10).backgroundColor(this.colors.surface).borderRadius(12);
              }, (item: DshQueuedPrompt) => `${item.id}/${item.target}/${item.text}/${item.automatic}/${item.resendable}`);
            }.width('100%');
          }.width('100%').constraintSize({ maxHeight: 200 });
        }
      }
      if (this.error) Text(this.error).fontSize(13).fontColor(this.colors.danger);
    }.width('100%');
  }
}
