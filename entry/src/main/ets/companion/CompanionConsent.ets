import { object, WireObject } from '../dsh/DshWire'
export interface CompanionConsent { state:boolean; optionalSpeech:boolean; voice:boolean; nightCare:boolean }
export function companionConsent(raw:string|undefined,available:boolean=true):CompanionConsent|undefined {
  if(!available)return undefined
  if(raw===undefined)return{state:true,optionalSpeech:true,voice:false,nightCare:false}
  let value:WireObject={};try{value=object(JSON.parse(raw))}catch{}
  return{state:value['state']===true,optionalSpeech:value['optionalSpeech']===true,voice:value['voice']===true,nightCare:value['nightCare']===true}
}
export function companionConsentAllows(value:CompanionConsent|undefined,kind:string):boolean {
  if(!value)return false
  if(kind==='state')return value.state
  if(kind==='optionalSpeech')return value.state&&value.optionalSpeech
  if(kind==='voice')return value.state&&value.optionalSpeech&&value.voice
  if(kind==='nightCare')return value.state&&value.optionalSpeech&&value.nightCare
  return false
}
export interface CompanionPrivatePreferences { read:(key:string)=>Promise<string|undefined>; write:(key:string,value:string)=>Promise<void> }
export class CompanionConsentOwner {
  value:CompanionConsent|undefined=undefined
  private epoch:number=0
  private queue:Promise<void>=Promise.resolve()
  private storage:CompanionPrivatePreferences
  constructor(storage:CompanionPrivatePreferences){this.storage=storage}
  async load():Promise<void>{const epoch=++this.epoch;try{const value=companionConsent(await this.storage.read('signal-consent'));if(epoch===this.epoch)this.value=value}catch{if(epoch===this.epoch)this.value=undefined}}
  set(value:CompanionConsent):Promise<void>{const epoch=++this.epoch;const safe:CompanionConsent={state:value.state,optionalSpeech:value.optionalSpeech,voice:value.voice,nightCare:value.nightCare};
    // A new yes becomes active only after durable storage; a no takes effect now.
    const prior=this.value;this.value={state:!!prior?.state&&safe.state,optionalSpeech:!!prior?.optionalSpeech&&safe.optionalSpeech,voice:!!prior?.voice&&safe.voice,nightCare:!!prior?.nightCare&&safe.nightCare}
    const run=this.queue.then(async()=>{await this.storage.write('signal-consent',JSON.stringify(safe));if(epoch===this.epoch)this.value=safe});this.queue=run.catch(()=>{});return run
  }
}
