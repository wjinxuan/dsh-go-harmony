import assert from 'node:assert/strict'
import test from 'node:test'
import { workspaceViewPreferences, workspaceSections, workspacePreferenceChange, workspaceMoveRequest,
  workspaceMoveResult, workspaceDisplayTitle } from './ui/WorkspaceViewData.ts'
import { newChatPresets, defaultNewChatPreset, newChatPresetToApply, resolveNewChatModes, applyNewChatModes,
  newChatSetupRecords } from './ui/NewChatOptionsData.ts'
import { quickPanelPreferences, moveQuickDestination, appPageLink, launcherEntry, recentChatShortcuts,
  PAGE_LINK_IDS } from './ui/ShellNavigationData.ts'

const workspaces = ['a', 'b', 'c', 'd', 'e'].map(id => ({ id, title: id, path: `/work/${id}`, sessionIds: [] }))

test('workspace views preserve host order inside pinned/group/rest sections and group order by first member', () => {
  const prefs = workspaceViewPreferences({ selected: 'b', pinned: ['d', 'b', 'd'], groups: { a: 'Z', c: 'Y', d: 'Z', e: 'Y' } })
  assert.deepEqual(workspaceSections(workspaces, prefs).map(section => [section.kind, section.title, section.items.map(w => w.id)]), [
    ['pinned', '置顶', ['b', 'd']], ['group', 'Z', ['a']], ['group', 'Y', ['c', 'e']]
  ])
  assert.deepEqual(workspaceSections(workspaces, workspaceViewPreferences()).map(s => [s.title, s.items.length]), [['', 5]])
})

test('workspace preferences pin/unpin/group/select/forget are isolated copies and reject unknown operations', () => {
  const original = workspaceViewPreferences(), pinned = workspacePreferenceChange(original, 'b', 'pin')
  const grouped = workspacePreferenceChange(pinned, 'b', 'group', '  Clients  ')
  const selected = workspacePreferenceChange(grouped, 'b', 'select')
  assert.deepEqual(original, { selected: '', pinned: [], groups: {} })
  assert.equal(selected.groups.b, 'Clients')
  assert.deepEqual(workspacePreferenceChange(selected, 'b', 'forget'), original)
  assert.deepEqual(workspacePreferenceChange(grouped, 'b', 'unpin').pinned, [])
  assert.deepEqual(workspacePreferenceChange(grouped, 'b', 'group').groups, {})
  assert.throws(() => workspacePreferenceChange(original, 'b', 'wipe'))
  assert.equal(workspaceDisplayTitle({ ...workspaces[0], title: 'default-workspace' }), '默认工作区')
  assert.equal(workspaceDisplayTitle({ ...workspaces[0], title: '' }), 'a')
})

test('workspace reorder uses the published before-id contract and accepts only the confirmed full order', () => {
  assert.deepEqual(workspaceMoveRequest(['a', 'b', 'c'], 'b', -1), { request: { workspaceId: 'b', beforeWorkspaceId: 'a' } })
  assert.deepEqual(workspaceMoveRequest(['a', 'b', 'c'], 'a', 1), { request: { workspaceId: 'a', beforeWorkspaceId: 'c' } })
  assert.deepEqual(workspaceMoveRequest(['a', 'b', 'c'], 'b', 1), { request: { workspaceId: 'b' } })
  assert.deepEqual(workspaceMoveResult({ workspaceIds: ['a', 'c', 'b'] }, ['a', 'b', 'c'], 'b', 1), ['a', 'c', 'b'])
  assert.throws(() => workspaceMoveResult({ workspaceIds: ['a', 'b', 'c'] }, ['a', 'b', 'c'], 'b', 1), /未确认/)
  assert.throws(() => workspaceMoveRequest(['a'], 'a', 1))
  assert.throws(() => workspaceMoveRequest(['a', 'b'], 'missing', 1))
})

const presets = [{ id: 'dsh-go-companion-full', isDefault: true }, { id: 'standard' }, { id: 'broken', broken: 'load failed' }, { id: 'ptc' }]
test('new chat hides companion preset and explicitly applies visible default when the host default is hidden', () => {
  assert.deepEqual(newChatPresets(presets).map(p => p.id), ['standard', 'broken', 'ptc'])
  assert.equal(defaultNewChatPreset(newChatPresets(presets)), 'standard')
  assert.equal(newChatPresetToApply(presets, ''), 'standard')
  assert.equal(newChatPresetToApply(presets, 'ptc'), 'ptc')
  assert.equal(newChatPresetToApply([{ id: 'standard', isDefault: true }], ''), '')
})

test('explicit picks are checked again before creating a session; stale/broken choices do not silently downgrade', async () => {
  const client = { listAgentPresets: async () => presets, permissionPresets: async () => ({ options: [{ value: 'read-only' }] }) }
  assert.deepEqual(await resolveNewChatModes(client, { preset: '', permission: '' }), { preset: 'standard', permission: '' })
  assert.deepEqual(await resolveNewChatModes(client, { preset: 'ptc', permission: 'read-only' }), { preset: 'ptc', permission: 'read-only' })
  for (const preset of ['missing', 'broken', 'dsh-go-companion-full']) {
    await assert.rejects(resolveNewChatModes(client, { preset, permission: '' }), /不可用/)
  }
  await assert.rejects(resolveNewChatModes(client, { preset: '', permission: 'danger-full-access' }), /不可用/)
})

