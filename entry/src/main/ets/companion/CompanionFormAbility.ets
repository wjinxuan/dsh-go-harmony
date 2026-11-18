import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit'
import { Want } from '@kit.AbilityKit'
import { companionWidgetBinding, registerCompanionWidget } from './CompanionWidget'
import { companionWidgetView } from './CompanionWidgetData'
export default class CompanionFormAbility extends FormExtensionAbility {
 onAddForm(want:Want):formBindingData.FormBindingData{const id=String(want.parameters?.[formInfo.FormParam.IDENTITY_KEY]||'');void registerCompanionWidget(this.context,id).catch(()=>{});return formBindingData.createFormBindingData(companionWidgetView({}))}
 onUpdateForm(formId:string):void{void companionWidgetBinding(this.context).then((binding:formBindingData.FormBindingData)=>formProvider.updateForm(formId,binding)).catch(()=>{})}
 onRemoveForm(formId:string):void{void registerCompanionWidget(this.context,formId,true).catch(()=>{})}
 onCastToNormalForm(formId:string):void{void registerCompanionWidget(this.context,formId).catch(()=>{})}
}
