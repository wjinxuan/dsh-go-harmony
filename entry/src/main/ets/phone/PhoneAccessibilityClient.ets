import { ensurePrivateDirectory } from '../local/PrivateDirectory'
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { accessibility } from '@kit.AccessibilityKit';
import { object, string, number } from '../dsh/DshWire';
import type { WireObject } from '../dsh/DshWire';
import type { PhoneAction } from './PhoneAccessibilityData';
import { phoneBridgeRoot, phoneReadFile, phoneWriteFile, phoneRemoveFile } from './PhoneAccessibilityFiles';
export async function phoneAccessibilityStatus(context: common.Context): Promise<string> {
  const list = await accessibility.getAccessibilityExtensionList('all', 'enable');
  const enabled = list.some((entry: accessibility.AccessibilityAbilityInfo) => entry.bundleName === 'com.dshgo.harmony' && entry.name === 'PhoneAccessibilityAbility');
  if (!enabled) return '无障碍服务未连接。若系统提供已安装服务入口，请先启用；否则可使用单次截图和文字识别。';
  const state = await phoneReadFile(phoneBridgeRoot(context) + '/ready.json', 4096);
  return state && Date.now() - number(state['seenAt'], 0) < 3000 ? '辅助服务已连接；读取屏幕后才会验证节点能力' : '系统已启用扩展，但尚未收到实际服务连接';
}
export async function phoneAccessibilityCall(context: common.Context, command: PhoneAction, current: () => boolean): Promise<WireObject> {
  const root = phoneBridgeRoot(context), id = util.generateRandomUUID();
  await ensurePrivateDirectory(root);
  const request = root + '/' + id + '.request', response = root + '/' + id + '.response';
  await phoneWriteFile(request, { 'id': id, 'expires': Date.now() + 30000, 'command': command });
  try {
    for (let attempt = 0; attempt < 150; attempt++) {
      if (!current()) throw new Error('手机操作已取消');
      const value = await phoneReadFile(response);
      if (value) { if (typeof value['error'] === 'string') throw new Error(string(value['error'])); return object(value['value']); }
      await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 200); });
    }
    throw new Error('辅助服务未响应，请检查系统设置与设备支持情况');
  } finally { await phoneRemoveFile(request); await phoneRemoveFile(response); }
}
