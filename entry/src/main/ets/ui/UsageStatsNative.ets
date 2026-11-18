import { common, bundleManager } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { util } from '@kit.ArkTS'
import { deviceInfo } from '@kit.BasicServicesKit'
import { http } from '@kit.NetworkKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { WireObject } from '../dsh/DshWire'
import { UsageStats, UsageDriver, UsageDevice, usageMaker } from './UsageStatsData'
import { settingsLanguage } from './SettingsLocale'
export function createUsageStats(context:common.UIAbilityContext,language:()=>string):UsageStats {
  const driver:UsageDriver={
    load:async():Promise<string>=>{const store=await preferences.getPreferences(context,'dsh-usage');return store.getSync('ledger-v1','{}') as string},
    save:async(value:string):Promise<void>=>{const store=await preferences.getPreferences(context,'dsh-usage');store.putSync('ledger-v1',value);await store.flush()},
    post:async(body:WireObject):Promise<number>=>{const request=http.createHttp();try{const response=await request.request('https://go.dshtui.com/api/usage/v1',{
      method:http.RequestMethod.POST,header:{'Content-Type':'application/json','User-Agent':'dsh-go'},extraData:JSON.stringify(body),usingCache:false,maxRedirects:0,connectTimeout:10000,readTimeout:10000,maxLimit:65536});return response.responseCode}finally{request.destroy()}},
    random:():string=>new util.Base64Helper().encodeToStringSync(cryptoFramework.createRandom().generateRandomSync(16).data).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,''),
    device:async():Promise<UsageDevice>=>{const bundle=await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      return {app:bundle.versionName,build:bundle.versionCode,sdk:deviceInfo.sdkApiVersion,abi:deviceInfo.abiList.split(',')[0],maker:usageMaker(deviceInfo.manufacture),model:usageMaker(deviceInfo.productModel),rom:usageMaker(deviceInfo.osFullName)}},
    language:():string=>settingsLanguage(language()).toLowerCase().startsWith('zh')?'zh':'en',now:():number=>Date.now()
  }
  return new UsageStats(driver,!context.applicationInfo.debug)
}
