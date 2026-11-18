import { object, string, WireObject } from '../dsh/DshWire'
import { CompanionPrivatePreferences } from './CompanionConsent'
import { CompanionInitiativeClock, CompanionInitiativeController, CompanionInitiativeView, companionInitiativePace } from './CompanionInitiative'
export interface CompanionInitiativeCandidate { id:string; text:string; voice:boolean; nightCare:boolean; expiresAtMonoMs:number; nightKey?:string; current:()=>boolean; mood:string; action:string }
interface SignalPresentation { candidate:CompanionInitiativeCandidate; presented:(candidate:CompanionInitiativeCandidate)=>void; token:number }
export class CompanionInitiativeOwner {
  private storage:CompanionPrivatePreferences
  private clock:()=>CompanionInitiativeClock
  private controller?:CompanionInitiativeController
  private loading?:Promise<void>
  private listener?: (effect:WireObject)=>void
  private token:number=0
  private view?:CompanionInitiativeView
  private queue:Promise<void>=Promise.resolve()
  private pending:string=''
  private candidate?:SignalPresentation
  constructor(storage:CompanionPrivatePreferences,clock:()=>CompanionInitiativeClock){this.storage=storage;this.clock=clock}
  private async load():Promise<void>{try{const raw=await this.storage.read('initiative-ledger');let value:Object|undefined=undefined;if(raw!==undefined){try{value=JSON.parse(raw) as Object}catch{const invalid:WireObject={};value=invalid}};this.controller=new CompanionInitiativeController(this.clock(),raw===undefined?'new':'loaded',value)}catch{this.controller=new CompanionInitiativeController(this.clock(),'unavailable')}}
  async attach(view:CompanionInitiativeView,listener:(effect:WireObject)=>void):Promise<number>{
    if(this.listener&&this.controller)this.effects(this.controller.handle({'type':'leave'},this.clock()))
    this.candidate=undefined;const token=++this.token;this.listener=listener;this.view=view
    if(!this.loading)this.loading=this.load();await this.loading
    if(token===this.token)this.effects(this.controller!.handle({'type':'enter','view':object(JSON.parse(JSON.stringify(this.view)))},this.clock()))
    return token
  }
  detach(token:number):void{if(token!==this.token)return;if(this.controller)this.effects(this.controller.handle({'type':'leave'},this.clock()));this.listener=undefined;this.view=undefined;this.candidate=undefined;this.token++}
  update(token:number,view:CompanionInitiativeView,pace:string='rare'):void{if(token!==this.token||!this.listener)return;this.view=view;if(!this.controller)return;this.controller.pace=companionInitiativePace(pace);this.effects(this.controller.handle({'type':'observe','view':object(JSON.parse(JSON.stringify(view)))},this.clock()))}
  activate(token:number):void{if(token===this.token&&this.controller)this.effects(this.controller.handle({'type':'userActivation'},this.clock()))}
  tick(token:number):void{if(token!==this.token||!this.controller||!this.listener)return;this.pruneSignal();this.effects(this.controller.handle({'type':'check'},this.clock()))}
  answer(token:number,id:string,yes:boolean,view:CompanionInitiativeView):void{if(token!==this.token||!this.controller)return;this.update(token,view);this.effects(this.controller.handle({'type':yes?'accept':'decline','ticketId':id},this.clock()))}
  signal(token:number,candidate:CompanionInitiativeCandidate|undefined,presented:(candidate:CompanionInitiativeCandidate)=>void):void{
    if(token!==this.token||!this.controller||!this.view)return
    if(this.candidate?.candidate===candidate)return
    const previous=this.candidate;this.candidate=undefined
    if(previous)this.effects(this.controller.handle({'type':'cancelSignal','signalId':previous.candidate.id},this.clock()))
    if(!candidate)return
    const now=this.clock();if(!candidate.id||!candidate.text||candidate.text.length>512||!Number.isSafeInteger(candidate.expiresAtMonoMs)||candidate.expiresAtMonoMs<=now.monoMs||candidate.expiresAtMonoMs-now.monoMs>120000)return
    try{if(!candidate.current())return}catch{return}
    this.candidate={candidate:candidate,presented:presented,token:token}
    const value:WireObject={'id':candidate.id,'contextKey':this.view.contextKey,'expiresAtMonoMs':candidate.expiresAtMonoMs};if(candidate.nightKey)value['nightKey']=candidate.nightKey
    this.effects(this.controller.handle({'type':'signal','signal':value,'nightCareEnabled':candidate.nightCare,'view':object(JSON.parse(JSON.stringify(this.view)))},now))
  }
  private signalCurrent(id:string):boolean{const value=this.candidate;if(!value||value.token!==this.token||value.candidate.id!==id||this.clock().monoMs>=value.candidate.expiresAtMonoMs)return false;try{return value.candidate.current()}catch{return false}}
  private pruneSignal():void{const value=this.candidate;if(value&&!this.signalCurrent(value.candidate.id)){this.candidate=undefined;this.effects(this.controller!.handle({'type':'cancelSignal','signalId':value.candidate.id},this.clock()))}}
  private write(record:WireObject):Promise<void>{const run=this.queue.then(()=>this.storage.write('initiative-ledger',JSON.stringify(record)));this.queue=run.catch(()=>{});return run}
  private fail():void{if(this.controller)this.effects(this.controller.handle({'type':'storageFault'},this.clock()))}
  private effects(effects:WireObject[]):void{
    for(const effect of effects){const type=string(effect['type'])
      if(type==='persist'){void this.write(object(effect['value'])).catch(()=>this.fail());continue}
      if(type==='offer'){const ticket=object(effect['ticket']);if(ticket['kind']==='greeting'){this.effects(this.controller!.handle({'type':'dropOffer','ticketId':ticket['id']},this.clock()));continue};void this.present(ticket);continue}
      this.listener?.(effect)
      if(type==='show'){const display=object(effect['display']),value=this.candidate;if(display['kind']==='signal'&&value&&this.signalCurrent(string(display['signalId'])))value.presented(value.candidate)}
    }
  }
  private async present(ticket:WireObject):Promise<void>{const token=this.token,id=string(ticket['id']),controller=this.controller;if(!controller||!this.listener||this.pending===id)return;this.pending=id
    try{if(ticket['kind']==='signal'&&!this.signalCurrent(string(ticket['signalId']))){this.effects(controller.handle({'type':'dropOffer','ticketId':id},this.clock()));return};const staged=controller.stagePresentation(id,this.clock());if(!staged?.record)return;await this.write(staged.record)
      if(token!==this.token||!this.listener)return
      if(ticket['kind']==='signal'&&!this.signalCurrent(string(ticket['signalId']))){this.pruneSignal();return}
      const expires=staged.display['expiresAtMono'];if(typeof expires==='number'&&this.clock().monoMs>=expires){this.effects(controller.handle({'type':'dropOffer','ticketId':id},this.clock()));return}
      const effects=controller.commitPresentation(staged).filter((effect:WireObject)=>effect['type']!=='persist');this.effects(effects)
    }catch{this.fail()}finally{if(this.pending===id)this.pending=''}
  }
}
