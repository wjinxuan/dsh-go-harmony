import assert from 'node:assert/strict'
import test from 'node:test'
import http from 'node:http'
import { setTimeout as delay } from 'node:timers/promises'
import { cotTranslationLimits, reasoningFragments, reasoningNeedsTranslation, reasoningTranslationRequest,
  ReasoningTranslation, CotTranslationStore } from './ui/CotTranslationData.ts'
import { voiceScribeEntries, voiceScribeSettings, VoiceScribeController } from './ui/VoiceScribeData.ts'

const flush = () => delay(0)
const settings = () => ({ language: 'zh', polishPrompt: '', providers: [{ url: 'https://speech.test/v1',
  model: 'whisper-1', hasKey: true }], hotwords: { path: '/tmp/hotwords.txt', rules: 3, error: '' } })
const inventory = () => ({ entries: [{ entryId: 'plugin:scribe', moduleName: 'dsh-voice-scribe', enabled: true, fiberPhase: 'active' }] })

test('translation limits preserve accepted provider, explicit target and session cache scope', () => {
  const limits = cotTranslationLimits({ maxTextChars: 8, availableProviders: ['google'], preferences: { provider: 'google', targetLanguage: 'auto' } })
  assert.deepEqual(reasoningTranslationRequest('abc', limits, 'zh', 'session-1'), {
    request: { text: 'abc', provider: 'google', targetLanguage: 'zh', sessionId: 'session-1' }
  })
  assert.equal(cotTranslationLimits({}).maxTextChars, 4000)
  assert.equal(cotTranslationLimits({ preferences: { provider: 'bing' }, availableProviders: ['google'] }).usable, false)
  assert.throws(() => reasoningTranslationRequest('a'.repeat(9), limits, 'zh', 's'))
  assert.throws(() => reasoningTranslationRequest('a', { ...limits, usable: false }, 'zh', 's'))
  assert.equal(reasoningTranslationRequest('abc', { ...limits, targetLanguage: 'ja' }, 'zh', '').request.targetLanguage, 'ja')
})

test('fragment splitting preserves separators, UTF16 surrogate pairs and unfinished streaming tail', () => {
  for (const source of ['One.\r\n \r\nTwo.\n\nThr', 'abcdefgh😀ijk lmnopqrst', '\n\n😀😀😀\n\n', '  abcdefghijk  ']) {
    const fragments = reasoningFragments(source, true, 6)
    assert.equal(fragments.map(f => f.text + f.suffix).join(''), source)
    assert.ok(fragments.every(f => f.text.length <= 6))
    assert.ok(fragments.every(f => !/[\uD800-\uDBFF]$/.test(f.text) && !/^[\uDC00-\uDFFF]/.test(f.text)))
    assert.equal(fragments.at(-1).complete, false)
  }
  assert.throws(() => reasoningFragments('😀x', false, 1))
  assert.deepEqual(reasoningFragments('Alpha.\n\nBeta.', true, 4000), [
    { text: 'Alpha.', suffix: '\n\n', complete: true }, { text: 'Beta.', suffix: '', complete: false }
  ])
})

test('translation offer follows upstream Unicode script policy', () => {
  for (const source of ['Let me check the pubspec first.', 'é', '設定を確認します。', '설정을 확인합니다 設定', 'Θα ελέγξω']) {
    assert.equal(reasoningNeedsTranslation(source, 'zh'), true, source)
  }
  for (const source of ['看 flutter_riverpod 的 ProviderScope 实现。', '设 θ 为入射角，先算 sin θ 的值。', '𠀀𠀁𠀂 id', '123 + 456', '… ✅']) {
    assert.equal(reasoningNeedsTranslation(source, 'zh'), false, source)
  }
  assert.equal(reasoningNeedsTranslation('先检查设置。', 'en'), true)
  assert.equal(reasoningNeedsTranslation('The button says 登录 here.', 'en'), false)
})

