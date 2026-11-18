import assert from 'node:assert/strict'
import { test } from 'node:test'
import { setTimeout as delay } from 'node:timers/promises'
import { activeMentionQuery, decodeSessionReferenceUri, encodeSessionReferenceUri, formatFileMention,
  formatSessionMention, fuzzyMentionScore, mentionAge, mentionDisplayOffset, mentionRawOffset, mentionRecents,
  MentionComposer, MentionLabels, MentionPickerController, parseMessageMentions } from './ui/MentionData.ts'

const session = (id, title, extra = {}) => ({ id, title, cwd: '/work', updatedAt: 100, ...extra })
const candidate = (id, title, extra = {}) => ({ sessionId: id, label: title, mention: formatSessionMention(id, title), sameWorkspace: true, ...extra })
function source() {
  return { generation: 1, connectionIdentity() { return this.generation },
    async listSessions(all, children) { return [session('current', 'Current'), session('chat', 'Other chat'),
      ...(all ? [session('archived', 'Archived', { archived: true })] : []),
      ...(children ? [session('child', 'Child label', { origin: 'subagent', parentSessionId: 'current' }),
        session('alien', 'Alien child', { origin: 'subagent', parentSessionId: 'chat' })] : [])] },
    async fileReferences(id, query) { return [{ path: query.endsWith('/') ? `${query}child.txt` : 'lib', kind: query.endsWith('/') ? 'file' : 'directory' }] },
    async sessionReferences() { return [candidate('chat', 'Other chat'), candidate('child', 'Child label'),
      candidate('archived', 'Archived'), candidate('alien', 'Alien child')] }
  }
}
async function query(controller, text) {
  controller.composer.replace(0, controller.composer.text.length, text, false)
  controller.changed()
  await delay(150)
}

test('encodes exact semantic session references including Unicode, validates canonical URIs, safely quotes paths', () => {
  for (const id of ['abc', '测试 id', 'quote"\\']) {
    const uri = encodeSessionReferenceUri(id)
    assert.equal(uri, `dsh-session:${Buffer.from(JSON.stringify(id)).toString('base64url')}`)
    assert.equal(decodeSessionReferenceUri(uri), id)
  }
  assert.equal(formatSessionMention('abc', 'title]\\'), '@[title\\]\\\\](dsh-session:ImFiYyI)')
  for (const bad of ['x:ImFiYyI', 'dsh-session:ImFiYyI=', 'dsh-session:eyJrIjoxfQ', 'dsh-session:wA']) assert.equal(decodeSessionReferenceUri(bad), undefined)
  assert.equal(formatFileMention('a b', true), '@"a b/')
  assert.equal(formatFileMention('a b'), '@"a b"')
  assert.equal(formatFileMention('lib', true, true), '@"lib/')
  for (const bad of ['bad"x', 'bad\nx', '\x7f', '']) assert.equal(formatFileMention(bad), undefined)
})

test('queries at caret respect emails, lines, quoted spaces, selected tokens, and path-only scope', () => {
  assert.equal(activeMentionQuery('a@b', 3), undefined)
  assert.deepEqual(activeMentionQuery('前文\n@"hello world', 16), { start: 3, end: 16, query: 'hello world', quoted: true, pathOnly: true })
  assert.equal(activeMentionQuery('@lib/ tail', 5).query, 'lib/')
  assert.equal(activeMentionQuery('@lib/ tail', 10), undefined)
  assert.equal(activeMentionQuery('@file.ts', 8, parseMessageMentions('@file.ts')), undefined)
})

test('message references preserve offsets, choose longest known labels, ignore emails and bare words', () => {
  const canonical = formatSessionMention('s', '修复]登录')
  const text = `${canonical} @修复 登录， @lib/file.ts。 @"a b/ @word a@b.com @README.md`
  assert.deepEqual(parseMessageMentions(text, ['修复', '修复 登录']).map(t => [t.kind, t.label]),
    [['session', '修复]登录'], ['session', '修复 登录'], ['file', 'file.ts'], ['folder', 'a b/'], ['file', 'README.md']])
  for (const token of parseMessageMentions(text)) assert.ok(text.slice(token.start, token.end).startsWith('@'))
})

test('native builder coordinates round-trip all token boundaries and preserve exact wire form while editing', () => {
  const c = new MentionComposer(), raw = formatSessionMention('chat', 'Chat')
  c.restore(`a ${raw} @"folder a/ end`)
  for (let rawOffset = 0; rawOffset <= c.text.length; rawOffset++) {
    if (c.tokens.some(t => t.start < rawOffset && rawOffset < t.end)) continue
    assert.equal(mentionRawOffset(mentionDisplayOffset(rawOffset, c.tokens), c.tokens), rawOffset)
  }
  const original = c.tokens[0]
  c.replace(original.end - 1, original.end, '', false)
  assert.equal(c.text, 'a  @"folder a/ end')
  assert.equal(c.tokens[0].label, 'folder a/')
  c.restore('before @ch after')
  c.insert(raw, 7, 10)
  assert.equal(c.text, `before ${raw} after`)
  assert.equal(c.start, 7 + raw.length + 1)
  c.replace(8, 8, 'x', false)
  assert.equal(c.text, `before ${raw}x after`)
})

test('pasted references become atomic but typed path text remains editable until selected', () => {
  const c = new MentionComposer()
  for (const character of '@file.ts') c.replace(c.end, c.end, character)
  assert.equal(c.tokens.length, 0)
  c.replace(c.end, c.end, ' @other.ts')
  assert.equal(c.tokens.length, 1)
  c.select(c.tokens[0].start + 2, c.tokens[0].end - 1)
  assert.equal(c.text.slice(c.start, c.end), '@other.ts')
})

