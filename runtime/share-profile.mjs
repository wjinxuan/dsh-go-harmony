// Fixed dsh-Go a9877420 share_models/settings_sanitizer/profile_export/share_import contract.
import { encodeCode, decodeCode } from './share-codec.mjs';
import { redactText } from './share-redact.mjs';
const obj = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const own = (v, k) => Object.hasOwn(v ?? {}, k);
const clean = o => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined));
const text = (v, n) => typeof v === 'string' && v.trim() ? v.replace(/\s+/g, ' ').trim().slice(0, n) : undefined;
const pkg = /^(?:@[a-z0-9][a-z0-9._~-]*\/)?[a-z0-9][a-z0-9._~-]*$/;
const version = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*)?(?:\+[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*)?$/;
const github = /^github:([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)#([A-Za-z0-9_./-]+)(&path:\/[A-Za-z0-9_./@+-]+)?$/;
const git = /^git\+https:\/\/([A-Za-z0-9.-]+)\/([A-Za-z0-9_./-]+?)(?:\.git)?#([A-Za-z0-9_./-]+)(&path:\/[A-Za-z0-9_./@+-]+)?$/;
const badKey = k => ['__proto__', 'prototype', 'constructor'].includes(k);
const absolute = /^(\/|~\/|~$|[A-Za-z]:[\\/]|\\\\|file:)/;
export const shareableNamespace = ns => !badKey(ns) && /^[A-Za-z0-9._:@/-]{1,80}$/.test(ns) && !/(account|credential|telemetry|analytics|anonymous|remote-access|remotes|webserver|gateway|otel|login|auth)/i.test(ns);
export function secretField(key) {
  const words = key.replace(/([a-z0-9])([A-Z])/g, '$1 $2').split(/[\s_.-]+/).filter(Boolean).map(v => v.toLowerCase()), last = words.at(-1);
  return ['token','secret','password','passwd','passphrase','cookie','authorization','apikey'].includes(last) || last === 'key' && (words.length === 1 || ['api','private','secret','access','client','session','signing','license'].includes(words.at(-2)));
}
export function containsShareSecret(v) { return redactText(v) !== v; }
function unsafeString(v) {
  if (absolute.test(v.trim()) || containsShareSecret(v) || /^bearer\s/i.test(v) || /^[A-Za-z0-9+/_=.-]{40,}$/.test(v) && /\d/.test(v) && /[A-Za-z]/.test(v) && !v.includes('.')) return true;
  try { const url = new URL(v); return !!url.username || !!url.password || [...url.searchParams.keys()].some(k => /^(token|key|secret|sig|signature|password|access_token|auth|api_key|apikey)$/i.test(k)); } catch { return false; }
}
function schemaNode(node, schema, depth = 0) {
  if (depth > 20) return {};
  if(typeof node==='number')return schemaNode(schema?.refs?.[node],schema,depth+1);
  if(obj(node?.refs))return schemaNode(node.uid,node,depth+1);
  if (!obj(node)) return {};
  if(node.type==='intersect'){const rows=(node.list??[]).map(v=>schemaNode(v,schema,depth+1));return {type:'object',dict:Object.assign({},...rows.map(v=>v.dict??v.fields??{})),meta:Object.assign({},...rows.map(v=>v.meta??{}),node.meta??{})};}
  if (typeof node.$ref === 'string') return schemaNode(schema?.$defs?.[node.$ref.replace(/^#\/\$defs\//, '')] ?? schema?.definitions?.[node.$ref], schema, depth + 1);
  if (['transform','optional','default','nullable'].includes(node.type) && obj(node.inner)) return { ...schemaNode(node.inner, schema, depth + 1), meta: { ...node.inner.meta, ...node.meta } };
  return node;
}
const fieldNode = (node, key, schema) => schemaNode(schemaNode(node,schema)?.dict?.[key] ?? schemaNode(node,schema)?.fields?.[key] ?? (schemaNode(node,schema)?.type === 'dict' ? schemaNode(node,schema).inner : undefined), schema);
const drop = Symbol('drop');
export function sanitizeSection(view, values = view.user) {
  if (!shareableNamespace(view.ns) || !obj(values)) return {};
  function visit(value, node, path, key, depth) {
    if (depth > 32) throw new Error('配置嵌套过深');
    node = schemaNode(node, view.schema);
    const ref = node.meta?.role === 'credential-ref';
    if (badKey(key) || node.meta?.role === 'secret' || node.meta?.secret === true || view.secrets?.some(s => JSON.stringify(s.path) === JSON.stringify(path)) || !ref && secretField(key)) return drop;
    if (typeof value === 'string') return (ref ? absolute.test(value.trim()) : unsafeString(value)) ? drop : value;
    if (Array.isArray(value)) { const rows = value.map((v, i) => visit(v, node.inner, [...path, String(i)], '', depth + 1)).filter(v => v !== drop); return value.length && !rows.length ? drop : rows; }
    if (obj(value)) { const entries = Object.entries(value).map(([k, v]) => [k, visit(v, fieldNode(node, k, view.schema), [...path, k], k, depth + 1)]).filter(([, v]) => v !== drop); return Object.keys(value).length && !entries.length ? drop : Object.fromEntries(entries); }
    return value;
  }
  return Object.fromEntries(Object.entries(values).map(([key, value]) => [key, visit(value, fieldNode(view.schema, key, view.schema), [key], key, 0)]).filter(([, v]) => v !== drop));
}
export function sharedPlugin(v) {
  if (!obj(v) || typeof v.name !== 'string' || v.name.length > 214 || !pkg.test(v.name)) throw new Error('插件名称无效');
  const { name, source, spec, integrity } = v;
  if (source === 'npm') {
    if (!version.test(v.version ?? '') || spec !== name + '@' + v.version || integrity !== undefined && !/^sha(256|384|512)-[A-Za-z0-9+/]+={0,2}$/.test(integrity)) throw new Error('插件必须使用精确版本');
  } else if (source === 'github') { if (!github.test(spec ?? '') && git.exec(spec ?? '')?.[1] !== 'github.com') throw new Error('GitHub 插件来源无效'); }
  else if (source === 'git') { if (!git.test(spec ?? '')) throw new Error('Git 插件需要 HTTPS 地址和版本引用'); }
  else if (source === 'official') { if (spec !== undefined && spec !== null) throw new Error('官方插件不能指定下载来源'); }
  else throw new Error('不支持此插件来源');
  return clean({ name, source, spec: source === 'official' ? undefined : spec, version: version.test(v.version ?? '') ? v.version : undefined,
    integrity: source === 'npm' ? integrity : undefined, title: text(v.title,80), author: text(v.author,80), summary: text(v.summary,200) });
}
export const safeSkillPath = v => typeof v === 'string' && /^[A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+){0,3}$/.test(v) && !v.split('/').some(p => p.startsWith('.'));
export function sharedSkill(v) {
  if (!obj(v) || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(v.name ?? '') || !obj(v.files) || !own(v.files,'SKILL.md') || Object.keys(v.files).length > 12 || Object.entries(v.files).some(([p,t]) => !safeSkillPath(p) || typeof t !== 'string' || t.length > 65536)) throw new Error('技能文件无效或过大');
  return { name:v.name, files:v.files };
}
function list(raw, read, max) { if (raw === undefined) return []; if (!Array.isArray(raw) || raw.length > max) throw new Error('分享条目无效或过多'); const values = raw.map(read); return values; }
export function profilePayload(raw) {
  if (!obj(raw) || raw.v !== 1 || !['plugin','profile'].includes(raw.kind)) throw new Error('不兼容的配置分享格式');
  if (Buffer.byteLength(JSON.stringify(raw)) > 1024 * 1024) throw new Error('配置分享超过 1 MB');
  if (raw.kind === 'plugin') return {v:1,kind:'plugin',plugin:sharedPlugin(raw.plugin)};
  const settings = Object.create(null);
  if (raw.settings !== undefined && !obj(raw.settings)) throw new Error('配置参数必须是对象');
  for (const [ns, value] of Object.entries(raw.settings ?? {})) {
    if (!/^[A-Za-z0-9._:@/-]{1,80}$/.test(ns) || !obj(value)) throw new Error('配置命名空间无效');
    if (shareableNamespace(ns)) settings[ns] = value;
  }
  const plugins=list(raw.plugins,sharedPlugin,64), skills=list(raw.skills,sharedSkill,32);
  if (new Set(plugins.map(v=>v.name)).size !== plugins.length || new Set(skills.map(v=>v.name)).size !== skills.length) throw new Error('分享包含重复条目');
  const presets=list(raw.presets,v=>{if(!obj(v)||!/^[A-Za-z0-9._-]{1,64}$/.test(v.id??''))throw new Error('预设无效');return clean({id:v.id,name:text(v.name,60),bundle:typeof v.bundle==='string'?v.bundle:undefined})},64);
  if (raw.agentsMd !== undefined && (typeof raw.agentsMd !== 'string' || raw.agentsMd.length > 65536)) throw new Error('AGENTS.md 无效或过大');
  return clean({v:1,kind:'profile',name:text(raw.name,40),created:typeof raw.created==='string'&&Number.isFinite(Date.parse(raw.created))?new Date(raw.created).toISOString():undefined,settings,plugins,presets,skills,agentsMd:raw.agentsMd?.trim()?raw.agentsMd:undefined});
}
export function profileFile(raw) { const body=profilePayload(raw),code=encodeCode(body);if(code.length>1024*1024)throw new Error('配置分享超过 1 MB');return {body,code,file:JSON.stringify({dshgo:1,kind:body.kind,name:body.name??body.plugin?.title??body.plugin?.name??'配置',code})+'\n'}; }
export function decodeProfileFile(text) {
  if(typeof text!=='string'||Buffer.byteLength(text)>4*1024*1024)throw new Error('分享文件过大');
  let code=text.trim();if(code.startsWith('{')){const value=JSON.parse(code);if(!obj(value)||!Number.isInteger(value.dshgo)||typeof value.code!=='string')throw new Error('不是 dsh-go 文件');code=value.code;}
  return profileFile(decodeCode(code));
}
export function shareKind(text) { let code=text.trim();if(code.startsWith('{'))code=JSON.parse(code).code;return decodeCode(code).kind; }
function installedPlugin(b) {
  if(b.official===true)return b.installed||b.optional&&b.enabled?sharedPlugin({name:b.name,source:'official',title:b.title}):undefined;
  if(!b.installed)return undefined;
  const s=typeof b.source==='string'?b.source:'';
  const source=github.test(s)?'github':git.test(s)?(git.exec(s)[1]==='github.com'?'github':'git'):undefined;
  if(source)return sharedPlugin({name:b.name,source,spec:s,version:b.version,title:typeof b.title==='string'?b.title:undefined});
  const registry=s.replace(/^npm:/,'');
  if(version.test(b.version??'')&&(registry===b.name||registry.startsWith(b.name+'@')&&/^[\w.^~<>=|* -]+$/.test(registry.slice(b.name.length+1))))return sharedPlugin({name:b.name,source:'npm',spec:b.name+'@'+b.version,version:b.version,title:typeof b.title==='string'?b.title:undefined});
}
export function profileSource(snapshot, files={}) {
  const settings=Object.create(null),plugins=[],presets=[],skills=[],items=[];
  for(const view of snapshot.settings?.namespaces??[]){const values=sanitizeSection(view);if(Object.keys(values).length){settings[view.ns]=values;items.push({id:'settings:'+view.ns,title:view.ns,section:'settings',bytes:Buffer.byteLength(JSON.stringify(values)),defaultOn:true})}}
  for(const b of snapshot.bundles??[]){let p;try{p=installedPlugin(b)}catch{};if(!p){if(b.installed&&!b.official)items.push({id:'plugin:'+b.name,title:b.name,section:'plugins',blocked:'本地路径或未固定版本的插件不能分享'});continue;}
    plugins.push(p);items.push({id:'plugin:'+p.name,title:p.title??p.name,section:'plugins',detail:p.spec??'官方插件',bytes:Buffer.byteLength(JSON.stringify(p)),defaultOn:true});
    for(const row of b.rows??[])if(row.moduleName==='@deepseek-ai/dsh-agent-preset'&&row.rowId?.startsWith('preset-')){const id=row.rowId.slice(7);presets.push({id,name:snapshot.presets?.find(p=>p.id===id)?.name,bundle:b.name})}
  }
  for(const skill of files.skills??[]){const p=sharedSkill(skill),blocked=Object.values(p.files).some(containsShareSecret)?'文件包含疑似凭据，不能分享':undefined;if(!blocked)skills.push(p);items.push(clean({id:'skill:'+p.name,title:p.name,section:'skills',bytes:Buffer.byteLength(JSON.stringify(p)),defaultOn:true,blocked}));}
  const agentsMd=files.agentsMd&&!containsShareSecret(files.agentsMd)?files.agentsMd:undefined;
  if(files.agentsMd)items.push(clean({id:'agents-md',title:'AGENTS.md',section:'agentsMd',bytes:Buffer.byteLength(files.agentsMd),defaultOn:false,blocked:agentsMd?undefined:'文件包含疑似凭据，不能分享'}));
  return {items,body:profilePayload({v:1,kind:'profile',settings,plugins,presets,skills,agentsMd})};
}
export function selectProfile(source, selected, name, pluginOnly=false) {
  const allowed=new Set(source.items.filter(v=>!v.blocked).map(v=>v.id));if(!Array.isArray(selected)||selected.some(id=>!allowed.has(id)))throw new Error('分享选择已失效，请刷新');
  const body=source.body,plugins=body.plugins.filter(v=>selected.includes('plugin:'+v.name));
  if(pluginOnly){if(plugins.length!==1||selected.length!==1)throw new Error('请选择一个插件');return profileFile({v:1,kind:'plugin',plugin:plugins[0]})}
  return profileFile(shareSafeProfile({v:1,kind:'profile',name,created:new Date().toISOString(),settings:Object.fromEntries(Object.entries(body.settings).filter(([ns])=>selected.includes('settings:'+ns))),plugins,presets:body.presets.filter(v=>plugins.some(p=>p.name===v.bundle)),skills:body.skills.filter(v=>selected.includes('skill:'+v.name)),agentsMd:selected.includes('agents-md')?body.agentsMd:undefined}));
}
const endpoint=/url|uri|endpoint|host|proxy|registry/i;
function importValues(ns,values,view={}) {
  function visit(value,node,path,key){node=schemaNode(node,view.schema);if(badKey(key)||node.meta?.role==='secret'||node.meta?.secret===true||node.meta?.role!=='credential-ref'&&secretField(key)||view.secrets?.some(s=>JSON.stringify(s.path)===JSON.stringify(path)))return drop;
    if(Array.isArray(value)){const rows=value.map((v,i)=>visit(v,node.inner,[...path,String(i)],''));return rows.includes(drop)||JSON.stringify(rows)!==JSON.stringify(value)?drop:rows;}
    if(obj(value))return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,visit(v,fieldNode(node,k,view.schema),[...path,k],k)]).filter(([,v])=>v!==drop));return value;}
  return visit(values,view.schema,[],'');
}
function settingDiff(ns,values,view){
  const cleanValues=importValues(ns,values,view),out=[];
  const visit=(to,from,path,node,sensitive)=>{node=schemaNode(node,view?.schema);sensitive=sensitive||endpoint.test(path.at(-1))||node.meta?.role==='credential-ref';
    if(obj(to)){for(const [k,v]of Object.entries(to))visit(v,obj(from)?from[k]:undefined,[...path,k],fieldNode(node,k,view?.schema),sensitive)}
    else if(JSON.stringify(to)!==JSON.stringify(from))out.push({path,from:from??null,to,sensitive:sensitive||Array.isArray(to)&&JSON.stringify(to).match(/"[^\"]*(?:url|uri|endpoint|host|proxy|registry)"\s*:/i)!==null})};
  for(const[k,v]of Object.entries(cleanValues))visit(v,view?.value?.[k],[k],fieldNode(view?.schema,k,view?.schema),ns.startsWith('llm-')||['permission','bash-sandbox','pwsh-sandbox'].includes(ns));return out;
}
export function planProfile(raw,snapshot,localFiles={}) {
  const payload=profilePayload(raw),changes=[],bundles=snapshot.bundles??[],plugins=payload.kind==='plugin'?[payload.plugin]:payload.plugins;
  for(const p of plugins){const have=bundles.find(b=>b.name===p.name),official=p.source==='official',same=official?have?.enabled:have?.installed&&have.version===p.version&&p.version;
    const kind=same?'unchanged':official?'enable':have?.installed?'upgrade':'install';const target=official?have?.installTarget?.spec:p.spec;
    const got=snapshot.facts?.[p.name]?.integrity,integrity=p.integrity&&got?(p.integrity===got?'verified':'mismatch'):'unverifiable';
    const blocked=kind==='unchanged'?undefined:official&&!have?'当前主机没有此官方插件':snapshot.canInstall!==true?'当前主机不支持插件安装或启用':integrity==='mismatch'?'插件完整性校验不匹配':undefined;
    changes.push(clean({id:'plugin:'+p.name,section:'plugins',title:p.title??p.name,kind,plugin:p,fromVersion:have?.version,fromSource:have?.source,installSpec:target,integrity,detail:target??'官方插件',blocked,defaultOn:!blocked&&kind!=='unchanged'}));
  }
  if(payload.kind==='profile'){
    const later=changes.some(c=>c.section==='plugins'&&!c.blocked&&c.kind!=='unchanged');
    for(const p of payload.presets){const owner=changes.find(c=>c.id==='plugin:'+p.bundle);if(owner&&!owner.blocked&&owner.kind!=='unchanged'&&!snapshot.presets?.some(v=>v.id===p.id))changes.push({id:'preset:'+p.id,section:'presets',title:p.name??p.id,kind:'add',follows:owner.id})}
    for(const[ns,values]of Object.entries(payload.settings)){const view=snapshot.settings?.namespaces?.find(v=>v.ns===ns),diff=settingDiff(ns,values,view);if(!diff.length)continue;
      const sensitive=diff.some(d=>d.sensitive),blocked=!snapshot.settings?'无法读取主机设置':!view&&!later?'当前主机没有此配置项':snapshot.settings.writable===false||view?.writable===false?'主机设置为只读':undefined;
      changes.push(clean({id:'settings:'+ns,section:'settings',title:ns,kind:diff.every(d=>d.from===null)?'add':'change',diff,ops:diff.map(d=>({op:'set',path:d.path,value:d.to})),revision:view?.revision,blocked,sensitive,defaultOn:!sensitive&&!blocked}));
    }
    for(const skill of payload.skills){const current=localFiles.skills?.find(v=>v.name===skill.name),error=localFiles.errors?.['skill:'+skill.name];if(current&&JSON.stringify(current.files)===JSON.stringify(skill.files))continue;
      changes.push(clean({id:'skill:'+skill.name,section:'skills',title:skill.name,kind:current?'change':'add',skill,defaultOn:false,blocked:snapshot.local?error:'技能和提示文件只能导入本机引擎',expected:localFiles.hashes?.['skill:'+skill.name]}));}
    if(payload.agentsMd&&payload.agentsMd.trim()!==localFiles.agentsMd?.trim())changes.push(clean({id:'agents-md',section:'agentsMd',title:'AGENTS.md',kind:localFiles.agentsMd?'change':'add',text:payload.agentsMd,defaultOn:false,blocked:snapshot.local?localFiles.errors?.['agents-md']:'技能和提示文件只能导入本机引擎',expected:localFiles.hashes?.['agents-md']}));
  }
  return {payload,changes};
}

export function shareSafeProfile(raw) {
  const body=profilePayload(raw);if(body.kind==='plugin')return body;
  const settings=Object.create(null);for(const [ns,user]of Object.entries(body.settings)){const values=sanitizeSection({ns,user});if(Object.keys(values).length)settings[ns]=values;}
  if(body.skills.some(s=>Object.values(s.files).some(containsShareSecret))||body.agentsMd&&containsShareSecret(body.agentsMd))throw new Error('文件包含疑似凭据，不能分享');
  return {...body,settings};
}
