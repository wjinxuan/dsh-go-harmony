import { array, number, object, string } from '../../dsh/DshWire'
import type { DshSettingsOp, WireObject } from '../../dsh/DshWire'

export const CONTEXT_PRESETS: number[] = [32768, 65536, 131072, 200000, 262144, 1000000]
export const OUTPUT_PRESETS: number[] = [8192, 16384, 32768, 65536, 131072]
export const THINKING_LEVELS: string[] = ['off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max']
export interface ProviderModelDraft {
  id: string; name: string; context: string; output: string; images: boolean; levels: string[]
}
export function parseModelTokens(raw: string): number | undefined {
  const match = /^(\d+(?:\.\d+)?)([kKmM])?$/.exec(raw.replace(/[\s,_]/g, ''))
  if (!match) return undefined
  const value = Number(match[1]) * (match[2]?.toLowerCase() === 'k' ? 1000 : match[2]?.toLowerCase() === 'm' ? 1000000 : 1)
  return Number.isSafeInteger(Math.round(value)) && value > 0 && Math.abs(value - Math.round(value)) <= 1e-6 ? Math.round(value) : undefined
}
export function modelTokenText(value: number): string {
  if (value >= 1000000 && value % 1000000 === 0) return `${value / 1000000}M`
  if (value >= 1048576 && value % 1048576 === 0) return `${value / 1048576}M`
  if (value >= 1024 && value % 1024 === 0) return `${value / 1024}K`
  if (value >= 1000 && value % 1000 === 0) return `${value / 1000}K`
  return String(value)
}
export function providerModelDraft(value: WireObject, defaultImages: boolean = false): ProviderModelDraft {
  const input = array(value['input']), context = number(value['contextWindow'], 0), output = number(value['maxTokens'], 0)
  return { id: string(value['id']), name: string(value['name']), context: context > 0 ? String(context) : '',
    output: output > 0 ? String(output) : '', images: input.length ? input.includes('image') : defaultImages,
    levels: THINKING_LEVELS.filter((level: string) => Object.keys(object(value['reasoningEfforts'])).includes(level)) }
}
function without(value: WireObject, fields: string[]): WireObject {
  const result: WireObject = {}
  Object.keys(value).filter((key: string) => !fields.includes(key)).forEach((key: string) => { result[key] = value[key] })
  return result
}
export function providerModelValue(before: WireObject, draft: ProviderModelDraft, defaultImages: boolean = false): WireObject {
  const id = draft.id.trim(), context = parseModelTokens(draft.context), output = parseModelTokens(draft.output)
  if (!id || /\s/.test(id)) throw new Error('填写不含空格的模型 ID。')
  if ((draft.context.trim() && !context) || (draft.output.trim() && !output)) throw new Error('Token 数须为正整数，可使用 K 或 M。')
  const result = without(before, ['id', 'name', 'contextWindow', 'maxTokens'])
  result['id'] = id
  if (draft.name.trim()) result['name'] = draft.name.trim()
  if (context) result['contextWindow'] = context
  if (output) result['maxTokens'] = output
  const original = providerModelDraft(before, defaultImages)
  if (draft.images !== original.images) result['input'] = draft.images ? ['text', 'image'] : ['text']
  const levels = THINKING_LEVELS.filter((level: string) => draft.levels.includes(level))
  if (levels.join(',') !== original.levels.join(',') || typeof before['reasoningEfforts'] === 'object') {
    const next = object(before['reasoningEfforts']), efforts: WireObject = {}
    for (const level of levels) efforts[level] = next[level] !== undefined && (next[level] !== null || level === 'off') ? next[level] : level === 'off' ? null : level
    if (levels.length) result['reasoningEfforts'] = levels.some((level: string) => level !== 'off') ? efforts : false
    else if (typeof before['reasoningEfforts'] === 'object') result['reasoningEfforts'] = false
    else if (before['reasoningEfforts'] !== false) return without(result, ['reasoningEfforts'])
  }
  return result
}
export function subscriptionContextOps(route: string, modelId: string, overrides: WireObject, raw: string): DshSettingsOp[] {
  if (!['openai-codex', 'anthropic'].includes(route) || !modelId) throw new Error('订阅模型无效。')
  const context = parseModelTokens(raw)
  if (raw.trim() && !context) throw new Error('Token 数须为正整数，可使用 K 或 M。')
  const next = without(object(overrides[modelId]), ['contextWindow'])
  if (context) next['contextWindow'] = context
  const path = ['providers', route, 'modelOverrides']
  if (Object.keys(next).length) return [{ op: 'set', path: path.concat(modelId), value: next }]
  return [{ op: 'unset', path: Object.keys(overrides).length <= 1 ? path : path.concat(modelId) }]
}
