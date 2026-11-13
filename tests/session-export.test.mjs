import assert from 'node:assert/strict'
import { test } from 'node:test'
import { EXPORT_CACHE_MAX_AGE_SECONDS, isStaleExportFolder, sessionArchiveName } from './SessionExportData.ts'

test('matches upstream archive naming and cannot put host input into directory names', () => {
  assert.equal(sessionArchiveName('session_123-abc'), 'dsh-session-session_123-abc.zip')
  assert.equal(sessionArchiveName('../中文\\name'), 'dsh-session-______name.zip')
  for (const bad of ['', 'bad\0id', 'bad\nid', 'x'.repeat(257)]) assert.throws(() => sessionArchiveName(bad), /无效/)
})

test('cache cleanup only recognizes expired export directories', () => {
  const name = 'export-73d7ddbc-69e6-410c-b4dd-96e4e7f5e177'
  const now = 100000
  assert.equal(isStaleExportFolder(name, now - EXPORT_CACHE_MAX_AGE_SECONDS - 1, now), true)
  assert.equal(isStaleExportFolder(name, now - EXPORT_CACHE_MAX_AGE_SECONDS, now), false)
  assert.equal(isStaleExportFolder(name, 0, now), false)
  assert.equal(isStaleExportFolder(name, now + 1, now), false)
  assert.equal(isStaleExportFolder('../' + name, 1, now), false)
  assert.equal(isStaleExportFolder('dsh-runtime', 1, now), false)
})
