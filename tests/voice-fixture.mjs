export const common = {}
export class BusinessError extends Error {}
export const fixture = { permission: { authResults: [0] }, engines: [], captures: [], createEngine: undefined, releaseCapture: undefined }
globalThis.canIUse = () => true
export const abilityAccessCtrl = { createAtManager: () => ({
  requestPermissionsFromUser: async (_context, permissions) => { fixture.permissions = permissions; return fixture.permission },
  requestPermissionOnSetting: async () => { fixture.settings = true; return [0] }
}) }
export const speechRecognizer = {
  async createEngine(options) {
    if (fixture.createEngine) return fixture.createEngine(options)
    const engine = { options, frames: [], setListener(listener) { this.listener = listener },
      startListening(params) { this.params = params; queueMicrotask(() => this.listener.onStart(params.sessionId, 'started')) },
      writeAudio(id, data) { this.frames.push(new Uint8Array(data)) },
      finish(id) { this.finished = id }, cancel(id) { this.cancelled = id }, shutdown() { this.released = true } }
    fixture.engines.push(engine)
    return engine
  }
}
export const audio = {
  AudioSamplingRate: { SAMPLE_RATE_16000: 16000 }, AudioChannel: { CHANNEL_1: 1 },
  AudioSampleFormat: { SAMPLE_FORMAT_S16LE: 1 }, AudioEncodingType: { ENCODING_TYPE_RAW: 0 },
  SourceType: { SOURCE_TYPE_VOICE_RECOGNITION: 1 }, InterruptHint: { INTERRUPT_HINT_STOP: 3, INTERRUPT_HINT_PAUSE: 2 },
  async createAudioCapturer(options) {
    const capture = { options, callbacks: {}, on(type, callback) { this.callbacks[type] = callback },
      off(type) { delete this.callbacks[type] }, async start() { this.started = true },
      async stop() { this.stopped = true }, async release() {
        if (fixture.releaseCapture) await fixture.releaseCapture(this)
        this.released = true
      } }
    fixture.captures.push(capture)
    return capture
  }
}
