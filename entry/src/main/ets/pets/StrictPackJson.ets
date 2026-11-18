import { WireObject } from '../dsh/DshWire'
import { archiveUtf8 } from './PrivateArchive'
export function strictPackJson(bytes:Uint8Array,cap:number=262144):Object|null {
 if(bytes.length>cap||bytes[0]===239&&bytes[1]===187&&bytes[2]===191)throw new Error('素材清单大小或编码无效')
 return new PackJsonReader(archiveUtf8(bytes)).read()
}
class PackJsonReader {
 private text:string;private at:number=0
 constructor(text:string){this.text=text}
 private fail():never {throw new Error('素材清单 JSON 无效')}
 private space():void {while(/[ \t\r\n]/.test(this.text[this.at]||'!'))this.at++}
 private take(value:string):boolean {this.space();if(this.text[this.at]===value){this.at++;return true}return false}
 read():Object|null {const value=this.value(0);this.space();if(this.at!==this.text.length)this.fail();return value}
 private quoted():string {
  this.space();if(this.text[this.at]!=='"')this.fail();const start=this.at++
  while(this.at<this.text.length){const char=this.text[this.at++];if(char==='\\'){this.at++;continue}if(char==='"'){const result=JSON.parse(this.text.slice(start,this.at)) as string;for(let i=0;i<result.length;i++){const code=result.charCodeAt(i);if(code>=0xd800&&code<=0xdbff){const low=result.charCodeAt(++i);if(!(low>=0xdc00&&low<=0xdfff))this.fail()}else if(code>=0xdc00&&code<=0xdfff)this.fail()}return result}}
  return this.fail()
 }
 private value(depth:number):Object|null {
  if(depth>64)this.fail();this.space();const char=this.text[this.at]
  if(char==='"')return this.quoted()
  if(char==='{'){this.at++;const result:WireObject={},seen:Set<string>=new Set();if(this.take('}'))return result;do{const key=this.quoted();if(seen.has(key)||['__proto__','constructor','prototype'].includes(key))this.fail();seen.add(key);if(!this.take(':'))this.fail();result[key]=this.value(depth+1);if(this.take('}'))return result}while(this.take(','));return this.fail()}
  if(char==='['){this.at++;const result:(Object|null)[]=[];if(this.take(']'))return result;do{result.push(this.value(depth+1));if(this.take(']'))return result}while(this.take(','));return this.fail()}
  for(const literal of ['null','true','false'])if(this.text.slice(this.at,this.at+literal.length)===literal){this.at+=literal.length;return literal==='null'?null:literal==='true'}
  const match=/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(this.text.slice(this.at));if(!match)this.fail();const value=Number(match![0]);if(!Number.isFinite(value))this.fail();this.at+=match![0].length;return value
 }
}
