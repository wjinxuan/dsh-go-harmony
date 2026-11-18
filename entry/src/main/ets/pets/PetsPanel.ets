import { common } from '@kit.AbilityKit'
import { ThemeColors, themeColors } from '../ui/DshTheme'
import { localizedSettingsText } from '../ui/SettingsLocale'
import { PetPack, PetPreferences, petPreferences } from './PetData'
import { listPets, loadPetPreferences, savePetPreferences, installPet, removePet } from './PetStore'
import { pickPrivateZip } from './ArchiveFiles'
import { PetSprite } from './PetSprite'
@Component
export struct PetsPanel {
 @StorageProp('dshLanguage') language:string='system'
 @Prop colors:ThemeColors=themeColors()
 @Prop preferEnabled:boolean=true
 @Prop animations:boolean=true
 onClose:()=>void=()=>{}
 onOpenCompanion:()=>void=()=>{}
 @State private packs:PetPack[]=[]
 @State private prefs:PetPreferences=petPreferences()
 @State private busy:boolean=false
 @State private error:string=''
 private t(value:string):string{return localizedSettingsText(value,this.language)}
 aboutToAppear():void{void this.load()}
 private async load():Promise<void>{try{this.prefs=await loadPetPreferences(getContext(this),this.preferEnabled);this.packs=await listPets(getContext(this))}catch(error){this.error=error instanceof Error?error.message:String(error)}}
 private async save():Promise<void>{try{await savePetPreferences(getContext(this),this.prefs)}catch(error){this.error=error instanceof Error?error.message:String(error)}}
 private select(id:string):void{this.prefs={packId:id,explicit:true,size:this.prefs.size,quiet:this.prefs.quiet,position:this.prefs.position,hiddenUntil:0,overlay:this.prefs.overlay,overlayMode:this.prefs.overlayMode,overlayPosition:this.prefs.overlayPosition,overlayHiddenUntil:this.prefs.overlayHiddenUntil};void this.save()}
 private async bring():Promise<void>{if(this.busy)return;this.busy=true;this.error='';try{const bytes=await pickPrivateZip(getContext(this) as common.UIAbilityContext,67108864);if(bytes){const pack=await installPet(getContext(this),bytes);this.select(pack.id);await this.load()}}catch(error){this.error=error instanceof Error?error.message:String(error)}finally{this.busy=false}}
 private remove(pack:PetPack):void{this.getUIContext().showAlertDialog({title:this.t('移除宠物？'),message:pack.name,primaryButton:{value:this.t('取消'),action:()=>{}},secondaryButton:{value:this.t('移除'),action:()=>{void this.removeNow(pack)}}})}
 private async removeNow(pack:PetPack):Promise<void>{this.busy=true;try{await removePet(getContext(this),pack.id);await this.load()}catch(error){this.error=error instanceof Error?error.message:String(error)}finally{this.busy=false}}
 build(){Column({space:12}){Row(){Button('‹').onClick(this.onClose);Text(this.t('宠物')).fontSize(23).fontWeight(FontWeight.Bold).fontColor(this.colors.text).layoutWeight(1);Button(this.t('导入')).enabled(!this.busy).onClick(()=>{void this.bring()})}.width('100%')
 Scroll(){Column({space:12}){Button(this.t('不显示')+(this.prefs.packId==='none'?' ✓':'')).width('100%').onClick(()=>this.select('none'))
 ForEach(this.packs,(pack:PetPack)=>{Column({space:4}){Row(){PetSprite({pack:pack,petSize:'large',animations:this.animations});Column({space:5}){Text(pack.name+(this.prefs.packId===pack.id?' ✓':'')).fontSize(17).fontColor(this.colors.text);Text([pack.author,pack.license].filter((v:string)=>!!v).join(' · ')).fontSize(11).fontColor(this.colors.muted)}.alignItems(HorizontalAlign.Start).layoutWeight(1);if(pack.id.startsWith('user-'))Button(this.t('移除')).enabled(!this.busy).onClick(()=>this.remove(pack))}.width('100%').onClick(()=>this.select(pack.id));if(pack.source)Text(pack.source).fontSize(11).fontColor(this.colors.muted)}.padding(10).backgroundColor(this.prefs.packId===pack.id?this.colors.primaryContainer:this.colors.surface).borderRadius(14)},(pack:PetPack)=>pack.id)
 if(this.prefs.packId!=='none'){Text(this.t('大小')).fontColor(this.colors.text);Row({space:8}){ForEach(['small','medium','large'],(size:string,index:number)=>{Button(this.t(['小','中','大'][index])+(this.prefs.size===size?' ✓':'')).onClick(()=>{this.prefs.size=size;void this.save()})})};Row(){Text(this.t('安静模式')).fontColor(this.colors.text).layoutWeight(1);Toggle({type:ToggleType.Switch,isOn:this.prefs.quiet}).onChange((value:boolean)=>{this.prefs.quiet=value;void this.save()})};Text(this.t('只保留动作，不显示会话提醒气泡')).fontSize(12).fontColor(this.colors.muted);if(this.prefs.hiddenUntil>Date.now())Button(this.t('立即显示')).onClick(()=>{this.prefs.hiddenUntil=0;void this.save()})}
 Column({space:6}){Row(){Text(this.t('App 外显示')).fontColor(this.colors.text).layoutWeight(1);Toggle({type:ToggleType.Switch,isOn:false}).enabled(false)};Text(this.t('当前鸿蒙手机应用不具备系统悬浮窗权限；宠物可在应用内显示。')).fontSize(12).fontColor(this.colors.muted)}
 Button(this.t('伙伴小屋')).width('100%').onClick(this.onOpenCompanion)
 Text(this.t('支持原版 pack.json 宠物包及 Codex pet.json PNG / WebP 图集。只在本机读取，不下载外部资源。')).fontSize(12).fontColor(this.colors.muted)
 if(this.busy)LoadingProgress().width(28).height(28);if(this.error)Text(this.t(this.error)).fontColor(this.colors.danger).fontSize(13)
 }.width('100%')}.layoutWeight(1)
 }.padding(18).width('100%').height('100%').backgroundColor(this.colors.background)}
}
