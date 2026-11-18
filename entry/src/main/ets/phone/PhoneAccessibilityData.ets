import { object, string, number } from '../dsh/DshWire';
import type { WireObject } from '../dsh/DshWire';
export interface PhoneNode { id: number; text: string; type: string; actions: string[]; editable: boolean; password: boolean; parent: number; bounds: number[]; }
export interface PhoneTree { id: string; bundle: string; nodes: PhoneNode[]; truncated: boolean; createdAt: number; }
export interface PhoneAction { action: string; screenId: string; nodeId: number; text: string; approved: boolean; x?: number; y?: number; x2?: number; y2?: number; duration?: number; width?: number; height?: number; }
export interface PhoneBridgeRequest { id: string; expires: number; command: PhoneAction; }
export function parsePhoneAction(value: Object): PhoneAction {
  const data = object(value), action = string(data['action']);
  if (!['screen', 'click', 'longClick', 'setText', 'scrollForward', 'scrollBackward', 'scrollLeft', 'scrollRight', 'back', 'home', 'recentTask', 'notificationCenter', 'gestureTap', 'gestureLong', 'gestureSwipe'].includes(action)) throw new Error('此手机操作尚不支持');
  const text = string(data['text']);
  if (text.length > 8192) throw new Error('输入文字过长');
  const command: PhoneAction = { action: action, screenId: string(data['screenId']), nodeId: number(data['nodeId'], -1), text: text, approved: data['approved'] === true };
  if (action.startsWith('gesture')) {
    command.width = number(data['width'], 0); command.height = number(data['height'], 0);
    command.x = number(data['x'], -1); command.y = number(data['y'], -1); command.x2 = number(data['x2'], command.x); command.y2 = number(data['y2'], command.y);
    command.duration = number(data['duration'], action === 'gestureLong' ? 800 : action === 'gestureSwipe' ? 400 : 100);
    if (command.width < 1 || command.height < 1 || command.width * command.height > 40000000 || command.duration < 100 || command.duration > 2000 ||
      ![command.x, command.x2].every((n: number) => Number.isInteger(n) && n >= 0 && n < command.width!) || ![command.y, command.y2].every((n: number) => Number.isInteger(n) && n >= 0 && n < command.height!)) throw new Error('手势坐标或时长无效');
  }
  return command;
}
export function phoneWriteAllowed(bundle: string, denied: string[], password: boolean, approved: boolean): void {
  if (denied.includes(bundle)) throw new Error('应用名单禁止操作此应用');
  if (bundle === 'com.dshgo.harmony' || /(^|\.)(settings|systemui|permissioncontroller|packageinstaller|securitycenter)(\.|$)/i.test(bundle)) throw new Error('系统权限页面和 DSH Go 自身交由你操作');
  if (password) throw new Error('密码和验证码输入交由你操作');
  if (!approved) throw new Error('此操作需要你确认');
}
export function phoneRequestValid(value: Object, now: number): PhoneBridgeRequest {
  const data: WireObject = object(value), id = string(data['id']), expires = number(data['expires'], 0);
  if (!/^[a-f0-9-]{36}$/.test(id) || expires <= now || expires > now + 31000) throw new Error('手机操作已过期');
  return { id: id, expires: expires, command: parsePhoneAction(object(data['command'])) };
}
