import assert from 'node:assert/strict'
import { test } from 'node:test'
import { setTimeout as delay } from 'node:timers/promises'
import { VoiceInputController, voiceDraft, VoicePcmFrames, voiceWav, voiceLevel } from './ui/VoiceData.ts'
import { checkSpeechWav } from './dsh/SpeechData.ts'
import { HarmonyVoiceBridge } from './ui/VoiceInput.ts'
import { fixture, speechRecognizer } from './voice-fixture.mjs'

const catalog = { providerId: 'sensevoice-local', language: 'zh', maxDurationSeconds: 60, maxAudioBytes: 32000 * 60 + 44,
  providers: [{ id: 'sensevoice-local', name: 'SenseVoice', phase: 'ready', location: 'host-local' }] }
function setup(mode = 'system') {
  const state = { draft: { text: 'Hello world', start: 5, end: 5 }, writes: [], messages: [], starts: [], cancelCount: 0, catalog,
    permission: 'granted', capability: { recognizer: true, recorder: true }, wav: voiceWav([new Uint8Array(32000)]) }
  const bridge = { async capabilities() { return state.capability }, async requestPermission() { return state.permission },
    async startRecognizer(consume) { state.starts.push('system'); state.consume = consume },
    async startRecorder(seconds, consume) { state.starts.push('engine'); state.seconds = seconds; state.consume = consume },
    async stop() { return state.wav }, async cancel() { state.cancelCount++ }, async openSettings() {} }
  const client = { generation: 1, connectionIdentity() { return this.generation }, async speechCatalog() { return state.catalog },
    async transcribeSpeech(wav, providerId, language, setCancel) {
      state.transcription = { wav, providerId, language }
      setCancel(() => { state.rpcCancelled = true })
      return { text: 'recognized text' }
    } }
  const controller = new VoiceInputController(client, bridge)
  controller.loadMode = async () => mode
  controller.readDraft = () => state.draft
  controller.writeDraft = value => { state.draft = value; state.writes.push(value) }
  controller.onMessage = value => state.messages.push(value)
  return { state, bridge, client, controller }
}

test('dictation uses fixed selection anchor, Latin seam spaces, CJK adjacency and provisional bounds', () => {
  assert.deepEqual(voiceDraft({ text: 'Helloworld', start: 5, end: 5 }, ' new ', true),
    { text: 'Hello new world', start: 9, end: 9, provisionalStart: 6, provisionalEnd: 9 })
  assert.equal(voiceDraft({ text: '你世界', start: 1, end: 1 }, '好', false).text, '你好世界')
  assert.equal(voiceDraft({ text: 'Hello,world', start: 6, end: 6 }, 'new', false).text, 'Hello, new world')
  assert.equal(voiceDraft({ text: 'replace this now', start: 8, end: 12 }, 'that', false).text, 'replace that now')
})

test('PCM frames preserve split sample bytes and WAV format matches host validator', () => {
  const data = Uint8Array.from({ length: 1300 }, (_, i) => i % 256), frames = new VoicePcmFrames()
  assert.equal(frames.push(data.slice(0, 13)).length, 0)
  const emitted = frames.push(data.slice(13))
  assert.equal(emitted.length, 2)
  assert.deepEqual(emitted[0], data.slice(0, 640))
  assert.deepEqual(emitted[1], data.slice(640, 1280))
  const tail = frames.finish()
  assert.deepEqual(tail.slice(0, 20), data.slice(1280))
  assert.ok(tail.slice(20).every(byte => byte === 0))
  assert.equal(frames.finish(), undefined)
  const wav = voiceWav([data.slice(0, 400), data.slice(400)])
  checkSpeechWav(wav)
  assert.deepEqual(new Uint8Array(wav).slice(44), data)
  assert.throws(() => voiceWav([new Uint8Array(1)]))
  assert.equal(voiceLevel(new Uint8Array(640)), 0)
  assert.ok(voiceLevel(new Uint8Array(new Int16Array(320).fill(16384).buffer)) > 0)
})

test('system partial/final replace one anchor and cancellation restores complete original draft', async () => {
  const { controller, state } = setup()
  await controller.start()
  assert.equal(controller.phase, 'listening')
  state.consume({ type: 'partial', text: 'new' })
  assert.equal(state.draft.text, 'Hello new world')
  state.consume({ type: 'partial', text: 'new words' })
  assert.equal(state.draft.text, 'Hello new words world')
  await controller.cancel()
  assert.deepEqual(state.draft, { text: 'Hello world', start: 5, end: 5 })
  await controller.start()
  state.consume({ type: 'final', text: 'final words' })
  assert.equal(state.draft.text, 'Hello final words world')
  assert.equal(state.draft.provisionalStart, -1)
  assert.equal(controller.phase, 'idle')
})

