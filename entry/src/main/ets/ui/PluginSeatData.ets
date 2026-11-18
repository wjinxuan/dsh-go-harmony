import { array, object, string, number, strings, WireObject } from '../dsh/DshWire'

const UNSEATED: string[] = ["conversation.approval.detail", "conversation.chat.flow", "conversation.chat.message.images", "conversation.chat.reasoning.body", "conversation.chat.user.images", "conversation.composer.bar", "conversation.header", "conversation.hero.agentPreset", "conversation.hero.workspace", "conversation.hero.workspace.directoryFlow", "conversation.input.activity", "conversation.input.attachments", "conversation.input.model", "conversation.input.model.label", "conversation.input.permission", "conversation.input.plan", "conversation.session", "conversation.session.header", "conversation.session.header.corner", "conversation.session.header.lineage", "conversation.trajectory.images", "main.conversation", "plugins.bundle.activation", "rightbar", "rightbar.session", "root", "settings.close", "settings.header", "settings.launcher", "settings.models.sign-in", "settings.trigger", "shell.bottom", "shell.leading", "sidebar", "sidebar.brand.mark", "sidebar.brand.name", "sidebar.chat.conversation", "sidebar.right.pane.tab.title", "sidebar.settings", "sidebar.toggle.badge", "sidebar.workspaces", "sidebar.workspaces.directoryFlow", "workspace.toast"]

function seatLabels(raw: Object | null | undefined): string[] {
  if (typeof raw === 'string') return raw.trim() ? [raw.trim()] : []
  const value = object(raw), labels: string[] = []
  for (const key of Object.keys(value)) { const label = string(value[key]).trim(); if (label && !labels.includes(label)) labels.push(label) }
  return labels
}

