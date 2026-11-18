import { constants, lstatSync, readdirSync, mkdirSync, openSync, closeSync, fstatSync, readFileSync, writeFileSync, fsyncSync, renameSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { sharedSkill, safeSkillPath, profilePayload } from './share-profile.mjs';
const missing = e => e.code === 'ENOENT';
function info(path) { try { return lstatSync(path); } catch(e) { if(missing(e))return undefined;throw e; } }
function directory(path, create=false) { const stat=info(path);if(!stat){if(create)mkdirSync(path,{mode:0o700});return create;}if(!stat.isDirectory()||stat.isSymbolicLink())throw new Error('分享文件目录不安全');return true; }
function readText(path) { let fd;try{fd=openSync(path,constants.O_RDONLY|constants.O_NOFOLLOW|constants.O_NONBLOCK);const stat=fstatSync(fd);if(!stat.isFile()||stat.size>262144)throw new Error('文件过大或类型不支持');const bytes=readFileSync(fd);const text=new TextDecoder('utf-8',{fatal:true}).decode(bytes);if(text.length>65536)throw new Error('文件过大');return text;}catch(e){if(missing(e))return undefined;throw e;}finally{if(fd!==undefined)closeSync(fd);} }
const hash = v => createHash('sha256').update(JSON.stringify(v??null)).digest('hex');
function rootPaths(root) { directory(root);const workspace=join(root,'workspace');directory(workspace);return {workspace,dsh:join(workspace,'.dsh'),agents:join(workspace,'.agents')}; }
function readSkill(root,name) {
  if(!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(name))throw new Error('技能名称无效');
  if(!directory(root))return undefined;
  const folder=join(root,name),flat=join(root,name+'.md'),a=info(folder),b=info(flat);
  if(a&&b)throw new Error('存在同名技能目录和文件，无法安全替换');
  if(!a&&!b)return undefined;
  if(b)return {name,files:{'SKILL.md':readText(flat)}};
  directory(folder);const files=Object.create(null);let count=0;
  function walk(dir,prefix=''){for(const entry of readdirSync(dir,{withFileTypes:true})){if(++count>48)throw new Error('技能文件过多');const rel=prefix+entry.name;if(!safeSkillPath(rel))throw new Error('技能包含不能完整备份的文件');const path=join(dir,entry.name);if(entry.isDirectory()){if(rel.split('/').length>=4)throw new Error('技能目录过深');directory(path);walk(path,rel+'/');}else{if(!entry.isFile()||Object.keys(files).length>=12)throw new Error('技能包含不支持的文件');files[rel]=readText(path);}}}walk(folder);return sharedSkill({name,files});
}
function pathsFor(root) { const p=rootPaths(root);return {...p,skills:join(p.dsh,'skills'),sharedSkills:join(p.agents,'skills'),agentsFile:join(p.workspace,'AGENTS.md')}; }
export function readProfileFiles(root, payload) {
  const p=pathsFor(root),skills=[],hashes={},errors={};
  const names=payload?.skills?.map(v=>v.name);
  if(names){for(const name of names){try{directory(p.dsh);const value=readSkill(p.skills,name);if(value)skills.push(value);hashes['skill:'+name]=hash(value);}catch{errors['skill:'+name]='现有技能不能完整读取或备份，已阻止替换';}}}
  else for(const parent of [p.dsh,p.agents]){if(!directory(parent))continue;const dir=join(parent,'skills');if(!directory(dir))continue;for(const entry of readdirSync(dir)){const name=entry.endsWith('.md')?entry.slice(0,-3):entry;if(skills.some(v=>v.name===name))continue;try{const value=readSkill(dir,name);if(value)skills.push(value);}catch{}}}
  let agentsMd;try{agentsMd=readText(p.agentsFile);hashes['agents-md']=hash(agentsMd);if(!payload){const global=readText(join(root,'AGENTS.md'));if(global?.trim()&&!global.trimLeft().startsWith('<!-- dsh-app:managed'))agentsMd=global;}}catch{errors['agents-md']='现有 AGENTS.md 不能完整读取或备份，已阻止替换';}
  return {skills,agentsMd:agentsMd?.trimLeft().startsWith('<!-- dsh-app:managed')?undefined:agentsMd,hashes,errors};
}
function safeWrite(path,text){let fd;try{fd=openSync(path,constants.O_WRONLY|constants.O_CREAT|constants.O_EXCL|constants.O_NOFOLLOW,0o600);writeFileSync(fd,text);fsyncSync(fd);}finally{if(fd!==undefined)closeSync(fd)}}
function writeSkill(folder,files){mkdirSync(folder,{mode:0o700});for(const [rel,text]of Object.entries(files)){const parts=rel.split('/');let parent=folder;for(const dir of parts.slice(0,-1)){parent=join(parent,dir);directory(parent,true);}safeWrite(join(folder,...parts),text);}}
export function backupProfile(root, confirmed) {
  if(confirmed!==true)throw new Error('需要确认导入');const p=pathsFor(root);directory(join(root,'backups'),true);const backup=join(root,'backups','share-import-'+randomUUID());mkdirSync(backup,{mode:0o700});
  const profile=join(root,'profile');if(directory(profile)){const path=join(profile,'cordis.patch.yml');let fd;try{fd=openSync(path,constants.O_RDONLY|constants.O_NOFOLLOW);const stat=fstatSync(fd);if(!stat.isFile()||stat.size>1024*1024)throw new Error('无法备份现有配置');safeWrite(join(backup,'cordis.patch.yml'),readFileSync(fd));}catch(e){if(!missing(e))throw e;}finally{if(fd!==undefined)closeSync(fd)}}
  return {backup:backup.slice(root.length+1)};
}
export function applyProfileFiles(root, body, signal) {
  if(body.confirmed!==true)throw new Error('需要确认导入');const payload=profilePayload(body.payload);if(payload.kind!=='profile')throw new Error('不是配置分享');
  if(!Array.isArray(body.selected)||body.selected.some(v=>v!=='agents-md'&&!payload.skills.some(s=>'skill:'+s.name===v)))throw new Error('文件选择无效');
  const current=readProfileFiles(root,payload),p=pathsFor(root);for(const id of body.selected){if(current.errors[id]||typeof body.expected?.[id]!=='string'||current.hashes[id]!==body.expected[id])throw new Error('文件已更改，请重新预览后导入');}
  signal?.throwIfAborted();const {backup}=backupProfile(root,true),folder=join(root,backup),done=[];
  for(const id of body.selected){signal?.throwIfAborted();
    if(id==='agents-md'){if(typeof payload.agentsMd!=='string')throw new Error('缺少 AGENTS.md');const old=readText(p.agentsFile);if(old!==undefined)safeWrite(join(folder,'AGENTS.md'),old);const staged=join(p.workspace,'.share-agents-'+randomUUID());safeWrite(staged,payload.agentsMd);renameSync(staged,p.agentsFile);done.push(id);continue;}
    const name=id.slice(6),skill=payload.skills.find(s=>s.name===name);directory(p.dsh,true);directory(p.skills,true);const old=readSkill(p.skills,name);if(old){directory(join(folder,'skills'),true);writeSkill(join(folder,'skills',name),old.files);}
    const staged=join(p.skills,'.share-'+randomUUID()),target=join(p.skills,name),flat=join(p.skills,name+'.md'),retired=join(p.skills,'.share-old-'+randomUUID());writeSkill(staged,skill.files);const prior=info(target)?target:info(flat)?flat:undefined;
    try{if(prior)renameSync(prior,retired);try{renameSync(staged,target);}catch(e){if(prior)renameSync(retired,prior);throw e;}if(prior)rmSync(retired,{recursive:true});}finally{rmSync(staged,{recursive:true,force:true});}done.push(id);
  }
  return {done,backup};
}
