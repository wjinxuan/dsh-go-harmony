import { array, object, string, number } from '../dsh/DshWire'
import type { WireObject } from '../dsh/DshWire'
export interface NotificationPreferences { enabled:boolean;done:boolean;failed:boolean;approval:boolean;question:boolean;live:boolean }
export interface ChatNotification { kind:string;sessionId:string;key:string;text:string;destination?:string;botId?:string;botRoom?:boolean }
export function notificationPreferences(value:Object|null|undefined=undefined):NotificationPreferences {
  const row=object(value);return {enabled:row['enabled']!==false,done:row['done']!==false,failed:row['failed']!==false,approval:row['approval']!==false,question:row['question']!==false,live:row['live']!==false}
}
export function notificationAllowed(prefs:NotificationPreferences,kind:string):boolean {
  return prefs.enabled && (kind==='done'?prefs.done:kind==='failed'||kind==='stopped'?prefs.failed:kind==='approval'?prefs.approval:kind==='question'?prefs.question:false)
}
export function notificationText(kind:string):string {
  return kind==='done'?'对话已完成':kind==='failed'?'对话遇到错误':kind==='stopped'?'对话已停止':kind==='approval'?'有操作等待确认':'有问题等待回答'
}
export function requestNotification(event:WireObject):ChatNotification|undefined {
  if(event['type']!=='waterfall'||!['approval/request','user-questions/request'].includes(string(event['event'])))return undefined
  const request=object(event['request']),sessionId=string(request['sessionId']),key=string(event['eventId'])
  if(!sessionId||!key)return undefined
  const kind=event['event']==='approval/request'?'approval':'question'
  return {kind:kind,sessionId:sessionId,key:key,text:notificationText(kind)}
}
export function turnNotification(sessionId:string,page:Object|null|undefined):ChatNotification|undefined {
  const records=array(object(page)['records']).map(object)
  for(let index=records.length-1;index>=0;index--){const row=records[index],event=object(row['event']),type=string(event['type'])||string(row['type'])
    if(type!=='turn/end')continue
    const data=object(row['data']||event['data']),reason=string(object(data['reason'])['kind']),seq=number(event['seq'],number(row['seq'],0))
    if(!seq||!reason)return undefined
    const kind=reason==='completed'||reason==='max-tokens'?'done':reason==='aborted'?'stopped':'failed'
    return {kind:kind,sessionId:sessionId,key:`turn-${seq}`,text:notificationText(kind)}
  }
  return undefined
}
export class NotificationDeduper {
  private keys:string[]=[]
  claim(scope:string,item:ChatNotification):boolean {
    const key=JSON.stringify([scope,item.sessionId,item.key]);if(this.keys.includes(key))return false
    this.keys.push(key);if(this.keys.length>1024)this.keys.shift();return true
  }
}
