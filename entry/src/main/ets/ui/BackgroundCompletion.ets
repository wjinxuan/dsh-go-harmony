import { backgroundTaskManager } from '@kit.BackgroundTasksKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { BusinessError } from '@kit.BasicServicesKit'

// Only bounded completion of work already started in the foreground. Never renew in the background.
// https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/transient-task/
export function backgroundCompletionLog(event: string, code: number = 0, grantedMs: number = 0): void {
  hilog.info(0x0000, 'DSHGoBackground', 'event=%{public}s code=%{public}d grantedMs=%{public}d', event, code, grantedMs)
}

export class BackgroundCompletion {
  private foreground: boolean = true
  private attempted: boolean = false
  private owner: number = 0
  private work: boolean = false
  private requestId: number | undefined = undefined
  private leaseEpoch: number = 0

  attach(): number {
    this.release('owner-changed')
    this.work = false
    return ++this.owner
  }

  update(owner: number, work: boolean): void {
    if (owner !== this.owner) return
    this.work = work
    if (!work) this.release('finished')
  }

  detach(owner: number): void {
    if (owner !== this.owner) return
    this.owner++
    this.work = false
    this.release('stopped')
  }

  // Called synchronously by UIAbility.onBackground, not an asynchronous UI state watcher.
  onBackground(): void {
    if (!this.foreground) return
    this.foreground = false
    if (!this.work || this.attempted || this.requestId !== undefined) return
    this.attempted = true
    const epoch = ++this.leaseEpoch
    let expired = false
    try {
      const info = backgroundTaskManager.requestSuspendDelay('完成已开始的对话并发送结果通知', () => {
        expired = true
        if (epoch === this.leaseEpoch) this.release('expired')
      })
      this.requestId = info.requestId
      if (expired || epoch !== this.leaseEpoch || this.foreground) { this.release('expired'); return }
      backgroundCompletionLog('granted', 0, info.actualDelayTime)
    } catch (error) { backgroundCompletionLog('request-failed', (error as BusinessError)?.code || 0) }
  }

  onForeground(): void {
    this.foreground = true
    this.attempted = false
    this.release('foreground')
  }

  destroy(): void {
    this.owner++
    this.work = false
    this.foreground = true
    this.attempted = false
    this.release('destroyed')
  }

  private release(reason: string): void {
    this.leaseEpoch++
    const requestId = this.requestId
    if (requestId === undefined) return
    try {
      backgroundTaskManager.cancelSuspendDelay(requestId)
      this.requestId = undefined
      backgroundCompletionLog(reason)
    } catch (error) {
      // Keep ownership when cancellation is unconfirmed; do not request another lease over it.
      backgroundCompletionLog('cancel-failed', (error as BusinessError)?.code || 0)
    }
  }
}

export const backgroundCompletion: BackgroundCompletion = new BackgroundCompletion()