test('translation queues one fragment at a time, caches duplicate text, and follows live source updates', async () => {
  const asked = [], gates = []
  const controller = new ReasoningTranslation(4000, text => new Promise(resolve => { asked.push(text); gates.push(resolve) }))
  controller.update('One.\n\nTwo.\n\nThr', true)
  assert.deepEqual(asked, ['One.'])
  controller.update('One.\n\nTwo.\n\nThree.', false)
  gates.shift()('一'); await flush()
  assert.deepEqual(asked, ['One.', 'Two.'])
  assert.equal(controller.text, '一\n\nTwo.\n\nThree.')
  gates.shift()('二'); await flush(); gates.shift()('三'); await flush()
  assert.equal(controller.text, '一\n\n二\n\n三')
  controller.update('One.\n\nOne.\n\nThree.', false); await flush()
  assert.equal(asked.length, 3)
  assert.equal(controller.text, '一\n\n一\n\n三')
  assert.equal(controller.pending, false)
})

test('translation failures stop requests until explicit retry; empty responses never erase source', async () => {
  let failed = true, count = 0
  const controller = new ReasoningTranslation(4000, async text => { count++; if (failed) return ''; return `译:${text}` })
  controller.update('Alpha.\n\nBeta.', false); await flush()
  assert.equal(controller.failed, true); assert.equal(controller.text, 'Alpha.\n\nBeta.')
  controller.update('Alpha.\n\nBeta.', false); await flush(); assert.equal(count, 1)
  failed = false; controller.retry(); await flush()
  assert.equal(controller.failed, false); assert.equal(controller.text, '译:Alpha.\n\n译:Beta.')
})

test('translation store retains collapse/row recreation state and disposes previous host/session', async () => {
  const store = new CotTranslationStore(), holder = store.get('host1/session1', 'block1')
  let done, notices = 0
  holder.controller = new ReasoningTranslation(4000, () => new Promise(resolve => { done = resolve }))
  holder.controller.onChange = () => notices++
  holder.showTranslation = true; holder.controller.update('pending', false)
  assert.equal(store.get('host1/session1', 'block1'), holder)
  const previous = notices, newer = store.get('host2/session1', 'block1')
  done('translated'); await flush()
  assert.equal(notices, previous); assert.equal(newer.showTranslation, false); assert.equal(holder.controller, undefined)
  assert.notEqual(store.get('host1/session1', 'block1'), holder)
})

test('scribe decoder rejects invalid settings and does not retain unknown provider secrets', () => {
  const value = settings(); value.providers[0].apiKey = 'must not enter UI'
  assert.equal(voiceScribeSettings(value).providers[0].apiKey, undefined)
  assert.equal(voiceScribeEntries({ entries: inventory().entries.concat([{ ...inventory().entries[0], enabled: false }]) }).length, 1)
  for (const invalid of [{}, { ...settings(), providers: [{}] }, { ...settings(), hotwords: { path: '', rules: 1.5, error: '' } }]) {
    assert.throws(() => voiceScribeSettings(invalid))
  }
})

function scribeSetup() {
  const state = { value: settings(), requests: [], active: true, entries: inventory(), failRead: false, failWrite: false }
  const transport = { async inventory() { return state.entries }, async request(body) {
    state.requests.push(body)
    if (body.action === 'get-settings') { if (state.failRead) throw new Error('read failed'); return structuredClone(state.value) }
    if (state.failWrite) throw new Error('write failed')
    Object.assign(state.value, body.patch); return {}
  } }
  return { state, transport, controller: new VoiceScribeController('plugin:scribe', transport, () => state.active) }
}

test('scribe reads and writes only the two REST fields, trims/reset values and reads the accepted result', async () => {
  const { state, controller } = scribeSetup()
  await controller.refresh()
  assert.equal(await controller.save(controller.generation, 'language', ' en '), true)
  assert.equal(controller.data.language, 'en')
  assert.deepEqual(state.requests[1], { action: 'set-settings', patch: { language: 'en' } })
  assert.equal(await controller.save(controller.generation, 'polishPrompt', '  rewrite  '), true)
  assert.equal(await controller.save(controller.generation, 'polishPrompt', ''), true)
  assert.equal(state.value.polishPrompt, '')
  assert.equal(await controller.save(controller.generation, 'apiKey', 'bad'), false)
  assert.equal(await controller.save(controller.generation, 'polishPrompt', 'x'.repeat(8001)), false)
  assert.equal(state.requests.filter(body => body.action === 'set-settings').length, 3)
})

