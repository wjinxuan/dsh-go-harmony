import { array, number, object, string, strings, WireObject } from '../dsh/DshWire'
export const BUILTIN_PETS: string[] = ['deepy-whale','whale-girl']
export const PET_STATES: string[] = ['idle','thinking','working','juggling','sweeping','notification','attention','error','carrying','sleeping','waking']
export interface PetRect { x:number;y:number;w:number;h:number }
export interface PetFrame { i:number;ms:number }
export interface PetAnimation { name:string;sheet:string;frameW:number;frameH:number;cols:number;box:PetRect;frames:PetFrame[];loop:boolean;duration:number }
export interface PetPack { id:string;name:string;author:string;license:string;source:string;pixelArt:boolean;scale:number;width:number;height:number;anchorX:number;baseline:number;contentBox:PetRect;animations:PetAnimation[];raw:WireObject;directory:string }
export interface PetPreferences { packId:string;explicit:boolean;size:string;quiet:boolean;position:number;hiddenUntil:number;overlay:boolean;overlayMode:string;overlayPosition:number;overlayHiddenUntil:number }
export function petPreferences(value:Object|null|undefined=undefined,preferEnabled:boolean=true):PetPreferences {
 const raw=object(value);const pack=string(raw['packId']);const explicit=pack==='none'||BUILTIN_PETS.includes(pack)||/^user-[a-z0-9]+(?:-[a-z0-9]+)*$/.test(pack)
 return {packId:explicit?pack:preferEnabled?'deepy-whale':'none',explicit:explicit,size:['small','medium','large'].includes(string(raw['size']))?string(raw['size']):'medium',quiet:raw['quiet']===true,position:Math.max(0,Math.min(1,number(raw['position'],0.25))),hiddenUntil:Math.max(0,number(raw['hiddenUntil'],0)),overlay:raw['overlay']===true,overlayMode:raw['overlayMode']==='always'?'always':'active',overlayPosition:Math.max(0,Math.min(1,number(raw['overlayPosition'],0.5))),overlayHiddenUntil:Math.max(0,number(raw['overlayHiddenUntil'],0))}
}
function requirePet(condition:boolean,code:string):void {if(!condition)throw new Error('宠物包无效：'+code)}
function rect(value:Object|null|undefined):PetRect {const row=object(value);const result:PetRect={x:number(row['x'],NaN),y:number(row['y'],NaN),w:number(row['w'],NaN),h:number(row['h'],NaN)};requirePet([result.x,result.y,result.w,result.h].every((v:number)=>Number.isFinite(v))&&result.w>0&&result.h>0,'box');return result}
function whole(value:Object|null|undefined,min:number,max:number):number {requirePet(typeof value==='number'&&Number.isInteger(value)&&value>=min&&value<=max,'integer');return Number(value)}
export function parsePetPack(value:Object|null|undefined,directory:string=''):PetPack {
 const raw=object(value);requirePet(raw['schema']===1,'schema');const id=string(raw['id']);requirePet(!!id&&id.length<=200,'id')
 requirePet(JSON.stringify(value).length<=262144,'size');const canvas=object(raw['canvas']),scale=whole(raw['scale']??1,1,4096),width=whole(canvas['w'],1,1073741824),height=whole(canvas['h'],1,1073741824),anchor=object(raw['anchor']);const content=rect(raw['contentBox'])
 const animations:PetAnimation[]=[];const sheetAliases:Map<string,string>=new Map();const items=object(raw['animations'])
 for(const name of Object.keys(items)) {
  const row=object(items[name]),sheet=string(row['sheet']);requirePet(!!sheet&&sheet.length<=120&&!sheet.startsWith('.')&&!/[\\/\x00]/.test(sheet)&&/\.png$/i.test(sheet),'sheet')
  const alias=sheet.normalize('NFC').toLowerCase();requirePet(!sheetAliases.has(alias)||sheetAliases.get(alias)===sheet,'sheet-alias');sheetAliases.set(alias,sheet);requirePet(sheetAliases.size<=64,'sheet-count')
  const frameW=whole(row['frameW'],1,4096),frameH=whole(row['frameH'],1,4096),cols=whole(row['cols'],1,4096),box=rect(row['box']);requirePet(Math.trunc(Math.fround(Math.fround(box.w)*scale))===frameW&&Math.trunc(Math.fround(Math.fround(box.h)*scale))===frameH,'cell-box-scale')
  const frames:PetFrame[]=array(row['frames']).map((v:Object):PetFrame=>{const f=object(v);return{i:whole(f['i'],0,1073741824),ms:whole(f['ms'],1,1073741824)}});requirePet(frames.length>0,'frames')
  animations.push({name:name,sheet:sheet,frameW:frameW,frameH:frameH,cols:cols,box:box,frames:frames,loop:row['loop']!==false,duration:frames.reduce((sum:number,f:PetFrame)=>sum+f.ms,0)})
 }
 requirePet(animations.length>0,'animations');const known=(name:string):boolean=>animations.some((a:PetAnimation)=>a.name===name)
 const states=object(raw['states']);requirePet(strings(states['idle']).length>0,'idle')
 for(const key of Object.keys(states))for(const name of strings(states[key]))requirePet(known(name),'state '+key)
 for(const key of Object.keys(object(raw['reactions'])))requirePet(known(string(object(raw['reactions'])[key])),'reaction')
 for(const key of Object.keys(object(raw['tiers'])))for(const tier of array(object(raw['tiers'])[key]))requirePet(known(string(object(tier)['anim'])),'tier')
 const roam=string(object(raw['roam'])['anim']);if(roam)requirePet(known(roam),'roam')
 return{id:id,name:string(raw['name'])||id,author:string(raw['author']),license:string(raw['license']),source:string(raw['source']),pixelArt:raw['pixelArt']!==false,scale:scale,width:width,height:height,anchorX:number(anchor['x'],width/2),baseline:number(anchor['baseline'],height),contentBox:content,animations:animations,raw:raw,directory:directory}
}
export function petAnimation(pack:PetPack,state:string,tier:number=0):PetAnimation {
 const tiers=array(object(pack.raw['tiers'])[state]).map(object).sort((a:WireObject,b:WireObject)=>number(b['min'],1)-number(a['min'],1));const picked=tiers.find((row:WireObject)=>tier>=number(row['min'],1));const states=object(pack.raw['states']);const name=picked?string(picked['anim']):strings(states[state])[0]||strings(states['idle'])[0]
 return pack.animations.find((a:PetAnimation)=>a.name===name)||pack.animations[0]
}
export function petFrameAt(animation:PetAnimation,elapsed:number,motion:boolean=true):PetFrame {
 if(!motion)return animation.frames[0];let time=animation.loop?Math.max(0,elapsed)%animation.duration:Math.min(Math.max(0,elapsed),animation.duration-1)
 for(const frame of animation.frames){if(time<frame.ms)return frame;time-=frame.ms}return animation.frames[animation.frames.length-1]
}
export function petArtScale(pack:PetPack,size:string,dpr:number):number {
 const small=Math.max(1,Math.round(22*dpr/pack.contentBox.h)),medium=Math.max(small+1,Math.round(30*dpr/pack.contentBox.h)),large=Math.max(medium+1,Math.round(40*dpr/pack.contentBox.h))
 return pack.pixelArt?(size==='small'?small:size==='large'?large:medium)/dpr:(size==='small'?22:size==='large'?40:30)/pack.contentBox.h
}
export interface PetSessionSnapshot {hostKey:string;sessionId:string;activity:string;running:boolean;subagents:number;waiting:string;time:number;title:string;eventId:string;event:string}
export interface PetBubble {kind:string;sessionId:string;hostKey:string;title:string;count:number;until:number}
export interface PetMood {state:string;tier:number;targetId:string;targetHost:string;bubble?:PetBubble}
interface PetMoment {kind:string;at:number;session:PetSessionSnapshot}
const PRIORITY:Record<string,number>={'error':8,'notification':7,'sweeping':6,'attention':5,'carrying':4,'juggling':4,'working':3,'thinking':2,'idle':1,'sleeping':0,'waking':9}
export class PetMoodReducer {
 private events:Set<string>=new Set();private pending:PetMoment[]=[];private moment?:PetMoment;private bubble?:PetBubble;private lastTouch:number=Date.now();private state:string='idle';private stateAt:number=0;private tier:number=0;private tierSince:number=0;private lowerTier:number=0;private wakeUntil:number=0
 private pack:PetPack|undefined=undefined
 configure(pack:PetPack|undefined):void{this.pack=pack}
 private minimum(state:string):number{const defaults:Record<string,number>={'attention':5200,'error':4800,'sweeping':5600,'notification':3200,'carrying':3200,'working':1000,'thinking':1000};return number(object(object(this.pack?.raw['timings'])['minDisplay'])[state],defaults[state]||0)}
 private duration(state:string):number{const defaults:Record<string,number>={'attention':5200,'error':4800,'sweeping':300000,'carrying':3200};return number(object(object(this.pack?.raw['timings'])['autoReturn'])[state],defaults[state]||0)}
 private wake():number{const raw=object(this.pack?.raw['timings']);return number(raw['wakeMs'],this.pack?petAnimation(this.pack,'waking',0).duration:1500)}
 touch(now:number=Date.now()):void {this.lastTouch=now;if(this.state==='sleeping')this.wakeUntil=now+this.wake()}
 dismiss():void {this.bubble=undefined}
 update(sessions:PetSessionSnapshot[],focus:string,quiet:boolean,now:number=Date.now()):PetMood {
  for(const session of sessions) {
   if(session.running)this.pending=this.pending.filter((m:PetMoment)=>m.session.sessionId!==session.sessionId||m.session.hostKey!==session.hostKey)
   if(!session.eventId||this.events.has(session.hostKey+'|'+session.eventId))continue
   this.events.add(session.hostKey+'|'+session.eventId);if(this.events.size>1024)this.events.delete(this.events.values().next().value)
   if(!['done','failed','approval','question'].includes(session.event))continue
   this.touch(now);const event:PetMoment={kind:session.event,at:now,session:session}
   if(session.event==='done')this.pending.push(event);else this.show(event,focus,quiet,now)
  }
  for(const pending of this.pending.filter((event:PetMoment)=>now-event.at>=1500))this.show(pending,focus,quiet,now)
  this.pending=this.pending.filter((event:PetMoment)=>now-event.at<1500)
  if(this.bubble&&(this.bubble.until<=now||(['approval','question'].includes(this.bubble.kind)&&!sessions.some((s:PetSessionSnapshot)=>s.sessionId===this.bubble?.sessionId&&s.hostKey===this.bubble?.hostKey&&!!s.waiting))))this.bubble=undefined
  let chosen:PetSessionSnapshot|undefined=undefined;let state='idle';const current=sessions.find((s:PetSessionSnapshot)=>s.sessionId===focus&&s.running)
  for(const session of current?[current]:sessions){const next=session.waiting?'notification':session.activity==='compacting'?'sweeping':session.subagents>0?'juggling':!session.running?'idle':['tool','writing'].includes(session.activity)?'working':'thinking';if(PRIORITY[next]>PRIORITY[state]||PRIORITY[next]===PRIORITY[state]&&session.time>(chosen?.time||0)){state=next;chosen=session}}
  if(this.moment){const temporary=this.moment.kind==='failed'?'error':'attention';if(now-this.moment.at<this.duration(temporary)&&PRIORITY[temporary]>=PRIORITY[state]){state=temporary;chosen=this.moment.session}else if(now-this.moment.at>=this.duration(temporary))this.moment=undefined}
  if(state==='idle'&&now-this.lastTouch>=number(object(this.pack?.raw['sleep'])['afterMs'],60000))state='sleeping'
  if(now<this.wakeUntil)state='waking'
  if(['thinking','working'].includes(state)&&['thinking','working'].includes(this.state)&&state!==this.state&&now-this.stateAt<this.minimum(this.state))state=this.state
  if(state!==this.state){this.state=state;this.stateAt=now}
  const count=state==='juggling'?sessions.reduce((sum:number,s:PetSessionSnapshot)=>sum+s.subagents,0):sessions.filter((s:PetSessionSnapshot)=>s.running).length
  const targetTier=state==='juggling'?Math.min(2,count):Math.min(3,count)
  if(targetTier>=this.tier){this.tier=targetTier;this.tierSince=0}else if(targetTier!==this.lowerTier||!this.tierSince){this.lowerTier=targetTier;this.tierSince=now}else if(now-this.tierSince>=5000){this.tier=targetTier;this.tierSince=0}
  const waits=sessions.filter((s:PetSessionSnapshot)=>!!s.waiting).sort((a:PetSessionSnapshot,b:PetSessionSnapshot)=>a.time-b.time)
  const target=waits[0]||chosen||sessions.slice().sort((a:PetSessionSnapshot,b:PetSessionSnapshot)=>b.time-a.time)[0]
  return{state:state,tier:this.tier,targetId:target?.sessionId||'',targetHost:target?.hostKey||'',bubble:quiet?undefined:this.bubble}
 }
 private show(event:PetMoment,focus:string,quiet:boolean,now:number):void {
  if(['done','failed'].includes(event.kind))this.moment=event
  if(event.session.sessionId===focus||quiet)return
  const rank=(kind:string):number=>['approval','question'].includes(kind)?2:kind==='failed'?1:0
  if(this.bubble&&rank(this.bubble.kind)>rank(event.kind))return
  const old=this.bubble;const duration=event.kind==='done'?5200:event.kind==='failed'?4800:30000
  this.bubble={kind:event.kind,sessionId:old&&old.kind===event.kind&&old.until-now>duration-2000?old.sessionId:event.session.sessionId,hostKey:event.session.hostKey,title:event.session.title.slice(0,12),count:old&&old.kind===event.kind&&old.until-now>duration-2000?old.count+1:1,until:now+duration}
 }
}
export function petIdleDelay(pack:PetPack|undefined,u:number):number{const every=object(object(pack?.raw['idlePool'])['everyMs']);const mean=number(every['mean'],120000),min=number(every['min'],45000),max=number(every['max'],300000);return Math.min(max,min+Math.round(-Math.max(0,mean-min)*Math.log(1-Math.max(0,Math.min(.999999,u)))))}
export interface PetIdleChoice {animation:PetAnimation;ms:number}
export function petIdleChoice(pack:PetPack,u:number):PetIdleChoice|undefined{const entries=array(object(pack.raw['idlePool'])['anims']).map(object).filter((entry:WireObject)=>number(entry['weight'],1)>0&&pack.animations.some((animation:PetAnimation)=>animation.name===entry['anim']));let weight=entries.reduce((sum:number,entry:WireObject)=>sum+number(entry['weight'],1),0)*Math.max(0,Math.min(.999999,u));for(const entry of entries){weight-=number(entry['weight'],1);if(weight<=0){const animation=pack.animations.find((item:PetAnimation)=>item.name===entry['anim'])!;return{animation:animation,ms:number(entry['ms'],animation.duration)}}}return undefined}
