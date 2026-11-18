import { array, number, object, string, WireObject } from '../dsh/DshWire'
export const PLUGIN_INPUTS: string[] = ['textField','number','stepper','toggle','slider','select','segmented','chips','date','time','rating']
export const PLUGIN_CONTAINERS: string[] = ['form','tabs','collapsible','accordion','carousel','timeline','grid']
export const PLUGIN_DISPLAYS: string[] = ['badge','tag','avatar','codeBlock','divider','spacer','emptyState','gallery']
export function pluginInputPath(bind: string): string[] | undefined {
  if (bind.length > 256 || !/^data(?:\.[A-Za-z_][A-Za-z0-9_-]{0,63}){1,16}$/.test(bind)) return undefined
  const keys = bind.slice(5).split('.')
  return keys.some((key: string) => ['__proto__','constructor','prototype'].includes(key)) ? undefined : keys
}
export function pluginInputData(data: WireObject, bind: string, value: Object | null): WireObject {
  const path = pluginInputPath(bind); if (!path) throw new Error('输入字段绑定无效')
  const result: WireObject = JSON.parse(JSON.stringify(data)) as WireObject
  let cursor = result
  for (let i=0;i<path.length-1;i++) { const next: WireObject = object(cursor[path[i]]); cursor[path[i]] = next; cursor = next }
  cursor[path[path.length-1]] = value; return result
}
export function pluginInputIssue(raw: WireObject, value: Object | null | undefined): string {
  const type = string(raw['type']); const text = typeof value === 'string' ? value : ''
  if (raw['password'] === true || raw['obscureText'] === true || raw['inputType'] === 'password' || raw['keyboardType'] === 'password') return '插件不能索取密码'
  if (raw['required'] === true && (value === null || value === undefined || text.trim() === '' && typeof value === 'string' || Array.isArray(value) && !array(value).length)) return '此项为必填项'
  const empty = value === null || value === undefined || typeof value === 'string' && !value.trim() || Array.isArray(value) && !array(value).length
  if (empty) return ''
  if (type === 'textField' && typeof value !== 'string' || type === 'toggle' && typeof value !== 'boolean' || type === 'chips' && raw['multi'] === true && !Array.isArray(value)) return '输入格式不正确'
  if (['number','stepper','slider','rating'].includes(type)) {
    const min = number(raw['min'], type==='number'||type==='stepper' ? -1e9:0)
    const max = number(raw['max'],type==='rating'?5:type==='number'||type==='stepper'?1e9:100)
    const values = type==='slider'&&raw['range']===true ? array(value) : [value ?? null]
    if (type === 'slider' && raw['range'] === true && values.length !== 2) return '范围需要两个数值'
    if (values.some((item: Object|null) => !['string','number'].includes(typeof item)||!Number.isFinite(Number(item))||Number(item)<min||Number(item)>max||type==='rating'&&!Number.isInteger(Number(item)))) return '数值超出允许范围'
    if (values.length===2 && Number(values[0])>Number(values[1])) return '范围起点不能大于终点'
  }
  if (type==='textField') {
    if (text.length< number(raw['minLength'],0)||text.length>Math.min(2000,number(raw['maxLength'],256))) return '文本长度超出允许范围'
    const pattern=string(raw['pattern']); let valid=true
    if (pattern==='email') valid=/^[^\s@]+@[^\s@.]+(?:\.[^\s@.]+)+$/.test(text)
    else if (pattern==='integer') valid=/^[+-]?[0-9]+$/.test(text)
    else if (pattern==='decimal') valid=/^[+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)$/.test(text)
    else if (pattern==='alphanumeric') valid=/^[A-Za-z0-9]+$/.test(text)
    else if (pattern==='slug') valid=/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(text)
    else if (pattern) valid=false
    if (!valid) return '输入格式不正确'
  }
  if (type==='date'&&text) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(text)||!Number.isFinite(Date.parse(text))||new Date(text).toISOString().slice(0,10)!==text) return '请输入有效日期'
    if (string(raw['minDate'])&&text<string(raw['minDate'])||string(raw['maxDate'])&&text>string(raw['maxDate'])) return '日期超出允许范围'
  }
  if (type==='time'&&text&&!/^([01]\d|2[0-3]):[0-5]\d$/.test(text)) return '请输入有效时间'
  if (['select','segmented','chips'].includes(type)) {
    const choices=array(raw['options']).map((option:Object)=>typeof option==='string'?option:string(object(option)['value'])||string(object(option)['label']))
    const values=Array.isArray(value)?array(value):[value??'']
    if (values.some((item:Object)=>!!item&&!choices.includes(string(item)))) return '选择的项目已不可用'
  }
  return ''
}

export function pluginInputSubmitted(raw: WireObject, value: Object | null): Object | null {
  return ['number','stepper','slider','rating'].includes(string(raw['type'])) && typeof value === 'string' ? value.trim() ? Number(value) : null : value
}
