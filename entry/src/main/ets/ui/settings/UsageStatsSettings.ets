import { localizedSettingsText } from '../SettingsLocale'
import { UsageStats } from '../UsageStatsData'
import { DshGlyphs, ThemeColors, themeColors } from '../DshTheme'
@Component
export struct UsageStatsSettings {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors:ThemeColors=themeColors()
  usage?:UsageStats
  onClose:()=>void=()=>{}
  @State private settingEnabled:boolean=true
  @State private loaded:boolean=false
  @State private busy:boolean=false
  @State private error:string=''
  private active:boolean=false
  aboutToAppear():void{this.active=true;void this.load()}
  aboutToDisappear():void{this.active=false}
  private async load():Promise<void>{try{await this.usage?.initialize();if(this.active){this.settingEnabled=this.usage?.state.enabled!==false;this.loaded=this.usage!==undefined}await this.usage?.noticed()}catch{if(this.active)this.error=this.t('统计设置未能读取。')}}
  private async change(enabled:boolean):Promise<void>{if(!this.usage||!this.loaded||this.busy)return;this.busy=true;try{await this.usage.setEnabled(enabled);if(this.active)this.settingEnabled=this.usage.state.enabled}catch{if(this.active)this.error=this.t('统计设置未能保存。')}finally{if(this.active)this.busy=false}}
  build(){Column({space:16}){
    Row({space:12}){Button({type:ButtonType.Circle}){Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text)}.width(44).height(44).backgroundColor(this.colors.surface).onClick(this.onClose)
      Text(this.t('匿名使用统计')).fontSize(22).fontColor(this.colors.text).layoutWeight(1)}.width('100%')
    if(this.error){Text(this.t(this.error)).fontColor(this.colors.danger)}
    Row(){Text(this.t('帮助改进 DSH Go')).fontSize(17).fontColor(this.colors.text).layoutWeight(1)
      Toggle({type:ToggleType.Switch,isOn:this.settingEnabled}).selectedColor(this.colors.primary).enabled(this.loaded&&!this.busy).onChange((enabled:boolean)=>{void this.change(enabled)})}.padding(16).width('100%').backgroundColor(this.colors.surface).borderRadius(14)
    Text(this.t('仅在你看过此说明后开始统计。按天记录消息、语音、分享、生成、手机任务次数，以及插件数量与引擎模式；不会收集对话内容、文件路径、密钥或账号。')).fontSize(15).fontColor(this.colors.muted)
    Text(this.t('报告包含应用版本、系统与设备型号、语言，以及每 90 天轮换的随机编号。历史统计最多保留 7 天，次日发送。关闭会删除本机统计与随机编号，并停止后续发送。')).fontSize(15).fontColor(this.colors.muted)
    if(this.usage?.active===false){Text(this.t('调试构建不统计也不发送。')).fontSize(14).fontColor(this.colors.hint)}
    Blank()
  }.width('100%').height('100%').padding(16).backgroundColor(this.colors.background)}
}
