import { i18n } from '@kit.LocalizationKit'
import { DshClient } from '../dsh/DshClient'
import { array, object, string, WireObject } from '../dsh/DshWire'
import { DshGlyphs, ThemeColors, themeColors } from './DshTheme'
import { featureError, featureRequest, scheduleFailure, scheduleName, scheduleTiming } from './EngineFeatureData'

interface TimingChoice { id: string; label: string; hint: string }
const TIMINGS: TimingChoice[] = [
  { id: 'at', label: '指定时间', hint: 'YYYY-MM-DD HH:mm' },
  { id: 'every', label: '固定间隔', hint: '间隔秒数（至少 60）' },
  { id: 'daily', label: '每天', hint: 'HH:mm' },
  { id: 'weekly', label: '每周', hint: 'HH:mm' },
  { id: 'cron', label: 'Cron', hint: '分 时 日 月 周' },
  { id: 'after', label: '延迟运行', hint: '延迟秒数' },
  { id: 'rrule', label: 'RRULE', hint: '重复规则' }
]

@Component
export struct EngineScheduleEditor {
  @Prop colors: ThemeColors = themeColors()
  @Prop sessionId: string = ''
  client: DshClient = new DshClient()
  task: WireObject = {}
  onClose: () => void = () => {}
  onBackHandler?: (handler: (() => boolean) | undefined) => void
  onSaved: (task: WireObject) => void = () => {}
  @State private name: string = ''
  @State private instruction: string = ''
  @State private timing: string = 'at'
  @State private value: string = ''
  @State private zone: string = ''
  @State private weekdays: number[] = []
  @State private destination: string = 'new_once'
  @State private targetSession: string = ''
  @State private changeTiming: boolean = true
  @State private changeTarget: boolean = true
  @State private busy: boolean = false
  @State private error: string = ''
  private active: boolean = true
  private cleanDraft: string = ''
  private readonly labels: string[] = ['一', '二', '三', '四', '五', '六', '日']

  aboutToAppear(): void {
    this.active = true
    this.onBackHandler?.(() => this.back())
    this.name = this.task['id'] ? scheduleName(this.task) : ''
    this.instruction = string(this.task['prompt'])
    this.timing = string(this.task['kind']) || 'at'
    this.changeTiming = !this.task['id']
    this.changeTarget = !this.task['id']
    this.zone = string(this.task['timeZone']) || this.deviceZone()
    this.weekdays = array(this.task['weekdays']).filter((day: Object) => typeof day === 'number') as number[]
    const target = object(this.task['target'])
    this.destination = string(target['kind']) || (this.sessionId ? 'session' : 'new_once')
    this.targetSession = string(target['sessionId']) || this.sessionId
    this.value = this.initialValue()
    this.cleanDraft = this.draftSignature()
  }

  aboutToDisappear(): void {
    this.active = false
    this.onBackHandler?.(undefined)
  }

  private draftSignature(): string {
    return JSON.stringify(this.weekdays) + JSON.stringify([this.name, this.instruction, this.timing, this.value,
      this.zone, this.destination, this.targetSession]) + String(this.changeTiming) + String(this.changeTarget)
  }

  private back(): boolean {
    if (this.busy) return true
    if (this.cleanDraft === this.draftSignature()) return false
    this.getUIContext().showAlertDialog({
      title: '放弃更改？', message: '还没有保存自动化任务更改。',
      primaryButton: { value: '继续编辑', action: () => {} },
      secondaryButton: { value: '放弃', action: this.onClose }
    })
    return true
  }

  private deviceZone(): string {
    try { return i18n.getTimeZone().getID() || 'UTC' }
    catch { return 'UTC' }
  }

  private initialValue(): string {
    switch (this.timing) {
      case 'at': return string(this.task['scheduledAt'])
      case 'after': return typeof this.task['afterSeconds'] === 'number' ? `${this.task['afterSeconds']}` : ''
      case 'every': return typeof this.task['everySeconds'] === 'number' ? `${this.task['everySeconds']}` : ''
      case 'cron': return string(this.task['expression'])
      case 'rrule': return string(this.task['rrule'])
      default: return string(this.task['time'])
    }
  }

  private target(): WireObject {
    if (this.destination !== 'session') {
      const target: WireObject = { 'kind': this.destination }
      return target
    }
    if (!this.targetSession.trim()) throw new Error('请输入目标对话的 ID')
    const target: WireObject = { 'kind': 'session', 'sessionId': this.targetSession.trim() }
    return target
  }

  private async save(): Promise<void> {
    if (this.busy) return
    this.error = ''
    this.busy = true
    try {
      const id = string(this.task['id'])
      const title = this.name.trim()
      const prompt = this.instruction.trim()
      if (!title || !prompt || title.length > 120) throw new Error('名称和指令不能为空，名称最多 120 字')
      const timing = this.changeTiming ? scheduleTiming(this.timing, this.value, this.zone, this.weekdays) : undefined
      const patch: WireObject = { 'title': title, 'prompt': prompt }
      if (timing) patch['timing'] = timing
      if (this.changeTarget) patch['target'] = this.target()
      let saved: WireObject
      if (!id) {
        saved = object(await this.client.request('schedule/create', featureRequest(patch)))
      } else if (this.task['target']) {
        saved = await this.client.editSchedule(id, 'update', string(this.task['updatedAt']) || undefined, patch)
      } else {
        const expected: WireObject = {}
        Object.keys(this.task).forEach((key: string) => {
          if (!['sessionId', 'status', 'lastDelivery'].includes(key)) expected[key] = this.task[key]
        })
        const args: WireObject = { 'sessionId': string(this.task['sessionId']), 'id': id, 'expected': expected,
          'title': title, 'prompt': prompt }
        if (timing) args['change'] = timing
        const result = object(await this.client.request('schedule/update', featureRequest(args)))
        scheduleFailure(result)
        saved = object(result['record'])
        saved['sessionId'] = this.task['sessionId']
        saved['status'] = this.task['status']
        saved['lastDelivery'] = this.task['lastDelivery']
      }
      scheduleFailure(saved)
      if (!string(saved['id']) || (id && saved['id'] !== id)) throw new Error('主机未确认任务已保存')
      if (this.active) this.onSaved(saved)
    } catch (reason) {
      if (this.active) this.error = featureError(reason, '没能保存任务')
    } finally {
      if (this.active) this.busy = false
    }
  }

