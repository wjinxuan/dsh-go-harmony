export interface ArchiveEntry {name:string;directory:boolean;method:number;flags:number;compressed:number;size:number;crc:number;offset:number;start:number}
function archiveCheck(ok:boolean,code:string):void {if(!ok)throw new Error('压缩包校验失败：'+code)}
export function archivePath(name:string):boolean {return !!name&&!name.startsWith('/')&&!/[\\\x00]/.test(name)&&name.replace(/\/$/,'').split('/').every((part:string)=>!!part&&part!=='.'&&part!=='..'&&!part.includes(':'))}
export function archiveCrc(bytes:Uint8Array):number {let crc=0xffffffff;for(const byte of bytes){crc^=byte;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0)}return(crc^0xffffffff)>>>0}
export function archiveUtf8(bytes:Uint8Array):string {
 let result='';for(let i=0;i<bytes.length;i++){const first=bytes[i];if(first<128){result+=String.fromCharCode(first);continue}let value=first& (first<224?31:first<240?15:7),length=first>=194&&first<224?1:first>=224&&first<240?2:first>=240&&first<245?3:-1;archiveCheck(length>0&&i+length<bytes.length,'utf8');for(let n=0;n<length;n++){const next=bytes[++i];archiveCheck((next&192)===128,'utf8');value=value*64+(next&63)}archiveCheck(value>=(length===1?128:length===2?2048:65536)&&value<=0x10ffff&&!(value>=0xd800&&value<=0xdfff),'utf8');result+=String.fromCodePoint(value)}return result
}
function archiveName(bytes:Uint8Array,utf8:boolean):string {if(utf8)return archiveUtf8(bytes);const high='ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ ';let out='';for(const byte of bytes)out+=byte<128?String.fromCharCode(byte):high.charAt(byte-128);return out}
export class PrivateArchive {
 readonly entries:ArchiveEntry[]=[]
 private bytes:Uint8Array
 constructor(bytes:Uint8Array,maxBytes:number=67108864,maxEntries:number=256) {
  archiveCheck(bytes.length<=maxBytes&&bytes.length>=22,'size');this.bytes=bytes;const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength)
  let end=-1;for(let i=bytes.length-22;i>=Math.max(0,bytes.length-65557);i--)if(view.getUint32(i,true)===0x06054b50&&i+22+view.getUint16(i+20,true)===bytes.length){end=i;break}
  archiveCheck(end>=0,'directory');archiveCheck(view.getUint16(end+4,true)===0&&view.getUint16(end+6,true)===0,'multidisk')
  const count=view.getUint16(end+10,true),centralSize=view.getUint32(end+12,true),central=view.getUint32(end+16,true);archiveCheck(count<=maxEntries&&view.getUint16(end+8,true)===count&&central+centralSize===end,'directory')
  let cursor=central,total=0;const aliases:Set<string>=new Set();const names:Map<number,Uint8Array>=new Map()
  for(let i=0;i<count;i++) {
   archiveCheck(cursor+46<=end&&view.getUint32(cursor,true)===0x02014b50,'central-header')
   const flags=view.getUint16(cursor+8,true),method=view.getUint16(cursor+10,true),size=view.getUint32(cursor+24,true),compressed=view.getUint32(cursor+20,true),length=view.getUint16(cursor+28,true),extra=view.getUint16(cursor+30,true),comment=view.getUint16(cursor+32,true),offset=view.getUint32(cursor+42,true)
   archiveCheck(cursor+46+length+extra+comment<=end&&(flags&0x61)===0,'encoding')
   archiveCheck(method===0||method===8,'method');archiveCheck(view.getUint16(cursor+34,true)===0,'multidisk')
   const rawName=bytes.slice(cursor+46,cursor+46+length),name=archiveName(rawName,(flags&2048)!==0),directory=name.endsWith('/'),kind=(view.getUint32(cursor+38,true)>>>16)&0xf000
   archiveCheck(archivePath(name),'path');const alias=name.normalize('NFKC').toLowerCase();archiveCheck(!aliases.has(alias),'duplicate');aliases.add(alias)
   archiveCheck(kind===0||kind===(directory?0x4000:0x8000),'type');archiveCheck(size<=maxBytes-total,'expanded-size');total+=size
   const entry:ArchiveEntry={name:name,directory:directory,flags:flags,method:method,compressed:compressed,size:size,crc:view.getUint32(cursor+16,true),offset:offset,start:0};this.entries.push(entry);names.set(offset,rawName);cursor+=46+length+extra+comment
  }
  archiveCheck(cursor===end,'directory-size');const sorted=this.entries.slice().sort((a:ArchiveEntry,b:ArchiveEntry)=>a.offset-b.offset)
  for(let i=0;i<sorted.length;i++) {
   const entry=sorted[i],offset=entry.offset,next=sorted[i+1]?.offset??central
   archiveCheck(offset+30<=central&&view.getUint32(offset,true)===0x04034b50,'local-header');archiveCheck(view.getUint16(offset+6,true)===entry.flags&&view.getUint16(offset+8,true)===entry.method,'local-encoding')
   const length=view.getUint16(offset+26,true),extra=view.getUint16(offset+28,true),start=offset+30+length+extra,rawName=names.get(offset)!
   archiveCheck(length===rawName.length&&start<=next&&entry.compressed<=next-start&&entry.compressed<=central-start,'overlap');for(let n=0;n<length;n++)archiveCheck(bytes[offset+30+n]===rawName[n],'local-name')
   if(!(entry.flags&8))archiveCheck(view.getUint32(offset+14,true)===entry.crc&&view.getUint32(offset+18,true)===entry.compressed&&view.getUint32(offset+22,true)===entry.size,'local-size')
   entry.start=start
  }
 }
 manifests(name:string):string[] {return this.entries.filter((entry:ArchiveEntry)=>!entry.directory&&(entry.name===name||entry.name.endsWith('/'+name)&&entry.name.split('/').length===2)).map((entry:ArchiveEntry)=>entry.name)}
 async read(name:string,inflate:(bytes:Uint8Array,cap:number)=>Promise<Uint8Array>,cap:number=67108864):Promise<Uint8Array> {
  const entry=this.entries.find((row:ArchiveEntry)=>row.name===name&&!row.directory);archiveCheck(!!entry,'missing');archiveCheck(entry!.size<=cap,'member-size')
  const compressed=this.bytes.slice(entry!.start,entry!.start+entry!.compressed);const value=entry!.method===0?compressed:await inflate(compressed,entry!.size)
  archiveCheck(value.length===entry!.size&&archiveCrc(value)===entry!.crc,'member-integrity');return value
 }
}
