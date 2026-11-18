import { object, array, string, number } from '../dsh/DshWire';
import type { WireObject } from '../dsh/DshWire';
import type { PhoneAction } from './PhoneAccessibilityData';
export type PhoneNodeCall = (command: PhoneAction) => Promise<WireObject>;
export async function collectPhoneList(args: WireObject, call: PhoneNodeCall, current: () => boolean): Promise<WireObject> {
  let screen = object(args['initial']); const listId = number(args['list'], -1), limit = number(args['max_pages'], 10), until = string(args['until']);
  if (!current()) throw new Error('手机操作已取消或过期');
  const verify: PhoneAction = { action: 'screen', screenId: '', nodeId: -1, text: '', approved: false };
  const live = await call(verify);
  if (live['bundle'] !== screen['bundle'] || JSON.stringify(live['nodes']) !== JSON.stringify(screen['nodes'])) throw new Error('目标应用或列表已变化，请重新读取');
  screen = live;
  const target = array(screen['nodes']).map((raw: Object): WireObject => object(raw)).find((node: WireObject) => number(node['id'], -2) === listId);
  if (!target) throw new Error('列表节点已失效');
  const bounds = JSON.stringify(target['bounds']), type = string(target['type']), seen: string[] = [];
  let pages = 0, reason = 'page-limit';
  for (let page = 0; page < limit; page++) {
    if (!current()) throw new Error('手机操作已取消或过期');
    const nodes = array(screen['nodes']).map((raw: Object): WireObject => object(raw)), list = nodes.find((node: WireObject) => string(node['type']) === type && JSON.stringify(node['bounds']) === bounds);
    if (!list || screen['truncated'] === true) { reason = 'list-changed-or-truncated'; break; }
    const ids: number[] = [number(list['id'], -1)]; let added = 0;
    for (const node of nodes) {
      if (!ids.includes(number(node['parent'], -2))) continue;
      ids.push(number(node['id'], -1));
      const text = string(node['text']).trim();
      if (text && !seen.includes(text)) { seen.push(text); added++; }
    }
    pages++;
    if (seen.some((text: string) => !!until && text.includes(until))) { reason = 'matched'; break; }
    if (page > 0 && added === 0) { reason = 'no-new-items'; break; }
    if (seen.length >= 2000 || seen.join('\n').length > 100000) { reason = 'size-limit'; break; }
    if (page + 1 >= limit) break;
    const scroll: PhoneAction = { action: 'scrollForward', screenId: string(screen['id']), nodeId: number(list['id'], -1), text: '', approved: true };
    await call(scroll);
    await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 250); });
    const read: PhoneAction = { action: 'screen', screenId: '', nodeId: -1, text: '', approved: false };
    const next = await call(read); if (next['bundle'] !== screen['bundle']) throw new Error('目标应用已变化，已停止收集'); screen = next;
  }
  return { 'items': seen, 'pages': pages, 'reason': reason, 'complete': reason === 'matched' || reason === 'no-new-items', 'screen': screen };
}
