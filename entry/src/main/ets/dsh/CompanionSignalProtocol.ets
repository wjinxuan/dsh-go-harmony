// Port of dsh-Go a9877420 companion_signals{,_api}.dart (AGPL-3.0).
// Decoding does not authorize: live receipts are created only by DshClient.
import { object, string, WireObject } from './DshWire'
export interface CompanionSignalCapability { generation:string; available:boolean; reason:string }
export interface CompanionSignal { id:string; kind:string; source:WireObject; payload:WireObject; observedAt:string; freshness:string }
export interface CompanionRunReceipt { client:Object; connection:number; capability:CompanionSignalCapability; signal:CompanionSignal; received:number; current:()=>boolean; locallyCurrent:()=>boolean }
export function signalScalar(value:string,controls:boolean=false):boolean{for(let i=0;i<value.length;i++){const n=value.charCodeAt(i);if(n>=0xd800&&n<=0xdbff){const low=value.charCodeAt(++i);if(!(low>=0xdc00&&low<=0xdfff))return false}else if(n>=0xdc00&&n<=0xdfff||!controls&&(n<32||n>=127&&n<=159))return false}return true}
export function signalUtf8(text:string):number[]{const out:number[]=[];for(let i=0;i<text.length;i++){let c=text.charCodeAt(i);if(c>=0xd800&&c<=0xdbff){const low=text.charCodeAt(++i);if(!(low>=0xdc00&&low<=0xdfff))throw new Error('invalid Unicode');c=0x10000+((c-0xd800)<<10)+(low-0xdc00)}else if(c>=0xdc00&&c<=0xdfff)throw new Error('invalid Unicode');if(c<128)out.push(c);else if(c<2048)out.push(192|(c>>6),128|(c&63));else if(c<65536)out.push(224|(c>>12),128|((c>>6)&63),128|(c&63));else out.push(240|(c>>18),128|((c>>12)&63),128|((c>>6)&63),128|(c&63))}return out}
export function signalDecode(bytes:number[]):string{let text='';for(let i=0;i<bytes.length;){const first=bytes[i++];let n=first,count=0,min=0;if(first<128){}else if(first>=194&&first<=223){n=first&31;count=1;min=128}else if(first>=224&&first<=239){n=first&15;count=2;min=2048}else if(first>=240&&first<=244){n=first&7;count=3;min=65536}else throw new Error('invalid UTF-8');for(let j=0;j<count;j++){const c=bytes[i++];if(!(c>=128&&c<=191))throw new Error('invalid UTF-8');n=(n<<6)|(c&63)}if(n<min||n>0x10ffff||n>=0xd800&&n<=0xdfff)throw new Error('invalid UTF-8');text+=String.fromCodePoint(n)}return text}
export function signalId(v:Object|null|undefined,max:number=256):boolean{return typeof v==='string'&&v.length>0&&signalScalar(v)&&signalUtf8(v).length<=max}
export function signalInt(v:Object|null|undefined,min:number=0,max:number=Number.MAX_SAFE_INTEGER):boolean{return typeof v==='number'&&Number.isSafeInteger(v)&&v>=min&&v<=max}
export function signalUuid(v:Object|null|undefined):boolean{return typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(v)}
export function signalKeys(v:WireObject,keys:string[]):boolean{return Object.keys(v).length===keys.length&&keys.every((k:string)=>Object.keys(v).includes(k))}
function bad():never{throw new Error('伙伴信号协议无效')}
export function signalCapability(raw:Object|null|undefined):CompanionSignalCapability{const v=object(raw),k=v['kinds'];const unavailable=(value:Object|null|undefined):boolean=>{const o=object(value);return signalKeys(o,['available'])&&o['available']===false};if(!signalKeys(v,['v','generation','available','reason','kinds','maxEventBytes','replay','counts','devicePower','notifications'])||v['v']!==1||!signalUuid(v['generation'])||typeof v['available']!=='boolean'||v['maxEventBytes']!==1024||v['replay']!==false||v['counts']!==false||!unavailable(v['devicePower'])||!unavailable(v['notifications'])||!Array.isArray(k))return bad();if(v['available']===true?k.length!==1||k[0]!=='run.result'||v['reason']!==null:k.length!==0||!['engine-unavailable','producer-unavailable'].includes(string(v['reason'])))return bad();return{generation:string(v['generation']),available:v['available']===true,reason:string(v['reason'])}}
function checkRun(s:WireObject,p:WireObject):void{if(!signalId(s['callId'])||!signalInt(s['turn'],1)||!signalInt(s['step'],1)||!signalInt(s['seq'])||!signalKeys(p,['runId','runKind','result','exitCode','durationMs','passed','failed','skipped'])||p['runId']!==s['callId']||!['build','test','command'].includes(string(p['runKind']))||!['succeeded','failed','cancelled','not_run','unknown'].includes(string(p['result']))||p['exitCode']!==null&&!signalInt(p['exitCode'],-2147483648,2147483647)||p['durationMs']!==null&&!signalInt(p['durationMs'],0,604800000)||p['passed']!==null||p['failed']!==null||p['skipped']!==null||p['runKind']==='command'&&['succeeded','failed'].includes(string(p['result']))||p['result']==='succeeded'&&p['exitCode']!==0||p['result']==='failed'&&(p['exitCode']===null||p['exitCode']===0))bad()}
export function signalRun(raw:Object|null|undefined,generation:string,host:string,observedAt:string):CompanionSignal{const v=object(raw),s=object(v['source']),p=object(v['payload']);if(!signalKeys(v,['v','id','generation','source','payload'])||v['v']!==1||v['generation']!==generation||!signalUuid(generation)||signalUtf8(JSON.stringify(v)).length>1024||!signalKeys(s,['sessionId','turn','step','callId','seq'])||!signalId(s['sessionId'])||!signalId(host))return bad();checkRun(s,p);if(v['id']!==signalRunId(string(s['sessionId']),string(s['callId']),s['seq'] as number))return bad();const source:WireObject={'type':'dsh','hostKey':host};for(const key of Object.keys(s))source[key]=s[key];return{id:string(v['id']),kind:'run.result',source:source,payload:p,observedAt:observedAt,freshness:'live'}}
export function signalPhase(kind:string):string{if(kind==='completed')return'completed';if(kind==='max-tokens')return'output_limit';if(kind==='aborted')return'stopped';if(kind==='interrupted')return'interrupted';if(kind==='error'||kind==='blocked')return'failed';return'unknown'}
export function signalMetadata(raw:Object|null|undefined):CompanionSignal{const v=object(raw),s=object(v['source']),p=object(v['payload']),kind=string(v['kind']);if(!signalKeys(v,['v','id','kind','source','observedAt','freshness','payload'])||v['v']!==1||!signalId(v['id'],512)||!['live','reconciled'].includes(string(v['freshness']))||typeof v['observedAt']!=='string'||!Number.isFinite(Date.parse(v['observedAt']))||new Date(v['observedAt']).toISOString()!==v['observedAt']||signalUtf8(JSON.stringify(p)).length>1024)bad();if(kind.startsWith('task.')||kind==='run.result'){const extras=kind==='task.terminal'?['seq','turn']:kind==='run.result'?['seq','turn','step','callId']:['requestId'];if(!signalKeys(s,['type','hostKey','sessionId'].concat(extras))||s['type']!=='dsh'||!signalId(s['hostKey'])||!(kind==='task.approval_cleared'&&s['sessionId']===null)&&!signalId(s['sessionId']))bad();if(kind==='run.result')checkRun(s,p);else if(kind==='task.terminal'){if(!signalInt(s['seq'])||s['turn']!==null&&!signalInt(s['turn'],1)||!signalKeys(p,['phase','endKind','endSeq','turn'])||p['endSeq']!==s['seq']||p['turn']!==s['turn']||!['completed','max-tokens','aborted','interrupted','error','blocked','forked','unknown'].includes(string(p['endKind']))||p['phase']!==signalPhase(string(p['endKind'])))bad()}else if(!['task.approval_waiting','task.approval_cleared'].includes(kind)||!signalId(s['requestId'])||!signalKeys(p,['requestId','openSessionId','requestKind'])||p['requestId']!==s['requestId']||!(kind==='task.approval_cleared'&&p['openSessionId']===null)&&!signalId(p['openSessionId'])||!['approval','question'].includes(string(p['requestKind'])))bad()}else if(kind==='app.late_use'){const night=string(p['nightKey']);if(!signalKeys(s,['type'])||s['type']!=='device'||!signalKeys(p,['nightKey','utcOffsetMinutes','recentInteraction','activeMinutesBucket'])||!signalInt(p['utcOffsetMinutes'],-840,840)||p['recentInteraction']!==true||p['activeMinutesBucket']!=='15plus'||!/^\d{4}-\d{2}-\d{2}$/.test(night)||!Number.isFinite(Date.parse(night+'T23:00:00Z'))||new Date(night+'T23:00:00Z').toISOString().slice(0,10)!==night)bad()}else if(kind==='device.power'){if(!signalKeys(s,['type'])||s['type']!=='device'||!signalKeys(p,['charging','band'])||p['charging']!==true&&p['charging']!==false&&p['charging']!=='unknown'||!['normal','low','critical','unknown'].includes(string(p['band'])))bad()}else if(kind==='notification.available'||kind==='notification.removed'){if(!signalKeys(s,['type'])||s['type']!=='notification'||!signalKeys(p,['opaqueKey','packageId','change','count'])||!signalId(p['opaqueKey'])||!signalId(p['packageId'])||!signalInt(p['count'],0,1000000)||(kind==='notification.removed'?p['change']!=='removed':!['posted','updated'].includes(string(p['change']))))bad()}else bad();return{id:string(v['id']),kind:kind,source:s,payload:p,observedAt:string(v['observedAt']),freshness:string(v['freshness'])}}
export interface CompanionSignalFrame { event:string; id:string|undefined; value:WireObject }
export class CompanionSignalSse {
 ready:boolean=false
 unavailable:boolean=false
 private generation:string
 private line:number[]=[]
 private bytes:number=0
 private event:string|undefined=undefined
 private id:string|undefined=undefined
 private data:string|undefined=undefined
 constructor(generation:string){if(!signalUuid(generation))bad();this.generation=generation}
 push(chunk:Uint8Array,emit:(frame:CompanionSignalFrame)=>void):void{for(const byte of chunk){if(this.unavailable)return;if(++this.bytes>4096)bad();if(byte!==10){if(this.line.length>=2048)bad();this.line.push(byte);continue}if(this.line[this.line.length-1]===13)this.line.pop();const line=signalDecode(this.line);this.line=[];if(line===''){if(this.event!==undefined||this.data!==undefined||this.id!==undefined){if(!this.event||this.data===undefined||signalUtf8(this.data).length>1024)bad();const value=object(JSON.parse(this.data));if(!this.ready){if(this.event!=='companion/ready'||this.id!==undefined||!signalKeys(value,['v','generation'])||value['v']!==1||value['generation']!==this.generation)bad();this.ready=true}else if(this.event==='companion/unavailable'){if(!signalKeys(value,['v','generation','reason'])||value['v']!==1||value['generation']!==this.generation||!['engine-unavailable','producer-unavailable'].includes(string(value['reason'])))bad();this.unavailable=true}else if(this.event!=='companion/run-result')bad();const frame:CompanionSignalFrame={event:this.event,id:this.id,value:value};emit(frame)}this.event=undefined;this.data=undefined;this.id=undefined;this.bytes=0}else if(!line.startsWith(':')){const split=line.indexOf(':');if(split<1)bad();const key=line.slice(0,split);let value=line.slice(split+1);if(value.startsWith(' '))value=value.slice(1);if(key==='event'&&this.event===undefined)this.event=value;else if(key==='data'&&this.data===undefined)this.data=value;else if(key==='id'&&this.id===undefined)this.id=value;else bad()}}}
}

