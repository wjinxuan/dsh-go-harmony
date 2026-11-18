import type { DshClient } from '../dsh/DshClient'
import { selectedSpeechProvider, speechProviderUsable, speechMaxSeconds, SpeechCatalog, SpeechMode } from '../dsh/SpeechData'

export type VoicePhase = 'idle' | 'starting' | 'listening' | 'transcribing'
export type VoiceEngine = 'system' | 'engine'
export interface VoiceDraft {
  text: string; start: number; end: number; provisionalStart?: number; provisionalEnd?: number
}
export interface VoiceMessage { text: string; openSettings?: boolean; change?: boolean }
export interface VoiceCapabilities { recognizer: boolean; recorder: boolean; systemUnreliable?: boolean }
export interface VoiceEvent { type: string; text?: string; code?: number; level?: number }
export interface VoiceBridge {
  capabilities(): Promise<VoiceCapabilities>;
  requestPermission(): Promise<string>;
  startRecognizer(consume: (event: VoiceEvent) => void): Promise<void>;
  startRecorder(maxSeconds: number, consume: (event: VoiceEvent) => void): Promise<void>;
  stop(): Promise<ArrayBuffer | undefined>;
  cancel(): Promise<void>;
  openSettings(): Promise<void>;
}

// dsh-Go a9877420 voice_controller: a Latin seam gets a space, CJK does not.
export function voiceDraft(base: VoiceDraft, heard: string, provisional: boolean): VoiceDraft {
  const start = Math.max(0, Math.min(base.start, base.text.length))
  const end = Math.max(start, Math.min(base.end, base.text.length))
  const before = base.text.substring(0, start), after = base.text.substring(end), spoken = heard.trim()
  const space = (left: string, right: string): boolean => /[A-Za-z0-9,.!?;:]$/.test(left) && /^[A-Za-z0-9]/.test(right)
  const lead = spoken && space(before, spoken) ? ' ' : '', trail = spoken && space(spoken, after) ? ' ' : ''
  const caret = start + lead.length + spoken.length
  return { text: before + lead + spoken + trail + after, start: caret, end: caret,
    provisionalStart: provisional && spoken ? start + lead.length : -1,
    provisionalEnd: provisional && spoken ? caret : -1 }
}

export function voiceWav(chunks: Uint8Array[]): ArrayBuffer {
  const size = chunks.reduce((sum: number, chunk: Uint8Array) => sum + chunk.byteLength, 0)
  if (size % 2 !== 0 || size > 32000 * 600) throw new Error('录音格式或长度无效')
  const wav = new ArrayBuffer(44 + size), view = new DataView(wav), output = new Uint8Array(wav)
  const label = (offset: number, text: string): void => {
    for (let i = 0; i < text.length; i++) view.setUint8(offset + i, text.charCodeAt(i))
  }
  label(0, 'RIFF'); view.setUint32(4, 36 + size, true); label(8, 'WAVE'); label(12, 'fmt ')
  view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true)
  view.setUint32(24, 16000, true); view.setUint32(28, 32000, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true)
  label(36, 'data'); view.setUint32(40, size, true)
  let offset = 44
  for (const chunk of chunks) { output.set(chunk, offset); offset += chunk.byteLength }
  return wav
}

export function voiceLevel(pcm: Uint8Array): number {
  const view = new DataView(pcm.buffer, pcm.byteOffset, pcm.byteLength)
  let power = 0
  for (let i = 0; i + 1 < pcm.byteLength; i += 2) power += Math.pow(view.getInt16(i, true) / 32768, 2)
  return Math.min(1, Math.sqrt(power / Math.max(1, Math.floor(pcm.byteLength / 2))) * 4)
}

export class VoicePcmFrames {
  private pending: Uint8Array = new Uint8Array(0)
  push(bytes: Uint8Array): Uint8Array[] {
    const joined = new Uint8Array(this.pending.length + bytes.length)
    joined.set(this.pending); joined.set(bytes, this.pending.length)
    const frames: Uint8Array[] = []
    let offset = 0
    for (; offset + 640 <= joined.length; offset += 640) frames.push(joined.slice(offset, offset + 640))
    this.pending = joined.slice(offset)
    return frames
  }
  finish(): Uint8Array | undefined {
    if (!this.pending.length) return undefined
    const frame = new Uint8Array(640); frame.set(this.pending); this.pending = new Uint8Array(0)
    return frame
  }
}

