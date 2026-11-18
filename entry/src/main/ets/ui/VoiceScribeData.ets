import { array, object } from '../dsh/DshWire'
import type { WireObject } from '../dsh/DshWire'

export type VoiceScribeField = 'language' | 'polishPrompt'
export interface VoiceScribeProvider { url: string; model: string; hasKey: boolean }
export interface VoiceScribeSettings {
  language: string; polishPrompt: string; providers: VoiceScribeProvider[];
  hotwordsPath: string; hotwordsRules: number; hotwordsError: string
}
export interface VoiceScribeTransport {
  inventory: () => Promise<WireObject>;
  request: (body: WireObject) => Promise<WireObject>;
}

export function voiceScribeEntries(inventory: WireObject): WireObject[] {
  return array(inventory['entries']).map(object).filter((entry: WireObject) =>
    entry['moduleName'] === 'dsh-voice-scribe' && entry['enabled'] === true && entry['fiberPhase'] === 'active')
}

export function voiceScribeSettings(value: Object | null | undefined): VoiceScribeSettings {
  const row = object(value), hotwords = object(row['hotwords'])
  if (typeof row['language'] !== 'string' || typeof row['polishPrompt'] !== 'string' ||
    !Array.isArray(row['providers']) || typeof hotwords['path'] !== 'string' ||
    typeof hotwords['rules'] !== 'number' || !Number.isInteger(hotwords['rules']) || typeof hotwords['error'] !== 'string') {
    throw new Error('语音速记返回的设置格式不受支持')
  }
  const providers = array(row['providers']).map((value: Object): VoiceScribeProvider => {
    const provider = object(value)
    if (typeof provider['url'] !== 'string' || typeof provider['model'] !== 'string' || typeof provider['hasKey'] !== 'boolean') {
      throw new Error('语音速记返回的服务配置格式不受支持')
    }
    return { url: provider['url'] as string, model: provider['model'] as string, hasKey: provider['hasKey'] as boolean }
  })
  return { language: row['language'] as string, polishPrompt: row['polishPrompt'] as string, providers: providers,
    hotwordsPath: hotwords['path'] as string, hotwordsRules: hotwords['rules'] as number, hotwordsError: hotwords['error'] as string }
}

// A plugin restart invalidates editors even when the selected host remains the same.
export class VoiceScribeController {
  data?: VoiceScribeSettings
  error: string = ''
  loading: boolean = false
  saving: boolean = false
  generation: number = 0
  onChange: () => void = () => {}
  private readId: number = 0
  private disposed: boolean = false
  private entryId: string
  private transport: VoiceScribeTransport
  private isCurrent: () => boolean

  constructor(entryId: string, transport: VoiceScribeTransport, isCurrent: () => boolean) {
    this.entryId = entryId; this.transport = transport; this.isCurrent = isCurrent
  }

  accepts(generation: number): boolean { return !this.disposed && generation === this.generation && this.isCurrent() }

  invalidate(): void {
    this.generation++; this.readId++; this.data = undefined; this.loading = false; this.saving = false; this.error = ''
    this.onChange()
  }

  dispose(): void { this.disposed = true; this.invalidate(); this.onChange = () => {} }

  private async request(body: WireObject, current: () => boolean): Promise<WireObject> {
    if (!current()) throw new Error('主机连接已变更')
    const inventory = await this.transport.inventory()
    if (!current()) throw new Error('主机连接已变更')
    const entries = voiceScribeEntries(inventory)
    if (!this.entryId && entries.length === 1) this.entryId = entries[0]['entryId'] as string
    if (!this.entryId || !entries.some((entry: WireObject) => entry['entryId'] === this.entryId)) {
      throw new Error('语音速记插件尚未启用或未运行')
    }
    const response = await this.transport.request(body)
    if (!current()) throw new Error('主机连接已变更')
    return response
  }

  private async read(current: () => boolean): Promise<VoiceScribeSettings> {
    return voiceScribeSettings(await this.request({ 'action': 'get-settings' }, current))
  }

  async refresh(): Promise<void> {
    const generation = this.generation
    if (!this.accepts(generation) || this.saving) return
    const read = ++this.readId
    const current = (): boolean => this.accepts(generation) && read === this.readId
    this.loading = true; this.error = ''; this.onChange()
    try { const value = await this.read(current); if (current()) this.data = value }
    catch (reason) { if (current()) this.error = reason instanceof Error ? reason.message : '无法读取语音速记设置，请重试。' }
    finally { if (current()) { this.loading = false; this.onChange() } }
  }

  async save(generation: number, field: VoiceScribeField, value: string): Promise<boolean> {
    if (!this.accepts(generation) || this.saving || !this.data) return false
    if (field !== 'language' && field !== 'polishPrompt') return false
    const normalized = value.trim()
    if (field === 'polishPrompt' && normalized.length > 8000) { this.error = '润色提示词最多 8000 个字符'; this.onChange(); return false }
    if ((field === 'language' ? this.data.language : this.data.polishPrompt) === normalized) return true
    const current = (): boolean => this.accepts(generation)
    this.saving = true; this.readId++; this.loading = false; this.error = ''; this.onChange()
    try {
      const patch: WireObject = {}; patch[field] = normalized
      await this.request({ 'action': 'set-settings', 'patch': patch }, current)
      if (!current() || !this.data) return false
      if (field === 'language') this.data.language = normalized
      else this.data.polishPrompt = normalized
      try { const next = await this.read(current); if (!current()) return false; this.data = next }
      catch { if (!current()) return false; this.error = '设置已保存，但未能重新读取，请刷新确认。' }
      return true
    } catch { if (current()) this.error = '未能确认保存结果，请刷新后检查。'; return false }
    finally { if (current()) { this.saving = false; this.onChange() } }
  }
}
