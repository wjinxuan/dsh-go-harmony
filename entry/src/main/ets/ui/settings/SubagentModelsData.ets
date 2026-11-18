import { array, object, string, DshSettingsOp, DshProviderGroup, WireObject } from '../../dsh/DshWire'
export interface SubagentRoute { provider: string; model: string }
export interface SubagentModel extends SubagentRoute { title: string; providerTitle: string; available: boolean }
export function subagentRoutes(value: Object | null | undefined): SubagentRoute[] {
  const routes: SubagentRoute[] = []
  for (const raw of array(value)) { const item = object(raw), provider = string(item['provider']), model = string(item['model'])
    if (provider && model && !routes.some((r: SubagentRoute) => r.provider === provider && r.model === model)) routes.push({ provider: provider, model: model }) }
  return routes
}
export function subagentCandidates(groups: DshProviderGroup[], saved: SubagentRoute[]): SubagentModel[] {
  const models: SubagentModel[] = []
  for (const group of groups) for (const model of group.models) models.push({ provider: group.id, model: model.id, title: model.name || model.id, providerTitle: group.name, available: true })
  for (const route of saved) if (!models.some((model: SubagentModel) => model.provider === route.provider && model.model === route.model)) models.push({ provider: route.provider, model: route.model, title: route.model, providerTitle: route.provider, available: false })
  return models
}
export function pickSubagentModel(value: WireObject, pending: boolean, route: SubagentRoute): DshSettingsOp[] {
  const allowed = subagentRoutes(value['allowedModels']), selected = allowed.some((r: SubagentRoute) => r.provider === route.provider && r.model === route.model)
  if (selected && value['enabled'] === true && allowed.length === 1) throw new Error('启用自选模型时至少保留一个模型。')
  const next = selected ? allowed.filter((r: SubagentRoute) => r.provider !== route.provider || r.model !== route.model) : allowed.concat([route])
  const ops: DshSettingsOp[] = [{ op: 'set', path: ['allowedModels'], value: next }]
  if (pending && value['enabled'] !== true && next.length) ops.unshift({ op: 'set', path: ['enabled'], value: true })
  return ops
}