test('new session setup waits for projection acknowledgements and retries only unconfirmed picks', async () => {
  const calls = [], saved = []; let permission = '', preset = '', permissionWorks = false
  const client = { async selectAgentPreset(id, value) { calls.push(['preset', id, value]); preset = value },
    async setPermissionPreset(id, value) { calls.push(['permission', id, value]); if (permissionWorks) permission = value },
    async sessionProjections(id) { calls.push(['read', id]); return { agentPreset: preset, permissionPreset: permission } } }
  let owed = { preset: 'ptc', permission: 'read-only' }
  const settle = async remaining => { owed = remaining; saved.push(remaining) }
  await assert.rejects(applyNewChatModes(client, 'session', owed, () => true, settle), /权限预设尚未确认/)
  assert.deepEqual(owed, { preset: '', permission: 'read-only' })
  permissionWorks = true
  assert.deepEqual(await applyNewChatModes(client, 'session', owed, () => true, settle), { preset: '', permission: '' })
  assert.equal(calls.filter(call => call[0] === 'preset').length, 1)
  assert.equal(calls.filter(call => call[0] === 'permission').length, 2)
  assert.deepEqual(saved, [{ preset: '', permission: 'read-only' }, { preset: '', permission: '' }])
})

test('setup stops at changed connection or failed preset before sending later permission mutations', async () => {
  let current = true, permissions = 0
  const client = { async selectAgentPreset() { current = false }, async sessionProjections() { throw Error('should not read') },
    async setPermissionPreset() { permissions++ } }
  await assert.rejects(applyNewChatModes(client, 's', { preset: 'ptc', permission: 'read-only' }, () => current), /已变更/)
  assert.equal(permissions, 0)
  await assert.rejects(applyNewChatModes(client, '', { preset: '', permission: '' }, () => true), /已变更/)
})

test('corrupt owed setup storage fails closed and does not lose unacknowledged choices', () => {
  for (const encoded of ['', 'null', '[]', '{', '{"s":{}}', '{"s":{"preset":123,"permission":""}}']) {
    assert.throws(() => newChatSetupRecords(encoded), /已损坏/)
  }
  const stored = Object.fromEntries(Array.from({ length: 25 }, (_, i) => [`host/session-${i}`, { preset: 'ptc', permission: 'read-only' }]))
  assert.deepEqual(newChatSetupRecords(JSON.stringify(stored)), stored)
  assert.deepEqual(newChatSetupRecords('{}'), {})
})

test('quick panel defaults, empty choices, removed destinations and ordering survive normalization', () => {
  assert.deepEqual(quickPanelPreferences(), { swipe: true, items: ['plugins', 'engine', 'settings'] })
  assert.deepEqual(quickPanelPreferences({ swipe: false, items: ['remote', 'removed', 'remote', 'web'] }), { swipe: false, items: ['remote', 'web'] })
  assert.deepEqual(quickPanelPreferences({ items: [] }), { swipe: true, items: [] })
  assert.deepEqual(moveQuickDestination(['plugins', 'engine', 'settings'], 'settings', -1), ['plugins', 'settings', 'engine'])
  assert.deepEqual(moveQuickDestination(['plugins'], 'plugins', -1), ['plugins'])
})

test('fixed page deep links match upstream allowlist and reject host/session mutations and malformed URLs', () => {
  for (const id of PAGE_LINK_IDS) assert.equal(appPageLink(`dshgo://open/${id}`), id)
  assert.equal(appPageLink('DSHGO://OPEN/engine/'), 'engine')
  assert.equal(appPageLink('dshgo://open/%65ngine'), 'engine')
  for (const link of ['https://open/engine', 'dshgo://share/engine', 'dshgo://open', 'dshgo://open/',
    'dshgo://open/engine/logs', 'dshgo://open/engine?x=1', 'dshgo://open/engine#top', 'dshgo://me@open/engine',
    'dshgo://open:8080/engine', 'dshgo://open/Engine', 'dshgo://open/nope', 'dshgo://open/cot-translation',
    'dshgo://open/voice-input', 'dshgo://open/web', 'dshgo://open/files', 'dshgo://open/session-detail',
    'dshgo://open/plugin-panel:pkg%23main', 'dshgo://open/%', 'dshgo://open/engine\nlogs']) assert.equal(appPageLink(link), '', link)
})

test('launcher entries stage new/voice text, validate chat IDs, and reject unauthenticated screenshot paths', () => {
  assert.deepEqual(launcherEntry({ kind: 'voice', text: 'draft' }), { kind: 'voice', text: 'draft', sessionId: '', host: '' })
  assert.deepEqual(launcherEntry({ kind: 'chat', sessionId: 's1', host: 'remote-a', text: 'not sent' }),
    { kind: 'chat', text: '', sessionId: 's1', host: 'remote-a' })
  for (const raw of [{}, { kind: 'screenshot', path: '/private/file' }, { kind: 'chat', sessionId: '' },
    { kind: 'chat', sessionId: 'id\0bad' }, { kind: 'new', text: 'x'.repeat(131073) }]) assert.equal(launcherEntry(raw), undefined)
  const sessions = [4, 3, 2, 1].map(i => ({ id: `s${i}`, title: i === 4 ? '' : `Chat ${i}`, cwd: '/', updatedAt: i }))
  assert.deepEqual(recentChatShortcuts(sessions.concat({ ...sessions[0], id: 'archive', updatedAt: 9, archived: true }), 'host')
    .map(s => [s.id, s.title]), [['s4', '未命名对话'], ['s3', 'Chat 3'], ['s2', 'Chat 2']])
})
