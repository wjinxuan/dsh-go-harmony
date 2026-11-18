import { localizedSettingsText as t, localizedSettingsFormat as f } from './settings-locale-fixture.mjs';
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { stripTypeScriptTypes } from 'node:module'
import { test } from 'node:test'
import { setTimeout as delay } from 'node:timers/promises'
import vm from 'node:vm'

// Exercise the real page callbacks, controller and mention composer. Only the
// platform microphone, preferences, performance and usage services are replaced;
// this is not a device test. Performance SDK behavior has its own native fixture.
const read = path => readFileSync(new URL(`../entry/src/main/ets/${path}`, import.meta.url), 'utf8')
const index = read('pages/Index.ets')
const begin = index.indexOf('  aboutToAppear(): void {')
const end = index.indexOf('  private async loadStartup(', begin)
assert.ok(begin >= 0 && end > begin, 'Index voice lifecycle methods must be present')
const methods = index.slice(begin, end)
const recordUsage = index.match(/^  private recordUsage\(.*$/m)
assert.ok(recordUsage, 'Index usage callback must be present')
const fields = ['speechModeReady', 'speechModeLoadFailed'].map(name => {
  const match = index.match(new RegExp(`^  private ${name}:.*$`, 'm'))
  assert.ok(match, `Index ${name} field must be present`)
  return match[0]
}).join('\n')
const modules = ['dsh/SpeechData.ets', 'ui/MentionData.ets', 'ui/VoiceData.ets']
  .map(path => read(path).replace(/^import .*\n/gm, '').replace(/^export /gm, '')).join('\n')
const code = stripTypeScriptTypes(`${modules}\n(class Owner {
  ${fields}
  ${recordUsage[0]}
  ${methods}
  createMentions(client) { return new MentionPickerController(client) }
})`)

function deferred() {
  let resolve, reject
  const promise = new Promise((yes, no) => { resolve = yes; reject = no })
  return { promise, resolve, reject }
}

function fixture(loaded = Promise.resolve('system')) {
  let keyboardMode = 0
  const state = { starts: [], saves: [], usage: [], performance: [], cancelled: 0, capabilities: 0, focused: 0,
    catalog: { providerId: 'sensevoice-local', language: 'zh', maxDurationSeconds: 60,
      maxAudioBytes: 32000 * 60 + 44,
      providers: [{ id: 'sensevoice-local', location: 'host-local', phase: 'ready' }] } }
  class HarmonyVoiceBridge {
    async capabilities() { state.capabilities++; return { recognizer: true, recorder: true } }
    async requestPermission() { return 'granted' }
    async startRecognizer(consume) { state.starts.push('system'); state.consume = consume }
    async startRecorder(_seconds, consume) { state.starts.push('engine'); state.consume = consume }
    async cancel() { state.cancelled++ }
  }
  const Owner = vm.runInNewContext(code, {
    KeyboardAvoidMode: { OFFSET: 0, RESIZE: 1 },
    HarmonyVoiceBridge, setTimeout, clearTimeout,
    PerformanceMonitor: class {
      async start() { state.performance.push('start') }
      activity(foreground, active) { state.performance.push({ foreground, active }) }
    },
    createUsageStats: () => ({ async foreground() {}, async count(kind) { state.usage.push(kind) } }),
    loadAdvancedPreferences: async () => ({ language: 'system' }),
    loadQuickPanelPreferences: async () => ({}),
    registerDshFonts() {}, loadSpeechMode: () => loaded,
    loadAppPreferences: async () => ({ accentId: 'mist', themeMode: 'system', fontSize: 16 }),
    saveSpeechMode: async (_context, mode) => {
      state.saves.push(mode)
      if (state.saveError) throw state.saveError
    },
    util: {
      TextEncoder: class { encodeInto(text) { return new TextEncoder().encode(text) } },
      TextDecoder: { create: (...args) => ({ decodeWithStream: bytes => new TextDecoder(...args).decode(bytes) }) },
      Base64Helper: class {
        encodeToStringSync(bytes) { return Buffer.from(bytes).toString('base64') }
        decodeSync(text) { return new Uint8Array(Buffer.from(text, 'base64')) }
      }
    }
  })
  const owner = new Owner()
  const client = { connectionIdentity: () => 1, speechCatalog: async () => state.catalog }
  Object.assign(owner, {
    t, f, pendingLaunchChanged() {}, advanced: { language: 'system' },
    client, mode: 'remote', page: 'chat', sessionId: 'chat', foreground: true, speechMode: 'auto',
    draft: '', mentionRevision: 0, voicePhase: 'idle', voiceAvailable: false,
    voiceLevel: 0, voiceLevels: [0, 0, 0, 0, 0], voiceProvisionalStart: -1, voiceProvisionalEnd: -1,
    voiceNotice: '', errorText: '', connected: true, withdrawingAttachmentSessions: [],
    mentions: owner.createMentions(client), updateColors() {}, async loadStartup() {},
    getUIContext: () => ({ getHostContext: () => ({}),
      getKeyboardAvoidMode: () => keyboardMode, setKeyboardAvoidMode: value => { keyboardMode = value },
      getFocusController: () => ({ clearFocus() { state.focused++ } }) })
  })
  owner.aboutToAppear()
  return { owner, state }
}

test('voice start waits for the persisted mode before choosing any capture service', async t => {
  const load = deferred(), { owner, state } = fixture(load.promise)
  t.after(() => owner.voice.dispose())
  const start = owner.voice.start()
  await delay(0)
  assert.equal(owner.voicePhase, 'starting')
  assert.deepEqual(state.starts, [])
  load.resolve('engine')
  await start
  assert.deepEqual(state.starts, ['engine'])
  assert.equal(owner.speechMode, 'engine')
})

test('failed preference loading blocks capture until a replacement mode is saved successfully', async t => {
  const load = deferred(), { owner, state } = fixture(load.promise)
  t.after(() => owner.voice.dispose())
  load.reject(new Error('preference read failed'))
  await owner.speechModeReady
  await owner.voice.start()
  assert.equal(owner.voicePhase, 'idle')
  assert.deepEqual(state.starts, [])
  assert.equal(owner.speechModeLoadFailed, true)
  assert.match(owner.errorText, /语音设置读取失败/)
  assert.match(owner.voiceNotice, /读取语音设置/)
  state.saveError = new Error('preference write failed')
  await assert.rejects(owner.changeSpeechMode('engine'), /preference write failed/)
  await assert.rejects(owner.voice.loadMode(), /语音设置未能读取/)
  assert.equal(owner.speechMode, 'auto')
  state.saveError = undefined
  await owner.changeSpeechMode('system')
  assert.equal(owner.speechModeLoadFailed, false)
  await owner.voice.start()
  assert.deepEqual(state.starts, ['system'])
})

test('saving a new mode waits for startup loading so an old stored mode cannot overwrite it', async t => {
  const load = deferred(), { owner, state } = fixture(load.promise)
  t.after(() => owner.voice.dispose())
  const change = owner.changeSpeechMode('engine')
  await delay(0)
  assert.deepEqual(state.saves, [])
  load.resolve('system')
  await change
  assert.deepEqual(state.saves, ['engine'])
  assert.equal(owner.speechMode, 'engine')
  assert.equal(await owner.voice.loadMode(), 'engine')
  await owner.voice.start()
  assert.deepEqual(state.starts, ['engine'])
})

test('automatic model preference follows the current local connection, not a remote provider label', async t => {
  const { owner, state } = fixture(Promise.resolve('auto'))
  t.after(() => owner.voice.dispose())
  await owner.speechModeReady
  await owner.voice.refresh()
  await delay(0)
  owner.mode = 'local'
  assert.equal(owner.voice.preferLocalModel(), true)
  await owner.voice.start()
  assert.deepEqual(state.starts, ['engine'])
  await owner.voice.cancel()
  owner.mode = 'remote'
  assert.equal(owner.voice.preferLocalModel(), false)
  await owner.voice.start()
  assert.deepEqual(state.starts, ['engine', 'system'])
})

test('dictation and cancellation keep page text, mention wire tokens, selection and provisional spans in sync', async t => {
  const { owner, state } = fixture()
  t.after(() => owner.voice.dispose())
  const reference = `@[Thread](dsh-session:${Buffer.from(JSON.stringify('thread')).toString('base64url')})`
  const before = `Review @docs/readme.md ${reference} later`
  owner.draft = before
  assert.equal(owner.voice.readDraft().text, before)
  assert.equal(owner.mentions.composer.tokens.length, 2)
  const selection = before.lastIndexOf('later')
  owner.mentions.composer.select(selection, before.length)
  await owner.voice.start()
  state.consume({ type: 'partial', text: 'first words' })
  const provisional = before.slice(0, selection) + 'first words'
  assert.equal(owner.draft, provisional)
  assert.equal(owner.mentions.composer.text, provisional)
  assert.equal(owner.mentions.composer.tokens.length, 2)
  assert.equal(owner.mentions.composer.start, provisional.length)
  assert.equal(owner.mentions.composer.end, provisional.length)
  assert.equal(owner.voiceProvisionalStart, selection)
  assert.equal(owner.voiceProvisionalEnd, provisional.length)
  const revision = owner.mentionRevision
  await owner.voice.cancel()
  assert.equal(owner.draft, before)
  assert.equal(owner.mentions.composer.text, before)
  assert.equal(owner.mentions.composer.start, selection)
  assert.equal(owner.mentions.composer.end, before.length)
  assert.equal(owner.voiceProvisionalStart, -1)
  assert.equal(owner.voiceProvisionalEnd, -1)
  assert.ok(owner.mentionRevision > revision)
  await owner.voice.start()
  state.consume({ type: 'final', text: 'final words' })
  assert.equal(owner.draft, before.slice(0, selection) + 'final words')
  assert.equal(owner.mentions.composer.text, owner.draft)
  assert.equal(owner.mentions.composer.tokens[1].kind, 'session')
  assert.equal(owner.voicePhase, 'idle')
  assert.deepEqual(state.usage, ['voice'])
})

test('page and foreground callbacks cancel provisional speech and reject stale results', async t => {
  const { owner, state } = fixture()
  t.after(() => owner.voice.dispose())
  owner.draft = 'original'
  owner.voicePageChanged()
  await owner.voice.start()
  const old = state.consume
  old({ type: 'partial', text: 'temporary' })
  owner.page = 'settings'
  owner.voicePageChanged()
  assert.equal(owner.voicePhase, 'idle')
  assert.equal(owner.draft, 'original')
  owner.draft = 'next chat'
  owner.sessionId = 'next'
  owner.page = 'chat'
  owner.voicePageChanged()
  old({ type: 'final', text: 'stale previous chat' })
  assert.equal(owner.draft, 'next chat')
  await owner.voice.start()
  state.consume({ type: 'partial', text: 'temporary again' })
  owner.foreground = false
  owner.voiceForegroundChanged()
  assert.equal(owner.voicePhase, 'idle')
  assert.equal(owner.draft, 'next chat')
  const starts = state.starts.length
  await owner.voice.start()
  assert.equal(state.starts.length, starts)
  owner.foreground = true
  owner.voiceForegroundChanged()
  await owner.voice.start()
  assert.equal(state.starts.length, starts + 1)
})

test('page start action observes composer operation guards and binds the active session', async t => {
  const { owner, state } = fixture()
  t.after(() => owner.voice.dispose())
  for (const field of ['loadingChat', 'busy', 'sending', 'regenerating', 'choosingAttachments']) {
    owner[field] = true
    owner.startVoice()
    owner[field] = false
  }
  owner.withdrawingAttachmentSessions = [owner.sessionId]
  owner.startVoice()
  owner.withdrawingAttachmentSessions = []
  owner.connected = false
  owner.startVoice()
  assert.deepEqual(state.starts, [])
  assert.equal(state.focused, 0)
  owner.connected = true
  owner.startVoice()
  await delay(0)
  assert.deepEqual(state.starts, ['system'])
  assert.equal(state.focused, 1)
  owner.voice.setContext('different chat')
  assert.equal(owner.voicePhase, 'idle')
})
