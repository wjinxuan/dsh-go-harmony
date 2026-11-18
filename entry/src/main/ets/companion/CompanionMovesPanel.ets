import { ThemeColors, themeColors } from '../ui/DshTheme'
import { localizedSettingsText } from '../ui/SettingsLocale'
import { CompanionMove } from './CompanionMoves'
@Component
export struct CompanionMovesPanel {
 @StorageProp('dshLanguage') language:string='system'
 @Prop colors:ThemeColors=themeColors()
 @Prop moves:CompanionMove[]=[]
 onChange:(move:CompanionMove)=>void=()=>{}
 onTry:(move:CompanionMove)=>void=()=>{}
 onDirtyChange:(dirty:boolean)=>void=()=>{}
 @State private editing:string=''
 @State private label:string=''
 private t(value:string):string{return localizedSettingsText(value,this.language)}
 build(){Column({space:8}){Text(this.t('角色自带的表情和动作')).fontSize(17).fontColor(this.colors.text);Text(this.t('可试播、改名，并选择哪些允许模型使用；改名与开关仅属于当前角色。')).fontSize(12).fontColor(this.colors.muted)
 if(!this.moves.length)Text(this.t('这个角色没有自带表情或动作')).fontColor(this.colors.muted)
 ForEach(this.moves,(move:CompanionMove)=>{Column({space:5}){Row({space:6}){Text(move.label).fontColor(this.colors.text).layoutWeight(1);Toggle({type:ToggleType.Switch,isOn:move.ai}).onChange((value:boolean)=>this.onChange({kind:move.kind,raw:move.raw,label:move.label,ai:value}));Button(this.t('试播')).onClick(()=>this.onTry(move));Button(this.t('改名')).onClick(()=>{this.editing=move.kind+':'+move.raw;this.label=move.label})};Text(move.raw).fontSize(10).fontColor(this.colors.muted)
 if(this.editing===move.kind+':'+move.raw){TextInput({text:this.label}).maxLength(40).onChange((value:string)=>{this.label=value;this.onDirtyChange(value!==move.label)});Row({space:6}){Button(this.t('保存名称')).enabled(!!this.label.trim()).onClick(()=>{this.onChange({kind:move.kind,raw:move.raw,label:this.label.trim(),ai:move.ai});this.editing='';this.onDirtyChange(false)});Button(this.t('取消')).onClick(()=>{this.editing='';this.onDirtyChange(false)})}}}.width('100%')},(move:CompanionMove)=>move.kind+':'+move.raw)
 }.width('100%')}
}
