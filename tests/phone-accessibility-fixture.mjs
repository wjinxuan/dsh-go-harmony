import * as fs from 'node:fs/promises';
import {constants} from 'node:fs';import {randomUUID}from'node:crypto';
export const common={};export const fixture={root:'',bundle:'com.example.app',deny:[],calls:[],text:'Read target',password:false};
const handles=new Map();
export const fileIo={OpenMode:{CREATE:constants.O_CREAT,TRUNC:constants.O_TRUNC,WRITE_ONLY:constants.O_WRONLY,NOFOLLOW:constants.O_NOFOLLOW},
 async access(p){try{await fs.access(p);return true}catch{return false}},async mkdir(p,r){try{await fs.lstat(p)}catch(e){if(e.code==='ENOENT'){await fs.mkdir(p,{recursive:!!r});return}throw e}throw Object.assign(new Error('File exists'),{code:13900015})},
 async open(p,f){const h=await fs.open(p,f);handles.set(h.fd,h);return h},async write(fd,b){return(await handles.get(fd).write(Buffer.from(b))).bytesWritten},
 async close(h){handles.delete(h.fd);await h.close()},rename:fs.rename,unlink:fs.unlink,lstat:fs.lstat,
 async readText(p){return fs.readFile(p,'utf8')},listFile:fs.readdir};
export default{async fchmod(fd,m){await handles.get(fd).chmod(m)}};
export const util={generateRandomUUID:randomUUID,TextEncoder:{create(){return{encodeInto(s){return new TextEncoder().encode(s)}}}}};
export async function loadPhonePolicy(){return{denyPackages:fixture.deny}};
const node={async attributeValue(name){return{bundleName:fixture.bundle,isPassword:fixture.password,contents:[fixture.text],componentType:'TextInput',rect:{left:0,top:0,width:1080,height:2400},editable:true,children:[]}[name]},async actionNames(){return['click','setText','scrollForward']},async performAction(action,params){fixture.calls.push({action,params})}};
export class AccessibilityElement{}
export class AccessibilityExtensionAbility{context={filesDir:fixture.root,async getWindowRootElement(){return node},async injectGesture(path){fixture.calls.push({gesture:path})}}}
export const display={getDefaultDisplay:async()=>({width:1080,height:2400})};
export class GesturePath{constructor(durationTime){this.durationTime=durationTime;this.points=[]}}
export class GesturePoint{constructor(positionX,positionY){this.positionX=positionX;this.positionY=positionY}}
export const accessibility={async getAccessibilityExtensionList(){return[{bundleName:'com.dshgo.harmony',name:'PhoneAccessibilityAbility'}]}};