test('fuzzy ranking and recent validation match original rules', () => {
  assert.ok(fuzzyMentionScore('Find file', 'fi') > fuzzyMentionScore('My file', 'fi'))
  assert.ok(fuzzyMentionScore('My file', 'fi') > fuzzyMentionScore('Profile', 'fi'))
  assert.ok(fuzzyMentionScore('abc', 'ac') !== undefined)
  assert.equal(fuzzyMentionScore('abc', 'ca'), undefined)
  assert.equal(mentionAge(0, 60000), '1分钟')
  assert.equal(mentionAge(0, 24 * 3600000), '1天')
  assert.equal(mentionRecents([{ key: 'f:a', mention: '@a' }, { key: 'f:a', mention: '@a' }, {}]).length, 1)
})

test('picker separates own children from visible chats, drills folders, inserts and persists canonical selections', async () => {
  const client = source(), picker = new MentionPickerController(client)
  picker.setContext('current')
  await query(picker, '@')
  assert.deepEqual(picker.sections.map(s => s.title), ['文件', '子代理', '对话'])
  assert.deepEqual(picker.items.map(i => i.key), ['f:lib', 's:child', 's:chat'])
  assert.equal(picker.highlighted, -1)
  assert.equal(picker.pickHighlighted(), false)
  const folder = picker.items[0]
  assert.equal(picker.pick(folder, true), true)
  assert.equal(picker.composer.text, '@lib/')
  await delay(150)
  assert.deepEqual(picker.items.map(i => i.key), ['f:lib/child.txt'])
  assert.equal(picker.pick(folder), false, 'stale row callback cannot select an earlier batch')
  assert.equal(picker.pickHighlighted(), true)
  assert.equal(picker.composer.text, '@lib/child.txt ')
  assert.equal(picker.composer.tokens[0].kind, 'file')
  assert.equal(picker.recents[0].cwd, '/work')
  await query(picker, '@oth')
  const chat = picker.items.find(i => i.key === 's:chat')
  assert.equal(picker.pick(chat), true)
  assert.equal(picker.composer.text, `${formatSessionMention('chat', 'Other chat')} `)
})

test('unavailable file service leaves chats usable and new chats use visible local sessions', async () => {
  const client = source()
  client.fileReferences = async () => { throw new Error('unavailable') }
  const picker = new MentionPickerController(client)
  picker.setContext('current'); await query(picker, '@')
  assert.equal(picker.items.length, 2)
  picker.setContext(''); await query(picker, '@oth')
  assert.deepEqual(picker.items.map(i => i.key), ['s:chat'])
  await query(picker, '@lib/')
  assert.deepEqual(picker.items, [])
})

test('dismissal persists within a query, hardware navigation wraps and Tab drills while Enter picks', async () => {
  const picker = new MentionPickerController(source())
  picker.setContext('current'); await query(picker, '@')
  assert.equal(picker.key('ArrowUp'), true)
  assert.equal(picker.highlighted, 2)
  assert.equal(picker.key('ArrowDown'), true)
  assert.equal(picker.highlighted, 0)
  assert.equal(picker.key('Tab'), true)
  await delay(150)
  assert.equal(picker.composer.text, '@lib/')
  picker.dismiss(); await query(picker, '@lib/c')
  assert.equal(picker.isOpen, false)
  await query(picker, 'x @')
  assert.equal(picker.isOpen, true)
})

test('query and connection races never expose old host rows or select stale candidates', async () => {
  const client = source(), gates = []
  client.fileReferences = () => new Promise(resolve => gates.push(resolve))
  const picker = new MentionPickerController(client)
  picker.setContext('current'); picker.composer.replace(0, 0, '@', false); picker.changed()
  await delay(0)
  picker.composer.replace(1, 1, 'x', false); picker.changed()
  assert.deepEqual(picker.items, [])
  await delay(140)
  gates[0]([{ path: 'old.txt' }]); await delay(0)
  assert.deepEqual(picker.items, [])
  client.generation++
  gates[1]([{ path: 'new.txt' }]); await delay(0)
  assert.deepEqual(picker.items, [])
  picker.setContext('current')
  assert.equal(picker.isOpen, false)
})

test('delayed labels notify message rendering without publishing an old composer draft', async () => {
  const client = source(), pending = []
  client.listSessions = () => new Promise(resolve => pending.push(resolve))
  const picker = new MentionPickerController(client)
  MentionLabels.clear()
  picker.composer.restore('old session draft')
  let draft = 'new session draft', labelChanges = 0
  picker.onChange = () => { draft = picker.composer.text }
  picker.onLabelsChange = () => { labelChanges++ }
  picker.setContext('current')
  assert.equal(parseMessageMentions('@Late title', [...MentionLabels.all]).length, 0)
  pending[0]([session('late', 'Late title')]); await delay(0)
  assert.equal(draft, 'new session draft')
  assert.equal(parseMessageMentions('@Late title', [...MentionLabels.all])[0].kind, 'session')
  assert.equal(labelChanges, 2, 'connection reset and loaded labels independently invalidate message rendering')
  picker.setContext('other')
  client.generation++
  pending[1]([session('stale', 'Old host label')]); await delay(0)
  assert.equal(MentionLabels.all.has('Old host label'), false)
  assert.equal(labelChanges, 2)
})
