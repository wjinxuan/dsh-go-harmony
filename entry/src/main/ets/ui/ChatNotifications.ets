import { localizedSettingsText } from './SettingsLocale'
import { common, bundleManager, wantAgent } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { notificationManager } from '@kit.NotificationKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { backgroundCompletion, backgroundCompletionLog } from './BackgroundCompletion'
import { DshClient, DshSubscription } from '../dsh/DshClient'
import { array, string, WireObject } from '../dsh/DshWire'
import { ChatNotification, NotificationPreferences, NotificationDeduper, notificationPreferences, notificationAllowed, requestNotification, turnNotification } from './NotificationData'

export async function loadNotificationPreferences(context:common.Context):Promise<NotificationPreferences> {
  const store=await preferences.getPreferences(context,'dsh-notifications')
  try{return notificationPreferences(JSON.parse(store.getSync('preferences','{}') as string))}catch{return notificationPreferences()}
}
export async function saveNotificationPreferences(context:common.Context,value:NotificationPreferences):Promise<void> {
  const store=await preferences.getPreferences(context,'dsh-notifications');store.putSync('preferences',JSON.stringify(value));await store.flush()
}
function notificationId(key:string):number {let hash=0;for(let i=0;i<key.length;i++)hash=(hash*31+key.charCodeAt(i))|0;return hash&0x7fffffff}
export class ChatNotifications {
  private client:DshClient
  private context:common.UIAbilityContext
  private scope:string
  private visible:()=>string
  private foreground:()=>boolean
  private banner:(item:ChatNotification)=>void
  private botSessions:Set<string>=new Set()
  setBotSessions(sessions:string[]):void{this.botSessions=new Set(sessions)}
  async bot(notice:WireObject,caughtUp:boolean):Promise<void>{
    if(caughtUp||!this.current()||!this.loaded)return
    const room=string(notice['roomId']),bot=string(notice['botId']),id=room||bot,kind=string(notice['kind'])
    if(!id||!['message','group','done','question','view','approval'].includes(kind))return
    const alertKind=kind==='approval'?'approval':kind==='question'||kind==='view'?'question':'done'
    const item:ChatNotification={kind:alertKind,sessionId:id,key:'dsbot-'+String(notice['seq']),text:alertKind==='approval'?'DS Bot 有操作等待确认':alertKind==='question'?'DS Bot 有问题等待回答':'DS Bot 有新消息',destination:'ds-bot',botId:id,botRoom:!!room}
    await this.show(item)
  }
  private running:Map<string,boolean>=new Map()
  private deduper:NotificationDeduper=new NotificationDeduper()
  private subscription?:DshSubscription
  private identity:number
  private active:boolean=true
  private prefs:NotificationPreferences=notificationPreferences()
  private loaded:boolean=false
  private preferenceVersion:number=0
  private completionOwner:number|undefined=undefined
  private finishing:number=0
  constructor(client:DshClient,context:common.UIAbilityContext,scope:string,visible:()=>string,foreground:()=>boolean,banner:(item:ChatNotification)=>void){
    this.client=client;this.context=context;this.scope=scope;this.visible=visible;this.foreground=foreground;this.banner=banner;this.identity=client.connectionIdentity()
  }
  async start():Promise<void>{
    const version=this.preferenceVersion
    const prefs=await loadNotificationPreferences(this.context)
    if(!this.current())return
    if(version===this.preferenceVersion)this.prefs=prefs
    this.loaded=true;this.completionOwner=backgroundCompletion.attach();this.subscription=this.client.onHostEvent((event:WireObject)=>{void this.event(event).catch(()=>{})})
  }
  updatePreferences(value:NotificationPreferences):void{this.preferenceVersion++;this.prefs=value}
  stop():void{this.active=false;this.subscription?.();this.subscription=undefined;if(this.completionOwner!==undefined)backgroundCompletion.detach(this.completionOwner);this.completionOwner=undefined}
  private current():boolean{return this.active&&this.identity===this.client.connectionIdentity()}
  private completionChanged():void{if(this.current()&&this.completionOwner!==undefined)backgroundCompletion.update(this.completionOwner,this.finishing>0||Array.from(this.running.values()).some((running:boolean)=>running))}
  private async event(event:WireObject):Promise<void>{
    if(!this.current()||!this.loaded)return
    if(event['type']==='cancel'){await notificationManager.cancel(notificationId(this.scope+'/'+string(event['eventId']))).catch(()=>{});return}
    const request=requestNotification(event)
    if(request){if(!this.botSessions.has(request.sessionId))await this.show(request);return}
    if(event['type']!=='emit'||event['event']!=='api-session/status')return
    const args=array(event['args']),sessionId=string(args[0]);if(!sessionId||this.botSessions.has(sessionId)||typeof args[1]!=='boolean')return
    const before=this.running.get(sessionId);this.running.set(sessionId,args[1]===true)
    if(args[1]===true||before!==true){this.completionChanged();return}
    this.finishing++;this.completionChanged()
    try{const address:WireObject={'kind':'session','sessionId':sessionId}
      const payload:WireObject={'address':address,'maxMessages':1}
      const request:WireObject={'request':payload}
      const page=await this.client.request('session/page',request)
      if(!this.current()||this.running.get(sessionId)===true)return
      const alert=turnNotification(sessionId,page);if(alert)await this.show(alert)
    }catch(error){backgroundCompletionLog('completion-read-failed',(error as BusinessError)?.code||0)}finally{this.finishing--;this.completionChanged()}
  }
  private async show(item:ChatNotification):Promise<void>{
    if(!this.current()||!this.deduper.claim(this.scope,item)||!notificationAllowed(this.prefs,item.kind))return
    if(this.foreground()){if(this.visible()!==item.sessionId)this.banner(item);return}
    this.finishing++;this.completionChanged()
    let stage='permission'
    try{
    if(!await notificationManager.isNotificationEnabled()||!this.current())return
    stage='bundle'
    const bundle=await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
    const id=item.destination==='ds-bot'?notificationId(this.scope+'/dsbot/'+item.sessionId):notificationId(this.scope+'/'+(item.kind==='approval'||item.kind==='question'?'':item.sessionId+'/')+item.key)
    stage='want-agent'
    const agent=await wantAgent.getWantAgent({wants:[{bundleName:bundle.name,abilityName:'EntryAbility',parameters:{'dsh.kind':item.destination==='ds-bot'?(item.botRoom?'dsbot-room':'dsbot-bot'):'chat','dsh.sessionId':item.sessionId,'dsh.host':this.scope}}],
      operationType:wantAgent.OperationType.START_ABILITY,requestCode:id,wantAgentFlags:[wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]})
    if(!this.current())return
    stage='publish'
    // SDK NotificationRequest uses the legacy enum type; 2 is SERVICE_INFORMATION, 0 is BASIC_TEXT.
    await notificationManager.publish({id:id,slotType:2,autoDeletedTime:new Date().getTime()+86400000,
      wantAgent:agent,content:{contentType:0,normal:{title:'DSH Go',text:localizedSettingsText(item.text,AppStorage.get<string>('dshLanguage') || 'system'),additionalText:localizedSettingsText('点按查看对话',AppStorage.get<string>('dshLanguage') || 'system')}}})
    backgroundCompletionLog('published')
    }catch(error){backgroundCompletionLog('notification-'+stage+'-failed',(error as BusinessError)?.code||0)}finally{this.finishing--;this.completionChanged()}
  }
}
