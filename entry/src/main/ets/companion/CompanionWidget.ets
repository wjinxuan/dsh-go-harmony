import { common } from '@kit.AbilityKit'
import { formBindingData, formProvider } from '@kit.FormKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { array, object, WireObject } from '../dsh/DshWire'
import { privateBytes, writePrivate, removePrivate } from '../pets/ArchiveFiles'
import { companionWidgetUpdate, companionWidgetView } from './CompanionWidgetData'
let writing:Promise<void>=Promise.resolve()
async function read(context:common.Context,name:string):Promise<Object|undefined>{const path=context.filesDir+'/'+name;try{if(!await fs.access(path))return undefined;return JSON.parse(util.TextDecoder.create('utf-8').decodeToString(await privateBytes(path,65536))) as Object}catch{return undefined}}
async function write(context:common.Context,name:string,value:Object):Promise<void>{const path=context.filesDir+'/'+name,temporary=path+'.'+util.generateRandomUUID()+'.part';try{await writePrivate(temporary,new util.TextEncoder().encodeInto(JSON.stringify(value)));await fs.rename(temporary,path)}finally{await removePrivate(temporary)}}
export async function companionWidgetBinding(context:common.Context):Promise<formBindingData.FormBindingData>{return formBindingData.createFormBindingData(companionWidgetView(object(await read(context,'companion-widget.json'))))}
export function registerCompanionWidget(context:common.Context,id:string,remove:boolean=false):Promise<void>{if(!/^\d{1,30}$/.test(id))return Promise.resolve();const run=writing.then(async()=>{const ids=array(await read(context,'companion-widget-ids.json')).filter((v:Object)=>typeof v==='string'&&/^\d{1,30}$/.test(v as string)).map((v:Object)=>String(v));const next=ids.filter((value:string)=>value!==id);if(!remove)next.push(id);await write(context,'companion-widget-ids.json',next.slice(-256));if(!remove)await formProvider.updateForm(id,await companionWidgetBinding(context))});writing=run.catch(()=>{});return run}
export function updateCompanionWidget(context:common.Context,values:WireObject):Promise<void>{const run=writing.then(async()=>{const current=object(await read(context,'companion-widget.json')),next=companionWidgetUpdate(current,values);await write(context,'companion-widget.json',next);const binding=formBindingData.createFormBindingData(companionWidgetView(next));for(const id of array(await read(context,'companion-widget-ids.json'))){if(typeof id!=='string'||!/^\d{1,30}$/.test(id))continue;try{await formProvider.updateForm(id,binding)}catch{}}});writing=run.catch(()=>{});return run}
