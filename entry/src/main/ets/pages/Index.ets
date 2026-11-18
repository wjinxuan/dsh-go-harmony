import { readBundledBot, setBundledBot } from '../local/BundledBot'
import { PhoneTaskHost } from '../ui/PhoneTaskHost'
import { PetsPanel } from '../pets/PetsPanel'
import { PetActivityFeed } from '../pets/PetActivityFeed'
import { PetPerch } from '../pets/PetPerch'
import { PetSessionSnapshot } from '../pets/PetData'
import { CompanionPanel } from '../companion/CompanionPanel'
import { companionBindingIds } from '../companion/CompanionStore'
import { nativePluginLocale } from '../ui/NativePluginLocale'
import { ProfileSharePanel } from '../ui/ProfileSharePanel'
import { DSBotPanel } from '../ui/DSBotPanel'
import { DSBotHub } from '../ui/DSBotData'
import { createDSBotHub } from '../ui/DSBotNative'
import { NativePluginStrip } from '../ui/NativePluginStrip'
import { PerformancePreferences, PerformanceState, performanceState } from '../ui/PerformanceData'
import { PerformanceMonitor } from '../ui/PerformanceNative'
import { PerformanceSettings } from '../ui/settings/PerformanceSettings'
import { SystemAccessPanel } from '../ui/SystemAccessPanel'
import { PhoneControlPanel } from '../ui/PhoneControlPanel'
import { ForumPanel } from '../ui/ForumPanel'
import { forumAuthCallback } from '../forum/ForumCallback'
import { modelUiReplyState, ModelUiState } from '../ui/NativePluginReplyData'
import { foldedTurns } from '../ui/TurnFoldData'
import { shareLaunch } from '../ui/ShareLaunchData'
import { ConversationSharePanel } from '../ui/ConversationSharePanel'
import { ConversationImportPanel } from '../ui/ConversationImportPanel'
import { AdvancedPreferences, advancedPreferences } from '../ui/AdvancedPreferencesData'
import { WallpaperBackdrop } from '../ui/WallpaperBackdrop'
import { localizedSettingsText, localizedSettingsFormat } from '../ui/SettingsLocale'
import { ChatNotifications } from '../ui/ChatNotifications'
import { ChatNotification, NotificationPreferences } from '../ui/NotificationData'
import { UsageStats } from '../ui/UsageStatsData'
import { createUsageStats } from '../ui/UsageStatsNative'
import { loadWorkspaceView, changeWorkspaceView } from '../ui/WorkspaceViewPreferences'
import { StartupPanel } from '../ui/StartupPanel'
import { loadStartupSettings, rememberStartupHost, startupTarget } from '../ui/StartupPreferences'
import { NetworkDiagnosticsPanel } from '../ui/NetworkDiagnosticsPanel'
import { WebModePanel } from '../ui/WebModePanel'
import { NativePluginView } from '../ui/NativePluginView'
import { NativePluginActions, loadPluginPlaces } from '../ui/NativePluginActions'
import { NativePluginsPanel } from '../ui/NativePluginsPanel'
import { PluginEffect, PluginPlace } from '../ui/NativePluginData'
import { common } from '@kit.AbilityKit'
import { KeyboardAvoidMode, UIContext } from '@kit.ArkUI'
import { pasteboard } from '@kit.BasicServicesKit'
import { util } from '@kit.ArkTS'
import { ThemeColors, themeColors, DshGlyphs, registerDshFonts } from '../ui/DshTheme'
import { MessageBody } from '../ui/MessageBody'
import { AnsiText } from '../ui/AnsiText'
import { CotReasoning } from '../ui/CotReasoning'
import { CotTranslationStore } from '../ui/CotTranslationData'
import { MediaParams, MediaMeta, MediaItem, formatMediaMessage, mediaMeta, mediaParamsFromMeta, regenerateMediaMessage, validateMediaReferences } from '../dsh/MediaData'
import { loadMediaCatalog } from '../dsh/MediaApi'
import { sessionArtifacts, SessionArtifact } from '../ui/SessionArtifacts'
import { ArtifactCard } from '../ui/ArtifactCard'
import { ToolDiffPreview } from '../ui/ToolDiffPreview'
import { QuickPanel } from '../ui/QuickPanel'
import { QuickPanelPreferences, quickPanelPreferences, appPageLink, launcherEntry } from '../ui/ShellNavigationData'
import { loadQuickPanelPreferences } from '../ui/QuickPanelPreferences'
import { NewChatModes, resolveNewChatModes, applyNewChatModes } from '../ui/NewChatOptionsData'
import { loadNewChatSetup, saveNewChatSetup } from '../ui/NewChatSetupPreferences'
import { MediaGeneratePanel } from '../ui/MediaGeneratePanel'
import { MediaResultCard } from '../ui/MediaResultCard'
import { MediaViewer } from '../ui/MediaViewer'
import { MentionPickerController } from '../ui/MentionData'
import { MentionEditor } from '../ui/MentionEditor'
import { MentionPickerPanel } from '../ui/MentionPickerPanel'
import { MentionMessage } from '../ui/MentionMessage'
import { VoiceDraft, VoiceInputController, VoiceMessage } from '../ui/VoiceData'
import { HarmonyVoiceBridge } from '../ui/VoiceInput'
import { SpeechMode } from '../dsh/SpeechData'
import { loadSpeechMode, saveSpeechMode } from '../ui/SpeechPreferences'
import { SessionsPanel } from '../ui/SessionsPanel'
import { WorkspacesPanel } from '../ui/WorkspacesPanel'
import { FilesPanel } from '../ui/FilesPanel'
import { ModelPanel } from '../ui/ModelPanel'
import { SettingsPanel } from '../ui/SettingsPanel'
import { EngineFeaturesPanel } from '../ui/EngineFeaturesPanel'
import { ChatRow, ChatTimeline } from '../ui/ChatTimeline'
import { AppPreferenceValues, loadAppPreferences, loadAdvancedPreferences, saveAdvancedPreferences, saveAppPreferences, loadOnboardingComplete, saveOnboardingComplete } from '../ui/AppPreferences'
import { DshAttachmentRef, DshCommand, DshCommandNotice, DshModelSelection, DshTool, DshTurnNotice, DshQueuedPrompt, DshQueueMoveResult, DshQuestionRequest, DshTodo, DshGoal, WireObject, messageAttachments, turnTraces, string, modelSelection, normalizeProviderKey, object } from '../dsh/DshWire'
import { ChatActivityPanel } from '../ui/ChatActivityPanel'
import { QuestionCard } from '../ui/QuestionCard'
import { QuestionDrafts } from '../ui/QuestionDrafts'
import { ComposerDrafts } from '../ui/ComposerDrafts'
import { forkBeforePrompt, regenerablePrompt } from '../ui/MessageRegeneration'
import { resendImages } from '../ui/RegenerationAttachments'
import { SlashCommand, filterSlash, resolveSlash, slashCommands, slashInput } from '../ui/SlashCommands'
import { todoSummary, goalHeadline } from '../ui/ChatProgress'
import { SessionOptionsPanel } from '../ui/SessionOptionsPanel'
import { SessionDetailPanel } from '../ui/SessionDetailPanel'
import { SessionExportPanel } from '../ui/SessionExportPanel'
import { OnboardingPanel } from '../ui/OnboardingPanel'
import { hasLocalApiKey, loadLocalApiKey, saveLocalApiKey, removeLocalApiKey } from '../local/LocalKeyStore'
import { LocalEngine } from '../local/LocalEngine'
import { RemoteHostConnection, listRemoteHosts, getRemoteHostConnection } from '../remote/RemoteHosts'
import { RemoteHostsPanel } from '../ui/RemoteHostsPanel'
import { SshPanel } from '../ui/SshPanel'
import { RelayPanel } from '../ui/RelayPanel'
import { TerminalPanel } from '../ui/TerminalPanel'
import { TransportControl, TransportEndpoint } from '../remote/TransportEndpoint'
import { DraftAttachment, MAX_ATTACHMENTS, MAX_ATTACHMENT_TOTAL, deleteAttachments, pickAttachments } from '../ui/AttachmentPicker'
import { AttachmentGallery, AttachmentThumbnail } from '../ui/AttachmentGallery'
import { GalleryImage } from '../ui/AttachmentGalleryData'
import { DshApproval, DshChatUpdate, DshClient, DshMessage, DshSession, DshSessionRecord, DshWorkspace } from '../dsh/DshClient'

interface QueuedAttachmentDraft {
  sessionId: string
  requestId: string
  files: DraftAttachment[]
}

