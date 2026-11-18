import { localizedSettingsText } from '../SettingsLocale'
import { common } from '@kit.AbilityKit'
import { AdvancedPreferences, advancedPreferences } from '../AdvancedPreferencesData'
import { loadAdvancedPreferences, saveAdvancedPreferences } from '../AppPreferences'
import { ACCENTS, DshAccent, DshGlyphs, ThemeColors, themeColors } from '../DshTheme'
import { pickWallpaper, removeWallpaperCopy } from '../WallpaperPicker'
import { WallpaperBackdrop } from '../WallpaperBackdrop'
@Component
export struct AppearanceSettings {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors: ThemeColors=themeColors()
  @Prop accentId:string='mist'
  @Prop themeMode:string='system'
  @Prop fontSize:number=16
  @Prop dark:boolean=false
  onClose:()=>void=()=>{}
  onThemeChange:(accentId:string,mode:string)=>void=()=>{}
  onFontSizeChange:(size:number)=>void=()=>{}
  onChange:(value:AdvancedPreferences)=>void=()=>{}
  @State private value:AdvancedPreferences=advancedPreferences()
  @State private customColor:string='#5F7A55'
  @State private loaded:boolean=false
  @State private busy:boolean=false
  @State private error:string=''
  private active:boolean=false
  aboutToAppear():void {this.active=true;void this.load()}
  aboutToDisappear():void {this.active=false}
  private async load():Promise<void> {
    try {const value=await loadAdvancedPreferences(this.getUIContext().getHostContext() as common.Context);if(this.active){this.value=value;this.customColor=value.customColor;this.loaded=true}}
    catch {if(this.active)this.error=this.t('无法读取外观设置，请重试。')}
  }
  private async update(change:(value:AdvancedPreferences)=>void):Promise<boolean> {
    if(!this.loaded||this.busy)return false
    const next=advancedPreferences(this.value);change(next);this.busy=true;this.error=''
    try {await saveAdvancedPreferences(this.getUIContext().getHostContext() as common.Context,next);if(this.active)this.value=next;this.onChange(next);return true}
    catch {if(this.active)this.error=this.t('设置未能保存，请重试。');return false} finally {if(this.active)this.busy=false}
  }
  private async custom():Promise<void> {if(!/^#[\da-fA-F]{6}$/.test(this.customColor)){this.error=this.t('请输入 #RRGGBB 格式的颜色。');return}const saved=await this.update((value:AdvancedPreferences)=>value.customColor=this.customColor.toUpperCase());if(saved)this.onThemeChange('custom',this.themeMode)}
  private async chooseWallpaper():Promise<void> {
    if(this.busy||!this.loaded)return
    this.busy=true;this.error=''
    const context=this.getUIContext().getHostContext() as common.UIAbilityContext,old=this.value.wallpaper.path
    let selected:string=''
    try {const paper=await pickWallpaper(context,this.value.wallpaper);if(!paper)return;selected=paper.path
      if(!this.active){await removeWallpaperCopy(context,selected);return}
      const next=advancedPreferences(this.value);next.wallpaper=paper;await saveAdvancedPreferences(context,next);selected='';if(this.active)this.value=next;this.onChange(next);await removeWallpaperCopy(context,old)
    }catch(reason){if(selected)await removeWallpaperCopy(context,selected);if(this.active)this.error=reason instanceof Error?reason.message:this.t('无法导入壁纸。')}finally{if(this.active)this.busy=false}
  }
  @Builder private toggle(label:()=>string,value:()=>boolean,change:(value:boolean)=>void) {
    Row(){Text(label()).fontColor(this.colors.text).fontSize(15).layoutWeight(1)
      Toggle({type:ToggleType.Switch,isOn:value()}).selectedColor(this.colors.primary).enabled(this.loaded&&!this.busy).onChange(change)
    }.width('100%').padding({top:8,bottom:8})
  }
  @Builder private slider(label:()=>string,value:()=>number,min:number,max:number,change:(value:number)=>void) {
    Text(label()).fontSize(14).fontColor(this.colors.muted).width('100%')
    Slider({value:value(),min:min,max:max,step:.01}).selectedColor(this.colors.primary).enabled(this.loaded&&!this.busy)
      .onChange((value:number,mode:SliderChangeMode)=>{if(mode===SliderChangeMode.End||mode===SliderChangeMode.Click)change(value)})
  }
  build(){
    Column({space:12}){
      Row({space:12}){Button({type:ButtonType.Circle}){Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text)}
        .width(44).height(44).backgroundColor(this.colors.surface).onClick(this.onClose)
        Text(this.t('主题与界面')).fontSize(22).fontColor(this.colors.text).layoutWeight(1)}.width('100%')
      if(this.error){Text(this.t(this.error)).fontColor(this.colors.danger)}
      Scroll(){Column({space:14}){
        Row({space:8}){ForEach(['system','light','dark'],(mode:string)=>{Button(mode==='system'?this.t('跟随系统'):mode==='light'?this.t('浅色'):this.t('深色')).layoutWeight(1)
          .fontColor(mode===this.themeMode?this.colors.onPrimary:this.colors.text).backgroundColor(mode===this.themeMode?this.colors.primary:this.colors.surface)
          .onClick(()=>this.onThemeChange(this.accentId,mode))})}.width('100%')
        Flex({wrap:FlexWrap.Wrap}){ForEach(ACCENTS,(accent:DshAccent)=>{Button(this.t(accent.name)).backgroundColor(this.dark?accent.dark:accent.light).fontColor(this.dark?'#192026':'#FFFFFF').margin(4)
          .onClick(()=>this.onThemeChange(accent.id,this.themeMode))})}
        Row({space:8}){TextInput({text:this.customColor,placeholder:'#5F7A55'}).fontColor(this.colors.text).backgroundColor(this.colors.surface).layoutWeight(1)
          .onChange((value:string)=>this.customColor=value);Button(this.t('自定义颜色')).fontColor(this.colors.text).backgroundColor(this.colors.surface).enabled(!this.busy&&this.loaded).onClick(()=>{void this.custom()})}.width('100%')
        Text(this.t('文字大小')).fontColor(this.colors.muted).width('100%')
        Row({space:8}){ForEach([14,16,18,20],(size:number)=>{Button(String(size)).layoutWeight(1).fontSize(size).fontColor(this.fontSize===size?this.colors.onPrimary:this.colors.text)
          .backgroundColor(this.fontSize===size?this.colors.primary:this.colors.surface).onClick(()=>this.onFontSizeChange(size))})}.width('100%')
        this.toggle(()=>this.t('折叠已完成轮次'),()=>this.value.foldCompletedTurns,(enabled:boolean)=>{void this.update((value:AdvancedPreferences)=>value.foldCompletedTurns=enabled)})
        this.toggle(()=>this.t('宽屏展开侧边栏'),()=>this.value.sidebarOpen,(enabled:boolean)=>{void this.update((value:AdvancedPreferences)=>value.sidebarOpen=enabled)})
        this.toggle(()=>this.t('宽屏显示详情栏'),()=>this.value.panelOpen,(enabled:boolean)=>{void this.update((value:AdvancedPreferences)=>value.panelOpen=enabled)})
        this.toggle(()=>this.t('玻璃效果'),()=>this.value.glass,(enabled:boolean)=>{void this.update((value:AdvancedPreferences)=>value.glass=enabled)})
        this.toggle(()=>this.t('实体键盘 Enter 发送'),()=>this.value.hardwareEnterSends,(enabled:boolean)=>{void this.update((value:AdvancedPreferences)=>value.hardwareEnterSends=enabled)})
        this.toggle(()=>this.t('可视化回复'),()=>this.value.visualReplies,(enabled:boolean)=>{void this.update((value:AdvancedPreferences)=>value.visualReplies=enabled)})
        Text(this.t('语言')).fontColor(this.colors.muted).width('100%')
        Row({space:8}){ForEach(['system','zh','en'],(language:string)=>{Button(language==='system'?this.t('跟随系统'):language==='zh'?this.t('中文'):'English').layoutWeight(1)
          .backgroundColor(this.value.language===language?this.colors.primary:this.colors.surface).fontColor(this.value.language===language?this.colors.onPrimary:this.colors.text)
          .enabled(this.loaded&&!this.busy).onClick(()=>{void this.update((value:AdvancedPreferences)=>value.language=language)})})}.width('100%')
        Text(this.t('壁纸')).fontSize(20).fontColor(this.colors.text).width('100%')
        Stack(){WallpaperBackdrop({paper:this.value.wallpaper,colors:this.colors,dark:this.dark})
          Text('DSH Go').fontSize(24).fontColor(this.colors.text).padding(20).backgroundColor(this.colors.surface).borderRadius(14)
        }.height(240).width('100%').borderRadius(18).clip(true)
        Button(this.t('选择图片')).width('100%').fontColor(this.colors.text).backgroundColor(this.colors.surface).enabled(this.loaded&&!this.busy).onClick(()=>{void this.chooseWallpaper()})
        if(this.value.wallpaper.path){
          this.toggle(()=>this.t('使用自定义壁纸'),()=>this.value.wallpaper.on,(enabled:boolean)=>{void this.update((value:AdvancedPreferences)=>value.wallpaper.on=enabled)})
          this.slider(()=>this.t('缩放'),()=>this.value.wallpaper.zoom,1,5,(amount:number)=>{void this.update((value:AdvancedPreferences)=>value.wallpaper.zoom=amount)})
          this.slider(()=>this.t('水平位置'),()=>this.value.wallpaper.alignX,-1,1,(amount:number)=>{void this.update((value:AdvancedPreferences)=>value.wallpaper.alignX=amount)})
          this.slider(()=>this.t('垂直位置'),()=>this.value.wallpaper.alignY,-1,1,(amount:number)=>{void this.update((value:AdvancedPreferences)=>value.wallpaper.alignY=amount)})
          this.slider(()=>this.t('模糊'),()=>this.value.wallpaper.blur,0,1,(amount:number)=>{void this.update((value:AdvancedPreferences)=>value.wallpaper.blur=amount)})
          this.slider(()=>this.dark?this.t('压暗'):this.t('提亮'),()=>this.dark?this.value.wallpaper.dim:this.value.wallpaper.lighten,0,1,(amount:number)=>{void this.update((value:AdvancedPreferences)=>{if(this.dark)value.wallpaper.dim=amount;else value.wallpaper.lighten=amount})})
        }
      }.width('100%').padding({bottom:24})}.width('100%').layoutWeight(1).align(Alignment.Top)
    }.width('100%').height('100%').padding(16).backgroundColor(this.colors.background)
  }
}
