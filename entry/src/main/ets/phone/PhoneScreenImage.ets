import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { string } from '../dsh/DshWire';
import type { WireObject } from '../dsh/DshWire';
import { capturePhoneScreen } from './PhoneControl';
import { phoneAccessibilityCall } from './PhoneAccessibilityClient';
import type { PhoneAction } from './PhoneAccessibilityData';
export async function attachPhoneScreenImage(context: common.UIAbilityContext, before: WireObject, current: () => boolean): Promise<WireObject> {
  const shot = await capturePhoneScreen(context, false, 3000, current);
  if (!shot) throw new Error('手机截图已取消');
  try {
    const read: PhoneAction = { action: 'screen', screenId: '', nodeId: -1, text: '', approved: false };
    const after = await phoneAccessibilityCall(context, read, current);
    if (string(after['bundle']) !== string(before['bundle']) || JSON.stringify(after['nodes']) !== JSON.stringify(before['nodes']) || after['truncated'] === true) throw new Error('截图期间屏幕发生变化，请重新读取');
    const scale = Math.min(1, 1280 / Math.max(shot.width, shot.height));
    if (scale < 1) await shot.pixels.scale(scale, scale);
    let info = await shot.pixels.getImageInfo(); const packer = image.createImagePacker(); let bytes: ArrayBuffer;
    try {
      bytes = await packer.packing(shot.pixels, { format: 'image/png', quality: 100 });
      for (let attempt = 0; bytes.byteLength > 1500000 && attempt < 3; attempt++) {
        if (!current()) throw new Error('手机截图已取消');
        await shot.pixels.scale(0.5, 0.5); info = await shot.pixels.getImageInfo();
        bytes = await packer.packing(shot.pixels, { format: 'image/png', quality: 100 });
      }
    } finally { await packer.release(); }
    if (bytes.byteLength > 1500000) throw new Error('截图超过传输大小限制');
    if (!current()) throw new Error('手机截图已取消');
    const picture: WireObject = { 'mediaType': 'image/png', 'base64': new util.Base64Helper().encodeToStringSync(new Uint8Array(bytes)),
      'width': info.size.width, 'height': info.size.height, 'viewportWidth': shot.width, 'viewportHeight': shot.height };
    after['image'] = picture; after['observation'] = after['id']; return after;
  } finally { await shot.pixels.release(); }
}