  @Builder
  private choice(label: () => string, selected: () => boolean, action: () => void) {
    Button(label()).height(36).fontSize(13)
      .backgroundColor(selected() ? this.colors.primaryContainer : this.colors.surface)
      .fontColor(selected() ? this.colors.onPrimaryContainer : this.colors.muted).onClick(action)
  }

  @Builder
  private timingForm() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(TIMINGS, (choice: TimingChoice) => {
        this.choice(() => choice.label, () => this.timing === choice.id, () => {
          if (this.timing !== choice.id) { this.timing = choice.id; this.value = '' }
        })
      }, (choice: TimingChoice) => choice.id)
    }.width('100%')
    TextInput({ text: this.value, placeholder: this.timingHint() })
      .fontColor(this.colors.text).backgroundColor(this.colors.surface).onChange((text: string) => { this.value = text })
    if (this.timing === 'weekly') {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.labels, (label: string, index: number) => {
          this.choice(() => label, () => this.weekdays.includes(index + 1), () => {
            const day = index + 1
            this.weekdays = this.weekdays.includes(day) ? this.weekdays.filter((value: number) => value !== day) :
              this.weekdays.concat([day])
          })
        }, (label: string) => label)
      }.width('100%')
    }
    if (['at', 'daily', 'weekly', 'cron'].includes(this.timing)) {
      TextInput({ text: this.zone, placeholder: '时区，例如 Asia/Shanghai' })
        .fontColor(this.colors.text).backgroundColor(this.colors.surface).onChange((text: string) => { this.zone = text })
    }
  }

  private timingHint(): string {
    return TIMINGS.find((choice: TimingChoice) => choice.id === this.timing)?.hint || '运行时间'
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Button({ type: ButtonType.Circle }) {
          Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.text)
        }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText('返回')
          .enabled(!this.busy).onClick(() => { if (!this.back()) this.onClose() })
        Text(this.task['id'] ? '编辑自动化任务' : '新建自动化任务')
          .fontColor(this.colors.text).fontSize(22).fontWeight(FontWeight.Medium).layoutWeight(1)
      }.width('100%')
      Scroll() {
        Column({ space: 12 }) {
          Text('名称').fontSize(15).fontColor(this.colors.text).width('100%')
          TextInput({ text: this.name, placeholder: '比如：每日站会提醒' }).maxLength(120)
            .fontColor(this.colors.text).backgroundColor(this.colors.surface).onChange((value: string) => { this.name = value })
          Text('指令').fontSize(15).fontColor(this.colors.text).width('100%')
          TextArea({ text: this.instruction, placeholder: '比如：整理昨天的提交，发我摘要' }).height(108)
            .fontColor(this.colors.text).backgroundColor(this.colors.surface)
            .onChange((value: string) => { this.instruction = value })
          Text('运行时间').fontSize(15).fontColor(this.colors.text).width('100%')
          if (this.task['id']) this.choice(() => this.changeTiming ? '保留原规则' : '修改运行规则', () => this.changeTiming, () => {
            this.changeTiming = !this.changeTiming
          })
          if (this.changeTiming) this.timingForm()
          if (!this.task['id'] || this.task['target']) {
            Text('在哪里运行').fontSize(15).fontColor(this.colors.text).width('100%')
            if (this.task['id']) this.choice(() => this.changeTarget ? '保留原目的地' : '更换目的地', () => this.changeTarget, () => {
              this.changeTarget = !this.changeTarget
            })
            if (this.changeTarget) {
              Flex({ wrap: FlexWrap.Wrap }) {
                this.choice(() => '现有对话', () => this.destination === 'session', () => { this.destination = 'session' })
                this.choice(() => '首次新建并沿用', () => this.destination === 'new_once', () => { this.destination = 'new_once' })
                this.choice(() => '每次新建', () => this.destination === 'new', () => { this.destination = 'new' })
              }.width('100%')
              if (this.destination === 'session') {
                TextInput({ text: this.targetSession, placeholder: '目标对话 ID' }).fontColor(this.colors.text)
                  .backgroundColor(this.colors.surface).onChange((text: string) => { this.targetSession = text })
              }
            }
          }
          if (this.error) Text(this.error).fontSize(14).fontColor(this.colors.danger).width('100%')
          Button(this.busy ? '正在保存…' : '保存').height(44).width('100%').fontColor(this.colors.onPrimary)
            .backgroundColor(this.colors.primary).enabled(!this.busy).onClick(() => { void this.save() })
        }.alignItems(HorizontalAlign.Start).width('100%')
      }.layoutWeight(1).width('100%').align(Alignment.TopStart)
    }.height('100%').width('100%').padding(16).backgroundColor(this.colors.background)
  }
}
