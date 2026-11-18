import { array, object, string, number, WireObject } from '../dsh/DshWire'
export const COMPANION_INITIATIVE_WINDOW:number=86400000
export interface CompanionInitiativeClock { wallMs:number; monoMs:number; offsetMinutes?:number }
export interface CompanionInitiativeView { visible:boolean; resumed:boolean; blocked:boolean; enabled:boolean; accessible:boolean; contextKey:string }
export interface CompanionInitiativePace { maxPerDay:number; gapMs:number; quietMs:number }
export function companionInitiativePace(name:string):CompanionInitiativePace{return name==='chatty'?{maxPerDay:12,gapMs:1800000,quietMs:20000}:name==='often'?{maxPerDay:6,gapMs:7200000,quietMs:30000}:{maxPerDay:2,gapMs:21600000,quietMs:45000}}
interface Night { offsetMinutes:number; stableAfterMs:number; lastNightKey:string|null; lastNightAtMs:number|null; lastNightOffsetMinutes:number|null; changedSinceLast:boolean }
interface Record { v:number; lastGreetingAtMs:number|null; inviteAtMs:number[]; signalAtMs:number[]; declinedUntilMs:number; night:Night|null }
interface Stay { id:number; interacted:boolean; invited:boolean }
interface Ticket { id:string; kind:string; ownerEpoch:number; stayId:number; contextKey:string; signalId?:string }
interface Display { ticket:Ticket; committedAtWallMs:number; expiresAtMono:number|null }
export interface CompanionInitiativeSignal { id:string; contextKey:string; expiresAtMonoMs:number; nightKey?:string }
interface State { record:Record|null; fault:string|null; lastNow:CompanionInitiativeClock; inRoom:boolean; outsideSinceMono:number|null; view:CompanionInitiativeView|null; ownerEpoch:number; nextStay:number; nextTicket:number; stay:Stay|null; quietSinceMono:number|null; ticket:Ticket|null; display:Display|null; signal:CompanionInitiativeSignal|null; nightCareEnabled:boolean; signalQuietSinceMono:number|null; optionalMonos:number[]; declinedUntilMono:number }
function wire(value:Object):WireObject{return object(JSON.parse(JSON.stringify(value)))}
function natural(value:Object|null|undefined):boolean{return typeof value==='number'&&Number.isSafeInteger(value)&&value>=0}
function validClock(now:CompanionInitiativeClock):boolean{const offset=now.offsetMinutes??0;return natural(now.wallMs)&&natural(now.monoMs)&&Number.isInteger(offset)&&offset>=-840&&offset<=840&&now.wallMs<=8640000000000000-3*86400000&&now.monoMs<=Number.MAX_SAFE_INTEGER-86400000}
export function companionNightKey(wall:number,offset:number=0):string|null{const local=new Date(wall+offset*60000),h=local.getUTCHours();if(h>=7&&h<23)return null;if(h<7)local.setUTCDate(local.getUTCDate()-1);return local.toISOString().slice(0,10)}
function nextNight(now:CompanionInitiativeClock):number{const local=new Date(now.wallMs+(now.offsetMinutes??0)*60000);let next=Date.UTC(local.getUTCFullYear(),local.getUTCMonth(),local.getUTCDate(),23)-(now.offsetMinutes??0)*60000;if(next<=now.wallMs)next+=86400000;return next}
function readNight(value:Object|null|undefined):Night|null{
  const raw=object(value),keys=['offsetMinutes','stableAfterMs','lastNightKey','lastNightAtMs','lastNightOffsetMinutes','changedSinceLast'];if(Object.keys(raw).length!==6||Object.keys(raw).some((k:string)=>!keys.includes(k)))return null
  const offset=raw['offsetMinutes'],last=raw['lastNightOffsetMinutes'],at=raw['lastNightAtMs'];if(typeof offset!=='number'||!Number.isInteger(offset)||Math.abs(offset)>840||!natural(raw['stableAfterMs'])||typeof raw['changedSinceLast']!=='boolean')return null
  if(at===null){if(raw['lastNightKey']!==null||last!==null)return null}else{if(!natural(at)||typeof last!=='number'||!Number.isInteger(last)||Math.abs(last)>840||typeof raw['lastNightKey']!=='string')return null;try{if(companionNightKey(at as number,last)!==raw['lastNightKey'])return null}catch{return null};if(raw['changedSinceLast']!==true&&offset!==last)return null}
  return JSON.parse(JSON.stringify(raw)) as Night
}
function readRecord(value:Object|null|undefined):Record|null{
  const raw=object(value),v=raw['v'],keys=v===1?['v','lastGreetingAtMs','inviteAtMs','declinedUntilMs']:['v','lastGreetingAtMs','inviteAtMs','declinedUntilMs','signalAtMs','night'];if(![1,2].includes(number(v,0))||Object.keys(raw).length!==keys.length||Object.keys(raw).some((k:string)=>!keys.includes(k))||raw['lastGreetingAtMs']!==null&&!natural(raw['lastGreetingAtMs'])||!natural(raw['declinedUntilMs']))return null
  const times=(value:Object|null|undefined):number[]|undefined=>{if(!Array.isArray(value)||array(value).length>12)return undefined;const result:number[]=[];for(const v of array(value)){if(!natural(v)||result.length&&number(v,0)-result[result.length-1]<1800000)return undefined;result.push(number(v,0))};return result}
  const invites=times(raw['inviteAtMs']),signals=v===1?[]:times(raw['signalAtMs']);if(!invites||!signals)return null;const all=invites.concat(signals).sort((a:number,b:number)=>a-b);if(all.length>12||all.some((v:number,i:number)=>i>0&&v-all[i-1]<1800000))return null
  const night=raw['night']===null||raw['night']===undefined?null:readNight(raw['night']);if(raw['night']!==null&&raw['night']!==undefined&&!night)return null
  return{v:2,lastGreetingAtMs:raw['lastGreetingAtMs']===null?null:number(raw['lastGreetingAtMs'],0),inviteAtMs:invites,signalAtMs:signals,declinedUntilMs:number(raw['declinedUntilMs'],0),night:night}
}
export class CompanionInitiativePresentation {
  before:State
  after:State
  effects:WireObject[]
  used:boolean=false
  owner:CompanionInitiativeController
  constructor(owner:CompanionInitiativeController,before:State,after:State,effects:WireObject[]){this.owner=owner;this.before=before;this.after=after;this.effects=effects}
  get display():WireObject{return object(this.effects.find((v:WireObject)=>v['type']==='show')?.['display'])}
  get record():WireObject|undefined{return this.after.record?wire(this.after.record):undefined}
}
export class CompanionInitiativeController {
  pace:CompanionInitiativePace=companionInitiativePace('rare')
  private state:State
  private quietHours:boolean
  constructor(now:CompanionInitiativeClock,restored:string='unavailable',value?:Object,quietHours:boolean=true){
    if(!validClock(now))throw new Error('Invalid initiative clock');this.quietHours=quietHours
    let record:Record|null=null,fault:string|null=null
    if(restored==='new')record={v:2,lastGreetingAtMs:null,inviteAtMs:[],signalAtMs:[],declinedUntilMs:0,night:null}
    else if(restored!=='loaded')fault='ledger-unavailable'
    else{record=readRecord(value);if(!record)fault='ledger-invalid';else if(record.lastGreetingAtMs!==null&&record.lastGreetingAtMs>now.wallMs||record.inviteAtMs.concat(record.signalAtMs).some((v:number)=>v>now.wallMs)||record.night?.lastNightAtMs!==null&&record.night?.lastNightAtMs!==undefined&&record.night!.lastNightAtMs!>now.wallMs)fault='history-in-future'}
    this.state={record:record,fault:fault,lastNow:now,inRoom:false,outsideSinceMono:null,view:null,ownerEpoch:0,nextStay:1,nextTicket:1,stay:null,quietSinceMono:null,ticket:null,display:null,signal:null,nightCareEnabled:false,signalQuietSinceMono:null,optionalMonos:record?record.inviteAtMs.concat(record.signalAtMs).sort((a:number,b:number)=>a-b).map((t:number)=>now.monoMs-(now.wallMs-t)):[],declinedUntilMono:record?now.monoMs+Math.max(0,record.declinedUntilMs-now.wallMs):0}
  }
  get fault():string|null{return this.state.fault}
  get record():WireObject|undefined{return this.state.record?wire(this.state.record):undefined}
  get offer():WireObject|undefined{return this.state.ticket?wire(this.state.ticket):undefined}
  get display():WireObject|undefined{return this.state.display?this.displayJson(this.state.display):undefined}
  private displayJson(d:Display):WireObject{const v=wire(d.ticket);v['committedAtWallMs']=d.committedAtWallMs;v['expiresAtMono']=d.expiresAtMono;return v}
  inspect():WireObject{const s=this.state,clock:WireObject={'wallMs':s.lastNow.wallMs,'monoMs':s.lastNow.monoMs};return{'record':s.record?wire(s.record):null,'fault':s.fault,'lastNow':clock,'inRoom':s.inRoom,'outsideSinceMono':s.outsideSinceMono,'view':s.view?wire(s.view):null,'ownerEpoch':s.ownerEpoch,'nextStay':s.nextStay,'nextTicket':s.nextTicket,'stay':s.stay?wire(s.stay):null,'quietSinceMono':s.quietSinceMono,'ticket':s.ticket?wire(s.ticket):null,'display':s.display?this.displayJson(s.display):null}}
  private eligible(s:State):boolean{return !s.fault&&s.inRoom&&!!s.view?.visible&&s.view.resumed&&!s.view.blocked&&s.view.enabled}
  private quietEligible(s:State):boolean{return this.eligible(s)&&!!s.stay&&!s.stay.interacted&&!s.stay.invited}
  private persist(s:State,e:WireObject[]):void{e.push({'type':'persist','value':s.record?wire(s.record):null})}
  private cancel(s:State,e:WireObject[],reason:string):void{if(s.ticket)e.push({'type':'cancelOffer','ticketId':s.ticket.id,'reason':reason});if(s.display)e.push({'type':'hide','ticketId':s.display.ticket.id,'reason':reason});s.ticket=null;s.display=null;s.signal=null;s.signalQuietSinceMono=null}
  private block(s:State,e:WireObject[],reason:string):void{s.fault=s.fault||reason;s.quietSinceMono=null;this.cancel(s,e,reason)}
  private expiry(s:State,ticket:Ticket,now:CompanionInitiativeClock):number|null{const usual=s.view!.accessible?null:now.monoMs+8000;if(ticket.kind!=='signal')return usual;const expiry=s.signal!.expiresAtMonoMs;return usual===null||expiry<usual?expiry:usual}
  private applyView(s:State,view:CompanionInitiativeView,now:CompanionInitiativeClock,e:WireObject[]):void{
    if(!view.contextKey)throw new Error('Expected nonempty context key');if(s.view?.contextKey!==view.contextKey){s.ownerEpoch++;s.quietSinceMono=null;this.cancel(s,e,'context-changed')};const old=s.view?.accessible;s.view=view
    if(!this.eligible(s)){s.quietSinceMono=null;this.cancel(s,e,'not-presentable')}else if(s.display&&old!==view.accessible){s.display.expiresAtMono=this.expiry(s,s.display.ticket,now);e.push({'type':'updateTimeout','ticketId':s.display.ticket.id,'expiresAtMono':s.display.expiresAtMono})}
  }
  private offerTicket(s:State,kind:string,e:WireObject[]):void{if(s.ticket||s.display)return;s.ticket={id:String(s.nextTicket++),kind:kind,ownerEpoch:s.ownerEpoch,stayId:s.stay!.id,contextKey:s.view!.contextKey};if(kind==='signal')s.ticket.signalId=s.signal?.id;e.push({'type':'offer','ticket':wire(s.ticket)})}
  private greetingAllows(s:State,wall:number):boolean{return!!s.record&&(s.record.lastGreetingAtMs===null||wall-s.record.lastGreetingAtMs>=1800000)}
  private inviteAllows(s:State,wall:number):boolean{const r=s.record;if(!r||wall<r.declinedUntilMs||s.lastNow.monoMs<s.declinedUntilMono)return false;const all=r.inviteAtMs.concat(r.signalAtMs).sort((a:number,b:number)=>a-b),mono=s.optionalMonos.filter((v:number)=>v>s.lastNow.monoMs-86400000);return all.filter((v:number)=>v>wall-86400000).length<this.pace.maxPerDay&&(!all.length||wall-all[all.length-1]>=this.pace.gapMs)&&mono.length<this.pace.maxPerDay&&(!s.optionalMonos.length||s.lastNow.monoMs-s.optionalMonos[s.optionalMonos.length-1]>=this.pace.gapMs)}
  private day(now:CompanionInitiativeClock):boolean{return!this.quietHours||companionNightKey(now.wallMs,now.offsetMinutes??0)===null}
  private signalAllows(s:State,now:CompanionInitiativeClock):boolean{const c=s.signal;if(!c||!this.eligible(s)||s.signalQuietSinceMono===null||now.monoMs-s.signalQuietSinceMono<this.pace.quietMs||now.monoMs>=c.expiresAtMonoMs||c.contextKey!==s.view?.contextKey||!this.inviteAllows(s,now.wallMs))return false
    if(c.nightKey){const n=s.record?.night;return s.nightCareEnabled&&!!n&&n.offsetMinutes===(now.offsetMinutes??0)&&now.wallMs>=n.stableAfterMs&&c.nightKey===companionNightKey(now.wallMs,now.offsetMinutes??0)&&c.nightKey!==n.lastNightKey&&(!n.changedSinceLast||n.lastNightAtMs===null||now.wallMs-n.lastNightAtMs>=86400000)}return this.day(now)
  }
  private userAction(s:State,e:WireObject[]):void{if(!s.inRoom||!s.stay)return;s.stay.interacted=true;s.quietSinceMono=null;this.cancel(s,e,'user-action')}
  private currentOptional(s:State,id:string):boolean{return!!s.display&&s.display.ticket.id===id&&s.display.ticket.kind!=='greeting'&&s.display.ticket.ownerEpoch===s.ownerEpoch&&s.display.ticket.stayId===s.stay?.id}
  private retireSignal(s:State,e:WireObject[],reason:string):void{const id=s.signal?.id;if(!id)return;if(s.ticket?.signalId===id){e.push({'type':'cancelOffer','ticketId':s.ticket.id,'reason':reason});s.ticket=null};if(s.display?.ticket.signalId===id){e.push({'type':'hide','ticketId':s.display.ticket.id,'reason':reason});s.display=null};s.signal=null}
  private expire(s:State,now:CompanionInitiativeClock,e:WireObject[]):void{if(s.signal&&(now.monoMs>=s.signal.expiresAtMonoMs||s.signal.contextKey!==s.view?.contextKey||s.signal.nightKey&&companionNightKey(now.wallMs,now.offsetMinutes??0)!==s.signal.nightKey))this.retireSignal(s,e,'signal-expired');if(s.display&&s.display.expiresAtMono!==null&&now.monoMs>=s.display.expiresAtMono){e.push({'type':'hide','ticketId':s.display.ticket.id,'reason':'timeout'});if(s.display.ticket.kind==='signal')s.signal=null;s.display=null}}
  handle(event:WireObject,now:CompanionInitiativeClock):WireObject[]{
    const s=JSON.parse(JSON.stringify(this.state)) as State,e:WireObject[]=[],type=string(event['type']);if(!validClock(now)||now.monoMs<s.lastNow.monoMs||now.wallMs<s.lastNow.wallMs||this.quietHours&&Math.abs(now.wallMs-s.lastNow.wallMs-(now.monoMs-s.lastNow.monoMs))>1000){this.block(s,e,'clock-invalid-or-regressed');this.state=s;return e}
    if(this.quietHours&&!s.fault&&s.record){let n=s.record.night;if(!n){n={offsetMinutes:s.lastNow.offsetMinutes??0,stableAfterMs:0,lastNightKey:null,lastNightAtMs:null,lastNightOffsetMinutes:null,changedSinceLast:false};s.record.night=n;this.persist(s,e)}if(n.offsetMinutes!==(now.offsetMinutes??0)){n.offsetMinutes=now.offsetMinutes??0;n.stableAfterMs=Math.max(n.stableAfterMs,nextNight(now));n.changedSinceLast=true;this.persist(s,e)}}s.lastNow=now
    const viewEvent=type==='enter'||type==='observe';if(!viewEvent)this.expire(s,now,e)
    if(type==='enter'){const before=s.inRoom,newStay=!s.stay||!before&&s.outsideSinceMono!==null&&now.monoMs-s.outsideSinceMono>=1800000;if(!before){s.inRoom=true;s.ownerEpoch++;s.quietSinceMono=null;this.cancel(s,e,'enter')};s.outsideSinceMono=null;this.applyView(s,JSON.parse(JSON.stringify(event['view'])) as CompanionInitiativeView,now,e);if(newStay){s.stay={id:s.nextStay++,interacted:false,invited:false};if(this.eligible(s)&&this.greetingAllows(s,now.wallMs))this.offerTicket(s,'greeting',e)}}
    else if(type==='leave'){if(s.inRoom){s.inRoom=false;s.outsideSinceMono=now.monoMs;s.ownerEpoch++;s.quietSinceMono=null;this.cancel(s,e,'leave')}}
    else if(type==='observe')this.applyView(s,JSON.parse(JSON.stringify(event['view'])) as CompanionInitiativeView,now,e)
    else if(type==='userActivation')this.userAction(s,e)
    else if(type==='dropOffer'){if(s.ticket?.id===event['ticketId']){e.push({'type':'cancelOffer','ticketId':s.ticket!.id,'reason':'adapter-discarded'});if(s.ticket!.kind==='signal')s.signal=null;s.ticket=null}}
    else if(type==='decline'){if(s.inRoom&&(event['ticketId']===undefined||event['ticketId']===null||this.currentOptional(s,string(event['ticketId'])))){this.userAction(s,e);if(!s.fault&&s.record){s.record.declinedUntilMs=Math.max(s.record.declinedUntilMs,now.wallMs+this.pace.gapMs);s.declinedUntilMono=Math.max(s.declinedUntilMono,now.monoMs+this.pace.gapMs);this.persist(s,e)}}}
    else if(type==='accept'){if(this.eligible(s)&&this.currentOptional(s,string(event['ticketId']))&&s.display!.ticket.kind==='invite'){const t=s.display!.ticket;this.userAction(s,e);e.push({'type':'restIntent','ticketId':t.id,'contextKey':t.contextKey,'ownerEpoch':t.ownerEpoch})}}
    else if(type==='present'){const t=s.ticket;if(t&&t.id===event['ticketId']){s.ticket=null;const current=this.eligible(s)&&!s.display&&t.ownerEpoch===s.ownerEpoch&&t.stayId===s.stay?.id&&t.contextKey===s.view!.contextKey,allowed=current&&(t.kind==='greeting'?this.greetingAllows(s,now.wallMs):t.kind==='signal'?t.signalId===s.signal?.id&&this.signalAllows(s,now):this.quietEligible(s)&&s.quietSinceMono!==null&&now.monoMs-s.quietSinceMono>=this.pace.quietMs&&this.inviteAllows(s,now.wallMs)&&this.day(now));if(!allowed)e.push({'type':'cancelOffer','ticketId':t.id,'reason':'present-rejected'});else{const r=s.record!;if(t.kind==='greeting')r.lastGreetingAtMs=now.wallMs;else{r.inviteAtMs=r.inviteAtMs.filter((v:number)=>v>now.wallMs-86400000);r.signalAtMs=r.signalAtMs.filter((v:number)=>v>now.wallMs-86400000);if(t.kind==='signal'){r.signalAtMs.push(now.wallMs);if(s.signal!.nightKey&&r.night){r.night.lastNightKey=s.signal!.nightKey!;r.night.lastNightAtMs=now.wallMs;r.night.lastNightOffsetMinutes=now.offsetMinutes??0;r.night.changedSinceLast=false}}else{r.inviteAtMs.push(now.wallMs);s.stay!.invited=true};s.optionalMonos=s.optionalMonos.filter((v:number)=>v>now.monoMs-86400000).concat(now.monoMs)}s.display={ticket:t,committedAtWallMs:now.wallMs,expiresAtMono:this.expiry(s,t,now)};e.push({'type':'show','display':this.displayJson(s.display),'silent':t.kind!=='signal','autoAnnounce':false});this.persist(s,e)}}}
    else if(type==='signal'){if(event['view'])this.applyView(s,JSON.parse(JSON.stringify(event['view'])) as CompanionInitiativeView,now,e);const c=JSON.parse(JSON.stringify(event['signal'])) as CompanionInitiativeSignal;if(this.eligible(s)&&!s.display&&c.id&&c.contextKey===s.view!.contextKey&&c.expiresAtMonoMs>now.monoMs&&c.expiresAtMonoMs-now.monoMs<=120000&&s.signal?.id!==c.id){if(s.ticket&&['invite','signal'].includes(s.ticket.kind)){e.push({'type':'cancelOffer','ticketId':s.ticket.id,'reason':'signal-replaced-offer'});s.ticket=null};s.signal=c;s.nightCareEnabled=event['nightCareEnabled']===true}}
    else if(type==='cancelSignal'){if(s.signal?.id===event['signalId'])this.retireSignal(s,e,'signal-withdrawn')}
    else if(type==='storageFault')this.block(s,e,'storage-failed')
    if(viewEvent)this.expire(s,now,e)
    if(!this.quietEligible(s))s.quietSinceMono=null;else if(s.quietSinceMono===null)s.quietSinceMono=now.monoMs
    if(!this.eligible(s))s.signalQuietSinceMono=null;else if(s.signalQuietSinceMono===null)s.signalQuietSinceMono=now.monoMs
    if(viewEvent||type==='check'||type==='signal'){if(this.signalAllows(s,now))this.offerTicket(s,'signal',e);if(!s.signal&&this.quietEligible(s)&&this.day(now)&&s.quietSinceMono!==null&&now.monoMs-s.quietSinceMono>=this.pace.quietMs&&this.inviteAllows(s,now.wallMs))this.offerTicket(s,'invite',e)}this.state=s;return e
  }
  stagePresentation(ticketId:string,now:CompanionInitiativeClock):CompanionInitiativePresentation|undefined{const before=this.state,event:WireObject={'type':'present','ticketId':ticketId},effects=this.handle(event,now),after=this.state;this.state=before;if(!effects.some((v:WireObject)=>v['type']==='show')){if(after.fault)this.state=after;return undefined}return new CompanionInitiativePresentation(this,before,after,effects)}
  commitPresentation(value:CompanionInitiativePresentation):WireObject[]{if(value.owner!==this||value.used||value.before!==this.state)return[];value.used=true;this.state=value.after;return value.effects}
}
