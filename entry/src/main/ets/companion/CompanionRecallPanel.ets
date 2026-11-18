import { util } from '@kit.ArkTS'
import { DshClient } from '../dsh/DshClient'
import { WireObject, object, string, number } from '../dsh/DshWire'
import { ThemeColors, themeColors } from '../ui/DshTheme'
import { localizedSettingsText } from '../ui/SettingsLocale'
import { companionPrivateRead, companionPrivateWrite } from './CompanionStore'
import { CompanionPrivatePreferences } from './CompanionConsent'
import { CompanionRecallOwner, CompanionRecallTransport } from './CompanionRecall'
@Component
export struct CompanionRecallPanel {
 @StorageProp('dshLanguage') language:string='system'
 @Prop colors:ThemeColors=themeColors()
 @Prop hostKey:string='local'
 @Prop sessionId:string=''
 @Prop memoryState:WireObject={}
 @Prop cleanSession:boolean=false
 @Prop blocked:boolean=false
 client:DshClient|undefined=undefined
 onChanged:(newSession:boolean)=>void=()=>{}
 @State private busy:boolean=false
 @State private status:string=''
 @State private error:string=''
 @State private supported:boolean=false
 @State private bound:boolean=false
 private owner:CompanionRecallOwner|undefined=undefined
 private active:boolean=false
 private t(text:string):string{return localizedSettingsText(text,this.language)}
 aboutToAppear():void{this.active=true;void this.load()}
 aboutToDisappear():void{this.active=false;this.owner?.close()}
 private async load():Promise<void>{if(!this.client)return;this.busy=true;this.error='';const client=this.client;const transport:CompanionRecallTransport={identity:():number=>client.connectionIdentity(),call:async(method:string,path:string,body?:WireObject):Promise<WireObject|null>=>{const value=await client.companionJson(method,path,body);return value===null?null:object(value)}};const storage:CompanionPrivatePreferences={read:(key:string):Promise<string|undefined>=>companionPrivateRead(getContext(this),key),write:(key:string,value:string):Promise<void>=>companionPrivateWrite(getContext(this),key,value)};this.owner?.close();const owner=new CompanionRecallOwner(this.hostKey,transport,storage,():string=>util.generateRandomUUID().toLowerCase());this.owner=owner;try{await owner.load();if(!this.active||this.owner!==owner)return;this.supported=owner.capabilities?.['supported']===true;this.bound=!!owner.stored&&!owner.stored.off&&owner.binding?.['status']==='ready';this.status=this.bound?'已启用自动回忆':this.supported?'此主机支持自动回忆':'此主机暂不支持自动回忆'}catch(error){if(this.active)this.error=error instanceof Error?error.message:'自动回忆状态读取失败'}finally{if(this.active)this.busy=false}}
 private confirm(enable:boolean):void{this.getUIContext().showAlertDialog({title:this.t(enable?'启用自动回忆':'关闭自动回忆'),message:this.t(enable?'仅使用你已确认的记忆，最多选择 12 条、1200 字；绑定到当前干净的伙伴会话。记忆不会授予工具权限。':'撤销当前回忆绑定并开始新的伙伴会话。原聊天记录保留，旧绑定会话不会作为普通会话继续使用。'),primaryButton:{value:this.t('取消'),action:()=>{}},secondaryButton:{value:this.t('确认'),action:()=>{void this.change(enable)}}})}
 private async change(enable:boolean):Promise<void>{if(!this.owner)return;this.busy=true;this.error='';try{if(enable)await this.owner.bind(string(this.memoryState['storeId']),number(this.memoryState['memoryRevision'],0),this.sessionId,true,this.cleanSession);else await this.owner.revoke(true);if(this.active)this.onChanged(!enable)}catch(error){if(this.active)this.error=error instanceof Error?error.message:'自动回忆更新失败'}finally{if(this.active)this.busy=false}}
 build(){Column({space:8}){Text(this.t('自动回忆')).fontColor(this.colors.text).fontSize(17);Text(this.t(this.status||'读取自动回忆能力…')).fontColor(this.colors.muted).fontSize(12);if(!this.bound&&!this.cleanSession)Text(this.t('启用前请先重新开始伙伴聊天，使用没有消息的新会话。')).fontColor(this.colors.muted).fontSize(12);Row({space:6}){if(this.bound)Button(this.t('关闭自动回忆')).enabled(!this.busy&&!this.blocked).onClick(()=>this.confirm(false));else Button(this.t('启用自动回忆')).enabled(this.supported&&this.cleanSession&&!this.busy&&!this.blocked).onClick(()=>this.confirm(true));Button(this.t('刷新')).enabled(!this.busy).onClick(()=>{void this.load()})};if(this.error)Text(this.t(this.error)).fontColor(this.colors.danger).fontSize(12)}.width('100%')}
}