export function signalRunId(sessionId:string,callId:string,seq:number):string{
 const input=signalUtf8(JSON.stringify([sessionId,callId,seq])),bytes=input.concat([128]);while(bytes.length%64!==56)bytes.push(0);const bits=input.length*8;for(let i=7;i>=0;i--)bytes.push(Math.floor(bits/Math.pow(256,i))&255);
 const h:number[]=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19],k:number[]=[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];const r=(v:number,n:number):number=>(v>>>n)|(v<<(32-n));
 for(let start=0;start<bytes.length;start+=64){const w:number[]=new Array<number>(64).fill(0);for(let i=0;i<16;i++){const j=start+i*4;w[i]=(bytes[j]<<24)|(bytes[j+1]<<16)|(bytes[j+2]<<8)|bytes[j+3]}for(let i=16;i<64;i++){const x=w[i-15],y=w[i-2];w[i]=(w[i-16]+(r(x,7)^r(x,18)^(x>>>3))+w[i-7]+(r(y,17)^r(y,19)^(y>>>10)))>>>0}let a=h[0],b=h[1],c=h[2],d=h[3],e=h[4],f=h[5],g=h[6],z=h[7];for(let i=0;i<64;i++){const t1=(z+(r(e,6)^r(e,11)^r(e,25))+((e&f)^((~e)&g))+k[i]+w[i])>>>0,t2=((r(a,2)^r(a,13)^r(a,22))+((a&b)^(a&c)^(b&c)))>>>0;z=g;g=f;f=e;e=(d+t1)>>>0;d=c;c=b;b=a;a=(t1+t2)>>>0}const next:number[]=[a,b,c,d,e,f,g,z];for(let i=0;i<8;i++)h[i]=(h[i]+next[i])>>>0}
 const digest:number[]=[];for(const n of h)for(const shift of [24,16,8,0])digest.push((n>>>shift)&255);const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';let result='';for(let i=0;i<digest.length;i+=3){const n=(digest[i]<<16)|((digest[i+1]||0)<<8)|(digest[i+2]||0);result+=alphabet.charAt((n>>>18)&63)+alphabet.charAt((n>>>12)&63);if(i+1<digest.length)result+=alphabet.charAt((n>>>6)&63);if(i+2<digest.length)result+=alphabet.charAt(n&63)}return result
}
