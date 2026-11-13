import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { util } from '@kit.ArkTS'
import { ThemeColors, themeColors, DshGlyphs, registerDshFonts } from '../ui/DshTheme'
import { MessageBody } from '../ui/MessageBody'
import { SessionsPanel } from '../ui/SessionsPanel'
import { WorkspacesPanel } from '../ui/WorkspacesPanel'
import { FilesPanel } from '../ui/FilesPanel'
import { ModelPanel } from '../ui/ModelPanel'
import { SettingsPanel } from '../ui/SettingsPanel'
import { EngineFeaturesPanel } from '../ui/EngineFeaturesPanel'
import { ChatRow, ChatTimeline } from '../ui/ChatTimeline'
import { AppPreferenceValues, loadAppPreferences, saveAppPreferences, loadOnboardingComplete, saveOnboardingComplete } from '../ui/AppPreferences'
import { DshModelSelection, DshTool, DshTurnNotice, DshQueuedPrompt, DshQuestionRequest, DshTodo, DshGoal, modelSelection, normalizeProviderKey, object } from '../dsh/DshWire'
import { ChatActivityPanel } from '../ui/ChatActivityPanel'
import { QuestionCard } from '../ui/QuestionCard'
import { QuestionDrafts } from '../ui/QuestionDrafts'
import { ComposerDrafts } from '../ui/ComposerDrafts'
import { todoSummary, goalHeadline } from '../ui/ChatProgress'
import { SessionOptionsPanel } from '../ui/SessionOptionsPanel'
import { SessionDetailPanel } from '../ui/SessionDetailPanel'
import { SessionExportPanel } from '../ui/SessionExportPanel'
import { OnboardingPanel } from '../ui/OnboardingPanel'
import { hasLocalApiKey, loadLocalApiKey, saveLocalApiKey, removeLocalApiKey } from '../local/LocalKeyStore'
import { LocalEngine } from '../local/LocalEngine'
import { RemoteHostConnection } from '../remote/RemoteHosts'
import { RemoteHostsPanel } from '../ui/RemoteHostsPanel'
import { DshApproval, DshChatUpdate, DshClient, DshMessage, DshSession, DshWorkspace } from '../dsh/DshClient'

@Entry
@Component
struct Index {
  @State private page: string = 'loading'
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
  @State private expandedReasoning: string[] = []
  @State private expandedTools: string[] = []
  @State private modelName: string = '选择模型'
  @State private reasoningEffort: string = ''
  @State private currentModel: DshModelSelection | undefined = undefined
  @State private turnNotices: DshTurnNotice[] = []
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
  private remoteOrigin: string = 'connect'
  @State private remoteHostId: string = ''
  private remoteHostScope: string = ''
  private localConfigured: boolean = false
  private switchingHost: boolean = false

  @State private colors: ThemeColors = themeColors()

  private updateColors(): void {
    this.colors = themeColors(this.accentId, this.themeMode === 'dark' || (this.themeMode === 'system' && this.systemDark))
  }

  aboutToAppear(): void {
    registerDshFonts(this.getUIContext())
    this.updateColors()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    void loadAppPreferences(context).then((prefs: AppPreferenceValues) => {
      this.accentId = prefs.accentId
      this.themeMode = prefs.themeMode
      this.fontSize = prefs.fontSize
    }).catch(() => { this.errorText = '外观设置读取失败，已使用默认外观。' })
    void this.loadStartup(context)
  }

  private async loadStartup(context: common.UIAbilityContext): Promise<void> {
    const version = this.connectionVersion
    let complete = false
    try {
      complete = await loadOnboardingComplete(context)
    } catch { this.errorText = '首次引导状态暂时无法读取。' }
    try {
      const stored = await hasLocalApiKey()
      if (version !== this.connectionVersion) return
      this.hasSavedKey = stored
      this.rememberKey = stored
    } catch {
      if (version === this.connectionVersion) {
        this.credentialNotice = '安全密钥暂时无法读取。可解锁后重试，或手动输入 Key。'
      }
    }
    if (version === this.connectionVersion) this.page = complete ? 'connect' : 'onboarding'
  }

  private async finishOnboarding(): Promise<void> {
    const version = this.connectionVersion
    try { await saveOnboardingComplete(this.getUIContext().getHostContext() as common.UIAbilityContext) }
    catch { if (version === this.connectionVersion) this.errorText = '首次引导状态未能保存，下次启动可能再次显示。' }
    if (version === this.connectionVersion) this.page = this.connected ? 'chat' : 'connect'
  }

