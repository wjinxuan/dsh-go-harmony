import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { PhonePolicy, PhoneCheck, updatePhoneRule, phonePolicyRule } from '../phone/PhoneData';
import { checkPhone, capturePhoneScreen, loadPhonePolicy, savePhonePolicy } from '../phone/PhoneControl';
import { phoneAccessibilityStatus, phoneAccessibilityCall } from '../phone/PhoneAccessibilityClient';
import { PhoneTree, PhoneNode, PhoneAction } from '../phone/PhoneAccessibilityData';
import { PhoneTaskClient } from '../phone/PhoneTaskClient';
import { TransportControl } from '../remote/TransportEndpoint';
import { array, object, string, number } from '../dsh/DshWire';
import { localizedSettingsText } from './SettingsLocale';
import { ThemeColors, themeColors } from './DshTheme';
@Component
export struct PhoneControlPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system';
  @Prop colors: ThemeColors = themeColors();
  onClose: () => void = () => {};
  onScreenText: (text: string) => void = () => {};
  getControl: () => Promise<TransportControl> = async () => { throw new Error('本机连接服务不可用'); };
  onBackHandler?: (handler: (() => boolean) | undefined) => void;
  @State private policy: PhonePolicy = { confirmMode: 'ask', denyPackages: [], confirmEveryWritePackages: [], localOcrEnabled: true };
  @State private checks: PhoneCheck[] = [];
  @State private pixels: image.PixelMap | undefined = undefined;
  @State private screenText: string = '';
  @State private error: string = '';
  @State private busy: boolean = false;
  @State private logs: string[] = [];
  @State private bundle: string = '';
  @State private captureDelay: boolean = false;
  @State private accessibilityStatus: string = '';
  @State private tree: PhoneTree | undefined = undefined;
  @State private typeText: string = '';
  @State private toolsEnabled: boolean = false;
  private active: boolean = false;
  private generation: number = 0;
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage); }
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  aboutToAppear(): void { this.active = true; this.onBackHandler?.(() => { if (!this.busy) return false; this.generation++; this.busy = false; return true; }); void this.load(); }
  aboutToDisappear(): void { this.active = false; this.generation++; this.onBackHandler?.(undefined); void this.pixels?.release(); this.pixels = undefined; this.screenText = ''; }
  private async load(): Promise<void> {
    try { const policy = await loadPhonePolicy(this.context()), checks = await checkPhone();
      const status = await phoneAccessibilityStatus(this.context());
      if (this.active) { this.policy = policy; this.checks = checks; this.accessibilityStatus = status; } }
    catch { if (this.active) this.error = '手机控制状态未能读取'; }
    try { const state = await (new PhoneTaskClient(await this.getControl())).request('pending'); if (this.active) this.toolsEnabled = state['enabled'] === true; } catch {}
  }
  private async save(policy: PhonePolicy): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try { await savePhonePolicy(this.context(), policy); if (this.active) this.policy = policy; }
    catch { if (this.active) this.error = '手机控制策略未能保存'; }
    finally { if (this.active) this.busy = false; }
  }
  private async capture(): Promise<void> {
    if (this.busy) return;
    const version = ++this.generation; this.busy = true; this.error = '';
    try {
      const screen = await capturePhoneScreen(this.context(), this.policy.localOcrEnabled, this.captureDelay ? 3000 : 0, () => this.active && version === this.generation);
      if (!screen) return;
      const old = this.pixels; this.pixels = screen.pixels; this.screenText = screen.text; await old?.release();
      this.logs = [`${new Date().toLocaleTimeString()} · ${screen.width} × ${screen.height} · ${this.policy.localOcrEnabled ? '本机 OCR 已完成' : '截图已完成'}`].concat(this.logs).slice(0, 30);
      this.checks = this.checks.map((item: PhoneCheck): PhoneCheck => item.stage !== 'capture' ? item : { stage: 'capture', state: 'pass', observed: true, detail: `${screen.width} × ${screen.height}` });
    } catch (error) { if (this.active && version === this.generation) { this.error = (error as Error).message || '截图或文字识别失败'; this.logs = ['截屏检查失败'].concat(this.logs).slice(0, 30); } }
    finally { if (this.active && version === this.generation) this.busy = false; }
  }
  private setRule(rule: string): void {
    try { void this.save(updatePhoneRule(this.policy, this.bundle.trim(), rule)); } catch (error) { this.error = (error as Error).message; }
  }
  private async setTools(enabled: boolean): Promise<void> {
    if (this.busy) return; this.busy = true; this.error = '';
    try {
      if (enabled) {
        const choice = await this.getUIContext().getPromptAction().showDialog({ title: this.t('允许模型请求手机操作'),
          message: this.t('模型可以请求读取屏幕、点击、输入和滚动。每次操作仍由你确认，密码、系统页面及禁止名单保持拦截。'),
          buttons: [{ text: this.t('取消'), color: this.colors.muted }, { text: this.t('启用'), color: this.colors.primary }] });
        if (choice.index !== 1) return;
      }
      await (new PhoneTaskClient(await this.getControl())).request('enable', { 'enabled': enabled });
      if (this.active) this.toolsEnabled = enabled;
    } catch (error) { if (this.active) this.error = (error as Error).message; }
    finally { if (this.active) this.busy = false; }
  }
  private async accessible(action: string, nodeId: number = -1): Promise<void> {
    if (this.busy) return;
    const version = ++this.generation; this.busy = true; this.error = '';
    try {
      if (action !== 'screen') {
        const choice = await this.getUIContext().getPromptAction().showDialog({ title: this.t('确认手机操作'),
          message: this.t('将在 3 秒后对当前选定应用执行此操作，请切回目标应用。') + '\n' + (this.tree?.bundle || '') + ' · ' + action,
          buttons: [{ text: this.t('取消'), color: this.colors.muted }, { text: this.t('允许本次'), color: this.colors.primary }] });
        if (choice.index !== 1) return;
      }
      await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 3000); });
      if (!this.active || version !== this.generation) return;
      const command: PhoneAction = { action: action, screenId: this.tree?.id || '', nodeId: nodeId, text: action === 'setText' ? this.typeText : '', approved: action !== 'screen' };
      const value = await phoneAccessibilityCall(this.context(), command, () => this.active && version === this.generation);
      if (!this.active || version !== this.generation) return;
      if (action === 'screen') {
        const nodes: PhoneNode[] = array(value['nodes']).map((raw: Object | null): PhoneNode => {
          const node = object(raw); return { id: number(node['id'], -1), text: string(node['text']), type: string(node['type']), actions: array(node['actions']).map((item: Object | null) => string(item)), editable: node['editable'] === true, password: node['password'] === true, parent: number(node['parent'], -1), bounds: array(node['bounds']).map((item: Object | null) => number(item, 0)) };
        });
        this.tree = { id: string(value['id']), bundle: string(value['bundle']), nodes: nodes, truncated: value['truncated'] === true, createdAt: number(value['createdAt'], 0) };
        this.checks = this.checks.map((item: PhoneCheck): PhoneCheck => item.stage !== 'tree' ? item : { stage: 'tree', state: 'pass', observed: true, detail: this.tree?.bundle || '' });
      } else {
        this.tree = undefined; this.typeText = '';
        this.checks = this.checks.map((item: PhoneCheck): PhoneCheck => item.stage !== 'input' ? item : { stage: 'input', state: 'pass', observed: true, detail: '系统已确认接收节点操作；业务结果仍须读取屏幕核实' });
      }
      this.logs = [new Date().toLocaleTimeString() + ' · ' + action + ' · ' + this.t('系统已响应')].concat(this.logs).slice(0, 30);
    } catch (error) { if (this.active && version === this.generation) this.error = (error as Error).message; }
    finally { if (this.active && version === this.generation) this.busy = false; }
  }
  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) { Button(this.t('返回')).enabled(!this.busy).onClick(this.onClose); Text(this.t('手机控制')).fontSize(19).fontColor(this.colors.text).layoutWeight(1); }.width('100%').padding(12);
      Scroll() {
        Column({ space: 12 }) {
          Text(this.t(this.checks.some((item: PhoneCheck) => item.stage === 'input' && item.observed && item.state === 'pass') ? '已验证本机节点读取和操作' : '尚未完成设备操作验证')).fontSize(17).fontColor(this.colors.warning);
          Text(this.t('辅助接口在当前 SDK 中已被标记废弃，需在此设备实际启用和测试。授权截屏与本机文字识别可单独使用。')).fontSize(14).fontColor(this.colors.muted);
          Text(this.t(this.accessibilityStatus)).fontSize(13).fontColor(this.colors.muted);
          Row({ space: 8 }) {
            Text(this.t('允许模型请求手机操作')).fontColor(this.colors.text).layoutWeight(1);
            Toggle({ type: ToggleType.Switch, isOn: this.toolsEnabled }).enabled(!this.busy).onChange((value: boolean) => { void this.setTools(value); });
          }.width('100%');
          Button(this.t('刷新自检')).enabled(!this.busy).onClick(() => { void this.load(); });
          ForEach(this.checks, (item: PhoneCheck) => {
            Text(`${item.stage} · ${item.observed && item.state === 'pass' ? this.t('已实测') : item.state === 'not_run' ? this.t('未测试') : this.t('不可用')}\n${this.t(item.detail)}`).fontSize(13).fontColor(this.colors.muted).width('100%');
          }, (item: PhoneCheck) => JSON.stringify(item));
          Text(this.t('辅助节点与操作')).fontSize(17).fontColor(this.colors.text);
          Text(this.t('点击读取后有 3 秒切换到目标应用。每次写入都需确认，操作后请重新读取，系统响应不代表业务已完成。')).fontSize(12).fontColor(this.colors.muted);
          Button(this.t('3 秒后读取屏幕节点')).enabled(!this.busy).onClick(() => { void this.accessible('screen'); });
          if (this.tree) {
            Text(this.tree.bundle + (this.tree.truncated ? this.t(' · 已截断') : '')).fontSize(13).fontColor(this.colors.text);
            TextInput({ placeholder: this.t('向选定输入框填写的文字'), text: this.typeText }).enabled(!this.busy).onChange((text: string) => { this.typeText = text; });
            ForEach(this.tree.nodes.filter((item: PhoneNode) => item.text.length > 0 || item.actions.length > 0), (node: PhoneNode) => {
              Column({ space: 6 }) {
                Text('#' + node.id + ' ' + node.type + ' · ' + node.text).fontSize(13).fontColor(this.colors.text).width('100%');
                Row({ space: 6 }) {
                  if (node.actions.includes('click') && !node.password) Button(this.t('点击')).enabled(!this.busy).onClick(() => { void this.accessible('click', node.id); });
                  if (node.actions.includes('setText') && node.editable && !node.password) Button(this.t('填写')).enabled(!this.busy && this.typeText.length > 0).onClick(() => { void this.accessible('setText', node.id); });
                  if (node.actions.includes('scrollForward')) Button(this.t('向下滚动')).enabled(!this.busy).onClick(() => { void this.accessible('scrollForward', node.id); });
                  if (node.actions.includes('scrollBackward')) Button(this.t('向上滚动')).enabled(!this.busy).onClick(() => { void this.accessible('scrollBackward', node.id); });
                }
              }.width('100%').padding(8).backgroundColor(this.colors.surface).borderRadius(8);
            }, (node: PhoneNode) => `${this.tree?.id || ''}:${node.id}`);
          }
          Text(this.t('读取屏幕')).fontSize(17).fontColor(this.colors.text);
          Text(this.t('截图与识别只保留在当前页面内存。只有点击“放入聊天草稿”后，文字才会交给聊天页，仍需手动发送。')).fontSize(12).fontColor(this.colors.muted);
          Row({ space: 8 }) { Text(this.t('本机文字识别')).fontColor(this.colors.text).layoutWeight(1);
            Toggle({ type: ToggleType.Switch, isOn: this.policy.localOcrEnabled }).enabled(!this.busy).onChange((value: boolean) => { void this.save({ confirmMode: this.policy.confirmMode, denyPackages: this.policy.denyPackages, confirmEveryWritePackages: this.policy.confirmEveryWritePackages, localOcrEnabled: value }); });
          }.width('100%');
          Row({ space: 8 }) { Checkbox().select(this.captureDelay).enabled(!this.busy).onChange((value: boolean) => { this.captureDelay = value; }); Text(this.t('授权后等待 3 秒，可切换到目标页面')).fontSize(13).fontColor(this.colors.text); }
          Button(this.t(this.busy ? '正在读取…' : '授权截屏并读取')).enabled(!this.busy).onClick(() => { void this.capture(); });
          if (this.pixels) Image(this.pixels).width('100%').height(220).objectFit(ImageFit.Contain);
          if (this.screenText) {
            Text(this.screenText).fontSize(14).fontColor(this.colors.text).copyOption(CopyOptions.InApp).width('100%');
            Button(this.t('放入聊天草稿')).enabled(!this.busy).onClick(() => { this.onScreenText(this.screenText); });
          }
          Text(this.t('应用规则')).fontSize(17).fontColor(this.colors.text);
          Text(this.t('禁止规则在辅助服务执行前重新检查。节点操作目前每次都需确认。')).fontSize(12).fontColor(this.colors.muted);
          TextInput({ placeholder: this.t('应用包名，例如 com.example.app'), text: this.bundle }).enabled(!this.busy).onChange((value: string) => { this.bundle = value; });
          Row({ space: 6 }) { Button(this.t('禁止')).enabled(!this.busy).onClick(() => this.setRule('deny')); Button(this.t('每次确认')).enabled(!this.busy).onClick(() => this.setRule('confirm')); Button(this.t('恢复默认')).enabled(!this.busy).onClick(() => this.setRule('default')); }
          ForEach(this.policy.denyPackages.concat(this.policy.confirmEveryWritePackages), (name: string) => {
            Text(`${name} · ${this.t(phonePolicyRule(this.policy, name) === 'deny' ? '禁止' : '每次确认')}`).fontSize(13).fontColor(this.colors.muted).onClick(() => { this.bundle = name; });
          }, (name: string) => name);
          if (this.logs.length) { Text(this.t('动作日志')).fontSize(17).fontColor(this.colors.text); Text(this.logs.join('\n')).fontSize(12).fontColor(this.colors.muted); }
          if (this.error) Text(this.t(this.error)).fontSize(13).fontColor(this.colors.danger);
        }.width('100%').padding(14).alignItems(HorizontalAlign.Start);
      }.width('100%').layoutWeight(1);
    }.width('100%').height('100%').backgroundColor(this.colors.background);
  }
}
