import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { object, string, number, WireObject } from '../dsh/DshWire';
import { TransportControl } from '../remote/TransportEndpoint';
import { PhoneTaskClient } from '../phone/PhoneTaskClient';
import { phoneAccessibilityCall } from '../phone/PhoneAccessibilityClient';
import { PhoneAction } from '../phone/PhoneAccessibilityData';
import { phoneTaskFirstStart } from '../phone/PhoneTaskData';
import { executePhoneIntent } from '../phone/PhoneIntent';
import { collectPhoneList } from '../phone/PhoneCollect';
import { attachPhoneScreenImage } from '../phone/PhoneScreenImage';
import { requestPhoneCapture } from '../phone/PhoneControl';
import { localizedSettingsText } from './SettingsLocale';
import { ThemeColors, themeColors } from './DshTheme';
@Component
export struct PhoneTaskHost {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system';
  @Prop @Watch('connectionChanged') localConnected: boolean = false;
  @Prop colors: ThemeColors = themeColors();
  getControl: () => Promise<TransportControl> = async () => { throw new Error('本机连接服务不可用'); };
  onTaskStarted: () => void = () => {};
  @State private pending: WireObject = {};
  @State private working: boolean = false;
  @State private message: string = '';
  private client?: PhoneTaskClient;
  private timer: number = -1;
  private generation: number = 0;
  private active: boolean = false;
  private polling: boolean = false;
  private startedTasks: string[] = [];
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage); }
  aboutToAppear(): void { this.active = true; this.connectionChanged(); }
  aboutToDisappear(): void { this.active = false; this.generation++; if (this.timer >= 0) clearInterval(this.timer); }
  private connectionChanged(): void {
    this.generation++; this.client = undefined; this.pending = {}; this.working = false;
    if (this.timer >= 0) clearInterval(this.timer); this.timer = -1;
    if (this.active && this.localConnected) { this.timer = setInterval(() => { void this.poll(); }, 800); void this.poll(); }
  }
  private async poll(): Promise<void> {
    if (this.polling || !this.localConnected || !this.active) return;
    this.polling = true; const generation = this.generation;
    try {
      const client = this.client || new PhoneTaskClient(await this.getControl());
      const state = await client.request('pending');
      if (this.active && generation === this.generation) {
        const next = object(state['request']); this.client = client;
        if (this.working && string(next['id']) !== string(this.pending['id'])) { this.generation++; this.working = false; this.message = ''; }
        this.pending = next;
      }
    } catch { if (generation === this.generation) { this.generation++; this.client = undefined; this.pending = {}; this.working = false; this.message = ''; } }
    finally { this.polling = false; }
  }
  private async finish(allow: boolean): Promise<void> {
    const id = string(this.pending['id']), client = this.client; if (!id || !client || this.working) return;
    const generation = this.generation, expires = number(this.pending['expires'], 0), tool = string(this.pending['tool']), args = object(this.pending['args']), taskId = string(this.pending['taskId']);
    this.working = true; this.message = '';
    const current = (): boolean => this.active && this.localConnected && generation === this.generation && Date.now() < expires;
    const start = (): void => {
      if (!current()) throw new Error('手机操作已取消或过期');
      if (phoneTaskFirstStart(this.startedTasks, taskId)) this.onTaskStarted();
    };
    try {
      if (!allow) { await client.request('complete', { 'id': id, 'error': '用户拒绝了本次手机操作' }); return; }
      let value: WireObject;
      if (tool === 'handoff') { start(); value = { 'continued': true }; }
      else if (tool === 'intent') { start(); value = await executePhoneIntent(this.getUIContext().getHostContext() as common.UIAbilityContext, args, current); }
      else if (tool === 'open') {
        start();
        await (this.getUIContext().getHostContext() as common.UIAbilityContext).openLink(string(args['url']));
        value = { 'launched': true, 'businessResult': 'unknown' };
      } else if (tool === 'clipboard') {
        start();
        if (args['get'] === true) value = { 'text': (await pasteboard.getSystemPasteboard().getData()).getPrimaryText().slice(0, 8192) };
        else { await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, string(args['set']))); value = { 'written': true }; }
      } else if (tool === 'notify') {
        start();
        await notificationManager.requestEnableNotification(this.getUIContext().getHostContext() as common.UIAbilityContext);
        if (!current()) throw new Error('手机操作已取消或过期');
        await notificationManager.publish({ id: 720001, content: { contentType: 0,
          normal: { title: string(args['title']), text: string(args['text']) } } });
        value = { 'published': true };
      }
      else {
        if (tool === 'screen' && args['image'] === true) await requestPhoneCapture(this.getUIContext().getHostContext() as common.UIAbilityContext);
        this.message = '3 秒后执行，请切回目标应用';
        await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 3000); });
        start();
        if (tool === 'collect') {
          value = await collectPhoneList(args, (command: PhoneAction): Promise<WireObject> => phoneAccessibilityCall(this.getUIContext().getHostContext() as common.UIAbilityContext, command, current), current);
        } else {
        const command: PhoneAction = { action: tool === 'screen' ? 'screen' : tool === 'tap_xy' ? args['action'] === 'swipe' ? 'gestureSwipe' : args['action'] === 'long' ? 'gestureLong' : 'gestureTap' : tool === 'key' ? args['key'] === 'recents' ? 'recentTask' : args['key'] === 'notifications' ? 'notificationCenter' : string(args['key']) : tool === 'tap' ? args['long'] === true ? 'longClick' : 'click' : tool === 'type' ? 'setText' : args['direction'] === 'left' ? 'scrollLeft' : args['direction'] === 'right' ? 'scrollRight' : args['direction'] === 'up' ? 'scrollBackward' : 'scrollForward',
          screenId: string(args['screen']), nodeId: number(args['id'], -1), text: string(args['text']), approved: true };
        if (tool === 'tap_xy') { command.x = number(args['x'], -1); command.y = number(args['y'], -1); command.x2 = number(args['x2'], -1); command.y2 = number(args['y2'], -1); command.width = number(args['width'], 0); command.height = number(args['height'], 0); command.duration = number(args['duration'], 100); }
        value = await phoneAccessibilityCall(this.getUIContext().getHostContext() as common.UIAbilityContext, command, current);
        if (tool === 'screen' && args['image'] === true) {
          try { value = await attachPhoneScreenImage(this.getUIContext().getHostContext() as common.UIAbilityContext, value, current); }
          catch (error) { value['imageError'] = (error as Error).message || '截图不可用'; }
        }
        if (tool !== 'screen') {
          const screenCommand: PhoneAction = { action: 'screen', screenId: '', nodeId: -1, text: '', approved: false };
          await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 250); });
          const screen = await phoneAccessibilityCall(this.getUIContext().getHostContext() as common.UIAbilityContext, screenCommand, current);
          value = { 'acknowledged': true, 'screen': screen, 'businessResult': 'unknown' };
        }
        }
      }
      await client.request('complete', { 'id': id, 'value': value });
    } catch (error) {
      try { await client.request('complete', { 'id': id, 'error': (error as Error).message || '手机操作失败' }); } catch {}
    } finally { if (generation === this.generation) { this.pending = {}; this.working = false; this.message = ''; } }
  }
  private async stop(): Promise<void> { const client = this.client; this.generation++; this.pending = {}; this.working = false; this.message = ''; try { await client?.request('stop'); } catch {} }
  build() {
    if (string(this.pending['id'])) {
      Column({ space: 10 }) {
        Text(this.t('模型请求操作手机')).fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.colors.text);
        Text(string(this.pending['tool']) + ' · ' + this.t('每次操作都需你确认')).fontColor(this.colors.text);
        Text(string(this.pending['summary']).slice(0, 2000)).fontSize(13).fontColor(this.colors.muted);
        Text(this.t(this.message || '确认后有 3 秒切回目标应用。超时会拒绝，不会自动继续。')).fontSize(13).fontColor(this.colors.muted);
        Row({ space: 10 }) {
          Button(this.t('停止手机操作')).onClick(() => { void this.stop(); });
          Button(this.t('拒绝')).enabled(!this.working).onClick(() => { void this.finish(false); });
          if (string(this.pending['tool']) === 'clipboard' && object(this.pending['args'])['get'] === true) {
            PasteButton({ icon: PasteIconStyle.LINES, text: PasteDescription.PASTE, buttonType: ButtonType.Capsule })
              .enabled(!this.working).onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
                if (result === PasteButtonOnClickResult.SUCCESS) void this.finish(true);
                else this.message = '未能获得本次剪贴板访问授权。';
              });
          } else Button(this.t(string(this.pending['tool']) === 'handoff' ? '继续' : '允许本次')).enabled(!this.working).onClick(() => { void this.finish(true); });
        }
      }.width('92%').padding(16).backgroundColor(this.colors.surface).borderRadius(16).border({ width: 1, color: this.colors.border }).position({ x: '4%', y: '100%' }).markAnchor({ x: 0, y: '100%' });
    }
  }
}
