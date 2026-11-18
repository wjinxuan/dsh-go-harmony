import { common } from '@kit.AbilityKit'
import { webview } from '@kit.ArkWeb'
import { util } from '@kit.ArkTS'
import { object, string, WireObject } from '../dsh/DshWire'
import { archivePath } from '../pets/PrivateArchive'
import { privateBytes } from '../pets/ArchiveFiles'
class CompanionStageProxy {sink:(event:WireObject)=>void=()=>{};postMessage(text:string):void{if(typeof text!=='string'||text.length>262144)return;try{const row=object(JSON.parse(text));if(['ready','error','failed','touch','wake','mood','object','activity','model','probe','adapted'].includes(string(row['type'])))this.sink(row)}catch{}}}
export class CompanionStageController {
 private controller:webview.WebviewController|undefined=undefined
 private ready:boolean=false
 attach(controller:webview.WebviewController):void{this.controller=controller;this.ready=false}
 markReady():void{this.ready=true}
 detach():void{this.ready=false;this.controller=undefined}
 command(type:string,args:WireObject={}):void{if(!this.ready||!['mood','emotion','action','say','quiet','loudness','beat','mouth','vitals','activity','adapter','glance','beckon','prop','pause','resume'].includes(type))return;const message:WireObject={};for(const key of Object.keys(args))message[key]=args[key];message['type']=type;void this.controller?.runJavaScript('window.stage.command('+JSON.stringify(message)+')').catch(()=>{})}
}
@Component
export struct CompanionStage {
 @Prop reducedMotion:boolean=false
 @Prop lowMemory:boolean=false
 @Prop reloadId:number=0
 stage:CompanionStageController=new CompanionStageController()
 onEvent:(event:WireObject)=>void=()=>{}
 private controller:webview.WebviewController=new webview.WebviewController()
 private bridge:CompanionStageProxy=new CompanionStageProxy()
 private origin:string='https://companion.invalid/'+util.generateRandomUUID()+'/'
 private timeout:number=-1
 private alive:boolean=true
 aboutToAppear():void{this.alive=true;this.stage.attach(this.controller);this.bridge.sink=(event:WireObject)=>{if(!this.alive)return;if(event['type']==='ready'){clearTimeout(this.timeout);this.stage.markReady()}this.onEvent(event)};this.timeout=setTimeout(()=>this.onEvent({'type':'failed','message':'角色加载超时'}),40000)}
 aboutToDisappear():void{this.alive=false;clearTimeout(this.timeout);this.stage.detach()}
 private intercept(request:WebResourceRequest):WebResourceResponse {const response=new WebResourceResponse();response.setResponseIsReady(false);void this.serve(request,response);return response}
 private async serve(request:WebResourceRequest,response:WebResourceResponse):Promise<void>{try{const url=request.getRequestUrl().split('?')[0];if(!['GET','HEAD'].includes(request.getRequestMethod())||!url.startsWith(this.origin))throw new Error('origin');const encoded=url.slice(this.origin.length);const parts=encoded.split('/').map((part:string)=>decodeURIComponent(part));if(parts.some((part:string)=>part.includes('/'))||!archivePath(parts.join('/')))throw new Error('path');const scope=parts.shift(),path=parts.join('/');let bytes:Uint8Array
  if(scope==='app'&&['index.html','scene.js','stage.js','stage.css'].includes(path))bytes=await (getContext(this) as common.Context).resourceManager.getRawFileContent('companion/'+path)
  else if(scope==='pack')bytes=await privateBytes((getContext(this) as common.Context).filesDir+'/companion/pack/'+path,67108864)
  else throw new Error('path')
  const extension=path.split('.').pop()||'',types:Map<string,string>=new Map([['html','text/html'],['js','text/javascript'],['css','text/css'],['json','application/json'],['png','image/png'],['jpg','image/jpeg'],['jpeg','image/jpeg'],['webp','image/webp'],['wav','audio/wav'],['mp3','audio/mpeg']]);response.setResponseCode(200);response.setReasonMessage('OK');response.setResponseMimeType(types.get(extension)||'application/octet-stream');response.setResponseEncoding('utf-8');response.setResponseHeader([{headerKey:'Cache-Control',headerValue:'no-store'},{headerKey:'X-Content-Type-Options',headerValue:'nosniff'}]);response.setResponseData(request.getRequestMethod()==='HEAD'?'':bytes.buffer)
 }catch{response.setResponseCode(404);response.setReasonMessage('Not Found');response.setResponseData('')}finally{response.setResponseIsReady(true)}}
 build(){Web({src:this.origin+'app/index.html?reduceMotion='+(this.reducedMotion?'1':'0')+'&maxTexture='+(this.lowMemory?'2048':'4096'),controller:this.controller}).javaScriptAccess(true).domStorageAccess(false).fileAccess(false).databaseAccess(false).geolocationAccess(false).mixedMode(MixedMode.None).javaScriptProxy({object:this.bridge,name:'DshCompanion',methodList:['postMessage'],controller:this.controller}).onInterceptRequest((event)=>this.intercept(event.request)).onOverrideUrlLoading((request)=>!request.getRequestUrl().startsWith(this.origin)).onPermissionRequest((event)=>event.request.deny()).onVisibleAreaChange([0,1],(visible:boolean)=>this.stage.command(visible?'resume':'pause')).width('100%').height('100%')}
}
