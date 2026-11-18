// Compatibility for the fixed DS Bot per-Session schedule API on DSH 0.2.2-rc.1.
// Calls only public Schedule methods; no storage access or authorization bypass.
const invalid = message => Object.assign(new Error(message), { code: 'bot/invalid' })
const conflict = () => Object.assign(new Error('The scheduled task changed. Refresh and try again.'), { code: 'bot/schedule-conflict' })
const sessionId = value => typeof value === 'string' && value.length > 0 && value.length <= 256
const belongs = (entry, id) => entry?.target?.kind === 'session' && entry.target.sessionId === id
const movable = entry => entry.status === 'active' || entry.status === 'paused'
const legacyEntry = entry => ({ ...entry, sessionId: entry.target.sessionId })

function timingOf(request) {
  const selectors = ['after_seconds', 'at', 'every_seconds', 'daily', 'weekly', 'cron'].filter(key => request[key] !== undefined)
  if (selectors.length !== 1) throw invalid('Specify exactly one schedule timing')
  const key = selectors[0], kind = { after_seconds: 'after', every_seconds: 'every' }[key] ?? key
  return { kind, [key]: request[key] }
}
function checked(value) {
  if (value?.code) throw Object.assign(new Error(`Scheduled task operation failed: ${value.code}`), { code: value.code === 'schedule_conflict' ? 'bot/schedule-conflict' : 'bot/invalid' })
  return value
}

export function scheduleCompat(host) {
  if (!host || typeof host.catalog !== 'function') return null
  if (typeof host.delete === 'function') return host
  if (!['view', 'create', 'edit'].every(key => typeof host[key] === 'function')) return null
  const catalog = async () => {
    const entries = await host.catalog()
    if (!Array.isArray(entries)) throw invalid('Invalid schedule catalog')
    return entries.filter(entry => entry?.target?.kind === 'session' && sessionId(entry.target.sessionId)).map(legacyEntry)
  }
  const owned = async (id, session) => {
    if (!sessionId(id) || !sessionId(session)) throw invalid('No such task')
    const entry = checked(await host.view({ id }))
    if (!belongs(entry, session)) throw invalid('No such task for this conversation')
    return entry
  }
  return {
    hostWide: true,
    catalog,
    list: async ({ sessionId: session }) => (await catalog()).filter(entry => entry.sessionId === session),
    async create(session, request) {
      if (!sessionId(session)) throw invalid('No such conversation')
      const entry = checked(await host.create({ title: request.title, prompt: request.prompt,
        timing: timingOf(request), target: { kind: 'session', sessionId: session } }))
      if (!belongs(entry, session)) throw invalid('Host did not confirm the scheduled task target')
      return legacyEntry(entry)
    },
    async delete({ id, sessionId: session }) {
      const entry = await owned(id, session)
      const result = checked(await host.edit({ id, action: 'delete', expectedUpdatedAt: entry.updatedAt ?? null }))
      if (result?.id !== id || result.deleted !== true) throw invalid('Host did not confirm task deletion')
      return result
    },
    async move(from, to) {
      if (!sessionId(from) || !sessionId(to)) throw invalid('Invalid conversation for task migration')
      if (from === to) return
      for (const candidate of (await catalog()).filter(entry => entry.sessionId === from && movable(entry))) {
        // Re-read each task: the catalog is only an enumeration, never authority to edit.
        const entry = await owned(candidate.id, from)
        if (!movable(entry) || entry.updatedAt !== candidate.updatedAt || entry.executionActive) throw conflict()
        const result = checked(await host.edit({ id: entry.id, action: 'update',
          expectedUpdatedAt: entry.updatedAt ?? null, patch: { target: { kind: 'session', sessionId: to } } }, from))
        if (result?.id !== entry.id || !belongs(result, to) || result.status !== entry.status || result.scheduledAt !== entry.scheduledAt) throw invalid('Host did not confirm task migration')
      }
      // A new task may have been created while a user was authorizing migration.
      // Do not let the caller archive/stop the old part until every owned task moved.
      if ((await catalog()).some(entry => entry.sessionId === from && movable(entry))) throw conflict()
    },
  }
}
