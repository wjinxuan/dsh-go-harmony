import { abilityAccessCtrl, common } from '@kit.AbilityKit'
import { audio } from '@kit.AudioKit'
import { speechRecognizer } from '@kit.CoreSpeechKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { VoiceBridge, VoiceCapabilities, VoiceEvent, VoicePcmFrames, voiceLevel, voiceWav } from './VoiceData'

// CoreSpeechKit consumes 20 ms PCM frames; the same capture format serves host transcription.
export class HarmonyVoiceBridge implements VoiceBridge {
  private context: common.Context
  private capturer?: audio.AudioCapturer
  private recognizer?: speechRecognizer.SpeechRecognitionEngine
  private generation: number = 0
  private session: string = ''
  private system: boolean = false
  private recording: boolean = false
  private chunks: Uint8Array[] = []
  private frames: VoicePcmFrames = new VoicePcmFrames()
  private pending: Uint8Array[] = []
  private bytes: number = 0
  private maxBytes: number = 0
  private pump?: number
  private limitTimer?: number
  private closing: Promise<void> = Promise.resolve()
  private consume: (event: VoiceEvent) => void = () => {}
  private systemUnreliable: boolean = false

  constructor(context: common.Context) { this.context = context }

  async capabilities(): Promise<VoiceCapabilities> {
    return { recognizer: canIUse('SystemCapability.AI.SpeechRecognizer'),
      recorder: canIUse('SystemCapability.Multimedia.Audio.Capturer'), systemUnreliable: this.systemUnreliable }
  }