export interface PluginSeat { slot: string; pkg: string; cell: string; title: string; labels: string[]; order: number }
export function parseWebBoot(html: string): WireObject {
  if (html.length > 4194304) return {}
  const assignment = /(?:globalThis|window|self)\s*(?:\.\s*__DSH_BOOT__|\[\s*(["'])__DSH_BOOT__\1\s*\])\s*=\s*/g
  let match: RegExpExecArray | null
  while ((match = assignment.exec(html)) !== null) {
    const start = assignment.lastIndex; if (html[start] !== '{') continue
    let depth = 0, quoted = false
    for (let at = start; at < html.length; at++) {
      const char = html[at]
      if (quoted) { if (char === '\\') at++; else if (char === '"') quoted = false; else if (char === '\n') break; continue }
      if (char === '"') quoted = true
      else if (char === '{' || char === '[') depth++
      else if (char === '<') break
      else if (char === '}' || char === ']') {
        if (--depth !== 0) continue
        try { const graph = object(JSON.parse(html.slice(start, at + 1))); if (Array.isArray(graph['entries'])) return graph } catch {}
        break
      }
    }
  }
  return {}
}

export function pluginSeats(value: Object | null | undefined, bundles: WireObject[] = [], boot: WireObject = {}): PluginSeat[] {
  const inventory = object(value), slots: WireObject = {}, seen = new Set<string>(), result: PluginSeat[] = []
  for (const key of Object.keys(object(inventory['slots']))) slots[key] = object(inventory['slots'])[key]
  const packages = array(inventory['packages']).map(object)
  const official = packages.concat(bundles).filter((pkg: WireObject) => pkg['official'] === true).map((pkg: WireObject) => string(pkg['name']))
  if (!inventory['slots'] || object(inventory['occupancy'])['stale'] === true || (boot['rev'] && boot['rev'] !== inventory['bootRev'])) {
    const clients = Array.isArray(boot['entries']) ? array(boot['entries']).map(object).map((row: WireObject) => string(row['id'])) : packages.filter((row: WireObject) => row['hasClient'] === true).map((row: WireObject) => string(row['name']))
    for (const bundle of bundles) {
      const name = string(bundle['name']); if (!name || bundle['installed'] !== true || !clients.includes(name) || official.includes(name) || name.startsWith('@deepseek-ai/')) continue
      const cell: WireObject = { 'package': name, 'cell': name, 'label': object(bundle['meta'])['title'] }
      slots['plugins.bundle.config'] = array(slots['plugins.bundle.config']).concat([cell])
      for (const row of array(bundle['rows']).map(object)) {
        const id = string(row['rowId']); if (!id) continue
        const config: WireObject = { 'package': name, 'cell': name + '#' + id, 'label': object(row['meta'])['title'] }
        slots['plugins.row.config'] = array(slots['plugins.row.config']).concat([config])
      }
    }
  }
  for (const slot of Object.keys(slots)) for (const raw of array(slots[slot])) {
    const row = object(raw), pkg = string(row['package']), cell = string(row['cell']), key = JSON.stringify([slot, pkg, cell])
    const labels = seatLabels(row['label']), named = slot === 'main' ? 'sidebar.panellist' : slot === 'sidebar.right.pane.tab' ? 'sidebar.right.pane.tab.title' : ''
    const siblings = array(slots[named]).map(object).filter((item: WireObject) => item['package'] === pkg)
    const sibling = siblings.find((item: WireObject) => item['cell'] === cell) || (siblings.length === 1 ? siblings[0] : undefined)
    for (const label of seatLabels(sibling?.['label'])) if (!labels.includes(label)) labels.push(label)
    if (UNSEATED.includes(slot) || slot === 'dsh-go.panel' || cell.startsWith('dsh-go:') || !pkg || pkg === 'dsh-go-bridge' || pkg.startsWith('@deepseek-ai/') || row['official'] === true || official.includes(pkg) || seen.has(key)) continue
    if (slot.length > 128 || pkg.length > 214 || cell.length > 256) continue
    seen.add(key); result.push({ slot: slot, pkg: pkg, cell: cell, title: labels[0] || cell || pkg, labels: labels, order: number(row['order'], 0) })
  }
  return result.sort((a: PluginSeat, b: PluginSeat) => a.order - b.order)
}

export function seatConfig(seat: PluginSeat, session: string, recipes: WireObject, guard: boolean): WireObject | undefined {
  if (!guard) return undefined
  const recipe = object(object(recipes['slots'])[seat.slot]), forms = strings(recipe['forms'])
  if (!forms.length || (recipe['session'] === true && !session)) return undefined
  const mode = forms.includes('page') ? 'page' : forms.includes('panel') ? 'panel' : ''
  if (!mode) return undefined // Overlay islands are opt-in in the fixed upstream and have no active override provider.
  const target: WireObject = {}, official = object(recipes['official']), cell = seat.cell, labels = seat.labels
  if (recipe['session'] === true) target['session'] = session
  const web: WireObject = {}, after: WireObject = {}
  switch (recipe['open']) {
    case 'settings':
      if (!cell || strings(official['settings']).includes(cell)) web['settings'] = cell || 'general'
      else { if (!labels.length) return undefined; web['settings'] = 'general'; after['settings'] = labels }
      break
    case 'settings-general': web['settings'] = 'general'; break
    case 'plugin': web['panel'] = 'plugins'; after['plugin'] = cell || seat.pkg; break
    case 'plugin-row': {
      const split = cell.indexOf('#'); if (split <= 0 || split === cell.length - 1) return undefined
      web['panel'] = 'plugins'; after['plugin'] = cell.slice(0, split); after['row'] = cell.slice(split + 1); break
    }
    case 'panel':
      if (strings(official['panels']).includes(cell)) web['panel'] = cell
      else { if (!labels.length) return undefined; after['panel'] = labels }
      break
    case 'rightbar':
      if (!cell) return undefined
      if (strings(official['rightbar']).includes(cell)) web['rightbar'] = cell
      else after['rightbar'] = labels
      break
    case 'session-view': {
      if (!cell || !labels.length) return undefined
      const view: WireObject = { 'id': cell, 'names': labels }; after['view'] = view; break
    }
    case 'session': case 'none': break
    default: return undefined
  }
  if (Object.keys(web).length) target['web'] = web
  if (Object.keys(after).length) target['then'] = after
  const mask = mode === 'panel' || ['settings.general.item'].includes(seat.slot)
  const emptyLabels: WireObject = {}
  const config: WireObject = { 'slot': seat.slot, 'cell': mode === 'panel' ? null : cell, 'mode': mode, 'mask': mask,
    'stretch': string(recipe['stretch']) || 'scroller', 'pad': recipe['pad'] || [16, 16], 'labels': recipes['labels'] || emptyLabels, 'target': target }
  if (Array.isArray(recipe['slots'])) config['slots'] = recipe['slots']
  return config
}
export function seatWebTarget(seat: PluginSeat, session: string): WireObject {
  const target: WireObject = {}
  if (/^conversation\.|^sidebar\.right\.|^tool\./.test(seat.slot) && session) target['session'] = session
  if (seat.slot.startsWith('settings.')) target['settings'] = ['general', 'models', 'plugins', 'agent-presets', 'account'].includes(seat.cell) ? seat.cell : 'general'
  else if (seat.slot.startsWith('plugins.')) target['pluginItem'] = [seat.pkg, seat.title]
  else if (seat.slot === 'main' || seat.slot === 'sidebar.panellist') { if (['plugins', 'schedules', 'cordis'].includes(seat.cell)) target['panel'] = seat.cell; else target['sidebar'] = true }
  else if (seat.slot === 'tool.view.cordis') target['panel'] = 'cordis'
  else if (seat.slot.startsWith('sidebar.') && !seat.slot.startsWith('sidebar.right.')) target['sidebar'] = true
  return target
}

export function cordisShown(row: WireObject): WireObject {
  const versions = array(row['packages']).map(object)
  return versions.find((pkg: WireObject) => pkg['packageId'] === row['nextPackageId']) || versions.find((pkg: WireObject) => pkg['packageId'] === row['currentPackageId']) || versions[versions.length - 1] || {}
}
export function cordisStatus(row: WireObject): string {
  const latest = object(row['latestRun']), active = object(row['activeRun'])
  if (latest['status'] === 'awaiting-approval') return '等待批准'
  if (latest['status'] === 'failed' && latest['packageId'] === cordisShown(row)['packageId']) return '启动失败'
  if (string(active['pluginRunId'])) return '运行中'
  return latest['status'] === 'starting-host' ? '正在启动' : '未运行'
}
