import { common } from '@kit.AbilityKit'
import { fileIo as fs, picker } from '@kit.CoreFileKit'
import { zlib } from '@kit.BasicServicesKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
export async function inflatePrivate(bytes:Uint8Array,cap:number):Promise<Uint8Array> {return inflateBounded(bytes,cap,-15,true)}
export async function inflateBounded(bytes:Uint8Array,cap:number,windowBits:number=15,exact:boolean=false):Promise<Uint8Array> {
 const zip=await zlib.createZip();const out=new ArrayBuffer(Math.max(1,cap));const stream:zlib.ZStream={nextIn:bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),availableIn:bytes.length,nextOut:out,availableOut:out.byteLength}
 try {if(await zip.inflateInit2(stream,windowBits)!==zlib.ReturnStatus.OK)throw new Error('无法读取压缩数据');const status=await zip.inflate(stream,zlib.CompressFlushMode.FINISH);if(status!==zlib.ReturnStatus.STREAM_END||(exact?stream.totalOut!==cap:(stream.totalOut||0)>cap)||stream.totalIn!==bytes.length)throw new Error('压缩数据长度不匹配');return new Uint8Array(out,0,stream.totalOut||0)} finally {await zip.inflateEnd(stream)}
}
export async function privateBytes(path:string,cap:number):Promise<Uint8Array> {
 const file=await fs.open(path,fs.OpenMode.READ_ONLY)
 try {const stat=await fs.stat(file.fd);if(!stat.isFile()||stat.size>cap||stat.size<0)throw new Error('文件超过允许大小');const result=new Uint8Array(stat.size);let received=0;while(received<stat.size){const chunk=new ArrayBuffer(Math.min(65536,stat.size-received));const n=await fs.read(file.fd,chunk,{length:chunk.byteLength});if(n<=0)throw new Error('文件读取不完整');result.set(new Uint8Array(chunk,0,n),received);received+=n}return result}finally{await fs.close(file)}
}
export async function writePrivate(path:string,bytes:Uint8Array):Promise<void> {
 const file=await fs.open(path,fs.OpenMode.CREATE|fs.OpenMode.WRITE_ONLY|fs.OpenMode.TRUNC)
 try {const n=await fs.write(file.fd,bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.length));if(n!==bytes.length)throw new Error('文件写入不完整');await fs.fsync(file.fd)}finally{await fs.close(file)}
}
export async function pickPrivateZip(context:common.UIAbilityContext,cap:number):Promise<Uint8Array|undefined> {
 const selector=new picker.DocumentViewPicker(context);const selected=await selector.select({maxSelectNumber:1,fileSuffixFilters:['ZIP|.zip']});if(!selected.length)return undefined;return privateBytes(selected[0],cap)
}
export async function privateSha256(bytes:Uint8Array):Promise<string> {
 const hash=cryptoFramework.createMd('SHA256');await hash.update({data:bytes});const result=await hash.digest();let value='';for(const byte of result.data)value+=byte.toString(16).padStart(2,'0');return value
}
export async function removePrivate(path:string):Promise<void> {try{const stat=await fs.stat(path);if(stat.isDirectory())await fs.rmdir(path);else await fs.unlink(path)}catch{}}
