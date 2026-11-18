import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { object, string, WireObject } from '../dsh/DshWire'
import { archivePath } from '../pets/PrivateArchive'
import { privateBytes, privateSha256, writePrivate, removePrivate } from '../pets/ArchiveFiles'
import { strictPackJson } from '../pets/StrictPackJson'
import { companionAdapterCheck, companionAdapterEmpty } from './CompanionAdapt'
export interface CompanionAdaptPreferences {consent:boolean;auto:boolean}
export async function companionAdaptPreferences(context:common.Context):Promise<CompanionAdaptPreferences>{const prefs=await preferences.getPreferences(context,'dsh-companion');return{consent:prefs.getSync('adapt-consent',false)===true,auto:prefs.getSync('adapt-auto',true)!==false}}
export async function saveCompanionAdaptPreferences(context:common.Context,value:CompanionAdaptPreferences):Promise<void>{const prefs=await preferences.getPreferences(context,'dsh-companion');prefs.putSync('adapt-consent',value.consent);prefs.putSync('adapt-auto',value.auto);await prefs.flush()}
export async function companionFingerprint(context:common.Context,probe:WireObject):Promise<string>{const moc=string(probe['moc']);if(!moc||!archivePath(moc)||!moc.endsWith('.moc3'))throw new Error('角色模型指纹不可用');return privateSha256(await privateBytes(context.filesDir+'/companion/pack/character/'+moc,67108864))}
export async function companionAdaptTried(context:common.Context,fingerprint:string,mark:boolean=false):Promise<boolean>{if(!/^[a-f0-9]{64}$/.test(fingerprint))throw new Error('角色模型指纹无效');const prefs=await preferences.getPreferences(context,'dsh-companion'),key='adapt-tried-'+fingerprint;if(mark){prefs.putSync(key,true);await prefs.flush();return true}return prefs.getSync(key,false)===true}
export async function readCompanionAdapter(context:common.Context):Promise<WireObject|undefined>{try{return object(strictPackJson(await privateBytes(context.filesDir+'/companion/pack/character/adapter.json',262144)))}catch{return undefined}}
export async function writeCompanionAdapter(context:common.Context,probe:WireObject,answer:WireObject,expectedFingerprint:string):Promise<void>{const current=await companionFingerprint(context,probe);if(current!==expectedFingerprint)throw new Error('角色模型已更换，请重新适配');const checked=companionAdapterCheck(answer,probe).adapter;if(companionAdapterEmpty(checked))throw new Error('模型未返回可用适配');checked['moc']=current;const target=context.filesDir+'/companion/pack/character/adapter.json',temporary=target+'.'+util.generateRandomUUID()+'.part';try{await writePrivate(temporary,new util.TextEncoder().encodeInto(JSON.stringify(checked)));if(await companionFingerprint(context,probe)!==current)throw new Error('角色模型已更换，请重新适配');await fs.rename(temporary,target)}finally{await removePrivate(temporary)}}
export async function removeCompanionAdapter(context:common.Context):Promise<void>{await removePrivate(context.filesDir+'/companion/pack/character/adapter.json')}