export function voiceErrorText(code: number): string {
  if (code === 201 || code === 9) return '需要麦克风权限才能语音输入'
  if (code === 100 || code === 6800104) return '没能打开麦克风'
  if (code === 6) return '没有听到声音，请再说一次'
  if (code === 7) return '没有听清，再说一次'
  if (code === 1002200006 || code === 8) return '系统识别正忙，请稍后再试'
  if (code === 1002200009 || code === 4) return '系统识别服务出错，请稍后再试'
  if ([1002200001, 1002200002, 1002200007, 1002200008, 1002200010, 5].includes(code)) return '无法启动系统识别，请检查语音服务'
  if (code === 1) return '语音识别连接超时，请检查网络'
  if (code === 2) return '语音识别网络连接失败'
  return `语音服务返回错误 ${code}，请更换识别服务`
}

export class VoiceInputController {
  phase: VoicePhase = 'idle'
  engine?: VoiceEngine
  level: number = 0
  readDraft: () => VoiceDraft = (): VoiceDraft => ({ text: '', start: 0, end: 0 })
  writeDraft: (value: VoiceDraft) => void = () => {}
  loadMode: () => Promise<SpeechMode> = (): Promise<SpeechMode> => Promise.resolve('auto')
  preferLocalModel: () => boolean = (): boolean => false
  onChange: () => void = () => {}
  onRecognized: () => void = () => {}
  onMessage: (message: VoiceMessage) => void = () => {}
  private client: DshClient
  private bridge: VoiceBridge
  private caps: VoiceCapabilities = { recognizer: false, recorder: false }
  private catalog?: SpeechCatalog
  private catalogConnection: number = -1
  private operation: number = 0
  private probeId: number = 0
  private sessionId: string = ''
  private runSession: string = ''
  private connection: number = -1
  private mode: SpeechMode = 'auto'
  private target?: SpeechCatalog
  private base?: VoiceDraft
  private heard: string = ''
  private fallbackTried: boolean = false
  private switching: boolean = false
  private foreground: boolean = true
  private permissionPending: boolean = false
  private disposed: boolean = false
  private timeout?: number
  private cancelTranscription?: () => void

  constructor(client: DshClient, bridge: VoiceBridge) { this.client = client; this.bridge = bridge }
  get active(): boolean { return this.phase !== 'idle' }
  get engineReady(): boolean {
    return this.caps.recorder && this.catalogConnection === this.client.connectionIdentity() &&
      !!this.catalog && speechProviderUsable(selectedSpeechProvider(this.catalog))
  }
  get available(): boolean { return this.caps.recognizer || this.engineReady }

  private localModelReady(catalog: SpeechCatalog | undefined = this.catalog): boolean {
    const provider = selectedSpeechProvider(catalog)
    return this.preferLocalModel() && this.engineReady && provider?.id === 'sensevoice-local' && provider.location === 'host-local'
  }

  setContext(sessionId: string): void {
    if (sessionId !== this.sessionId || this.active && this.connection !== this.client.connectionIdentity()) void this.cancel()
    this.sessionId = sessionId
    if (this.catalogConnection !== this.client.connectionIdentity()) { this.catalog = undefined; void this.refresh() }
  }

  setForeground(value: boolean): void {
    this.foreground = value
    if (!value && this.active && !this.permissionPending) void this.cancel()
    else if (value) void this.refresh()
  }

  async refresh(): Promise<void> {
    try { this.caps = await this.bridge.capabilities() } catch { this.caps = { recognizer: false, recorder: false } }
    if (this.disposed) return
    this.onChange()
    // Probe in the background: a working phone service does not wait for an unavailable host.
    void this.probe()
  }

