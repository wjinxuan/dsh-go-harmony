import { common } from '@kit.AbilityKit'
import { picker } from '@kit.CoreFileKit'
import { ThemeColors, themeColors } from '../ui/DshTheme'
import { localizedSettingsText } from '../ui/SettingsLocale'
import { privateBytes } from '../pets/ArchiveFiles'
import { CompanionVoiceSettings as VoiceSettings, companionVoiceSettings, COMPANION_VOICE_PRESETS, CompanionVoicePreset } from './CompanionVoiceData'
import { loadCompanionVoice, saveCompanionVoice, saveCompanionVoiceSecret, keepCompanionRecording, removeCompanionRecording, CompanionSpeaker, CompanionVoiceEvent } from './CompanionVoice'
@Component
export struct CompanionVoiceSettings {
 @StorageProp('dshLanguage') language:string='system'
 @Prop colors:ThemeColors=themeColors()
 @Prop @Watch('foregroundChanged') foreground:boolean=true
 onDirtyChange:(dirty:boolean)=>void=()=>{}
 private saved:string=''
 private dirty():void{this.onDirtyChange(JSON.stringify(this.settings)!==this.saved||!!this.secret||!!this.headerDraft)}
 onChanged:(settings:VoiceSettings)=>void=()=>{}
 @State private settings:VoiceSettings=companionVoiceSettings()
 @State private secret:string=''
 @State private headerDraft:string=''
 @State private notice:string=''
 @State private error:string=''
 @State private busy:boolean=false
 private speaker:CompanionSpeaker|undefined=undefined
 private t(text:string):string{return localizedSettingsText(text,this.language)}
 aboutToAppear():void{void loadCompanionVoice(getContext(this)).then((value:VoiceSettings)=>{this.settings=value;this.saved=JSON.stringify(value)});this.speaker=new CompanionSpeaker(getContext(this),(event:CompanionVoiceEvent)=>{if(event.type==='error'||event.type==='fallback')this.error=event.reason})}
 aboutToDisappear():void{this.speaker?.close()}
 private foregroundChanged():void{if(!this.foreground)this.speaker?.stop()}
 private async save():Promise<void>{this.error='';this.notice='';this.busy=true;try{await saveCompanionVoice(getContext(this),this.settings);this.saved=JSON.stringify(this.settings);this.dirty();this.onChanged(this.settings);this.notice=this.t('语音设置已保存')}catch(error){this.error=error instanceof Error?error.message:'语音设置保存失败'}finally{this.busy=false}}
 private secretId():string{return this.settings.source==='preset'?this.settings.preset:'compatible'}
 private async saveSecret(clear:boolean=false):Promise<void>{this.error='';try{await saveCompanionVoiceSecret(this.secretId(),clear?'':this.secret.trim());this.secret='';this.dirty();this.notice=this.t(clear?'语音密钥已移除':'语音密钥已保存')}catch(error){this.error=error instanceof Error?error.message:'语音密钥保存失败'}}
 private async headers():Promise<void>{try{await saveCompanionVoiceSecret('headers',this.headerDraft);this.headerDraft='';this.dirty();this.notice=this.t('请求头已安全保存')}catch(error){this.error=error instanceof Error?error.message:'请求头保存失败'}}
 private preset():CompanionVoicePreset{return COMPANION_VOICE_PRESETS.find((preset:CompanionVoicePreset)=>preset.id===this.settings.preset)||COMPANION_VOICE_PRESETS[0]}
 private async importRecording():Promise<void>{this.busy=true;this.error='';try{const paths=await new picker.DocumentViewPicker(getContext(this)).select({maxSelectNumber:1,fileSuffixFilters:['音频|.wav,.mp3']});if(paths.length){this.settings.cloneSample=await keepCompanionRecording(getContext(this),await privateBytes(paths[0],7340032));this.settings.cloneOn=true;await this.save()}}catch(error){this.error=error instanceof Error?error.message:'录音导入失败'}finally{this.busy=false}}
 private confirmRecording():void{this.getUIContext().showAlertDialog({title:this.t('使用自己的声音'),message:this.t('仅导入你自己的声音或已获许可的录音。启用后，每句语音都会将录音发给所选服务。建议使用清晰的短录音，最长 7 MiB。'),primaryButton:{value:this.t('取消'),action:()=>{}},secondaryButton:{value:this.t('我有许可，选择录音'),action:()=>{void this.importRecording()}}})}
 private testVoice():void{if(!this.foreground)return;const settings=companionVoiceSettings(this.settings);settings.on=true;this.speaker?.configure(settings);this.speaker?.speak(this.language==='en'?'Hello, I am here with you.':'你好，我在这里陪你。')}
 build(){Column({space:10}){
 Row(){Text(this.t('朗读她的回复')).fontColor(this.colors.text).layoutWeight(1);Toggle({type:ToggleType.Switch,isOn:this.settings.on}).onChange((value:boolean)=>{this.settings.on=value;void this.save();this.dirty()})}
 Text(this.t('默认静音。外部语音失败时，此句改用手机系统语音；不会自动重复付费请求。')).fontSize(12).fontColor(this.colors.muted)
 Row({space:4}){ForEach(['system','preset','openai','custom'],(source:string,index:number)=>{Button(this.t(['手机语音','服务预设','兼容接口','自定义'][index])+(this.settings.source===source?' ✓':'')).fontSize(12).onClick(()=>{this.settings.source=source;this.secret='';this.headerDraft='';void this.save()})})}
 if(this.settings.source==='preset'){
 Row({space:4}){ForEach(COMPANION_VOICE_PRESETS,(preset:CompanionVoicePreset)=>{Button(preset.name+(this.settings.preset===preset.id?' ✓':'')).fontSize(12).onClick(()=>{this.settings.preset=preset.id;this.secret='';void this.save()})})}
 Select(this.preset().voices.map((voice:string):SelectOption=>({value:voice}))).value(this.settings.presetVoices[this.settings.preset]||this.preset().voices[0]).onSelect((_index:number,value:string)=>{this.settings.presetVoices[this.settings.preset]=value;this.dirty()})
 TextInput({text:this.settings.presetVoices[this.settings.preset]||'',placeholder:this.t('也可填写服务提供的音色 ID')}).onChange((value:string)=>{this.settings.presetVoices[this.settings.preset]=value;this.dirty()})
 if(this.preset().styled)TextArea({text:this.settings.presetStyle,placeholder:this.t('说话风格（留空使用原版默认）')}).height(80).maxLength(2000).onChange((value:string)=>{this.settings.presetStyle=value;this.dirty()})
 if(this.preset().clones){Row(){Text(this.t('用自己的声音')).fontColor(this.colors.text).layoutWeight(1);Toggle({type:ToggleType.Switch,isOn:this.settings.cloneOn}).enabled(!!this.settings.cloneSample).onChange((value:boolean)=>{this.settings.cloneOn=value;void this.save();this.dirty()})};Button(this.t(this.settings.cloneSample?'替换声音录音':'导入自己的声音')).enabled(!this.busy).onClick(()=>this.confirmRecording());if(this.settings.cloneSample)Button(this.t('删除声音录音')).onClick(()=>{void removeCompanionRecording(getContext(this)).then(()=>{this.settings.cloneSample='';this.settings.cloneOn=false;void this.save()}).catch((error:Error)=>{this.error=error.message})})}
 }
 if(this.settings.source==='openai'){TextInput({text:this.settings.openaiBase,placeholder:this.t('API 根地址')}).onChange((v:string)=>{this.settings.openaiBase=v;this.dirty()});TextInput({text:this.settings.openaiModel,placeholder:this.t('语音模型')}).onChange((v:string)=>{this.settings.openaiModel=v;this.dirty()});TextInput({text:this.settings.openaiVoice,placeholder:this.t('音色 ID')}).onChange((v:string)=>{this.settings.openaiVoice=v;this.dirty()})}
 if(['preset','openai'].includes(this.settings.source)){TextInput({text:this.secret,placeholder:this.t('新 API Key（已保存的密钥不回显）')}).type(InputType.Password).onChange((v:string)=>{this.secret=v;this.dirty()});Row({space:6}){Button(this.t('保存密钥')).enabled(!!this.secret.trim()).onClick(()=>{void this.saveSecret()});Button(this.t('移除密钥')).onClick(()=>{void this.saveSecret(true)})}}
 if(this.settings.source==='custom'){TextInput({text:this.settings.customUrl,placeholder:this.t('服务 URL，可用 {text}')}).onChange((v:string)=>{this.settings.customUrl=v;this.dirty()});Row(){Text('POST').fontColor(this.colors.text).layoutWeight(1);Toggle({type:ToggleType.Switch,isOn:this.settings.customPost}).onChange((v:boolean)=>{this.settings.customPost=v;this.dirty()})};TextArea({text:this.headerDraft,placeholder:this.t('请求头，每行 Name: value（安全保存，不回显）')}).height(90).onChange((v:string)=>{this.headerDraft=v;this.dirty()});Button(this.t('保存请求头')).onClick(()=>{void this.headers()});if(this.settings.customPost)TextArea({text:this.settings.customBody,placeholder:this.t('JSON 请求模板，文本使用 {text}')}).height(100).onChange((v:string)=>{this.settings.customBody=v;this.dirty()});TextInput({text:this.settings.customField,placeholder:this.t('JSON 音频字段路径（直接返回音频则留空）')}).onChange((v:string)=>{this.settings.customField=v;this.dirty()})}
 Row({space:6}){Button(this.t('保存语音设置')).enabled(!this.busy).onClick(()=>{void this.save()});Button(this.t('试听')).enabled(!this.busy&&this.foreground).onClick(()=>this.testVoice());Button(this.t('停止试听')).onClick(()=>this.speaker?.stop())}
 if(this.notice)Text(this.t(this.notice)).fontColor(this.colors.success).fontSize(12);if(this.error)Text(this.t(this.error)).fontColor(this.colors.danger).fontSize(12)
 }.width('100%')}
}
