// Discourse protocol port of dsh-Go app/lib/forum at a9877420ab9aee121134faf01b6a92a39ce0b05b.
import { generateKeyPair, privateDecrypt, constants, randomBytes } from 'node:crypto';
import { promisify } from 'node:util';
import { request as httpsRequest } from 'node:https';
import { request as httpRequest } from 'node:http';
import { createRequire } from 'node:module';
import { PrivateVault } from './private-vault.mjs';
const require=createRequire(import.meta.url);const Turndown=require('turndown');const domino=require('@mixmark-io/domino');
const keyPair=promisify(generateKeyPair);
export const FORUM_DEFAULT='https://forum.dshtui.com';
export class ForumError extends Error {constructor(kind,message){super(message);this.kind=kind;}}
const invalid=()=>new ForumError('invalid','社区操作参数无效');
export function normalizeForumBase(input) {
  let text=String(input??'').trim();if(!text)return FORUM_DEFAULT;if(!text.includes('://'))text='https://'+text;
  if(text.length>2048||/[\x00-\x20\x7f\\]/.test(text))throw invalid();
  let value;try{value=new URL(text);}catch{throw invalid();}
  if(value.username||value.password||value.search||value.hash||!value.hostname||
    !(value.protocol==='https:'||(value.protocol==='http:'&&['127.0.0.1','[::1]','localhost'].includes(value.hostname))))throw invalid();
  return value.origin+value.pathname.replace(/\/+$/,'');
}
const id=value=>{if(!Number.isSafeInteger(value)||value<1)throw invalid();return value;};
const text=(value,max=200000)=>{if(typeof value!=='string'||!value.trim()||value.length>max||value.includes('\0'))throw invalid();return value;};
const page=(value,first=0)=>{if(value===undefined)return first;if(!Number.isSafeInteger(value)||value<first||value>100000)throw invalid();return value;};
function publicError(status,body,credential) {
  const kind=({401:'unauthorized',403:'forbidden',404:'notFound',410:'notFound',429:'rateLimited',400:'rejected',409:'rejected',422:'rejected'})[status]??'server';
  const generic=({unauthorized:'社区登录已失效，请重新登录',forbidden:'当前账号没有此操作权限',notFound:'内容不存在或已删除',rateLimited:'操作过于频繁，请稍后再试',rejected:'社区拒绝了这次操作',server:'社区服务暂时不可用'})[kind];
  let detail=Array.isArray(body?.errors)?body.errors.find(x=>typeof x==='string'):undefined;
  if(typeof detail==='string'){detail=detail.slice(0,500);if(credential?.key)detail=detail.replaceAll(credential.key,'[已隐藏]');}
  return new ForumError(kind,['rejected','forbidden'].includes(kind)&&detail?detail:generic);
}
async function send(base,path,{method='GET',query,form,body,headers={},credential,signal,timeout=20000}={}) {
  const address=new URL(base+path);if(query)for(const[key,value]of Object.entries(query)){for(const item of Array.isArray(value)?value:[value])address.searchParams.append(key,String(item));}
  const outgoing={accept:'application/json',...headers};
  if(credential){outgoing['User-Api-Key']=credential.key;outgoing['User-Api-Client-Id']=credential.client;}
  if(form){body=Buffer.from(new URLSearchParams(form).toString());outgoing['content-type']='application/x-www-form-urlencoded';}
  if(body)outgoing['content-length']=body.length;
  return new Promise((resolve,reject)=>{
    let finished=false;const fail=error=>{if(finished)return;finished=true;reject(error instanceof ForumError?error:new ForumError('network','无法连接社区，请检查网络后重试'));};
    const request=(address.protocol==='https:'?httpsRequest:httpRequest)(address,{method,headers:outgoing,signal:signal?AbortSignal.any([signal,AbortSignal.timeout(timeout)]):AbortSignal.timeout(timeout)},response=>{
      const chunks=[];let bytes=0;
      response.on('data',chunk=>{bytes+=chunk.length;if(bytes>8*1024*1024){request.destroy();fail(new ForumError('server','社区返回内容过大'));}else chunks.push(chunk);});
      response.on('error',fail);response.on('end',()=>{
        if(finished)return;let value;
        try{value=bytes?JSON.parse(Buffer.concat(chunks).toString('utf8')):null;}catch{fail(new ForumError('server','社区返回格式无效'));return;}
        if(response.statusCode<200||response.statusCode>=300){fail(publicError(response.statusCode,value,credential));return;}
        if(Array.isArray(value?.errors)&&value.errors.length&&value.success!==true){fail(publicError(422,value,credential));return;}
        finished=true;resolve(value);
      });
    });
    request.setTimeout(timeout,()=>request.destroy());request.on('error',fail);request.end(body);
  });
}
export function forumMarkdown(html,base) {
  if(typeof html!=='string'||html.length>1024*1024)return '';
  const service=new Turndown({headingStyle:'atx',codeBlockStyle:'fenced'});service.remove(['script','style','iframe','object','embed','form','input','button']);
  const safe=value=>{try{const address=new URL(value,base+'/');return ['https:','http:','dshgo:'].includes(address.protocol)?address.href:'';}catch{return '';}};
  service.addRule('safe-link',{filter:'a',replacement:(content,node)=>{const href=safe(node.getAttribute('href'));return href?'['+content.replace(/\]/g,'\\]')+']('+href.replace(/\)/g,'%29')+')':content;}});
  service.addRule('image',{filter:'img',replacement:(_,node)=>{const src=safe(node.getAttribute('src'));return src?'\n[图片：'+(node.getAttribute('alt')||'查看图片')+']('+src+')\n':'';}});
  service.addRule('table',{filter:'table',replacement:(_,node)=>{
    const rows=Array.from(node.querySelectorAll('tr')).slice(0,100).map(row=>Array.from(row.querySelectorAll('th,td')).slice(0,20).map(cell=>cell.textContent.replace(/\|/g,'\\|').replace(/\s+/g,' ').trim()));
    if(!rows.length)return '';const width=Math.max(...rows.map(row=>row.length));const line=row=>'| '+Array.from({length:width},(_,i)=>row[i]??'').join(' | ')+' |';return '\n\n'+line(rows[0])+'\n'+line(Array(width).fill('---'))+'\n'+rows.slice(1).map(line).join('\n')+'\n\n';
  }});
  service.addRule('discourse-quote',{filter:node=>node.nodeName==='ASIDE'&&node.classList.contains('quote'),replacement:content=>'\n\n'+content.trim().replace(/^/gm,'> ')+'\n\n'});
  service.addRule('details',{filter:'details',replacement:content=>'\n\n'+content.trim()+'\n\n'});
  service.addRule('media',{filter:['video','audio'],replacement:(_,node)=>{const source=safe(node.getAttribute('src')||node.querySelector('source')?.getAttribute('src'));return source?'\n[播放媒体]('+source+')\n':'';}});
  return service.turndown(html);
}
function withMarkdown(value,base) {
  if(!value||typeof value!=='object')return value;
  const posts=value.post_stream?.posts??value.posts??(value.post?[value.post]:value.cooked?[value]:[]);
  for(const post of posts)if(post&&typeof post==='object'){
    post.native_markdown=forumMarkdown(post.cooked,base);
    post.native_images=[];
    if(typeof post.cooked==='string'&&post.cooked.length<=1024*1024){
      const document=domino.createWindow(post.cooked).document;
      for(const image of Array.from(document.querySelectorAll('img:not(.emoji)')).slice(0,20)){
        try{const url=new URL(image.getAttribute('src'),base+'/');if(['http:','https:'].includes(url.protocol)&&!url.username&&!url.password)post.native_images.push(url.href);}catch{}
      }
    }
  }
  return value;
}
export class ForumService {
  constructor(root,{transport=send,now=Date.now}={}){this.root=root;this.transport=transport;this.now=now;this.vault=undefined;this.state=undefined;this.queue=Promise.resolve();this.controller=new AbortController();}
  async unlock(masterKey){
    if(this.vault){const candidate=new PrivateVault(this.root,'.harmony-forum-vault.json',masterKey);try{await candidate.load();}finally{candidate.destroy();}return this.status();}
    const vault=new PrivateVault(this.root,'.harmony-forum-vault.json',masterKey);
    try{const state=await vault.load()??{version:1,baseUrl:FORUM_DEFAULT,sessions:{}};if(state.version!==1||!state.sessions||typeof state.sessions!=='object')throw invalid();state.baseUrl=normalizeForumBase(state.baseUrl);this.state=state;this.vault=vault;await this.save();return this.status();}catch(error){vault.destroy();throw error;}
  }
  status(){this.requireUnlocked();const credential=this.state.sessions[this.state.baseUrl];return {baseUrl:this.state.baseUrl,signedIn:!!credential?.key,waiting:!!this.state.pending&&this.state.pending.base===this.state.baseUrl&&this.now()-this.state.pending.at<15*60*1000,user:credential?.user??null};}
  requireUnlocked(){if(!this.vault||!this.state)throw new ForumError('locked','请解锁手机后打开社区');}
  save(){return this.vault.save(this.state);}
  async request(base,path,options={}){
    const credential=this.state.sessions[base];
    try{return withMarkdown(await this.transport(base,path,{...options,credential,signal:this.controller.signal}),base);}
    catch(error){
      if(credential&&['unauthorized','forbidden'].includes(error.kind)){
        let expired=path==='/session/current.json'||path==='/site.json';
        if(!expired)try{await this.transport(base,'/session/current.json',{credential,signal:this.controller.signal});}catch(check){expired=['unauthorized','forbidden','notFound'].includes(check.kind);}
        if(expired&&this.state.sessions[base]?.key===credential.key){delete this.state.sessions[base];await this.save();}
      }
      throw error;
    }
  }
  async dispatch(action,args={}){
    if(action==='unlock')return this.unlock(args.masterKey);
    this.requireUnlocked();
    if(action!=='complete'&&action!=='state'&&action!=='setBase'&&args.expectedBase!==this.state.baseUrl)throw new ForumError('changed','社区地址已切换，请刷新后重试');
    const base=this.state.baseUrl;
    if(action==='state')return this.status();
    if(action==='setBase'){this.state.baseUrl=normalizeForumBase(args.baseUrl);await this.save();return this.status();}
    if(action==='begin'){
      if(!this.state.rsa){const pair=await keyPair('rsa',{modulusLength:2048,publicKeyEncoding:{type:'spki',format:'pem'},privateKeyEncoding:{type:'pkcs8',format:'pem'}});this.state.rsa=pair;}
      this.state.client??=randomBytes(16).toString('hex');const nonce=randomBytes(16).toString('hex');this.state.pending={nonce,base,at:this.now()};await this.save();
      const address=new URL(base+'/user-api-key/new');for(const[key,value]of Object.entries({application_name:'dsh-go',client_id:this.state.client,scopes:'read,write,notifications,session_info',public_key:this.state.rsa.publicKey,nonce,auth_redirect:'dshgo://forum/auth',padding:'oaep'}))address.searchParams.set(key,value);
      return {url:address.href};
    }
    if(action==='complete'){
      const address=new URL(text(args.redirect,8192));if(address.protocol!=='dshgo:'||address.hostname!=='forum'||address.pathname!=='/auth'||address.searchParams.getAll('payload').length!==1)throw invalid();
      const pending=this.state.pending;if(!pending||this.now()-pending.at>=15*60*1000||!this.state.rsa)throw new ForumError('expired','登录请求已过期，请重新登录');
      let clear;try{
        const payload=address.searchParams.get('payload').replace(/\s/g,'');if(!/^[A-Za-z0-9+/]+={0,2}$/.test(payload))throw invalid();
        clear=privateDecrypt({key:this.state.rsa.privateKey,padding:constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha1'},Buffer.from(payload,'base64'));
        const value=JSON.parse(clear.toString('utf8'));if(value.nonce!==pending.nonce||typeof value.key!=='string'||!value.key||value.key.length>4096||/[\x00-\x20\x7f]/.test(value.key))throw invalid();
        this.state.sessions[pending.base]={key:value.key,client:this.state.client};delete this.state.pending;await this.save();
      }catch{throw new ForumError('rejected','社区登录未完成，请重新发起登录');}finally{clear?.fill(0);}
      if(pending.base===base)try{await this.refreshUser(base);}catch{}return this.status();
    }
    if(action==='cancel'){delete this.state.pending;await this.save();return this.status();}
    if(action==='signOut'){const credential=this.state.sessions[base];delete this.state.sessions[base];delete this.state.pending;await this.save();if(credential)try{await this.transport(base,'/user-api-key/revoke',{method:'POST',credential,signal:this.controller.signal});}catch{}return this.status();}
    if(action==='refreshUser'){await this.refreshUser(base);return this.status();}
    if(action==='site')return this.request(base,'/site.json');
    if(action==='topics'){
      const path=args.kind==='category'?`/c/${encodeURIComponent(text(args.slug,128))}/${id(args.categoryId)}/l/latest.json`:args.kind==='top'?'/top.json':args.kind==='latest'?'/latest.json':null;if(!path)throw invalid();
      return this.request(base,path,{query:{page:page(args.page),...(args.kind==='top'?{period:'monthly'}:{})}});
    }
    if(action==='topic')return this.request(base,`/t/${id(args.id)}.json`);
    if(action==='posts'){if(!Array.isArray(args.ids)||args.ids.length>100)throw invalid();return this.request(base,`/t/${id(args.topicId)}/posts.json`,{query:{'post_ids[]':args.ids.map(id)}});}
    if(action==='search')return this.request(base,'/search.json',{query:{q:text(args.query,1000),page:page(args.page,1)}});
    if(action==='user')return this.request(base,`/u/${encodeURIComponent(text(args.username,128))}/summary.json`);
    if(!this.state.sessions[base]?.key)throw new ForumError('unauthorized','请先登录社区');
    if(action==='notifications')return this.request(base,'/notifications.json',{query:{limit:30,offset:page(args.offset)}});
    if(action==='markRead')return this.request(base,'/notifications/mark-read.json',{method:'PUT',form:args.id?{id:id(args.id)}:{}});
    if(action==='createTopic')return this.request(base,'/posts.json',{method:'POST',form:{title:text(args.title,255),raw:text(args.raw),archetype:'regular',...(args.categoryId?{category:id(args.categoryId)}:{})}});
    if(action==='reply')return this.request(base,'/posts.json',{method:'POST',form:{topic_id:id(args.topicId),raw:text(args.raw),...(args.replyTo?{reply_to_post_number:id(args.replyTo)}:{})}});
    if(action==='like')return this.request(base,'/post_actions.json',{method:'POST',form:{id:id(args.id),post_action_type_id:2,flag_topic:'false'}});
    if(action==='unlike')return this.request(base,`/post_actions/${id(args.id)}.json`,{method:'DELETE',query:{post_action_type_id:2}});
    if(action==='bookmark')return this.request(base,'/bookmarks.json',{method:'POST',form:{bookmarkable_id:id(args.id),bookmarkable_type:'Post'}});
    if(action==='unbookmark')return this.request(base,`/bookmarks/${id(args.id)}.json`,{method:'DELETE'});
    if(action==='upload'){
      const name=text(args.filename,128);if(/[\x00-\x1f\x7f"/\\]/.test(name)||typeof args.data!=='string'||args.data.length>14*1024*1024||!/^[A-Za-z0-9+/]*={0,2}$/.test(args.data))throw invalid();
      const bytes=Buffer.from(args.data,'base64');if(!bytes.length||bytes.length>10*1024*1024)throw invalid();const boundary='dsh-'+randomBytes(24).toString('hex');
      const body=Buffer.concat([Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="type"\r\n\r\ncomposer\r\n--${boundary}\r\nContent-Disposition: form-data; name="synchronous"\r\n\r\ntrue\r\n--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${name}"\r\nContent-Type: application/octet-stream\r\n\r\n`),bytes,Buffer.from(`\r\n--${boundary}--\r\n`)]);
      return this.request(base,'/uploads.json',{method:'POST',headers:{'content-type':`multipart/form-data; boundary=${boundary}`},body,timeout:90000});
    }
    throw invalid();
  }
  async refreshUser(base){const user=await this.request(base,'/session/current.json');if(!user?.current_user?.username){delete this.state.sessions[base];await this.save();throw new ForumError('unauthorized','社区登录已失效');}const credential=this.state.sessions[base];if(credential){credential.user=user.current_user;await this.save();}}
  call(action,args){const operation=()=>this.dispatch(action,args);const work=this.queue.then(operation,operation);this.queue=work.catch(()=>{});return work;}
  async close(){this.controller.abort();await this.queue;this.vault?.destroy();this.vault=undefined;this.state=undefined;}
}
export function createForumHandler(root){
  const service=new ForumService(root);
  return {handle(request,response){
    if(request.method!=='POST'||request.url!=='/forum/call')return false;
    void(async()=>{
      const chunks=[];let bytes=0;for await(const chunk of request){bytes+=chunk.length;if(bytes>15*1024*1024)throw invalid();chunks.push(chunk);}
      const value=JSON.parse(Buffer.concat(chunks).toString('utf8'));if(typeof value.action!=='string'||!value.args||typeof value.args!=='object')throw invalid();
      const result=await service.call(value.action,value.args);response.writeHead(200,{'content-type':'application/json','cache-control':'no-store'}).end(JSON.stringify(result??null));
    })().catch(error=>{if(!response.destroyed&&!response.headersSent)response.writeHead(400,{'content-type':'application/json','cache-control':'no-store'}).end(JSON.stringify({error:{kind:error instanceof ForumError?error.kind:'internal',message:error instanceof ForumError?error.message:'社区操作未能完成，请重试'}}));});return true;
  },close:()=>service.close()};
}
