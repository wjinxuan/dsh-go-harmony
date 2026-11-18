import { nativePluginLocale } from './NativePluginLocale'
import { localizedSettingsText } from './SettingsLocale'
import { pasteboard } from '@kit.BasicServicesKit'
import { DshClient } from '../dsh/DshClient'
import { object, WireObject } from '../dsh/DshWire'
import { pluginCaps, pluginReplyEffects, pluginPlaces, PluginPlace, PluginEffect } from './NativePluginData'
import { NativePluginConnection } from './NativePluginConnection'
import { NativePluginsPanel } from './NativePluginsPanel'
import { ThemeColors, themeColors } from './DshTheme'

interface PlaceCache { locale: string; identity: number; time: number; promise: Promise<PluginPlace[]> }
const placeCache: Map<DshClient, PlaceCache> = new Map()
export async function loadPluginPlaces(client: DshClient, locale: string = 'zh-CN'): Promise<PluginPlace[]> {
  const identity = client.connectionIdentity(); const current = placeCache.get(client)
  if (current && current.identity === identity && current.locale === locale && Date.now() - current.time < 5000) return current.promise
  const promise = client.bridgeJson('GET', '/dsh-go/v1/contributions', pluginCaps(locale)).then((value: Object | null) => {
    if (identity !== client.connectionIdentity()) return []
    return pluginPlaces(value)
  })
  if (placeCache.size >= 8) placeCache.clear()
  placeCache.set(client, { locale: locale, identity: identity, time: Date.now(), promise: promise }); return promise
}

@Component
export struct NativePluginActions {
  @StorageProp('dshLanguage') @Watch('localeChanged') language: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.language) }
  @Prop colors: ThemeColors = themeColors()
  @Prop @Watch('load') surface: string = 'composer.actions'
  @Prop @Watch('load') scope: WireObject = {}
  @Prop draft: string = ''
  @Prop message: string = ''
  client: DshClient = new DshClient()
  onEffect?: (effect: PluginEffect) => void
  onOpenPanel?: (place: PluginPlace) => void
  @State private places: PluginPlace[] = []
  @State private busy: boolean = false
  @State private error: string = ''
  private deferredLocale: boolean = false
  private localeChanged(): void { if (this.busy) this.deferredLocale = true; else this.load() }
  private generation: number = 0
  private identity: number = 0
  private ownerKey: string = ''
  private stream?: NativePluginConnection
  aboutToAppear(): void { this.load() }
  private load(): void {
    const key = String(this.client.connectionIdentity()) + '|' + this.surface + '|' + JSON.stringify(this.scope) + '|' + nativePluginLocale(this.language)
    if (key === this.ownerKey) return
    this.ownerKey = key; this.stream?.close(); this.stream = undefined; this.places = []; this.busy = false; this.error = ''
    this.identity = this.client.connectionIdentity(); const generation = ++this.generation
    loadPluginPlaces(this.client, nativePluginLocale(this.language)).then((places: PluginPlace[]) => {
      if (this.current(generation)) this.places = places.filter((place: PluginPlace) => place.surface === this.surface).slice(0, 8)
    }).catch(() => {})
  }
  aboutToDisappear(): void { this.generation++; this.stream?.close() }
  private current(generation: number): boolean { return generation === this.generation && this.identity === this.client.connectionIdentity() }
  private async tap(place: PluginPlace, clipboardGranted: boolean = false): Promise<void> {
    if (this.busy) return
    const generation = this.generation; const gesture = Date.now(); this.busy = true; this.error = ''
    try {
      let effects: Object = place.effects; let arrived = gesture; let deferred = false
      if (!place.effects.length) {
        const context: WireObject = {}
        const composer = this.surface.startsWith('composer.')
        if (composer && place.wants.includes('draft')) context['draft'] = this.draft.slice(0, 16000)
        if (this.surface === 'message.actions' && place.wants.includes('message')) context['message'] = this.message.slice(0, 16000)
        if (composer && place.wants.includes('clipboard')) {
          if (!clipboardGranted) throw new Error(this.t('未能获得本次剪贴板访问授权。'))
          const value = await pasteboard.getSystemPasteboard().getData(); if (!this.current(generation)) return
          context['clipboard'] = value.getPrimaryText().slice(0, 16000)
        }
        const stream = this.stream || new NativePluginConnection(this.client, nativePluginLocale(this.language)); this.stream = stream
        const conn = await stream.open(); if (!this.current(generation)) return
        const request: WireObject = { 'v': 1, 'pkg': place.pkg, 'id': place.id, 'surface': this.surface,
          'scope': this.scope, 'context': context, 'locale': nativePluginLocale(this.language), 'stream': conn, 'userGesture': true }
        const acknowledgment = object(await this.client.bridgeJson('POST', '/dsh-go/v1/invoke', {}, request)); arrived = Date.now(); deferred = !!acknowledgment['pending']
        const result = await stream.result(acknowledgment)
        effects = result['effects'] || []
      }
      if (!this.current(generation)) return
      for (const effect of pluginReplyEffects(effects, gesture, arrived, deferred)) {
        if (effect.type === 'open' && effect.id.startsWith('panel:')) {
          const places = await loadPluginPlaces(this.client, nativePluginLocale(this.language))
          if (!this.current(generation) || Date.now() - gesture > 3000) return
          const panel = places.find((item: PluginPlace) => item.pkg === place.pkg && item.surface === 'panel' && item.id === effect.id.slice(6))
          if (panel) this.onOpenPanel?.(panel)
        } else this.onEffect?.(effect)
      }
    } catch (reason) { if (this.current(generation)) this.error = reason instanceof Error ? reason.message : '插件操作未能确认' }
    finally { if (this.current(generation)) { this.busy = false; if (this.deferredLocale) { this.deferredLocale = false; this.load() } } }
  }
  build() {
    Column({ space: 4 }) {
      if (this.places.length) Row({ space: 6 }) {
        ForEach(this.places, (place: PluginPlace) => {
          if (!place.effects.length && this.surface.startsWith('composer.') && place.wants.includes('clipboard')) Row({ space: 4 }) {
            Text(place.title).fontSize(12).fontColor(this.colors.primary)
            PasteButton({ icon: PasteIconStyle.LINES, text: PasteDescription.PASTE, buttonType: ButtonType.Capsule })
              .enabled(!this.busy).fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt)
              .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
                if (result === PasteButtonOnClickResult.SUCCESS) void this.tap(place, true)
                else this.error = this.t('未能获得本次剪贴板访问授权。')
              })
          }
          else Button(place.title).fontSize(12).fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt)
            .enabled(!this.busy).accessibilityText(place.plugin + '：' + place.title).onClick(() => { void this.tap(place) })
        }, (place: PluginPlace) => place.pkg + '|' + place.id)
      }.width('100%')
      if (this.busy) Button(this.t('取消操作')).fontSize(12).onClick(() => this.stream?.cancelPending())
      if (this.error) Text(this.t(this.error)).fontSize(12).fontColor(this.colors.danger)
    }.width('100%')
  }
}
