import { object, string, number } from '../dsh/DshWire'
import type { WireObject } from '../dsh/DshWire'
export const USAGE_LIMITS:Record<string,number>={'turns':5000,'voice':2000,'phone':2000,'share':1000,'gen':1000,'plugins':500}
export interface UsageDay {counts:Record<string,number>;engine:string;tries:number}
export interface UsageState {enabled:boolean;noticed:boolean;days:Record<string,UsageDay>;lastPlugins:number;iid:string;iidSince:number;failedAt:number;closedDay:string}
export interface UsageDevice {app:string;build:number;sdk:number;abi:string;maker:string;model:string;rom:string}
export interface UsageDriver {load:()=>Promise<string>;save:(value:string)=>Promise<void>;post:(body:WireObject)=>Promise<number>;random:()=>string;device:()=>Promise<UsageDevice>;language:()=>string;now:()=>number}
export function usageDay(now:number):string {const d=new Date(now);return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`}
function dayTime(day:string):number {const parts=day.split('-').map(Number);if(parts.length!==3)return NaN;const value=new Date(parts[0],parts[1]-1,parts[2]).getTime();return usageDay(value)===day?value:NaN}
function count(value:Object|null|undefined):number {const n=number(value,0);return Number.isSafeInteger(n)&&n>=0?n:0}
export function usageState(encoded:string='{}'):UsageState {
  let row:WireObject={};try{row=object(JSON.parse(encoded))}catch{}
  const days:Record<string,UsageDay>={},raw=object(row['days'])
  for(const day of Object.keys(raw)){if(!Number.isFinite(dayTime(day)))continue;const record=object(raw[day]),counts=object(record['counts']),values:Record<string,number>={}
    for(const key of Object.keys(USAGE_LIMITS))values[key]=count(counts[key]);days[day]={counts:values,engine:['direct','proot'].includes(string(record['engine']))?string(record['engine']):'none',tries:count(record['tries'])}}
  return {enabled:row['enabled']!==false,noticed:row['noticed']===true,days:row['enabled']===false?{}:days,lastPlugins:count(row['lastPlugins']),iid:string(row['iid']),iidSince:count(row['iidSince']),failedAt:count(row['failedAt']),closedDay:string(row['closedDay'])}
}
export function usageMaker(value:string):string {return value.toLowerCase().replace(/[^a-z0-9 ._-]/g,'').replace(/^[^a-z0-9]+/,'').substring(0,32).trim()||'unknown'}
export function usagePayload(state:UsageState,day:string,device:UsageDevice,lang:string,v2:boolean):WireObject {
  const row=state.days[day],counts:WireObject={};for(const key of Object.keys(USAGE_LIMITS))counts[key]=Math.min(count(row.counts[key]),USAGE_LIMITS[key])
  const body:WireObject={'v':v2&&!!device.model&&!!device.rom?2:1,'iid':state.iid,'day':day,'app':device.app,'build':device.build,'sdk':device.sdk,'abi':device.abi,'maker':device.maker,'lang':lang,'engine':row.engine,'counts':counts}
  if(body['v']===2){body['model']=device.model;body['rom']=device.rom}return body
}
export function usageProblem(body:WireObject,now:number):string {
  const expected=['v','iid','day','app','build','sdk','abi','maker','lang','engine','counts'].concat(body['v']===2?['model','rom']:[])
  if(body['v']!==1&&body['v']!==2)return 'v'
  if(Object.keys(body).sort().join(',')!==expected.sort().join(','))return 'keys'
  if(!/^[A-Za-z0-9_-]{21}[AQgw]$/.test(string(body['iid'])))return 'iid'
  const date=dayTime(string(body['day'])),host=new Date(now+8*3600000),today=new Date(host.getUTCFullYear(),host.getUTCMonth(),host.getUTCDate()).getTime()
  if(!Number.isFinite(date)||date<today-7*86400000||date>today+86400000)return 'day'
  if(!/^\d{1,3}\.\d{1,3}\.\d{1,3}(?:-[0-9A-Za-z.]{1,20})?$/.test(string(body['app'])))return 'app'
  if(count(body['build'])<1||count(body['build'])>2100000000)return 'build'
  if(count(body['sdk'])<26||count(body['sdk'])>60)return 'sdk'
  if(!['arm64-v8a','armeabi-v7a','x86_64','x86'].includes(string(body['abi'])))return 'abi'
  for(const key of body['v']===2?['maker','model','rom']:['maker'])if(!/^[A-Za-z0-9][A-Za-z0-9 ._-]{0,31}$/.test(string(body[key])))return key
  if(!/^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$/.test(string(body['lang'])))return 'lang'
  if(!['none','direct','proot'].includes(string(body['engine'])))return 'engine'
  const counts=object(body['counts']);if(Object.keys(counts).sort().join(',')!==Object.keys(USAGE_LIMITS).sort().join(','))return 'counts'
  for(const key of Object.keys(USAGE_LIMITS)){const value=number(counts[key],-1);if(!Number.isSafeInteger(value)||value<0||value>USAGE_LIMITS[key])return 'counts.'+key}return ''
}
function removeDay(state:UsageState,key:string):void {const next:Record<string,UsageDay>={};for(const day of Object.keys(state.days))if(day!==key)next[day]=state.days[day];state.days=next}
export class UsageStats {
  state:UsageState=usageState()
  loaded:boolean=false
  readonly active:boolean
  private driver:UsageDriver
  private initializing?:Promise<void>
  private writing:Promise<void>=Promise.resolve()
  private sending?:Promise<void>
  private generation:number=0
  private v1Only:boolean=false
  constructor(driver:UsageDriver,active:boolean){this.driver=driver;this.active=active}
  initialize():Promise<void>{if(!this.initializing)this.initializing=this.driver.load().then((encoded:string)=>{this.state=usageState(encoded);this.loaded=true});return this.initializing}
  private collecting():boolean{return this.active&&this.loaded&&this.state.enabled&&this.state.noticed}
  private save():Promise<void>{const encoded=JSON.stringify(this.state);this.writing=this.writing.catch(()=>{}).then(()=>this.driver.save(encoded));return this.writing}
  async noticed():Promise<void>{await this.initialize();this.state.noticed=true;await this.save();await this.foreground()}
  async setEnabled(enabled:boolean):Promise<void>{await this.initialize();this.generation++;if(!enabled){this.state=usageState();this.state.enabled=false}this.state.enabled=enabled;this.state.noticed=true;await this.save();if(enabled)await this.foreground()}
  private today(now:number):UsageDay {const day=usageDay(now);if(!this.state.days[day]){const counts:Record<string,number>={};for(const key of Object.keys(USAGE_LIMITS))counts[key]=key==='plugins'?this.state.lastPlugins:0;this.state.days[day]={counts:counts,engine:'none',tries:0}}return this.state.days[day]}
  async count(kind:string):Promise<void>{await this.initialize();if(!this.collecting()||!Object.keys(USAGE_LIMITS).includes(kind)||kind==='plugins')return;const row=this.today(this.driver.now());row.counts[kind]++;await this.save()}
  async plugins(installed:number):Promise<void>{await this.initialize();if(!this.collecting())return;this.state.lastPlugins=Math.max(0,Math.floor(installed));this.today(this.driver.now()).counts['plugins']=this.state.lastPlugins;await this.save()}
  async engine(mode:string):Promise<void>{await this.initialize();if(!this.collecting()||!['direct','proot'].includes(mode))return;this.today(this.driver.now()).engine=mode;await this.save()}
  async foreground():Promise<void>{await this.initialize();if(!this.collecting())return;this.today(this.driver.now());await this.save();await this.send()}
  send():Promise<void>{if(!this.sending)this.sending=this.performSend().finally(()=>this.sending=undefined);return this.sending}
  private async performSend():Promise<void>{
    if(!this.collecting())return;const now=this.driver.now(),generation=this.generation,today=usageDay(now)
    if(this.state.closedDay===today||(this.state.failedAt&&now>=this.state.failedAt&&now-this.state.failedAt<600000))return
    this.state.closedDay='';const dayStart=dayTime(today),host=new Date(now+8*3600000),hostStart=new Date(host.getUTCFullYear(),host.getUTCMonth(),host.getUTCDate()).getTime(),oldest=Math.max(dayStart,hostStart)-7*86400000
    for(const day of Object.keys(this.state.days))if(dayTime(day)<oldest||this.state.days[day].tries>=3)removeDay(this.state,day)
    const due=Object.keys(this.state.days).filter((day:string)=>dayTime(day)<dayStart).sort();if(!due.length){await this.save();return}
    const device=await this.driver.device();if(!this.collecting()||generation!==this.generation)return
    if(!this.state.iid||now-this.state.iidSince>=90*86400000){this.state.iid=this.driver.random();this.state.iidSince=now}
    for(const day of due){if(!this.collecting()||generation!==this.generation)return;if(!this.state.days[day])continue
      let body=usagePayload(this.state,day,device,this.driver.language(),!this.v1Only)
      if(usageProblem(body,now)){removeDay(this.state,day);continue}
      let status=0
      try{status=await this.driver.post(body);if(status===400&&body['v']===2&&this.collecting()&&generation===this.generation){this.v1Only=true;body=usagePayload(this.state,day,device,this.driver.language(),false);status=await this.driver.post(body)}}catch{}
      if(!this.collecting()||generation!==this.generation)return
      if((status>=200&&status<300)||[400,413,415].includes(status))removeDay(this.state,day)
      else if(status===404){this.state.closedDay=today;await this.save();return}
      else{this.state.days[day].tries++;if(this.state.days[day].tries>=3)removeDay(this.state,day);this.state.failedAt=now;await this.save();return}
    }
    this.state.failedAt=0;await this.save()
  }
}