  async requestPermission(): Promise<string> {
    const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.context, ['ohos.permission.MICROPHONE'])
    if (result.authResults[0] === 0) return 'granted'
    return result.authResults[0] === -1 && result.dialogShownResults?.[0] === false ? 'blocked' : 'denied'
  }

  async openSettings(): Promise<void> {
    await abilityAccessCtrl.createAtManager().requestPermissionOnSetting(this.context, ['ohos.permission.MICROPHONE'])
  }

  async startRecognizer(consume: (event: VoiceEvent) => void): Promise<void> {
    const generation = this.generation + 1
    await this.cancel()
    if (generation !== this.generation) return
    this.consume = consume; this.system = true; this.session = `dsh_voice_${Date.now()}_${generation}`
    const session = this.session
    let engine: speechRecognizer.SpeechRecognitionEngine
    try { engine = await speechRecognizer.createEngine({ language: 'zh-CN', online: 1,
      extraParams: { 'recognizerMode': 'long', 'locate': 'CN' } }) }
    catch (reason) { this.systemUnreliable = true; throw this.error(reason) }
    if (generation !== this.generation) { engine.shutdown(); return }
    this.recognizer = engine
    let committed = ''
    let startTimer: number | undefined
    let started: () => void = () => {}
    let failed: (error: Error) => void = () => {}
    let starting = true
    const ready = new Promise<void>((resolve: () => void, reject: (error: Error) => void) => {
      started = resolve; failed = reject
      startTimer = setTimeout(() => reject(new Error('1002200002')), 5000)
    })
    const current = (id: string): boolean => generation === this.generation && id === session
    engine.setListener({
      onStart: (id: string, _message: string): void => { if (current(id)) started() },
      onEvent: (_id: string, _code: number, _message: string): void => {},
      onResult: (id: string, result: speechRecognizer.SpeechRecognitionResult): void => {
        if (!current(id)) return
        const text = committed + result.result
        if (result.isLast) this.consume({ type: 'final', text: text })
        else {
          if (result.isFinal) committed = text
          this.consume({ type: 'partial', text: text })
        }
      },
      onComplete: (id: string, _message: string): void => { if (current(id)) this.consume({ type: 'end' }) },
      onError: (id: string, code: number, _message: string): void => {
        if (!current(id)) return
        this.systemUnreliable = true
        if (starting) failed(new Error(`${code}`))
        else this.consume({ type: 'error', code: code })
      }
    })
    try {
      engine.startListening({ sessionId: session,
        audioInfo: { audioType: 'pcm', sampleRate: 16000, soundChannel: 1, sampleBit: 16 } })
      await ready
      starting = false
      if (generation !== this.generation) return
      this.pump = setInterval(() => this.feed(generation), 20)
      await this.capture(generation, 59)
    } catch (reason) {
      this.systemUnreliable = true
      failed(this.error(reason))
      await ready.catch(() => {})
      if (generation === this.generation) await this.cancel()
      throw this.error(reason)
    } finally { if (startTimer !== undefined) clearTimeout(startTimer) }
  }

  async startRecorder(maxSeconds: number, consume: (event: VoiceEvent) => void): Promise<void> {
    const generation = this.generation + 1
    await this.cancel()
    if (generation !== this.generation) return
    this.consume = consume; this.system = false
    try { await this.capture(generation, Math.max(1, Math.min(600, maxSeconds))) }
    catch (reason) { if (generation === this.generation) await this.cancel(); throw this.error(reason) }
  }

  private async capture(generation: number, maxSeconds: number): Promise<void> {
    const capturer = await audio.createAudioCapturer({ streamInfo: { samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
      channels: audio.AudioChannel.CHANNEL_1, sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW },
      capturerInfo: { source: audio.SourceType.SOURCE_TYPE_VOICE_RECOGNITION, capturerFlags: 0 } })
    if (generation !== this.generation) { await capturer.release(); return }
    this.capturer = capturer; this.maxBytes = Math.floor(maxSeconds * 32000); this.recording = true
    capturer.on('readData', (buffer: ArrayBuffer): void => {
      if (generation !== this.generation || !this.recording) return
      const remaining = this.maxBytes - this.bytes
      const length = Math.min(buffer.byteLength, remaining) & ~1
      const bytes = new Uint8Array(buffer).slice(0, length)
      this.bytes += length
      this.consume({ type: 'level', level: voiceLevel(bytes) })
      if (this.system) this.pending.push(...this.frames.push(bytes))
      else this.chunks.push(bytes)
      if (this.bytes >= this.maxBytes) this.limit(generation)
    })
    capturer.on('audioInterrupt', (event: audio.InterruptEvent): void => {
      if (generation === this.generation && (event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP ||
        event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE)) this.consume({ type: 'error', code: 100 })
    })
    await capturer.start()
    if (generation !== this.generation) return
    this.limitTimer = setTimeout(() => this.limit(generation), maxSeconds * 1000)
  }

  private limit(generation: number): void {
    if (generation !== this.generation || !this.recording) return
    this.recording = false
    this.consume({ type: 'limit' })
  }

  private feed(generation: number): void {
    if (generation !== this.generation || !this.recognizer || !this.pending.length) return
    const frame = this.pending.shift()
    if (!frame) return
    try { this.recognizer.writeAudio(this.session, frame) }
    catch (reason) { this.consume({ type: 'error', code: this.errorCode(reason) }) }
  }

  private stopCapture(): Promise<void> {
    this.recording = false
    if (this.limitTimer !== undefined) clearTimeout(this.limitTimer)
    this.limitTimer = undefined
    const capturer = this.capturer; this.capturer = undefined
    if (capturer) {
      capturer.off('readData'); capturer.off('audioInterrupt')
      // Detaching the capturer does not release the microphone; every restart waits for this promise.
      this.closing = this.closing.catch(() => {}).then(async (): Promise<void> => {
        try { await capturer.stop() } finally { await capturer.release() }
      })
    }
    return this.closing
  }

  async stop(): Promise<ArrayBuffer | undefined> {
    const generation = this.generation
    await this.stopCapture()
    if (generation !== this.generation) return undefined
    if (!this.system) {
      const wav = voiceWav(this.chunks); this.chunks = []; return wav
    }
    const tail = this.frames.finish()
    if (tail) this.pending.push(tail)
    while (generation === this.generation && this.pending.length) {
      await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 20) })
    }
    if (this.pump !== undefined) clearInterval(this.pump)
    this.pump = undefined
    if (generation === this.generation) this.recognizer?.finish(this.session)
    return undefined
  }

  async cancel(): Promise<void> {
    this.generation++
    if (this.pump !== undefined) clearInterval(this.pump)
    this.pump = undefined
    const recognizer = this.recognizer; this.recognizer = undefined
    if (recognizer) {
      try { recognizer.cancel(this.session) } catch {}
      try { recognizer.shutdown() } catch {}
    }
    this.chunks = []; this.pending = []; this.frames = new VoicePcmFrames(); this.bytes = 0
    this.consume = () => {}
    await this.stopCapture().catch(() => {})
  }

  private errorCode(reason: Object): number { return (reason as BusinessError).code || 100 }
  private error(reason: Object): Error {
    const code = this.errorCode(reason)
    return new Error(`${code === 100 && reason instanceof Error && /^\d+$/.test(reason.message) ? reason.message : code}`)
  }
}