test('auto retries a failing system service once, discards its partial and records fresh audio', async () => {
  const { controller, state } = setup('auto')
  await controller.start()
  state.consume({ type: 'partial', text: 'discard me' })
  state.consume({ type: 'error', code: 1002200009 })
  await delay(0)
  assert.deepEqual(state.starts, ['system', 'engine'])
  assert.equal(state.draft.text, 'Hello world')
  assert.equal(state.seconds, 59)
  assert.ok(state.messages.some(message => message.text.includes('请再说一次')))
  state.consume({ type: 'error', code: 100 })
  await delay(0)
  assert.deepEqual(state.starts, ['system', 'engine'])
  assert.equal(controller.phase, 'idle')
})

test('auto prefers only the on-device SenseVoice model; a ready remote host still starts system recognition', async () => {
  const remote = setup('auto')
  await remote.controller.refresh(); await delay(0)
  await remote.controller.start()
  assert.deepEqual(remote.state.starts, ['system'])
  await remote.controller.cancel()
  const ready = setup('auto')
  ready.controller.preferLocalModel = () => true
  await ready.controller.refresh(); await delay(0)
  await ready.controller.start()
  assert.deepEqual(ready.state.starts, ['engine'])
  await ready.controller.stop()
  assert.equal(ready.state.transcription.providerId, 'sensevoice-local')
  assert.equal(ready.state.transcription.language, 'zh')
  assert.equal(ready.state.draft.text, 'Hello recognized text world')
  const cloud = setup('auto')
  cloud.controller.preferLocalModel = () => true
  cloud.state.catalog = { ...catalog, providerId: 'cloud', providers: [{ id: 'cloud', phase: 'ready', location: 'cloud' }] }
  await cloud.controller.refresh(); await delay(0); await cloud.controller.start()
  assert.deepEqual(cloud.state.starts, ['system'])
  await cloud.controller.cancel()
})

test('explicit engine mode uses a ready remote provider and cannot claim an absent provider works', async () => {
  const remote = setup('engine')
  await remote.controller.start(); await remote.controller.stop()
  assert.deepEqual(remote.state.starts, ['engine'])
  assert.equal(remote.state.transcription.providerId, 'sensevoice-local')
  const absent = setup('engine')
  absent.state.catalog = undefined
  await absent.controller.start()
  assert.deepEqual(absent.state.starts, [])
  assert.equal(absent.controller.phase, 'idle')
  assert.equal(absent.state.messages[0].change, true)
})

test('denied permission never records and blocked permission exposes settings action', async () => {
  const { controller, state } = setup()
  state.permission = 'blocked'
  await controller.start()
  assert.deepEqual(state.starts, [])
  assert.equal(state.messages[0].openSettings, true)
  assert.equal(state.writes.length, 0)
})

test('background, session change and delayed transfer cancellation preserve draft owner', async () => {
  const { controller, state, client } = setup('engine')
  let complete
  client.transcribeSpeech = async (_wav, _provider, _language, setCancel) => {
    setCancel(() => { state.rpcCancelled = true })
    return new Promise(resolve => { complete = resolve })
  }
  controller.setContext('first')
  await controller.start()
  const stop = controller.stop(); await delay(0)
  controller.setContext('second')
  state.draft = { text: 'second owner', start: 12, end: 12 }
  complete({ text: 'must not leak' }); await stop
  assert.equal(state.rpcCancelled, true)
  assert.equal(state.draft.text, 'second owner')
  await controller.start()
  controller.setForeground(false)
  assert.equal(controller.phase, 'idle')
})

test('microphone permission dialog lifecycle does not cancel its own pending request', async () => {
  const { controller, bridge, state } = setup()
  let grant
  bridge.requestPermission = () => new Promise(resolve => { grant = resolve })
  const start = controller.start()
  controller.setForeground(false)
  assert.equal(controller.phase, 'starting')
  controller.setForeground(true)
  grant('granted'); await start
  assert.equal(controller.phase, 'listening')
  await controller.cancel()
})