test('scribe stopped plugin and old editors cannot send a mutation, including A→B→A identity changes', async () => {
  const { state, controller } = scribeSetup()
  await controller.refresh(); const generation = controller.generation
  state.active = false; controller.invalidate(); state.active = true; await controller.refresh()
  assert.equal(await controller.save(generation, 'language', 'ja'), false)
  state.entries.entries[0].fiberPhase = 'inactive'
  assert.equal(await controller.save(controller.generation, 'language', 'ja'), false)
  assert.equal(state.requests.filter(body => body.action === 'set-settings').length, 0)
})

test('scribe read/write races preserve acknowledged values; acknowledged save survives refresh failure', async () => {
  const { state, transport, controller } = scribeSetup()
  await controller.refresh()
  const request = transport.request; let late
  transport.request = body => body.action === 'get-settings' && !late ? new Promise(resolve => { late = resolve }) : request(body)
  const refresh = controller.refresh(); await flush()
  assert.equal(await controller.save(controller.generation, 'language', 'en'), true)
  late(settings()); await refresh
  assert.equal(controller.data.language, 'en')
  state.failRead = true
  assert.equal(await controller.save(controller.generation, 'language', 'ja'), true)
  assert.equal(controller.data.language, 'ja'); assert.match(controller.error, /已保存/)
  state.failRead = false; state.failWrite = true
  assert.equal(await controller.save(controller.generation, 'language', 'ko'), false)
  assert.equal(controller.data.language, 'ja'); assert.match(controller.error, /未能确认/)
})

test('scribe checks source again after asynchronous inventory before sending REST bytes', async () => {
  const { state, transport, controller } = scribeSetup()
  await controller.refresh(); let release
  transport.inventory = () => new Promise(resolve => { release = resolve })
  const save = controller.save(controller.generation, 'language', 'ja')
  state.active = false; controller.invalidate(); release(inventory())
  assert.equal(await save, false)
  assert.equal(state.requests.filter(body => body.action === 'set-settings').length, 0)
  assert.equal(controller.data, undefined)
})

test('synthetic HTTP plugin and RPC service exercise real request/ack/streaming work, without external speech or translation providers', async t => {
  let value = settings(); const observed = []
  const server = http.createServer(async (req, res) => {
    let text = ''; for await (const chunk of req) text += chunk
    const body = JSON.parse(text); observed.push({ path: req.url, body })
    res.setHeader('content-type', 'application/json')
    if (req.url === '/voice-input') {
      if (body.action === 'set-settings') { Object.assign(value, body.patch); res.end(JSON.stringify({ ok: true })); return }
      res.end(JSON.stringify({ ok: true, value })); return
    }
    assert.equal(req.url, '/api/cotTranslation/translate')
    assert.equal(body.request.provider, 'google'); assert.equal(body.request.sessionId, 'session')
    res.end(JSON.stringify({ value: `译:${body.request.text}` }))
  })
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
  t.after(() => new Promise(resolve => server.close(resolve)))
  const base = `http://127.0.0.1:${server.address().port}`
  const post = async (path, body) => (await fetch(base + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) })).json()
  const scribe = new VoiceScribeController('plugin:scribe', { inventory: async () => inventory(), request: async body => {
    const envelope = await post('/voice-input', body); assert.equal(envelope.ok, true); return envelope.value || {}
  } }, () => true)
  await scribe.refresh(); assert.equal(await scribe.save(0, 'language', 'ja'), true); assert.equal(scribe.data.language, 'ja')
  const limits = cotTranslationLimits({ preferences: { provider: 'google', targetLanguage: 'zh' } })
  const translation = new ReasoningTranslation(4000, async text => (await post('/api/cotTranslation/translate',
    reasoningTranslationRequest(text, limits, 'zh', 'session'))).value)
  translation.update('First.\n\nNext', true)
  for (let i = 0; translation.pending && i < 100; i++) await delay(10)
  assert.equal(translation.text, '译:First.\n\nNext')
  translation.update('First.\n\nNext.', false)
  for (let i = 0; translation.pending && i < 100; i++) await delay(10)
  assert.equal(translation.text, '译:First.\n\n译:Next.')
  assert.equal(observed.filter(call => call.path.includes('cotTranslation')).length, 2)
})
