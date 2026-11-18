import type { DshCommand, WireObject } from '../dsh/DshWire'
import { string } from '../dsh/DshWire'

export interface SlashCommand extends DshCommand {
  kind: 'app' | 'host' | 'skill';
}

export interface SlashInput {
  token: string;
  rest?: string;
}

const appCommands: SlashCommand[] = [
  { name: 'new', label: '新对话', description: '开始一个新对话', kind: 'app' },
  { name: 'model', label: '模型', description: '切换模型与思考深度', kind: 'app' },
  { name: 'export', label: '导出日志', description: '将这个对话的完整记录打包为 ZIP', kind: 'app' },
  { name: 'features', label: '全部功能', description: '打开全部功能', kind: 'app' }
]
const order: string[] = ['new', 'model', 'compact', 'permission', 'plan', 'goal', 'feedback', 'export', 'features']

export function slashCommands(host: DshCommand[], skills: WireObject[]): SlashCommand[] {
  const commands = appCommands.slice()
  const names = new Set(appCommands.map((item: SlashCommand) => item.name))
  for (const item of host) {
    if (names.has(item.name)) continue
    names.add(item.name)
    commands.push({ name: item.name, label: item.label, description: item.description, hint: item.hint,
      definitionId: item.definitionId, kind: 'host' })
  }
  for (const skill of skills) {
    const name = string(skill['name'])
    if (!name || names.has(name)) continue
    names.add(name)
    commands.push({ name: name, label: name, description: string(skill['description']), kind: 'skill' })
  }
  return commands.sort((a: SlashCommand, b: SlashCommand) => rank(a.name) - rank(b.name))
}

function rank(name: string): number {
  const index = order.indexOf(name)
  return index < 0 ? order.length : index
}

export function slashInput(text: string): SlashInput | undefined {
  const line = text.trimStart()
  if (!line.startsWith('/')) return undefined
  const index = line.search(/\s/)
  return index < 0 ? { token: line.slice(1) } : { token: line.slice(1, index), rest: line.slice(index) }
}

export function resolveSlash(commands: SlashCommand[], token: string): SlashCommand | undefined {
  const query = token.toLowerCase()
  return commands.find((item: SlashCommand) => item.name.toLowerCase() === query || item.label.toLowerCase() === query)
}

function matchRank(item: SlashCommand, query: string): number {
  const name = item.name.toLowerCase()
  const label = item.label.toLowerCase()
  if (name.startsWith(query)) return 0
  if (label.startsWith(query)) return 1
  if (name.includes(query) || label.includes(query)) return 2
  let matched = 0
  for (let i = 0; i < name.length && matched < query.length; i++) {
    if (name[i] === query[matched]) matched++
  }
  return matched === query.length ? 3 : 4
}

export function filterSlash(commands: SlashCommand[], token: string): SlashCommand[] {
  const query = token.toLowerCase()
  return commands.filter((item: SlashCommand) => matchRank(item, query) < 4)
    .sort((a: SlashCommand, b: SlashCommand) => matchRank(a, query) - matchRank(b, query))
}
