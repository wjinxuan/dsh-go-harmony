import { archiveCrc } from './PrivateArchive'
export interface PetPngInfo {width:number;height:number;rendering:Uint8Array}
function check(ok:boolean,code:string):void {if(!ok)throw new Error('宠物图片无效：'+code)}
function join(parts:Uint8Array[]):Uint8Array {const bytes=new Uint8Array(parts.reduce((n:number,p:Uint8Array)=>n+p.length,0));let at=0;for(const part of parts){bytes.set(part,at);at+=part.length}return bytes}
// Validate the complete rendering stream before giving it to ImageKit. Ancillary
// compressed data is checked within a separate bounded buffer and never decoded by ImageKit.
export async function validatePetPng(bytes:Uint8Array,inflate:(bytes:Uint8Array,cap:number)=>Promise<Uint8Array>):Promise<PetPngInfo> {
 check(bytes.length>=33&&bytes.length<=8388608,'size');const signature=[137,80,78,71,13,10,26,10];check(signature.every((v:number,i:number)=>bytes[i]===v),'signature')
 const data=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength),width=data.getUint32(16),height=data.getUint32(20),depth=bytes[24],color=bytes[25],interlace=bytes[28]
 check(width>0&&height>0&&width<=4096&&height<=4096&&width*height*4<=16777216,'dimensions')
 const depths:Map<number,number[]>=new Map([[0,[1,2,4,8,16]],[2,[8,16]],[3,[1,2,4,8]],[4,[8,16]],[6,[8,16]]]);const channels:Map<number,number>=new Map([[0,1],[2,3],[3,1],[4,2],[6,4]])
 check(data.getUint32(8)===13&&!!depths.get(color)?.includes(depth)&&bytes[26]===0&&bytes[27]===0&&interlace<=1,'format')
 let at=8,ended=false,saw=false,idatEnded=false,palette=0,transparency=false,metadata=0;const compressed:Uint8Array[]=[],rendering:Uint8Array[]=[bytes.slice(0,8)]
 while(at<bytes.length){check(at+12<=bytes.length,'chunk');const length=data.getUint32(at);check(length<=bytes.length-at-12,'chunk');const kind=String.fromCharCode(...bytes.slice(at+4,at+8));check(/^[a-zA-Z]{4}$/.test(kind),'chunk-name');check(archiveCrc(bytes.subarray(at+4,at+8+length))===data.getUint32(at+8+length),'crc');check(!['acTL','fcTL','fdAT'].includes(kind),'animated');check(kind!=='IHDR'||at===8,'header');check(at!==8||kind==='IHDR','header');check((bytes[at+4]&32)!==0||['IHDR','PLTE','IDAT','IEND'].includes(kind),'critical')
  if(['iCCP','zTXt','iTXt','tEXt'].includes(kind)){const content=bytes.subarray(at+8,at+8+length),zero=content.indexOf(0);check(zero>0&&zero<=79,'metadata-key');let decoded=content.length
   if(kind==='iCCP'||kind==='zTXt'){check(zero+2<content.length&&content[zero+1]===0,'metadata-compression');decoded=(await inflate(content.subarray(zero+2),1048576)).length}
   else if(kind==='iTXt'){check(zero+3<content.length&&content[zero+1]<=1&&content[zero+2]===0,'metadata-compression');const language=content.indexOf(0,zero+3),translated=content.indexOf(0,language+1);check(language>=0&&translated>=0,'metadata-text');decoded=content[zero+1]===1?(await inflate(content.subarray(translated+1),1048576)).length:content.length-translated-1}
   check(decoded<=1048576,'metadata-size');metadata+=decoded;check(metadata<=67108864,'metadata-total')}
  if(kind==='PLTE'){check(!saw&&!transparency&&palette===0&&color!==0&&color!==4&&length>0&&length<=768&&length%3===0,'palette');palette=length/3;check(color!==3||palette<=Math.pow(2,depth),'palette')}
  if(kind==='tRNS'){check(!saw&&!transparency&&(color===0&&length===2||color===2&&length===6||color===3&&palette>0&&length>0&&length<=palette),'transparency');transparency=true}
  if(kind==='IDAT'){check(!idatEnded&&(color!==3||palette>0),'data-order');saw=true;compressed.push(bytes.slice(at+8,at+8+length))}else if(saw)idatEnded=true
  if(['IHDR','PLTE','tRNS','IDAT','IEND'].includes(kind))rendering.push(bytes.slice(at,at+12+length));at+=12+length
  if(kind==='IEND'){check(length===0&&at===bytes.length,'trailing');ended=true;break}
 }
 check(ended&&saw,'truncated');const bits=(channels.get(color)||0)*depth;const rows:number[][]=[]
 if(interlace===0)rows.push([Math.ceil(width*bits/8),height]);else for(const pass of [[0,0,8,8],[4,0,8,8],[0,4,4,8],[2,0,4,4],[0,2,2,4],[1,0,2,2],[0,1,1,2]]){const w=width<=pass[0]?0:Math.ceil((width-pass[0])/pass[2]),h=height<=pass[1]?0:Math.ceil((height-pass[1])/pass[3]);if(w&&h)rows.push([Math.ceil(w*bits/8),h])}
 const expected=rows.reduce((n:number,r:number[])=>n+(r[0]+1)*r[1],0),pixels=await inflate(join(compressed),expected);check(pixels.length===expected,'decoded-size');let start=0;for(const row of rows)for(let i=0;i<row[1];i++){check(pixels[start]<=4,'filter');start+=row[0]+1}
 return{width:width,height:height,rendering:join(rendering)}
}
export function validateStaticWebp(bytes:Uint8Array,width:number,height:number):void {
 const data=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);const tag=(at:number):string=>String.fromCharCode(...bytes.slice(at,at+4));check(bytes.length>=20&&tag(0)==='RIFF'&&tag(8)==='WEBP'&&data.getUint32(4,true)===bytes.length-8,'webp');let at=12,streams=0;const seen:Set<string>=new Set()
 while(at<bytes.length){check(at+8<=bytes.length,'webp-chunk');const type=tag(at),size=data.getUint32(at+4,true),start=at+8,end=start+size+(size&1);check(end<=bytes.length&&(!(size&1)||bytes[end-1]===0),'webp-chunk');check(type!=='ANIM'&&type!=='ANMF','webp-animated');if(['VP8X','VP8 ','VP8L','ALPH','ICCP','EXIF','XMP '].includes(type)){check(!seen.has(type),'webp-duplicate');seen.add(type)}if(type==='VP8X'){check(at===12&&size===10&&(bytes[start]&0xc3)===0&&bytes[start+1]===0&&bytes[start+2]===0&&bytes[start+3]===0,'webp-header');const w=bytes[start+4]|bytes[start+5]<<8|bytes[start+6]<<16,h=bytes[start+7]|bytes[start+8]<<8|bytes[start+9]<<16;check(w+1===width&&h+1===height,'webp-grid')}if(type==='VP8 '||type==='VP8L')streams++;at=end}check(streams===1,'webp-stream')
}
