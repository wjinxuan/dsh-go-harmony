import { array, object, string, WireObject } from '../dsh/DshWire'
export interface DSBotView { supported: boolean; lines: string[]; choices: WireObject[]; control: WireObject }
function scalar(value: Object | null | undefined): boolean { return typeof value === 'string' || typeof value === 'boolean' || typeof value === 'number' && Number.isFinite(value) }
function optionalText(value: Object | null | undefined): boolean { return value === undefined || value === null || typeof value === 'string' }
function formula(value: Object | null | undefined, depth: number = 0): boolean {
  if (depth > 16) return true
  if (Array.isArray(value)) return value.some((item: Object) => formula(item,depth+1))
  if (value && typeof value === 'object') { const node = object(value); if (Object.keys(node).includes('=') || node['let'] && (typeof node['let'] !== 'object' || Array.isArray(node['let']) || Object.keys(object(node['let'])).length)) return true; return Object.keys(node).some((key: string) => formula(node[key],depth+1)) }
  return false
}
export function dsBotChoiceValue(option: WireObject): Object { return option['value'] ?? option['label'] ?? '' }
function valid(node: WireObject, depth: number): boolean {
  if (depth > 6) return false
  const type = string(node['type']), id = !!string(node['id'])
  if (type === 'text') return typeof node['text'] === 'string'
  if (type === 'metric') return typeof node['label'] === 'string' && scalar(node['value']) && !node['caption']
  if (type === 'progress') return typeof node['percent'] === 'number' && Number.isFinite(node['percent'] as number) && optionalText(node['label']) && node['value'] === undefined && node['max'] === undefined && node['valueLabel'] === undefined
  if (type === 'submit') return id && optionalText(node['label'])
  if (type === 'confirm') return id && optionalText(node['confirmLabel']) && optionalText(node['cancelLabel'])
  if (type === 'options') return id && Array.isArray(node['options']) && array(node['options']).length > 0 && array(node['options']).every((value: Object) => typeof object(value)['label'] === 'string' && optionalText(object(value)['description']))
  if (type === 'form') return id && optionalText(node['submitLabel']) && Array.isArray(node['fields']) && array(node['fields']).every((value: Object) => typeof object(value)['id'] === 'string' && typeof object(value)['label'] === 'string' && optionalText(object(value)['placeholder']))
  if (type === 'choice') {
    const options = array(node['options']).map(object), values: Object[] = [], labels: string[] = []
    if (!id || typeof node['label'] !== 'string' || !options.length) return false
    for (const option of options) { const value = dsBotChoiceValue(option), label = string(option['label']); if (!label.trim() || !scalar(value) || values.includes(value) || labels.includes(label)) return false; values.push(value); labels.push(label) }
    return values.includes(node['value'] ?? values[0])
  }
  return ['stack','row'].includes(type) && Array.isArray(node['children']) && array(node['children']).every((child: Object) => valid(object(child),depth+1))
}
export function dsBotView(value: WireObject): DSBotView {
  const result: DSBotView = { supported: !formula(value) && valid(value,0), lines: [], choices: [], control: {} }
  if (!result.supported) return result
  const walk = (node: WireObject): void => {
    const type = string(node['type'])
    if (type === 'text' && string(node['text']).trim()) result.lines.push(string(node['text']).trim())
    if (type === 'metric') result.lines.push(string(node['label']) + ': ' + String(node['value']))
    if (type === 'progress') result.lines.push((string(node['label']) ? string(node['label']) + ' ' : '') + String(node['percent']) + '%')
    if (type === 'choice') result.choices.push(node)
    if (['options','confirm','form','submit'].includes(type) && !result.control['id']) result.control = node
    for (const child of array(node['children'])) walk(object(child))
  }; walk(value); return result
}
export function dsBotViewAnswer(view: DSBotView, inputs: WireObject, selected: string[], fields: WireObject, confirmed?: boolean): WireObject {
  if (!view.supported || !view.control['id']) throw new Error('此卡片需要在网页中打开')
  const result: WireObject = {}, values: WireObject = {}
  for (const choice of view.choices) { const id = string(choice['id']), options = array(choice['options']).map(object), value = inputs[id] ?? choice['value'] ?? dsBotChoiceValue(options[0]); if (!options.some((option: WireObject) => dsBotChoiceValue(option) === value)) throw new Error('卡片选项已更改'); values[id] = value }
  if (view.choices.length) result['inputs'] = values
  const type = view.control['type']
  if (type === 'options') { const labels = array(view.control['options']).map((item: Object) => string(object(item)['label'])); if (!selected.length || selected.some((label: string) => !labels.includes(label)) || view.control['multi'] !== true && selected.length > 1) throw new Error('请选择有效选项'); result['selected'] = selected }
  if (type === 'confirm') { if (typeof confirmed !== 'boolean') throw new Error('请确认选项'); result['confirmed'] = confirmed }
  if (type === 'form') { const next: WireObject = {}; for (const field of array(view.control['fields']).map(object)) next[string(field['id'])] = string(fields[string(field['id'])]); result['fields'] = next }
  return result
}
