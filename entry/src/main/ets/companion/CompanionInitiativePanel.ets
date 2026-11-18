import { common } from '@kit.AbilityKit'
import { systemDateTime } from '@kit.BasicServicesKit'
import { object, string, WireObject } from '../dsh/DshWire'
import { ThemeColors, themeColors } from '../ui/DshTheme'
import { localizedSettingsText } from '../ui/SettingsLocale'
import { CompanionInitiativeClock, CompanionInitiativeView } from './CompanionInitiative'
import { CompanionInitiativeOwner, CompanionInitiativeCandidate } from './CompanionInitiativeOwner'
import { CompanionPrivatePreferences } from './CompanionConsent'
import { companionPrivateRead, companionPrivateWrite } from './CompanionStore'
let installedOwner:CompanionInitiativeOwner|undefined=undefined
function owner(context:common.Context):CompanionInitiativeOwner{
  if(!installedOwner){const storage:CompanionPrivatePreferences={read:(key:string)=>companionPrivateRead(context,key),write:(key:string,value:string)=>companionPrivateWrite(context,key,value)};installedOwner=new CompanionInitiativeOwner(storage,():CompanionInitiativeClock=>{return{wallMs:Date.now(),monoMs:systemDateTime.getUptime(systemDateTime.TimeType.STARTUP,false),offsetMinutes:-new Date().getTimezoneOffset()}})}return installedOwner
}
@Component
export struct CompanionInitiativePanel {
  @StorageProp('dshLanguage') private language:string='system'
  private t(value:string):string{return localizedSettingsText(value,this.language)}
  @Prop colors:ThemeColors=themeColors()
  @Prop @Watch('changed') foreground:boolean=true
  @Prop @Watch('changed') stageReady:boolean=false
  @Prop @Watch('changed') contextKey:string=''
  @Prop @Watch('changed') blocked:boolean=true
  @Prop @Watch('changed') initiativeEnabled:boolean=false
  @Prop @Watch('changed') accessible:boolean=false
  @Prop @Watch('changed') pace:string='rare'
  @Prop @Watch('activated') activationVersion:number=0
  @Prop @Watch('signalChanged') signalCandidate:CompanionInitiativeCandidate|undefined=undefined
  onSignalPresented:(candidate:CompanionInitiativeCandidate)=>void=()=>{}
  onInviteAccepted:(action:string)=>void=()=>{}
  onModelContext?:(event:WireObject)=>void
  onStageCommand:(type:string,args:WireObject)=>void=()=>{}
  @State private display:WireObject={}
  private active:boolean=false
  private owner?:CompanionInitiativeOwner
  private token:number=-1
  private timer:number=-1
  private attachment:number=0
  private view():CompanionInitiativeView{return{visible:this.active&&this.stageReady,resumed:this.foreground,blocked:this.blocked,enabled:this.initiativeEnabled,accessible:this.accessible,contextKey:this.contextKey||'companion/unavailable'}}
  aboutToAppear():void{this.active=true;this.owner=owner(this.getUIContext().getHostContext() as common.Context);const attachment=++this.attachment;void this.owner.attach(this.view(),(effect:WireObject)=>{if(this.active&&attachment===this.attachment)this.effect(effect)}).then((token:number)=>{if(!this.active||attachment!==this.attachment){this.owner?.detach(token);return};this.token=token;this.changed();this.signalChanged()})}
  aboutToDisappear():void{this.active=false;this.attachment++;clearInterval(this.timer);this.owner?.detach(this.token);this.onStageCommand('beckon',{'prop':null});this.display={}}
  private changed():void{if(!this.active||this.token<0)return;this.owner?.update(this.token,this.view(),this.pace);clearInterval(this.timer);this.timer=-1;if(this.foreground)this.timer=setInterval(()=>{if(this.active)this.owner?.tick(this.token)},1000)}
  private signalChanged():void{if(this.active&&this.token>=0)this.owner?.signal(this.token,this.signalCandidate,(candidate:CompanionInitiativeCandidate)=>{if(this.active&&candidate===this.signalCandidate)this.onSignalPresented(candidate)})}
  private activated():void{if(this.active&&this.token>=0)this.owner?.activate(this.token)}
  private effect(effect:WireObject):void{const type=string(effect['type']);if(type==='show'){this.display=object(effect['display']);if(this.display['kind']==='signal')return;this.onStageCommand('glance',{'prop':'rest','ms':1800});this.onStageCommand('beckon',{'prop':'rest'})}else if(type==='hide'&&this.display['id']===effect['ticketId']){this.display={};this.onStageCommand('beckon',{'prop':null})}else if(type==='updateTimeout'&&this.display['id']===effect['ticketId']){const next:WireObject={};for(const key of Object.keys(this.display))next[key]=this.display[key];next['expiresAtMono']=effect['expiresAtMono'];this.display=next}else if(type==='restIntent'&&effect['contextKey']===this.contextKey){this.onStageCommand('prop',{'name':'rest'});this.onInviteAccepted('rest')}}
  private answer(yes:boolean):void{const id=string(this.display['id']);if(!id)return;this.owner?.answer(this.token,id,yes,this.view());if(!yes)this.onStageCommand('action',{'name':'nodSmall'})}
  build(){if(this.display['id'])Column({space:10}){
    Text(this.display['kind']==='signal'?(this.signalCandidate?.text||''):this.t('要不要陪我在软垫上歇一会儿？')).fontSize(16).fontColor(this.colors.text).width('100%')
    if(this.display['kind']==='signal'){Button(this.t('关闭')).onClick(()=>this.owner?.activate(this.token))}else Row({space:12}){Button(this.t('好呀')).layoutWeight(1).onClick(()=>this.answer(true));Button(this.t('等会儿')).layoutWeight(1).onClick(()=>this.answer(false))}.width('100%')
  }.padding(16).borderRadius(22).backgroundColor(this.colors.surface).width('100%')}
}
