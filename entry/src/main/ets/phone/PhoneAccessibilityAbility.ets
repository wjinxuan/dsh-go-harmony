import { ensurePrivateDirectory } from '../local/PrivateDirectory'
import { AccessibilityExtensionAbility, AccessibilityElement, GesturePath, GesturePoint } from '@kit.AccessibilityKit';
import { display } from '@kit.ArkUI';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { number } from '../dsh/DshWire';
import type { WireObject } from '../dsh/DshWire';
import { phoneRequestValid, phoneWriteAllowed } from './PhoneAccessibilityData';
import type { PhoneTree, PhoneNode } from './PhoneAccessibilityData';
import { phoneBridgeRoot, phoneReadFile, phoneWriteFile, phoneRemoveFile } from './PhoneAccessibilityFiles';
import { phonePolicy } from './PhoneData';

// The SDK still exposes this legacy extension. Its APIs are deprecated since 12;
// only actual callbacks/results can establish availability on a particular device.
export default class PhoneAccessibilityAbility extends AccessibilityExtensionAbility {
  private timer: number = -1;
  private active: boolean = false;
  private working: boolean = false;
  private seenAt: number = 0;
  private tree: PhoneTree = { id: '', bundle: '', nodes: [], truncated: false, createdAt: 0 };
  private elements: AccessibilityElement[] = [];
  onConnect(): void { this.active = true; void this.start(); }
  onDisconnect(): void { this.active = false; if (this.timer >= 0) clearInterval(this.timer); this.elements = []; void phoneRemoveFile(phoneBridgeRoot(this.context) + '/ready.json'); }
  private async start(): Promise<void> {
    await ensurePrivateDirectory(phoneBridgeRoot(this.context));
    if (!this.active) return;
    this.timer = setInterval(() => { void this.tick(); }, 200); void this.tick();
  }
  private async tick(): Promise<void> {
    if (!this.active || this.working) return;
    this.working = true;
    const root = phoneBridgeRoot(this.context);
    try {
      if (Date.now() - this.seenAt > 1000) { this.seenAt = Date.now(); await phoneWriteFile(root + '/ready.json', { 'seenAt': this.seenAt }); }
      const files = await fs.listFile(root);
      for (const name of files.filter((item: string) => /^[a-f0-9-]{36}\.response$/.test(item)).slice(0, 16)) {
        const path = root + '/' + name, response = await phoneReadFile(path);
        if (response && number(response['expires'], 0) <= Date.now()) await phoneRemoveFile(path);
      }
      const names = files.filter((name: string) => /^[a-f0-9-]{36}\.request$/.test(name)).slice(0, 16);
      for (const name of names) {
        if (!this.active) break;
        const path = root + '/' + name, reply = root + '/' + name.replace('.request', '.response');
        try {
          const raw = await phoneReadFile(path, 32768); if (!raw) continue;
          const request = phoneRequestValid(raw, Date.now());
          if (name !== request.id + '.request') throw new Error('手机操作标识不一致');
          const storedPolicy = await phoneReadFile(root + '/policy.json', 32768);
          if (!storedPolicy) throw new Error('请先打开手机控制页面完成本机规则设置');
          const policy = phonePolicy(storedPolicy), current = await this.context.getWindowRootElement();
          const bundle = await current.attributeValue('bundleName');
          if (policy.denyPackages.includes(bundle)) throw new Error('应用名单禁止读取或操作此应用');
          let result: Object;
          if (request.command.action === 'screen') result = await this.capture(current, bundle);
          else {
            const command = request.command;
            if (command.screenId !== this.tree.id || bundle !== this.tree.bundle || Date.now() - this.tree.createdAt > 30000) throw new Error('屏幕已变化或过期，请重新读取');
            const previous = this.tree;
            const fresh = await this.capture(current, bundle);
            if (fresh.truncated || JSON.stringify(fresh.nodes) !== JSON.stringify(previous.nodes)) throw new Error('屏幕节点已变化，请重新读取');
            const gesture = command.action.startsWith('gesture');
            const horizontal = command.action === 'scrollLeft' || command.action === 'scrollRight';
            const global = gesture || ['back', 'home', 'recentTask', 'notificationCenter'].includes(command.action);
            const element = global ? current : this.elements[command.nodeId], node = this.tree.nodes[global ? 0 : command.nodeId];
            if (!element || !node || (!global && !(horizontal ? node.actions.some((action: string) => action === 'scrollForward' || action === 'scrollBackward') : node.actions.includes(command.action)))) throw new Error('节点不支持此操作，请重新读取');
            phoneWriteAllowed(bundle, policy.denyPackages, gesture ? fresh.nodes.some((item: PhoneNode) => item.password) : node.password, command.approved);
            if ((gesture || command.action === 'setText') && fresh.nodes.some((item: PhoneNode) => /验证码|付款|支付密码|verification code|one.time.password|\botp\b|payment password/i.test(item.text))) throw new Error('验证码和支付页面交由你操作');
            if (!await fs.access(path) || !this.active || Date.now() >= request.expires) throw new Error('手机操作已取消或过期');
            if (gesture) {
              const actual = await display.getDefaultDisplay();
              if (actual.width !== command.width || actual.height !== command.height) throw new Error('屏幕尺寸或旋转已变化，请重新截图');
              if (!await fs.access(path) || !this.active || Date.now() >= request.expires) throw new Error('手机操作已取消或过期');
              const stroke = new GesturePath(command.duration!);
              stroke.points = [new GesturePoint(command.x!, command.y!)];
              if (command.action === 'gestureSwipe') stroke.points.push(new GesturePoint(command.x2!, command.y2!));
              await this.context.injectGesture(stroke);
            } else if (horizontal) {
              const actual = await display.getDefaultDisplay(), box = node.bounds;
              const left = Math.max(0, box[0]), right = Math.min(actual.width - 1, box[0] + box[2]), top = Math.max(0, box[1]), bottom = Math.min(actual.height - 1, box[1] + box[3]);
              if (right - left < 20 || bottom - top < 20) throw new Error('列表可见区域不足，不能安全滚动');
              if (!await fs.access(path) || !this.active || Date.now() >= request.expires) throw new Error('手机操作已取消或过期');
              const low = Math.round(left + (right - left) * 0.25), high = Math.round(left + (right - left) * 0.75), y = Math.round((top + bottom) / 2);
              const stroke = new GesturePath(400);
              stroke.points = [new GesturePoint(command.action === 'scrollLeft' ? high : low, y), new GesturePoint(command.action === 'scrollLeft' ? low : high, y)];
              await this.context.injectGesture(stroke);
            } else {
              const params: Record<string, string> = {}; if (command.action === 'setText') params['setText'] = command.text;
              await element.performAction(command.action, params);
            }
            // API acknowledgement is not proof that the requested business action succeeded.
            const acknowledged: WireObject = { 'acknowledged': true, 'action': command.action, 'bundle': bundle };
            result = acknowledged;
            this.tree.id = ''; this.elements = [];
          }
          if (this.active && await fs.access(path)) await phoneWriteFile(reply, { 'expires': Date.now() + 30000, 'value': result });
        } catch (error) {
          if (this.active && await fs.access(path)) await phoneWriteFile(reply, { 'expires': Date.now() + 30000, 'error': (error as Error).message || '系统未能完成辅助操作' });
        } finally { await phoneRemoveFile(path); }
      }
    } catch { /* An unavailable OS service is reported by the request timeout; never mark ready. */ }
    finally { this.working = false; }
  }
  private async capture(root: AccessibilityElement, bundle: string): Promise<PhoneTree> {
    const queue: AccessibilityElement[] = [root], parents: number[] = [-1], elements: AccessibilityElement[] = [], nodes: PhoneNode[] = [];
    const deadline = Date.now() + 5000;
    while (queue.length && nodes.length < 128 && Date.now() < deadline && this.active) {
      const element = queue.shift(), parent = parents.shift() ?? -1; if (!element) break;
      const password = await element.attributeValue('isPassword'), content = password ? ['••••'] : await element.attributeValue('contents');
      const rect = await element.attributeValue('rect');
      const item: PhoneNode = { id: nodes.length, text: content.join(' ').slice(0, 1000), type: await element.attributeValue('componentType'),
        actions: await element.actionNames(), editable: await element.attributeValue('editable'), password: password, parent: parent, bounds: [rect.left, rect.top, rect.width, rect.height] };
      nodes.push(item); elements.push(element);
      const children = await element.attributeValue('children'); const admitted = children.slice(0, Math.max(0, 256 - queue.length)); queue.push(...admitted); parents.push(...admitted.map(() => item.id));
    }
    const tree: PhoneTree = { id: util.generateRandomUUID(), bundle: bundle, nodes: nodes, truncated: queue.length > 0, createdAt: Date.now() };
    this.tree = tree; this.elements = elements; return tree;
  }
}