  private async prepareLocal(): Promise<void> {
    if (this.busy || this.engineReady) return
    const version = this.connectionVersion
    this.busy = true; this.errorText = ''; this.mode = 'local'
    try {
      await this.localEngine.start(this.getUIContext().getHostContext() as common.UIAbilityContext,
        (message: string) => { if (version === this.connectionVersion) this.localStage = message })
      if (version === this.connectionVersion) this.engineReady = true
      else await this.localEngine.stop()
    } catch { if (version === this.connectionVersion) this.errorText = '本机引擎准备失败，请重试。' }
    finally { if (version === this.connectionVersion) { this.busy = false; this.localStage = '' } }
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
    } catch { if (version === this.connectionVersion) this.credentialNotice = '安全密钥未能删除，请解锁后重试。' }
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
    } catch { if (version === this.connectionVersion) this.credentialNotice = '安全密钥暂时无法访问，请解锁后重试。' }
    finally { if (version === this.connectionVersion) this.busy = false }
  }

  private async showSessionOptions(): Promise<void> {
    if (!this.sessionId) await this.newSession()
    if (this.sessionId) this.page = 'sessionOptions'
  }

  private async persistPreferences(): Promise<void> {
    try {
      await saveAppPreferences(this.getUIContext().getHostContext() as common.UIAbilityContext,
        { accentId: this.accentId, themeMode: this.themeMode, fontSize: this.fontSize })
    } catch { this.errorText = '外观设置未能保存，退出后可能恢复原值。' }
  }

  private showSettings(page: string = 'home'): void {
    if (this.page !== 'settings') {
      this.settingsOrigin = this.page === 'models' ? 'models' : 'chat'
      this.settingsScope = `${this.connectionVersion}/${this.sessionId}`
    }
    this.settingsPage = page
    this.settingsRequestVersion++
    this.drawer = false
    this.page = 'settings'
  }

  private closeSettings(): void {
    this.page = this.connected ? (this.settingsScope === `${this.connectionVersion}/${this.sessionId}` ?
      this.settingsOrigin : 'chat') : 'connect'
  }

  private async showModels(): Promise<void> {
    if (this.busy || this.sending || this.switchingHost) return
    if (!this.connected) { this.page = 'connect'; return }
    this.page = 'models'
  }

  private home(): void {
    this.composerDrafts.write(this.sessionId, this.draft)
    this.chatVersion++
    void this.client.unwatchSession()
    this.sessionId = ''
    this.sessionTitle = ''
    this.messages = []
    this.tools = []
    this.turnNotices = []; this.sessionError = ''
    this.currentModel = undefined; this.pendingSessionModel = undefined; this.pendingModelSessionId = ''
    this.queuedPrompts = []
    this.questions = []
    this.todos = []; this.goal = undefined; this.todosExpanded = false; this.detailTab = 'trajectory'
    this.expandedReasoning = []
    this.expandedTools = []
    this.approval = undefined
    this.draft = this.composerDrafts.read('')
    this.running = false
    this.loadingChat = false
    this.sending = false
    this.stopping = false
    this.deciding = false
    this.modelName = '选择模型'
    this.reasoningEffort = ''
    this.page = 'chat'
    this.drawer = false
  }

  private async copyMessage(text: string): Promise<void> {
    try { await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)) }
    catch { this.errorText = '复制失败，请重试。' }
  }

  private async fork(): Promise<void> {
    if (this.busy || !this.sessionId) return
    const version = this.connectionVersion
    this.busy = true
    try {
      const id = await this.client.forkSession(this.sessionId)
      if (version === this.connectionVersion) await this.openSession(id, this.sessionTitle)
    } catch { this.errorText = '无法创建分支对话，请重试。' }
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
  @State private busy: boolean = false
  @State private refreshing: boolean = false
  @State private sending: boolean = false
  @State private deciding: boolean = false
  @State private errorText: string = ''
  @State private sessions: DshSession[] = []
  @State private workspaces: DshWorkspace[] = []
  @State private workspaceId: string = ''
  @State private sessionId: string = ''
  @State private sessionTitle: string = ''
  @State private messages: DshMessage[] = []
  @State private approval: DshApproval | undefined = undefined
  @State private running: boolean = false
  @State private loadingChat: boolean = false
  @State private stopping: boolean = false
  @State private draft: string = ''
  private client: DshClient = new DshClient((reason: string) => {
    const nextPage = this.mode === 'remote' ? 'remoteHosts' : 'connect'
    void this.disconnect(false, nextPage).then(() => {
      this.errorText = this.errorMessage(new Error(reason), '连接已断开。请重新连接。')
    })
  })
  private chatScroller: Scroller = new Scroller()
  @State private connectionVersion: number = 0
  private chatVersion: number = 0

  aboutToDisappear(): void {
    this.connectionVersion++
    this.chatVersion++
    this.client.close()
    this.modelKey = ''; this.questionDrafts.clear(); this.composerDrafts.clear()
    void this.localEngine.stop().catch(() => {})
  }

  onBackPress(): boolean {
    if (this.drawer && this.sessionsBack?.()) return true
    if (this.page === 'workspaces' && this.workspaceBack?.()) return true
    if (this.page === 'settings' && this.settingsBack?.()) return true
    if (this.page === 'engineFeatures' && this.featuresBack?.()) return true
    if (this.page === 'files' && this.filesBack?.()) return true
    if (this.page === 'models' && this.modelsBack?.()) return true
    if (this.page === 'detail' && this.detailBack?.()) return true
    if (this.page === 'onboarding' && this.onboardingBack?.()) return true
    if (this.page === 'sessionExport' && this.exportBack?.()) return true
    if (this.page === 'remoteHosts' && this.remoteBack?.()) return true
    if (this.page === 'chat' && this.viewportWidth >= 840 && this.sessionsBack?.()) return true
    if (this.drawer) { this.drawer = false; return true }
    if (this.page === 'onboarding' || this.page === 'loading') return true
    if (this.page === 'engineFeatures') { this.page = this.featureOrigin; return true }
    if (this.page === 'sessionExport') { this.page = 'features'; return true }
    if (this.page === 'remoteHosts') { this.closeRemoteHosts(); return true }
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

  private async connect(keyOverride?: string, remember?: boolean, keepOnboarding: boolean = false): Promise<boolean> {
    const local = this.mode === 'local'
    const draftKey = keyOverride || this.modelKey.trim()
    const saveKey = remember === undefined ? this.rememberKey : remember
    if (this.busy || !(local ? draftKey || this.hasSavedKey || this.localConfigured : this.address.trim())) {
      return false
    }
    const version = ++this.connectionVersion
    this.busy = true
    this.errorText = ''
    const wasEngineReady = this.engineReady
    try {
      if (local) {
        const storedKey = !draftKey && this.hasSavedKey ? await loadLocalApiKey() : undefined
        const normalizedKey = draftKey || storedKey ? normalizeProviderKey(draftKey || storedKey || '') : ''
        if (!normalizedKey && !this.localConfigured) throw new Error('已保存的 API Key 不可用，请重新输入。')
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
        this.localStage = '正在连接本机引擎…'
        await this.client.connect(endpoint.url, undefined, true)
        if (version !== this.connectionVersion) return false
        if (normalizedKey) await this.client.setLocalModelKey(normalizedKey)
        else {
          const credentials = await this.client.describeCredentials(['DEEPSEEK_API_KEY'])
          if (version !== this.connectionVersion) return false
          if (object(credentials['DEEPSEEK_API_KEY'])['configured'] !== true) {
            this.localConfigured = false
            throw new Error('本机引擎的 API Key 已失效，请重新输入。')
          }
        }
        if (version !== this.connectionVersion) return false
        this.engineReady = true
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
        } catch { this.credentialNotice = '已连接，但安全密钥保存设置未能更新，请解锁后重试。' }
        this.localWorkspace = endpoint.workspaceDir
        this.modelKey = ''
        this.host = '本机 · DeepSeek Harness'
      } else {
        const launchUrl = this.address.trim()
        await this.client.connect(launchUrl, this.authorization.trim())
        this.host = launchUrl.replace(/^https?:\/\//i, '').split(/[/?#]/)[0]
        this.authorization = ''
        this.address = launchUrl.split(/[?#]/)[0]
      }
      if (version !== this.connectionVersion) {
        return false
      }
      this.connected = true
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
      return this.connected && version === this.connectionVersion
    } catch (error) {
      if (version === this.connectionVersion) {
        if (!this.connected) {
          this.client.close()
          if (local && !wasEngineReady) {
            await this.localEngine.stop().catch(() => {})
            this.engineReady = false; this.localConfigured = false
          }
        }
        this.errorText = this.errorMessage(error as Error, local ?
          '本机引擎启动失败，请重试。' : '连接失败，请检查地址、凭据和主机状态。')
      }
      return this.connected && version === this.connectionVersion
    } finally {
      if (version === this.connectionVersion) {
        this.localStage = ''
        this.busy = false
      }
    }
  }

  private async disconnect(stopLocal: boolean = true, nextPage: string = 'connect'): Promise<void> {
    if (this.localStage === '正在停止本机引擎…') {
      return
    }
    const local = stopLocal && this.mode === 'local'
    this.connectionVersion++
    this.chatVersion++
    this.client.close()
    this.connected = false
    this.modelName = '选择模型'
    this.reasoningEffort = ''
    this.currentModel = undefined; this.pendingSessionModel = undefined; this.pendingModelSessionId = ''
    this.turnNotices = []; this.sessionError = ''
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
    this.messages = []
    this.tools = []
    this.queuedPrompts = []
    this.questions = []
    this.todos = []; this.goal = undefined; this.todosExpanded = false; this.detailTab = 'trajectory'
    this.questionDrafts.clear()
    this.composerDrafts.clear()
    this.expandedReasoning = []
    this.expandedTools = []
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
      this.localStage = '正在停止本机引擎…'
      try {
        await this.localEngine.stop()
      } catch {
        this.errorText = '本机引擎正在退出，请稍后再试。'
      } finally {
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
        this.errorText = this.errorMessage(error as Error, '无法读取会话，请检查连接。')
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
      const cwd = this.mode === 'local' ? this.localWorkspace || undefined : undefined
      const id = await this.client.createSession(this.workspaceId || undefined, cwd)
      if (version === this.connectionVersion && chatVersion === this.chatVersion) {
        this.pendingSessionModel = selected
        this.pendingModelSessionId = selected ? id : ''
        const opening = this.openSession(id, '新会话')
        const openedVersion = this.chatVersion
        await opening
        if (openedVersion !== this.chatVersion) return false
        return await this.applyPendingModel(id, version)
      }
    } catch (error) {
      if (version === this.connectionVersion) {
        this.errorText = this.errorMessage(error as Error, '创建会话失败。')
      }
    } finally {
      if (version === this.connectionVersion) {
        this.busy = false
      }
    }
    return false
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
        this.errorText = '对话已创建，但所选模型未能应用。消息尚未发送，可重试或重新选择模型。'
      }
      return false
    }
  }

  private async openSession(id: string, title: string): Promise<void> {
    this.composerDrafts.write(this.sessionId, this.draft)
    const version = ++this.chatVersion
    this.sessionId = id
    this.sessionTitle = title
    const selected = this.sessions.find((item: DshSession) => item.id === id)?.model
    this.currentModel = selected
    if (this.pendingModelSessionId !== id) { this.pendingSessionModel = undefined; this.pendingModelSessionId = '' }
    this.modelName = selected?.model || '选择模型'
    this.reasoningEffort = selected?.reasoningEffort || ''
    this.messages = []
    this.tools = []
    this.turnNotices = []; this.sessionError = ''
    this.queuedPrompts = []
    this.questions = []
    this.todos = []; this.goal = undefined; this.todosExpanded = false; this.detailTab = 'trajectory'
    this.expandedReasoning = []
    this.expandedTools = []
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
        this.tools = update.tools || []
        this.turnNotices = update.notices || []
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
        if (update.error) {
          this.errorText = this.errorMessage(new Error(update.error), '会话连接已断开。')
        }
        if (followLatest && this.messages.length > 0) {
          first = false
          this.scrollToLatest(version)
        }
      })
    } catch (error) {
      if (version === this.chatVersion) {
        this.loadingChat = false
        this.errorText = this.errorMessage(error as Error, '无法加载会话。返回列表后可以重试。')
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

  private async send(): Promise<void> {
    const value = this.draft.trim()
    if (this.loadingChat || this.sending || this.busy || !value) {
      return
    }
    if (!this.sessionId) {
      const created = await this.newSession()
      if (!created) {
        if (this.connected && this.sessionId === this.pendingModelSessionId && !this.draft.trim()) this.draft = value
        return
      }
      if (!this.draft.trim()) this.draft = value
      if (this.composerDrafts.read('') === value) this.composerDrafts.write('', '')
    }
    const version = this.chatVersion
    const connectionVersion = this.connectionVersion
    const id = this.sessionId
    this.sending = true
    this.errorText = ''
    try {
      if (!await this.applyPendingModel(id, connectionVersion)) return
      if (version !== this.chatVersion || connectionVersion !== this.connectionVersion) return
      await this.client.prompt(id, value)
      if (version === this.chatVersion && this.draft.trim() === value) {
        this.draft = ''
        this.composerDrafts.write(this.sessionId, '')
        this.scrollToLatest(version)
      }
    } catch (error) {
      if (version === this.chatVersion) {
        this.errorText = this.errorMessage(error as Error, '发送失败，输入内容已保留。')
      }
    } finally {
      if (version === this.chatVersion) {
        this.sending = false
      }
    }
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
    const text = notice.recovery === 'continue' ? '继续' : notice.retryText
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
      if (connectionVersion === this.connectionVersion) this.submittedRecoveries = this.submittedRecoveries.concat(key)
    } catch {
      if (chatVersion === this.chatVersion && connectionVersion === this.connectionVersion) {
        this.errorText = '尚未确认恢复请求是否送达。可先查看对话，再重试同一次请求。'
      }
    } finally {
      if (chatVersion === this.chatVersion && connectionVersion === this.connectionVersion) this.sending = false
    }
  }

  private async stop(): Promise<void> {
    if (this.stopping || !this.running) {
      return
    }
    this.stopping = true
    const version = this.chatVersion
    this.errorText = ''
    try {
      await this.client.cancel(this.sessionId)
    } catch (error) {
      if (version === this.chatVersion) {
        this.errorText = this.errorMessage(error as Error, '停止请求失败。')
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
        this.errorText = this.errorMessage(error as Error, '未能提交审批，请确认主机状态。')
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

  private timeline(): ChatRow[] {
    return this.chatTimeline.update(this.sessionId, this.messages, this.tools, this.turnNotices)
  }

  private showDetail(tab: string = 'trajectory'): void { this.detailTab = tab; this.page = 'detail' }
  private showFiles(): void { this.filesOrigin = this.page === 'detail' ? 'detail' : 'chat'; this.page = 'files' }

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

  private async connectRemote(connection: RemoteHostConnection): Promise<boolean> {
    if (this.busy || this.switchingHost) return false
    this.switchingHost = true
    try {
      await this.disconnect(false, 'remoteHosts')
      this.mode = 'remote'
      this.address = connection.launchUrl
      this.authorization = connection.authorization
      const success = await this.connect()
      if (success) {
        this.remoteHostId = connection.id; this.host = connection.name
        this.remoteHostScope = connection.launchUrl.split(/[?#]/)[0]
      } else this.page = 'remoteHosts'
      return success
    } finally {
      this.address = ''; this.authorization = ''; this.switchingHost = false
    }
  }

  private async stopLocalEngine(): Promise<boolean> {
    if (this.busy) return false
    if (this.mode === 'local') { await this.disconnect(); return !this.errorText }
    this.busy = true
    try {
      await this.localEngine.stop()
      this.engineReady = false; this.localConfigured = false; this.localWorkspace = ''
      return true
    } catch { this.errorText = '本机引擎未能停止，请重试。'; return false }
    finally { this.busy = false }
  }

  @Builder
  private iconButton(glyph: string, label: string, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      Text(glyph).fontFamily(DshGlyphs.family).fontSize(22).fontColor(this.colors.text)
    }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText(label).onClick(action)
  }

  @Builder
  private notice() {
    if (this.credentialNotice) {
      Row({ space: 8 }) {
        Text(this.credentialNotice).fontSize(14).fontColor(this.colors.warning).layoutWeight(1)
        Button('×').fontSize(20).fontColor(this.colors.warning).backgroundColor(Color.Transparent)
          .width(36).height(36).accessibilityText('关闭密钥提示').onClick(() => this.credentialNotice = '')
      }.width('100%').padding(12).backgroundColor(this.colors.surface).borderRadius(14)
    }
    if (this.errorText) {
      Row({ space: 8 }) {
        Text(this.errorText).fontSize(14).fontColor(this.colors.danger).layoutWeight(1)
        Button('×').fontSize(20).fontColor(this.colors.danger).backgroundColor(Color.Transparent)
          .width(36).height(36).accessibilityText('关闭提示').onClick(() => this.errorText = '')
      }.width('100%').padding(12).backgroundColor(this.colors.surface).borderRadius(14)
    }
    if (this.page === 'chat' && this.sessionError && !this.errorText) {
      Row({ space: 8 }) {
        Text(this.sessionError).fontSize(14).fontColor(this.colors.danger).layoutWeight(1)
        Button('×').fontSize(20).fontColor(this.colors.danger).backgroundColor(Color.Transparent)
          .width(36).height(36).accessibilityText('关闭会话提示').onClick(() => this.client.dismissSessionError(this.sessionId))
      }.width('100%').padding(12).backgroundColor(this.colors.surface).borderRadius(14)
    }
  }

  @Builder
  private connectScreen() {
    Scroll() {
      Column({ space: 24 }) {
        Row() {
          Blank()
          this.iconButton(DshGlyphs.settings, '设置', () => this.showSettings())
        }.width('100%')
        Column({ space: 14 }) {
          Image($r('app.media.app_icon')).width(76).height(76).objectFit(ImageFit.Contain).borderRadius(16)
          Text($r('app.string.app_name')).fontSize(36).fontWeight(FontWeight.Bold).fontColor(this.colors.text)
          Text('在鸿蒙上运行或连接\nDeepSeek Harness').fontSize(17).fontColor(this.colors.muted).textAlign(TextAlign.Center)
        }.width('100%').padding({ top: 20, bottom: 12 })
        Column({ space: 18 }) {
          Text('DSH 在哪里运行？').fontSize(21).fontWeight(FontWeight.Medium).fontColor(this.colors.text)
          Row({ space: 10 }) {
            this.modeButton('local', '本机')
            this.modeButton('remote', '远程主机')
          }.width('100%')
          if (this.mode === 'local') {
            Text('连接 DeepSeek').fontSize(18).fontColor(this.colors.text).width('100%')
            Text('API Key').fontSize(13).fontColor(this.colors.muted).width('100%')
            TextInput({ placeholder: this.hasSavedKey ? '已安全保存，留空使用已保存的 Key' : '输入 DeepSeek API Key', text: this.modelKey })
              .type(InputType.Password).height(50).fontSize(16).fontColor(this.colors.text)
              .backgroundColor(this.colors.surfaceAlt).enableAutoFill(false).enabled(!this.busy)
              .maxLength(1024)
              .accessibilityText('DeepSeek API Key').onChange((value: string) => this.modelKey = value)
            Row({ space: 8 }) {
              Checkbox({ name: 'rememberKey' }).select(this.rememberKey).selectedColor(this.colors.primary)
                .enabled(!this.busy).onChange((selected: boolean) => this.rememberKey = selected)
              Text('安全保存 API Key').fontSize(14).fontColor(this.colors.text)
            }.width('100%')
            Text('勾选后由鸿蒙安全资产存储保护，下次启动可直接使用。').fontSize(12).fontColor(this.colors.muted)
            if (this.hasSavedKey) {
              Button('删除已保存的 Key').fontSize(13).fontColor(this.colors.danger).backgroundColor(Color.Transparent)
                .enabled(!this.busy).onClick(() => { void this.forgetKey() })
            }
            if (this.credentialNotice) {
              Button('重新检查已保存的 Key').fontSize(13).fontColor(this.colors.primary).backgroundColor(Color.Transparent)
                .enabled(!this.busy).onClick(() => { void this.refreshSavedKey() })
            }
          } else {
            Text('连接主机').fontSize(18).fontColor(this.colors.text).width('100%')
            TextInput({ placeholder: 'DSH 启动链接', text: this.address }).type(InputType.URL)
              .height(50).fontSize(15).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
              .enableAutoFill(false).enabled(!this.busy).onChange((value: string) => this.address = value)
            TextInput({ placeholder: '反向代理授权（可选）', text: this.authorization }).type(InputType.Password)
              .height(50).fontSize(15).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
              .enableAutoFill(false).enabled(!this.busy).onChange((value: string) => this.authorization = value)
          }
          this.notice()
          if (this.busy) { LoadingProgress().width(32).height(32).color(this.colors.primary) }
          Button(this.busy ? (this.localStage || '连接中…') : (this.mode === 'local' ? '启动本机引擎' : '连接主机'))
            .width('100%').height(48).fontColor(this.colors.onPrimary).backgroundColor(this.colors.primary)
            .enabled(!this.busy && (this.mode === 'local' ? !!this.modelKey.trim() || this.hasSavedKey || this.localConfigured : !!this.address.trim()))
            .onClick(() => { void this.connect() })
        }.alignItems(HorizontalAlign.Start).padding(24).width('100%').backgroundColor(this.colors.surface).borderRadius(24)
        Text(this.mode === 'local' ? 'DeepSeek Harness 在本机运行，模型回复需要联网。' : '文件、命令和任务在当前连接的电脑上执行。')
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
    SessionsPanel({ colors: this.colors, client: this.client, sessions: this.sessions,
      workspaces: this.workspaces, workspaceId: this.workspaceId, selectedId: this.sessionId,
      host: this.mode === 'local' ? '本机' : this.host, refreshing: this.refreshing,
      onSelect: (id: string, title: string) => { void this.openSession(id, title) },
      onNew: () => this.home(), onRefresh: () => { void this.refreshSessions() },
      onDeleted: (ids: string[]) => { if (ids.includes(this.sessionId)) this.home() },
      onBackHandler: (handler?: () => boolean) => { this.sessionsBack = handler },
      onWorkspaceSelect: (id: string) => this.workspaceId = id,
      onSettings: () => this.showSettings(), onFeatures: () => { this.drawer = false; this.page = 'features' },
      onHost: () => this.showRemoteHosts(),
      onManageWorkspaces: () => { this.drawer = false; this.page = 'workspaces' }, onClose: () => this.drawer = false })
  }

  @Builder
  private approvalCard(item: DshApproval) {
    Column({ space: 10 }) {
      Text('需要你的确认').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.colors.warning)
      Scroll() {
        Text(item.title).fontSize(14).fontColor(this.colors.text).width('100%').copyOption(CopyOptions.LocalDevice)
      }.width('100%').constraintSize({ maxHeight: 160 }).align(Alignment.TopStart)
      if (item.canAllow !== true) {
        Text('主机未提供足够的操作详情。').fontSize(13).fontColor(this.colors.muted)
      }
      Row({ space: 10 }) {
        Button('拒绝').height(44).layoutWeight(1).backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.danger)
          .enabled(!this.deciding).onClick(() => { void this.decide(item.id, false) })
        Button('允许本次').height(44).layoutWeight(1).backgroundColor(this.colors.primary).fontColor(this.colors.onPrimary)
          .enabled(!this.deciding && item.canAllow === true).onClick(() => { void this.decide(item.id, true) })
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(16).backgroundColor(this.colors.surface).borderRadius(18)
  }

  @Builder
  private messageMenu(item: DshMessage) {
    Menu() {
      MenuItem({ content: '复制' }).onClick(() => { void this.copyMessage(item.text) })
      MenuItem({ content: '引用' }).onClick(() => { this.draft = item.text.split('\n').map((line: string) => `> ${line}`).join('\n') + '\n\n' })
    }
  }

  @Builder
  private messageRow(item: DshMessage) {
              Column({ space: 9 }) {
                if (item.role !== 'user') {
                  Row({ space: 8 }) {
                    Text(item.role === 'assistant' ? 'DeepSeek' : '工具').fontSize(13).fontWeight(FontWeight.Medium)
                      .fontColor(this.colors.muted).layoutWeight(1)
                    Button({ type: ButtonType.Circle }) {
                      Text(DshGlyphs.more).fontFamily(DshGlyphs.family).fontSize(18).fontColor(this.colors.hint)
                    }.width(36).height(36).backgroundColor(Color.Transparent).accessibilityText('消息操作')
                      .bindMenu(this.messageMenu(item))
                  }.width('100%')
                }
                if (item.reasoning) {
                  Column({ space: 8 }) {
                    Button(this.expandedReasoning.includes(item.id) ? '收起思考过程' : '思考过程', { type: ButtonType.Normal })
                      .height(36).fontSize(13).backgroundColor(Color.Transparent).fontColor(this.colors.muted)
                      .onClick(() => this.toggleReasoning(item.id))
                    if (this.expandedReasoning.includes(item.id)) {
                      MessageBody({ text: item.reasoning, colors: this.colors, fontSize: this.fontSize - 1 })
                    }
                  }.width('100%').alignItems(HorizontalAlign.Start).padding(10).backgroundColor(this.colors.surfaceAlt).borderRadius(12)
                }
                if (item.text) MessageBody({ text: item.text, colors: this.colors, fontSize: this.fontSize })
                if (item.usage) {
                  Text(`${item.usage.inputTokens} 输入 · ${item.usage.outputTokens} 输出 tokens`).fontSize(11).fontColor(this.colors.hint)
                }
              }.alignItems(HorizontalAlign.Start).width('100%').padding(item.role === 'user' ? 16 : 4)
                .backgroundColor(item.role === 'user' ? this.colors.bubble : Color.Transparent).borderRadius(20)
                .bindContextMenu(this.messageMenu(item), ResponseType.LongPress)
  }

  @Builder
  private toolRow(item: DshTool) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text(item.isError ? '!' : (item.result === undefined ? '·' : '✓')).fontSize(16)
          .fontColor(item.isError ? this.colors.danger : this.colors.primary)
        Text(item.name).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.colors.text).layoutWeight(1)
        Text(this.expandedTools.includes(item.callId) ? '⌃' : '⌄').fontColor(this.colors.muted)
      }.width('100%').onClick(() => this.toggleTool(item.callId))
      if (this.expandedTools.includes(item.callId)) {
        if (item.arguments) {
          Text(item.arguments).fontFamily('JetBrainsMono').fontSize(12).fontColor(this.colors.muted)
            .width('100%').copyOption(CopyOptions.LocalDevice)
        }
        if (item.result !== undefined) {
          Scroll() {
            Text(item.result).fontFamily('JetBrainsMono').fontSize(12).fontColor(item.isError ? this.colors.danger : this.colors.text)
              .width('100%').copyOption(CopyOptions.LocalDevice)
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
            Button(item.recovery === 'continue' ? '继续' : '重试').height(40).fontColor(this.colors.primary)
              .backgroundColor(this.colors.surfaceAlt).margin({ right: 8, bottom: 4 })
              .enabled(this.canRecoverTurn(item)).onClick(() => { void this.recoverTurn(item) })
          }
          if (item.code?.startsWith('ACCOUNT_')) {
            Button('查看账号').height(40).fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt)
              .enabled(!this.sending && !this.busy).onClick(() => this.showSettings('account'))
          } else if (['MISSING_CREDENTIAL', 'INVALID_CREDENTIAL', 'AUTH', 'QUOTA'].includes(item.code || '')) {
            Button('模型与服务商').height(40).fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt)
              .enabled(!this.sending && !this.busy).onClick(() => this.showSettings('models'))
          } else if (['MODEL_UNSUPPORTED', 'UNSUPPORTED_REASONING_EFFORT', 'CLIENT_UPGRADE_REQUIRED'].includes(item.code || '')) {
            Button('选择模型').height(40).fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt)
              .enabled(!this.sending && !this.busy).onClick(() => { void this.showModels() })
          }
        }.width('100%')
      }
    }.width('100%').padding(14).backgroundColor(this.colors.surface).borderRadius(14)
      .border({ width: 1, color: this.colors.border })
  }

  @Builder
  private chatScreen() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        if (this.viewportWidth < 840) this.iconButton(DshGlyphs.menu, '对话列表', () => this.showSessions())
        Column({ space: 3 }) {
          Text(this.sessionTitle || $r('app.string.app_name')).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.colors.text)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 5 }) {
            Circle().width(5).height(5).fill(this.running ? this.colors.primary : this.colors.success)
            Text(this.running ? '生成中' : (this.mode === 'local' ? '本机' : '远程主机')).fontSize(11).fontColor(this.colors.muted)
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1).padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .backgroundColor(this.colors.surface).borderRadius(24)
          .onClick(() => { if (this.sessionId) this.showDetail() })
        Button(this.modelName, { type: ButtonType.Normal }).height(44).constraintSize({ maxWidth: 130 }).fontSize(13)
          .fontColor(this.colors.primary).backgroundColor(this.colors.surface).borderRadius(22)
          .enabled(!this.busy && !this.sending)
          .onClick(() => { void this.showModels() })
        this.iconButton(DshGlyphs.add, '新对话', () => this.home())
      }.width('100%').height(56)
      this.notice()
      if (!this.sessionId) {
        Column({ space: 16 }) {
          Blank()
          Image($r('app.media.app_icon')).width(64).height(64).objectFit(ImageFit.Contain).borderRadius(14)
          Text('今天想做点什么？').fontSize(26).fontWeight(FontWeight.Medium).fontColor(this.colors.text)
          Blank()
        }.layoutWeight(1).width('100%')
      } else {
        List({ scroller: this.chatScroller, space: 20 }) {
          if (this.loadingChat) {
            ListItem() { LoadingProgress().width(32).height(32).color(this.colors.primary) }
          }
          ForEach(this.timeline(), (row: ChatRow) => {
            ListItem() {
              if (row.message) this.messageRow(row.message)
              else if (row.tool) this.toolRow(row.tool)
              else if (row.notice) this.turnNoticeRow(row.notice)
            }
          }, (row: ChatRow) => row.key)
          ForEach(this.questions, (question: DshQuestionRequest) => {
            ListItem() {
              QuestionCard({ colors: this.colors, request: question, client: this.client, draftStore: this.questionDrafts })
            }
          }, (question: DshQuestionRequest) => `${question.sessionId}/${question.id}/${question.continued}`)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      }
      if (this.approval) this.approvalCard(this.approval)
      if (this.goal) {
        Row({ space: 8 }) {
          Text('目标').fontSize(13).fontColor(this.colors.primary)
          Text(goalHeadline(this.goal.objective))
            .fontSize(13).fontColor(this.colors.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          Text('›').fontColor(this.colors.muted)
        }.width('100%').padding(10).backgroundColor(this.colors.surface).borderRadius(14)
          .accessibilityText('查看目标与进展').onClick(() => this.showDetail('progress'))
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
        ChatActivityPanel({ colors: this.colors, sessionId: this.sessionId, queue: this.queuedPrompts, client: this.client,
          onRecover: (sessionId: string, connection: number, text: string) => {
            if (connection !== this.client.connectionIdentity()) return
            if (sessionId === this.sessionId) this.composerDrafts.write(sessionId, this.draft)
            const recovered = this.composerDrafts.append(sessionId, text)
            if (sessionId === this.sessionId) {
              this.draft = recovered
              this.errorText = '排队消息已放回输入框，请检查后再发送。'
            }
          } })
      }
      Column({ space: 6 }) {
        TextArea({ placeholder: '发消息…', text: this.draft }).fontSize(this.fontSize).fontColor(this.colors.text)
          .placeholderColor(this.colors.hint).backgroundColor(Color.Transparent).height(64).width('100%')
          .padding({ left: 14, right: 14, top: 10, bottom: 4 }).accessibilityText('消息输入框')
          .onChange((value: string) => this.draft = value)
        Row({ space: 8 }) {
          this.iconButton(DshGlyphs.add, '更多功能', () => this.page = 'features')
          this.iconButton(DshGlyphs.settings, '对话选项', () => { void this.showSessionOptions() })
          if (this.workspaceId) {
            Text(this.workspaces.find((item: DshWorkspace) => item.id === this.workspaceId)?.title || '工作区')
              .fontSize(12).fontColor(this.colors.muted).maxLines(1).layoutWeight(1)
          } else { Blank() }
          if (this.running && !this.draft.trim()) {
            Button({ type: ButtonType.Circle }) {
              Text(DshGlyphs.stop).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.onPrimary)
            }.width(42).height(42).backgroundColor(this.colors.primary).enabled(!this.stopping)
              .accessibilityText('停止生成').onClick(() => { void this.stop() })
          } else {
            Button({ type: ButtonType.Circle }) {
              if (this.sending || this.busy) { LoadingProgress().width(22).height(22).color(this.colors.onPrimary) }
              else { Text(DshGlyphs.send).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.onPrimary) }
            }.width(42).height(42).backgroundColor(this.colors.primary)
              .enabled(!this.loadingChat && !this.sending && !this.busy && this.draft.trim().length > 0)
              .accessibilityText(this.running ? '加入消息队列' : '发送消息').onClick(() => { void this.send() })
          }
        }.width('100%').padding({ left: 4, right: 8, bottom: 8 })
      }.width('100%').backgroundColor(this.colors.surface).borderRadius(26)
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
        this.iconButton(DshGlyphs.back, '返回', () => this.page = 'chat')
        Text('全部功能').fontSize(23).fontWeight(FontWeight.Medium).fontColor(this.colors.text)
      }.width('100%')
      Scroll() {
        Column({ space: 10 }) {
          Text('对话').fontSize(13).fontColor(this.colors.muted).width('100%').padding(8)
          this.featureRow(DshGlyphs.chat, '对话详情', '查看当前对话和记录', () => {
            if (this.sessionId) this.showDetail()
            else this.errorText = '请先打开或创建一个对话。'
          })
          this.featureRow(DshGlyphs.file, '工作区文件', '浏览当前对话的文件', () => {
            if (this.sessionId) this.showFiles()
            else this.errorText = '请先打开或创建一个对话。'
          })
          this.featureRow(DshGlyphs.folder, '工作区', '切换和管理工作目录', () => this.page = 'workspaces')
          this.featureRow(DshGlyphs.file, '导出会话日志', '打包当前会话及其子会话', () => {
            if (this.sessionId) this.page = 'sessionExport'
            else this.errorText = '请先打开或创建一个对话。'
          })
          Text('能力').fontSize(13).fontColor(this.colors.muted).width('100%').padding(8)
          this.featureRow(DshGlyphs.plugin, '插件', '插件、预设与市场', () => this.openFeature('plugins'))
          this.featureRow(DshGlyphs.file, '技能', '浏览和使用工作区技能', () => this.openFeature('skills'))
          this.featureRow(DshGlyphs.chat, '子代理与团队', '查看分工、对话与进度', () => this.openFeature('agents'))
          this.featureRow(DshGlyphs.terminal, '后台任务', '查看任务输出与运行状态', () => this.openFeature('jobs'))
          this.featureRow(DshGlyphs.host, '自动化任务', '定时运行、历史与配置', () => this.openFeature('schedules'))
          Text('模型与应用').fontSize(13).fontColor(this.colors.muted).width('100%').padding(8)
          this.featureRow(DshGlyphs.model, '模型与渠道', '配置模型与提供方', () => this.showSettings('models'))
          this.featureRow(DshGlyphs.settings, '引擎参数', '调整 DeepSeek Harness', () => this.showSettings('parameters'))
          this.featureRow(DshGlyphs.host, '本机引擎', '运行状态与引擎管理', () => this.showSettings('engine'))
          this.featureRow(DshGlyphs.settings, '外观', '主题、配色与阅读字号', () => this.showSettings('appearance'))
          this.featureRow(DshGlyphs.settings, '设置', '应用设置', () => this.showSettings())
          this.notice()
        }.width('100%')
      }.width('100%').layoutWeight(1)
    }.padding(16).width('100%').height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Row() {
        if (this.connected && this.viewportWidth >= 840) {
          Column() { this.sessionDrawer() }.width(310).height('100%')
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
              onFinish: () => { void this.finishOnboarding() },
              onRemote: () => this.showRemoteHosts() })
          } else if (this.page === 'connect') this.connectScreen()
          else if (this.page === 'remoteHosts') {
            RemoteHostsPanel({ colors: this.colors, connected: this.connected, currentId: this.remoteHostId,
              currentName: this.mode === 'local' ? '本机' : this.host, connecting: this.busy, errorText: this.errorText,
              onBackHandler: (handler?: () => boolean) => { this.remoteBack = handler },
              onConnect: (connection: RemoteHostConnection) => this.connectRemote(connection),
              onLocal: () => this.switchHost('local'), onClose: () => this.closeRemoteHosts() })
          }
          else if (this.page === 'settings') {
            SettingsPanel({ colors: this.colors, client: this.client, connected: this.connected,
              connectionIdentity: this.connectionVersion,
              savedLocalKey: this.hasSavedKey,
              onLocalKeyStored: (stored: boolean) => { this.hasSavedKey = stored; this.rememberKey = stored },
              onBackHandler: (handler?: () => boolean) => { this.settingsBack = handler },
              local: this.mode === 'local', initialPage: this.settingsPage, requestVersion: this.settingsRequestVersion,
              engineStatus: this.localStage || (this.engineReady ? '运行中' : '已停止'),
              engineRunning: this.engineReady, engineBusy: this.busy,
              accentId: this.accentId, themeMode: this.themeMode, fontSize: this.fontSize,
              onClose: () => this.closeSettings(),
              onThemeChange: (accent: string, mode: string) => {
                this.accentId = accent; this.themeMode = mode; void this.persistPreferences()
              }, onFontSizeChange: (size: number) => { this.fontSize = size; void this.persistPreferences() },
              onStartEngine: () => this.switchHost('local'), onStopEngine: () => { void this.stopLocalEngine() },
              onRestartEngine: () => { void this.stopLocalEngine().then((stopped: boolean) => {
                if (stopped) this.switchHost('local')
              }) },
              onOpenHosts: () => this.switchHost('remote'),
              onOpenPlugins: () => this.openFeature('plugins') })
          } else if (this.page === 'workspaces') {
            WorkspacesPanel({ colors: this.colors, client: this.client, workspaces: this.workspaces,
              workingDir: this.mode === 'local' ? this.localWorkspace : '',
              hostScope: this.mode === 'local' ? 'local' : this.remoteHostScope,
              onBackHandler: (handler?: () => boolean) => { this.workspaceBack = handler },
              onClose: () => this.page = 'chat', onSelect: (id: string) => { this.workspaceId = id; this.home() } })
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
            EngineFeaturesPanel({ colors: this.colors, client: this.client, sessionId: this.sessionId,
              onBackHandler: (handler?: () => boolean) => { this.featuresBack = handler },
              kind: this.featureKind, onClose: () => this.page = this.featureOrigin,
              onOpenSession: (id: string) => { void this.openSession(id, '对话') },
              onUseSkill: (command: string, newSession: boolean) => {
                if (newSession) this.home()
                this.draft = command
                this.page = 'chat'
              } })
          } else if (this.page === 'sessionOptions') {
            SessionOptionsPanel({ colors: this.colors, client: this.client, sessionId: this.sessionId, local: this.mode === 'local',
              onClose: () => this.page = 'chat' })
          } else if (this.page === 'sessionExport') {
            SessionExportPanel({ colors: this.colors, client: this.client, sessionId: this.sessionId,
              onBackHandler: (handler?: () => boolean) => { this.exportBack = handler }, onClose: () => this.page = 'features' })
          } else if (this.page === 'detail') {
            SessionDetailPanel({ colors: this.colors, client: this.client, sessionId: this.sessionId, title: this.sessionTitle,
              onBackHandler: (handler?: () => boolean) => { this.detailBack = handler },
              initialTab: this.detailTab, onClose: () => this.page = 'chat', onFiles: () => this.showFiles(),
              onAgents: () => this.openFeature('agents'), onPlugins: () => this.openFeature('plugins'),
              onFork: () => { void this.fork() } })
          } else if (this.page === 'files') {
            FilesPanel({ colors: this.colors, client: this.client, sessionId: this.sessionId,
              onBackHandler: (handler?: () => boolean) => { this.filesBack = handler }, onClose: () => this.page = this.filesOrigin })
          } else if (this.page === 'features') this.featuresScreen()
          else this.chatScreen()
        }.layoutWeight(1).height('100%')
      }.width('100%').height('100%')
      if (this.drawer && this.viewportWidth < 840) {
        Row() {
          Column() { this.sessionDrawer() }.width(this.viewportWidth > 480 ? 380 : '88%').height('100%')
          Column().layoutWeight(1).height('100%').backgroundColor('#55000000').onClick(() => this.drawer = false)
        }.width('100%').height('100%').transition(TransitionEffect.move(TransitionEdge.START))
      }
    }.width('100%').height('100%').backgroundColor(this.colors.background)
      .onAreaChange((oldValue: Area, newValue: Area) => { this.viewportWidth = Number(newValue.width) })
  }
}
