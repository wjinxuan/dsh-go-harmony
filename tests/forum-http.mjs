import assert from'node:assert/strict';import{createServer}from'node:http';import{mkdtemp,rm}from'node:fs/promises';import{join}from'node:path';import{tmpdir}from'node:os';import{randomBytes,publicEncrypt,constants}from'node:crypto';import{pathToFileURL}from'node:url';
const runtime=process.argv[2];const{ForumService,createForumHandler}=await import(pathToFileURL(runtime+'/forum-service.mjs'));const{startTransportControl}=await import(pathToFileURL(runtime+'/transport-control.mjs'));
const requests=[];let mode='ok';
const server=createServer((req,res)=>{let body='';req.on('data',chunk=>body+=chunk);req.on('end',()=>{
 requests.push({url:req.url,method:req.method,headers:req.headers,body});res.setHeader('content-type','application/json');
 if(mode==='redirect'){res.writeHead(302,{location:'https://example.test/'}).end('{}');return;}
 if(mode==='invalid'){res.end('<html>login</html>');return;}
 if(mode==='forbidden'){res.writeHead(403).end('{"errors":["forbidden"]}');return;}
 if(mode==='reject'){res.writeHead(422).end('{"errors":["private-api-key rejected"]}');return;}
 if(req.url==='/sub/session/current.json')res.end('{"current_user":{"id":1,"username":"http-user"}}');
 else if(req.url==='/sub/posts.json')res.end('{"post":{"id":4,"topic_id":2,"cooked":"<p>Posted</p>"}}');
 else res.end('{"categories":[],"success":true}');
});});await new Promise(r=>server.listen(0,'127.0.0.1',r));const base=`http://127.0.0.1:${server.address().port}/sub`;
const root=await mkdtemp(join(tmpdir(),'forum-http-'));let control;
try{
 control=await startTransportControl({forum:createForumHandler(root)});
 const invoke=async(action,args={})=>{const res=await fetch(control.endpoint.url+'/forum/call',{method:'POST',headers:{authorization:control.endpoint.authorization,'content-type':'application/json'},body:JSON.stringify({action,args:{expectedBase:base,...args}})});return{status:res.status,value:await res.json()};};
 assert.equal((await fetch(control.endpoint.url+'/forum/call',{method:'POST',body:'{}'})).status,403);
 await invoke('unlock',{masterKey:randomBytes(32).toString('base64url')});await invoke('setBase',{baseUrl:base});
 await invoke('site');assert.equal(requests.at(-1).headers['user-api-key'],undefined);assert.equal(requests.at(-1).url,'/sub/site.json');
 const authorization=new URL((await invoke('begin')).value.url);
 const payload=publicEncrypt({key:authorization.searchParams.get('public_key'),padding:constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha1'},Buffer.from(JSON.stringify({key:'private-api-key',nonce:authorization.searchParams.get('nonce')}))).toString('base64');
 assert.equal((await invoke('complete',{redirect:'dshgo://forum/auth?payload='+encodeURIComponent(payload)})).value.signedIn,true);
 const posted=await invoke('createTopic',{title:'你好',raw:'text + &',categoryId:2});assert.equal(posted.value.post.native_markdown,'Posted');const last=requests.at(-1);assert.equal(last.headers['user-api-key'],'private-api-key');assert.equal(last.headers['user-api-client-id'],authorization.searchParams.get('client_id'));const form=new URLSearchParams(last.body);assert.equal(form.get('raw'),'text + &');assert.equal(form.get('title'),'你好');
 await invoke('upload',{filename:'test.png',data:Buffer.from([1,2,3]).toString('base64')});assert.match(requests.at(-1).headers['content-type'],/^multipart\/form-data; boundary=/);assert.match(requests.at(-1).body,/name="synchronous"/);
 mode='redirect';assert.equal((await invoke('site')).status,400);assert.equal(requests.at(-1).url,'/sub/site.json');
 mode='invalid';assert.equal((await invoke('site')).value.error.kind,'server');
 mode='reject';const error=(await invoke('createTopic',{title:'x',raw:'y'})).value.error;assert.equal(error.kind,'rejected');assert.doesNotMatch(error.message,/private-api-key/);
 mode='forbidden';await invoke('site');assert.equal((await invoke('state')).value.signedIn,false);
 console.log('Forum HTTP passed: actual authenticated loopback control, real Discourse HTTP/form/multipart, key headers, redirect refusal, malformed JSON, sanitized errors and revoked-key expiry');
}finally{await control?.close();await new Promise(r=>server.close(r));await rm(root,{recursive:true,force:true});}
