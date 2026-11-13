import assert from 'node:assert/strict'
import { test } from 'node:test'
import { absoluteHostPath, deletionOutcomeUnknown, directoryLevel, directoryNameProblem, directoryParent,
  directoryPreferenceKey, recentDirectoryPaths, searchSpans, sessionSearchRows, SessionDeletionGate } from './ui/SessionManagementData.ts'

const sessions = [
  { id: 'latest', title: 'ArkUI conversation', updatedAt: 30, cwd: '/work' },
  { id: 'older', title: 'Conversation: ArkUI', updatedAt: 20, cwd: '/other', archived: true },
  { id: 'by-content', title: 'Scratch', updatedAt: 10, cwd: '/work' }
]

test('combines case-insensitive title terms and ranked, deduplicated known host hits', () => {
  const hits = [
    { sessionId: 'unknown', snippet: 'ignore this' },
    { sessionId: 'by-content', snippet: 'one result' },
    { sessionId: 'by-content', snippet: 'duplicate' },
    { sessionId: 'older', snippet: 'an archive' }
  ]
  assert.deepEqual(sessionSearchRows(sessions, 'conversation Ａrkui', hits, false).map(row =>
    [row.id, row.titleMatch, row.snippet]), [['latest', true, ''], ['older', true, 'an archive'], ['by-content', false, 'one result']])
  assert.deepEqual(sessionSearchRows(sessions, '', [], true).map(row => row.id), ['older'])
  assert.deepEqual(sessionSearchRows(sessions, 'scratch work', [], false).map(row => row.id), ['by-content'])
})

test('keeps server paths authoritative, validates folder names, supports host path formats', () => {
  const level = directoryLevel({ path: '/work', home: '/work', entries: [
    { name: 'shown', path: '/actual/shown' }, { name: '.hidden', path: '/actual/.hidden', hidden: true }, { name: 'invalid' }
  ], truncated: true })
  assert.deepEqual(level.crumbs, [{ name: '/work', path: '/work', hidden: false }])
  assert.equal(level.entries.length, 2)
  assert.equal(level.entries[1].path, '/actual/.hidden')
  assert.equal(level.entries[1].hidden, true)
  assert.equal(level.truncated, true)
  assert.throws(() => directoryLevel({ path: '/work' }), /文件夹/)
  for (const bad of ['..', '.', 'a/b', 'a\\b', 'nul\0', 'a'.repeat(121)]) assert.ok(directoryNameProblem(bad), bad)
  assert.equal(directoryNameProblem('新项目'), '')
  for (const path of ['/root', 'C:\\projects', '\\\\server\\share']) assert.ok(absoluteHostPath(path), path)
  for (const path of ['foo/bar', 'C:relative', '/control\x7f']) assert.equal(absoluteHostPath(path), false, path)
})

test('only recognized definitive host refusal avoids an unknown destructive outcome', () => {
  assert.equal(deletionOutcomeUnknown(new Error('拒绝删除（session-active）')), false)
  assert.equal(deletionOutcomeUnknown(new Error('网关不可用（gateway/unavailable）')), true)
  assert.equal(deletionOutcomeUnknown(new Error('响应 ID 不匹配')), true)
})

test('a shared deletion gate persists across drawer and archive navigation', () => {
  const gate = new SessionDeletionGate()
  gate.markUnknown(7)
  const reopenedDrawer = gate
  const archive = gate
  assert.equal(reopenedDrawer.blocked(7), true)
  assert.equal(archive.blocked(7), true)
  archive.reconcile(6)
  assert.equal(reopenedDrawer.blocked(7), true)
  assert.equal(archive.blocked(8), false)
  archive.markUnknown(8)
  reopenedDrawer.reconcile(7)
  assert.equal(archive.blocked(7), false)
  assert.equal(archive.blocked(8), true)
  assert.equal(reopenedDrawer.begin(9), true)
  assert.equal(archive.begin(9), false)
  archive.markUnknown(9)
  reopenedDrawer.reconcile(9)
  archive.end(9)
  assert.equal(reopenedDrawer.blocked(9), true)
  reopenedDrawer.reconcile(9)
  assert.equal(archive.begin(9), true)
  archive.end(9)
})

test('highlights original code units and merges overlaps while leaving markup as literal text', () => {
  const snippet = '<mark>ＡrＫUI</mark> [link](javascript:script) İ 𐐀'
  const spans = searchSpans(snippet, 'arkui ui 𐐨')
  assert.deepEqual(spans.filter(part => part.highlighted).map(part => part.text), ['ＡrＫUI', '𐐀'])
  assert.equal(spans.map(part => part.text).join(''), snippet)
  const excerpt = searchSpans('prefix-prefix-prefix 😃abcdefghijklm查询尾部', '查询', true)
  assert.equal(excerpt[0].text, '…')
  assert.equal(excerpt[1].text[0], '😃'[0])
  assert.equal(excerpt[2].text, '查询')
})

test('recent directory scope retains only the host authority and limits distinct absolute paths', () => {
  assert.equal(directoryPreferenceKey('local'), 'host-local')
  assert.equal(directoryPreferenceKey('https://EXAMPLE.ORG:440/path?token=secret'), 'host-remote-example.org:440')
  assert.equal(directoryPreferenceKey('https://name:secret@example.org/path'), '')
  assert.equal(directoryPreferenceKey('https://local/path'), 'host-remote-local')
  assert.equal(directoryParent('/project/'), '/')
  assert.equal(directoryParent('/'), '')
  assert.equal(directoryParent('C:\\folder\\'), 'C:\\')
  assert.deepEqual(recentDirectoryPaths(['/home', '/home', 'relative', '/tmp', '/data', '/misc', '/extra']),
    ['/home', '/tmp', '/data', '/misc'])
})
