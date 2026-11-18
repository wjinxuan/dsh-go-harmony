import { object, string, number, WireObject } from '../dsh/DshWire'
import { CompanionPrivatePreferences } from './CompanionConsent'
export const COMPANION_RECALL_SELECTOR:string='confirmed-recency-v1'
const UUID:RegExp=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
function natural(value:Object|null|undefined):boolean{return typeof value==='number'&&Number.isSafeInteger(value)&&value>=0}
function session(value:Object|null|undefined):boolean{if(typeof value!=='string'||!value||value.length>512||Array.from(value).length>256)return false;for(let i=0;i<value.length;i++){const c=value.charCodeAt(i);if(c>=0xd800&&c<=0xdbff){const next=value.charCodeAt(++i);if(!(next>=0xdc00&&next<=0xdfff))return false}else if(c>=0xdc00&&c<=0xdfff)return false};return true}
function reason(value:Object|null|undefined):boolean{return value===null||value===undefined||typeof value==='string'&&value.length<=512&&(value===''||session(value))}
export interface CompanionRecallRecord { binding:string; session:string; off:boolean }
export function companionRecallGone(error:Object):boolean{return error instanceof Error&&(error.message==='伙伴请求失败（companion/recall-binding-not-found）'||error.message==='伙伴请求失败（companion/recall-retired）')}
export function companionRecallRecord(raw:Object|null|undefined):CompanionRecallRecord|undefined{const v=object(raw);return UUID.test(string(v['binding']))&&session(v['session'])?{binding:string(v['binding']),session:string(v['session']),off:v['off']===true}:undefined}
export function companionRecallCapabilities(value:WireObject):WireObject{
  if(value['v']!==1||typeof value['supported']!=='boolean'||typeof value['busy']!=='boolean'||value['selectorVersion']!==COMPANION_RECALL_SELECTOR||value['maxItems']!==12||value['textUtf16Budget']!==1200||!Object.keys(value).includes('activeBindingId')||!Object.keys(value).includes('reason')||!reason(value['reason'])||value['activeBindingId']!==null&&!UUID.test(string(value['activeBindingId']))||value['busy']!==(value['activeBindingId']!==null))throw new Error('主机返回了无效的自动回忆能力')
  return value
}
export function companionRecallBinding(value:WireObject,requireNow:boolean=false):WireObject{
  if(value['v']!==1||!['ready','retired','unavailable'].includes(string(value['status']))||['bindingId','bridgeEpoch','storeId'].some((k:string)=>!UUID.test(string(value[k])))||!natural(value['recallEpoch'])||!natural(value['memoryRevision'])||!session(value['sessionId'])||value['selectorVersion']!==COMPANION_RECALL_SELECTOR||!reason(value['reason'])||requireNow&&!natural(value['serverNow'])||value['serverNow']!==undefined&&value['serverNow']!==null&&!natural(value['serverNow']))throw new Error('主机返回了无效的自动回忆绑定')
  return value
}
export interface CompanionRecallTransport { call:(method:string,path:string,body?:WireObject)=>Promise<WireObject|null>; identity:()=>number }
export class CompanionRecallOwner {
  capabilities:WireObject|undefined=undefined
  binding:WireObject|undefined=undefined
  stored:CompanionRecallRecord|undefined=undefined
  busy:boolean=false
  private host:string
  private transport:CompanionRecallTransport
  private storage:CompanionPrivatePreferences
  private uuid:()=>string
  private identity:number
  private active:boolean=true
  constructor(host:string,transport:CompanionRecallTransport,storage:CompanionPrivatePreferences,uuid:()=>string){this.host=host;this.transport=transport;this.storage=storage;this.uuid=uuid;this.identity=transport.identity()}
  current():boolean{return this.active&&this.identity===this.transport.identity()}
  close():void{this.active=false}
  private check():void{if(!this.current())throw new Error('主机已变更，请重新打开自动回忆设置')}
  private key():string{return 'recall-binding:'+this.host}
  sealed(sessionId:string):boolean{return this.stored?.session===sessionId||this.binding?.['sessionId']===sessionId}
  async load():Promise<void>{const raw=await this.storage.read(this.key());this.check();if(raw!==undefined){try{this.stored=companionRecallRecord(JSON.parse(raw))}catch{throw new Error('自动回忆记录损坏，请先核对主机绑定')};if(!this.stored)throw new Error('自动回忆记录损坏，请先核对主机绑定')}
    const caps=await this.transport.call('GET','/recall');this.check();if(caps===null){this.capabilities=undefined;return};this.capabilities=companionRecallCapabilities(caps);if(this.stored&&!this.stored.off){try{this.binding=companionRecallBinding(object(await this.transport.call('GET','/recall/bindings/'+this.stored.binding)),true);this.check();if(this.binding['bindingId']!==this.stored.binding||this.binding['sessionId']!==this.stored.session)throw new Error('自动回忆绑定已变更')}catch(error){this.check();if(!companionRecallGone(error as Object))throw error as Error;const record:CompanionRecallRecord={binding:this.stored.binding,session:this.stored.session,off:true};await this.storage.write(this.key(),JSON.stringify(record));this.check();this.stored=record;this.binding=undefined}}
  }
  async bind(storeId:string,memoryRevision:number,sessionId:string,confirmed:boolean,cleanSession:boolean):Promise<void>{
    this.check();if(this.busy||!confirmed||!cleanSession||!this.capabilities||this.capabilities['supported']!==true||this.capabilities['busy']===true||!UUID.test(storeId)||!natural(memoryRevision)||!session(sessionId))throw new Error('请在干净的伙伴会话中明确确认启用自动回忆')
    this.busy=true;try{let consumer=await this.storage.read('recall-consumer');this.check();if(!consumer||!UUID.test(consumer)){consumer=this.uuid();if(!UUID.test(consumer))throw new Error('设备回忆标识无效');await this.storage.write('recall-consumer',consumer);this.check()}
      const operation=this.uuid();if(!UUID.test(operation))throw new Error('自动回忆操作标识无效')
      const args:WireObject={'v':1,'operationId':operation,'storeId':storeId,'expectedMemoryRevision':memoryRevision,'sessionId':sessionId,'consumerId':consumer,'consent':COMPANION_RECALL_SELECTOR}
      const value=companionRecallBinding(object(await this.transport.call('POST','/recall/bind',args)));this.check();if(value['storeId']!==storeId||value['sessionId']!==sessionId||value['status']==='ready'&&value['memoryRevision']!==memoryRevision)throw new Error('主机确认了不同的回忆目标')
      this.binding=value;const record:CompanionRecallRecord={binding:string(value['bindingId']),session:sessionId,off:value['status']!=='ready'};this.stored=record;await this.storage.write(this.key(),JSON.stringify(record));this.check()
    }finally{this.busy=false}
  }
  async revoke(confirmed:boolean):Promise<void>{this.check();if(this.busy||!confirmed||!this.capabilities)throw new Error('请确认关闭自动回忆');const id=this.stored?.binding||string(this.capabilities['activeBindingId']);if(!UUID.test(id))throw new Error('没有可撤销的回忆绑定');this.busy=true
    try{const operation=this.uuid();if(!UUID.test(operation))throw new Error('自动回忆操作标识无效');const args:WireObject={'v':1,'operationId':operation,'bindingId':id,'reason':'user-off'};let value:WireObject|undefined=undefined;try{value=companionRecallBinding(object(await this.transport.call('POST','/recall/revoke',args)));this.check();if(value['bindingId']!==id||value['status']!=='retired')throw new Error('主机未确认自动回忆已关闭')}catch(error){this.check();if(!companionRecallGone(error as Object)||this.stored?.binding!==id)throw error as Error}
      const record:CompanionRecallRecord={binding:id,session:value?string(value['sessionId']):this.stored!.session,off:true};await this.storage.write(this.key(),JSON.stringify(record));this.check();this.binding=value;this.stored=record
    }finally{this.busy=false}
  }
}
