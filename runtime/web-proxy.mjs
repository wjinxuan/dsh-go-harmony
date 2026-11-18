import { randomBytes, timingSafeEqual } from 'node:crypto';
import { createServer, request as httpRequest } from 'node:http';
import { request as httpsRequest } from 'node:https';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { WebSocket, WebSocketServer } = require('ws');
const hop = new Set(['connection','keep-alive','proxy-authenticate','proxy-authorization','te','trailer','transfer-encoding','upgrade','host']);
function equal(a, b) { const x=Buffer.from(a ?? ''), y=Buffer.from(b); return x.length===y.length && timingSafeEqual(x,y); }
export function webSession(value) {
  if (!value || typeof value !== 'object' || typeof value.baseUrl !== 'string' || value.baseUrl.length > 4096 || /[\x00-\x20\x7f\\]/.test(value.baseUrl)) throw Error('Invalid web session');
  const base = new URL(value.baseUrl);
  if (base.username || base.password || base.search || base.hash ||
      !(base.protocol==='https:' || (base.protocol==='http:' && ['127.0.0.1','[::1]'].includes(base.hostname)))) throw Error('Invalid web session');
  if (typeof value.cookie !== 'string' || !/^dsh-auth-[A-Za-z0-9_-]+=[A-Za-z0-9._~%=-]+$/.test(value.cookie) || value.cookie.length > 8192 ||
      typeof value.authorization !== 'string' || value.authorization.length > 4096 || /[\x00-\x1f\x7f]/.test(value.authorization)) throw Error('Invalid web credentials');
  return { base, prefix: base.pathname.replace(/\/+$/, ''), cookie: value.cookie, authorization: value.authorization };
}
export async function openWebProxy(input) {
  const session = webSession(input), secret = randomBytes(32).toString('base64url');
  const cookieName = `dsh-web-${randomBytes(8).toString('hex')}`;
  const pending = new Set(), peers = new Set();
  const wsServer = new WebSocketServer({ noServer: true, maxPayload: 16*1024*1024, perMessageDeflate: false });
  let origin, closed=false, launchUsed=false, timer;
  const touch = () => { clearTimeout(timer); timer=setTimeout(()=>{ void close(); }, 15*60*1000); timer.unref(); };
  const inScope = path => path === session.prefix || path.startsWith(session.prefix + '/');
  const authorized = request => request.headers.host === origin.slice(7) &&
    (!request.headers.origin || request.headers.origin === origin) &&
    (request.headers.cookie ?? '').split(';').some(pair => equal(pair.trim(), `${cookieName}=${secret}`));
  function headersFor(request) {
    const headers={};
    for(const [key,value] of Object.entries(request.headers)) {
      if (!hop.has(key) && !['authorization','cookie','origin','referer','sec-fetch-site','sec-websocket-key','sec-websocket-version','sec-websocket-extensions','sec-websocket-protocol'].includes(key) && value !== undefined) headers[key]=value;
    }
    headers.host=session.base.host; headers.cookie=session.cookie;
    if(session.authorization) headers.authorization=session.authorization;
    if(request.headers.origin) headers.origin=session.base.origin;
    if(request.headers.referer) headers.referer=session.base.origin + session.prefix + '/';
    return headers;
  }
  function requestPath(request) {
    if (!request.url?.startsWith('/') || request.url.startsWith('//') || request.url.includes('\\')) throw Error('Invalid path');
    const address=new URL(request.url, origin);
    if(address.origin!==origin || !inScope(address.pathname) || /%2f|%5c|%00/i.test(address.pathname)) throw Error('Invalid path');
    return address;
  }
  const server=createServer({requestTimeout:600000,headersTimeout:10000}, (request,response)=>{
    if(closed || request.headers.host!==origin.slice(7)) { response.writeHead(403).end();return; }
    let address;
    try { address=requestPath(request); } catch {response.writeHead(403).end();return;}
    if(request.method==='GET' && address.pathname===session.prefix+'/' && address.searchParams.has('__dsh_web_token')) {
      if(launchUsed || !equal(address.searchParams.get('__dsh_web_token'),secret) || request.headers.origin) {response.writeHead(403).end();return;}
      launchUsed=true;touch();response.writeHead(303,{location:session.prefix+'/', 'set-cookie':`${cookieName}=${secret}; Path=${session.prefix || '/'}; HttpOnly; SameSite=Strict`, 'cache-control':'no-store','referrer-policy':'no-referrer'}).end();return;
    }
    if(!authorized(request)) {response.writeHead(403).end();return;} touch();
    const target=new URL(address.pathname+address.search,session.base.origin);
    const upstream=(target.protocol==='https:'?httpsRequest:httpRequest)(target,{method:request.method,headers:headersFor(request)},remote=>{
      const headers={};
      for(const [key,value] of Object.entries(remote.headers)) if(!hop.has(key) && !['set-cookie','location','alt-svc','clear-site-data'].includes(key) && value!==undefined) headers[key]=value;
      if(remote.headers.location) {
        let location;
        try { location=new URL(remote.headers.location,target); } catch { remote.destroy();response.writeHead(502).end();return; }
        if(location.origin!==session.base.origin || !inScope(location.pathname)) {remote.destroy();response.writeHead(502).end();return;}
        headers.location=location.pathname+location.search+location.hash;
      }
      headers['cache-control']='no-store'; headers['referrer-policy']='no-referrer';
      response.writeHead(remote.statusCode??502,headers); remote.pipe(response);
      remote.on('error',()=>response.destroy());
    });
    pending.add(upstream);upstream.on('close',()=>pending.delete(upstream));
    upstream.setTimeout(600000,()=>upstream.destroy());
    upstream.on('error',()=>{if(!response.headersSent)response.writeHead(502).end();else response.destroy();});
    request.on('aborted',()=>upstream.destroy());response.on('close',()=>upstream.destroy());request.pipe(upstream);
  });
  server.maxConnections=40;
  server.on('upgrade',(request,socket,head)=>{
    let address; try {address=requestPath(request);}catch{socket.destroy();return;}
    if(closed || !authorized(request)) {socket.destroy();return;}touch();
    const target=new URL(address.pathname+address.search,session.base.origin);target.protocol=target.protocol==='https:'?'wss:':'ws:';
    const rawProtocols=request.headers['sec-websocket-protocol'];
    const protocols=typeof rawProtocols==='string'?rawProtocols.split(',').map(x=>x.trim()).filter(Boolean):[];
    const upstream=new WebSocket(target,protocols,{headers:headersFor(request),origin:session.base.origin,followRedirects:false,handshakeTimeout:10000,maxPayload:16*1024*1024,perMessageDeflate:false});
    peers.add(upstream);upstream.on('close',()=>peers.delete(upstream));upstream.on('error',()=>socket.destroy());
    socket.on('close',()=>{if(upstream.readyState!==WebSocket.CLOSED)upstream.terminate();});
    upstream.once('open',()=>{
      if(socket.destroyed || closed) {upstream.terminate();return;}
      // Reflect exactly the upstream-selected subprotocol; browser and service see identical framing.
      wsServer.options.handleProtocols=offered=>upstream.protocol && offered.has(upstream.protocol)?upstream.protocol:false;
      wsServer.handleUpgrade(request,socket,head,downstream=>{
        peers.add(downstream);downstream.on('close',()=>peers.delete(downstream));
        function pipe(from,to) {
          from.on('message',(data,binary)=>{
            touch();if(to.readyState!==WebSocket.OPEN || to.bufferedAmount>16*1024*1024){from.terminate();to.terminate();return;}
            to.send(data,{binary},error=>{if(error){from.terminate();to.terminate();}});
          });
          from.on('close',(code,reason)=>{ if(to.readyState===WebSocket.OPEN) to.close(code===1005||code===1006?1000:code,reason); else if(to.readyState===WebSocket.CONNECTING)to.terminate(); });
          from.on('error',()=>to.terminate());
        }
        pipe(downstream,upstream);pipe(upstream,downstream);
      });
    });
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',()=>{server.off('error',reject);resolve();});});
  origin=`http://127.0.0.1:${server.address().port}`;touch();
  async function close() {
    if(closed)return;closed=true;clearTimeout(timer);
    for(const request of pending)request.destroy();for(const peer of peers)peer.terminate();
    const done=new Promise(resolve=>server.close(resolve));server.closeAllConnections();wsServer.close();await done;
  }
  return { launchUrl:origin+session.prefix+'/?__dsh_web_token='+secret, origin, close };
}
export function createWebProxyHandler() {
  let active, queue=Promise.resolve();
  const reply=(response,status,value)=>response.writeHead(status,{'content-type':'application/json','cache-control':'no-store'}).end(JSON.stringify(value));
  return {
    handle(request,response) {
      if(!['/web/open','/web/close'].includes(request.url) || request.method!=='POST')return false;
      void (async()=>{
        const chunks=[];let bytes=0;
        for await(const chunk of request){bytes+=chunk.length;if(bytes>16384)throw Error('Too large');chunks.push(chunk);}
        const value=JSON.parse(Buffer.concat(chunks).toString('utf8'));
        const operation=async()=>{
          if(request.url==='/web/open')webSession(value);
          else if (!active || value?.origin !== active.origin) {reply(response,200,{closed:true});return;}
          await active?.close();active=undefined;
          if(request.url==='/web/open')active=await openWebProxy(value);
          reply(response,200,active?{launchUrl:active.launchUrl,origin:active.origin}:{closed:true});
        };
        queue=queue.then(operation,operation);await queue;
      })().catch(()=>{if(!response.destroyed&&!response.headersSent)reply(response,400,{error:'网页连接未能建立'});});
      return true;
    },
    async close(){await queue.catch(()=>{});await active?.close();active=undefined;}
  };
}
