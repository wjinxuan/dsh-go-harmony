import { localizedSettingsText } from '../SettingsLocale'
import { common } from '@kit.AbilityKit'
import { notificationManager } from '@kit.NotificationKit'
import { NotificationPreferences, notificationPreferences } from '../NotificationData'
import { loadNotificationPreferences, saveNotificationPreferences } from '../ChatNotifications'
import { DshGlyphs, ThemeColors, themeColors } from '../DshTheme'
@Component
export struct NotificationSettings {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors:ThemeColors=themeColors()
  onClose:()=>void=()=>{}
  onChange:(value:NotificationPreferences)=>void=()=>{}
  @StorageProp('dshForeground') @Watch('resumed') private foreground:boolean=true
  @State private value:NotificationPreferences=notificationPreferences()
  @State private systemAllowed:boolean=false
  @State private loaded:boolean=false
  @State private busy:boolean=false
  @State private error:string=''
  private active:boolean=false
  aboutToAppear():void{this.active=true;void this.load()}
  aboutToDisappear():void{this.active=false}
  private resumed():void{if(this.active&&this.foreground)void this.readSystem()}
  private async readSystem():Promise<void>{try{const enabled=await notificationManager.isNotificationEnabled();if(this.active)this.systemAllowed=enabled}catch{if(this.active)this.error=this.t('无法读取系统通知权限。')}}
  private async load():Promise<void>{try{const value=await loadNotificationPreferences(this.getUIContext().getHostContext() as common.Context);if(this.active){this.value=value;this.loaded=true}await this.readSystem()}catch{if(this.active)this.error=this.t('通知设置未能读取，请重试。')}}
  private async update(change:(value:NotificationPreferences)=>void):Promise<void>{
    if(!this.loaded||this.busy)return;const value=notificationPreferences(this.value);change(value);this.busy=true;this.error=''
    try{await saveNotificationPreferences(this.getUIContext().getHostContext() as common.Context,value);if(this.active){this.value=value;this.onChange(value)}}catch{if(this.active)this.error=this.t('通知设置未能保存。')}finally{if(this.active)this.busy=false}
  }
  private async permission(settings:boolean):Promise<void>{
    const context=this.getUIContext().getHostContext() as common.UIAbilityContext
    try{if(settings)await notificationManager.openNotificationSettings(context);else await notificationManager.requestEnableNotification(context)}catch{if(this.active)this.error=this.t('系统通知尚未开启，可以在系统设置中更改。')}
    await this.readSystem()
  }
  @Builder private toggle(label:string,value:()=>boolean,change:(value:boolean)=>void){Row(){Text(label).fontSize(16).fontColor(this.colors.text).layoutWeight(1)
    Toggle({type:ToggleType.Switch,isOn:value()}).selectedColor(this.colors.primary).enabled(this.loaded&&!this.busy).onChange(change)}.width('100%').padding(12)}
  build(){Column({space:14}){
    Row({space:12}){Button({type:ButtonType.Circle}){Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text)}.width(44).height(44).backgroundColor(this.colors.surface).onClick(this.onClose)
      Text(this.t('通知')).fontSize(22).fontColor(this.colors.text).layoutWeight(1)}.width('100%')
    if(this.error){Text(this.t(this.error)).fontColor(this.colors.danger)}
    Scroll(){Column({space:12}){
      Text(this.systemAllowed?this.t('系统通知已开启'):this.t('系统通知未开启')).fontColor(this.systemAllowed?this.colors.success:this.colors.warning).width('100%')
      Button(this.systemAllowed?this.t('系统通知设置'):this.t('开启系统通知')).width('100%').backgroundColor(this.colors.surface).fontColor(this.colors.text).onClick(()=>{void this.permission(this.systemAllowed)})
      if(!this.systemAllowed){Button(this.t('打开系统设置')).width('100%').backgroundColor(this.colors.surface).fontColor(this.colors.text).onClick(()=>{void this.permission(true)})}
      Column(){
        this.toggle(this.t('接收通知'),()=>this.value.enabled,(enabled:boolean)=>{void this.update((value:NotificationPreferences)=>value.enabled=enabled)})
        this.toggle(this.t('对话完成'),()=>this.value.done,(enabled:boolean)=>{void this.update((value:NotificationPreferences)=>value.done=enabled)})
        this.toggle(this.t('出错或停止'),()=>this.value.failed,(enabled:boolean)=>{void this.update((value:NotificationPreferences)=>value.failed=enabled)})
        this.toggle(this.t('操作等待确认'),()=>this.value.approval,(enabled:boolean)=>{void this.update((value:NotificationPreferences)=>value.approval=enabled)})
        this.toggle(this.t('问题等待回答'),()=>this.value.question,(enabled:boolean)=>{void this.update((value:NotificationPreferences)=>value.question=enabled)})
      }.width('100%').backgroundColor(this.colors.surface).borderRadius(14)
      Text(this.t('前台时显示应用内提醒，正在查看的对话不会重复提醒。锁屏通知只显示事件类型，点按后打开对话。')).fontSize(14).fontColor(this.colors.muted)
    }.width('100%')}.layoutWeight(1).width('100%')
  }.width('100%').height('100%').padding(16).backgroundColor(this.colors.background)}
}
