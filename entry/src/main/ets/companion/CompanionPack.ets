import { ensurePrivateDirectory } from '../local/PrivateDirectory'
import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { object, string, WireObject } from '../dsh/DshWire'
import { PrivateArchive, ArchiveEntry, archivePath } from '../pets/PrivateArchive'
import { inflatePrivate, privateBytes, privateSha256, removePrivate, writePrivate } from '../pets/ArchiveFiles'
import { strictPackJson } from '../pets/StrictPackJson'
export const COMPANION_RUNTIME_DIGEST:string='20e4e35ce1de09bd9017197363a96afdb4d9fc045d574fb669ebf21b4bc92e81'
const EXTENSIONS:string[]=['json','moc3','png','jpg','jpeg','webp','wav','mp3','txt','md']
const encode=(text:string):Uint8Array=>new util.TextEncoder().encodeInto(text)
const allowed=(name:string):boolean=>EXTENSIONS.includes(name.split('.').pop()?.toLowerCase()||'')
async function exists(path:string):Promise<boolean>{try{return await fs.access(path)}catch{return false}}
let queue:Promise<void>=Promise.resolve()
export async function companionPackInstalled(context:common.Context):Promise<boolean>{const root=context.filesDir+'/companion';if(!await exists(root+'/pack')&&await exists(root+'/pack.previous'))await fs.rename(root+'/pack.previous',root+'/pack');return await exists(root+'/pack/runtime/live2dcubismcore.min.js')&&await exists(root+'/pack/character/index.json')}
export async function companionCharacter(context:common.Context):Promise<WireObject>{try{return object(strictPackJson(await privateBytes(context.filesDir+'/companion/pack/character/character.json',262144)))}catch{return {}}}
async function copyRuntime(from:string,to:string):Promise<void>{await ensurePrivateDirectory(to);for(const name of await fs.listFile(from)){const src=from+'/'+name,target=to+'/'+name,stat=await fs.lstat(src);if(stat.isSymbolicLink())throw new Error('角色运行时不可包含链接');if(stat.isDirectory())await copyRuntime(src,target);else if(stat.isFile())await fs.copyFile(src,target)}}
export function installCompanionPack(context:common.Context,bytes:Uint8Array):Promise<void>{const run=queue.then(async()=>{
 const root=context.filesDir+'/companion',stage=root+'/pack.staging',live=root+'/pack',previous=root+'/pack.previous';await ensurePrivateDirectory(root);await companionPackInstalled(context);await removePrivate(stage);await fs.mkdir(stage,true)
 try{const archive=new PrivateArchive(bytes,419430400,4000);const files=archive.entries.filter((e:ArchiveEntry)=>!e.directory&&!e.name.startsWith('__MACOSX/')&&!e.name.endsWith('/.DS_Store')&&e.name!=='.DS_Store');if(!files.length)throw new Error('角色压缩包为空');const packaged=files.some((e:ArchiveEntry)=>e.name.startsWith('runtime/')||e.name.startsWith('character/'));const tops=new Set(files.map((e:ArchiveEntry)=>e.name.split('/')[0]));const strip=tops.size===1&&files.every((e:ArchiveEntry)=>e.name.includes('/'))?files[0].name.split('/')[0]+'/':''
 if(!packaged&&!files.some((e:ArchiveEntry)=>/\.model3\.json$/i.test(e.name)))throw new Error(files.some((e:ArchiveEntry)=>/\.moc$/i.test(e.name))?'不支持 Cubism 2 角色，请导入 moc3 角色':'找不到 model3.json')
 const hashes:Map<string,string>=new Map(),characters:string[]=[];const targets:Set<string>=new Set()
 for(const entry of files){const name=packaged?entry.name:'character/'+entry.name.slice(strip.length);if(!packaged&&!allowed(name))continue;if(!archivePath(name)||!(name.startsWith('runtime/')||name.startsWith('character/'))||name.startsWith('character/')&&!allowed(name))throw new Error('角色包包含不允许的文件');if(targets.has(name.normalize('NFKC').toLowerCase()))throw new Error('角色包路径重复');targets.add(name.normalize('NFKC').toLowerCase());const content=await archive.read(entry.name,inflatePrivate,419430400);const target=stage+'/'+name;await ensurePrivateDirectory(target.slice(0,target.lastIndexOf('/')));await writePrivate(target,content);if(name.startsWith('runtime/'))hashes.set(name,await privateSha256(content));else characters.push(name.slice(10))}
 if(hashes.size){let recipe='';for(const name of Array.from(hashes.keys()).sort())recipe+=name+'\x00'+hashes.get(name)+'\n';if(await privateSha256(encode(recipe))!==COMPANION_RUNTIME_DIGEST)throw new Error('角色运行时代码与原版签名不一致')}
 else {if(!await exists(live+'/runtime'))throw new Error('请先导入包含 runtime 的完整角色包');await copyRuntime(live+'/runtime',stage+'/runtime')}
 const models=characters.filter((n:string)=>/\.model3\.json$/i.test(n)).sort((a:string,b:string)=>a.split('/').length-b.split('/').length);if(!models.length)throw new Error('找不到 model3.json')
 if(!characters.includes('character.json')){const model=models[0];const info:WireObject={'schema':1,'name':model.split('/').pop()!.replace(/\.model3\.json$/i,''),'model':model};await writePrivate(stage+'/character/character.json',encode(JSON.stringify(info)));characters.push('character.json')}
 await writePrivate(stage+'/character/index.json',encode(JSON.stringify(characters)));await removePrivate(previous);const had=await exists(live);if(had)await fs.rename(live,previous);try{await fs.rename(stage,live)}catch(error){if(had)await fs.rename(previous,live);throw error as Error}await removePrivate(previous)
 }finally{await removePrivate(stage)}
 });queue=run.then(()=>{},()=>{});return run}
export function removeCompanionPack(context:common.Context):Promise<void>{const run=queue.then(async()=>{const root=context.filesDir+'/companion';await removePrivate(root+'/pack.previous');await removePrivate(root+'/pack');await removePrivate(root+'/pack.staging')});queue=run.then(()=>{},()=>{});return run}
