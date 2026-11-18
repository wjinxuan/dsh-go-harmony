import { WireObject, string } from '../dsh/DshWire'
import { ThemeColors, themeColors } from '../ui/DshTheme'
import { localizedSettingsText } from '../ui/SettingsLocale'
import { CompanionLightRequest, companionHasKey } from './CompanionLight'
import { COMPANION_ADAPT_SYSTEM, companionAdaptInput, companionAdaptJson, companionAdapterCheck, companionAdapterEmpty, companionAdaptWanted } from './CompanionAdapt'
import { CompanionAdaptPreferences, companionAdaptPreferences, saveCompanionAdaptPreferences, companionFingerprint, companionAdaptTried, readCompanionAdapter, writeCompanionAdapter, removeCompanionAdapter } from './CompanionAdaptStore'
@Component
export struct CompanionAdaptPanel {
 @StorageProp('dshLanguage') language:string='system'
 @Prop @Watch('discarded') discardVersion:number=0
 @Prop settingsMode:boolean=true
 @Prop colors:ThemeColors=themeColors()
 @Prop @Watch('probeChanged') probe:WireObject={}
 @Prop @Watch('visibilityChanged') foreground:boolean=true
 onDirtyChange:(dirty:boolean)=>void=()=>{}
 onApplied:()=>void=()=>{}
 @State private offer:boolean=false
 @State private prefs:CompanionAdaptPreferences={consent:false,auto:true}
 @State private note:string=''
 @State private error:string=''
 @State private candidate:WireObject|undefined=undefined
 @State private dropped:string[]=[]
 @State private busy:boolean=false
 private fingerprint:string=''
 private request:CompanionLightRequest|undefined=undefined
 private generation:number=0
 private active:boolean=false
 private discarded():void{this.generation++;this.request?.cancel();this.busy=false;this.note='';this.candidate=undefined;this.onDirtyChange(false)}
 private t(text:string):string{return localizedSettingsText(text,this.language)}
 aboutToAppear():void{this.active=true;void companionAdaptPreferences(getContext(this)).then((prefs:CompanionAdaptPreferences)=>{this.prefs=prefs;void this.auto()})}
 aboutToDisappear():void{this.active=false;this.generation++;this.request?.cancel()}
 private probeChanged():void{this.generation++;this.request?.cancel();this.busy=false;this.candidate=undefined;this.offer=false;void this.auto()}
 private visibilityChanged():void{if(!this.foreground){this.generation++;this.request?.cancel();this.busy=false}else void this.auto()}
 private async auto():Promise<void>{if(!this.active||!this.foreground||this.busy||!string(this.probe['moc']))return;const generation=this.generation,probe=this.probe;try{const fingerprint=await companionFingerprint(getContext(this),probe),adapter=await readCompanionAdapter(getContext(this));if(generation!==this.generation||probe!==this.probe)return;if(adapter&&typeof adapter['moc']==='string'&&adapter['moc']!==fingerprint){await removeCompanionAdapter(getContext(this));if(generation!==this.generation)return;this.onApplied()}if(!this.prefs.auto||!companionAdaptWanted(probe).length||!await companionHasKey())return;if(await companionAdaptTried(getContext(this),fingerprint)||generation!==this.generation)return;if(!this.prefs.consent){this.offer=true;return}await companionAdaptTried(getContext(this),fingerprint,true);if(generation===this.generation)await this.ask()}catch(error){if(generation===this.generation)this.error=error instanceof Error?error.message:'角色适配失败'}}
 private async decline():Promise<void>{this.offer=false;try{await companionAdaptTried(getContext(this),await companionFingerprint(getContext(this),this.probe),true)}catch(error){this.error=error instanceof Error?error.message:'角色适配设置保存失败'}}
 private confirm():void{this.getUIContext().showAlertDialog({title:this.t('让模型帮助适配角色'),message:this.t('将发送角色的参数名、数值范围、动作名称和你的反馈给 DeepSeek；不会上传角色文件。只接受通过校验的数据映射。'),primaryButton:{value:this.t('取消'),action:()=>{}},secondaryButton:{value:this.t('同意并生成建议'),action:()=>{this.offer=false;this.prefs.consent=true;void saveCompanionAdaptPreferences(getContext(this),this.prefs).then(()=>this.ask()).catch((error:Error)=>{this.error=error.message})}}})}
 private async ask():Promise<void>{if(this.busy||!this.foreground)return;this.offer=false;this.busy=true;this.error='';this.candidate=undefined;const generation=++this.generation,probe=this.probe;try{this.fingerprint=await companionFingerprint(getContext(this),probe);await companionAdaptTried(getContext(this),this.fingerprint,true);const previous=await readCompanionAdapter(getContext(this));const input=companionAdaptInput(probe,this.note,previous);let answer='';const request=new CompanionLightRequest();this.request=request;await request.run(COMPANION_ADAPT_SYSTEM,[{role:'user',text:JSON.stringify(input)}],{},(delta:string)=>{answer+=delta},3000,():boolean=>this.active&&this.foreground&&generation===this.generation);if(generation!==this.generation||!this.active)return;const parsed=companionAdaptJson(answer);if(!parsed)throw new Error('模型未返回有效的适配数据');const checked=companionAdapterCheck(parsed,probe);if(companionAdapterEmpty(checked.adapter))throw new Error('模型未找到有证据支持的适配改动');this.candidate=checked.adapter;this.dropped=checked.dropped;await this.apply()}catch(error){if(generation===this.generation)this.error=error instanceof Error?error.message:'角色适配失败'}finally{if(generation===this.generation){this.busy=false;this.request=undefined}}}
 private async apply():Promise<void>{if(!this.candidate||!this.active||!this.foreground)return;try{await writeCompanionAdapter(getContext(this),this.probe,this.candidate,this.fingerprint);this.candidate=undefined;this.note='';this.onDirtyChange(false);this.onApplied()}catch(error){this.error=error instanceof Error?error.message:'角色适配保存失败'}}
 private async reset():Promise<void>{try{await companionAdaptTried(getContext(this),await companionFingerprint(getContext(this),this.probe),true);await removeCompanionAdapter(getContext(this));this.candidate=undefined;this.note='';this.onDirtyChange(false);this.onApplied()}catch(error){this.error=error instanceof Error?error.message:'角色适配重置失败'}}
 build(){Column({space:8}){if(this.settingsMode){Text(this.t('角色适配')).fontColor(this.colors.text).fontSize(17);Text(this.t('根据角色实际参数调整动作；明确同意后，应用通过校验的适配。')).fontColor(this.colors.muted).fontSize(12);TextArea({text:this.note,placeholder:this.t('描述想调整的动作（可选）')}).height(80).maxLength(1000).onChange((v:string)=>{this.note=v;this.onDirtyChange(!!this.note.trim()||!!this.candidate)});Row(){Text(this.t('允许后自动为新角色生成建议')).fontColor(this.colors.text).layoutWeight(1);Toggle({type:ToggleType.Switch,isOn:this.prefs.auto}).onChange((v:boolean)=>{this.prefs.auto=v;void saveCompanionAdaptPreferences(getContext(this),this.prefs)})};Row({space:6}){Button(this.t('生成适配建议')).enabled(!this.busy&&this.foreground&&!!string(this.probe['moc'])).onClick(()=>this.confirm());Button(this.t('恢复默认适配')).enabled(!this.busy).onClick(()=>{void this.reset()});if(this.busy)Button(this.t('取消')).onClick(()=>{this.request?.cancel()})};if(this.candidate){Text(JSON.stringify(this.candidate,null,2)).fontColor(this.colors.text).fontSize(12).copyOption(CopyOptions.LocalDevice);if(this.dropped.length)Text(this.t('已丢弃未通过校验的字段')+'：'+this.dropped.join(', ')).fontSize(12).fontColor(this.colors.warning);Button(this.t('应用已校验的建议')).onClick(()=>{void this.apply()})}if(this.error)Text(this.t(this.error)).fontColor(this.colors.danger).fontSize(12)}else if(this.offer){Text(this.t('这个角色还有可以适配的动作，要帮她调整一下吗？')).fontColor(this.colors.text);Row({space:8}){Button(this.t('看看适配内容')).onClick(()=>this.confirm());Button(this.t('这次不用')).onClick(()=>{void this.decline()})}}else if(this.busy){Text(this.t('正在根据角色参数适配动作…')).fontSize(12).fontColor(this.colors.muted);Button(this.t('取消')).onClick(()=>this.request?.cancel())}else if(this.error){Text(this.t(this.error)).fontColor(this.colors.danger).fontSize(12)}}.width('100%')}
}
