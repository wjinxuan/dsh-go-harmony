import { common } from '@kit.AbilityKit';
import type { Want } from '@kit.AbilityKit';
import { call } from '@kit.TelephonyKit';
import { calendarManager } from '@kit.CalendarKit';
import { systemShare } from '@kit.ShareKit';
import { settings, deviceInfo } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { string, number } from '../dsh/DshWire';
import type { WireObject } from '../dsh/DshWire';
export async function executePhoneIntent(context: common.UIAbilityContext, args: WireObject, current: () => boolean): Promise<WireObject> {
  if (!current()) throw new Error('手机操作已取消或过期');
  const kind = string(args['kind']);
  if (kind === 'dial') {
    const phone = string(args['number']); if (!/^\+?[0-9 ()-]{1,32}$/.test(phone)) throw new Error('电话号码无效');
    await call.makeCall(phone);
  } else if (kind === 'calendar') {
    const start = new Date(string(args['begin'])).getTime(), end = args['end'] ? new Date(string(args['end'])).getTime() : start + (args['all_day'] === true ? 86400000 : 3600000);
    if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start || !string(args['title']).trim()) throw new Error('日程时间或标题无效');
    const event: calendarManager.Event = { type: calendarManager.EventType.NORMAL, title: string(args['title']).slice(0, 5000), startTime: start, endTime: end,
      isAllDay: args['all_day'] === true, location: { location: string(args['location']).slice(0, 5000) }, description: string(args['description']).slice(0, 5000) };
    const id = await calendarManager.getCalendarManager(context).editEvent(event);
    return { 'created': id > 0, 'cancelled': id < 0, 'eventId': id };
  } else if (kind === 'share') {
    if (args['app']) throw new Error('鸿蒙分享目标由系统分享面板选择，请省略 Android 应用包名');
    const text = string(args['text']); if (!text || text.length > 8192) throw new Error('分享文本为空或过长');
    const data = new systemShare.SharedData({ utd: 'general.plain-text', content: text });
    await new systemShare.ShareController(data).show(context, { previewMode: systemShare.SharePreviewMode.DEFAULT });
  } else if (kind === 'navigate') {
    const latitude = number(args['lat'], NaN), longitude = number(args['lng'], NaN), destination = string(args['destination']);
    const params: Record<string, Object> = {};
    if (Number.isFinite(latitude) && Number.isFinite(longitude) && Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180) {
      params['sceneType'] = 1; params['destinationLatitude'] = latitude; params['destinationLongitude'] = longitude;
      params['vehicleType'] = args['mode'] === 'walk' ? 1 : args['mode'] === 'ride' ? 2 : args['mode'] === 'transit' ? 3 : 0;
      if (destination) params['destinationName'] = destination.slice(0, 1000);
    } else if (destination && args['lat'] === undefined && args['lng'] === undefined) { params['sceneType'] = 3; params['destinationName'] = destination.slice(0, 1000); }
    else throw new Error('导航需要有效 GCJ-02 坐标或目的地名称');
    // The system lets the user choose a compatible map app; Android map package names are not reused.
    await new Promise<void>((resolve: () => void, reject: (error: Error) => void) => {
      const callback: common.AbilityStartCallback = { onError: (code: number, name: string, message: string) => reject(new Error(name + ': ' + message + ' (' + code + ')')), onResult: () => resolve() };
      context.startAbilityByType('navigation', params, callback).catch((error: Error) => reject(error));
    });
  } else if (kind === 'sms_draft') {
    const phone = string(args['number']), text = string(args['text']);
    if ((phone && !/^[1-9][0-9]{0,14}$/.test(phone)) || !text || text.length > 8192) throw new Error('短信草稿需有效数字号码和不超过 8192 字的正文');
    const contact: WireObject = { 'contactsName': '', 'telephone': Number(phone) };
    const want: Want = { bundleName: 'com.ohos.mms', abilityName: 'com.ohos.mms.MainAbility', parameters: {
      'contactObjects': JSON.stringify(phone ? [contact] : []), 'pageFlag': 'conversation', 'content': text } };
    await context.startAbility(want);
  } else if (kind === 'settings' && args['page'] === 'wifi') {
    if (!await settings.openNetworkManagerSettings(context)) throw new Error('系统未打开 WLAN 设置');
  } else if (kind === 'settings' && args['page'] === 'app_notifications' && (!args['app'] || args['app'] === 'com.dshgo.harmony')) {
    await notificationManager.openNotificationSettings(context);
  } else if (kind === 'settings' && args['page'] === 'nfc') {
    if (deviceInfo.sdkApiVersion < 24) throw new Error('打开 NFC 设置需要 API 24 或更新系统');
    settings.openNfcSettingsPage(context);
  } else if (kind === 'settings' && ['mobile_network', 'display', 'sound'].includes(string(args['page']))) {
    if (deviceInfo.sdkApiVersion < 26) throw new Error('此系统设置入口需要 API 26 或更新系统');
    if (args['page'] === 'mobile_network') settings.openMobileNetworkSettingsPage(context);
    else if (args['page'] === 'display') settings.openDisplaySettingsPage(context);
    else settings.openSoundSettingsPage(context);
  } else throw new Error('此 Android 设置或时钟意图没有当前普通鸿蒙应用可调用的等价接口，请交由用户操作');
  return { 'launched': true, 'businessResult': 'unknown' };
}