  private async probe(): Promise<SpeechCatalog | undefined> {
    if (!this.caps.recorder || this.disposed) return undefined
    const probe = ++this.probeId, connection = this.client.connectionIdentity()
    let timer: number | undefined
    let catalog: SpeechCatalog | undefined
    try {
      catalog = await Promise.race<SpeechCatalog | undefined>([this.client.speechCatalog(),
        new Promise<undefined>((resolve: (value: undefined) => void) => { timer = setTimeout(() => resolve(undefined), 4000) })])
      if (!catalog || !speechProviderUsable(selectedSpeechProvider(catalog))) catalog = undefined
    } catch { catalog = undefined }
    finally { if (timer !== undefined) clearTimeout(timer) }
    if (this.disposed || connection !== this.client.connectionIdentity()) return undefined
    if (probe === this.probeId) { this.catalog = catalog; this.catalogConnection = connection; this.onChange() }
    return catalog
  }

  private current(operation: number): boolean {
    return !this.disposed && this.active && operation === this.operation && this.sessionId === this.runSession &&
      this.connection === this.client.connectionIdentity()
  }
  private state(phase: VoicePhase): void { this.phase = phase; this.onChange() }

  async start(): Promise<void> {
    if (this.active || this.disposed || !this.foreground) return
    const operation = ++this.operation
    this.connection = this.client.connectionIdentity(); this.runSession = this.sessionId
    this.fallbackTried = false; this.switching = false; this.heard = ''; this.state('starting')
    this.permissionPending = true
    let permission = 'denied'
    try { permission = await this.bridge.requestPermission() }
    catch { if (this.current(operation)) this.fail('没能打开麦克风'); return }
    finally { if (operation === this.operation) this.permissionPending = false }
    if (!this.current(operation)) return
    if (!this.foreground) { await this.cancel(); return }
    if (permission !== 'granted') {
      this.finish()
      this.onMessage({ text: permission === 'blocked' ? '麦克风权限已关闭' : '需要麦克风权限才能语音输入', openSettings: permission === 'blocked' })
      return
    }
    try { this.mode = await this.loadMode(); this.caps = await this.bridge.capabilities() }
    catch { if (this.current(operation)) this.fail('没能读取语音设置，请重试'); return }
    if (!this.current(operation)) return
    this.base = this.readDraft()
    const system = this.mode === 'system' || this.mode === 'auto' && this.caps.recognizer && !this.caps.systemUnreliable
    if (system && !this.caps.recognizer) { this.fail('请在系统设置中选择语音识别服务', true); return }
    if (!system || this.mode === 'auto' && this.localModelReady()) {
      const target = await this.probe()
      if (!this.current(operation)) return
      if (target && (!system || this.localModelReady(target))) { await this.record(operation, target); return }
      if (!system) {
        this.fail(this.mode === 'engine' ? '请先在语音设置里下载语音模型' : '系统识别用不了，可以在语音设置里下载语音模型', true)
        return
      }
    }
    this.engine = 'system'
    try { await this.bridge.startRecognizer((event: VoiceEvent) => this.event(operation, event)) }
    catch (reason) { if (this.current(operation) && this.engine === 'system') await this.error(operation, this.code(reason)); return }
    if (this.current(operation) && this.engine === 'system' && !this.switching && this.phase === 'starting') this.state('listening')
  }

  private async record(operation: number, target: SpeechCatalog, fallback: boolean = false): Promise<void> {
    if (!this.current(operation)) return
    this.target = target; this.engine = 'engine'; this.switching = false
    try { await this.bridge.startRecorder(Math.max(1, Math.min(600, speechMaxSeconds(target) - 1)),
      (event: VoiceEvent) => this.event(operation, event)) }
    catch (reason) { if (this.current(operation)) this.fail(voiceErrorText(this.code(reason))); return }
    if (!this.current(operation)) return
    this.state('listening')
    if (fallback) this.onMessage({ text: '已改用语音模型，请再说一次' })
  }

  private async fallback(operation: number): Promise<void> {
    this.fallbackTried = true; this.switching = true; this.engine = undefined
    if (this.timeout !== undefined) clearTimeout(this.timeout)
    this.restore(); this.heard = ''; this.state('starting')
    try { await this.bridge.cancel() } catch {}
    if (!this.current(operation)) return
    const target = await this.probe()
    if (!this.current(operation)) return
    if (!target) { this.fail('系统识别用不了，可以在语音设置里下载语音模型', true); return }
    await this.record(operation, target, true)
  }

