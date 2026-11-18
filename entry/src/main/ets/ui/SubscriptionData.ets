import { array, object, string } from '../dsh/DshWire'
import type { WireObject } from '../dsh/DshWire'

export interface SubscriptionStatus { id: string; title: string; signedIn: boolean; account: string }
export interface SubscriptionStep { phase: string; url: string; userCode: string; message: string; placeholder: string; error: string }
export type SubscriptionRequest = (method: string, args: WireObject) => Promise<Object | null | undefined>

export function subscriptionStatuses(value: Object | null | undefined): SubscriptionStatus[] {
  const result: SubscriptionStatus[] = []
  for (const item of array(object(value)['providers'])) {
    const row = object(item), id = string(row['id'])
    if (id !== 'openai-codex' && id !== 'anthropic') continue
    if (result.some((status: SubscriptionStatus) => status.id === id)) continue
    result.push({ id: id, title: id === 'openai-codex' ? 'ChatGPT' : 'Claude',
      signedIn: row['signedIn'] === true, account: string(row['account']) })
  }
  return result
}

export function subscriptionBrowserUrl(value: string): string {
  return value.length <= 16384 && /^https:\/\/[^\s\/@?#\\]+(?:[\/?#][^\s\\]*)?$/.test(value) &&
    !/[\x00-\x1f\x7f]/.test(value) ? value : ''
}

export function subscriptionStep(value: Object | null | undefined): SubscriptionStep {
  const row = object(value), phase = string(row['phase'])
  const valid = ['starting', 'open', 'device', 'prompt', 'done', 'failed', 'cancelled'].includes(phase)
  const address = string(row['url']), url = subscriptionBrowserUrl(address)
  const invalidUrl = (phase === 'open' || phase === 'device') && !url
  return { phase: valid && !invalidUrl ? phase : 'failed', url: url, userCode: string(row['userCode']),
    message: string(row['message']), placeholder: string(row['placeholder']),
    error: invalidUrl ? '主机返回的授权链接无效' : !valid ? '主机返回的登录状态无效' : string(row['error']) }
}

export function subscriptionFinished(phase: string): boolean { return ['done', 'failed', 'cancelled'].includes(phase) }

export class SubscriptionLogin {
  step: SubscriptionStep = subscriptionStep({ 'phase': 'starting' } as WireObject)
  answering: boolean = false
  onChange: () => void = () => {}
  private request: SubscriptionRequest
  private provider: string
  private current: () => boolean
  private wait: () => Promise<void>
  private generation: number = 0
  private attemptId: string = ''
  private closed: boolean = false
  private pollEpoch: number = 0

  constructor(request: SubscriptionRequest, provider: string, current: () => boolean,
    wait: () => Promise<void> = () => new Promise<void>((resolve) => { setTimeout(resolve, 1000) })) {
    this.request = request; this.provider = provider; this.current = current; this.wait = wait
  }

  private publish(value: SubscriptionStep): void { if (!this.closed) { this.step = value; this.onChange() } }
  private accepts(generation: number): boolean { return !this.closed && generation === this.generation && this.current() }

  async start(): Promise<void> {
    if (this.closed || !this.current() || !['openai-codex', 'anthropic'].includes(this.provider)) return
    const generation = ++this.generation, previous = this.attemptId
    this.attemptId = ''; this.answering = false
    if (previous) await this.request('appAuth/cancel', { 'attemptId': previous }).catch(() => {})
    if (!this.accepts(generation)) return
    this.publish(subscriptionStep({ 'phase': 'starting' } as WireObject))
    try {
      const result = object(await this.request('appAuth/begin', { 'provider': this.provider })), id = string(result['attemptId'])
      if (!id || id.length > 256) throw new Error('主机未返回有效登录编号')
      if (!this.accepts(generation)) {
        if (this.current()) await this.request('appAuth/cancel', { 'attemptId': id }).catch(() => {})
        return
      }
      this.attemptId = id
      let misses = 0
      while (this.accepts(generation) && this.attemptId === id && !subscriptionFinished(this.step.phase)) {
        if (!this.answering) {
          const epoch = this.pollEpoch
          try {
            const next = subscriptionStep(await this.request('appAuth/poll', { 'attemptId': id }))
            if (!this.accepts(generation) || this.attemptId !== id) return
            if (epoch === this.pollEpoch) {
              misses = 0; this.publish(next)
              if (subscriptionFinished(next.phase)) { if (next.phase !== 'failed') this.attemptId = ''; return }
            }
          } catch {
            if (!this.accepts(generation)) return
            if (epoch === this.pollEpoch && ++misses >= 3) throw new Error('登录状态连续读取失败，请重试。')
          }
        }
        await this.wait()
      }
    } catch (reason) {
      if (this.accepts(generation)) this.publish(subscriptionStep({ 'phase': 'failed',
        'error': reason instanceof Error ? reason.message : '登录未完成，请重试。' } as WireObject))
    }
  }

  async answer(value: string): Promise<boolean> {
    const generation = this.generation, id = this.attemptId, answer = value.trim()
    if (!this.accepts(generation) || !id || this.answering || this.step.phase !== 'prompt' || !answer || answer.length > 8192) return false
    this.pollEpoch++; this.answering = true; this.onChange()
    try {
      await this.request('appAuth/answer', { 'attemptId': id, 'value': answer })
      if (!this.accepts(generation) || this.attemptId !== id) return false
      return true
    } catch {
      if (this.accepts(generation)) this.publish(subscriptionStep({ 'phase': 'failed', 'error': '授权内容未能提交，请重试登录。' } as WireObject))
      return false
    } finally { if (this.accepts(generation)) { this.answering = false; this.onChange() } }
  }

  async close(): Promise<void> {
    if (this.closed) return
    this.closed = true; this.generation++; this.onChange = () => {}
    const id = this.attemptId; this.attemptId = ''
    if (id && this.current()) await this.request('appAuth/cancel', { 'attemptId': id })
  }
}
