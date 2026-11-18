import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { DshClient } from '../dsh/DshClient'
import { DshRpcError, DshChatUpdate, number, object, string, WireObject } from '../dsh/DshWire'
import { CompanionPreferences, companionSystem } from './CompanionData'
import { CompanionRecallRecord, companionRecallRecord, companionRecallBinding, companionRecallGone } from './CompanionRecall'
import { companionPrivateRead, companionPrivateWrite, companionBinding } from './CompanionStore'
export class CompanionSession {
 client:DshClient|undefined=undefined
 id:string=''
 recallBinding:WireObject|undefined=undefined
 private parent:DshClient
 private context:common.Context
 private hostKey:string
 private generation:number=0
 private capability:WireObject|undefined=undefined
 private inline:boolean=false
 private told:boolean=false
 private pending:WireObject|undefined=undefined
 private pendingText:string=''
 private pendingRequest:string=''
 constructor(parent:DshClient,context:common.Context,hostKey:string){this.parent=parent;this.context=context;this.hostKey=hostKey}
 async open(onUpdate:(value:DshChatUpdate)=>void,onClose:(reason:string)=>void):Promise<void>{const generation=++this.generation,identity=this.parent.connectionIdentity();const client=await this.parent.forkConnection(onClose);if(generation!==this.generation||identity!==this.parent.connectionIdentity()){client.close();throw new Error('主机连接已变更')}this.client=client;let id=await companionBinding(this.context,this.hostKey)
 const recallRaw=await companionPrivateRead(this.context,'recall-binding:'+this.hostKey);if(recallRaw!==undefined){let record:CompanionRecallRecord|undefined;try{record=companionRecallRecord(JSON.parse(recallRaw))}catch{throw new Error('自动回忆记录损坏，请先核对主机绑定')}if(!record)throw new Error('自动回忆记录损坏，请先核对主机绑定');if(id===record.session){if(record.off){id='';await companionBinding(this.context,this.hostKey,'')}else{try{const status=companionRecallBinding(object(await client.companionJson('GET','/recall/bindings/'+record.binding)),true);if(status['bindingId']!==record.binding||status['sessionId']!==id)throw new Error('自动回忆绑定已变更');if(status['status']!=='ready'){record.off=true;await companionPrivateWrite(this.context,'recall-binding:'+this.hostKey,JSON.stringify(record));id='';await companionBinding(this.context,this.hostKey,'')}else this.recallBinding=status}catch(error){if(!companionRecallGone(error as Object))throw error as Error;record.off=true;await companionPrivateWrite(this.context,'recall-binding:'+this.hostKey,JSON.stringify(record));id='';await companionBinding(this.context,this.hostKey,'')}}}}
 if(id){const saved=await companionPrivateRead(this.context,'companion-inline:'+this.hostKey);if(saved!==undefined){try{const row=object(JSON.parse(saved));this.inline=row['id']===id&&row['inline']===true}catch{throw new Error('伙伴会话模式记录损坏')}}try{await client.sessionProjections(id)}catch(error){if(error instanceof DshRpcError&&error.code==='session/not-found')id='';else throw error as Error}}
 if(!id){this.inline=false;id=await client.createSession();const presets=await client.listAgentPresets();if(presets.some((p:WireObject)=>p['id']==='dsh-go-companion-full'&&!p['broken']))await client.selectAgentPreset(id,'dsh-go-companion-full');else this.inline=true;if(generation!==this.generation){client.close();return}await companionPrivateWrite(this.context,'companion-inline:'+this.hostKey,JSON.stringify({'id':id,'inline':this.inline} as WireObject));await companionBinding(this.context,this.hostKey,id)}
 this.id=id;await client.watchSession(id,(value:DshChatUpdate)=>{if(generation===this.generation){if(value.messages.some((m)=>m.role==='user'))this.told=true;if(this.pendingRequest&&value.messages.some((m)=>m.role==='user'&&m.requestId===this.pendingRequest)){this.pending=undefined;this.pendingRequest='';this.pendingText=''}onUpdate(value)}})
 if(this.inline)return;const capability=await client.companionJson('GET','/prompt-context',undefined,id);if(generation!==this.generation)return;if(capability!==null){const row=object(capability);if(row['v']!==1||row['supported']!==true||row['sessionId']!==id||!string(row['instanceId'])||!Number.isSafeInteger(row['profileRevision']))throw new Error('伙伴上下文能力响应无效');this.capability=row}
 }
 async send(text:string,prefs:CompanionPreferences,events:WireObject[]=[],moves:string='',current:()=>boolean=():boolean=>true):Promise<void>{const client=this.client;if(!client||!this.id)throw new Error('伙伴会话未连接');const generation=this.generation;if(!current())throw new Error('伙伴目标已变更');const requestId=this.pendingText===text&&this.pendingRequest?this.pendingRequest:util.generateRandomUUID();let prompt=text
 if(this.capability){const capability=this.capability;const update:WireObject=this.pendingText===text&&this.pending?this.pending:{'v':1,'sessionId':this.id,'requestId':requestId,'instanceId':capability['instanceId'],'expectedProfileRevision':capability['profileRevision'],'profile':{'persona':prefs.persona.trim(),'name':prefs.name.trim(),'callMe':prefs.callMe.trim(),'moves':moves.slice(0,1024)} as WireObject,'events':events} as WireObject;if(capability['memoryMode']!=='automatic')update['query']=Array.from(text.replace(/[\x00-\x1f\x7f]/g,' ')).slice(0,256).join('');this.pending=update;this.pendingText=text;this.pendingRequest=requestId;if(!current())throw new Error('伙伴目标已变更');const response=object(await client.companionJson('POST','/prompt-context',update));if(response['instanceId']!==capability['instanceId']||response['sessionId']!==this.id)throw new Error('伙伴主机已更换，请重新连接');this.capability=response}
 else if(this.inline&&!this.told)prompt='（从现在起请扮演下面的角色，直接开始，不要复述这段设定。）\n'+companionSystem(prefs,[],true,Date.now(),moves)+'\n\n'+text
 if(generation!==this.generation||!current())throw new Error('伙伴会话已关闭');await client.prompt(this.id,prompt,requestId);this.told=true
 }
 async refreshRecall():Promise<WireObject>{const previous=this.recallBinding,client=this.client,generation=this.generation;if(!previous||!client)throw new Error('当前伙伴没有就绪的自动回忆绑定');const value=companionRecallBinding(object(await client.companionJson('GET','/recall/bindings/'+string(previous['bindingId']))),true);if(generation!==this.generation||client!==this.client)throw new Error('伙伴目标已变更');this.recallBinding=value;return value}
 async revokeRecall():Promise<void>{const client=this.client;if(!client)return;const raw=await companionPrivateRead(this.context,'recall-binding:'+this.hostKey);if(raw===undefined)return;const record=companionRecallRecord(JSON.parse(raw));if(!record)throw new Error('自动回忆记录损坏，请先核对主机绑定');if(record.off)return;try{const value=companionRecallBinding(object(await client.companionJson('POST','/recall/revoke',{'v':1,'operationId':util.generateRandomUUID(),'bindingId':record.binding,'reason':'user-off'})));if(value['bindingId']!==record.binding||value['status']!=='retired')throw new Error('主机未确认自动回忆已关闭');this.recallBinding=value}catch(error){if(!companionRecallGone(error as Object))throw error as Error;this.recallBinding=undefined}record.off=true;await companionPrivateWrite(this.context,'recall-binding:'+this.hostKey,JSON.stringify(record))}
 async cancel():Promise<void>{if(this.client&&this.id)await this.client.cancel(this.id)}
 close():void{this.generation++;this.client?.close();this.client=undefined}
}
