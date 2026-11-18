import { array, number, object, string, WireObject } from '../dsh/DshWire'
// A conservative port of the model-only JSON repair and genui vocabulary.
// No string is evaluated as JavaScript; genui interactions stay read-only.
export function relaxedModelJson(text: string): Object | null {
  try { return JSON.parse(text) as Object } catch {}
  let out = ''; let quoted = false; let comma = ''; let spaces = ''
  for (let i = 0; i < text.length; i++) {
    const char = text[i]
    if (quoted) { out += char; if (char === '\\' && i + 1 < text.length) out += text[++i]; else if (char === '"') quoted = false; continue }
    if (char === '/' && text[i + 1] === '/') { while (i < text.length && text[i] !== '\n') i++; i--; continue }
    if (char === '/' && text[i + 1] === '*') { const end = text.indexOf('*/', i + 2); i = end < 0 ? text.length : end + 1; continue }
    if (char === ',') { out += comma + spaces; comma = ','; spaces = ''; continue }
    if (comma && /\s/.test(char)) { spaces += char; continue }
    if (char === '}' || char === ']') comma = ''
    out += comma + spaces + char; comma = ''; spaces = ''; if (char === '"') quoted = true
  }
  return JSON.parse(out + comma + spaces) as Object
}
export function normalizeModelUi(value: Object | null | undefined, depth: number = 0): Object | null | undefined {
  if (depth > 32) return null
  if (Array.isArray(value)) return array(value).map((item: Object) => normalizeModelUi(item, depth + 1) ?? null)
  if (!value || typeof value !== 'object') return value
  const raw = object(value)
  if (Object.keys(raw).length === 1 && Array.isArray(raw['item'])) return normalizeModelUi(raw['item'], depth + 1)
  const result: WireObject = {}
  for (const key of Object.keys(raw)) if (!['__proto__', 'prototype', 'constructor'].includes(key)) result[key] = normalizeModelUi(raw[key], depth + 1)
  for (const key of ['value','percent','min','max','step','height']) if (typeof result[key] === 'string' && string(result[key]).trim() && Number.isFinite(Number(result[key]))) result[key] = Number(result[key])
  if (Array.isArray(result['values'])) result['values'] = array(result['values']).map((item: Object) => typeof item === 'string' && item.trim() && Number.isFinite(Number(item)) ? Number(item) : item)
  return result
}
const GENUI: string[] = ['col','grid','card','carousel','divider','spacer','arrow','hero','stat','badge','progress','list','table','keyvalue','avatar','image','image-group','audio','video','timeline','file-tree','breadcrumb','diff','json','code','icon','blocks','plot','echart','button','input','select','checkbox','radio','switch','slider','textarea','tabs','accordion','copy','link','submit','svg','mermaid','diagram','scene3d','quiz','map']
export function isGenui(value: Object | null | undefined): boolean {
  if (Array.isArray(value)) return array(value).some((row: Object) => GENUI.includes(string(object(row)['type'])))
  const raw = object(value); const type = string(raw['type'])
  return !type && Array.isArray(raw['items']) || GENUI.includes(type) || ['text','callout'].includes(type) && typeof raw['content'] === 'string' && raw['text'] === undefined || type === 'row' && Array.isArray(raw['items']) && raw['children'] === undefined || type === 'steps' && Array.isArray(raw['steps']) && raw['items'] === undefined || type === 'chart' && Array.isArray(raw['data']) && raw['categories'] === undefined
}
function inlineText(value: Object | null | undefined): string { return typeof value === 'string' ? value.replace(/\[([^\]\n]+)\]\([^)\s]+\)/g, '$1').replace(/==([^=\n]+)==/g,'$1') : typeof value === 'number' ? String(value) : value === true ? '✓' : '' }
function plainText(text: string): WireObject { const value: WireObject = { 'type': 'text', 'text': text }; return value }
function webOnly(kind: string): WireObject { const value: WireObject = { 'type': 'tag', 'text': kind + ' · 在网页版查看', 'tone': 'muted' }; return value }
export function genuiView(value: Object | null | undefined): WireObject {
  let count = 0
  const list = (raw: Object | null | undefined, depth: number): WireObject[] => array(raw).slice(0,32).map((item: Object) => node(item,depth)).filter((item: WireObject) => !!Object.keys(item).length)
  const node = (raw: Object | null | undefined, depth: number): WireObject => {
    if (++count > 120 || depth > 8) return webOnly('更多内容')
    if (typeof raw === 'string') return plainText(inlineText(raw))
    const row = object(raw); const type = string(row['type']); const out: WireObject = {}
    if (['button','input','select','checkbox','radio','switch','slider','textarea','submit','quiz'].includes(type)) return webOnly('可交互内容')
    if (['arrow','icon'].includes(type)) return out
    if (['row','col','grid','card','carousel'].includes(type)) {
      const children = list(row['items'],depth+1)
      if (type === 'card') { if (row['title']) children.unshift(plainText(inlineText(row['title']))); if (row['eyebrow']) children.unshift(plainText(inlineText(row['eyebrow']))) }
      out['type'] = type === 'col' || type === 'card' ? 'stack' : type; out['columns'] = number(row['cols'],2)
      if (type === 'carousel') out['items'] = children.slice(0,8).map((child: WireObject,index:number):WireObject => { const section:WireObject={'label':String(index+1),'children':[child]};return section })
      else out['children'] = children
    } else if (type === 'text' || type === 'callout') { out['type']=type;out['text']=inlineText(row['content']??row['text']);out['tone']=row['tone'] }
    else if (type === 'hero' || type === 'stat') { out['type']=row['value']===undefined?'text':'metric';out['text']=inlineText(row['title']);out['label']=inlineText(row['label']??row['title']);out['value']=inlineText(row['value']);out['caption']=inlineText(row['delta']??row['subtitle']);out['tone']=inlineText(row['delta']).startsWith('-')?'bad':inlineText(row['delta']).startsWith('+')?'good':row['tone'] }
    else if (type === 'badge' || type === 'avatar') { out['type']=type==='badge'?'badge':'tag';out['text']=inlineText(row['label']??row['name']);out['tone']=row['tone'] }
    else if (['code','copy','json','diff'].includes(type)) { out['type']='codeBlock';out['language']=type==='json'?'json':type==='diff'?'diff':row['lang'];out['code']=type==='json'?JSON.stringify(row['value'],null,2):type==='diff'?inlineText(row['before']).split('\n').map((line:string)=>'- '+line).concat(inlineText(row['after']).split('\n').map((line:string)=>'+ '+line)).join('\n'):row['code']??row['text'] }
    else if (type==='progress') {out['type']='progress';out['label']=row['label'];out['value']=row['value']??row['percent'];out['max']=row['max']??100;out['caption']=row['caption']}
    else if (type==='list'||type==='steps') {out['type']=type;out['items']=array(row[type==='steps'?'steps':'items']).map((item:Object):WireObject=>{const source=object(item);const line:WireObject={'title':typeof item==='string'?inlineText(item):inlineText(source['title']??source['label']),'subtitle':source['description']??source['subtitle'],'status':source['status']};return line})}
    else if (type==='keyvalue') {out['type']='keyValue';out['items']=row['items']}
    else if (type==='table') {out['type']='table';out['columns']=row['columns']??row['headers'];out['rows']=array(row['rows']).map((item:Object)=>array(item).map((cell:Object)=>inlineText(cell)))}
    else if (type==='tabs'||type==='accordion'||type==='timeline') {out['type']=type;out['items']=array(row[type==='tabs'?'tabs':'items']).map((item:Object):WireObject=>{const section=object(item);const result:WireObject={'label':inlineText(section['label']??section['title']),'children':list(section['items']??section['children'],depth+1)};return result})}
    else if (type==='chart') {out['type']='chart';out['kind']=row['kind']??row['chartType']??'bar';const data=array(row['data']).map(object);out['categories']=data.map((item:WireObject)=>inlineText(item['label']??item['name']));out['values']=data.map((item:WireObject)=>number(item['value'],0))}
    else if (type==='link') return plainText(inlineText(row['label']??row['href']))
    else if (type==='breadcrumb') return plainText(array(row['items']).map((item:Object)=>inlineText(item)).join(' › '))
    else if (type==='divider'||type==='spacer') {out['type']=type;out['size']='M'}
    else if (type==='image') {if (!string(row['src']).startsWith('data:image/')) return webOnly('图片');out['type']='image';out['src']=row['src'];out['alt']=row['alt']}
    else return webOnly(['audio','video','map','scene3d','file-tree'].includes(type)?type:['plot','echart'].includes(type)?'图表':['diagram','mermaid','svg','blocks'].includes(type)?'图示':'内容')
    return out
  }
  const raw=object(value);const result:WireObject={'v':2,'type':'stack','title':raw['type']?undefined:raw['title'],'children':list(Array.isArray(value)?value:raw['type']?[value]:raw['items'],1)};return result
}