  async stop(): Promise<void> {
    if (this.phase !== 'listening') return
    const operation = this.operation
    this.state('transcribing')
    if (this.engine === 'system') {
      this.timeout = setTimeout(() => {
        if (!this.current(operation) || this.engine !== 'system') return
        this.complete(this.heard)
      }, 6000)
      try { await this.bridge.stop() }
      catch (reason) { if (this.current(operation) && this.engine === 'system') await this.error(operation, this.code(reason)) }
      return
    }
    let wav: ArrayBuffer | undefined
    try { wav = await this.bridge.stop() }
    catch (reason) { if (this.current(operation)) this.fail(voiceErrorText(this.code(reason))); return }
    if (!this.current(operation)) return
    if (!wav || wav.byteLength < 44 + 9600) { this.fail('没有听清，再说一次'); return }
    const target = this.target
    if (!target) { this.fail('无法连接到引擎'); return }
    try {
      const transcript = await this.client.transcribeSpeech(wav, target.providerId, target.language,
        (cancel: () => void): void => { if (this.current(operation)) this.cancelTranscription = cancel; else cancel() })
      if (!this.current(operation)) return
      if (!transcript.text.trim()) { this.fail('没有听清，再说一次'); return }
      this.apply(transcript.text, false); this.finish()
    } catch { if (this.current(operation)) this.fail('没能转写这段语音', true) }
  }

  private event(operation: number, event: VoiceEvent): void {
    if (!this.current(operation) || this.switching) return
    if (event.type === 'level') { this.level = Math.max(0, Math.min(1, event.level || 0)); this.onChange() }
    else if (event.type === 'partial' && this.engine === 'system') { this.heard = event.text || ''; this.apply(this.heard, true) }
    else if (event.type === 'final' && this.engine === 'system') this.complete(event.text || this.heard)
    else if (event.type === 'end' && this.engine === 'system') this.complete(this.heard)
    else if (event.type === 'error') void this.error(operation, event.code || 0)
    else if (event.type === 'limit' && this.phase === 'listening') void this.stop()
  }

  private async error(operation: number, code: number): Promise<void> {
    if (this.engine === 'system' && this.mode === 'auto' && !this.fallbackTried && ![6, 7].includes(code)) {
      await this.fallback(operation); return
    }
    const heard = this.heard
    if (heard.trim()) this.apply(heard, false)
    else this.restore()
    this.finish()
    if (![6, 7].includes(code) || !heard.trim()) this.onMessage({ text: voiceErrorText(code) })
  }

  private code(reason: Object): number {
    const error = reason as Error
    const match = /\b(100220\d{4}|680\d{4}|201|100)\b/.exec(error.message || '')
    return match ? Number(match[1]) : 100
  }
  private apply(text: string, provisional: boolean): void { if (this.base) this.writeDraft(voiceDraft(this.base, text, provisional)) }
  private restore(): void { if (this.base && this.sessionId === this.runSession) this.writeDraft(this.base) }
  private complete(text: string): void {
    if (text.trim()) { this.apply(text, false); this.finish(); this.onRecognized() }
    else { this.restore(); this.fail('没有听清，再说一次') }
  }
  private fail(text: string, change: boolean = false): void { this.finish(); this.onMessage({ text: text, change: change }) }
  private finish(): void {
    this.operation++; this.permissionPending = false; this.switching = false
    if (this.timeout !== undefined) clearTimeout(this.timeout)
    this.timeout = undefined; this.cancelTranscription?.(); this.cancelTranscription = undefined
    this.base = undefined; this.target = undefined; this.engine = undefined; this.level = 0
    void this.bridge.cancel().catch(() => {})
    this.state('idle')
  }
  async cancel(): Promise<void> {
    if (!this.active) return
    this.restore(); this.finish()
  }
  async openSettings(): Promise<void> { await this.bridge.openSettings() }
  dispose(): void { void this.cancel(); this.disposed = true; this.probeId++ }
}
