import { ensurePrivateDirectory } from '../local/PrivateDirectory'
import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { display, screenshot } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { preferences } from '@kit.ArkData';
import { phoneBridgeRoot, phoneReadFile, phoneWriteFile } from './PhoneAccessibilityFiles';
import type { PhonePolicy, PhoneCheck } from './PhoneData';
import { phonePolicy, phoneChecks, phoneCaptureSupported } from './PhoneData';
import type { WireObject } from '../dsh/DshWire';
export interface PhoneScreen { pixels: image.PixelMap; text: string; width: number; height: number; }
export async function loadPhonePolicy(context: common.Context): Promise<PhonePolicy> {
  const existing = await phoneReadFile(phoneBridgeRoot(context) + '/policy.json', 32768);
  if (existing) return phonePolicy(existing);
  const store = await preferences.getPreferences(context, 'dsh-phone'); const raw = store.getSync('policy-v1', '{}');
  let policy: PhonePolicy;
  try { policy = phonePolicy(JSON.parse(typeof raw === 'string' ? raw : '{}') as WireObject); }
  catch { const empty: WireObject = {}; policy = phonePolicy(empty); }
  await savePhonePolicy(context, policy); return policy;
}
export async function savePhonePolicy(context: common.Context, policy: PhonePolicy): Promise<void> {
  await ensurePrivateDirectory(phoneBridgeRoot(context));
  const value: WireObject = { 'confirmMode': policy.confirmMode, 'denyPackages': policy.denyPackages,
    'confirmEveryWritePackages': policy.confirmEveryWritePackages, 'localOcrEnabled': policy.localOcrEnabled };
  await phoneWriteFile(phoneBridgeRoot(context) + '/policy.json', value);
}
export async function checkPhone(): Promise<PhoneCheck[]> {
  const screen = await display.getDefaultDisplay(); return phoneChecks(deviceInfo.deviceType, deviceInfo.sdkApiVersion, screen.width, screen.height);
}
export async function capturePhoneScreen(context: common.UIAbilityContext, ocr: boolean, delayMs: number, current: () => boolean): Promise<PhoneScreen | undefined> {
  await requestPhoneCapture(context);
  if (delayMs > 0) await new Promise<void>((resolve: () => void) => { setTimeout(resolve, Math.min(5000, delayMs)); });
  if (!current()) return undefined;
  return captureApprovedPhoneScreen(ocr, current);
}
export async function requestPhoneCapture(context: common.UIAbilityContext): Promise<void> {
  if (!phoneCaptureSupported(deviceInfo.deviceType, deviceInfo.sdkApiVersion)) throw new Error('此截屏接口需要手机 API 21 或更新系统');
  const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, ['ohos.permission.CUSTOM_SCREEN_CAPTURE']);
  if (result.authResults[0] !== 0) throw new Error('未获得屏幕截图授权');
}
async function captureApprovedPhoneScreen(ocr: boolean, current: () => boolean): Promise<PhoneScreen | undefined> {
  const source = await screenshot.capture(); let pixels: image.PixelMap | undefined;
  try {
    const info = await source.getImageInfo();
    if (info.size.width < 1 || info.size.height < 1 || info.size.width * info.size.height > 40000000) throw new Error('截图尺寸无效或过大');
    const packer = image.createImagePacker(); let bytes: ArrayBuffer;
    try { bytes = await packer.packing(source, { format: 'image/png', quality: 100 }); }
    finally { await packer.release(); }
    const decoded = image.createImageSource(bytes);
    try { pixels = await decoded.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 }); }
    finally { await decoded.release(); }
    const text = ocr ? (await textRecognition.recognizeText({ pixelMap: pixels })).value : '';
    if (!current()) return undefined;
    const screen: PhoneScreen = { pixels: pixels, text: text, width: info.size.width, height: info.size.height }; pixels = undefined; return screen;
  } finally { await source.release(); await pixels?.release(); }
}
