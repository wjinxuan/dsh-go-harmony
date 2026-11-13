import { DshModelInfo, DshModelSelection, DshProviderGroup, DshSessionProjections, modelSelection, object } from '../dsh/DshWire'

export function filterModelGroups(groups: DshProviderGroup[], query: string): DshProviderGroup[] {
  const words = query.trim().toLowerCase().split(/\s+/).filter((word: string) => !!word)
  return groups.map((group: DshProviderGroup): DshProviderGroup => {
    const models = group.models.filter((model: DshModelInfo) => {
      const terms = `${group.name} ${group.id} ${model.name} ${model.id}`.toLowerCase()
      return words.every((word: string) => terms.includes(word))
    })
    return { id: group.id, name: group.name, models: models }
  }).filter((group: DshProviderGroup) => group.models.length > 0)
}

export function projectedModelSelection(projections: DshSessionProjections | null | undefined): DshModelSelection | undefined {
  const values = object(projections?.values['modelSelection'])
  return modelSelection(values['next']) ?? modelSelection(values['lastUsed'])
}

export function catalogModel(groups: DshProviderGroup[], provider: string, id: string): DshModelInfo | undefined {
  return groups.find((group: DshProviderGroup) => group.id === provider)?.models
    .find((model: DshModelInfo) => model.id === id)
}

export function modelDisplayName(groups: DshProviderGroup[], selection: DshModelSelection): string {
  return catalogModel(groups, selection.provider, selection.model)?.name || selection.model
}

export function defaultModelEffort(model: DshModelInfo): string {
  const efforts = model.efforts.map(item => item.id)
  if (model.defaultEffort && efforts.includes(model.defaultEffort)) return model.defaultEffort
  if (efforts.includes('medium')) return 'medium'
  return efforts.find((id: string) => id !== 'none' && id !== 'off') || efforts[0] || ''
}
