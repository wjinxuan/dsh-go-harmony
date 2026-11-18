import { systemDateTime } from '@kit.BasicServicesKit'
import { DshClient, DshSubscription } from '../dsh/DshClient'
import { array, object, string, number, WireObject } from '../dsh/DshWire'
import { CompanionSignalCapability, CompanionRunReceipt, CompanionSignal, signalMetadata, signalPhase, signalInt, signalId } from '../dsh/CompanionSignalProtocol'
import { CompanionConsent, CompanionConsentOwner, CompanionPrivatePreferences } from './CompanionConsent'
import { CompanionSignalGate, CompanionSignalSource, CompanionSignalIngress, CompanionSignalEvidence, CompanionSignalSlot, CompanionSignalSpeech, CompanionSignalPreview, CompanionSignalShareTarget, CompanionSignalLateUse } from './CompanionSignalsData'
export interface CompanionSignalsView { status:string; error:string; consent:CompanionConsent|undefined; slots:CompanionSignalSlot[]; speech:CompanionSignalSpeech|undefined; overflow:number; runAvailable:boolean }
export class CompanionSignals {
 readonly gate:CompanionSignalGate
 readonly recipient:WireObject={}
 readonly consent:CompanionConsentOwner
 private client:DshClient|undefined
 private hostKey:string
 private change:(view:CompanionSignalsView)=>void
 private clock:()=>number
 private excluded:(session:string)=>boolean
 private epoch:WireObject={}
 private source:CompanionSignalSource|undefined=undefined
 private localSource:CompanionSignalSource
 private localIngress:CompanionSignalIngress|undefined=undefined
 private ingress:CompanionSignalIngress|undefined=undefined
 private runStop:DshSubscription|undefined=undefined
 private hostStop:DshSubscription|undefined=undefined
 private active:boolean=true
 private foreground:boolean=true
 private sceneActive:boolean=true
 private version:number=0
 private timer:number=-1
 private status:string='unread'
 private error:string=''
 private capability:CompanionSignalCapability|undefined=undefined
 private running:Map<string,boolean>=new Map()
 private revisions:Map<string,number>=new Map()
 private pending:Map<string,CompanionSignal>=new Map()
 private excludedChildren:Set<string>=new Set()
 private late:CompanionSignalLateUse=new CompanionSignalLateUse()
 private language:string='zh'
 constructor(client:DshClient|undefined,storage:CompanionPrivatePreferences,hostKey:string,onChange:(view:CompanionSignalsView)=>void,
   excluded:(session:string)=>boolean=():boolean=>false,clock:()=>number=():number=>systemDateTime.getUptime(systemDateTime.TimeType.STARTUP,false)){
  this.client=client;this.hostKey=hostKey;this.change=onChange;this.excluded=excluded;this.clock=clock;this.gate=new CompanionSignalGate(clock);this.consent=new CompanionConsentOwner(storage);
  this.localSource={hostKey:'local-device',client:undefined,connection:0,capability:undefined,generation:():number=>0,attached:():boolean=>this.active&&this.foreground&&this.sceneActive,local:true}
 }
 setLanguage(language:string):void{this.language=language==='en'?'en':'zh'}
 async start(foreground:boolean=true,sceneActive:boolean=true):Promise<void>{if(!this.active)return;this.foreground=foreground;this.sceneActive=sceneActive;await this.consent.load();if(!this.active)return;await this.attach()}
 close():void{if(!this.active)return;this.active=false;this.retire();this.gate.leave();clearInterval(this.timer)}
 setSceneActive(value:boolean):void{if(value===this.sceneActive||!this.active)return;this.sceneActive=value;this.late.observe(Date.now(),this.clock(),-new Date().getTimezoneOffset(),value&&this.foreground);this.retire();this.gate.leave();this.status=value?'paused':'scene-inactive';this.notify();void this.attach()}
 setForeground(value:boolean):void{if(value===this.foreground||!this.active)return;this.late.observe(Date.now(),this.clock(),-new Date().getTimezoneOffset(),value&&this.sceneActive);this.foreground=value;this.retire();this.gate.leave();this.status=value?'paused':'background';this.notify();if(value)void this.attach()}
 async setConsent(value:CompanionConsent):Promise<void>{this.retire();this.gate.leave();const save=this.consent.set(value);this.status='saving';this.notify();try{await save;this.error=''}catch(error){this.error=error instanceof Error?error.message:'伙伴信号设置保存失败'}if(this.active)await this.attach()}
 async refresh():Promise<void>{if(!this.active)return;if(!this.consent.value)await this.consent.load();if(this.active)await this.attach()}
 interact():void{if(this.active&&this.foreground&&this.sceneActive)this.late.observe(Date.now(),this.clock(),-new Date().getTimezoneOffset(),this.foreground,true)}
 private retire():void{this.version++;this.runStop?.();this.hostStop?.();this.runStop=undefined;this.hostStop=undefined;if(this.source)this.gate.detach(this.source);this.source=undefined;this.ingress=undefined;this.localIngress=undefined;this.capability=undefined;this.pending.clear();this.running.clear();this.revisions.clear();this.excludedChildren.clear();clearInterval(this.timer);this.timer=-1}
 private notify(speech?:CompanionSignalSpeech):void{if(!this.active)return;const value:CompanionSignalsView={status:this.status,error:this.error,consent:this.consent.value,slots:this.gate.slots(),speech:speech,overflow:this.gate.overflow(this.hostKey),runAvailable:!!this.capability?.available&&this.status==='live'};this.change(value)}
 private allowed(source:CompanionSignalSource,version:number):boolean{return this.active&&this.foreground&&this.sceneActive&&this.version===version&&this.source===source&&this.consent.value?.state===true&&(!source.client||source.generation()===source.connection)}
 private async attach():Promise<void>{this.retire();this.gate.leave();const version=this.version;if(!this.active||!this.foreground){this.status='background';this.notify();return}const consent=this.consent.value;if(!consent){this.status='unread';this.notify();return}if(!this.sceneActive){await this.inspectInactiveCapability(version);return}this.epoch={};this.gate.enter(this.recipient,this.epoch);this.gate.setConsent(this.localSource,consent);if(!consent.state){this.status='off';this.notify();return}const client=this.client;this.status=client?'loading':'producer-unavailable';
  let source:CompanionSignalSource|undefined=undefined;
  if(client){try{client.webSession();source={hostKey:this.hostKey,client:client,connection:client.connectionIdentity(),capability:undefined,generation:():number=>client.connectionIdentity(),attached:():boolean=>!!source&&this.allowed(source,version),local:false};this.source=source;this.gate.setConsent(source,consent)}catch{this.status='engine-unavailable'}}
  this.localIngress=this.gate.open(this.localSource);this.notify();this.timer=setInterval(()=>{if(!this.active||version!==this.version)return;if(this.source&&this.source.generation()!==this.source.connection){this.retire();this.gate.leave();this.status='connection-changed';this.notify();return}this.observeLate();this.notify()},1000);
  if(!source||!client)return;
  const captured=source;
  // Only live mux callbacks create task evidence; session reads are tied to an actual idle edge.
  this.ingress=this.gate.open(captured);const ingress=this.ingress;
  if(ingress)this.hostStop=client.onHostEvent((event:WireObject)=>{if(this.allowed(captured,version)&&this.gate.current(ingress))void this.hostEvent(event,captured,ingress,version)});
  try{const sessions=await client.listSessions(false,true);if(this.allowed(captured,version))for(const session of sessions)if(session.parentSessionId)this.excludedChildren.add(session.id)}catch{}
  try{const capability=await client.companionSignalCapabilities();if(!this.allowed(captured,version))return;this.capability=capability;captured.capability=capability;if(!capability||!capability.available){this.status=capability?.reason||'absent';this.notify();return}this.status='connecting';this.notify();if(!ingress)return;
   this.runStop=client.companionSignalEvents(capability,this.hostKey,():boolean=>this.allowed(captured,version)&&this.gate.current(ingress),this.clock,(receipt:CompanionRunReceipt):void=>{if(!this.allowed(captured,version)||this.exclude(string(receipt.signal.source['sessionId'])))return;const result=this.gate.receiveRun(ingress,receipt);this.received(result,receipt.signal)},(reason:string):void=>{if(!this.allowed(captured,version))return;this.status=reason==='producer-unavailable'||reason==='engine-unavailable'?reason:'closed';this.error=this.status==='closed'?reason:'';this.notify()},():void=>{if(this.allowed(captured,version)){this.status='live';this.notify()}})
  }catch(error){if(this.allowed(captured,version)){this.status='error';this.error=error instanceof Error?error.message:'伙伴信号读取失败';this.notify()}}
 }
 private async inspectInactiveCapability(version:number):Promise<void>{
  const client=this.client,connection=client?.connectionIdentity();this.status=client?'loading':'scene-inactive';this.notify();if(!client)return
  const current=():boolean=>this.active&&this.foreground&&!this.sceneActive&&this.version===version&&this.client===client&&client.connectionIdentity()===connection
  try{client.webSession();const capability=await client.companionSignalCapabilities();if(!current())return;this.capability=capability;this.status=capability?.available?'scene-inactive':capability?.reason||'absent';this.error='';this.notify()}
  catch(error){if(current()){this.status='error';this.error=error instanceof Error?error.message:'伙伴信号读取失败';this.notify()}}
 }
 private exclude(session:string):boolean{return this.excludedChildren.has(session)||this.excluded(session)}
 private received(result:string,signal:CompanionSignal):void{if(result==='accepted'){const slot=this.gate.slots().find((item:CompanionSignalSlot)=>item.signal===signal);this.notify(slot?this.gate.speech(slot,this.language):undefined)}else this.notify()}
 private evidence(source:CompanionSignalSource,ingress:CompanionSignalIngress,version:number,received:number,pending?:()=>boolean):CompanionSignalEvidence{return{received:received,current:():boolean=>this.allowed(source,version)&&this.gate.current(ingress),local:():boolean=>this.allowed(source,version),pending:pending}}
 private async hostEvent(event:WireObject,source:CompanionSignalSource,ingress:CompanionSignalIngress,version:number):Promise<void>{const received=this.clock(),observed=new Date().toISOString(),type=string(event['type']);
  try{if(type==='waterfall'&&['approval/request','user-questions/request'].includes(string(event['event']))){const request=object(event['request']),session=string(request['sessionId']),id=string(event['eventId']);if(!signalId(session)||!signalId(id)||this.exclude(session))return;const src:WireObject={'type':'dsh','hostKey':this.hostKey,'sessionId':session,'requestId':id},payload:WireObject={'requestId':id,'openSessionId':session,'requestKind':event['event']==='approval/request'?'approval':'question'},raw:WireObject={'v':1,'id':'waiting:'+id,'kind':'task.approval_waiting','source':src,'observedAt':observed,'freshness':'live','payload':payload};const signal=signalMetadata(raw);this.pending.set(id,signal);this.received(this.gate.receive(ingress,signal,this.evidence(source,ingress,version,received,():boolean=>this.pending.get(id)===signal)),signal);return}
   if(type==='cancel'){const id=string(event['eventId']);if(!signalId(id))return;const old=this.pending.get(id);this.pending.delete(id);const src:WireObject={'type':'dsh','hostKey':this.hostKey,'sessionId':old?.source['sessionId']||null,'requestId':id},payload:WireObject={'requestId':id,'openSessionId':old?.payload['openSessionId']||null,'requestKind':old?.payload['requestKind']||'approval'},raw:WireObject={'v':1,'id':'clear:'+id,'kind':'task.approval_cleared','source':src,'observedAt':observed,'freshness':'live','payload':payload};const signal=signalMetadata(raw);this.received(this.gate.receive(ingress,signal,this.evidence(source,ingress,version,received)),signal);return}
   if(type!=='emit'||event['event']!=='api-session/status')return;const args=array(event['args']),session=string(args[0]);if(!signalId(session)||typeof args[1]!=='boolean'||this.exclude(session))return;const before=this.running.get(session),revision=(this.revisions.get(session)||0)+1;this.revisions.set(session,revision);this.running.set(session,args[1]===true);if(args[1]===true||before!==true)return;
   const page=await this.client!.sessionPage(session,undefined,1);if(!this.allowed(source,version)||!this.gate.current(ingress)||this.revisions.get(session)!==revision||this.running.get(session)!==false)return;
   for(let i=page.records.length-1;i>=0;i--){const record=page.records[i];if(record.type!=='turn/end')continue;const kind=string(object(record.data['reason'])['kind']),turn=signalInt(record.data['turn'],1)?record.data['turn']:null,src:WireObject={'type':'dsh','hostKey':this.hostKey,'sessionId':session,'seq':record.seq,'turn':turn},payload:WireObject={'phase':signalPhase(kind),'endKind':kind,'endSeq':record.seq,'turn':turn},raw:WireObject={'v':1,'id':session+':'+record.seq,'kind':'task.terminal','source':src,'payload':payload,'freshness':'live','observedAt':observed};const signal=signalMetadata(raw);const evidence=this.evidence(source,ingress,version,received);evidence.current=():boolean=>this.allowed(source,version)&&this.revisions.get(session)===revision&&this.running.get(session)===false&&this.gate.current(ingress);this.received(this.gate.receive(ingress,signal,evidence),signal);break}
  }catch{}
 }
 private observeLate():void{const now=this.clock(),payload=this.late.observe(Date.now(),now,-new Date().getTimezoneOffset(),this.foreground&&this.sceneActive);if(!payload||!this.consent.value?.nightCare||!this.localIngress)return;const source:WireObject={'type':'device'},raw:WireObject={'v':1,'id':'late-use:'+payload['nightKey']+':'+Math.floor(now/60000),'kind':'app.late_use','source':source,'payload':payload,'observedAt':new Date().toISOString(),'freshness':'live'};const signal=signalMetadata(raw),ingress=this.localIngress,evidence:CompanionSignalEvidence={received:now,current:():boolean=>this.active&&this.foreground&&this.sceneActive&&this.gate.current(ingress),local:():boolean=>this.active&&this.foreground&&this.sceneActive};this.received(this.gate.receive(ingress,signal,evidence),signal)}
 preview(slot:CompanionSignalSlot):CompanionSignalPreview|undefined{return this.gate.preview(slot,this.language)}
 async detail(slot:CompanionSignalSlot):Promise<CompanionSignalPreview|undefined>{return this.gate.detail(slot,async(client:Object,session:string,seq:number):Promise<string|undefined>=>{if(client!==this.client)return undefined;const page=await this.client.sessionPage(session,seq+1,1,seq);const record=page.records.find((item)=>item.seq===seq);if(!record)return undefined;const encoded=JSON.stringify(record.data);return encoded.length<=4096?encoded:undefined})}
 async share(preview:CompanionSignalPreview,target:CompanionSignalShareTarget,confirmed:boolean,send:(text:string,target:CompanionSignalShareTarget,current:()=>boolean)=>Promise<boolean>):Promise<boolean>{const permit=this.gate.approve(preview,target,confirmed);return !!permit&&await this.gate.dispatch(permit,send)}
}
