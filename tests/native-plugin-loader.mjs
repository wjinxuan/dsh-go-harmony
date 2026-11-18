import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes,createRequire} from 'node:module';
const url=code=>'data:text/javascript,'+encodeURIComponent(stripTypeScriptTypes(code));
export async function loadPluginConnection(runtime){
 const wire=url(await readFile(new URL('../entry/src/main/ets/dsh/DshWire.ets',import.meta.url),'utf8'));
 const source=async name=>(await readFile(new URL('../entry/src/main/ets/ui/'+name+'.ets',import.meta.url),'utf8')).replace(', WireObject','').replace("'../dsh/DshWire'",JSON.stringify(wire));
 const controls=url(await source('NativePluginControlsData')),model=url(await source('NativePluginModel'));
 const data=url((await source('NativePluginData')).replace("'./NativePluginControlsData'",JSON.stringify(controls)).replace("'./NativePluginModel'",JSON.stringify(model)));
 const WS=createRequire(runtime+'/main.cjs')('ws');
 globalThis.pluginTestSocket={createWebSocket(){const callbacks=new Map();let socket;return{on:(type,fn)=>callbacks.set(type,fn),off:type=>callbacks.delete(type),close:async()=>socket?.close(),send:async text=>{socket.send(text);return true},connect:async(url,opts)=>{socket=new WS(url,{headers:{...opts.header,Origin:new URL(url).origin.replace(/^ws/,'http')}});for(const type of ['open','close','error'])socket.on(type,(...args)=>callbacks.get(type)?.(...args));socket.on('message',data=>callbacks.get('message')?.(undefined,data.toString()))}}}};
 const code=(await source('NativePluginConnection')).replace("import { webSocket } from '@kit.NetworkKit'","const webSocket=globalThis.pluginTestSocket").replace("import { deviceInfo } from '@kit.BasicServicesKit'","const deviceInfo={sdkApiVersion:26}").replace("import { DshClient } from '../dsh/DshClient'",'').replace(', PluginPlace','').replace("'./NativePluginData'",JSON.stringify(data));
 try{return(await import(url(code))).NativePluginConnection}finally{delete globalThis.pluginTestSocket}
}
