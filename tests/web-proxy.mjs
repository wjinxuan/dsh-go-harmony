import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
const runtime=process.argv[2];if(!runtime)throw Error('runtime required');
const require=createRequire(runtime+'/package.json');const {WebSocket,WebSocketServer}=require('ws');
const {openWebProxy,webSession,createWebProxyHandler}=await import(pathToFileURL(runtime+'/web-proxy.mjs'));
const {startTransportControl}=await import(pathToFileURL(runtime+'/transport-control.mjs'));
const seen=[];
const upstream=createServer((req,res)=>{
 seen.push({url:req.url,headers:req.headers});
 if(req.headers.cookie!=='dsh-auth-test=secret' || req.headers.authorization!=='Bearer remote-private')return res.writeHead(401).end();
 if(req.url==='/prefix/redirect')return res.writeHead(302,{location:'/prefix/ok','set-cookie':'bad=credential'}).end();
 if(req.url==='/prefix/external')return res.writeHead(302,{location:'https://example.com/leak'}).end();
 if(req.url==='/prefix/post'){let body='';req.on('data',x=>body+=x);req.on('end',()=>res.end(body));return;}
 res.end('web content');
});
const wss=new WebSocketServer({server:upstream});wss.on('connection',(ws,req)=>{seen.push({url:req.url,headers:req.headers});ws.on('message',(value,binary)=>ws.send(value,{binary}));});
await new Promise(r=>upstream.listen(0,'127.0.0.1',r));
const baseUrl=`http://127.0.0.1:${upstream.address().port}/prefix`;
const input={baseUrl,cookie:'dsh-auth-test=secret',authorization:'Bearer remote-private'};
let proxy,control;
try{
 for(const bad of [{...input,baseUrl:'http://remote.test/'},{...input,baseUrl:'https://user@remote.test'},{...input,cookie:'bad=foo'},{...input,authorization:'a\r\nb'}])assert.throws(()=>webSession(bad));
 proxy=await openWebProxy(input);
 const launch=await fetch(proxy.launchUrl,{redirect:'manual'});assert.equal(launch.status,303);
 const cookie=launch.headers.get('set-cookie').split(';')[0];assert.equal(launch.headers.get('location'),'/prefix/');
 assert.equal((await fetch(proxy.launchUrl,{redirect:'manual'})).status,403);
 assert.equal((await fetch(proxy.origin+'/prefix/')).status,403);
 assert.equal((await fetch(proxy.origin+'/prefix/',{headers:{cookie,origin:'https://evil.test'}})).status,403);
 assert.equal((await fetch(proxy.origin+'/outside',{headers:{cookie}})).status,403);
 assert.equal((await fetch(proxy.origin+'/prefix/',{headers:{cookie}})).status,200);
 assert.equal(seen.at(-1).headers.cookie,input.cookie);assert.equal(seen.at(-1).headers.authorization,input.authorization);
 assert.equal(await(await fetch(proxy.origin+'/prefix/post',{method:'POST',headers:{cookie,origin:proxy.origin},body:'actual body'})).text(),'actual body');
 assert.equal(seen.at(-1).headers.origin,new URL(baseUrl).origin);
 const redirect=await fetch(proxy.origin+'/prefix/redirect',{headers:{cookie},redirect:'manual'});assert.equal(redirect.status,302);assert.equal(redirect.headers.get('location'),'/prefix/ok');assert.equal(redirect.headers.get('set-cookie'),null);
 assert.equal((await fetch(proxy.origin+'/prefix/external',{headers:{cookie},redirect:'manual'})).status,502);
 const socket=new WebSocket(proxy.origin.replace('http:','ws:')+'/prefix/api/remote.mux',{headers:{cookie},origin:proxy.origin});
 await new Promise((r,j)=>{socket.once('open',r);socket.once('error',j)});
 for(const [data,binary]of[['frame',false],[Buffer.from([1,2,3]),true]]){
  const response=new Promise((r,j)=>{socket.once('message',(data,binary)=>r({data,binary}));socket.once('error',j)});socket.send(data,{binary});const result=await response;assert.equal(result.binary,binary);assert.deepEqual(result.data,Buffer.from(data));
 }
 assert.equal(seen.at(-1).headers.cookie,input.cookie);assert.equal(seen.at(-1).headers.origin,new URL(baseUrl).origin);
 const socketClosed=new Promise(r=>socket.once('close',r));await proxy.close();await socketClosed;assert.equal(socket.readyState,WebSocket.CLOSED);
 control=await startTransportControl({web:createWebProxyHandler()});const headers={authorization:control.endpoint.authorization,'content-type':'application/json'};
 assert.equal((await fetch(control.endpoint.url+'/web/open',{method:'POST',body:JSON.stringify(input)})).status,403);
 const opened=await(await fetch(control.endpoint.url+'/web/open',{method:'POST',headers,body:JSON.stringify(input)})).json();
 assert.equal((await fetch(opened.launchUrl,{redirect:'manual'})).status,303);
 await fetch(control.endpoint.url+'/web/close',{method:'POST',headers,body:JSON.stringify({origin:'http://127.0.0.1:1'})});
 assert.equal((await fetch(opened.origin+'/prefix/')).status,403);
 await fetch(control.endpoint.url+'/web/close',{method:'POST',headers,body:JSON.stringify({origin:opened.origin})});
 await assert.rejects(fetch(opened.origin+'/prefix/'));
 console.log('web proxy passed: same-origin HTTP/POST/WS, credential isolation, redirect rejection, one-use launch and scoped cleanup');
}finally{await control?.close();await proxy?.close();for(const client of wss.clients)client.terminate();wss.close();await new Promise(r=>upstream.close(r));}
