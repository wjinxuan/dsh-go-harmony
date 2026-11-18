import { array, number, object, string, WireObject } from '../dsh/DshWire'
import { pluginInputIssue, pluginInputPath } from './NativePluginControlsData'
import { pluginText } from './NativePluginData'
import { localizedSettingsText } from './SettingsLocale'
import { ThemeColors, themeColors } from './DshTheme'
@Component
export struct NativePluginInput {
  @StorageProp('dshLanguage') language: string = 'system'
  @Prop colors: ThemeColors = themeColors()
  @Prop raw: WireObject = {}
  onValue?: (bind: string, value: Object | null, action: Object | null | undefined) => void
  @State private issue: string = ''
  private editable(): boolean { return !!this.onValue && this.raw['readOnly']!==true && !!pluginInputPath(string(this.raw['bind'])) }
  private min(): number { return number(this.raw['min'],['number','stepper'].includes(string(this.raw['type']))?-1e9:0) }
  private max(): number { return number(this.raw['max'],this.raw['type']==='rating'?5:['number','stepper'].includes(string(this.raw['type']))?1e9:100) }
  private value(): Object|null { return this.raw['value']??(this.raw['type']==='toggle'?false:['slider','stepper','rating'].includes(string(this.raw['type']))?this.min():'') }
  private change(value:Object|null):void { this.issue=pluginInputIssue(this.raw,value);this.onValue?.(string(this.raw['bind']),value,this.issue?undefined:this.raw['onChange']) }
  private pick(option:Object):void {
    const value=typeof option==='string'?option:string(object(option)['value'])||string(object(option)['label'])
    if (this.raw['type']==='chips'&&this.raw['multi']===true) { const values=array(this.value()).map((item:Object)=>string(item));this.change(values.includes(value)?values.filter((item:string)=>item!==value):values.concat(value)) }
    else this.change(value)
  }
  private selected(option:Object):boolean {
    const value=typeof option==='string'?option:string(object(option)['value'])||string(object(option)['label'])
    return this.raw['type']==='chips'&&this.raw['multi']===true ? array(this.value()).some((item:Object)=>string(item)===value) : this.value()===value
  }
  build() {
    Column({space:6}) {
      Text(string(this.raw['label'])).fontSize(14).fontColor(this.colors.text).width('100%')
      if (!this.editable()) Text(pluginText(this.value())).fontSize(14).fontColor(this.colors.muted).width('100%')
      else if (this.raw['type']==='toggle') Toggle({type:ToggleType.Switch,isOn:this.value()===true}).onChange((value:boolean)=>this.change(value))
      else if (this.raw['type']==='slider') {
        if (this.raw['range']===true) {
          Slider({value:number(array(this.value())[0],this.min()),min:this.min(),max:this.max(),step:Math.max(0.000000001,number(this.raw['step'],1))}).onChange((value:number)=>this.change([value,number(array(this.value())[1],this.max())]))
          Slider({value:number(array(this.value())[1],this.max()),min:this.min(),max:this.max(),step:Math.max(0.000000001,number(this.raw['step'],1))}).onChange((value:number)=>this.change([number(array(this.value())[0],this.min()),value]))
        } else Slider({value:number(this.value(),this.min()),min:this.min(),max:this.max(),step:Math.max(0.000000001,number(this.raw['step'],1))}).onChange((value:number)=>this.change(value))
      } else if (this.raw['type']==='rating'||this.raw['type']==='stepper') {
        Row({space:8}) {
          Button('−').onClick(()=>this.change(Math.max(this.min(),number(this.value(),0)-number(this.raw['step'],1))))
          Text(pluginText(this.value())).fontColor(this.colors.text)
          Button('+').onClick(()=>this.change(Math.min(this.max(),number(this.value(),0)+number(this.raw['step'],1))))
        }
      } else if (['select','segmented','chips'].includes(string(this.raw['type']))) {
        Flex({wrap:FlexWrap.Wrap}) { ForEach(array(this.raw['options']).slice(0,24),(option:Object)=> {
          Button((this.selected(option)?'✓ ':'')+(typeof option==='string'?option:string(object(option)['label']))).fontSize(12).margin(3)
            .backgroundColor(this.selected(option)?this.colors.primary:this.colors.surfaceAlt)
            .fontColor(this.selected(option)?this.colors.onPrimary:this.colors.text)
            .accessibilitySelected(this.selected(option)).onClick(()=>this.pick(option))
        }) }
      } else if (this.raw['type']==='textField'&&this.raw['multiline']===true) {
        TextArea({text:string(this.value()),placeholder:string(this.raw['placeholder'])}).maxLength(Math.min(2000,number(this.raw['maxLength'],256))).onChange((value:string)=>this.change(value))
      } else {
        TextInput({text:typeof this.value()==='number'?String(this.value()):string(this.value()),placeholder:string(this.raw['placeholder'])|| (this.raw['type']==='date'?'YYYY-MM-DD':this.raw['type']==='time'?'HH:mm':'')})
          .type(this.raw['type']==='number'?InputType.Number:InputType.Normal).maxLength(Math.min(2000,number(this.raw['maxLength'],256)))
          .onChange((value:string)=>this.change(this.raw['type']==='number'&&value.trim()?Number(value):value))
      }
      if (this.issue) Text(localizedSettingsText(this.issue,this.language)).fontSize(12).fontColor(this.colors.danger).width('100%')
    }.width('100%')
  }
}
