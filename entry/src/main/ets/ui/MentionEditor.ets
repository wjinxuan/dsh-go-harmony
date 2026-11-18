import { localizedSettingsText } from './SettingsLocale'
import { pasteboard } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { KeyCode } from '@kit.InputKit'
import { DshClient } from '../dsh/DshClient'
import { MentionPickerController, MentionRecent, MentionToken, mentionDisplayOffset, mentionRawOffset,
  mentionRecents } from './MentionData'
import { MentionChip } from './MentionChip'
import { ThemeColors, themeColors } from './DshTheme'

@Component
export struct MentionEditor {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }

  @Prop colors: ThemeColors = themeColors()
  @Prop fontSize: number = 16
  @Prop readOnly: boolean = false
  @Prop hardwareEnterSends: boolean = false
  onSend: () => void = () => {}
  onFocusChanged: (focused: boolean) => void = () => {}
  @Prop @Watch('updated') provisionalStart: number = -1
  @Prop @Watch('updated') provisionalEnd: number = -1
  @Prop @Watch('externalText') text: string = ''
  @Prop @Watch('contextChanged') sessionId: string = ''
  @Prop @Watch('contextChanged') connectionId: number = 0
  @Prop @Watch('updated') revision: number = 0
  controller: MentionPickerController = new MentionPickerController(new DshClient())
  onError: (message: string) => void = () => {}
  private editor: RichEditorController = new RichEditorController()
  private ready: boolean = false
  private painting: boolean = false
  private changing: boolean = false
  private composing: boolean = false
  private pasting: boolean = false
  private clipboardVersion: number = 0
  private renderedText: string = ''
  private renderedTokens: string = ''
  private renderedProvisional: string = ''
  private active: boolean = false
  private saves: Promise<void> = Promise.resolve()

  aboutToAppear(): void {
    this.active = true
    this.controller.setContext(this.sessionId)
    if (this.text !== this.controller.composer.text) this.controller.restore(this.text)
    this.controller.onRecents = (entries: MentionRecent[]): void => {
      this.saves = this.saves.catch(() => {}).then(async (): Promise<void> => {
        const store = await preferences.getPreferences(this.getUIContext().getHostContext() as common.Context, 'dsh-mentions')
        store.putSync('mention_recents_v1', JSON.stringify(entries))
        await store.flush()
      }).catch(() => {})
    }
    void this.loadRecents()
  }

  aboutToDisappear(): void {
    this.onFocusChanged(false)
    this.active = false; this.ready = false
    this.clipboardVersion++
    this.controller.reset()
    this.controller.onRecents = () => {}
  }

  private async loadRecents(): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.getUIContext().getHostContext() as common.Context, 'dsh-mentions')
      const loaded = mentionRecents(JSON.parse(store.getSync('mention_recents_v1', '[]') as string))
      if (!this.active) return
      this.controller.recents = mentionRecents(this.controller.recents.concat(loaded))
    } catch {}
  }

  private contextChanged(): void {
    this.clipboardVersion++
    this.changing = false; this.composing = false; this.pasting = false
    this.controller.setContext(this.sessionId)
    this.externalText()
  }

  private externalText(): void {
    if (this.text !== this.controller.composer.text) this.controller.restore(this.text)
    this.updated()
  }

  private tokenSignature(): string { return JSON.stringify(this.controller.composer.tokens) }

  private updated(): void {
    if (!this.ready || this.painting || this.changing) return
    const c = this.controller.composer
    if (this.renderedText !== c.text || this.renderedTokens !== this.tokenSignature() ||
      this.renderedProvisional !== `${this.provisionalStart}:${this.provisionalEnd}`) this.paint()
    else {
      const selection = this.editor.getSelection().selection
      const start = mentionDisplayOffset(c.start, c.tokens), end = mentionDisplayOffset(c.end, c.tokens)
      if (selection[0] !== start || selection[1] !== end) this.editor.setSelection(start, end)
    }
  }

  @Builder
  private chip(token: MentionToken) {
    MentionChip({ token: token, colors: this.colors, fontSize: this.fontSize })
  }

  private addText(text: string, start: number): void {
    const from = Math.max(start, this.provisionalStart), to = Math.min(start + text.length, this.provisionalEnd)
    if (from >= to) {
      this.editor.addTextSpan(text, { style: { fontSize: this.fontSize, fontColor: this.colors.text } })
      return
    }
    if (from > start) this.editor.addTextSpan(text.substring(0, from - start),
      { style: { fontSize: this.fontSize, fontColor: this.colors.text } })
    this.editor.addTextSpan(text.substring(from - start, to - start),
      { style: { fontSize: this.fontSize, fontColor: this.colors.muted } })
    if (to < start + text.length) this.editor.addTextSpan(text.substring(to - start),
      { style: { fontSize: this.fontSize, fontColor: this.colors.text } })
  }

  private paint(): void {
    this.painting = true
    const c = this.controller.composer
    try {
      this.editor.deleteSpans()
      let at = 0
      for (const token of c.tokens) {
        if (at < token.start) this.addText(c.text.substring(at, token.start), at)
        this.editor.addBuilderSpan(() => { this.chip(token) })
        at = token.end
      }
      if (at < c.text.length) this.addText(c.text.substring(at), at)
      this.editor.setTypingStyle({ fontSize: this.fontSize, fontColor: this.colors.text })
      this.editor.setSelection(mentionDisplayOffset(c.start, c.tokens), mentionDisplayOffset(c.end, c.tokens))
      this.renderedText = c.text; this.renderedTokens = this.tokenSignature()
      this.renderedProvisional = `${this.provisionalStart}:${this.provisionalEnd}`
    } finally { this.painting = false }
  }

  private edited(before: TextRange, after: TextRange): void {
    if (this.painting) return
    if (before.start === undefined || before.end === undefined || after.start === undefined || after.end === undefined) {
      this.changing = false; this.paint(); return
    }
    const c = this.controller.composer
    const start = mentionRawOffset(before.start, c.tokens), end = mentionRawOffset(before.end, c.tokens)
    let inserted = ''
    let unsupported = false
    if (after.end > after.start) {
      for (const span of this.editor.getSpans({ start: after.start, end: after.end })) {
        const text = span as RichEditorTextSpanResult
        if (typeof text.value === 'string') {
          inserted += text.value.substring(text.offsetInSpan[0], text.offsetInSpan[1])
        } else unsupported = true
      }
    }
    c.replace(start, end, inserted, !this.composing)
    this.changing = false
    this.renderedText = c.text; this.renderedTokens = this.tokenSignature()
    // Native paste supplies its permitted clipboard text. Rebuild without images or foreign styles so
    // every native character still maps to the wire text (or one of our atomic reference spans).
    const normalize = this.pasting && !this.composing || unsupported || inserted.length !== after.end - after.start
    this.pasting = false
    if (normalize || !this.composing && inserted.length > 1 && c.tokens.some((t: MentionToken) => t.start >= start && t.end <= start + inserted.length)) this.paint()
    this.controller.changed()
  }

  private willChange(change: RichEditorChangeValue): boolean {
    if (this.painting) return true
    if (this.readOnly) return false
    // An image-only paste must not erase the currently selected text.
    if ((change.replacedImageSpans.length || change.replacedSymbolSpans.length) && !change.replacedSpans.length) {
      this.pasting = false
      return false
    }
    this.changing = true
    this.composing = change.replacedSpans.some((span: RichEditorTextSpanResult) => !!span.previewText)
    return true
  }

  private selected(range: RichEditorRange): void {
    if (this.painting || this.changing || range.start === undefined || range.end === undefined) return
    const c = this.controller.composer
    this.controller.select(mentionRawOffset(range.start, c.tokens), mentionRawOffset(range.end, c.tokens))
  }

  private async copy(cut: boolean): Promise<void> {
    if (cut && this.readOnly) return
    const c = this.controller.composer, text = c.text, start = c.start, end = c.end
    if (start === end) return
    const version = ++this.clipboardVersion, revision = c.revision
    const session = this.sessionId, connection = this.connectionId
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text.substring(start, end)))
      if (cut && this.active && !this.readOnly && version === this.clipboardVersion && revision === c.revision &&
        session === this.sessionId && connection === this.connectionId && text === c.text && start === c.start && end === c.end) {
        c.replace(start, end, '', false); this.paint(); this.controller.changed()
      }
    } catch { if (this.active && version === this.clipboardVersion && session === this.sessionId && connection === this.connectionId) this.onError(this.t("没能复制引用，请重试")) }
  }

  private handleKey(event: KeyEvent): void {
    if (this.readOnly || event.type !== KeyType.Down) return
    const name = event.keyCode === KeyCode.KEYCODE_DPAD_UP ? 'ArrowUp' : event.keyCode === KeyCode.KEYCODE_DPAD_DOWN ? 'ArrowDown' :
      event.keyCode === KeyCode.KEYCODE_ESCAPE ? 'Escape' : event.keyCode === KeyCode.KEYCODE_TAB ? 'Tab' :
        event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER ? 'Enter' : ''
    if (name && this.controller.key(name)) { event.stopPropagation(); return }
    if (name === 'Enter' && this.hardwareEnterSends && !this.composing && event.keySource === KeySource.Keyboard &&
      !event.getModifierKeyState?.(['Shift']) && !event.getModifierKeyState?.(['Ctrl']) && !event.getModifierKeyState?.(['Alt'])) {
      event.stopPropagation(); this.onSend()
    }
  }

  build() {
    RichEditor({ controller: this.editor })
      .placeholder(this.t("发消息…"), { font: { size: this.fontSize }, fontColor: this.colors.hint })
      .backgroundColor(Color.Transparent).height(64).width('100%').padding({ left: 14, right: 14, top: 10, bottom: 4 })
      .accessibilityText(this.t("消息输入框")).draggable(false)
      .enableKeyboardOnFocus(!this.readOnly).focusable(!this.readOnly)
      .onReady(() => { this.ready = true; this.paint() })
      .onFocus(() => this.onFocusChanged(true)).onBlur(() => this.onFocusChanged(false))
      .onWillChange((change: RichEditorChangeValue): boolean => this.willChange(change))
      .onDidChange((before: TextRange, after: TextRange) => this.edited(before, after))
      .onSelectionChange((range: RichEditorRange) => this.selected(range))
      .onCopy((event: CopyEvent) => { event.preventDefault?.(); void this.copy(false) })
      .onCut((event: CutEvent) => { event.preventDefault?.(); void this.copy(true) })
      .onPaste((event?: PasteEvent) => {
        if (this.readOnly) event?.preventDefault?.()
        else this.pasting = true
      })
      .onKeyEvent((event: KeyEvent) => this.handleKey(event))
  }
}