test('late system callbacks after cancel and old-host results cannot write a new draft', async () => {
  const { controller, state, client } = setup()
  await controller.start()
  const old = state.consume
  await controller.cancel()
  state.draft = { text: 'new draft', start: 9, end: 9 }
  old({ type: 'final', text: 'stale' })
  assert.equal(state.draft.text, 'new draft')
  await controller.start()
  client.generation++
  state.consume({ type: 'partial', text: 'another host' })
  assert.equal(state.draft.text, 'new draft')
  controller.setContext('')
  assert.equal(controller.phase, 'idle')
})

test('too-short host recordings do not upload, no-speech errors do not trigger fallback', async () => {
  const short = setup('engine')
  short.state.wav = voiceWav([new Uint8Array(100)])
  await short.controller.start(); await short.controller.stop()
  assert.equal(short.state.transcription, undefined)
  assert.equal(short.state.messages.at(-1).text, '没有听清，再说一次')
  const noSpeech = setup('auto')
  await noSpeech.controller.start()
  noSpeech.state.consume({ type: 'error', code: 7 }); await delay(0)
  assert.deepEqual(noSpeech.state.starts, ['system'])
})

test('native bridge configures real APIs for Chinese PCM16, frames input, forwards final and releases microphone', async () => {
  const bridge = new HarmonyVoiceBridge({})
  const events = []
  await bridge.startRecognizer(event => events.push(event))
  const engine = fixture.engines.at(-1), capture = fixture.captures.at(-1)
  assert.deepEqual(engine.options, { language: 'zh-CN', online: 1, extraParams: { recognizerMode: 'long', locate: 'CN' } })
  assert.equal(capture.options.streamInfo.samplingRate, 16000)
  assert.equal(capture.options.streamInfo.channels, 1)
  const bytes = Uint8Array.from({ length: 1280 }, (_, i) => i % 256)
  capture.callbacks.readData(bytes.buffer)
  await delay(50)
  assert.deepEqual(engine.frames, [bytes.slice(0, 640), bytes.slice(640)])
  engine.listener.onResult(engine.params.sessionId, { result: '你好', isFinal: true, isLast: false })
  engine.listener.onResult(engine.params.sessionId, { result: '世界', isFinal: true, isLast: true })
  assert.equal(events.findLast(event => event.type === 'final').text, '你好世界')
  await bridge.stop()
  assert.equal(engine.finished, engine.params.sessionId)
  assert.equal(capture.released, true)
  await bridge.cancel()
  assert.equal(engine.released, true)
})

test('native recorder emits complete WAV and stale createEngine cannot cancel replacement capture', async () => {
  const bridge = new HarmonyVoiceBridge({})
  let release
  fixture.createEngine = () => new Promise(resolve => { release = resolve })
  const oldStart = bridge.startRecognizer(() => {})
  await delay(0)
  await bridge.cancel()
  fixture.createEngine = undefined
  await bridge.startRecorder(5, () => {})
  const capture = fixture.captures.at(-1), stale = { shutdown() { this.released = true } }
  release(stale); await oldStart
  assert.equal(stale.released, true)
  assert.equal(capture.released, undefined)
  capture.callbacks.readData(new Uint8Array(9600).buffer)
  const wav = await bridge.stop()
  checkSpeechWav(wav)
  assert.equal(wav.byteLength, 9644)
  await bridge.cancel()
})

test('native restart waits for a detached microphone release after cancel or stop, and old cleanup cannot release its replacement', async () => {
  for (const closingAction of ['cancel', 'stop']) {
    const bridge = new HarmonyVoiceBridge({})
    await bridge.startRecorder(5, () => {})
    const first = fixture.captures.at(-1), count = fixture.captures.length
    let release, closingStarted = false
    fixture.releaseCapture = capture => {
      if (capture !== first) return Promise.resolve()
      closingStarted = true
      return new Promise(resolve => { release = resolve })
    }
    try {
      const closing = bridge[closingAction]()
      await delay(0)
      assert.equal(closingStarted, true)
      const cancelling = bridge.cancel()
      const restarting = bridge.startRecorder(5, () => {})
      await delay(0)
      assert.equal(fixture.captures.length, count, `${closingAction}: no new capturer while old release is pending`)
      release()
      await Promise.all([closing, cancelling, restarting])
      assert.equal(first.released, true)
      assert.equal(fixture.captures.length, count + 1)
      const second = fixture.captures.at(-1)
      assert.equal(second.started, true)
      assert.equal(second.released, undefined, 'old cleanup must only release the first capturer')
      second.callbacks.readData(new Uint8Array(9600).buffer)
      assert.equal((await bridge.stop()).byteLength, 9644)
    } finally {
      fixture.releaseCapture = undefined
      await bridge.cancel()
    }
  }
})
