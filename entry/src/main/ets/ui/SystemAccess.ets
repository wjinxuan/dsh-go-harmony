import { phoneCaptureSupported } from '../phone/PhoneData'
import { abilityAccessCtrl, common, bundleManager } from '@kit.AbilityKit'
import { notificationManager } from '@kit.NotificationKit'
import { deviceInfo } from '@kit.BasicServicesKit'

export interface SystemAccessState { microphone: string; notifications: string; capture: boolean }
export async function systemAccess(context: common.UIAbilityContext): Promise<SystemAccessState> {
  let microphone = 'unknown', notifications = 'unknown'
  try { microphone = abilityAccessCtrl.createAtManager().checkAccessTokenSync(context.applicationInfo.accessTokenId, 'ohos.permission.MICROPHONE') === 0 ? 'granted' : 'denied' } catch { /* Show unknown rather than claiming access. */ }
  try { notifications = await notificationManager.isNotificationEnabled() ? 'granted' : 'denied' } catch { /* Optional service. */ }
  return { microphone: microphone, notifications: notifications,
    capture: phoneCaptureSupported(deviceInfo.deviceType, deviceInfo.sdkApiVersion) }
}
export async function openApplicationSettings(context: common.UIAbilityContext): Promise<void> {
  const bundle = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
  await context.startAbility({ bundleName: 'com.huawei.hmos.settings', abilityName: 'com.huawei.hmos.settings.MainAbility',
    uri: 'application_info_entry', parameters: { 'pushParams': bundle.name } })
}
export async function requestSystemAccess(context: common.UIAbilityContext, kind: string): Promise<void> {
  if (kind === 'microphone') {
    const manager = abilityAccessCtrl.createAtManager()
    const result = await manager.requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE'])
    if (result.authResults[0] !== 0 && result.dialogShownResults?.[0] === false) await manager.requestPermissionOnSetting(context, ['ohos.permission.MICROPHONE'])
  } else if (kind === 'notifications') {
    if (await notificationManager.isNotificationEnabled()) await notificationManager.openNotificationSettings(context)
    else await notificationManager.requestEnableNotification(context)
  } else if (kind === 'settings') await openApplicationSettings(context)
  else throw new Error('未知系统权限入口')
}
