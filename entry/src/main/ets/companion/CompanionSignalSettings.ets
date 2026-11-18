import { ThemeColors, themeColors } from '../ui/DshTheme'
import { localizedSettingsText, settingsLanguage } from '../ui/SettingsLocale'
import { CompanionConsent } from './CompanionConsent'
import { CompanionSignals, CompanionSignalsView } from './CompanionSignals'
import { CompanionSignalSlot, CompanionSignalPreview, CompanionSignalShareTarget, companionSignalTemplate } from './CompanionSignalsData'
export function emptyCompanionSignalsView():CompanionSignalsView{return{status:'unread',error:'',consent:undefined,slots:[],speech:undefined,overflow:0,runAvailable:false}}
@Component
export struct CompanionSignalSettings {
 @StorageProp('dshLanguage') private language:string='system'
 @Prop settingsMode:boolean=true
 @Prop colors:ThemeColors=themeColors()
 @Prop view:CompanionSignalsView=emptyCompanionSignalsView()
 getOwner:()=>CompanionSignals|undefined=():undefined=>undefined
 getShareTarget:()=>CompanionSignalShareTarget|undefined=():undefined=>undefined
 onShare:(text:string,target:CompanionSignalShareTarget,current:()=>boolean)=>Promise<boolean>=async():Promise<boolean>=>false
 @State private busy:boolean=false
 @State private preview:CompanionSignalPreview|undefined=undefined
 @State private error:string=''
 private t(text:string):string{return localizedSettingsText(text,this.language)}
 private status():string{const status=this.view.status;if(status==='live')return'执行结果实时信号已连接';if(status==='producer-unavailable')return'当前引擎没有可用的执行结果生产器';if(status==='engine-unavailable')return'当前主机引擎不可用';if(status==='absent')return'此主机尚未提供执行结果信号接口';if(status==='scene-inactive')return'角色舞台未显示，实时信号已暂停';if(status==='off')return'伙伴状态感知已关闭';if(status==='background')return'后台暂停伙伴信号';if(status==='unread')return'伙伴同意设置尚未读取';if(status==='loading'||status==='connecting')return'正在验证伙伴信号能力…';if(status==='saving')return'正在保存伙伴同意设置…';return'伙伴实时信号已停止，请刷新重新连接'}
 private async update(key:string,value:boolean):Promise<void>{const owner=this.getOwner();if(this.busy||!owner||!this.view.consent)return;const old=this.view.consent,consent:CompanionConsent={state:key==='state'?value:old.state,optionalSpeech:key==='optionalSpeech'?value:old.optionalSpeech,voice:key==='voice'?value:old.voice,nightCare:key==='nightCare'?value:old.nightCare};this.busy=true;this.preview=undefined;try{await owner.setConsent(consent)}finally{this.busy=false}}
 private async details():Promise<void>{const preview=this.preview,owner=this.getOwner();if(!preview||!owner)return;this.busy=true;try{const detail=await owner.detail(preview.slot);if(this.getOwner()!==owner||this.preview!==preview)return;if(!detail)this.error='所选信号已过期或无法读取对应详情';else this.preview=detail}finally{this.busy=false}}
 private confirmShare():void{if(!this.preview||!this.getOwner())return;const preview=this.preview,target=this.getShareTarget();if(!target){this.error='当前伙伴目标未就绪，无法分享';return}this.getUIContext().showAlertDialog({title:this.t('分享这段预览给当前伙伴'),message:preview.text,primaryButton:{value:this.t('取消'),action:()=>{}},secondaryButton:{value:this.t('确认分享'),action:()=>{void this.share(preview,target)}}})}
 private async share(preview:CompanionSignalPreview,target:CompanionSignalShareTarget):Promise<void>{const owner=this.getOwner();if(this.busy||!owner)return;this.busy=true;try{const ok=await owner.share(preview,target,true,this.onShare);if(this.getOwner()!==owner||this.preview!==preview)return;this.error=ok?'已分享所确认的预览':'信号或伙伴目标已变化，分享未完成';this.preview=undefined}finally{this.busy=false}}
 @Builder private toggle(label:string,key:string,value:()=>boolean){Row(){Text(this.t(label)).fontColor(this.colors.text).layoutWeight(1);Toggle({type:ToggleType.Switch,isOn:value()}).enabled(!this.busy&&!!this.view.consent).onChange((on:boolean)=>{void this.update(key,on)})}.width('100%')}
 build(){Column({space:9}){
  if(this.settingsMode){Text(this.t('伙伴信号')).fontSize(17).fontColor(this.colors.text)
  this.toggle('感知其它会话的状态','state',():boolean=>this.view.consent?.state===true)
  this.toggle('允许伙伴主动说一句','optionalSpeech',():boolean=>this.view.consent?.optionalSpeech===true)
  this.toggle('允许信号台词使用语音','voice',():boolean=>this.view.consent?.voice===true)
  this.toggle('允许深夜关怀','nightCare',():boolean=>this.view.consent?.nightCare===true)
  Text(this.t(this.status())).fontColor(this.colors.muted).fontSize(12)
  Text(this.t('仅接收实时元数据，不回放历史；电量和通知信号暂不可用。台词仍受安静时段、共享频率和语音设置限制。')).fontColor(this.colors.muted).fontSize(12)
  Button(this.t('刷新信号能力')).enabled(!this.busy&&!!this.view.status&&!!this.getOwner()).onClick(()=>{void this.getOwner()?.refresh()})
  }else{ForEach(this.view.slots,(slot:CompanionSignalSlot)=>{Button(companionSignalTemplate(slot.signal,settingsLanguage(this.language).startsWith('zh')?'zh':'en')).onClick(()=>{this.preview=this.getOwner()?.preview(slot);this.error=''})},(slot:CompanionSignalSlot)=>slot.key)
  if(this.preview){Text(this.preview.text).fontColor(this.colors.text).fontSize(13);Row({space:6}){Button(this.t('查看所选事件详情')).enabled(!this.busy).onClick(()=>{void this.details()});Button(this.t('分享给当前伙伴')).enabled(!this.busy).onClick(()=>this.confirmShare());Button(this.t('关闭')).onClick(()=>{this.preview=undefined})}}
  }
  if(this.view.error||this.error)Text(this.t(this.error||this.view.error)).fontColor(this.colors.danger).fontSize(12)
 }.width('100%')}
}