@Entry
@Component
struct Index {
  @StorageProp('dshLanguage') @Watch('languageChanged') private localeLanguage: string = 'system'
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage) }

  @State @Watch('voicePageChanged') private page: string = 'loading'
  private keyboardContext?: UIContext
  private previousKeyboardAvoidMode?: KeyboardAvoidMode
  @StorageLink('dshLaunchRequest') @Watch('pendingLaunchChanged') private launchRequest: string = ''
  @StorageLink('dshForeground') @Watch('voiceForegroundChanged') private foreground: boolean = true
  @State private speechMode: SpeechMode = 'auto'
  @State @Watch('performanceActivity') private voicePhase: string = 'idle'
  @State private voiceAvailable: boolean = false
  @State private voiceLevel: number = 0
  @State private voiceLevels: number[] = [0, 0, 0, 0, 0]
  @State private voiceProvisionalStart: number = -1
  @State private voiceProvisionalEnd: number = -1
  @State private voiceNotice: string = ''
  @State private voiceSettingsAction: boolean = false
  @State private voiceModeAction: boolean = false
  private voice?: VoiceInputController
  private voiceBridge?: HarmonyVoiceBridge
  private speechModeReady: Promise<void> = Promise.resolve()
  private speechModeLoadFailed: boolean = false
  @State private newPreset: string = ''
  @State private newPermission: string = ''
  private owedNewChatModes: Map<string, NewChatModes> = new Map()
  @State private mediaParams: MediaParams | undefined = undefined
  @State private mediaItems: MediaItem[] = []
  @State private mediaIndex: number = 0
  @State @Watch('pendingLaunchChanged') private maintenanceBusy: boolean = false
  @State private artifactPath: string = ''
  @State @Watch('refreshQuickPlugins') private quickOpen: boolean = false
  @State private quickPreferences: QuickPanelPreferences = quickPanelPreferences()
  @State private expandedToolGroups: string[] = []
  @State private drawer: boolean = false
  @State private viewportWidth: number = 400
  @State @Watch('updateColors') private accentId: string = 'mist'
  @State @Watch('updateColors') private themeMode: string = 'system'
  @State private fontSize: number = 16
  @StorageLink('dshSystemDark') @Watch('updateColors') private systemDark: boolean = false
  @State private settingsPage: string = 'home'
  @State private settingsRequestVersion: number = 0
  private settingsOrigin: string = 'chat'
  private settingsScope: string = ''
  @State private featureKind: string = 'plugins'
  @State private tools: DshTool[] = []
  private cotTranslations: CotTranslationStore = new CotTranslationStore()
  @State private expandedReasoning: string[] = []
  @State private expandedTools: string[] = []
  @State private modelName: string = this.t("选择模型")
  @State private reasoningEffort: string = ''
  @State private currentModel: DshModelSelection | undefined = undefined
  @State private turnNotices: DshTurnNotice[] = []
  @State private commandNotices: DshCommandNotice[] = []
  @State private hostCommands: DshCommand[] = []
  @State private sessionSkills: WireObject[] = []
  @State private compacting: boolean = false
  private catalogVersion: number = 0
  private commandCatalog?: Promise<void>
  private exportOrigin: string = 'features'
  @State private sessionError: string = ''
  private pendingSessionModel?: DshModelSelection
  private pendingModelSessionId: string = ''
  private recoveryRequestIds: Map<string, string> = new Map()
  @State private submittedRecoveries: string[] = []
  @State private queuedPrompts: DshQueuedPrompt[] = []
  @State private questions: DshQuestionRequest[] = []
  @State private todos: DshTodo[] = []
  @State private goal: DshGoal | undefined = undefined
  @State private todosExpanded: boolean = false
  @State private detailTab: string = 'trajectory'
  private filesOrigin: string = 'chat'
  private featureOrigin: string = 'features'
  @State private rememberKey: boolean = false
  @State private hasSavedKey: boolean = false
  @State private engineReady: boolean = false
  @State private credentialNotice: string = ''
  private questionDrafts: QuestionDrafts = new QuestionDrafts()
  private composerDrafts: ComposerDrafts = new ComposerDrafts()
  private sessionsBack?: () => boolean
  private workspaceBack?: () => boolean
  private settingsBack?: () => boolean
  private featuresBack?: () => boolean
  private filesBack?: () => boolean
  private modelsBack?: () => boolean
  private detailBack?: () => boolean
  private onboardingBack?: () => boolean
  private exportBack?: () => boolean
  private remoteBack?: () => boolean
  private sshBack?: () => boolean
  private remoteOrigin: string = 'connect'
  private transport?: TransportEndpoint
  @State private transportKind: string = ''
  @State private relayRoute: string = ''
  @State private remoteHostId: string = ''
  private remoteHostScope: string = ''
  private localConfigured: boolean = false
  private switchingHost: boolean = false
  private stoppingLocalEngine: boolean = false

  @State @Watch('advancedChanged') private advanced: AdvancedPreferences = advancedPreferences()
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage) }
  private notifications?: ChatNotifications
  private usage?: UsageStats
  private languageChanged(): void { void this.refreshQuickPlugins() }
  private recordUsage(kind: string): void { void this.usage?.count(kind).catch(() => {}) }
  @State private performance: PerformanceState = performanceState()
  private performanceMonitor?: PerformanceMonitor
  private phoneBack?: () => boolean
  private dsBotBack?: () => boolean
  private dsBot?: DSBotHub
  @State private dsBotOwnedSessions: string[] = []
  @State private dsBotInitialId: string = ''
  @State private dsBotInitialRoom: boolean = false
  @State private notificationBanner: ChatNotification | undefined = undefined
  @State private restoreHostId: string = ''
  @State private sharedPlugin: string = ''
  @State private shareSource: WireObject = {}
  @State private shareOnly: string[] = []
  @State private shareInput: string = ''
  @State private shareFile: string = ''
  @State private shareTab: string = 'import'
  private shareBack?: () => boolean
  private shareOrigin: string = 'chat'
  @State private bundledBotAvailable: boolean = false
  @State private bundledBotEnabled: boolean = false
  @State private bundledBotRestart: boolean = false
  private bundledBotControl?: TransportControl
  @State private pluginSection: string = 'panels'
  private nativePluginsBack?: () => boolean
  private companionBack?: () => boolean
  @State private composerFocused: boolean = false
  @State private chatScrolling: boolean = false
  @State private searchRequest: number = 0
  @StorageProp('dshCompanionBindings') private companionBindings: string = '{}'
  private petFeed?: PetActivityFeed
  @State private petSessions: PetSessionSnapshot[] = []
  private hiddenSessionIds(): string[] {
    let companion = ''; try { companion = string(object(JSON.parse(this.companionBindings))[this.hostScope()]) } catch {}
    return companion ? this.dsBotOwnedSessions.concat([companion]) : this.dsBotOwnedSessions
  }
  private async loadBundledBot(): Promise<void> {
    this.bundledBotAvailable = false
    const control = this.bundledBotControl
    if (!this.connected || this.mode !== 'local' || !control) return
    const version = this.connectionVersion
    try { const value = await readBundledBot(control); if (this.connected && this.mode === 'local' && version === this.connectionVersion && control === this.bundledBotControl) { this.bundledBotAvailable = true; this.bundledBotEnabled = value.enabled; this.bundledBotRestart = value.restartRequired } } catch {}
  }
  private async changeBundledBot(enabled: boolean): Promise<void> {
    const control = this.bundledBotControl, version = this.connectionVersion
    if (!this.connected || this.mode !== 'local' || !control) throw new Error(this.t('请先连接本机引擎'))
    await setBundledBot(control, enabled)
    if (this.connected && this.mode === 'local' && version === this.connectionVersion && control === this.bundledBotControl) await this.loadBundledBot()
  }
  @State private pluginPlace: PluginPlace | undefined = undefined
  @State private quickPlugins: PluginPlace[] = []
  @State private forumRedirect: string = ''
  private forumBack?: () => boolean
  @State private visualReplyPending: string[] = []
  private visualReplyRequests: Map<string, string> = new Map()
  private visualReplyAfterSeq: number = -1
  private settleVisualReply(): void {
    if (this.visualReplyPending.length && this.messages.some((m: DshMessage) => m.role === 'user' && (m.seq ?? -1) > this.visualReplyAfterSeq && m.text === this.visualReplyPending[0])) this.visualReplyPending = []
  }
  private async sendVisualReply(message: DshMessage, text: string): Promise<boolean> {
    if (!text.startsWith('[dsh-ui reply]') || text.length > 16000 || !this.connected || !this.sessionId || this.busy || this.sending || this.loadingChat || this.voice?.active ||
      this.visualState(message.id).state !== 'live') return false
    const session = this.sessionId, chat = this.chatVersion, connection = this.connectionVersion
    const current = (): boolean => session === this.sessionId && chat === this.chatVersion && connection === this.connectionVersion
    const key = `${connection}/${session}/${message.id}/${text}`
    let request = this.visualReplyRequests.get(key)
    if (!request) { request = util.generateRandomUUID(); this.visualReplyRequests.set(key, request) }
    this.sending = true
    try {
      if (!await this.applyPendingModes(session, connection)) return false
      if (!current() || !await this.applyPendingModel(session, connection)) return false
      await this.client.prompt(session, text, request)
      this.recordUsage('turns')
      if (current()) { this.visualReplyAfterSeq = message.seq ?? -1; this.visualReplyPending = [text]; this.settleVisualReply() }
      return current()
    } catch { if (current()) this.errorText = this.t("未能确认选项回复，请重试。"); return false }
    finally { if (current()) this.sending = false }
  }
  private visualState(id: string): ModelUiState { return modelUiReplyState(this.messages, id, this.running, this.visualReplyPending) }
  private async refreshQuickPlugins(): Promise<void> {
    if (!this.connected) return
    const connection = this.connectionVersion
    try { const places = await loadPluginPlaces(this.client, nativePluginLocale(this.localeLanguage)); if (connection === this.connectionVersion) this.quickPlugins = places.filter((p: PluginPlace) => p.surface === 'panel') }
    catch { if (connection === this.connectionVersion) this.quickPlugins = [] }
  }
  private quickPluginItems(): WireObject[] {
    return this.quickPlugins.map((p: PluginPlace): WireObject => ({ 'id': p.pkg + '|' + p.id, 'title': p.title }))
  }
  private openQuickPlugin(id: string): void {
    const place = this.quickPlugins.find((p: PluginPlace) => p.pkg + '|' + p.id === id)
    if (place) { this.pluginSection = 'panels'; this.pluginPlace = place; this.quickOpen = false; this.page = 'nativePlugins' }
  }
  private async setWidePanel(open: boolean): Promise<void> {
    const value = advancedPreferences(this.advanced)
    value.panelOpen = open
    this.advanced = value
    await saveAdvancedPreferences(this.getUIContext().getHostContext() as common.UIAbilityContext, this.advanced).catch(() => {})
  }
  private async selectWorkspace(id: string): Promise<void> {
    this.workspaceId = id
    try { await changeWorkspaceView(this.getUIContext().getHostContext() as common.UIAbilityContext, this.hostScope(), id, 'select') }
    catch { this.errorText = this.t("工作区选择未能保存。") }
  }

  @State private colors: ThemeColors = themeColors()

  private pluginScope(messageId: string = ''): WireObject {
    const scope: WireObject = { 'sessionId': this.sessionId }; if (messageId) scope['messageId'] = messageId; return scope
  }
  private isDark(): boolean { return this.themeMode === 'dark' || (this.themeMode === 'system' && this.systemDark) }
  private advancedChanged(): void { AppStorage.setOrCreate('dshLanguage', this.advanced.language); this.updateColors() }
  private showShare(only: string[] = []): void {
    if (!this.sessionId || this.loadingChat) return
    this.shareSource = JSON.parse(JSON.stringify({ 'title': this.sessionTitle, 'messages': this.messages,
      'tools': this.tools, 'notices': this.turnNotices, 'commands': this.commandNotices, 'records': this.records,
      'turns': turnTraces(this.records), 'model': this.modelName })) as WireObject
    this.shareOnly = only; this.shareOrigin = this.page; this.page = 'conversationShare'
  }
  private showShareImport(tab: string = 'import'): void {
    this.shareOrigin = this.page; this.shareTab = tab; this.shareInput = ''; this.shareFile = ''; this.page = 'conversationImport'
  }
  private async pluginEffect(effect: PluginEffect): Promise<void> {
    if (effect.type === 'insert') { this.draft += effect.text || ''; this.page = 'chat' }
    else if (effect.type === 'copy') await this.copyMessage(effect.text || '')
    else if (effect.type === 'toast') this.errorText = effect.text || ''
    else if (effect.type === 'open' && effect.id) this.openDestination(effect.id)
    else if (effect.type === 'command' && effect.id) {
      const command = this.hostCommands.find((item: DshCommand) => item.name === effect.id || item.definitionId === effect.id)
      if (command) { await this.runSlash({ name: command.name, definitionId: command.definitionId, label: command.label, description: command.description, hint: command.hint, kind: 'host' }, '/' + command.name + (effect.args ? ' ' + effect.args : '')) }
      else this.errorText = this.t("此插件命令当前不可用。")
    } else if (effect.type === 'link' && /^https:\/\//.test(effect.text || '')) {
      const target = effect.text || ''
      this.getUIContext().showAlertDialog({ title: this.t("打开插件链接？"), message: target,
        primaryButton: { value: this.t("取消"), action: () => {} }, secondaryButton: { value: this.t("打开"), action: () => {
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext
          void context.openLink(target).catch(() => { this.errorText = this.t("无法打开此链接") })
        } } })
    }
  }


  private updateColors(): void {
    this.colors = themeColors(this.accentId, this.isDark(), this.advanced.customColor)
  }

  aboutToAppear(): void {
    this.keyboardContext = this.getUIContext()
    this.updateKeyboardAvoidance()
    this.mentions.onChange = (): void => {
      this.mentionRevision++
      this.draft = this.mentions.composer.text
    }
    this.mentions.onLabelsChange = (): void => { this.mentionLabelsRevision++ }
    registerDshFonts(this.getUIContext())
    this.updateColors()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    this.speechModeReady = loadSpeechMode(context).then((mode: SpeechMode) => { this.speechMode = mode }).catch(() => {
      this.speechModeLoadFailed = true
      this.errorText = this.t("语音设置读取失败，请重新选择语音模式。")
    })
    this.performanceMonitor = new PerformanceMonitor(context, (value: PerformanceState) => { this.performance = value })
    void this.performanceMonitor.start().catch(() => { this.errorText = this.t('性能设置读取失败，已使用系统默认效果。') })
    this.initializeVoice(context)
    this.usage = createUsageStats(context, () => this.advanced.language)
    void this.usage.foreground()
    void loadAdvancedPreferences(context).then((prefs: AdvancedPreferences) => { this.advanced = prefs })
    void loadQuickPanelPreferences(context).then((prefs: QuickPanelPreferences) => { this.quickPreferences = prefs })
    void loadAppPreferences(context).then((prefs: AppPreferenceValues) => {
      this.accentId = prefs.accentId
      this.themeMode = prefs.themeMode
      this.fontSize = prefs.fontSize
    }).catch(() => { this.errorText = this.t("外观设置读取失败，已使用默认外观。") })
    void this.loadStartup(context)
  }

  private initializeVoice(context: common.UIAbilityContext): void {
    this.voiceBridge = new HarmonyVoiceBridge(context)
    const voice = new VoiceInputController(this.client, this.voiceBridge)
    this.voice = voice
    voice.readDraft = (): VoiceDraft => {
      if (this.mentions.composer.text !== this.draft) this.mentions.restore(this.draft)
      const composer = this.mentions.composer
      return { text: composer.text, start: composer.start, end: composer.end }
    }
    voice.writeDraft = (value: VoiceDraft): void => {
      this.mentions.composer.restore(value.text)
      this.mentions.composer.select(value.start, value.end)
      this.draft = value.text
      this.voiceProvisionalStart = value.provisionalStart ?? -1
      this.voiceProvisionalEnd = value.provisionalEnd ?? -1
      this.mentionRevision++
    }
    voice.loadMode = async (): Promise<SpeechMode> => {
      await this.speechModeReady
      if (this.speechModeLoadFailed) throw new Error(this.t("语音设置未能读取"))
      return this.speechMode
    }
    voice.preferLocalModel = (): boolean => this.mode === 'local'
    voice.onChange = (): void => {
      this.voicePhase = voice.phase
      if (voice.phase === 'idle') { this.voiceProvisionalStart = -1; this.voiceProvisionalEnd = -1 }
      this.voiceAvailable = voice.available
      if (voice.phase !== 'listening') this.voiceLevels = [0, 0, 0, 0, 0]
      else if (this.voiceLevel !== voice.level) this.voiceLevels = this.voiceLevels.slice(1).concat(voice.level)
      this.voiceLevel = voice.level
    }
    voice.onRecognized = () => this.recordUsage('voice')
    voice.onMessage = (message: VoiceMessage): void => {
      this.voiceNotice = message.text
      this.voiceSettingsAction = message.openSettings === true
      this.voiceModeAction = message.change === true
    }
    voice.setForeground(this.foreground)
    void voice.refresh()
  }

  private performanceActivity(): void { this.performanceMonitor?.activity(this.foreground, this.running || this.voicePhase !== 'idle') }
  private voiceForegroundChanged(): void { this.voice?.setForeground(this.foreground); this.performanceActivity(); if (this.foreground) void this.usage?.foreground(); this.pendingLaunchChanged() }

  private voicePageChanged(): void {
    this.updateKeyboardAvoidance()
    if (this.page !== 'chat') this.voice?.cancel()
    else { this.voice?.setContext(this.sessionId); void this.voice?.refresh() }
    this.pendingLaunchChanged()
  }

  private updateKeyboardAvoidance(): void {
    const context = this.keyboardContext
    if (!context) return
    // The route owns the page policy so old child disposal cannot undo a new route.
    if (this.page === 'chat' || this.page === 'terminal' || this.page === 'dsBot') {
      if (this.previousKeyboardAvoidMode === undefined) {
        this.previousKeyboardAvoidMode = context.getKeyboardAvoidMode()
        context.setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
      }
    } else this.restoreKeyboardAvoidance()
  }

  private restoreKeyboardAvoidance(): void {
    const context = this.keyboardContext
    const previousMode = this.previousKeyboardAvoidMode
    this.previousKeyboardAvoidMode = undefined
    if (context && previousMode !== undefined && context.getKeyboardAvoidMode() === KeyboardAvoidMode.RESIZE) {
      context.setKeyboardAvoidMode(previousMode)
    }
  }

  private async changeSpeechMode(mode: SpeechMode): Promise<void> {
    await this.speechModeReady
    await saveSpeechMode(this.getUIContext().getHostContext() as common.UIAbilityContext, mode)
    this.speechMode = mode
    this.speechModeLoadFailed = false
    void this.voice?.refresh()
  }

  private startVoice(): void {
    if (!this.voice || !this.connected || this.loadingChat || this.busy || this.sending || this.regenerating ||
      this.choosingAttachments || this.withdrawingAttachmentSessions.includes(this.sessionId)) return
    this.voiceNotice = ''
    this.mentions.dismiss()
    this.getUIContext().getFocusController().clearFocus()
    this.voice.setContext(this.sessionId)
    void this.voice.start()
  }

  private async loadStartup(context: common.UIAbilityContext): Promise<void> {
    const version = this.connectionVersion
    let complete = false
    try {
      complete = await loadOnboardingComplete(context)
    } catch { this.errorText = this.t("首次引导状态暂时无法读取。") }
    try {
      const stored = await hasLocalApiKey()
      if (version !== this.connectionVersion) return
      this.hasSavedKey = stored
      this.rememberKey = stored
    } catch {
      if (version === this.connectionVersion) {
        this.credentialNotice = this.t("安全密钥暂时无法读取。可解锁后重试，或手动输入 Key。")
      }
    }
    if (version === this.connectionVersion) {
      this.page = complete ? 'connect' : 'onboarding'
      if (complete) await this.restoreStartup(context, version)
    }
  }

  private async restoreStartup(context: common.UIAbilityContext, version: number): Promise<void> {
    try {
      const settings = await loadStartupSettings(context)
      const target = startupTarget(settings, version !== this.connectionVersion || this.page !== 'connect', true)
      if (!target) return
      if (target.kind === 'local') { this.mode = 'local'; await this.connect(undefined, undefined, false, !this.hasSavedKey); return }
      this.restoreHostId = target.id
      if (target.kind === 'http') {
        const hosts = await listRemoteHosts(context)
        if (version !== this.connectionVersion || this.page !== 'connect') return
        const host = hosts.find(item => item.id === target.id)
        const connection = host ? await getRemoteHostConnection(host) : undefined
        if (version !== this.connectionVersion || this.page !== 'connect') return
        if (connection) await this.connectRemote(connection)
        else { this.showRemoteHosts(); this.errorText = this.t("上次主机已移除或没有保存凭据，请重新选择。") }
      } else { this.remoteOrigin = 'connect'; this.page = target.kind === 'ssh' ? 'sshHosts' : 'relayHosts' }
    } catch { if (version === this.connectionVersion) this.errorText = this.t("无法恢复上次启动状态，请手动连接。") }
  }

  private async finishOnboarding(): Promise<void> {
    const version = this.connectionVersion
    try { await saveOnboardingComplete(this.getUIContext().getHostContext() as common.UIAbilityContext) }
    catch { if (version === this.connectionVersion) this.errorText = this.t("首次引导状态未能保存，下次启动可能再次显示。") }
    if (version === this.connectionVersion) this.page = this.connected ? 'chat' : 'connect'
  }

  private async prepareLocal(): Promise<void> {
    if (this.busy || this.engineReady) return
    const version = this.connectionVersion
    this.busy = true; this.errorText = ''; this.mode = 'local'
    try {
      await this.localEngine.start(this.getUIContext().getHostContext() as common.UIAbilityContext,
        (message: string) => { if (version === this.connectionVersion) this.localStage = message })
      if (version === this.connectionVersion) { this.engineReady = true; void this.usage?.engine('direct').catch(() => {}) }
      else await this.localEngine.stop()
    } catch { if (version === this.connectionVersion) this.errorText = this.t("本机引擎准备失败，请重试。") }
    finally { if (version === this.connectionVersion) { this.busy = false; this.localStage = '' } }
  }

  private async openLocalAccount(): Promise<void> {
    if (this.busy || this.switchingHost || this.mode !== 'local') return
    if (await this.connect(undefined, undefined, false, true)) this.showSettings('account')
  }

  private async forgetKey(): Promise<void> {
    if (this.busy) return
    const version = this.connectionVersion
    this.busy = true
    try {
      await removeLocalApiKey()
      if (version === this.connectionVersion) {
        this.hasSavedKey = false; this.rememberKey = false; this.credentialNotice = ''
      }
    } catch { if (version === this.connectionVersion) this.credentialNotice = this.t("安全密钥未能删除，请解锁后重试。") }
    finally { if (version === this.connectionVersion) this.busy = false }
  }

  private async refreshSavedKey(): Promise<void> {
    if (this.busy) return
    const version = this.connectionVersion
    this.busy = true
    try {
      const stored = await hasLocalApiKey()
      if (version === this.connectionVersion) {
        this.hasSavedKey = stored; this.rememberKey = stored; this.credentialNotice = ''
      }
    } catch { if (version === this.connectionVersion) this.credentialNotice = this.t("安全密钥暂时无法访问，请解锁后重试。") }
    finally { if (version === this.connectionVersion) this.busy = false }
  }

  private async showSessionOptions(): Promise<void> {
    if (this.connected) this.page = 'sessionOptions'
  }

  private async persistPreferences(): Promise<void> {
    try {
      await saveAppPreferences(this.getUIContext().getHostContext() as common.UIAbilityContext,
        { accentId: this.accentId, themeMode: this.themeMode, fontSize: this.fontSize })
    } catch { this.errorText = this.t("外观设置未能保存，退出后可能恢复原值。") }
  }

  private pendingLaunchChanged(): void {
    if (!this.launchRequest || !this.foreground || this.busy || this.maintenanceBusy || this.sending || ['loading', 'onboarding'].includes(this.page)) return
    let request: WireObject
    try { request = object(JSON.parse(this.launchRequest)) } catch { this.launchRequest = ''; return }
    const page = typeof request['page'] === 'string' ? appPageLink('dshgo://open/' + request['page']) : ''
    const entry = launcherEntry(request['entry'])
    const forum = forumAuthCallback(string(request['forum']))
    const launchShare = object(request['share'])
    const share = shareLaunch(string(launchShare['link']) || string(launchShare['file']), launchShare['file'] ? 'application/vnd.dshgo+json' : '')
    if (entry && !this.connected) return
    this.launchRequest = ''
    if (forum) { this.forumRedirect = forum; this.page = 'forum'; return }
    if (share) { this.showShareImport(); this.shareInput = share.link; this.shareFile = share.file; return }
    if (page) { this.openDestination(page); return }
    if (!entry) return
    if (entry.kind === 'dsbot-bot' || entry.kind === 'dsbot-room') {
      if (entry.host && entry.host !== this.hostScope()) { this.errorText = this.t('请先切换到通知所属的主机。'); return }
      this.dsBotInitialId = entry.sessionId; this.dsBotInitialRoom = entry.kind === 'dsbot-room'; this.page = 'dsBot'; return
    }
    if (entry.kind === 'chat') {
      if (entry.host && entry.host !== this.hostScope()) { this.errorText = this.t("请先切换到这条对话所属的主机。"); return }
      const session = this.sessions.find((item: DshSession) => item.id === entry.sessionId)
      if (session) void this.openSession(session.id, session.title)
      else this.errorText = this.t("当前主机中找不到这条对话。")
      return
    }
    this.home()
    if (entry.text) this.draft = this.draft.trim() ? this.draft + '\n\n' + entry.text : entry.text
    if (entry.kind === 'voice') this.startVoice()
  }

  private openDestination(id: string): void {
    if (id === 'plugins' || id === 'plugin-inventory') this.openFeature('plugins')
    else if (id === 'schedules') this.openFeature('schedules')
    else if (id === 'agent-team') this.openFeature('agents')
    else if (id === 'remote') this.showRemoteHosts()
    else if (id === 'cordis' || id === 'plugin-seats') { this.pluginPlace = undefined; this.pluginSection = id === 'cordis' ? 'cordis' : 'seats'; this.page = 'nativePlugins' }
    else if (id === 'pets' || id === 'companion') this.page = id
    else if (id === 'search' || id === 'session-search') { this.page = 'chat'; this.searchRequest++; this.drawer = true }
    else if (id === 'workspaces') this.page = 'workspaces'
    else if (id === 'features' || id === 'all-features') this.page = 'features'
    else if (id === 'ds-bot') { this.dsBotInitialId = ''; this.page = 'dsBot' }
    else if (id === 'forum' || id === 'community') this.page = 'forum'
    else if (id === 'web') this.page = 'webMode'
    else if (id === 'network' || id === 'diagnostics') this.page = 'networkDiagnostics'
    else if (id === 'startup') this.page = 'startup'
    else if (['phone', 'phone-unlocks', 'phone-files', 'phone-confirm'].includes(id)) this.page = 'phone'
    else if (['performance', 'background', 'system-permissions'].includes(id)) this.page = id
    else if (id === 'share-profile') this.showSettings('share-profile')
    else if (id === 'share-import') this.showShareImport()
    else if (id === 'shared-links') this.showShareImport('links')
    else if (id === 'new-chat') this.home()
    else if (id === 'reference') this.page = 'chat'
    else if (['skills', 'jobs'].includes(id)) this.openFeature(id)
    else if (id === 'subagents') this.openFeature('agents')
    else if (id === 'voice-input') this.showSettings('speech')
    else if (id === 'general') this.showSettings('home')
    else if (['session-detail', 'plan-goal', 'files', 'artifacts', 'terminal', 'export'].includes(id)) {
      if (!this.sessionId) { this.errorText = this.t('请先打开或创建一个对话。'); return }
      if (id === 'session-detail' || id === 'plan-goal') this.showDetail(id === 'plan-goal' ? 'progress' : 'trajectory')
      else if (id === 'files') this.showFiles()
      else if (id === 'artifacts') this.page = 'artifacts'
      else if (id === 'terminal') this.page = 'terminal'
      else { this.exportOrigin = this.page; this.page = 'sessionExport' }
    }
    else if (id === 'agent-presets') { void this.showSessionOptions() }
    else {
      const aliases: Record<string, string> = { 'settings': 'home', 'settingsSearch': 'home', 'web-search': 'search',
        'voice': 'speech', 'engine-settings': 'parameters', 'dark-mode': 'appearance', 'chat-text-size': 'appearance',
        'permission-default': 'permission' }
      const destination = aliases[id] || id
      if (['home', 'models', 'permission', 'search', 'media', 'appearance', 'speech', 'engine', 'parameters',
        'subagent-settings', 'agent-loop', 'shell-settings', 'diagnostics', 'about', 'account', 'personalization', 'interface', 'theme', 'notifications', 'privacy', 'usage-stats', 'subscriptions', 'voice-scribe', 'cot-translation'].includes(destination)) this.showSettings(destination)
      else this.errorText = this.t("无法识别这个入口。")
    }
  }

  private showSettings(page: string = 'home'): void {
    if (this.page !== 'settings') {
      this.settingsOrigin = ['models', 'onboarding', 'nativePlugins', 'engineFeatures', 'features'].includes(this.page) ? this.page : 'chat'
      this.settingsScope = `${this.connectionVersion}/${this.sessionId}`
    }
    this.settingsPage = page
    this.settingsRequestVersion++
    this.drawer = false
    this.page = 'settings'
  }

  private closeSettings(): void {
    if (this.settingsOrigin === 'onboarding') { this.page = 'onboarding'; return }
    this.page = this.connected ? (this.settingsScope === `${this.connectionVersion}/${this.sessionId}` ?
      this.settingsOrigin : 'chat') : 'connect'
  }

  private async showModels(): Promise<void> {
    if (this.busy || this.sending || this.switchingHost) return
    if (!this.connected) { this.page = 'connect'; return }
    this.page = 'models'
  }

  private home(): void {
    this.voice?.setContext('')
    this.retireRegeneration()
    this.mentions.reset()
    this.composerDrafts.write(this.sessionId, this.draft)
    this.changeAttachmentDraft('')
    this.chatVersion++
    void this.client.unwatchSession()
    this.sessionId = ''
    this.sessionTitle = ''
    this.messages = []
    this.records = []
    this.tools = []
    this.turnNotices = []; this.sessionError = ''
    this.commandNotices = []; this.hostCommands = []; this.sessionSkills = []; this.compacting = false
    this.commandCatalog = undefined
    this.currentModel = undefined; this.pendingSessionModel = undefined; this.pendingModelSessionId = ''
    this.queuedPrompts = []
    this.questions = []
    this.todos = []; this.goal = undefined; this.todosExpanded = false; this.detailTab = 'trajectory'
    this.cotTranslations.clear()
    this.expandedReasoning = []
    this.expandedTools = []
    this.expandedToolGroups = []
    this.expandedProcesses = []
    this.visualReplyPending = []; this.visualReplyRequests.clear()
    this.quickOpen = false
    this.approval = undefined
    this.draft = this.composerDrafts.read('')
    this.running = false
    this.loadingChat = false
    this.sending = false
    this.stopping = false
    this.deciding = false
    this.modelName = this.t("选择模型")
    this.reasoningEffort = ''
    this.page = 'chat'
    this.drawer = false
  }

  private async copyMessage(text: string): Promise<void> {
    try { await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)) }
    catch { this.errorText = this.t("复制失败，请重试。") }
  }

  private async fork(): Promise<void> {
    if (this.busy || !this.sessionId) return
    const version = this.connectionVersion
    this.busy = true
    try {
      const id = await this.client.forkSession(this.sessionId)
      if (version === this.connectionVersion) await this.openSession(id, this.sessionTitle)
    } catch { this.errorText = this.t("无法创建分支对话，请重试。") }
    finally { if (version === this.connectionVersion) this.busy = false }
  }
  @State private address: string = ''
  @State private authorization: string = ''
  @State private host: string = ''
  @State private mode: string = 'local'
  @State private modelKey: string = ''
  @State private localStage: string = ''
  private localEngine: LocalEngine = new LocalEngine()
  private localWorkspace: string = ''
  @State private connected: boolean = false
  @State @Watch('pendingLaunchChanged') private busy: boolean = false
  @State private refreshing: boolean = false
  @State @Watch('pendingLaunchChanged') private sending: boolean = false
  @State private deciding: boolean = false
  @State private errorText: string = ''
  @State private sessions: DshSession[] = []
  @State private workspaces: DshWorkspace[] = []
  @State private workspaceId: string = ''
  @State private sessionId: string = ''
  @State private sessionTitle: string = ''
  @State private messages: DshMessage[] = []
  @State private records: DshSessionRecord[] = []
  @State private regenerating: boolean = false
  private regenerationVersion: number = 0
  @State private regenerationSourceId: string = ''
  private regenerationSourceTitle: string = ''
  @State private approval: DshApproval | undefined = undefined
  @State @Watch('performanceActivity') private running: boolean = false
  @State private loadingChat: boolean = false
  @State private stopping: boolean = false
  @State private draft: string = ''
  @State private draftAttachments: DraftAttachment[] = []
  @State private choosingAttachments: boolean = false
  @State private galleryItems: GalleryImage[] = []
  private galleryIndex: number = 0
  private attachmentDrafts: Map<string, DraftAttachment[]> = new Map()
  private attachmentRequestIds: Map<string, string> = new Map()
  @State private queuedAttachmentDrafts: QueuedAttachmentDraft[] = []
  @State private withdrawingAttachmentSessions: string[] = []
  private client: DshClient = new DshClient((reason: string) => {
    const nextPage = this.mode === 'remote' ? 'remoteHosts' : 'connect'
    void this.disconnect(false, nextPage).then(() => {
      this.errorText = this.errorMessage(new Error(reason), this.t("连接已断开。请重新连接。"))
    })
  })
  private mentions: MentionPickerController = new MentionPickerController(this.client)
  @State private mentionRevision: number = 0
  @State private mentionLabelsRevision: number = 0
  private chatScroller: Scroller = new Scroller()
  @State private connectionVersion: number = 0
  private chatVersion: number = 0

  aboutToDisappear(): void {
    this.bundledBotControl = undefined; this.bundledBotAvailable = false
    this.restoreKeyboardAvoidance()
    this.keyboardContext = undefined
    this.performanceMonitor?.stop()
    this.voice?.dispose()
    this.retireRegeneration()
    this.mentions.reset()
    this.connectionVersion++
    this.chatVersion++
    this.petFeed?.close(); this.petFeed = undefined; this.petSessions = []; this.dsBot?.close(); this.dsBot = undefined; this.dsBotOwnedSessions = []
    this.notifications?.stop(); this.notificationBanner = undefined
    this.client.close()
    this.releaseTransport()
    this.clearAttachments()
    this.mediaParams = undefined
    this.mediaItems = []
    this.modelKey = ''; this.questionDrafts.clear(); this.composerDrafts.clear()
    void this.localEngine.stop().catch(() => {})
  }

  onBackPress(): boolean {
    if (this.maintenanceBusy) return true
    if (this.quickOpen) { this.quickOpen = false; return true }
    if (this.page === 'chat' && this.voice?.active) { this.voice.cancel(); return true }
    if (this.page === 'chat' && this.mentions.isOpen) { this.mentions.dismiss(); return true }
    if (this.drawer && this.sessionsBack?.()) return true
    if (this.page === 'workspaces' && this.workspaceBack?.()) return true
    if (this.page === 'settings' && this.settingsBack?.()) return true
    if (this.page === 'nativePlugins' && this.nativePluginsBack?.()) return true
    if (this.page === 'companion') { if (!this.companionBack?.()) this.page = 'features'; return true }
    if (this.page === 'engineFeatures' && this.featuresBack?.()) return true
    if (this.page === 'files' && this.filesBack?.()) return true
    if (this.page === 'models' && this.modelsBack?.()) return true
    if (this.page === 'detail' && this.detailBack?.()) return true
    if (this.page === 'onboarding' && this.onboardingBack?.()) return true
    if (['conversationShare', 'conversationImport', 'profileShare'].includes(this.page) && this.shareBack?.()) return true
    if (['conversationShare', 'conversationImport', 'profileShare'].includes(this.page)) { this.page = this.shareOrigin; return true }
    if (this.page === 'forum' && this.forumBack?.()) return true
    if (this.page === 'phone' && this.phoneBack?.()) return true
    if (this.page === 'dsBot' && this.dsBotBack?.()) return true
    if (this.page === 'sessionExport' && this.exportBack?.()) return true
    if (this.page === 'remoteHosts' && this.remoteBack?.()) return true
    if (this.page === 'sshHosts' && this.sshBack?.()) return true
    if (this.page === 'chat' && this.viewportWidth >= 840 && this.sessionsBack?.()) return true
    if (this.drawer) { this.drawer = false; return true }
    if (this.page === 'onboarding' || this.page === 'loading') return true
    if (this.page === 'engineFeatures') { this.page = this.featureOrigin; return true }
    if (this.page === 'sessionExport') { this.page = this.exportOrigin; return true }
    if (this.page === 'remoteHosts') { this.closeRemoteHosts(); return true }
    if (this.page === 'sshHosts' || this.page === 'relayHosts') { if (!this.busy) this.page = 'remoteHosts'; return true }
    if (this.page === 'terminal') { this.page = 'features'; return true }
    if (this.page === 'attachmentPreview') { this.closeAttachmentPreview(); return true }
    if (this.page === 'files') { this.page = this.filesOrigin; return true }
    if (this.page === 'settings') { this.closeSettings(); return true }
    if (this.page !== 'chat' && this.page !== 'connect') {
      this.page = this.connected ? 'chat' : 'connect'
      return true
    }
    if (this.page === 'chat' && this.sessionId) { this.home(); return true }
    return false
  }

  private errorMessage(error: Error, fallback: string): string {
    const detail = error?.message
    if (!detail || /(?:https?|wss?):\/\/|authorization|dsh-auth-|token=/i.test(detail)) {
      return fallback
    }
    return detail.slice(0, 240)
  }

  private async connect(keyOverride?: string, remember?: boolean, keepOnboarding: boolean = false,
    withoutKey: boolean = false, forMaintenance: boolean = false): Promise<boolean> {
    const local = this.mode === 'local'
    const draftKey = keyOverride || this.modelKey.trim()
    const saveKey = remember === undefined ? this.rememberKey : remember
    if (this.busy || (this.maintenanceBusy && !forMaintenance) || !(local ? withoutKey || draftKey || this.hasSavedKey || this.localConfigured : this.address.trim())) {
      return false
    }
    const version = ++this.connectionVersion
    this.bundledBotControl = undefined; this.bundledBotAvailable = false
    this.busy = true
    this.errorText = ''
    const wasEngineReady = this.engineReady
    try {
      if (local) {
        const storedKey = !withoutKey && !draftKey && this.hasSavedKey ? await loadLocalApiKey() : undefined
        const normalizedKey = !withoutKey && (draftKey || storedKey) ? normalizeProviderKey(draftKey || storedKey || '') : ''
        if (!withoutKey && !normalizedKey && !this.localConfigured) throw new Error(this.t("已保存的 API Key 不可用，请重新输入。"))
        if (version !== this.connectionVersion) return false
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext
        const endpoint = await this.localEngine.start(context, (message: string) => {
          if (version === this.connectionVersion) {
            this.localStage = message
          }
        })
        if (version !== this.connectionVersion) {
          await this.localEngine.stop()
          return false
        }
        this.localStage = this.t("正在连接本机引擎…")
        await this.client.connect(endpoint.url, undefined, true)
        if (version !== this.connectionVersion) return false
        if (normalizedKey) await this.client.setLocalModelKey(normalizedKey)
        else if (!withoutKey) {
          const credentials = await this.client.describeCredentials(['DEEPSEEK_API_KEY'])
          if (version !== this.connectionVersion) return false
          if (object(credentials['DEEPSEEK_API_KEY'])['configured'] !== true) {
            this.localConfigured = false
            throw new Error(this.t("本机引擎的 API Key 已失效，请重新输入。"))
          }
        }
        if (version !== this.connectionVersion) return false
        this.engineReady = true; void this.usage?.engine('direct').catch(() => {})
        if (!withoutKey) {
          this.localConfigured = true
          try {
            if (saveKey && normalizedKey) {
              await saveLocalApiKey(normalizedKey)
              if (version !== this.connectionVersion) return false
              this.hasSavedKey = true; this.rememberKey = true
            } else if (!saveKey) {
              await removeLocalApiKey()
              if (version !== this.connectionVersion) return false
              this.hasSavedKey = false; this.rememberKey = false
            }
            this.credentialNotice = ''
          } catch { this.credentialNotice = this.t("已连接，但安全密钥保存设置未能更新，请解锁后重试。") }
        }
        if (version !== this.connectionVersion) return false
        this.localWorkspace = endpoint.workspaceDir
        this.bundledBotControl = endpoint.transportControl
        this.modelKey = ''
        this.host = this.t("本机 · DeepSeek Harness")
      } else {
        const launchUrl = this.address.trim()
        await this.client.connect(launchUrl, this.authorization.trim())
        this.host = this.transport?.name || launchUrl.replace(/^https?:\/\//i, '').split(/[/?#]/)[0]
        this.authorization = ''
        this.address = launchUrl.split(/[?#]/)[0]
      }
      if (version !== this.connectionVersion) {
        return false
      }
      this.connected = true
      const workspaceView = await loadWorkspaceView(this.getUIContext().getHostContext() as common.UIAbilityContext, this.hostScope())
      if (version !== this.connectionVersion) return false
      this.workspaceId = workspaceView.selected
      this.client.onHostEvent((event: WireObject) => {
        if (version === this.connectionVersion && this.sessionId && event['type'] === 'emit' &&
          ['commands/change', 'agent-preset/selected'].includes(String(event['event']))) {
          this.commandCatalog = this.loadCommandCatalog()
        }
      })
      if (!keepOnboarding) await this.finishOnboarding()
      if (version !== this.connectionVersion || !this.connected) return false
      try {
        await this.client.watchWorkspaces((items: DshWorkspace[]) => {
          if (version === this.connectionVersion) {
            this.workspaces = items
            if (!items.some((item: DshWorkspace) => item.id === this.workspaceId)) {
              this.workspaceId = ''
            }
          }
        })
      } finally {
        if (version === this.connectionVersion) {
          await this.refreshSessions()
        }
      }
      if (this.connected && version === this.connectionVersion) {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext
        this.notifications?.stop()
        this.notifications = new ChatNotifications(this.client, context, this.hostScope(), () => this.page === 'chat' ? this.sessionId : this.page === 'dsBot' ? 'ds-bot' : '',
          () => this.foreground, (item: ChatNotification) => { this.notificationBanner = item })
        void this.notifications.start().catch(() => {})
        this.petFeed?.close()
        this.petFeed = new PetActivityFeed(this.client, this.hostScope(), () => this.sessions, (rows: PetSessionSnapshot[]) => { if (version === this.connectionVersion) this.petSessions = rows.filter((row: PetSessionSnapshot) => !this.hiddenSessionIds().includes(row.sessionId)) })
        void this.petFeed.start().catch(() => {})
        await this.startDSBot(version)
        if (version === this.connectionVersion) void this.loadBundledBot()
        void companionBindingIds(context, this.hostScope()).catch(() => {})
        void this.refreshQuickPlugins()
        void this.client.listPluginBundles().then((bundles: WireObject[]) => { if (version === this.connectionVersion) void this.usage?.plugins(bundles.filter((bundle: WireObject) => bundle['installed'] === true && bundle['official'] !== true).length).catch(() => {}) }).catch(() => {})
        void rememberStartupHost(context, local ? 'local' : this.transportKind || 'http', local ? '' : this.remoteHostId).catch(() => {})
      }
      return this.connected && version === this.connectionVersion
    } catch (error) {
      if (version === this.connectionVersion) {
        if (!this.connected) {
          this.petFeed?.close(); this.petFeed = undefined; this.petSessions = []; this.dsBot?.close(); this.dsBot = undefined; this.dsBotOwnedSessions = []
    this.notifications?.stop(); this.notificationBanner = undefined
    this.client.close()
          if (local && !wasEngineReady) {
            await this.localEngine.stop().catch(() => {})
            this.engineReady = false; this.localConfigured = false
          }
        }
        this.errorText = this.errorMessage(error as Error, local ?
          this.t("本机引擎启动失败，请重试。") : this.t("连接失败，请检查地址、凭据和主机状态。"))
      }
      return this.connected && version === this.connectionVersion
    } finally {
      if (version === this.connectionVersion) {
        this.localStage = ''
        this.busy = false
      }
    }
  }

  private async startDSBot(connection: number): Promise<void> {
    this.dsBot?.close(); this.dsBot = undefined; this.dsBotOwnedSessions = []
    try {
      const hub = await createDSBotHub(this.client, this.getUIContext().getHostContext() as common.UIAbilityContext,
        this.hostScope(), () => this.localeLanguage, this.transportKind === 'relay')
      if (!this.connected || connection !== this.connectionVersion) { hub.close(); return }
      this.dsBot = hub
      hub.onChange = () => { if (connection === this.connectionVersion) { this.dsBotOwnedSessions = hub.ownedSessions(); this.notifications?.setBotSessions(this.dsBotOwnedSessions) } }
      hub.onNotice = (notice: WireObject, caughtUp: boolean) => { if (connection === this.connectionVersion) void this.notifications?.bot(notice, caughtUp).catch(() => {}) }
      void hub.start()
    } catch { /* DS Bot remains independently retryable in its page. */ }
  }

  private async disconnect(stopLocal: boolean = true, nextPage: string = 'connect'): Promise<void> {
    if (this.stoppingLocalEngine) {
      return
    }
    const local = stopLocal && this.mode === 'local'
    this.bundledBotControl = undefined; this.bundledBotAvailable = false
    this.voice?.cancel()
    this.voiceNotice = ''
    this.retireRegeneration()
    this.mentions.reset()
    this.connectionVersion++
    this.chatVersion++
    this.petFeed?.close(); this.petFeed = undefined; this.petSessions = []; this.dsBot?.close(); this.dsBot = undefined; this.dsBotOwnedSessions = []
    this.notifications?.stop(); this.notificationBanner = undefined
    this.client.close()
    this.releaseTransport()
    this.clearAttachments()
    this.mediaParams = undefined
    this.mediaItems = []
    this.connected = false
    this.modelName = this.t("选择模型")
    this.reasoningEffort = ''
    this.currentModel = undefined; this.pendingSessionModel = undefined; this.pendingModelSessionId = ''
    this.turnNotices = []; this.sessionError = ''
    this.commandNotices = []; this.hostCommands = []; this.sessionSkills = []; this.compacting = false
    this.commandCatalog = undefined
    this.recoveryRequestIds.clear(); this.submittedRecoveries = []
    this.modelKey = ''
    this.remoteHostId = ''
    this.remoteHostScope = ''
    if (local) { this.engineReady = false; this.localConfigured = false; this.localWorkspace = '' }
    this.busy = local
    this.refreshing = false
    this.sessions = []
    this.workspaces = []
    this.workspaceId = ''
    this.sessionId = ''
    this.sessionTitle = ''
    this.messages = []
    this.records = []
    this.tools = []
    this.queuedPrompts = []
    this.questions = []
    this.todos = []; this.goal = undefined; this.todosExpanded = false; this.detailTab = 'trajectory'
    this.questionDrafts.clear()
    this.composerDrafts.clear()
    this.cotTranslations.clear()
    this.expandedReasoning = []
    this.expandedTools = []
    this.expandedToolGroups = []
    this.expandedProcesses = []
    this.visualReplyPending = []; this.visualReplyRequests.clear()
    this.quickOpen = false
    this.approval = undefined
    this.running = false
    this.loadingChat = false
    this.stopping = false
    this.sending = false
    this.deciding = false
    this.draft = ''
    this.errorText = ''
    this.page = nextPage
    this.drawer = false
    if (local) {
      this.stoppingLocalEngine = true
      this.localStage = this.t("正在停止本机引擎…")
      try {
        await this.localEngine.stop()
      } catch {
        this.errorText = this.t("本机引擎正在退出，请稍后再试。")
      } finally {
        this.stoppingLocalEngine = false
        this.localStage = ''
        this.busy = false
      }
    }
  }

  private async refreshSessions(): Promise<void> {
    if (!this.connected || this.refreshing) {
      return
    }
    const version = this.connectionVersion
    this.refreshing = true
    this.errorText = ''
    try {
      const sessions = await this.client.listSessions()
      if (version === this.connectionVersion) {
        this.sessions = sessions
      }
    } catch (error) {
      if (version === this.connectionVersion) {
        this.errorText = this.errorMessage(error as Error, this.t("无法读取会话，请检查连接。"))
      }
    } finally {
      if (version === this.connectionVersion) {
        this.refreshing = false
      }
    }
  }

  private visibleSessions(): DshSession[] {
    const workspace = this.workspaces.find((item: DshWorkspace) => item.id === this.workspaceId)
    if (!workspace) {
      return this.sessions
    }
    const sessionIds = new Set(workspace.sessionIds)
    return this.sessions.filter((item: DshSession) => sessionIds.has(item.id))
  }

  private async newSession(): Promise<boolean> {
    if (this.busy || !this.connected) {
      return false
    }
    const version = this.connectionVersion
    const chatVersion = this.chatVersion
    const selected = !this.sessionId ? this.currentModel : undefined
    this.busy = true
    this.errorText = ''
    try {
      const modes = await resolveNewChatModes(this.client, { preset: this.newPreset, permission: this.newPermission })
      if (version !== this.connectionVersion || chatVersion !== this.chatVersion) return false
      const cwd = this.mode === 'local' ? this.localWorkspace || undefined : undefined
      const id = await this.client.createSession(this.workspaceId || undefined, cwd)
      if (version === this.connectionVersion && chatVersion === this.chatVersion) {
        const scope = this.hostScope()
        this.owedNewChatModes.set(JSON.stringify([scope, id]), modes)
        await saveNewChatSetup(this.getUIContext().getHostContext() as common.UIAbilityContext, scope, id, modes)
        if (version !== this.connectionVersion || chatVersion !== this.chatVersion) return false
        this.pendingSessionModel = selected
        this.pendingModelSessionId = selected ? id : ''
        const opening = this.openSession(id, this.t("新会话"))
        const openedVersion = this.chatVersion
        await opening
        if (openedVersion !== this.chatVersion) return false
        return await this.applyPendingModes(id, version) && await this.applyPendingModel(id, version)
      }
    } catch (error) {
      if (version === this.connectionVersion) {
        this.errorText = this.errorMessage(error as Error, this.t("创建会话失败。"))
      }
    } finally {
      if (version === this.connectionVersion) {
        this.busy = false
      }
    }
    return false
  }

  private hostScope(): string { return this.mode === 'local' ? 'local' : this.remoteHostScope }

  private async applyPendingModes(id: string, connection: number): Promise<boolean> {
    const chat = this.chatVersion, scope = this.hostScope(), key = JSON.stringify([scope, id])
    const current = (): boolean => connection === this.connectionVersion && chat === this.chatVersion && id === this.sessionId
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    try {
      const owed = this.owedNewChatModes.get(key) || await loadNewChatSetup(context, scope, id)
      if (!current()) return false
      if (!owed.preset && !owed.permission) { this.owedNewChatModes.delete(key); return true }
      this.owedNewChatModes.set(key, owed)
      await saveNewChatSetup(context, scope, id, owed)
      if (!current()) return false
      await applyNewChatModes(this.client, id, owed, current, async (remaining: NewChatModes): Promise<void> => {
        this.owedNewChatModes.set(key, remaining)
        await saveNewChatSetup(context, scope, id, remaining)
      })
      if (!current()) return false
      this.owedNewChatModes.delete(key)
      return true
    } catch (error) {
      if (current()) this.errorText = (error as Error).message || this.t("新对话设置未能确认，消息尚未发送。")
      return false
    }
  }

  private async applyPendingModel(id: string, version: number): Promise<boolean> {
    if (version !== this.connectionVersion || id !== this.sessionId) return false
    const chatVersion = this.chatVersion
    const selected = this.pendingModelSessionId === id ? this.pendingSessionModel : undefined
    if (!selected) return true
    try {
      const result = await this.client.setModel(id, selected.provider, selected.model, selected.reasoningEffort)
      if (version !== this.connectionVersion || chatVersion !== this.chatVersion || id !== this.sessionId) return false
      this.currentModel = result.selected
      this.modelName = result.selected.model
      this.reasoningEffort = result.selected.reasoningEffort || ''
      this.pendingSessionModel = undefined; this.pendingModelSessionId = ''
      return true
    } catch {
      if (version === this.connectionVersion && chatVersion === this.chatVersion && id === this.sessionId) {
        this.errorText = this.t("对话已创建，但所选模型未能应用。消息尚未发送，可重试或重新选择模型。")
      }
      return false
    }
  }

  private retireRegeneration(): void {
    this.regenerationVersion++
    this.regenerating = false
    this.regenerationSourceId = ''
  }

  private async openSession(id: string, title: string, regenerationVersion?: number): Promise<void> {
    this.voice?.setContext(id)
    this.voiceNotice = ''
    if (regenerationVersion !== this.regenerationVersion) this.retireRegeneration()
    this.mentions.reset()
    this.regenerationSourceId = ''
    this.composerDrafts.write(this.sessionId, this.draft)
    this.changeAttachmentDraft(id)
    const version = ++this.chatVersion
    this.sessionId = id
    this.sessionTitle = title
    const selected = this.sessions.find((item: DshSession) => item.id === id)?.model
    this.currentModel = selected
    if (this.pendingModelSessionId !== id) { this.pendingSessionModel = undefined; this.pendingModelSessionId = '' }
    this.modelName = selected?.model || this.t("选择模型")
    this.reasoningEffort = selected?.reasoningEffort || ''
    this.messages = []
    this.records = []
    this.tools = []
    this.turnNotices = []; this.sessionError = ''
    this.commandNotices = []; this.hostCommands = []; this.sessionSkills = []; this.compacting = false
    this.commandCatalog = undefined
    this.queuedPrompts = []
    this.questions = []
    this.todos = []; this.goal = undefined; this.todosExpanded = false; this.detailTab = 'trajectory'
    this.cotTranslations.clear()
    this.expandedReasoning = []
    this.expandedTools = []
    this.expandedToolGroups = []
    this.expandedProcesses = []
    this.visualReplyPending = []; this.visualReplyRequests.clear()
    this.quickOpen = false
    this.approval = undefined
    this.running = false
    this.loadingChat = true
    this.stopping = false
    this.sending = false
    this.deciding = false
    this.draft = this.composerDrafts.read(id)
    this.errorText = ''
    this.page = 'chat'
    this.drawer = false
    let first = true
    try {
      await this.client.watchSession(id, (update: DshChatUpdate) => {
        if (version !== this.chatVersion || update.sessionId !== id) {
          return
        }
        const followLatest = first || this.chatScroller.isAtEnd()
        this.loadingChat = false
        this.messages = update.messages
        this.settleVisualReply()
        this.records = update.records || []
        this.releaseCommittedAttachments(id, update.messages)
        this.tools = update.tools || []
        this.turnNotices = update.notices || []
        this.commandNotices = update.commands || []
        this.compacting = update.compacting === true
        this.sessionError = update.sessionError || ''
        const selected = object(update.projections?.values['modelSelection'])
        const current = modelSelection(selected['next']) || modelSelection(selected['lastUsed'])
        if (current) {
          if (current.provider !== this.currentModel?.provider || current.model !== this.currentModel?.model) {
            this.modelName = current.model
          }
          this.currentModel = current
          this.reasoningEffort = current.reasoningEffort || ''
        }
        this.queuedPrompts = update.queue || []
        this.questions = update.questions || []
        this.todos = update.todos || []
        this.goal = update.goal
        if (update.running && !this.running) this.errorText = ''
        this.running = update.running
        this.approval = update.approval
        this.petFeed?.setFocusedSnapshot(id, { running: this.running, compacting: this.compacting, tools: this.tools.filter((tool: DshTool) => tool.result === undefined).length, reasoning: !!this.messages[this.messages.length - 1]?.reasoning && !this.messages[this.messages.length - 1]?.text, waiting: this.approval ? 'approval' : this.questions.length ? 'question' : '' })
        if (update.error) {
          this.errorText = this.errorMessage(new Error(update.error), this.t("会话连接已断开。"))
        }
        if (followLatest && (this.messages.length > 0 || this.commandNotices.length > 0)) {
          first = false
          this.scrollToLatest(version)
        }
      })
      if (version === this.chatVersion) this.commandCatalog = this.loadCommandCatalog()
    } catch (error) {
      if (version === this.chatVersion) {
        this.loadingChat = false
        this.errorText = this.errorMessage(error as Error, this.t("无法加载会话。返回列表后可以重试。"))
      }
    }
  }

  private showSessions(): void {
    this.drawer = true
    void this.refreshSessions()
  }

  private scrollToLatest(version: number = this.chatVersion): void {
    setTimeout(() => {
      if (version === this.chatVersion && this.page === 'chat') {
        this.chatScroller.scrollEdge(Edge.Bottom)
      }
    }, 80)
  }

  private async send(parseInput: boolean = true): Promise<void> {
    if (parseInput && this.mentions.pickHighlighted()) return
    const rawDraft = this.draft
    const draftValue = rawDraft.trim()
    let value = draftValue
    const media = parseInput ? this.mediaParams : undefined
    if (media) {
      try { value = formatMediaMessage(media, value) }
      catch { this.errorText = this.t("生成参数无效，请重新选择。"); return }
    }
    const originalConnection = this.connectionVersion
    const files = this.draftAttachments || []
    if (this.loadingChat || this.sending || this.busy || this.regenerating || this.choosingAttachments || this.voice?.active ||
      this.withdrawingAttachmentSessions.includes(this.sessionId) || (!draftValue && !files.length)) {
      return
    }
    if (files.length > MAX_ATTACHMENTS || files.reduce((total: number, file: DraftAttachment) => total + file.size, 0) > MAX_ATTACHMENT_TOTAL) {
      this.errorText = this.t("每条消息最多添加 9 个附件，附件总大小不能超过 400 MiB。请分批发送。")
      return
    }
    if (media) {
      const chat = this.chatVersion
      this.sending = true
      try {
        const catalog = await loadMediaCatalog(this.client)
        if (originalConnection !== this.connectionVersion || chat !== this.chatVersion || this.draft !== rawDraft ||
          this.mediaParams !== media || this.draftAttachments.length !== files.length ||
          !this.draftAttachments.every((file: DraftAttachment, index: number) => file.id === files[index].id)) return
        if (files.some((file: DraftAttachment) => !file.mediaType)) throw new Error(this.t("媒体生成只支持图片参考附件。"))
        validateMediaReferences(media, catalog, files.length)
      } catch (error) {
        if (originalConnection === this.connectionVersion && chat === this.chatVersion) this.errorText = (error as Error).message
        return
      } finally { if (originalConnection === this.connectionVersion && chat === this.chatVersion) this.sending = false }
    }
    if (parseInput && !media && !files.length && value.startsWith('/')) {
      const version = this.chatVersion
      if (await this.sendSlash(rawDraft)) return
      if (version !== this.chatVersion || this.draft !== rawDraft || this.sending || this.busy ||
        this.withdrawingAttachmentSessions.includes(this.sessionId)) return
    }
    if (!this.sessionId) {
      const created = await this.newSession()
      if (originalConnection !== this.connectionVersion) return
      if (files.length && (created || (this.sessionId && this.sessionId === this.pendingModelSessionId))) {
        const homeFiles = this.attachmentDrafts.get('')
        if (homeFiles?.length === files.length && homeFiles.every((file: DraftAttachment, index: number) => file.id === files[index].id)) {
          this.attachmentDrafts.delete('')
          this.attachmentDrafts.set(this.sessionId, files)
          this.draftAttachments = files
        }
      }
      if (!created) {
        if (this.connected && (this.sessionId === this.pendingModelSessionId ||
          this.owedNewChatModes.has(JSON.stringify([this.hostScope(), this.sessionId])))) {
          if (!this.draft.trim()) this.draft = rawDraft
          if (this.composerDrafts.read('') === rawDraft) this.composerDrafts.write('', '')
        }
        return
      }
      if (!this.draft.trim()) this.draft = rawDraft
      if (this.composerDrafts.read('') === rawDraft) this.composerDrafts.write('', '')
    }
    const version = this.chatVersion
    const connectionVersion = this.connectionVersion
    const id = this.sessionId
    this.sending = true
    this.errorText = ''
    try {
      if (!await this.applyPendingModes(id, connectionVersion) || !await this.applyPendingModel(id, connectionVersion)) return
      if (version !== this.chatVersion || connectionVersion !== this.connectionVersion) return
      if (files.length && (this.draftAttachments.length !== files.length ||
        !this.draftAttachments.every((file: DraftAttachment, index: number) => file.id === files[index].id))) return
      if (files.length) await this.sendAttachmentDraft(id, value, files, version, connectionVersion)
      else await this.client.prompt(id, value)
      this.recordUsage('turns'); if (media) this.recordUsage('gen')
      if (version === this.chatVersion && this.draft.trim() === draftValue) {
        this.draft = ''
        this.composerDrafts.write(this.sessionId, '')
        this.scrollToLatest(version)
      }
    } catch (error) {
      if (version === this.chatVersion) {
        this.errorText = this.errorMessage(error as Error, this.t("发送失败，输入内容已保留。"))
      }
    } finally {
      if (version === this.chatVersion) {
        this.sending = false
      }
    }
  }

  private async regenerateMedia(meta: MediaMeta): Promise<void> {
    if (!this.sessionId || !this.connected || this.sending || this.loadingChat || this.busy || this.voice?.active) return
    const connection = this.connectionVersion, chat = this.chatVersion, session = this.sessionId
    this.sending = true; this.errorText = ''
    try {
      const catalog = await loadMediaCatalog(this.client)
      if (connection !== this.connectionVersion || chat !== this.chatVersion || session !== this.sessionId) return
      const prompt = regenerateMediaMessage(meta, catalog)
      if (!prompt) {
        this.mediaParams = mediaParamsFromMeta(meta, catalog)
        this.draft = this.draft.trim() ? this.draft + '\n\n' + meta.prompt : meta.prompt
        this.page = 'mediaGenerate'
        return
      }
      await this.client.prompt(session, prompt)
      this.recordUsage('turns'); this.recordUsage('gen')
    } catch (error) {
      if (connection === this.connectionVersion && chat === this.chatVersion) this.errorText = (error as Error).message
    } finally { if (connection === this.connectionVersion && chat === this.chatVersion) this.sending = false }
  }

  private regenerationPrompt(reply: DshMessage): DshMessage | undefined {
    if (!this.connected || this.loadingChat || this.sending || this.busy || this.regenerating || this.voice?.active ||
      this.withdrawingAttachmentSessions.includes(this.sessionId)) return undefined
    return regenerablePrompt(this.messages, this.records, reply, this.running, this.queuedPrompts.length)
  }

  private async regenerateReply(reply: DshMessage): Promise<void> {
    const prompt = this.regenerationPrompt(reply)
    if (!prompt || prompt.seq === undefined) return
    const source = this.sessionId
    const connection = this.connectionVersion
    const identity = this.client.connectionIdentity()
    const chat = this.chatVersion
    const operation = ++this.regenerationVersion
    const current = (): boolean => operation === this.regenerationVersion && identity === this.client.connectionIdentity() &&
      connection === this.connectionVersion && chat === this.chatVersion && source === this.sessionId &&
      regenerablePrompt(this.messages, this.records, reply, this.running, this.queuedPrompts.length)?.id === prompt.id
    let images: DraftAttachment[] = []
    this.regenerating = true
    this.errorText = ''
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      images = await resendImages(this.client, source, prompt, context.cacheDir, current)
      if (!current()) return
      const fork = await forkBeforePrompt(this.client, source, prompt.seq, this.records, this.sessionTitle, current)
      if (!fork || !current()) return
      const originalTitle = this.sessionTitle
      const capturedImages = images
      this.composerDrafts.write(fork.sessionId, prompt.text)
      if (images.length) this.attachmentDrafts.set(fork.sessionId, images)
      images = []
      const opening = this.openSession(fork.sessionId, fork.title || this.t("新对话"), operation)
      const childChat = this.chatVersion
      await opening
      if (operation !== this.regenerationVersion || identity !== this.client.connectionIdentity() ||
        connection !== this.connectionVersion || childChat !== this.chatVersion || this.sessionId !== fork.sessionId) return
      this.regenerationSourceId = source
      this.regenerationSourceTitle = originalTitle
      if (fork.leftQueued || this.queuedPrompts.length || this.running) {
        this.errorText = this.t("分支中还有排队消息，请检查后再发送。")
        return
      }
      if (this.draft !== prompt.text || this.draftAttachments.length !== capturedImages.length ||
        !this.draftAttachments.every((file: DraftAttachment, index: number) => file.id === capturedImages[index].id)) {
        this.errorText = this.t("分支草稿已修改，请确认后发送。")
        return
      }
      this.regenerating = false
      await this.send(false)
    } catch (error) {
      if (operation === this.regenerationVersion && identity === this.client.connectionIdentity() &&
        connection === this.connectionVersion && chat === this.chatVersion) {
        this.errorText = this.errorMessage(error as Error, this.t("重新回答失败，请稍后重试。"))
      }
    } finally {
      if (images.length) await deleteAttachments(images)
      if (operation === this.regenerationVersion) this.regenerating = false
    }
  }

  private async sendAttachmentDraft(id: string, value: string, files: DraftAttachment[], chat: number,
    connection: number): Promise<void> {
    const current = (): boolean => chat === this.chatVersion && connection === this.connectionVersion && id === this.sessionId
    const key = `${id}/${JSON.stringify([value, files.map((file: DraftAttachment) => file.id)])}`
    const request = this.attachmentRequestIds.get(key) || util.generateRandomUUID()
    this.attachmentRequestIds.set(key, request)
    const asFiles = await this.client.promptWithAttachments(id, value, files, request, current, this.transportKind !== 'relay')
    if (connection !== this.connectionVersion) return
    this.attachmentRequestIds.delete(key)
    if (!this.queuedAttachmentDrafts.some((item: QueuedAttachmentDraft) => item.sessionId === id && item.requestId === request)) {
      this.queuedAttachmentDrafts = this.queuedAttachmentDrafts.concat({ sessionId: id, requestId: request, files: files })
    }
    const remaining = (this.attachmentDrafts.get(id) || []).filter((file: DraftAttachment) =>
      !files.some((sent: DraftAttachment) => sent.id === file.id))
    if (remaining.length) this.attachmentDrafts.set(id, remaining)
    else this.attachmentDrafts.delete(id)
    if (this.sessionId === id) {
      this.draftAttachments = remaining
      this.releaseCommittedAttachments(id, this.messages)
    }
    if (current()) {
      if (asFiles) this.errorText = this.t("当前模型不支持图片，已作为文件发送。")
      this.scrollToLatest(chat)
    }
  }

  private releaseCommittedAttachments(id: string, messages: DshMessage[]): void {
    if (!this.queuedAttachmentDrafts.length) return
    const remaining = this.queuedAttachmentDrafts.filter((item: QueuedAttachmentDraft) => {
      if (item.sessionId !== id || !messages.some((message: DshMessage) =>
        message.role === 'user' && message.requestId === item.requestId)) return true
      // An inbox removal can precede an echo or be part of steering.
      void deleteAttachments(item.files)
      return false
    })
    if (remaining.length !== this.queuedAttachmentDrafts.length) this.queuedAttachmentDrafts = remaining
  }

  private async withdrawAttachmentPrompt(id: string, connection: number, item: DshQueuedPrompt): Promise<void> {
    if (connection !== this.client.connectionIdentity() || this.withdrawingAttachmentSessions.includes(id) ||
      (id === this.sessionId && (this.sending || this.choosingAttachments || this.voice?.active))) return
    this.withdrawingAttachmentSessions = this.withdrawingAttachmentSessions.concat(id)
    try {
      await this.client.updateQueue(id, item.id, 'remove')
      this.recoverQueueDrafts(id, connection, [item])
    } finally {
      if (connection === this.client.connectionIdentity()) {
        this.withdrawingAttachmentSessions = this.withdrawingAttachmentSessions.filter((session: string) => session !== id)
      }
    }
  }

  private async sendQueuedImmediately(id: string, connection: number, item: DshQueuedPrompt): Promise<DshQueueMoveResult> {
    if (connection !== this.client.connectionIdentity() || this.withdrawingAttachmentSessions.includes(id) ||
      (id === this.sessionId && (this.sending || this.choosingAttachments || this.voice?.active))) return { sent: false, recoverable: [] }
    const drafts = this.queuedAttachmentDrafts.filter((entry: QueuedAttachmentDraft) => entry.sessionId === id)
    this.withdrawingAttachmentSessions = this.withdrawingAttachmentSessions.concat(id)
    try {
      const result = await this.client.sendQueuedNow(id, item.id,
        (requestId: string): DraftAttachment[] => drafts.find((entry: QueuedAttachmentDraft) => entry.requestId === requestId)?.files || [],
        this.transportKind !== 'relay')
      if (connection === this.client.connectionIdentity() && result.recoverable.length) {
        this.recoverQueueMove(id, result.recoverable)
      }
      return { sent: result.sent, recoverable: [], error: result.error }
    } finally {
      if (connection === this.client.connectionIdentity()) {
        this.withdrawingAttachmentSessions = this.withdrawingAttachmentSessions.filter((session: string) => session !== id)
      }
    }
  }

  private recoverQueueMove(id: string, items: DshQueuedPrompt[]): void {
    const active = id === this.sessionId
    if (active) void this.voice?.cancel()
    if (active) this.composerDrafts.write(id, this.draft)
    const text = items.map((item: DshQueuedPrompt) => item.text).filter((value: string) => !!value).join('\n\n')
    const recovered = text ? this.composerDrafts.append(id, text) : this.composerDrafts.read(id)
    let files = this.attachmentDrafts.get(id) || []
    this.queuedAttachmentDrafts = this.queuedAttachmentDrafts.filter((entry: QueuedAttachmentDraft) => {
      if (entry.sessionId !== id || !items.some((item: DshQueuedPrompt) => item.requestId === entry.requestId)) return true
      files = files.concat(entry.files.filter((file: DraftAttachment) => !files.some((previous: DraftAttachment) => previous.id === file.id)))
      return false
    })
    if (files.length) this.attachmentDrafts.set(id, files)
    if (active) {
      this.draft = recovered
      this.draftAttachments = files
      this.errorText = this.t("发送失败，消息与附件已放回输入框。")
    }
  }

  private recoverQueueDrafts(id: string, connection: number, items: DshQueuedPrompt[]): void {
    if (connection !== this.client.connectionIdentity()) return
    if (id === this.sessionId) void this.voice?.cancel()
    const active = id === this.sessionId
    const text = items.map((item: DshQueuedPrompt) => item.text).filter((value: string) => !!value).join('\n\n')
    const cached = this.queuedAttachmentDrafts.find((entry: QueuedAttachmentDraft) => entry.sessionId === id &&
      items.some((item: DshQueuedPrompt) => item.hasAttachments === true && item.requestId === entry.requestId))
    if (active) this.composerDrafts.write(id, this.draft)
    if (!cached) {
      if (!text) return
      const recovered = this.composerDrafts.append(id, text)
      if (active) {
        this.draft = recovered
        this.errorText = this.t("排队消息已放回输入框，请检查后再发送。")
      }
      return
    }
    this.queuedAttachmentDrafts = this.queuedAttachmentDrafts.filter((entry: QueuedAttachmentDraft) =>
      entry.sessionId !== id || entry.requestId !== cached.requestId)
    const oldText = this.composerDrafts.read(id)
    const oldFiles = this.attachmentDrafts.get(id) || []
    const canRestore = active || (!oldText && !oldFiles.length)
    const restoreText = canRestore && !oldText.trim() && !!text
    const restoreFiles = canRestore && !oldFiles.length
    if (restoreText) this.composerDrafts.write(id, text)
    if (restoreFiles) this.attachmentDrafts.set(id, cached.files)
    else void deleteAttachments(cached.files)
    if (active) {
      if (restoreText) this.draft = text
      if (restoreFiles) this.draftAttachments = cached.files
      this.errorText = restoreText || restoreFiles ? this.t("已撤回，可修改后再发") : this.t("已撤回")
    }
  }

  private changeAttachmentDraft(nextId: string): void {
    if (this.draftAttachments.length) this.attachmentDrafts.set(this.sessionId, this.draftAttachments)
    this.draftAttachments = this.attachmentDrafts.get(nextId) || []
    this.choosingAttachments = false
    this.clearAttachmentPreview()
  }

  private clearAttachments(): void {
    this.attachmentDrafts.forEach((items: DraftAttachment[]) => { void deleteAttachments(items) })
    this.attachmentDrafts.clear()
    this.attachmentRequestIds.clear()
    this.queuedAttachmentDrafts.forEach((item: QueuedAttachmentDraft) => { void deleteAttachments(item.files) })
    this.queuedAttachmentDrafts = []
    this.withdrawingAttachmentSessions = []
    this.draftAttachments = []
    this.choosingAttachments = false
    this.clearAttachmentPreview()
  }

  private async chooseAttachments(kind: string): Promise<void> {
    if (!this.connected || this.choosingAttachments || this.sending || this.busy || this.voice?.active ||
      this.withdrawingAttachmentSessions.includes(this.sessionId)) return
    const remaining = MAX_ATTACHMENTS - this.draftAttachments.length
    if (remaining <= 0) { this.errorText = this.t("每条消息最多添加 9 个附件。"); return }
    const used = this.draftAttachments.reduce((sum: number, file: DraftAttachment) => sum + file.size, 0)
    const chat = this.chatVersion
    const connection = this.connectionVersion
    const current = (): boolean => chat === this.chatVersion && connection === this.connectionVersion
    this.choosingAttachments = true
    this.errorText = ''
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const files = await pickAttachments(context, kind, remaining, MAX_ATTACHMENT_TOTAL - used, current)
      if (!current()) { await deleteAttachments(files); return }
      if (files.length) {
        this.draftAttachments = this.draftAttachments.concat(files)
        this.attachmentDrafts.set(this.sessionId, this.draftAttachments)
      }
    } catch (error) {
      if (current()) this.errorText = this.errorMessage(error as Error, this.t("无法添加附件，请重新选择。"))
    } finally { if (current()) this.choosingAttachments = false }
  }

  private removeAttachment(file: DraftAttachment): void {
    if (this.sending) return
    this.draftAttachments = this.draftAttachments.filter((item: DraftAttachment) => item.id !== file.id)
    this.attachmentDrafts.set(this.sessionId, this.draftAttachments)
    void deleteAttachments([file])
  }

  private messageImages(content: WireObject[]): GalleryImage[] {
    return messageAttachments(content).filter((file: DshAttachmentRef) => file.kind === 'image')
      .map((file: DshAttachmentRef, index: number): GalleryImage => {
        return { key: `${index}/${file.id}/${file.name}`, name: file.name, reference: file.reference }
      })
  }

  private openDraftGallery(id: string): void {
    const items = this.draftAttachments.filter((file: DraftAttachment) => !!file.mediaType)
      .map((file: DraftAttachment): GalleryImage => { return { key: file.id, name: file.name, path: file.path } })
    this.openAttachmentGallery(items, items.findIndex((item: GalleryImage) => item.key === id))
  }

  private openAttachmentGallery(items: GalleryImage[], index: number): void {
    if (!items[index] || this.page !== 'chat') return
    this.galleryIndex = index
    this.galleryItems = items
    this.page = 'attachmentPreview'
  }

  private clearAttachmentPreview(): void { this.galleryItems = [] }

  private closeAttachmentPreview(): void {
    this.page = 'chat'
    this.clearAttachmentPreview()
  }

  private async loadCommandCatalog(): Promise<void> {
    const id = this.sessionId
    const chat = this.chatVersion
    const connection = this.connectionVersion
    const version = ++this.catalogVersion
    const current = (): boolean => version === this.catalogVersion && chat === this.chatVersion &&
      connection === this.connectionVersion && id === this.sessionId
    await Promise.all([
      this.client.listCommands(id).then((commands: DshCommand[]) => {
        if (current()) this.hostCommands = commands
      }).catch(() => {}),
      this.client.listSkills(id).then((skills: WireObject[]) => {
        if (current()) this.sessionSkills = skills
      }).catch(() => {})
    ])
  }

  private async sendSlash(rawDraft: string): Promise<boolean> {
    const input = slashInput(rawDraft)
    if (!input) return false
    if (!input.token && input.rest === undefined) return true
    let commands = slashCommands(this.hostCommands, this.sessionSkills)
    let exact = resolveSlash(commands, input.token)
    if (!exact && this.commandCatalog) {
      const chat = this.chatVersion
      await this.commandCatalog
      if (chat !== this.chatVersion || this.draft !== rawDraft) return true
      commands = slashCommands(this.hostCommands, this.sessionSkills)
      exact = resolveSlash(commands, input.token)
    }
    if (exact?.kind === 'skill') return false
    if (exact) {
      await this.runSlash(exact, `/${exact.name}${input.rest || ''}`.trim(), rawDraft)
      return true
    }
    if (input.rest === undefined) {
      const match = filterSlash(commands, input.token)[0]
      if (match) { await this.pickSlash(match); return true }
    }
    if (['compact', this.t("压缩")].includes(input.token.toLowerCase())) {
      this.errorText = this.sessionId ? this.t("当前对话没有提供压缩命令。") : this.t("请先打开要压缩的对话。")
      return true
    }
    return false
  }

  private slashChoices(): SlashCommand[] {
    const input = slashInput(this.draft)
    if (!input || input.rest !== undefined) return []
    return filterSlash(slashCommands(this.hostCommands, this.sessionSkills), input.token)
  }

  private slashHint(): string {
    const input = slashInput(this.draft)
    if (input?.rest === undefined || input.rest.trim()) return ''
    return resolveSlash(slashCommands(this.hostCommands, this.sessionSkills), input.token)?.hint || ''
  }

  private compactCommand(): SlashCommand | undefined {
    return slashCommands(this.hostCommands, []).find((command: SlashCommand) => command.name === 'compact' &&
      (!command.definitionId || command.definitionId === '@deepseek-ai/dsh-command-compact'))
  }

  private async pickSlash(item: SlashCommand): Promise<void> {
    if (this.loadingChat || this.sending || this.busy) return
    if (item.kind === 'skill' || item.hint !== undefined) {
      this.draft = `/${item.name} `
    } else {
      await this.runSlash(item, `/${item.name}`, this.draft)
    }
  }

  private async runSlash(item: SlashCommand, line: string, rawDraft?: string): Promise<void> {
    if (!this.connected || this.loadingChat || this.sending || this.busy) return
    if (item.kind === 'app') {
      if (item.name === 'export' && !this.sessionId) {
        this.errorText = this.t("请先打开要导出的对话。")
        return
      }
      this.clearCommandDraft(rawDraft)
      if (item.name === 'new') this.home()
      else if (item.name === 'model') await this.showModels()
      else if (item.name === 'features') this.page = 'features'
      else { this.exportOrigin = 'chat'; this.page = 'sessionExport' }
      return
    }
    if (!this.sessionId) return
    const version = this.chatVersion
    const connection = this.connectionVersion
    const id = this.sessionId
    this.sending = true
    this.errorText = ''
    try {
      if (!await this.applyPendingModel(id, connection)) return
      if (version !== this.chatVersion || connection !== this.connectionVersion) return
      if (rawDraft !== undefined && this.draft !== rawDraft) return
      if (!this.hostCommands.some((command: DshCommand) => command.name === item.name &&
        command.definitionId === item.definitionId)) {
        this.errorText = this.t("当前对话的命令已变化，请重新选择。")
        return
      }
      if (item.name === 'compact' && (!item.definitionId || item.definitionId === '@deepseek-ai/dsh-command-compact') &&
        (this.running || this.queuedPrompts.length > 0)) {
        this.errorText = this.t("请等当前生成与排队消息结束后再压缩。")
        return
      }
      const result = await this.client.executeCommand(id, line)
      if (version === this.chatVersion && connection === this.connectionVersion) {
        if (result.success) this.clearCommandDraft(rawDraft)
        this.scrollToLatest(version)
      }
    } catch {
      if (version === this.chatVersion && connection === this.connectionVersion) {
        this.errorText = this.t("未能确认命令结果，请查看对话记录。")
      }
    } finally {
      if (version === this.chatVersion && connection === this.connectionVersion) this.sending = false
    }
  }

  private clearCommandDraft(rawDraft?: string): void {
    if (rawDraft === undefined || this.draft !== rawDraft) return
    this.draft = ''
    this.composerDrafts.write(this.sessionId, '')
  }

  private canRecoverTurn(notice: DshTurnNotice): boolean {
    return this.connected && !!this.sessionId && !this.running && !this.loadingChat && !this.sending &&
      !this.busy && this.queuedPrompts.length === 0 &&
      !this.submittedRecoveries.includes(`${this.connectionVersion}/${this.sessionId}/${notice.seq}`) &&
      this.turnNotices.some((current: DshTurnNotice) =>
        current.seq === notice.seq && current.kind === notice.kind && current.actionable === true &&
        current.recovery === notice.recovery && current.retryText === notice.retryText)
  }

  private async recoverTurn(notice: DshTurnNotice): Promise<void> {
    if (!notice.recovery || !this.canRecoverTurn(notice)) return
    const text = notice.recovery === 'continue' ? this.t("继续") : notice.retryText
    if (!text) return
    const id = this.sessionId
    const chatVersion = this.chatVersion
    const connectionVersion = this.connectionVersion
    const key = `${connectionVersion}/${id}/${notice.seq}`
    const requestId = this.recoveryRequestIds.get(key) || util.generateRandomUUID()
    this.recoveryRequestIds.set(key, requestId)
    this.sending = true
    this.errorText = ''
    try {
      await this.client.prompt(id, text, requestId)
      this.recordUsage('turns')
      if (connectionVersion === this.connectionVersion) this.submittedRecoveries = this.submittedRecoveries.concat(key)
    } catch {
      if (chatVersion === this.chatVersion && connectionVersion === this.connectionVersion) {
        this.errorText = this.t("尚未确认恢复请求是否送达。可先查看对话，再重试同一次请求。")
      }
    } finally {
      if (chatVersion === this.chatVersion && connectionVersion === this.connectionVersion) this.sending = false
    }
  }

  private async stop(): Promise<void> {
    if (this.stopping || !(this.running || (this.sending && this.compacting))) {
      return
    }
    this.stopping = true
    const version = this.chatVersion
    this.errorText = ''
    try {
      await this.client.cancel(this.sessionId)
    } catch (error) {
      if (version === this.chatVersion) {
        this.errorText = this.errorMessage(error as Error, this.t("停止请求失败。"))
      }
    } finally {
      if (version === this.chatVersion) {
        this.stopping = false
      }
    }
  }

  private async decide(id: string, allow: boolean): Promise<void> {
    if (this.deciding || this.approval?.id !== id) {
      return
    }
    const version = this.chatVersion
    this.deciding = true
    this.errorText = ''
    try {
      await this.client.approve(id, allow)
    } catch (error) {
      if (version === this.chatVersion) {
        this.errorText = this.errorMessage(error as Error, this.t("未能提交审批，请确认主机状态。"))
      }
    } finally {
      if (version === this.chatVersion) {
        this.deciding = false
      }
    }
  }

  private openFeature(kind: string): void {
    this.featureOrigin = this.page === 'detail' ? 'detail' : 'features'
    this.featureKind = kind
    this.drawer = false
    this.page = 'engineFeatures'
  }

  private activeCwd(): string {
    return this.sessions.find((item: DshSession) => item.id === this.sessionId)?.cwd ||
      this.workspaces.find((item: DshWorkspace) => item.id === this.workspaceId)?.path || (this.mode === 'local' ? this.localWorkspace : '')
  }

  private timeline(): ChatRow[] {
    const turns = turnTraces(this.records)
    return foldedTurns(this.chatTimeline.update(this.sessionId, this.messages, this.tools, this.turnNotices, this.commandNotices,
      sessionArtifacts(this.records, this.activeCwd()), turns), turns, this.advanced.foldCompletedTurns)
  }

  private showDetail(tab: string = 'trajectory'): void { this.detailTab = tab; this.page = 'detail' }
  private showFiles(): void { this.artifactPath = ''; this.filesOrigin = this.page === 'detail' ? 'detail' : 'chat'; this.page = 'files' }

  @State private expandedProcesses: string[] = []
  private chatTimeline: ChatTimeline = new ChatTimeline()

  private toggleReasoning(id: string): void {
    this.expandedReasoning = this.expandedReasoning.includes(id) ? this.expandedReasoning.filter((item: string) => item !== id) : this.expandedReasoning.concat(id)
  }

  private toggleTool(id: string): void {
    this.expandedTools = this.expandedTools.includes(id) ? this.expandedTools.filter((item: string) => item !== id) : this.expandedTools.concat(id)
  }

  private switchHost(mode: string): void {
    if (this.busy || this.switchingHost) return
    if (mode === 'remote') { this.showRemoteHosts(); return }
    if (this.connected && this.mode === 'local') { this.page = 'chat'; return }
    void this.disconnect(false).then(() => {
      this.mode = 'local'
      if (this.localConfigured || this.hasSavedKey) void this.connect()
      else if (this.engineReady) void this.connect(undefined, undefined, false, true)
    })
  }

  private showRemoteHosts(): void {
    if (this.busy) return
    this.remoteOrigin = this.page === 'onboarding' ? 'onboarding' : (this.connected ? 'chat' : 'connect')
    this.drawer = false; this.errorText = ''; this.page = 'remoteHosts'
  }

  private closeRemoteHosts(): void {
    if (this.busy) return
    this.page = this.connected ? 'chat' : this.remoteOrigin
    if (!this.connected) this.mode = 'local'
    this.errorText = ''
  }

  private async openTransportControl(): Promise<TransportControl> {
    if (this.busy) throw new Error(this.t("本机连接服务正在初始化。"))
    const version = this.connectionVersion
    this.busy = true
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const endpoint = await this.localEngine.start(context, (message: string) => {
        if (version === this.connectionVersion) this.localStage = message
      })
      if (version !== this.connectionVersion) {
        await this.localEngine.stop()
        throw new Error(this.t("连接已取消。"))
      }
      this.engineReady = true; void this.usage?.engine('direct').catch(() => {})
      if (!endpoint.transportControl) throw new Error(this.t("请停止并重新启动本机引擎后重试。"))
      return endpoint.transportControl
    } finally {
      if (version === this.connectionVersion) { this.localStage = ''; this.busy = false }
    }
  }

  private releaseTransport(): void {
    const transport = this.transport
    this.transport = undefined
    this.transportKind = ''
    this.relayRoute = ''
    if (transport) void transport.close().catch(() => {})
  }

  private async connectTransport(endpoint: TransportEndpoint, kind: string): Promise<boolean> {
    const panel = kind === 'ssh' ? 'sshHosts' : 'relayHosts'
    if (this.busy || this.switchingHost || this.page !== panel) return false
    this.switchingHost = true
    try {
      await this.disconnect(false, panel)
      this.mode = 'remote'
      this.transport = endpoint
      this.transportKind = kind
      this.relayRoute = endpoint.route || ''
      this.remoteHostId = endpoint.scope || kind
      this.remoteHostScope = endpoint.scope || kind
      this.address = endpoint.launchUrl
      this.authorization = endpoint.authorization || ''
      const success = await this.connect()
      if (!success && this.transport === endpoint) {
        this.releaseTransport()
        this.remoteHostId = ''
        this.remoteHostScope = ''
        this.page = panel
      }
      return success
    } finally {
      this.address = ''; this.authorization = ''; this.switchingHost = false
    }
  }

  private async connectRemote(connection: RemoteHostConnection): Promise<boolean> {
    if (this.busy || this.switchingHost) return false
    this.switchingHost = true
    try {
      await this.disconnect(false, 'remoteHosts')
      this.mode = 'remote'
      this.address = connection.launchUrl
      this.authorization = connection.authorization
      this.remoteHostId = connection.id
      this.remoteHostScope = connection.launchUrl.split(/[?#]/)[0]
      const success = await this.connect()
      if (success) {
        this.remoteHostId = connection.id; this.host = connection.name
        this.remoteHostScope = connection.launchUrl.split(/[?#]/)[0]
      } else { this.remoteHostId = ''; this.remoteHostScope = ''; this.page = 'remoteHosts' }
      return success
    } finally {
      this.address = ''; this.authorization = ''; this.switchingHost = false
    }
  }

  private async stopLocalEngine(stayInSettings: boolean = false): Promise<boolean> {
    if (this.busy) return false
    if (this.transport) { this.errorText = this.t("请先断开当前远程连接。"); return false }
    if (this.mode === 'local') { await this.disconnect(true, stayInSettings ? 'settings' : 'connect'); return !this.errorText }
    this.busy = true
    try {
      await this.localEngine.stop()
      this.engineReady = false; this.localConfigured = false; this.localWorkspace = ''
      return true
    } catch { this.errorText = this.t("本机引擎未能停止，请重试。"); return false }
    finally { this.busy = false }
  }

  private async restartForMaintenance(): Promise<void> {
    if (!await this.stopLocalEngine(true)) throw new Error(this.t("本机引擎未能停止"))
    if (this.mode === 'local') {
      if (!await this.connect(undefined, undefined, true, !this.hasSavedKey, true)) throw new Error(this.t("本机引擎未能重连"))
    } else {
      this.busy = true
      try {
        const endpoint = await this.localEngine.start(this.getUIContext().getHostContext() as common.UIAbilityContext,
          (message: string) => { this.localStage = message })
        this.engineReady = true; void this.usage?.engine('direct').catch(() => {}); this.localWorkspace = endpoint.workspaceDir; this.localStage = this.t("本机引擎运行中")
      } finally { this.busy = false }
    }
  }

  @Builder
  private iconButton(glyph: string, label: string, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      Text(glyph).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text)
    }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText(label).onClick(action)
  }

  @Builder
  private notice() {
    if (this.page === 'chat' && this.voiceNotice) {
      Row({ space: 8 }) {
        Text(this.t(this.voiceNotice)).fontSize(14).fontColor(this.colors.muted).layoutWeight(1)
        if (this.voiceSettingsAction) {
          Button(this.t("前往设置")).fontSize(13).fontColor(this.colors.primary).backgroundColor(Color.Transparent)
            .onClick(() => { void this.voiceBridge?.openSettings().catch(() => {
              this.voiceNotice = this.t("没能打开麦克风设置，请稍后重试。")
            }) })
        } else if (this.voiceModeAction) {
          Button(this.t("更换")).fontSize(13).fontColor(this.colors.primary).backgroundColor(Color.Transparent)
            .onClick(() => this.showSettings('speech'))
        }
        Button('×').fontSize(20).fontColor(this.colors.muted).backgroundColor(Color.Transparent)
          .width(36).height(36).accessibilityText(this.t("关闭语音提示")).onClick(() => this.voiceNotice = '')
      }.width('100%').padding(12).backgroundColor(this.colors.surface).borderRadius(14)
    }
    if (this.credentialNotice) {
      Row({ space: 8 }) {
        Text(this.t(this.credentialNotice)).fontSize(14).fontColor(this.colors.warning).layoutWeight(1)
        Button('×').fontSize(20).fontColor(this.colors.warning).backgroundColor(Color.Transparent)
          .width(36).height(36).accessibilityText(this.t("关闭密钥提示")).onClick(() => this.credentialNotice = '')
      }.width('100%').padding(12).backgroundColor(this.colors.surface).borderRadius(14)
    }
    if (this.errorText) {
      Row({ space: 8 }) {
        Text(this.t(this.errorText)).fontSize(14).fontColor(this.colors.danger).layoutWeight(1)
        Button('×').fontSize(20).fontColor(this.colors.danger).backgroundColor(Color.Transparent)
          .width(36).height(36).accessibilityText(this.t("关闭提示")).onClick(() => this.errorText = '')
      }.width('100%').padding(12).backgroundColor(this.colors.surface).borderRadius(14)
    }
    if (this.page === 'chat' && this.sessionError && !this.errorText) {
      Row({ space: 8 }) {
        Text(this.sessionError).fontSize(14).fontColor(this.colors.danger).layoutWeight(1)
        Button('×').fontSize(20).fontColor(this.colors.danger).backgroundColor(Color.Transparent)
          .width(36).height(36).accessibilityText(this.t("关闭会话提示")).onClick(() => this.client.dismissSessionError(this.sessionId))
      }.width('100%').padding(12).backgroundColor(this.colors.surface).borderRadius(14)
    }
  }

  @Builder
  private connectScreen() {
    Scroll() {
      Column({ space: 24 }) {
        Row() {
          Blank()
          this.iconButton(DshGlyphs.settings, this.t("设置"), () => this.showSettings())
        }.width('100%')
        Column({ space: 14 }) {
          Image($r('app.media.app_icon')).width(76).height(76).objectFit(ImageFit.Contain).borderRadius(16)
          Text($r('app.string.app_name')).fontSize(36).fontWeight(FontWeight.Bold).fontColor(this.colors.text)
          Text(this.t("在鸿蒙上运行或连接\nDeepSeek Harness")).fontSize(17).fontColor(this.colors.muted).textAlign(TextAlign.Center)
        }.width('100%').padding({ top: 20, bottom: 12 })
        Column({ space: 18 }) {
          Text(this.t("DSH 在哪里运行？")).fontSize(21).fontWeight(FontWeight.Medium).fontColor(this.colors.text)
          Row({ space: 10 }) {
            this.modeButton('local', this.t("本机"))
            this.modeButton('remote', this.t("远程主机"))
          }.width('100%')
          if (this.mode === 'local') {
            Text(this.t("连接 DeepSeek")).fontSize(18).fontColor(this.colors.text).width('100%')
            Text('API Key').fontSize(13).fontColor(this.colors.muted).width('100%')
            TextInput({ placeholder: this.hasSavedKey ? this.t("已安全保存，留空使用已保存的 Key") : this.t("输入 DeepSeek API Key"), text: this.modelKey })
              .type(InputType.Password).height(50).fontSize(16).fontColor(this.colors.text)
              .backgroundColor(this.colors.surfaceAlt).enableAutoFill(false).enabled(!this.busy)
              .maxLength(1024)
              .accessibilityText('DeepSeek API Key').onChange((value: string) => this.modelKey = value)
            Row({ space: 8 }) {
              Checkbox({ name: 'rememberKey' }).select(this.rememberKey).selectedColor(this.colors.primary)
                .enabled(!this.busy).onChange((selected: boolean) => this.rememberKey = selected)
              Text(this.t("安全保存 API Key")).fontSize(14).fontColor(this.colors.text)
            }.width('100%')
            Text(this.t("勾选后由鸿蒙安全资产存储保护，下次启动可直接使用。")).fontSize(12).fontColor(this.colors.muted)
            if (this.hasSavedKey) {
              Button(this.t("删除已保存的 Key")).fontSize(13).fontColor(this.colors.danger).backgroundColor(Color.Transparent)
                .enabled(!this.busy).onClick(() => { void this.forgetKey() })
            }
            if (this.credentialNotice) {
              Button(this.t("重新检查已保存的 Key")).fontSize(13).fontColor(this.colors.primary).backgroundColor(Color.Transparent)
                .enabled(!this.busy).onClick(() => { void this.refreshSavedKey() })
            }
          } else {
            Text(this.t("连接主机")).fontSize(18).fontColor(this.colors.text).width('100%')
            TextInput({ placeholder: this.t("DSH 启动链接"), text: this.address }).type(InputType.URL)
              .height(50).fontSize(15).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
              .enableAutoFill(false).enabled(!this.busy).onChange((value: string) => this.address = value)
            TextInput({ placeholder: this.t("反向代理授权（可选）"), text: this.authorization }).type(InputType.Password)
              .height(50).fontSize(15).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
              .enableAutoFill(false).enabled(!this.busy).onChange((value: string) => this.authorization = value)
          }
          this.notice()
          if (this.busy) { LoadingProgress().width(32).height(32).color(this.colors.primary) }
          Button(this.busy ? (this.localStage || this.t("连接中…")) : (this.mode === 'local' ? this.t("启动本机引擎") : this.t("连接主机")))
            .width('100%').height(48).fontColor(this.colors.onPrimary).backgroundColor(this.colors.primary)
            .enabled(!this.busy && (this.mode === 'local' ? !!this.modelKey.trim() || this.hasSavedKey || this.localConfigured : !!this.address.trim()))
            .onClick(() => { void this.connect() })
          if (this.mode === 'local') {
            Button(this.t("使用 DeepSeek 账号")).height(46).width('100%').fontColor(this.colors.primary)
              .backgroundColor(this.colors.surfaceAlt).enabled(!this.busy).onClick(() => { void this.openLocalAccount() })
          }
        }.alignItems(HorizontalAlign.Start).padding(24).width('100%').backgroundColor(this.colors.surface).borderRadius(24)
        Text(this.mode === 'local' ? this.t("DeepSeek Harness 在本机运行，模型回复需要联网。") : this.t("文件、命令和任务在当前连接的电脑上执行。"))
          .fontSize(13).fontColor(this.colors.hint).textAlign(TextAlign.Center)
      }.width('100%').constraintSize({ maxWidth: 560 }).padding(24)
    }.width('100%').height('100%').align(Alignment.Top)
  }

  @Builder
  private modeButton(mode: string, label: string) {
    Button(label, { type: ButtonType.Normal }).height(48).layoutWeight(1).borderRadius(16)
      .backgroundColor(this.mode === mode ? this.colors.primaryContainer : this.colors.surfaceAlt)
      .fontColor(this.mode === mode ? this.colors.onPrimaryContainer : this.colors.muted)
      .enabled(!this.busy).onClick(() => {
        if (mode === 'remote') { this.showRemoteHosts(); return }
        this.mode = mode; this.modelKey = ''; this.errorText = ''
      })
  }

  @Builder
  private sessionDrawer() {
    SessionsPanel({ colors: this.colors, client: this.client, searchRequest: this.searchRequest, onSearchConsumed: () => { this.searchRequest = 0 }, excludedIds: this.hiddenSessionIds(), sessions: this.sessions.filter((session: DshSession) => !this.hiddenSessionIds().includes(session.id)), hostScope: this.hostScope(),
      workspaces: this.workspaces, workspaceId: this.workspaceId, selectedId: this.sessionId,
      host: this.mode === 'local' ? this.t("本机") : this.host, refreshing: this.refreshing,
      onSelect: (id: string, title: string) => { void this.openSession(id, title) },
      onNew: () => this.home(), onRefresh: () => { void this.refreshSessions() },
      onDeleted: (ids: string[]) => { if (ids.includes(this.sessionId)) this.home() },
      onBackHandler: (handler?: () => boolean) => { this.sessionsBack = handler },
      onWorkspaceSelect: (id: string) => { void this.selectWorkspace(id) },
      onSettings: () => this.showSettings(), onFeatures: () => { this.drawer = false; this.page = 'features' },
      onHost: () => this.showRemoteHosts(),
      onManageWorkspaces: () => { this.drawer = false; this.page = 'workspaces' }, onClose: () => this.drawer = false })
  }

  @Builder
  private approvalCard(item: DshApproval) {
    Column({ space: 10 }) {
      Text(this.t("需要你的确认")).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.colors.warning)
      Scroll() {
        Text(item.title).fontSize(14).fontColor(this.colors.text).width('100%').copyOption(CopyOptions.LocalDevice)
      }.width('100%').constraintSize({ maxHeight: 160 }).align(Alignment.TopStart)
      if (item.canAllow !== true) {
        Text(this.t("主机未提供足够的操作详情。")).fontSize(13).fontColor(this.colors.muted)
      }
      Row({ space: 10 }) {
        Button(this.t("拒绝")).height(44).layoutWeight(1).backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.danger)
          .enabled(!this.deciding).onClick(() => { void this.decide(item.id, false) })
        Button(this.t("允许本次")).height(44).layoutWeight(1).backgroundColor(this.colors.primary).fontColor(this.colors.onPrimary)
          .enabled(!this.deciding && item.canAllow === true).onClick(() => { void this.decide(item.id, true) })
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(16).backgroundColor(this.colors.surface).borderRadius(18)
  }

  @Builder
  private messageMenu(item: DshMessage) {
    Menu() {
      MenuItem({ content: this.t("复制") }).onClick(() => { void this.copyMessage(item.text) })
      MenuItem({ content: this.t("分享") }).onClick(() => { this.showShare([item.id]) })
      MenuItem({ content: this.t("引用") }).onClick(() => {
        void this.voice?.cancel()
        this.draft = item.text.split('\n').map((line: string) => `> ${line}`).join('\n') + '\n\n'
      })
      if (this.regenerationPrompt(item)) {
        MenuItem({ content: this.t("重新回答") }).onClick(() => { void this.regenerateReply(item) })
      }
    }
  }

  @Builder
  private messageRow(item: DshMessage) {
              Column({ space: 9 }) {
                if (item.role !== 'user') {
                  Row({ space: 8 }) {
                    Text(item.role === 'assistant' ? 'DeepSeek' : this.t("工具")).fontSize(13).fontWeight(FontWeight.Medium)
                      .fontColor(this.colors.muted).layoutWeight(1)
                    Button({ type: ButtonType.Circle }) {
                      Text(DshGlyphs.more).fontFamily(DshGlyphs.family).fontSize(18).fontColor(this.colors.hint)
                    }.width(36).height(36).backgroundColor(Color.Transparent).accessibilityText(this.t("消息操作"))
                      .bindMenu(this.messageMenu(item))
                  }.width('100%')
                }
                if (item.reasoning) {
                  Column({ space: 8 }) {
                    Button(this.expandedReasoning.includes(item.id) ? this.t("收起思考过程") : this.t("思考过程"), { type: ButtonType.Normal })
                      .height(36).fontSize(13).backgroundColor(Color.Transparent).fontColor(this.colors.muted)
                      .onClick(() => this.toggleReasoning(item.id))
                    CotReasoning({ text: item.reasoning, colors: this.colors, fontSize: this.fontSize - 1,
                      expanded: this.expandedReasoning.includes(item.id), client: this.client, sessionId: this.sessionId,
                      running: this.running && this.messages[this.messages.length - 1]?.id === item.id,
                      scope: `${this.connectionVersion}|${this.sessionId}`,
                      holder: this.cotTranslations.get(`${this.connectionVersion}|${this.sessionId}`, item.id),
                      onOpenSettings: () => this.showSettings('cot-translation') })
                  }.width('100%').alignItems(HorizontalAlign.Start).padding(10).backgroundColor(this.colors.surfaceAlt).borderRadius(12)
                }
                if (item.text) {
                  if (item.role === 'user') MentionMessage({ text: item.text, colors: this.colors, fontSize: this.fontSize,
                    labelsRevision: this.mentionLabelsRevision })
                  else MessageBody({ text: item.text, colors: this.colors, fontSize: this.fontSize, visualReplies: this.advanced.visualReplies,
                    onReply: (text: string) => this.sendVisualReply(item, text), replyState: this.visualState(item.id).state, replyText: this.visualState(item.id).text,
                    streaming: this.running && this.messages[this.messages.length - 1]?.id === item.id })
                }
                this.messageImageStrip(this.messageImages(item.content || []))
                ForEach(messageAttachments(item.content || []).filter((file: DshAttachmentRef) => file.kind !== 'image'),
                  (file: DshAttachmentRef) => {
                  Row({ space: 8 }) {
                    Text(DshGlyphs.file).fontFamily(DshGlyphs.family).fontSize(18).fontColor(this.colors.primary)
                    Text(file.name).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      .fontSize(14).fontColor(this.colors.text)
                    Text(`${(file.bytes / 1024).toFixed(1)} KiB`).fontSize(12).fontColor(this.colors.muted)
                  }.width('100%').padding(10).borderRadius(12).backgroundColor(this.colors.surface)
                }, (file: DshAttachmentRef, index: number) => `${index}/${file.id}/${file.name}/${file.offloaded}`)
                NativePluginActions({ colors: this.colors, client: this.client, surface: 'message.actions', message: item.text, scope: this.pluginScope(item.id),
                  onEffect: (effect: PluginEffect) => { void this.pluginEffect(effect) }, onOpenPanel: (place: PluginPlace) => { this.pluginSection = 'panels'; this.pluginPlace = place; this.page = 'nativePlugins' } })
                if (item.usage) {
                  Text(this.f("{0} 输入 · {1} 输出 tokens", [item.usage.inputTokens, item.usage.outputTokens])).fontSize(11).fontColor(this.colors.hint)
                }
              }.alignItems(HorizontalAlign.Start).width('100%').padding(item.role === 'user' ? 16 : 4)
                .backgroundColor(item.role === 'user' ? this.colors.bubble : Color.Transparent).borderRadius(20)
                .bindContextMenu(this.messageMenu(item), ResponseType.LongPress)
  }

  @Builder
  private chatRow(row: ChatRow) {
    if (row.message) this.messageRow(row.message)
    else if (row.artifacts) ArtifactCard({ colors: this.colors, items: row.artifacts,
      onOpen: (path: string) => { this.artifactPath = path; this.filesOrigin = 'chat'; this.page = 'files' } })
    else if (row.tools) this.toolGroup(row.tools)
    else if (row.tool) this.toolRow(row.tool, row.cardOnly === true, row.rowOnly === true)
    else if (row.notice) this.turnNoticeRow(row.notice)
    else if (row.command) this.commandRow(row.command)
  }

  @Builder
  private turnProcess(row: ChatRow) {
    Column({ space: 10 }) {
      Button(this.f("✓ 已完成{0}{1}", [row.processTools ? ' · ' + row.processTools + this.t(" 次工具调用") : '', row.processMessages ? ' · ' + row.processMessages + this.t(" 条消息") : '']))
        .fontSize(13).fontColor(this.colors.muted).backgroundColor(Color.Transparent).width('100%')
        .onClick(() => {
          const id = row.processId || ''
          this.expandedProcesses = this.expandedProcesses.includes(id) ? this.expandedProcesses.filter((value: string) => value !== id) : this.expandedProcesses.concat(id)
        })
      if (this.expandedProcesses.includes(row.processId || '')) {
        Column({ space: 12 }) { ForEach(row.process || [], (child: ChatRow) => { this.chatRow(child) }, (child: ChatRow) => child.key) }
          .width('100%').padding({ left: 12 }).border({ width: { left: 1 }, color: this.colors.border })
      }
    }.width('100%')
  }

  @Builder
  private toolGroup(items: DshTool[]) {
    Column({ space: 10 }) {
      Button(this.f("工具 · 已完成 {0}/{1} 项", [items.filter((item: DshTool) => item.result !== undefined).length, items.length]))
        .width('100%').fontSize(14).fontColor(this.colors.muted).backgroundColor(this.colors.surface).height(44)
        .onClick(() => {
          const key = items[0].callId
          this.expandedToolGroups = this.expandedToolGroups.includes(key) ?
            this.expandedToolGroups.filter((id: string) => id !== key) : this.expandedToolGroups.concat(key)
        })
      if (this.expandedToolGroups.includes(items[0].callId)) {
        ForEach(items, (item: DshTool) => { this.toolRow(item) }, (item: DshTool) => JSON.stringify(item))
      }
    }.width('100%')
  }

  @Builder
  private toolRow(item: DshTool, cardOnly: boolean = false, rowOnly: boolean = false) {
    Column({ space: 10 }) {
      if (!cardOnly) Row({ space: 10 }) {
        Text(item.isError ? '!' : (item.result === undefined ? '·' : '✓')).fontSize(16)
          .fontColor(item.isError ? this.colors.danger : this.colors.primary)
        Text(item.name).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.colors.text).layoutWeight(1)
        Text(this.expandedTools.includes(item.callId) ? '⌃' : '⌄').fontColor(this.colors.muted)
      }.width('100%').onClick(() => this.toggleTool(item.callId))
      if (!rowOnly && mediaMeta(item.meta)) {
        MediaResultCard({ colors: this.colors, client: this.client, sessionId: this.sessionId, meta: mediaMeta(item.meta)!,
          onOpen: (items: MediaItem[], index: number) => { this.mediaItems = items; this.mediaIndex = index; this.page = 'mediaViewer' },
          onRegenerate: (meta: MediaMeta) => { void this.regenerateMedia(meta) },
          onSettings: () => this.showSettings('media') })
      }
      if (!rowOnly && object(item.meta)['dsh-go/view']) NativePluginView({ colors: this.colors, view: object(item.meta)['dsh-go/view']!, budget: 'toolCard' })
      if (!cardOnly && this.expandedTools.includes(item.callId)) {
        if (item.arguments) {
          Text(item.arguments).fontFamily('JetBrainsMono').fontSize(12).fontColor(this.colors.muted)
            .width('100%').copyOption(CopyOptions.LocalDevice)
        }
        ToolDiffPreview({ colors: this.colors, item: item })
        if (item.result !== undefined) {
          Scroll() {
            AnsiText({ text: item.result, colors: this.colors, error: item.isError === true })
          }.width('100%').constraintSize({ maxHeight: 300 }).align(Alignment.TopStart)
        }
      }
    }.width('100%').padding(14).backgroundColor(this.colors.surface).borderRadius(14)
      .border({ width: 1, color: this.colors.border })
  }

  @Builder
  private turnNoticeRow(item: DshTurnNotice) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        if (item.kind === 'retry') {
          Text(DshGlyphs.refresh).fontFamily(DshGlyphs.family).fontSize(18).fontColor(this.colors.primary)
        }
        Text(item.text).fontSize(14).fontColor(item.kind === 'error' ? this.colors.danger : this.colors.muted)
          .layoutWeight(1)
      }.width('100%')
      if (item.actionable) {
        Flex({ wrap: FlexWrap.Wrap }) {
          if (item.recovery) {
            Button(item.recovery === 'continue' ? this.t("继续") : this.t("重试")).height(40).fontColor(this.colors.primary)
              .backgroundColor(this.colors.surfaceAlt).margin({ right: 8, bottom: 4 })
              .enabled(this.canRecoverTurn(item)).onClick(() => { void this.recoverTurn(item) })
          }
          if (item.code?.startsWith('ACCOUNT_')) {
            Button(this.t("查看账号")).height(40).fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt)
              .enabled(!this.sending && !this.busy).onClick(() => this.showSettings('account'))
          } else if (item.code === 'CONTEXT_WINDOW_EXCEEDED') {
            if (this.compactCommand()) {
              Button(this.t("压缩上下文")).height(40).fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt)
                .margin({ right: 8, bottom: 4 })
                .enabled(!this.loadingChat && !this.sending && !this.busy && !this.running && !this.queuedPrompts.length)
                .onClick(() => {
                  const command = this.compactCommand()
                  if (command) void this.runSlash(command, '/compact')
                })
            }
            Button(this.t("新对话")).height(40).fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt)
              .enabled(!this.sending && !this.busy).onClick(() => this.home())
          } else if (['MISSING_CREDENTIAL', 'INVALID_CREDENTIAL', 'AUTH', 'QUOTA'].includes(item.code || '')) {
            Button(this.t("模型与服务商")).height(40).fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt)
              .enabled(!this.sending && !this.busy).onClick(() => this.showSettings('models'))
          } else if (['MODEL_UNSUPPORTED', 'UNSUPPORTED_REASONING_EFFORT', 'CLIENT_UPGRADE_REQUIRED'].includes(item.code || '')) {
            Button(this.t("选择模型")).height(40).fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt)
              .enabled(!this.sending && !this.busy).onClick(() => { void this.showModels() })
          }
        }.width('100%')
      }
    }.width('100%').padding(14).backgroundColor(this.colors.surface).borderRadius(14)
      .border({ width: 1, color: this.colors.border })
  }

  @Builder
  private commandRow(item: DshCommandNotice) {
    Column({ space: 6 }) {
      Text(`/${item.name}${item.args ? ` ${item.args.trim()}` : ''}`)
        .fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%')
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(item.done ? (item.text || (item.success ? this.t("命令已执行") : this.t("命令执行失败"))) :
        (item.name === 'compact' ? this.t("正在压缩上下文…") : this.t("正在执行命令…")))
        .fontSize(13).fontColor(item.done && item.success === false ? this.colors.danger : this.colors.muted)
        .width('100%').copyOption(CopyOptions.LocalDevice)
    }.width('100%').padding(14).backgroundColor(this.colors.surface).borderRadius(14)
      .border({ width: 1, color: this.colors.border })
  }

  @Builder
  private commandPalette() {
    Scroll() {
      Column({ space: 4 }) {
        ForEach(this.slashChoices(), (item: SlashCommand) => {
          Button({ type: ButtonType.Normal }) {
            Column({ space: 4 }) {
              Text(item.label === item.name ? `/${item.name}` : `${item.label}  /${item.name}`)
                .fontSize(14).fontColor(this.colors.text).width('100%')
              if (item.description || item.hint) {
                Text([item.hint, item.description].filter(Boolean).join(' · '))
                  .fontSize(12).fontColor(this.colors.muted).width('100%')
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }.padding({ top: 8, bottom: 8, left: 12, right: 12 }).width('100%')
          }.width('100%').constraintSize({ minHeight: 44 }).borderRadius(12).backgroundColor(this.colors.surface)
            .onClick(() => { void this.pickSlash(item) })
        }, (item: SlashCommand) => `${item.kind}/${item.name}/${item.definitionId}/${item.label}/${item.hint}/${item.description}`)
      }.width('100%').padding(5)
    }.width('100%').constraintSize({ maxHeight: 198 }).backgroundColor(this.colors.surfaceAlt).borderRadius(15)
  }

  @Builder
  private attachmentMenu() {
    Menu() {
      NativePluginActions({ colors: this.colors, client: this.client, surface: 'composer.tools', scope: this.pluginScope(), draft: this.draft,
        onEffect: (effect: PluginEffect) => { void this.pluginEffect(effect) }, onOpenPanel: (place: PluginPlace) => { this.pluginSection = 'panels'; this.pluginPlace = place; this.page = 'nativePlugins' } })
      MenuItem({ content: this.t("从相册选择") }).onClick(() => { void this.chooseAttachments('photos') })
      MenuItem({ content: this.t("拍照") }).onClick(() => { void this.chooseAttachments('camera') })
      if (this.transportKind !== 'relay') {
        MenuItem({ content: this.t("选择文件") }).onClick(() => { void this.chooseAttachments('files') })
      }
    }
  }

  @Builder
  private messageImageStrip(items: GalleryImage[]) {
    if (items.length) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(items, (file: GalleryImage, index: number) => {
          AttachmentThumbnail({ colors: this.colors, item: file, client: this.client, sessionId: this.sessionId,
            scope: `${this.connectionVersion}/${this.sessionId}/${file.key}`,
            onOpen: () => this.openAttachmentGallery(items, index) }).margin(4)
        }, (file: GalleryImage) => file.key)
      }.width('100%')
    }
  }

  private hostConnectionLabel(): string {
    if (this.mode === 'local') return this.t("本机")
    if (this.transportKind === 'ssh') return 'SSH'
    if (this.relayRoute === 'lan') return this.t("局域网直连")
    if (this.relayRoute === 'p2p') return this.t("WebRTC 直连")
    if (this.relayRoute === 'turn') return this.t("TURN 转发")
    return this.transportKind === 'relay' ? this.t("加密中继") : this.t("远程主机")
  }

  @Builder
  private chatScreen() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        if (this.viewportWidth < 840) this.iconButton(DshGlyphs.menu, this.t("对话列表"), () => this.showSessions())
        Column({ space: 3 }) {
          Text(this.sessionTitle || $r('app.string.app_name')).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.colors.text)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 5 }) {
            Blank().width(5).height(5).borderRadius(3).backgroundColor(this.running || this.compacting ? this.colors.primary : this.colors.success)
            Text(this.compacting ? this.t("正在压缩上下文") : this.running ? this.t("生成中") : this.hostConnectionLabel())
              .fontSize(11).fontColor(this.colors.muted)
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1).padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .backgroundColor(this.colors.surface).borderRadius(24)
          .onClick(() => { if (this.sessionId) this.showDetail() })
        Button(this.modelName, { type: ButtonType.Normal }).height(44).constraintSize({ maxWidth: 130 }).fontSize(13)
          .fontColor(this.colors.primary).backgroundColor(this.colors.surface).borderRadius(22)
          .enabled(!this.busy && !this.sending)
          .onClick(() => { void this.showModels() })
        this.iconButton(DshGlyphs.add, this.t("新对话"), () => this.home())
        this.iconButton(DshGlyphs.more, this.t("快捷面板"), () => { this.quickOpen = true })
      }.width('100%').height(56)
      if (this.sessionId) NativePluginActions({ colors: this.colors, client: this.client, surface: 'session.actions', scope: this.pluginScope(),
        onEffect: (effect: PluginEffect) => { void this.pluginEffect(effect) }, onOpenPanel: (place: PluginPlace) => { this.pluginSection = 'panels'; this.pluginPlace = place; this.page = 'nativePlugins' } })
      this.notice()
      if (!this.sessionId) {
        Column({ space: 16 }) {
          Blank()
          Image($r('app.media.app_icon')).width(64).height(64).objectFit(ImageFit.Contain).borderRadius(14)
          Text(this.t("今天想做点什么？")).fontSize(26).fontWeight(FontWeight.Medium).fontColor(this.colors.text)
          Blank()
        }.layoutWeight(1).width('100%')
      } else {
        List({ scroller: this.chatScroller, space: 20 }) {
          if (this.loadingChat) {
            ListItem() { LoadingProgress().width(32).height(32).color(this.colors.primary) }
          }
          ForEach(this.timeline(), (row: ChatRow) => {
            ListItem() {
              if (row.process) this.turnProcess(row)
              else this.chatRow(row)
            }
          }, (row: ChatRow) => row.key)
          ForEach(this.questions, (question: DshQuestionRequest) => {
            ListItem() {
              QuestionCard({ colors: this.colors, request: question, client: this.client, draftStore: this.questionDrafts })
            }
          }, (question: DshQuestionRequest) => `${question.sessionId}/${question.id}/${question.continued}`)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off).onScroll(() => { this.performanceMonitor?.pulse() })
          .onScrollStart(() => { this.chatScrolling = true }).onScrollStop(() => { this.chatScrolling = false }).onDisAppear(() => { this.chatScrolling = false })
      }
      if (this.approval) this.approvalCard(this.approval)
      if (this.goal) {
        Row({ space: 8 }) {
          Text(this.t("目标")).fontSize(13).fontColor(this.colors.primary)
          Text(goalHeadline(this.goal.objective))
            .fontSize(13).fontColor(this.colors.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          Text('›').fontColor(this.colors.muted)
        }.width('100%').padding(10).backgroundColor(this.colors.surface).borderRadius(14)
          .accessibilityText(this.t("查看目标与进展")).onClick(() => this.showDetail('progress'))
      }
      if (this.todos.length) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text(todoSummary(this.todos, this.running)).fontSize(13).fontColor(this.colors.muted).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            Text(this.todosExpanded ? '⌃' : '⌄').fontColor(this.colors.muted)
          }.width('100%').onClick(() => this.todosExpanded = !this.todosExpanded)
          if (this.todosExpanded) {
            Scroll() {
              Column({ space: 8 }) {
                ForEach(this.todos, (item: DshTodo) => {
                  Text(`${item.status === 'completed' ? '✓' : item.status === 'in_progress' ? '◉' : '○'}  ${item.content}`)
                    .width('100%').fontSize(14).fontColor(item.status === 'completed' ? this.colors.hint : this.colors.text)
                }, (item: DshTodo) => `${item.content}/${item.status}`)
              }.width('100%')
            }.width('100%').constraintSize({ maxHeight: 196 })
          }
        }.width('100%').padding(10).backgroundColor(this.colors.surface).borderRadius(14)
      }
      if (this.sessionId) {
        if (this.regenerationSourceId) {
          Button(this.t("返回原对话")).fontSize(13).height(32).fontColor(this.colors.primary).backgroundColor(Color.Transparent)
            .onClick(() => { void this.openSession(this.regenerationSourceId, this.regenerationSourceTitle) })
        }
        ChatActivityPanel({ colors: this.colors, sessionId: this.sessionId, queue: this.queuedPrompts, client: this.client,
          attachmentBusy: this.sending || this.choosingAttachments || this.voicePhase !== 'idle' ||
            this.withdrawingAttachmentSessions.includes(this.sessionId),
          attachmentRequests: this.queuedAttachmentDrafts.filter((item: QueuedAttachmentDraft) => item.sessionId === this.sessionId)
            .map((item: QueuedAttachmentDraft) => item.requestId),
          onWithdrawAttachment: (id: string, connection: number, item: DshQueuedPrompt) => this.withdrawAttachmentPrompt(id, connection, item),
          onSendNow: (id: string, connection: number, item: DshQueuedPrompt) => this.sendQueuedImmediately(id, connection, item),
          onRecover: (id: string, connection: number, items: DshQueuedPrompt[]) => this.recoverQueueDrafts(id, connection, items) })
      }
      if (this.voicePhase === 'idle' && !this.draftAttachments.length && !this.loadingChat && !this.sending && !this.busy && this.slashChoices().length) this.commandPalette()
      if (this.voicePhase === 'idle' && !this.draftAttachments.length && !this.sending && this.slashHint()) {
        Text(this.slashHint()).fontSize(12).fontColor(this.colors.muted).width('100%').padding({ left: 14 })
      }
      MentionPickerPanel({ controller: this.mentions, revision: this.mentionRevision, colors: this.colors })
      Column({ space: 6 }) {
        if (this.mediaParams) {
          Row({ space: 8 }) {
            Button(this.mediaParams.kind === 'image' ? this.t("生成图像") : this.t("生成视频")).height(32).fontSize(12)
              .fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt).onClick(() => { this.page = 'mediaGenerate' })
            Text(this.mediaParams.model?.model.label || '').fontSize(12).fontColor(this.colors.muted).layoutWeight(1)
            Button(this.t("取消")).height(32).fontSize(12).fontColor(this.colors.muted).backgroundColor(Color.Transparent)
              .onClick(() => { this.mediaParams = undefined })
          }.width('100%')
        }
        if (this.draftAttachments.length) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.draftAttachments, (file: DraftAttachment) => {
                Column({ space: 4 }) {
                  if (file.mediaType) {
                    AttachmentThumbnail({ colors: this.colors, edge: 56, item: { key: file.id, name: file.name, path: file.path },
                      scope: file.id, onOpen: () => this.openDraftGallery(file.id) })
                  }
                  Button(file.mediaType ? this.t("移除") : `${file.name}  ×`, { type: ButtonType.Normal }).height(44)
                    .constraintSize({ maxWidth: 180 }).fontSize(13).fontColor(this.colors.text)
                    .backgroundColor(this.colors.surfaceAlt).borderRadius(12).enabled(!this.sending)
                    .accessibilityText(this.f("移除附件 {0}", [file.name])).onClick(() => this.removeAttachment(file))
                }
              }, (file: DraftAttachment) => file.id)
            }.padding({ left: 10, right: 10, top: 6 })
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
        }
        NativePluginStrip({ colors: this.colors, client: this.client, scope: this.pluginScope() })
        NativePluginActions({ colors: this.colors, client: this.client, draft: this.draft, scope: this.pluginScope(),
          onEffect: (effect: PluginEffect) => { void this.pluginEffect(effect) }, onOpenPanel: (place: PluginPlace) => { this.pluginSection = 'panels'; this.pluginPlace = place; this.page = 'nativePlugins' } })
        MentionEditor({ onFocusChanged: (focused: boolean) => { this.composerFocused = focused }, colors: this.colors, fontSize: this.fontSize, text: this.draft, hardwareEnterSends: this.advanced.hardwareEnterSends, onSend: () => { void this.send() },
          sessionId: this.sessionId, connectionId: this.connectionVersion, revision: this.mentionRevision,
          readOnly: this.voicePhase !== 'idle', provisionalStart: this.voiceProvisionalStart,
          provisionalEnd: this.voiceProvisionalEnd,
          controller: this.mentions, onError: (message: string) => this.errorText = message })
        Row({ space: 8 }) {
          if (this.voicePhase === 'listening' || this.voicePhase === 'transcribing') {
            Button({ type: ButtonType.Circle }) {
              Text(DshGlyphs.close).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text)
            }.width(36).height(36).backgroundColor(this.colors.surfaceAlt).accessibilityText(this.t("取消语音输入"))
              .onClick(() => { this.voice?.cancel() })
            Text(this.voicePhase === 'listening' ? this.t("正在听…") : this.t("正在转写…"))
              .fontSize(13).fontColor(this.colors.muted).layoutWeight(1)
            Row({ space: 3.5 }) {
              ForEach(this.voiceLevels, (_level: number, index: number) => {
                Column().width(3).height(4 + this.voiceLevels[index] * 20).borderRadius(20)
                  .backgroundColor(this.colors.text).opacity(this.voicePhase === 'listening' ? 0.6 : 0.25)
                  .animation({ duration: this.performance.animations ? 120 : 0, curve: Curve.EaseInOut })
              }, (_level: number, index: number) => `${index}`)
            }.width(37).height(36).justifyContent(FlexAlign.Center)
              .accessibilityText(this.voicePhase === 'listening' ? this.t("正在听") : this.t("正在转写"))
          } else {
          Button({ type: ButtonType.Circle }) {
            Text(DshGlyphs.add).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text)
          }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText(this.t("添加附件"))
            .enabled(this.voicePhase === 'idle' && !this.sending && !this.busy && !this.choosingAttachments &&
              !this.withdrawingAttachmentSessions.includes(this.sessionId)).bindMenu(this.attachmentMenu())
          this.iconButton(DshGlyphs.more, this.t("更多功能"), () => this.page = 'features')
          this.iconButton(DshGlyphs.add, this.t("生成图像或视频"), () => { this.page = 'mediaGenerate' })
          this.iconButton(DshGlyphs.settings, this.t("对话选项"), () => { void this.showSessionOptions() })
          if (this.workspaceId) {
            Text(this.workspaces.find((item: DshWorkspace) => item.id === this.workspaceId)?.title || this.t("工作区"))
              .fontSize(12).fontColor(this.colors.muted).maxLines(1).layoutWeight(1)
          } else { Blank() }
          }
          if (this.voicePhase !== 'idle') {
            Button({ type: ButtonType.Circle }) {
              if (this.voicePhase === 'listening') {
                Text(DshGlyphs.stop).fontFamily(DshGlyphs.family).fontSize(18).fontColor(this.colors.onPrimary)
              } else { LoadingProgress().width(22).height(22).color(this.colors.onPrimary) }
            }.width(36).height(36).backgroundColor(this.colors.primary).enabled(this.voicePhase === 'listening')
              .accessibilityText(this.t("停止语音输入")).onClick(() => { void this.voice?.stop() })
          } else if ((this.running && !this.draft.trim() && !this.draftAttachments.length) || (this.sending && this.compacting)) {
            Button({ type: ButtonType.Circle }) {
              Text(DshGlyphs.stop).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.onPrimary)
            }.width(42).height(42).backgroundColor(this.colors.primary).enabled(!this.stopping)
              .accessibilityText(this.compacting ? this.t("停止压缩") : this.t("停止生成")).onClick(() => { void this.stop() })
          } else if (!this.draft.trim() && !this.draftAttachments.length && this.voiceAvailable && !this.busy && !this.sending) {
            Button({ type: ButtonType.Circle }) {
              Text(DshGlyphs.voice).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.text)
            }.width(36).height(36).backgroundColor(this.colors.surfaceAlt)
              .enabled(this.connected && !this.loadingChat && !this.regenerating && !this.choosingAttachments &&
                !this.withdrawingAttachmentSessions.includes(this.sessionId))
              .accessibilityText(this.t("语音输入")).onClick(() => this.startVoice())
          } else {
            Button({ type: ButtonType.Circle }) {
              if (this.sending || this.busy || this.regenerating) { LoadingProgress().width(22).height(22).color(this.colors.onPrimary) }
              else { Text(DshGlyphs.send).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.onPrimary) }
            }.width(42).height(42).backgroundColor(this.colors.primary)
              .enabled(!this.loadingChat && !this.sending && !this.busy && !this.regenerating && !this.choosingAttachments &&
                !this.withdrawingAttachmentSessions.includes(this.sessionId) &&
                (this.draftAttachments.length > 0 || (this.draft.trim().length > 0 && this.draft.trim() !== '/')))
              .accessibilityText(this.running ? this.t("加入消息队列") : this.t("发送消息")).onClick(() => { void this.send() })
          }
        }.width('100%').padding({ left: 4, right: 8, bottom: 8 })
      }.width('100%').backgroundColor(this.advanced.glass && this.performance.blur ? '#D9' + this.colors.surface.slice(1) : this.colors.surface)
        .backgroundBlurStyle(this.advanced.glass && this.performance.blur ? BlurStyle.Thin : BlurStyle.NONE).borderRadius(26)
        .border({ width: 1, color: this.colors.border })
    }.padding({ left: 12, right: 12, top: 4, bottom: 12 }).width('100%').height('100%')
  }

  @Builder
  private featureRow(glyph: string, title: string, subtitle: string, action: () => void) {
    Row({ space: 14 }) {
      Text(glyph).fontFamily(DshGlyphs.family).fontSize(24).fontColor(this.colors.primary)
      Column({ space: 5 }) {
        Text(title).fontSize(17).fontColor(this.colors.text)
        Text(subtitle).fontSize(13).fontColor(this.colors.muted)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text('›').fontSize(22).fontColor(this.colors.hint)
    }.padding(18).width('100%').backgroundColor(this.colors.surface).borderRadius(18).onClick(action)
  }

  @Builder
  private featuresScreen() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        this.iconButton(DshGlyphs.back, this.t("返回"), () => this.page = 'chat')
        Text(this.t("全部功能")).fontSize(23).fontWeight(FontWeight.Medium).fontColor(this.colors.text)
      }.width('100%')
      Scroll() {
        Column({ space: 10 }) {
          Text(this.t("对话")).fontSize(13).fontColor(this.colors.muted).width('100%').padding(8)
          this.featureRow(DshGlyphs.chat, this.t("对话详情"), this.t("查看当前对话和记录"), () => {
            if (this.sessionId) this.showDetail()
            else this.errorText = this.t("请先打开或创建一个对话。")
          })
          this.featureRow(DshGlyphs.file, this.t("工作区文件"), this.t("浏览当前对话的文件"), () => {
            if (this.sessionId) this.showFiles()
            else this.errorText = this.t("请先打开或创建一个对话。")
          })
          this.featureRow(DshGlyphs.folder, this.t("工作区"), this.t("切换和管理工作目录"), () => this.page = 'workspaces')
          this.featureRow(DshGlyphs.file, this.t("导出会话日志"), this.t("打包当前会话及其子会话"), () => {
            if (this.sessionId) { this.exportOrigin = 'features'; this.page = 'sessionExport' }
            else this.errorText = this.t("请先打开或创建一个对话。")
          })
          this.featureRow(DshGlyphs.chat, this.t('宠物'), this.t('桌宠、导入与互动'), () => { this.page = 'pets' })
          this.featureRow(DshGlyphs.chat, this.t('伙伴小屋'), this.t('独立对话、记忆与角色'), () => { this.page = 'companion' })
          this.featureRow(DshGlyphs.plugin, 'Cordis', this.t('动态插件与主机界面'), () => this.openDestination('cordis'))
          this.featureRow(DshGlyphs.plugin, this.t('插件席位'), this.t('主机扩展与应用内面板'), () => this.openDestination('plugin-seats'))
          this.featureRow(DshGlyphs.chat, 'DS Bot', this.t('团队、单聊、群聊与记忆'), () => { this.dsBotInitialId = ''; this.page = 'dsBot' })
          this.featureRow(DshGlyphs.chat, this.t("社区"), this.t("浏览、搜索和参与 DSH Go 社区"), () => { this.page = 'forum' })
          this.featureRow(DshGlyphs.chat, this.t("分享对话"), this.t("选择消息和回合、脱敏、加密链接"), () => this.showShare())
          this.featureRow(DshGlyphs.file, this.t("打开分享"), this.t("导入分享码、链接与会话文件"), () => this.showShareImport())
          this.featureRow(DshGlyphs.host, this.t("网页模式"), this.t("打开当前主机完整网页界面"), () => { this.page = 'webMode' })
          this.featureRow(DshGlyphs.host, this.t("网络诊断"), this.t("检查连接与重连"), () => { this.page = 'networkDiagnostics' })
          this.featureRow(DshGlyphs.settings, this.t("启动设置"), this.t("自动启动与恢复上次主机"), () => { this.page = 'startup' })
          Text(this.t("能力")).fontSize(13).fontColor(this.colors.muted).width('100%').padding(8)
          this.featureRow(DshGlyphs.plugin, this.t("插件"), this.t("插件、预设与市场"), () => this.openFeature('plugins'))
          this.featureRow(DshGlyphs.file, this.t("技能"), this.t("浏览和使用工作区技能"), () => this.openFeature('skills'))
          this.featureRow(DshGlyphs.chat, this.t("子代理与团队"), this.t("查看分工、对话与进度"), () => this.openFeature('agents'))
          this.featureRow(DshGlyphs.terminal, this.t("后台任务"), this.t("查看任务输出与运行状态"), () => this.openFeature('jobs'))
          if (this.mode !== 'local') {
            this.featureRow(DshGlyphs.terminal, this.t("终端"), this.t("连接主机的交互终端"), () => {
              if (this.sessionId) this.page = 'terminal'
              else this.errorText = this.t("请先打开一个对话。")
            })
          }
          this.featureRow(DshGlyphs.host, this.t("自动化任务"), this.t("定时运行、历史与配置"), () => this.openFeature('schedules'))
          Text(this.t("模型与应用")).fontSize(13).fontColor(this.colors.muted).width('100%').padding(8)
          this.featureRow(DshGlyphs.model, this.t("模型与渠道"), this.t("配置模型与提供方"), () => this.showSettings('models'))
          this.featureRow(DshGlyphs.settings, this.t("引擎参数"), this.t("调整 DeepSeek Harness"), () => this.showSettings('parameters'))
          this.featureRow(DshGlyphs.host, this.t("本机引擎"), this.t("运行状态与引擎管理"), () => this.showSettings('engine'))
          this.featureRow(DshGlyphs.settings, this.t("外观"), this.t("主题、配色与阅读字号"), () => this.showSettings('appearance'))
          this.featureRow(DshGlyphs.settings, this.t('性能'), this.t('自动、完整效果与轻量模式'), () => { this.page = 'performance' })
          this.featureRow(DshGlyphs.settings, this.t('后台运行'), this.t('查看系统限制和后台通知'), () => { this.page = 'background' })
          this.featureRow(DshGlyphs.settings, this.t('系统权限'), this.t('麦克风、通知与读取屏幕'), () => { this.page = 'system-permissions' })
          this.featureRow(DshGlyphs.settings, this.t('手机控制'), this.t('读取屏幕与应用规则'), () => { this.page = 'phone' })
          this.featureRow(DshGlyphs.settings, this.t("设置"), this.t("应用设置"), () => this.showSettings())
          this.notice()
        }.width('100%')
      }.width('100%').layoutWeight(1)
    }.padding(16).width('100%').height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      WallpaperBackdrop({ paper: this.advanced.wallpaper, colors: this.colors, dark: this.isDark() })
      Row() {
        if (this.connected && this.viewportWidth >= 840 && this.advanced.sidebarOpen) {
          Column() { this.sessionDrawer() }.width(310).height('100%').backgroundBlurStyle(this.advanced.glass && this.performance.blur ? BlurStyle.Thin : BlurStyle.NONE)
          Divider().vertical(true).color(this.colors.border)
        }
        Column() {
          if (this.page === 'loading') {
            LoadingProgress().width(40).height(40).color(this.colors.primary)
          } else if (this.page === 'onboarding') {
            OnboardingPanel({ colors: this.colors, accentId: this.accentId, themeMode: this.themeMode, fontSize: this.fontSize,
              onBackHandler: (handler?: () => boolean) => { this.onboardingBack = handler },
              engineBusy: this.busy, engineReady: this.engineReady, stageText: this.localStage, errorText: this.errorText,
              onThemeChange: (accent: string, mode: string) => {
                this.accentId = accent; this.themeMode = mode; void this.persistPreferences()
              }, onFontSizeChange: (size: number) => { this.fontSize = size; void this.persistPreferences() },
              onPrepareLocal: () => { void this.prepareLocal() },
              onConnectLocal: (key: string, remember: boolean) => this.connect(key, remember, true),
              onConnectAccount: () => { void this.openLocalAccount() },
              onOpenPrivacy: () => this.showSettings('privacy'), onFinish: () => { void this.finishOnboarding() },
              onRemote: () => this.showRemoteHosts() })
          } else if (this.page === 'connect') this.connectScreen()
          else if (this.page === 'remoteHosts') {
            RemoteHostsPanel({ colors: this.colors, connected: this.connected, currentId: this.remoteHostId,
              currentName: this.mode === 'local' ? this.t("本机") : this.host, connecting: this.busy, errorText: this.errorText,
              onBackHandler: (handler?: () => boolean) => { this.remoteBack = handler },
              onConnect: (connection: RemoteHostConnection) => this.connectRemote(connection),
              onLocal: () => this.switchHost('local'), onClose: () => this.closeRemoteHosts(),
              onSsh: () => { this.errorText = ''; this.page = 'sshHosts' },
              onRelay: () => { this.errorText = ''; this.page = 'relayHosts' } })
          } else if (this.page === 'sshHosts') {
            SshPanel({ initialHostId: this.restoreHostId, colors: this.colors, errorText: this.errorText, openControl: () => this.openTransportControl(),
              onConnect: (endpoint: TransportEndpoint) => this.connectTransport(endpoint, 'ssh'),
              onBackHandler: (handler?: () => boolean) => { this.sshBack = handler },
              onClose: () => { this.page = 'remoteHosts' } })
          } else if (this.page === 'relayHosts') {
            RelayPanel({ initialHostId: this.restoreHostId, autoRestore: !!this.restoreHostId, colors: this.colors, openControl: () => this.openTransportControl(),
              onConnect: (endpoint: TransportEndpoint) => this.connectTransport(endpoint, 'relay'),
              onClose: () => { this.page = 'remoteHosts' } })
          } else if (this.page === 'mediaGenerate') {
            MediaGeneratePanel({ colors: this.colors, client: this.client, currentParams: this.mediaParams,
              onSelected: (params: MediaParams) => { this.mediaParams = params; this.page = 'chat' },
              onSettings: () => this.showSettings('media'), onClose: () => { this.page = 'chat' } })
          } else if (this.page === 'mediaViewer') {
            MediaViewer({ colors: this.colors, client: this.client, sessionId: this.sessionId, items: this.mediaItems,
              initialIndex: this.mediaIndex, onClose: () => { this.mediaItems = []; this.page = 'chat' } })
          } else if (this.page === 'dsBot') {
            Column() {
            if (this.bundledBotRestart && this.mode === 'local') Button(this.t('重启本机引擎')).enabled(!this.busy).onClick(() => { void this.restartForMaintenance().then(() => { this.page = 'dsBot' }).catch((error: Error) => { this.errorText = error.message }) })
            DSBotPanel({ bundledAvailable: this.bundledBotAvailable && this.mode === 'local', bundledEnabled: this.bundledBotEnabled, bundledRestart: this.bundledBotRestart, onBundledChange: (enabled: boolean) => this.changeBundledBot(enabled), colors: this.colors, client: this.client, hub: this.dsBot, initialId: this.dsBotInitialId, initialRoom: this.dsBotInitialRoom, hostScope: this.hostScope(), rpc: this.transportKind === 'relay',
              onClose: () => { this.page = 'features' }, onOpenPlugins: () => this.openFeature('plugins'), onOpenWeb: () => { this.page = 'webMode' },
              onOpenSession: (id: string) => { void this.openSession(id, 'DS Bot') }, onBackHandler: (handler?: () => boolean) => { this.dsBotBack = handler } }).layoutWeight(1)
            }.width('100%').height('100%')
          } else if (this.page === 'pets') {
            PetsPanel({ colors: this.colors, preferEnabled: this.performance.tier !== 'low', animations: this.performance.animations && this.foreground, onClose: () => { this.page = 'features' }, onOpenCompanion: () => { this.page = 'companion' } })
          } else if (this.page === 'companion') {
            ForEach([`${this.hostScope()}|${this.connectionVersion}|${this.connected}`], (_identity: string) => {
            CompanionPanel({ onBackHandler: (handler?: () => boolean) => { this.companionBack = handler }, foreground: this.foreground, colors: this.colors, hostKey: this.hostScope(), animations: this.performance.animations, lowMemory: this.performance.tier === 'low', client: this.connected ? this.client : undefined, onClose: () => { this.page = 'features' }, onOpenSession: (host: string, id: string) => { if (host === this.hostScope()) void this.openSession(id, this.t('伙伴小屋')) } })
            }, (identity: string) => identity)
          } else if (this.page === 'forum') {
            ForumPanel({ colors: this.colors, getControl: () => this.openTransportControl(), authRedirect: this.forumRedirect,
              onAuthRedirectConsumed: () => { this.forumRedirect = '' }, onBackHandler: (handler?: () => boolean) => { this.forumBack = handler },
              onClose: () => { this.page = this.connected ? 'features' : 'connect' }, onOpenLink: (link: string) => {
                const share = shareLaunch(link)
                if (share) { this.showShareImport(); this.shareInput = share.link }
                else { const page = appPageLink(link); if (page) this.openDestination(page)
                  else if (/^https:\/\//.test(link)) void (this.getUIContext().getHostContext() as common.UIAbilityContext).openLink(link).catch(() => { this.errorText = this.t("无法打开链接") }) }
              } })
          } else if (this.page === 'performance') {
            PerformanceSettings({ colors: this.colors, state: this.performance, onClose: () => { this.page = 'features' },
              onChange: async (value: PerformancePreferences) => { if (!this.performanceMonitor) throw new Error(this.t('性能服务尚未就绪')); await this.performanceMonitor.update(value) } })
          } else if (this.page === 'background' || this.page === 'system-permissions') {
            SystemAccessPanel({ colors: this.colors, backgroundPage: this.page === 'background', onClose: () => { this.page = 'features' },
              onPhone: () => { this.page = 'phone' }, onNotifications: () => this.showSettings('notifications') })
          } else if (this.page === 'phone') {
            PhoneControlPanel({ getControl: () => this.openTransportControl(), colors: this.colors, onClose: () => { this.page = 'features' },
              onBackHandler: (handler?: () => boolean) => { this.phoneBack = handler },
              onScreenText: (text: string) => { this.draft = this.draft ? this.draft + '\n\n' + text : text; this.page = 'chat' } })
          } else if (this.page === 'startup') {
            Column() { Button(this.t("返回")).onClick(() => { this.page = 'features' }); StartupPanel({ colors: this.colors, getAppContext: () => this.getUIContext().getHostContext() as common.UIAbilityContext }) }.width('100%').height('100%')
          } else if (this.page === 'networkDiagnostics') {
            Column() { Button(this.t("返回")).onClick(() => { this.page = 'features' }); NetworkDiagnosticsPanel({ colors: this.colors, connected: this.connected, client: this.client }) }.width('100%').height('100%')
          } else if (this.page === 'webMode') {
            Column() { Button(this.t("返回")).onClick(() => { this.page = 'features' }); WebModePanel({ colors: this.colors, client: this.client, getControl: () => this.openTransportControl() }).layoutWeight(1) }.width('100%').height('100%')
          } else if (this.page === 'nativePlugins') {
            NativePluginsPanel({ initialSection: this.pluginSection, getControl: () => this.openTransportControl(), onOpenNamespace: (id: string) => this.showSettings('ns:' + id), onOpenSession: (id: string) => { void this.openSession(id, this.t('对话')) }, onBackHandler: (handler?: () => boolean) => { this.nativePluginsBack = handler }, colors: this.colors, client: this.client, sessionId: this.sessionId, initialPlace: this.pluginPlace,
              onClose: () => { this.page = 'chat' }, onEffect: (effect: PluginEffect) => { void this.pluginEffect(effect) }, onOpenWeb: () => { this.page = 'webMode' } })
          } else if (this.page === 'profileShare') {
            ProfileSharePanel({ colors: this.colors, client: this.client, local: this.mode === 'local', relay: this.transportKind === 'relay', initialPlugin: this.sharedPlugin, getControl: () => this.openTransportControl(), onClose: () => { this.page = this.shareOrigin }, onOpenPlugins: () => this.openFeature('plugins'), onBackHandler: (handler?: () => boolean) => { this.shareBack = handler } })
          } else if (this.page === 'conversationShare') {
            ConversationSharePanel({ colors: this.colors, client: this.client, source: this.shareSource, sessionId: this.sessionId, initialOnly: this.shareOnly,
              getControl: () => this.openTransportControl(), onClose: () => { this.page = this.shareOrigin }, onShared: () => { this.recordUsage('share') },
              onBackHandler: (handler?: () => boolean) => { this.shareBack = handler } })
          } else if (this.page === 'conversationImport') {
            ConversationImportPanel({ client: this.client, local: this.connected && this.mode === 'local', relay: this.transportKind === 'relay', onOpenPlugins: () => this.openFeature('plugins'), colors: this.colors, initialTab: this.shareTab, initialInput: this.shareInput, initialFile: this.shareFile,
              getControl: () => this.openTransportControl(), onClose: () => { this.page = this.shareOrigin }, onBackHandler: (handler?: () => boolean) => { this.shareBack = handler } })
          } else if (this.page === 'terminal') {
            TerminalPanel({ colors: this.colors, client: this.client, sessionId: this.sessionId,
              onClose: () => { this.page = 'features' } })
          } else if (this.page === 'settings') {
            SettingsPanel({ dark: this.isDark(), usage: this.usage, onAdvancedChange: (prefs: AdvancedPreferences) => { this.advanced = prefs },
              onLocalOcr: () => { this.page = 'phone' }, onNotificationChange: (prefs: NotificationPreferences) => this.notifications?.updatePreferences(prefs), onOpenShareLinks: () => this.showShareImport('links'), colors: this.colors, client: this.client, connected: this.connected,
              speechMode: this.speechMode, onSpeechModeChange: (mode: SpeechMode) => this.changeSpeechMode(mode),
              getLocalControl: () => this.openTransportControl(),
              connectionIdentity: this.connectionVersion, relay: this.transportKind === 'relay',
              savedLocalKey: this.hasSavedKey,
              onLocalKeyStored: (stored: boolean) => { this.hasSavedKey = stored; this.rememberKey = stored },
              onBackHandler: (handler?: () => boolean) => { this.settingsBack = handler },
              local: this.mode === 'local', initialPage: this.settingsPage, requestVersion: this.settingsRequestVersion,
              engineStatus: this.localStage || (this.engineReady ? this.t("运行中") : this.t("已停止")),
              engineRunning: this.engineReady, engineBusy: this.busy, maintenanceBusy: this.maintenanceBusy,
              onMaintenanceWorking: (working: boolean) => { this.maintenanceBusy = working },
              onMaintenanceStop: async (): Promise<void> => { if (!await this.stopLocalEngine(true)) throw new Error(this.t("本机引擎未能停止")) },
              onMaintenanceRestart: () => this.restartForMaintenance(),
              accentId: this.accentId, themeMode: this.themeMode, fontSize: this.fontSize,
              onClose: () => this.closeSettings(),
              onThemeChange: (accent: string, mode: string) => {
                this.accentId = accent; this.themeMode = mode; void this.persistPreferences()
              }, onFontSizeChange: (size: number) => { this.fontSize = size; void this.persistPreferences() },
              onStartEngine: () => this.switchHost('local'), onStopEngine: () => { void this.stopLocalEngine() },
              onRestartEngine: () => { void this.stopLocalEngine().then((stopped: boolean) => {
                if (stopped) this.switchHost('local')
              }) },
              onOpenDestination: (id: string) => this.openDestination(id), onOpenHosts: () => this.switchHost('remote'),
              onOpenPlugins: () => this.openFeature('plugins') })
          } else if (this.page === 'workspaces') {
            WorkspacesPanel({ colors: this.colors, client: this.client, workspaces: this.workspaces,
              workingDir: this.mode === 'local' ? this.localWorkspace : '',
              hostScope: this.mode === 'local' ? 'local' : this.remoteHostScope,
              onBackHandler: (handler?: () => boolean) => { this.workspaceBack = handler },
              onClose: () => this.page = 'chat', onSelect: (id: string) => { this.workspaceId = id; this.home() },
              onNew: (id: string) => { this.workspaceId = id; this.home() } })
          } else if (this.page === 'models') {
            ModelPanel({ colors: this.colors, client: this.client, sessionId: this.sessionId,
              currentSelection: this.pendingSessionModel || this.currentModel,
              onBackHandler: (handler?: () => boolean) => { this.modelsBack = handler },
              onClose: () => this.page = 'chat',
              onManageModels: () => this.showSettings('models'),
              onSelected: (name: string, selection: DshModelSelection, warning?: string) => {
                this.currentModel = selection
                this.pendingSessionModel = undefined; this.pendingModelSessionId = ''
                this.modelName = name; this.reasoningEffort = selection.reasoningEffort || ''; this.page = 'chat'
                this.errorText = warning || ''
              } })
          } else if (this.page === 'engineFeatures') {
            EngineFeaturesPanel({ onSharePlugin: (name: string) => { this.sharedPlugin = name; this.shareOrigin = 'engineFeatures'; this.page = 'profileShare' }, onPluginCount: (count: number) => { void this.usage?.plugins(count).catch(() => {}) }, getControl: () => this.openTransportControl(), onOpenNamespace: (id: string) => this.showSettings('ns:' + id), colors: this.colors, client: this.client, sessionId: this.sessionId,
              onBackHandler: (handler?: () => boolean) => { this.featuresBack = handler },
              onPluginEffect: (effect: PluginEffect) => { void this.pluginEffect(effect) }, onOpenPluginWeb: () => { this.page = 'webMode' },
              kind: this.featureKind, onClose: () => this.page = this.featureOrigin,
              onOpenSession: (id: string) => { void this.openSession(id, this.t("对话")) },
              onUseSkill: (command: string, newSession: boolean) => {
                if (newSession) this.home()
                this.draft = command
                this.page = 'chat'
              } })
          } else if (this.page === 'sessionOptions') {
            SessionOptionsPanel({ colors: this.colors, client: this.client, sessionId: this.sessionId, local: this.mode === 'local',
              presetDraft: this.newPreset, permissionDraft: this.newPermission,
              onDraftChange: (preset: string, permission: string) => { this.newPreset = preset; this.newPermission = permission },
              onClose: () => this.page = 'chat' })
          } else if (this.page === 'sessionExport') {
            SessionExportPanel({ colors: this.colors, client: this.client, sessionId: this.sessionId,
              onBackHandler: (handler?: () => boolean) => { this.exportBack = handler }, onClose: () => this.page = this.exportOrigin })
          } else if (this.page === 'detail') {
            SessionDetailPanel({ colors: this.colors, client: this.client, sessionId: this.sessionId, title: this.sessionTitle,
              onBackHandler: (handler?: () => boolean) => { this.detailBack = handler },
              initialTab: this.detailTab, onClose: () => this.page = 'chat', onFiles: () => this.showFiles(),
              onAgents: () => this.openFeature('agents'), onPlugins: () => this.openFeature('plugins'),
              onFork: () => { void this.fork() } })
          } else if (this.page === 'artifacts') {
            Column({ space: 12 }) { Row() { Button(this.t('返回')).onClick(() => { this.page = 'chat' }); Text(this.t('制品')).fontSize(22).fontColor(this.colors.text).layoutWeight(1) }.width('100%')
              Scroll() { Column({ space: 12 }) { ForEach(sessionArtifacts(this.records, this.activeCwd()), (artifact: SessionArtifact) => {
                ArtifactCard({ colors: this.colors, items: [artifact], onOpen: (path: string) => { this.artifactPath = path; this.filesOrigin = 'artifacts'; this.page = 'files' } })
              })
              if (!sessionArtifacts(this.records, this.activeCwd()).length) Text(this.t('当前对话还没有制品')).fontColor(this.colors.muted)
              }.width('100%') }.layoutWeight(1).width('100%')
            }.padding(16).width('100%').height('100%')
          } else if (this.page === 'files') {
            FilesPanel({ colors: this.colors, client: this.client, sessionId: this.sessionId, initialPath: this.artifactPath,
              onBackHandler: (handler?: () => boolean) => { this.filesBack = handler }, onClose: () => this.page = this.filesOrigin })
          } else if (this.page === 'features') this.featuresScreen()
          else this.chatScreen()
        }.layoutWeight(1).height('100%')
        if (this.connected && this.page === 'chat' && this.viewportWidth >= 1280 && this.advanced.panelOpen) {
          Divider().vertical(true).color(this.colors.border)
          QuickPanel({ colors: this.colors, client: this.client, sessionId: this.sessionId, title: this.sessionTitle,
            cwd: this.activeCwd(), model: this.modelName, pluginPanels: this.quickPluginItems(), onPlugin: (id: string) => this.openQuickPlugin(id),
            onClose: () => { void this.setWidePanel(false) }, onOpen: (id: string) => this.openDestination(id), onSessionDetail: () => this.showDetail(),
            onPreferencesChange: (prefs: QuickPanelPreferences) => { this.quickPreferences = prefs } }).width(330).height('100%')
        }
      }.width('100%').height('100%').enabled(!this.maintenanceBusy)
        .visibility(this.page === 'attachmentPreview' ? Visibility.Hidden : Visibility.Visible)
      if (this.drawer && (this.viewportWidth < 840 || !this.advanced.sidebarOpen)) {
        Row() {
          Column() { this.sessionDrawer() }.width(this.viewportWidth > 480 ? 380 : '88%').height('100%')
          Column().layoutWeight(1).height('100%').backgroundColor('#55000000').onClick(() => this.drawer = false)
        }.width('100%').height('100%').transition(this.performance.animations ? TransitionEffect.move(TransitionEdge.START).animation({ duration: this.performance.fluid ? 260 : 160, curve: this.performance.fluid ? Curve.EaseOut : Curve.Linear }) : TransitionEffect.IDENTITY)
      }
      if (this.quickOpen && this.page === 'chat') {
        Row() {
          Column().layoutWeight(1).height('100%').backgroundColor('#55000000').onClick(() => { this.quickOpen = false })
          QuickPanel({ colors: this.colors, client: this.client, sessionId: this.sessionId, title: this.sessionTitle,
            cwd: this.activeCwd(), model: this.modelName, pluginPanels: this.quickPluginItems(), onPlugin: (id: string) => this.openQuickPlugin(id),
            onClose: () => { this.quickOpen = false }, onOpen: (id: string) => { this.quickOpen = false; this.openDestination(id) },
            onSessionDetail: () => { this.quickOpen = false; this.showDetail() },
            onPreferencesChange: (prefs: QuickPanelPreferences) => { this.quickPreferences = prefs } })
            .width(this.viewportWidth > 480 ? 380 : '88%').height('100%')
        }.width('100%').height('100%').transition(this.performance.animations ? TransitionEffect.move(TransitionEdge.END).animation({ duration: this.performance.fluid ? 260 : 160, curve: this.performance.fluid ? Curve.EaseOut : Curve.Linear }) : TransitionEffect.IDENTITY)
      }
      if (this.page === 'chat' && !this.drawer && !this.quickOpen) PetPerch({ idleBlocked: this.composerFocused || this.chatScrolling, colors: this.colors, preferEnabled: this.performance.tier !== 'low', animations: this.performance.animations && this.foreground, sessions: this.petSessions, focusId: this.sessionId, onSettings: () => { this.page = 'pets' }, onOpenCompanion: () => { this.page = 'companion' }, onOpenSession: (host: string, id: string) => { if (host === this.hostScope()) void this.openSession(id, this.t('对话')) } })
        .position({ x: 0, y: '100%' }).markAnchor({ x: 0, y: '100%' }).hitTestBehavior(HitTestMode.Transparent)
      PhoneTaskHost({ onTaskStarted: () => this.recordUsage('phone'), localConnected: this.connected && this.mode === 'local', colors: this.colors, getControl: () => this.openTransportControl() })
      if (this.notificationBanner) {
        Row() { Text(this.t(this.notificationBanner.text)).fontColor(this.colors.text).layoutWeight(1); Button(this.t("查看")).onClick(() => {
          const item = this.notificationBanner; this.notificationBanner = undefined
          if (item?.destination === 'ds-bot') { this.dsBotInitialId = item.botId || ''; this.dsBotInitialRoom = item.botRoom === true; this.page = 'dsBot' }
          else if (item?.sessionId) void this.openSession(item.sessionId, this.t("对话"))
        }); Button(this.t("关闭")).onClick(() => { this.notificationBanner = undefined }) }.padding(12).backgroundColor(this.colors.surface).borderRadius(12).width('95%').position({ x: '2.5%', y: 8 })
      }
      if (this.page === 'attachmentPreview') {
        AttachmentGallery({ colors: this.colors, items: this.galleryItems, initialIndex: this.galleryIndex,
          client: this.client, sessionId: this.sessionId, onClose: () => this.closeAttachmentPreview() })
      }
    }.width('100%').height('100%').backgroundColor(this.colors.background)
      .onAreaChange((oldValue: Area, newValue: Area) => { this.viewportWidth = Number(newValue.width) })
      .parallelGesture(PanGesture({ direction: PanDirection.Left, distance: 50 }).onActionEnd((event: GestureEvent) => {
        if (this.page === 'chat' && this.quickPreferences.swipe && this.quickPreferences.items.length &&
          event.fingerList.length && event.fingerList[0].globalX - event.offsetX > this.viewportWidth - 40) this.quickOpen = true
      }))
  }
}
