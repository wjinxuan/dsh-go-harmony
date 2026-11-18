import { localizedSettingsText } from '../SettingsLocale'
import { DshClient } from '../../dsh/DshClient'
import { array, object, number, WireObject } from '../../dsh/DshWire'
import { DshGlyphs, ThemeColors, themeColors } from '../DshTheme'
@Component
export struct PrivacySettings {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  client:DshClient=new DshClient()
  @Prop colors:ThemeColors=themeColors()
  onClose:()=>void=()=>{}
  onHostedLinks?:()=>void
  onShareConfiguration?:()=>void
  onUsageStats?:()=>void
  onLocalOcr?:()=>void
  @State private loaded:boolean=false
  @State private served:boolean=false
  @State private settingEnabled:boolean=false
  @State private writable:boolean=false
  @State private busy:boolean=false
  @State private error:string=''
  private source:number=-1
  private revision:number=0
  private active:boolean=false
  aboutToAppear():void{this.active=true;this.source=this.client.connectionIdentity();void this.load()}
  aboutToDisappear():void{this.active=false}
  private current():boolean{return this.active&&this.source===this.client.connectionIdentity()}
  private async load():Promise<boolean>{
    try{const settings=await this.client.describeSettings();if(!this.current())return false
      const ns=array(settings['namespaces']).map(object).find((row:WireObject)=>row['ns']==='session-log-deepseek')
      this.served=ns!==undefined;this.settingEnabled=object(ns?.['value'])['enabled']===true;this.revision=number(ns?.['revision'],0)
      this.writable=this.served&&settings['writable']!==false&&ns?.['writable']!==false;this.loaded=true;return true
    }catch{if(this.current()){this.error=this.t('无法读取主机隐私设置。');this.loaded=true}return false}
  }
  private async setLog(enabled:boolean):Promise<void>{
    if(!this.current()||!this.writable||this.busy)return;this.busy=true;this.error=''
    try{await this.client.mutateSettings('session-log-deepseek',[{op:'set',path:['enabled'],value:enabled}],this.revision)
      if(!this.current())return;if(!await this.load())return;if(this.settingEnabled!==enabled)throw new Error(this.t('主机未确认日志上传设置。'))
    }catch{if(this.current()){await this.load();this.error=this.t('未能保存，请刷新后重试。')}}finally{if(this.current())this.busy=false}
  }
  @Builder private entry(label:string,action:()=>void){Button(label).width('100%').height(48).backgroundColor(this.colors.surface).fontColor(this.colors.text).onClick(action)}
  build(){Column({space:14}){
    Row({space:12}){Button({type:ButtonType.Circle}){Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text)}.width(44).height(44).backgroundColor(this.colors.surface).onClick(this.onClose)
      Text(this.t('隐私与分享')).fontSize(22).fontColor(this.colors.text).layoutWeight(1)}.width('100%')
    if(this.error){Text(this.t(this.error)).fontColor(this.colors.danger)}
    Scroll(){Column({space:14}){
      if(this.onHostedLinks){this.entry(this.t('已分享的链接'),()=>this.onHostedLinks?.())}
      if(this.onShareConfiguration){this.entry(this.t('分享配置'),()=>this.onShareConfiguration?.())}
      if(this.onUsageStats){this.entry(this.t('匿名使用统计'),()=>this.onUsageStats?.())}
      if(this.onLocalOcr){this.entry(this.t('本地文字识别'),()=>this.onLocalOcr?.());Text(this.t('图片文字识别在设备上处理。需要交给模型的内容会随你的请求发送到所选主机与服务商。')).fontSize(14).fontColor(this.colors.muted)}
      if(this.served){Column({space:8}){Row(){Text(this.t('上传对话日志到 DeepSeek')).fontColor(this.colors.text).layoutWeight(1)
        Toggle({type:ToggleType.Switch,isOn:this.settingEnabled}).selectedColor(this.colors.primary).enabled(this.writable&&!this.busy).onChange((enabled:boolean)=>{void this.setLog(enabled)})}.width('100%')
        Text(this.t('由当前主机的对话日志插件执行。关闭后不再上传新的对话日志。')).fontSize(14).fontColor(this.colors.muted)
      }.padding(16).width('100%').backgroundColor(this.colors.surface).borderRadius(14)}
      Text(this.t('API Key 使用本机安全存储。订阅授权保存在当前主机；退出订阅会从该主机移除授权。')).fontColor(this.colors.muted).fontSize(14)
      this.entry(this.loaded?this.t('刷新主机设置'):this.t('正在读取…'),()=>{void this.load()})
    }.width('100%')}.width('100%').layoutWeight(1)
  }.width('100%').height('100%').padding(16).backgroundColor(this.colors.background)}
}
