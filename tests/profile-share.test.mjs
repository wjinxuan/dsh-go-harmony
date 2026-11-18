import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,symlinkSync,rmSync,statSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {profilePayload,profileFile,decodeProfileFile,profileSource,selectProfile,planProfile,sanitizeSection,sharedPlugin,shareKind} from '../runtime/share-profile.mjs';
import {readProfileFiles,applyProfileFiles,backupProfile} from '../runtime/share-profile-files.mjs';
import {createShareHandler} from '../runtime/share-service.mjs';
import {startTransportControl} from '../runtime/transport-control.mjs';
const npm={name:'fixture-plugin',source:'npm',version:'1.2.3',spec:'fixture-plugin@1.2.3',integrity:'sha512-YWJj'};
const profile={v:1,kind:'profile',name:'示例',settings:{example:{depth:2}},plugins:[npm],skills:[{name:'sample',files:{'SKILL.md':'# skill','references/a.md':'details'}}],agentsMd:'# shared instructions'};
function root(t){const dir=mkdtempSync(join(tmpdir(),'dsh-profile-'));mkdirSync(join(dir,'workspace'));mkdirSync(join(dir,'profile'));writeFileSync(join(dir,'profile','cordis.patch.yml'),'existing: yes\n');t.after(()=>rmSync(dir,{recursive:true,force:true}));return dir;}
test('upstream plugin/profile wire round trip with exact package specs and strict bounded file paths',()=>{
 const result=profileFile(profile);assert.equal(shareKind(result.code),'profile');assert.deepEqual(decodeProfileFile(result.file).body,result.body);
 assert.equal(decodeProfileFile(profileFile({v:1,kind:'plugin',plugin:npm}).code).body.plugin.spec,npm.spec);
 for(const patch of [{version:'latest'},{spec:'https://example.test/package.tgz'},{name:'../bad'},{source:'official',spec:'evil'}])assert.throws(()=>sharedPlugin({...npm,...patch}));
 assert.equal(sharedPlugin({name:'p',source:'github',spec:'github:owner/repo#abc123'}).source,'github');
 for(const files of [{'../outside':'x','SKILL.md':'x'},{'.hidden':'x','SKILL.md':'x'},{'a/b/c/d/e':'x','SKILL.md':'x'}])assert.throws(()=>profilePayload({...profile,skills:[{name:'s',files}]}));
 assert.throws(()=>profilePayload({...profile,v:2}));assert.throws(()=>profilePayload({...profile,plugins:[npm,npm]}));assert.throws(()=>profilePayload({...profile,agentsMd:'x'.repeat(65537)}));
});
test('export sanitizes serialized schemastery refs, secret paths, account namespaces, URL credentials and absolute paths while preserving refs',()=>{
 const schema={uid:0,refs:{0:{type:'object',dict:{password:1,ref:2,nested:3}},1:{type:'string',meta:{role:'secret'}},2:{type:'string',meta:{role:'credential-ref'}},3:{type:'intersect',list:[4]},4:{type:'object',dict:{hidden:1,kept:5}},5:{type:'number'}}};
 const user={password:'value',ref:'MY_API_KEY',apiKeyEnv:'EXAMPLE_KEY',maxTokens:4096,endpoint:'https://api.example.test/v1',url:'https://u:p@evil.test',other:'https://e.test?a=1&token=abc',path:'/private/data',nested:{hidden:'value',kept:4},accessToken:'value',custom:'value'};
 const clean=sanitizeSection({ns:'llm-fixture',schema,user,secrets:[{path:['custom']}]});
 assert.deepEqual(clean,{ref:'MY_API_KEY',apiKeyEnv:'EXAMPLE_KEY',maxTokens:4096,endpoint:'https://api.example.test/v1',nested:{kept:4}});
 assert.deepEqual(sanitizeSection({ns:'credentials',user:{a:1}}),{});
 const source=profileSource({settings:{namespaces:[{ns:'llm-fixture',schema,user}]},bundles:[{name:'fixture-plugin',installed:true,source:'fixture-plugin@^1',version:'1.2.3'},{name:'local-plugin',installed:true,source:'/tmp/plugin',version:'1.0.0'}]}, {skills:[{name:'secret',files:{'SKILL.md':'API_KEY=not-for-sharing'}}]});
 assert.ok(source.items.find(v=>v.id==='plugin:local-plugin').blocked);assert.ok(source.items.find(v=>v.id==='skill:secret').blocked);
 const selected=selectProfile(source,['plugin:fixture-plugin'],'',true);assert.equal(selected.body.plugin.spec,'fixture-plugin@1.2.3');assert.throws(()=>selectProfile(source,['plugin:local-plugin'],'',true));
});
test('import preview preserves unrelated settings, never shifts lists with secret members, defaults sensitive changes off and blocks integrity mismatch',()=>{
 const raw={...profile,settings:{example:{depth:3,nested:{new:2},rows:[{name:'a',apiKey:'secret'}]},permission:{mode:'auto'},'llm-example':{endpoint:'https://model.test',credential:'REF'}}};
 const plan=planProfile(raw,{canInstall:true,local:false,facts:{'fixture-plugin':{integrity:'sha512-ZGlmZg=='}},settings:{writable:true,namespaces:[{ns:'example',revision:4,value:{depth:1,nested:{kept:1}},schema:{}},{ns:'permission',revision:1,value:{mode:'ask'}},{ns:'llm-example',revision:1,value:{},schema:{type:'object',dict:{credential:{type:'string',meta:{role:'credential-ref'}}}}}]}});
 const settings=plan.changes.find(v=>v.id==='settings:example');assert.deepEqual(settings.ops.map(v=>v.path),[['depth'],['nested','new']]);assert.equal(settings.revision,4);assert.equal(settings.defaultOn,true);
 for(const id of ['settings:permission','settings:llm-example'])assert.equal(plan.changes.find(v=>v.id===id).defaultOn,false);
 assert.match(plan.changes.find(v=>v.id==='plugin:fixture-plugin').blocked,/完整性/);assert.match(plan.changes.find(v=>v.id==='skill:sample').blocked,/只能导入本机/);
 assert.equal(planProfile(profile,{canInstall:false,settings:{namespaces:[]}}).changes[0].defaultOn,false);
});
test('read-only file preview leaves disk untouched; confirmation, exact hashes, backup bytes and cancellation govern imports',t=>{
 const dir=root(t),before=readFileSync(join(dir,'profile','cordis.patch.yml'),'utf8'),files=readProfileFiles(dir,profile);
 assert.equal(files.skills.length,0);assert.throws(()=>applyProfileFiles(dir,{payload:profile,selected:['skill:sample'],expected:files.hashes}),/确认/);
 const applied=applyProfileFiles(dir,{payload:profile,selected:['skill:sample','agents-md'],expected:files.hashes,confirmed:true});
 assert.deepEqual(applied.done,['skill:sample','agents-md']);assert.equal(readFileSync(join(dir,'workspace','.dsh','skills','sample','SKILL.md'),'utf8'),'# skill');
 assert.equal(readFileSync(join(dir,'workspace','AGENTS.md'),'utf8'),'# shared instructions');assert.equal(readFileSync(join(dir,applied.backup,'cordis.patch.yml'),'utf8'),before);
 assert.equal(statSync(join(dir,applied.backup)).mode&0o777,0o700);assert.equal(statSync(join(dir,'workspace','AGENTS.md')).mode&0o777,0o600);
 assert.throws(()=>applyProfileFiles(dir,{payload:profile,selected:['skill:sample'],expected:files.hashes,confirmed:true}),/文件已更改/);
 const controller=new AbortController();controller.abort();assert.throws(()=>applyProfileFiles(dir,{payload:profile,selected:[],expected:{},confirmed:true},controller.signal));
 const current=readProfileFiles(dir,profile),second={...profile,skills:[{name:'sample',files:{'SKILL.md':'replacement'}}]};
 const update=applyProfileFiles(dir,{payload:second,selected:['skill:sample'],expected:current.hashes,confirmed:true});assert.equal(readFileSync(join(dir,update.backup,'skills','sample','references','a.md'),'utf8'),'details');
 assert.equal(readFileSync(join(dir,'profile','cordis.patch.yml'),'utf8'),before);
});
test('existing symlinks, ambiguous skills, unsafe extra files and stale AGENTS never permit destructive replacement',t=>{
 const dir=root(t),skills=join(dir,'workspace','.dsh','skills');mkdirSync(skills,{recursive:true});mkdirSync(join(skills,'sample'));writeFileSync(join(skills,'sample','SKILL.md'),'old');writeFileSync(join(skills,'sample','.private'),'preserve');
 let current=readProfileFiles(dir,profile);assert.ok(current.errors['skill:sample']);assert.throws(()=>applyProfileFiles(dir,{payload:profile,selected:['skill:sample'],expected:current.hashes,confirmed:true}));assert.equal(readFileSync(join(skills,'sample','.private'),'utf8'),'preserve');
 rmSync(join(skills,'sample'),{recursive:true});symlinkSync(join(dir,'profile'),join(skills,'sample'));current=readProfileFiles(dir,profile);assert.ok(current.errors['skill:sample']);
 writeFileSync(join(dir,'workspace','AGENTS.md'),'changed');assert.throws(()=>applyProfileFiles(dir,{payload:profile,selected:['agents-md'],expected:{'agents-md':'0'.repeat(64)},confirmed:true}),/文件已更改/);
});
test('authenticated service routes three kinds, never mutates during plan, and verifies npm integrity at fixed no-redirect endpoint',async t=>{
 const dir=root(t);let requests=0;
 const control=await startTransportControl({share:createShareHandler(dir,{fetcher:async(url,request)=>{requests++;assert.equal(url,'https://registry.npmjs.org/fixture-plugin/1.2.3');assert.equal(request.redirect,'error');return new Response(JSON.stringify({name:npm.name,version:npm.version,dist:{integrity:npm.integrity}}))}})});t.after(()=>control.close());
 async function call(action,body){const r=await fetch(control.endpoint.url+'/share/'+action,{method:'POST',headers:{authorization:control.endpoint.authorization,'content-type':'application/json'},body:JSON.stringify(body)});assert.equal(r.status,200);return r.json()}
 assert.equal((await call('decode',{text:profileFile(profile).code})).body.kind,'profile');
 const plan=await call('profile-plan',{payload:profile,snapshot:{local:true,canInstall:true,settings:{namespaces:[]}}});assert.equal(plan.changes[0].integrity,'verified');assert.equal(requests,1);assert.throws(()=>readFileSync(join(dir,'workspace','AGENTS.md')));
});
