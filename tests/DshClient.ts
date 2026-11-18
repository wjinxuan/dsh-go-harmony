import { CompanionSignalSse, signalCapability, signalDecode, signalRun, signalId } from './CompanionSignalProtocol';
import type { CompanionSignalCapability, CompanionRunReceipt, CompanionSignalFrame } from './CompanionSignalProtocol';
import { dsBotAnswer, DSBOT_ENDPOINTS, DsBotSseParser } from './DsBotProtocol';
import { url, util } from '@kit.ArkTS';
import { webSocket } from '@kit.NetworkKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import type { DraftAttachment } from '../ui/AttachmentPicker';
import type { SpeechCatalog, SpeechTranscript } from './SpeechData';
import { checkSpeechWav, speechCatalog, speechTranscript } from './SpeechData';
import { parseBinaryRpcResponse } from './DshBinaryResponse';
import { approvalFromEvent, array, commandCatalog, commandResult, createMuxOpen,
      createRpcRequest, DshRpcError, DshTranscript, goalRef, goalView, localSessionError, modelCatalog, modelSelection,
      modelSelectionResult, normalizeProviderKey, number, object, parseRpcResponse, permissionCatalog, questionFromEvent,
      sessionPage, sessionProjections, string, strings, turnTraces, wireError, workspaceListing, workspaceText } from './DshWire';



export type DshSubscription = () => void;

class DshAttachmentPreparationError extends Error {}

export interface DshDuplexStream {
  write: (value: WireObject) => Promise<void>;
  cancel: DshSubscription;
}

export interface DshWebSession {
  baseUrl: string;
  cookie: string;
  authorization: string;
  generation: number;
}

export interface DshEngineCapabilities {
  local: boolean;
  settingsWritable: boolean;
  pluginManagement: boolean;
  settingsNamespaces: string[];
  presets: string[];
}

function requestArgs(request: WireObject): WireObject {
  const args: WireObject = {};
  args['request'] = request;
  return args;
}

function sessionRequest(sessionId: string): WireObject {
  const request: WireObject = {};
  request['sessionId'] = sessionId;
  return request;
}

function workspaceFileArgs(sessionId: string, path: string): WireObject {
  const args: WireObject = {};
  args['workspaceFileScopeId'] = sessionId;
  args['path'] = path || '.';
  return args;
}

interface Subscription {
  id: string;
  consume: (value: WireObject) => void;
  fail: (reason: string) => void;
}

interface PendingApproval {
  request: DshApproval;
  callId: string;
  toolName: string;
}

interface QuestionWait {
  stop?: DshSubscription;
  timer?: number;
}

function agentArgs(sessionId: string): WireObject {
  const args: WireObject = {};
  args['agentId'] = sessionId;
  return args;
}

export class DshClient {
  private socket?: webSocket.WebSocket;
  private ownedConnections: Set<DshClient> = new Set();
  private connectionOwner?: DshClient;
  private http?: rcp.Session;
  private base: string = '';
  private local: boolean = false;
  private proxy: 'system' | 'no-proxy' = 'system';
  private binaryUploadMissing: boolean = false;
  private headers: rcp.RequestHeaders = {};
  private events?: Subscription;
  private workspaceStream?: Subscription;
  private sessionStream?: Subscription;
  private streams: Map<string, Subscription> = new Map();
  private signalReceipts: WeakSet<CompanionRunReceipt> = new WeakSet();
  private signalCapabilities: Map<CompanionSignalCapability, number> = new Map();
  private signalSubscriptions: Set<DshSubscription> = new Set();
  private hostListeners: Set<(event: WireObject) => void> = new Set();
  private clientId: string = '';
  private generation: number = 0;
  private transcript?: DshTranscript;
  private sessionControlStop?: DshSubscription;
  private chatCallback?: (update: DshChatUpdate) => void;
  private workspaces: DshWorkspace[] = [];
  private archived: string[] = [];
  private pinned: string[] = [];
  private approvals: Map<string, PendingApproval> = new Map();
  private questions: Map<string, DshQuestionRequest> = new Map();
  private questionWaits: Map<string, QuestionWait> = new Map();
  private queueMove?: DshTranscript;
  private onDisconnected?: (reason: string) => void;

  constructor(onDisconnected?: (reason: string) => void) {
    this.onDisconnected = onDisconnected;
  }

  async connect(launchUrl: string, authorization?: string, local: boolean = false): Promise<void> {
    this.close();
    let address: url.URL;
    try {
      address = url.URL.parseURL(launchUrl.trim());
    } catch {
      throw new Error('请输入 DSH 打印的完整启动链接');
    }
    const loopback = ['127.0.0.1', 'localhost', '[::1]', '::1'].includes(address.hostname);
    if (local && (address.protocol !== 'http:' || address.hostname !== '127.0.0.1')) {
      throw new Error('本机引擎必须连接到手机回环地址');
    }
    if (address.protocol !== 'https:' && !(address.protocol === 'http:' && loopback)) {
      throw new Error('远程主机链接必须使用 HTTPS');
    }
    if (address.username || address.password || address.hash || !address.params.get('token')) {
      throw new Error('请输入含 token 参数的 DSH 启动链接');
    }
    const auth = authorization?.trim() ?? '';
    if (/[\r\n\u0000]/.test(auth)) {
      throw new Error('代理认证请求头格式无效');
    }
    this.base = address.origin + address.pathname.replace(/\/+$/, '');
    this.local = local;
    this.proxy = loopback ? 'no-proxy' : 'system';
    const headers: rcp.RequestHeaders = {};
    if (auth) {
      headers.authorization = auth;
    }
    let http: rcp.Session;
    try {
      http = rcp.createSession({
        requestConfiguration: {
          proxy: this.proxy,
          transfer: { autoRedirect: false, timeout: { connectMs: 10000, transferMs: 20000 } }
        }
      });
    } catch {
      throw new Error('无法创建 DSH 网络连接');
    }
    this.http = http;
    try {
      let response: rcp.Response;
      try {
        response = await http.fetch(new rcp.Request(address.toString(), 'GET', headers));
      } catch {
        throw new Error('无法访问 DSH 主机，请检查网络和 HTTPS 证书');
      }
      if (this.http !== http) {
        throw new Error('连接已取消');
      }
      if (response.statusCode !== 302 && response.statusCode !== 303) {
        throw new Error(response.statusCode === 401 ? '启动令牌无效，或代理认证失败' :
          `DSH 登录失败（HTTP ${response.statusCode}）`);
      }
      const cookie = response.cookies?.find((item: rcp.ResponseCookie) => item.name.startsWith('dsh-auth-'));
      const raw = response.headers['set-cookie'];
      const rawCookies = typeof raw === 'string' ? [raw] : raw ?? [];
      const rawCookie = rawCookies.map((entry: string) => entry.split(';', 1)[0].trim())
        .find((entry: string) => entry.startsWith('dsh-auth-'));
      headers.cookie = cookie ? `${cookie.name}=${cookie.value}` : rawCookie;
      if (!headers.cookie) {
        throw new Error('主机没有返回 DSH 登录 Cookie');
      }
      this.headers = headers;
      await this.openSocket();
    } catch (error) {
      if (this.http === http) {
        this.close();
      }
      throw new Error(error instanceof Error ? error.message : 'DSH 连接失败');
    }
  }

  close(): void {
    this.connectionOwner?.ownedConnections.delete(this);
    this.connectionOwner = undefined;
    for (const child of Array.from(this.ownedConnections)) child.close();
    this.ownedConnections.clear();
    this.generation++;
    this.signalSubscriptions.forEach((stop: DshSubscription) => stop());
    this.signalSubscriptions.clear();
    this.signalCapabilities.clear();
    const socket = this.socket;
    const http = this.http;
    this.socket = undefined;
    this.http = undefined;
    this.base = '';
    this.local = false;
    this.proxy = 'system';
    this.binaryUploadMissing = false;
    this.headers = {};
    this.clientId = '';
    const events = this.events;
    const workspaceStream = this.workspaceStream;
    const sessionStream = this.sessionStream;
    this.events = undefined;
    this.workspaceStream = undefined;
    this.sessionStream = undefined;
    this.stopChatControl();
    events?.fail('连接已关闭');
    workspaceStream?.fail('连接已关闭');
    sessionStream?.fail('连接已关闭');
    this.transcript = undefined;
    this.chatCallback = undefined;
    this.workspaces = [];
    this.archived = [];
    this.pinned = [];
    this.approvals.clear();
    this.questions.clear();
    const streams = Array.from(this.streams.values());
    this.streams.clear();
    this.hostListeners.clear();
    for (const stream of streams) {
      stream.fail('连接已关闭');
    }
    http?.close();
    if (socket) {
      socket.off('open');
      socket.off('message');
      socket.off('error');
      socket.off('close');
      socket.close().catch(() => {});
    }
  }

  connectionIdentity(): number {
    return this.generation;
  }

  webSession(): DshWebSession {
    if (!this.http || !this.clientId) throw new Error('DSH 主机未连接');
    return { baseUrl: this.base, cookie: String(this.headers.cookie || ''),
      authorization: String(this.headers.authorization || ''), generation: this.generation };
  }

  localAccountCallbackOrigin(): string {
    return this.local ? this.base : '';
  }

  async exportSessionLog(sessionId: string, localPath: string,
    setCancel?: (cancel: DshSubscription) => void): Promise<void> {
    const http = this.http;
    const generation = this.generation;
    if (!http || !this.clientId) {
      throw new Error('DSH 主机未连接');
    }
    if (!sessionId || sessionId.length > 256 || /[\x00-\x1f\x7f]/.test(sessionId)) {
      throw new Error('会话编号格式无效');
    }
    let encodedId: string;
    try {
      encodedId = encodeURIComponent(sessionId);
    } catch {
      throw new Error('会话编号格式无效');
    }
    if (await fs.access(localPath)) {
      throw new Error('导出文件已存在');
    }
    if (this.generation !== generation) {
      throw new Error('主机连接已变更');
    }
    const headers: rcp.RequestHeaders = { cookie: this.headers.cookie, authorization: this.headers.authorization };
    const request = new rcp.Request(`${this.base}/api/session.export?sessionId=${encodedId}&includeDescendants=true`,
      'GET', headers);
    request.configuration = { proxy: this.proxy,
      transfer: { autoRedirect: false, timeout: { connectMs: 10000, transferMs: 300000 } } };
    const destination: rcp.DownloadToFile = { kind: 'file', file: localPath };
    request.destination = destination;
    let cancelled = false;
    let finished = false;
    try {
      const download = http.fetch(request);
      setCancel?.(() => {
        if (!finished && !cancelled) {
          cancelled = true;
          http.cancel(request);
        }
      });
      let response: rcp.Response;
      try {
        response = await download;
      } catch {
        throw new Error(cancelled ? '已取消导出' : '无法从主机下载会话日志');
      }
      if (cancelled) {
        throw new Error('已取消导出');
      }
      if (this.generation !== generation) {
        throw new Error('主机连接已变更');
      }
      if (response.statusCode !== 200) {
        throw new Error(response.statusCode === 404 ? '主机上找不到会话或导出服务' :
          `主机未能导出会话日志（HTTP ${response.statusCode}）`);
      }
      const type = response.headers['content-type'];
      if (typeof type !== 'string' || type.split(';', 1)[0].trim().toLowerCase() !== 'application/zip' ||
        !await this.hasZipHeader(localPath)) {
        throw new Error('主机没有返回有效的 ZIP 文件');
      }
      if (cancelled || this.generation !== generation) {
        throw new Error(cancelled ? '已取消导出' : '主机连接已变更');
      }
      finished = true;
    } finally {
      if (!finished) {
        finished = true;
        await fs.unlink(localPath).catch(() => {});
      }
    }
  }

  private async hasZipHeader(path: string): Promise<boolean> {
    try {
      const file = await fs.open(path, fs.OpenMode.READ_ONLY);
      try {
        const buffer = new ArrayBuffer(4);
        const count = await fs.read(file.fd, buffer);
        const bytes = new Uint8Array(buffer);
        return count === 4 && bytes[0] === 0x50 && bytes[1] === 0x4b && bytes[2] === 0x03 && bytes[3] === 0x04;
      } finally {
        await fs.close(file);
      }
    } catch {
      return false;
    }
  }

  async sessionDeletionAvailable(): Promise<boolean> {
    const response = await this.sessionDeletionRequest('GET');
    if ([404, 405, 501].includes(response.statusCode)) {
      return false;
    }
    if (response.statusCode !== 200) {
      throw new Error(`无法确认主机是否支持删除会话（HTTP ${response.statusCode}）`);
    }
    const body = this.sessionDeletionReply(response);
    return body['version'] === 1 && body['supported'] === true;
  }

  async deleteSessionPermanently(sessionId: string): Promise<void> {
    if (!sessionId || sessionId.length > 256 || /[\x00-\x1f\x7f]/.test(sessionId)) {
      throw new Error('会话编号格式无效');
    }
    const response = await this.sessionDeletionRequest('POST', JSON.stringify(sessionRequest(sessionId)));
    const reply = this.sessionDeletionReply(response);
    if (response.statusCode !== 200) {
      const code = string(object(reply['error'])['code']);
      if (/^[A-Za-z0-9_/-]{1,80}$/.test(code)) {
        throw new Error(`主机拒绝永久删除（${code}）`);
      }
      if ([404, 405, 501].includes(response.statusCode)) {
        throw new Error('这台主机不支持永久删除会话');
      }
      throw new Error(`主机未确认永久删除（HTTP ${response.statusCode}）`);
    }
    if (reply['deleted'] !== true || reply['sessionId'] !== sessionId) {
      throw new Error('主机未确认指定会话已删除，请刷新列表核实');
    }
  }

  private async sessionDeletionRequest(method: 'GET' | 'POST', body?: string): Promise<rcp.Response> {
    const http = this.http;
    if (!http || !this.clientId) {
      throw new Error('DSH 主机未连接');
    }
    const path = method === 'GET' ? '/dsh-go/v1/sessions/deletion' : '/dsh-go/v1/sessions/delete';
    const headers: rcp.RequestHeaders = { cookie: this.headers.cookie, authorization: this.headers.authorization };
    if (body) {
      headers['content-type'] = 'application/json';
    }
    let response: rcp.Response;
    try {
      const request = new rcp.Request(`${this.base}${path}`, method, headers, body);
      request.configuration = {
        proxy: this.proxy,
        transfer: { autoRedirect: false, timeout: { connectMs: 8000, transferMs: method === 'GET' ? 8000 : 30000 } }
      };
      response = await http.fetch(request);
    } catch {
      throw new Error(method === 'GET' ? '无法查询主机删除会话能力' : '主机未确认删除结果，请刷新列表核实');
    }
    if (this.http !== http) {
      throw new Error('主机连接已变更');
    }
    return response;
  }

  private sessionDeletionReply(response: rcp.Response): WireObject {
    const header = response.headers['content-type'];
    const contentType = typeof header === 'string' ? header : '';
    if (contentType.split(';', 1)[0].trim().toLowerCase() !== 'application/json' ||
      !response.body || response.body.byteLength > 8192) {
      return {};
    }
    try {
      return object(JSON.parse(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(response.body))));
    } catch {
      return {};
    }
  }

  async searchSessions(query: string, setCancel?: (cancel: DshSubscription) => void): Promise<DshSessionSearch> {
    const request: WireObject = {};
    request['query'] = query;
    const value = object(await this.rpc('session/search', requestArgs(request), undefined, setCancel));
    const items = array(value['items']).map((item: Object): DshSessionSearchHit => {
      const row = object(item);
      return { sessionId: string(row['sessionId']), snippet: string(row['snippet']) };
    }).filter((item: DshSessionSearchHit) => !!item.sessionId);
    return { items: items, hasMore: value['hasMore'] === true };
  }

  async listSessions(includeArchived: boolean = false, includeSubagents: boolean = false): Promise<DshSession[]> {
    const request: WireObject = {};
    const args: WireObject = {};
    args['_request'] = request;
    const result = object(await this.rpc('session/list', args));
    const sessions: DshSession[] = [];
    for (const value of array(result['items'])) {
      const row = object(value);
      const id = string(row['sessionId']);
      const archived = this.archived.includes(id);
      if (!id || (!includeArchived && archived) || (!includeSubagents && row['origin'] === 'subagent')) {
        continue;
      }
      const projections = object(object(row['projections'])['values']);
      const models = object(projections['modelSelection']);
      const timestamp = row['updatedAt'];
      const parsed = typeof timestamp === 'string' ? Date.parse(timestamp) : number(timestamp, 0);
      sessions.push({
        id: id,
        title: string(projections['title']) || string(row['title']) || '新对话',
        cwd: string(row['cwd']),
        origin: string(row['origin']), parentSessionId: string(row['parentSessionId']),
        updatedAt: Number.isFinite(parsed) ? parsed : 0,
        archived: archived, pinned: this.pinned.includes(id), model: modelSelection(models['next']) ?? modelSelection(models['lastUsed'])
      });
    }
    return sessions;
  }

  async watchWorkspaces(callback: (items: DshWorkspace[]) => void): Promise<void> {
    const previous = this.workspaceStream;
    this.workspaceStream = undefined;
    await this.stop(previous);
    await new Promise<void>((resolve: () => void, reject: (error: Error) => void) => {
      const id = util.generateRandomUUID();
      const timer = setTimeout(() => stream.fail('项目列表加载超时'), 12000);
      const stream: Subscription = {
        id: id,
        consume: (value: WireObject): void => {
          this.applyWorkspace(value);
          if (value['type'] === 'baseline') {
            clearTimeout(timer);
            resolve();
          }
          callback(this.workspaces.slice());
        },
        fail: (reason: string): void => {
          clearTimeout(timer);
          reject(new Error(reason));
          if (this.workspaceStream === stream) {
            this.workspaceStream = undefined;
            this.cancelStream(stream.id);
          }
        }
      };
      this.workspaceStream = stream;
      this.send(createMuxOpen(id, 'workspace/follow', {})).catch(() => stream.fail('无法订阅项目列表'));
    });
  }

  async watchSession(sessionId: string, callback: (update: DshChatUpdate) => void): Promise<void> {
    const previous = this.sessionStream;
    this.sessionStream = undefined;
    this.stopChatControl();
    const transcript = new DshTranscript(sessionId, this.local);
    this.transcript = transcript;
    this.chatCallback = callback;
    await this.stop(previous);
    if (this.transcript !== transcript) {
      throw new Error('对话已切换');
    }
    await new Promise<void>((resolve: () => void, reject: (error: Error) => void) => {
      const id = util.generateRandomUUID();
      let opened = false;
      const timer = setTimeout(() => stream.fail('对话加载超时'), 15000);
      const stream: Subscription = {
        id: id,
        consume: (value: WireObject): void => {
          if (!opened) {
            if (value['type'] !== 'snapshot') {
              stream.fail('主机没有返回对话快照');
              return;
            }
            opened = true;
            clearTimeout(timer);
            resolve();
          }
          transcript.apply(value);
          this.claimVisibleQuestionWaits();
          this.publishChat();
        },
        fail: (reason: string): void => {
          clearTimeout(timer);
          reject(new Error(reason));
          if (this.sessionStream === stream) {
            this.sessionStream = undefined;
            this.stopChatControl();
            this.cancelStream(stream.id);
            transcript.running = false;
            transcript.compacting = false;
            if (opened) {
              this.publishChat(reason);
            }
          }
        }
      };
      this.sessionStream = stream;
      const address: WireObject = {};
      address['kind'] = 'session';
      address['sessionId'] = sessionId;
      const request: WireObject = {};
      request['address'] = address;
      request['assistantStream'] = true;
      request['maxMessages'] = 100;
      const args: WireObject = {};
      args['request'] = request;
      this.send(createMuxOpen(id, 'session/follow', args)).catch(() => stream.fail('无法订阅对话'));
    });
    if (this.transcript === transcript && this.sessionStream) {
      this.watchChatControl(transcript).catch(() => {});
    }
  }

  unwatchSession(): void {
    const previous = this.sessionStream;
    this.sessionStream = undefined;
    this.transcript = undefined;
    this.chatCallback = undefined;
    this.stopChatControl();
    this.stop(previous).catch(() => {});
  }

  dismissSessionError(sessionId: string): void {
    const transcript = this.transcript;
    if (transcript?.sessionId === sessionId) {
      transcript.sessionError = undefined;
      this.publishChat();
    }
  }

  private async watchChatControl(transcript: DshTranscript): Promise<void> {
    const stop = await this.openStream('session/control', {}, (value: WireObject): void => {
      if (this.transcript === transcript && this.sessionStream && transcript.applyControl(value)) {
        this.publishChat();
      }
    }, () => {});
    if (this.transcript === transcript && this.sessionStream) {
      this.sessionControlStop = stop;
    } else {
      stop();
    }
  }

  private stopChatControl(): void {
    this.sessionControlStop?.();
    this.sessionControlStop = undefined;
    for (const id of this.questionWaits.keys()) {
      this.releaseQuestionWait(id);
    }
  }

  async setLocalModelKey(key: string): Promise<void> {
    if (!this.local) {
      throw new Error('需要本机引擎连接和 DeepSeek API Key');
    }
    const value = normalizeProviderKey(key);
    try {
      await this.saveProviderKey(value, 'DEEPSEEK_API_KEY');
    } catch {
      throw new Error('本机引擎未能设置 DeepSeek API Key');
    }
  }

  async setProviderKey(key: string, ref: string = 'DEEPSEEK_API_KEY'): Promise<void> {
    await this.saveProviderKey(normalizeProviderKey(key), ref);
  }

  private async saveProviderKey(key: string, ref: string): Promise<void> {
    this.checkCredentialRef(ref);
    const args: WireObject = {};
    args['ref'] = ref;
    args['value'] = key;
    await this.rpc('credentials/set', args);
  }

  async clearProviderKey(ref: string = 'DEEPSEEK_API_KEY'): Promise<void> {
    this.checkCredentialRef(ref);
    const args: WireObject = {};
    args['ref'] = ref;
    await this.rpc('credentials/unset', args);
  }

  async describeCredentials(refs: string[]): Promise<WireObject> {
    const args: WireObject = {};
    args['refs'] = refs;
    return object(await this.rpc('credentials/describe', args));
  }

  async createSession(workspaceId?: string, cwd?: string, agentPreset?: string): Promise<string> {
    const request: WireObject = {};
    if (workspaceId) {
      request['workspaceId'] = workspaceId;
    } else if (cwd) {
      request['cwd'] = cwd;
    }
    if (agentPreset) {
      request['agentPreset'] = agentPreset;
    }
    const args: WireObject = {};
    args['request'] = request;
    const value = object(await this.rpc('session/create', args));
    const sessionId = string(value['sessionId']);
    if (!sessionId) {
      throw new Error('主机没有返回新对话编号');
    }
    return sessionId;
  }

  async renameSession(sessionId: string, title: string): Promise<string> {
    const request = sessionRequest(sessionId);
    request['title'] = title;
    const result = object(await this.rpc('session/rename', requestArgs(request)));
    return string(result['title']) || title;
  }

  async archiveSession(sessionId: string, stopActivity?: boolean): Promise<string[]> {
    const request = sessionRequest(sessionId);
    if (stopActivity !== undefined) {
      request['stopActivity'] = stopActivity;
    }
    const value = object(await this.rpc('workspace/archiveSession', requestArgs(request)));
    this.archived = strings(value['archivedSessionIds']);
    return this.archived.slice();
  }

  async restoreSession(sessionId: string): Promise<string[]> {
    const result = object(await this.rpc('workspace/unarchiveSession', requestArgs(sessionRequest(sessionId))));
    this.archived = strings(result['archivedSessionIds']);
    return this.archived.slice();
  }

  async forkSession(sessionId: string, atSeq?: number): Promise<string> {
    const request = sessionRequest(sessionId);
    if (atSeq !== undefined) {
      request['atSeq'] = atSeq;
    }
    const result = object(await this.rpc('session/fork', requestArgs(request)));
    const id = string(result['sessionId']);
    if (!id) {
      throw new Error('主机没有返回分支会话标识');
    }
    return id;
  }

  async listModels(): Promise<DshModelCatalog> {
    return modelCatalog(await this.rpc('session/modelCatalog', {}));
  }

  async setModel(sessionId: string, provider: string, model: string, reasoningEffort?: string): Promise<DshModelSelectionResult> {
    const request = sessionRequest(sessionId);
    request['provider'] = provider;
    request['model'] = model;
    if (reasoningEffort !== undefined) {
      request['reasoningEffort'] = reasoningEffort;
    }
    const fallback: DshModelSelection = { provider: provider, model: model, reasoningEffort: reasoningEffort };
    return modelSelectionResult(await this.rpc('session/selectModel', requestArgs(request)), fallback);
  }

  async listProviders(): Promise<WireObject[]> {
    return array(await this.rpc('llm/listProviders', {})).map(object);
  }

  async describeSettings(): Promise<WireObject> {
    return object(await this.rpc('settings/describe', {}));
  }

  async updateSettings(ns: string, patch: WireObject, expectedRevision?: number): Promise<WireObject> {
    const args: WireObject = {};
    args['ns'] = ns;
    args['patch'] = patch;
    if (expectedRevision !== undefined) {
      args['expectedRevision'] = expectedRevision;
    }
    return object(await this.rpc('settings/update', args));
  }

  async mutateSettings(ns: string, ops: DshSettingsOp[], expectedRevision?: number): Promise<WireObject> {
    const args: WireObject = {};
    args['ns'] = ns;
    args['ops'] = ops.map((op: DshSettingsOp): WireObject => {
      const result: WireObject = {};
      result['op'] = op.op;
      result['path'] = op.path;
      if (op.op === 'set') {
        result['value'] = op.value;
      }
      return result;
    });
    if (expectedRevision !== undefined) {
      args['expectedRevision'] = expectedRevision;
    }
    return object(await this.rpc('settings/mutate', args));
  }

  async listDirectory(path?: string): Promise<WireObject> {
    const args: WireObject = {};
    if (path !== undefined) {
      args['path'] = path;
    }
    return object(await this.rpc('directoryPicker/list', args));
  }

  async createWorkspace(path: string): Promise<DshWorkspace> {
    const request: WireObject = {};
    request['path'] = path;
    const result = object(await this.rpc('workspace/create', requestArgs(request)));
    return this.workspace(result['workspace']);
  }

  async renameWorkspace(workspaceId: string, title: string): Promise<DshWorkspace> {
    const request: WireObject = {};
    request['workspaceId'] = workspaceId;
    request['title'] = title;
    const result = object(await this.rpc('workspace/rename', requestArgs(request)));
    return this.workspace(result['workspace']);
  }

  async deleteWorkspace(workspaceId: string): Promise<void> {
    const request: WireObject = {};
    request['workspaceId'] = workspaceId;
    await this.rpc('workspace/delete', requestArgs(request));
  }

  async pinSession(sessionId: string, pinned: boolean = true): Promise<string[]> {
    const endpoint = pinned ? 'workspace/pinSession' : 'workspace/unpinSession';
    const value = object(await this.rpc(endpoint, requestArgs(sessionRequest(sessionId))));
    this.pinned = strings(value['pinnedSessionIds']);
    return this.pinned.slice();
  }

  async listWorkspace(sessionId: string, path: string = ''): Promise<DshWorkspaceListing> {
    return workspaceListing(await this.rpc('workspaceFiles/list', workspaceFileArgs(sessionId, path)), path);
  }

  async fileReferences(sessionId: string, query: string): Promise<WireObject[]> {
    const args = agentArgs(sessionId);
    args['query'] = query;
    return array(await this.rpc('fileReferences/list', args)).map((value: Object): WireObject => object(value));
  }

  async sessionReferences(sessionId: string, query: string): Promise<WireObject[]> {
    const args = agentArgs(sessionId);
    args['query'] = query;
    return array(await this.rpc('sessionReferenceResolver/candidates', args)).map((value: Object): WireObject => object(value));
  }

  async readWorkspaceText(sessionId: string, path: string, offset: number = 1, limit: number = 500): Promise<DshWorkspaceText> {
    const args = workspaceFileArgs(sessionId, path);
    const range: WireObject = {};
    range['offset'] = offset;
    range['limit'] = Math.min(5000, Math.max(1, limit));
    args['range'] = range;
    return workspaceText(await this.rpc('workspaceFiles/read', args), offset);
  }

  async prompt(sessionId: string, text: string, requestId?: string): Promise<void> {
    await this.sendPrompt(sessionId, text, false, requestId ?? util.generateRandomUUID());
  }

  async speechCatalog(): Promise<SpeechCatalog | undefined> {
    try { return speechCatalog(await this.rpc('speech/catalog', {}, 4000)); }
    catch (error) {
      if (error instanceof DshRpcError && ['gateway/endpoint-not-found', 'gateway/definition-unavailable',
        'gateway/invocation-unavailable', 'gateway/service-unavailable', 'gateway/method-unavailable'].includes(error.code)) return undefined;
      throw error as Error;
    }
  }

  async configureSpeech(providerId?: string, language?: string): Promise<void> {
    const patch: WireObject = {};
    if (providerId !== undefined) patch['providerId'] = providerId;
    if (language !== undefined) patch['language'] = language;
    await this.rpc('speech/configure', { 'patch': patch });
  }

  async prepareSpeech(providerId: string, downloadSource?: string): Promise<void> {
    const args: WireObject = { 'providerId': providerId };
    if (downloadSource !== undefined) {
      const options: WireObject = { 'downloadSource': downloadSource };
      args['options'] = options;
    }
    await this.rpc('speech/prepare', args);
  }

  async cancelSpeechPreparation(providerId: string): Promise<void> {
    await this.rpc('speech/cancelPreparation', { 'providerId': providerId }, 20000);
  }

  async transcribeSpeech(wav: ArrayBuffer, providerId?: string, language?: string,
    setCancel?: (cancel: DshSubscription) => void): Promise<SpeechTranscript> {
    checkSpeechWav(wav);
    const request: WireObject = { 'audioBase64': new util.Base64Helper().encodeToString(new Uint8Array(wav)) };
    if (providerId !== undefined) request['providerId'] = providerId;
    if (language !== undefined) request['language'] = language;
    return speechTranscript(await this.rpc('speech/transcribe', { 'request': request }, 120000, setCancel));
  }

  async promptWithAttachments(sessionId: string, text: string, files: DraftAttachment[], requestId: string,
    current: () => boolean, allowFileFallback: boolean, steer: boolean = false): Promise<boolean> {
    const generation = this.generation;
    const check = (): void => {
      if (generation !== this.generation || !current()) throw new Error('主机或对话已切换，附件未发送。');
    };
    const content: WireObject[] = [];
    const imageIndexes: number[] = [];
    if (text) content.push({ 'type': 'text', 'text': text });
    let imageBytes = 0;
    try {
      for (const file of files) {
        check();
        if (file.mediaType) {
          imageBytes += file.size;
          if (imageBytes > 12 * 1024 * 1024) throw new Error('单次发送的图片数据不能超过 12 MiB。');
          imageIndexes.push(content.length);
          const data = await this.attachmentBase64(file, 4 * 1024 * 1024);
          content.push({ 'type': 'image', 'mediaType': file.mediaType, 'name': file.name, 'data': data });
        } else {
          if (!allowFileFallback) throw new Error('加密中继只支持图片附件。');
          content.push(await this.stageAttachment(sessionId, file, check));
        }
      }
      check();
    } catch (error) {
      // No prompt was submitted, so a removed queue item can safely be restored as a draft.
      throw new DshAttachmentPreparationError((error as Error).message);
    }
    try {
      await this.submitPromptContent(sessionId, content, steer, requestId);
      return false;
    } catch (error) {
      if (!(error instanceof DshRpcError) || error.code !== 'session/attachment-invalid' ||
        error.reason !== 'MODEL_DOES_NOT_SUPPORT_IMAGES' || !imageIndexes.length) throw error as Error;
      if (!allowFileFallback) throw new DshAttachmentPreparationError('当前模型不支持图片，请切换到支持图片的模型。');
      const images = files.filter((file: DraftAttachment) => !!file.mediaType);
      try {
        for (let i = 0; i < imageIndexes.length; i++) {
          check();
          content[imageIndexes[i]] = await this.stageAttachment(sessionId, images[i], check);
        }
        check();
      } catch (preparationError) {
        throw new DshAttachmentPreparationError((preparationError as Error).message);
      }
      await this.submitPromptContent(sessionId, content, steer, requestId);
      return true;
    }
  }

  private async attachmentBase64(file: DraftAttachment, limit: number): Promise<string> {
    if (file.size > limit) throw new Error('主机的内联附件限额低于这个文件的大小。');
    const bytes = new ArrayBuffer(file.size);
    if (file.size) {
      const source = await fs.open(file.path, fs.OpenMode.READ_ONLY);
      try {
        let offset = 0;
        while (offset < file.size) {
          const chunk = new ArrayBuffer(Math.min(1024 * 1024, file.size - offset));
          const count = await fs.read(source.fd, chunk);
          if (count <= 0) throw new Error('附件缓存未完整读取。');
          new Uint8Array(bytes).set(new Uint8Array(chunk, 0, count), offset);
          offset += count;
        }
      } finally { await fs.close(source); }
    }
    return new util.Base64Helper().encodeToString(new Uint8Array(bytes));
  }

  private async stageAttachment(sessionId: string, file: DraftAttachment, check: () => void): Promise<WireObject> {
    const http = this.http;
    if (!http || !this.clientId) throw new Error('DSH 主机未连接');
    let value: WireObject = {};
    if (!this.binaryUploadMissing) {
      const address = `${this.base}/api/session/uploadFileBinary?sessionId=${encodeURIComponent(sessionId)}&name=${encodeURIComponent(file.name)}`;
      const headers: rcp.RequestHeaders = { cookie: this.headers.cookie, authorization: this.headers.authorization,
        'content-type': 'application/octet-stream' };
      const body = file.size ? new rcp.UploadFromFile(file.path) : new ArrayBuffer(0);
      const request = new rcp.Request(address, 'POST', headers, body);
      request.configuration = { proxy: this.proxy,
        transfer: { autoRedirect: false, timeout: { connectMs: 10000, transferMs: 600000 } } };
      const response = await http.fetch(request);
      check();
      if (response.statusCode === 404) this.binaryUploadMissing = true;
      else {
        if (response.statusCode !== 200 || !response.body || response.body.byteLength > 65536) {
          throw new Error(`主机未能上传附件（HTTP ${response.statusCode}）。`);
        }
        const envelope = object(JSON.parse(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(response.body))));
        if (envelope['ok'] !== true) throw new Error(wireError(envelope['error']));
        value = object(envelope['value']);
      }
    }
    if (this.binaryUploadMissing) {
      const data = await this.attachmentBase64(file, 30 * 1024 * 1024);
      check();
      const request: WireObject = { 'data': data, 'name': file.name };
      const args = agentArgs(sessionId);
      args['request'] = request;
      value = object(await this.rpc('fileUploads/upload', args, 120000));
      check();
    }
    const receipt = string(value['receiptId']);
    if (!receipt || receipt.length > 256 || number(object(value['file'])['bytes'], -1) !== file.size) {
      throw new Error('主机返回了无效的附件收据。');
    }
    return { 'type': 'file', 'receiptId': receipt };
  }

  async readSessionImage(sessionId: string, reference: WireObject,
    setCancel?: (cancel: DshSubscription) => void, current: () => boolean = () => true): Promise<ArrayBuffer> {
    if (!current()) throw new Error('图片请求已取消');
    const id = string(reference['attachmentId']);
    if (!/^sha256:[a-f0-9]{64}$/.test(id) || number(reference['bytes'], 0) > 20 * 1024 * 1024) {
      throw new Error('图片超出预览范围。');
    }
    const generation = this.generation;
    const request = sessionRequest(sessionId);
    request['attachment'] = reference;
    let result: WireObject;
    try { result = object(await this.rpc('session/attachment', requestArgs(request), 120000, setCancel)); }
    catch (error) {
      if (!current() || generation !== this.generation || !(error instanceof DshRpcError) ||
        !['gateway/arguments-invalid', 'gateway/input-invalid'].includes(error.code)) throw error as Error;
      const legacy = sessionRequest(sessionId);
      legacy['attachmentId'] = id;
      result = object(await this.rpc('session/attachment', requestArgs(legacy), 120000, setCancel));
    }
    if (!current() || generation !== this.generation) throw new Error('图片请求已取消');
    const data = string(result['data']);
    if (!data || data.length > 4 * Math.ceil(20 * 1024 * 1024 / 3) || !/^[A-Za-z0-9+/]+={0,2}$/.test(data) ||
      string(object(result['attachment'])['attachmentId']) !== id) throw new Error('主机返回了无效的图片。');
    const decoded = await new util.Base64Helper().decode(data);
    if (!current() || generation !== this.generation) throw new Error('图片请求已取消');
    if (decoded.byteLength > 20 * 1024 * 1024) throw new Error('图片超出预览范围。');
    return new Uint8Array(decoded).buffer;
  }

  private async sendPrompt(sessionId: string, text: string, steer: boolean, requestId: string): Promise<void> {
    if (!text.trim()) {
      throw new Error('请输入消息');
    }
    const content: WireObject = {};
    content['type'] = 'text';
    content['text'] = text;
    await this.submitPromptContent(sessionId, [content], steer, requestId);
  }

  private async submitPromptContent(sessionId: string, content: WireObject[], steer: boolean, requestId: string): Promise<void> {
    const request: WireObject = {};
    request['requestId'] = requestId;
    request['sessionId'] = sessionId;
    request['mode'] = steer ? 'steer' : 'queue';
    request['content'] = content;
    const args: WireObject = {};
    args['request'] = request;
    await this.rpc('session/prompt', args);
  }

  async updateQueue(sessionId: string, itemId: string, kind: DshQueueAction, editText?: string): Promise<void> {
    const action: WireObject = {};
    action['kind'] = kind;
    if (kind === 'edit') {
      if (!editText?.trim()) {
        throw new Error('请输入消息');
      }
      const content: WireObject = {};
      content['type'] = 'text';
      content['text'] = editText;
      action['content'] = [content];
    }
    const request = sessionRequest(sessionId);
    request['itemId'] = itemId;
    request['action'] = action;
    const result = object(await this.rpc('session/updateQueue', requestArgs(request)));
    if (result['accepted'] !== true) {
      throw new Error('主机没有确认待发送消息的更改');
    }
  }

  async sendQueuedNow(sessionId: string, itemId: string,
    attachments: (requestId: string) => DraftAttachment[] = () => [], allowFileFallback: boolean = true): Promise<DshQueueMoveResult> {
    const transcript = this.transcript;
    if (!transcript || transcript.sessionId !== sessionId || !this.sessionStream || this.queueMove === transcript) {
      throw new Error('待发送消息当前无法移动');
    }
    const queue = transcript.queuedPrompts();
    const files = new Map<string, DraftAttachment[]>();
    for (const item of queue) {
      if (item.hasAttachments && item.requestId) files.set(item.id, attachments(item.requestId).slice());
    }
    const resendable = (item: DshQueuedPrompt): boolean => !item.automatic &&
      (item.resendable || (item.hasAttachments === true && (files.get(item.id)?.length || 0) > 0));
    const index = queue.findIndex((item: DshQueuedPrompt) => item.id === itemId);
    const selected = queue[index];
    if (!selected || !resendable(selected)) {
      throw new Error('无法重新发送这条消息');
    }
    const recoverable: DshQueuedPrompt[] = [];
    const result: DshQueueMoveResult = { sent: false, recoverable: recoverable };
    const generation = this.generation;
    const stream = this.sessionStream;
    const current = (): boolean => generation === this.generation && this.transcript === transcript && this.sessionStream === stream;
    this.queueMove = transcript;
    try {
      await this.updateQueue(sessionId, selected.id, 'remove');
      const moved = [selected];
      if (current() && transcript.running) {
        try {
          await this.cancel(sessionId);
        } catch {
          result.error = '停止当前回合失败，待发送消息将放回队列';
        }
      }
      for (const item of queue.slice(index + 1)) {
        if (!current()) {
          break;
        }
        if (item.target === 'next-turn' && resendable(item)) {
          try {
            await this.updateQueue(sessionId, item.id, 'remove');
            moved.push(item);
          } catch (error) {
            if (!(error instanceof DshRpcError) || error.code !== 'session/queue-item-not-found') {
              result.error = '部分待发送消息无法调整顺序';
            }
          }
        }
      }
      for (const item of moved) {
        if (generation !== this.generation) {
          result.error = '主机连接已变更，请核对原主机的待发送消息';
          break;
        }
        const requestId = item.requestId ?? item.id;
        try {
          const itemFiles = files.get(item.id) || [];
          if (itemFiles.length) {
            await this.promptWithAttachments(sessionId, item.text, itemFiles, requestId,
              () => generation === this.generation, allowFileFallback, item.target === 'next-step');
          } else {
            await this.sendPrompt(sessionId, item.text, item.target === 'next-step', requestId);
          }
          result.sent = result.sent || item.id === selected.id;
        } catch (error) {
          if (transcript.messages().some((message: DshMessage) => message.role === 'user' && message.requestId === requestId)) {
            result.sent = result.sent || item.id === selected.id;
          } else if (error instanceof DshRpcError || error instanceof DshAttachmentPreparationError) {
            recoverable.push(item);
            result.error = '有消息未能重新发送，请检查恢复的草稿';
          } else {
            result.error = '有消息未获主机确认，重新发送前请检查会话';
          }
        }
      }
      if (generation !== this.generation) {
        recoverable.length = 0;
      }
      return result;
    } finally {
      if (this.queueMove === transcript) {
        this.queueMove = undefined;
      }
    }
  }

  async cancel(sessionId: string): Promise<void> {
    const request: WireObject = {};
    request['sessionId'] = sessionId;
    const args: WireObject = {};
    args['request'] = request;
    await this.rpc('session/cancel', args);
  }

  async approve(eventId: string, allow: boolean): Promise<void> {
    const approval = this.approvals.get(eventId);
    if (!approval || approval.request.sessionId !== this.transcript?.sessionId || !this.sessionStream || !this.clientId) {
      throw new Error('这条审批已失效');
    }
    if (allow && !this.approvalView(approval).canAllow) {
      throw new Error('无法确认工具操作，请在主机上查看完整审批详情');
    }
    const outcome: WireObject = {};
    outcome['kind'] = 'result';
    outcome['value'] = allow ? 'allowed-once' : 'rejected';
    const args: WireObject = {};
    args['clientId'] = this.clientId;
    args['eventId'] = eventId;
    args['outcome'] = outcome;
    await this.rpc('$events/result', args);
    this.approvals.delete(eventId);
    this.publishChat();
  }

  async answerQuestion(question: DshQuestionRequest, answers: DshQuestionAnswer[]): Promise<void> {
    const current = this.visibleQuestion(question);
    const value: WireObject = {};
    value['answers'] = answers.map((answer: DshQuestionAnswer): WireObject => {
      const item: WireObject = {};
      item['id'] = answer.id;
      item['selected'] = answer.selected;
      if (answer.custom !== undefined) {
        item['custom'] = answer.custom;
      }
      return item;
    });
    if (current.continued) {
      const args = agentArgs(current.sessionId);
      args['callId'] = current.callId;
      args['answer'] = value;
      if (await this.rpc('userQuestions/answer', args) !== true) {
        throw new Error('这组问题已经结束');
      }
    } else {
      const outcome: WireObject = {};
      outcome['kind'] = 'result';
      outcome['value'] = value;
      await this.settleQuestion(current, outcome);
    }
  }

  async rejectQuestion(question: DshQuestionRequest): Promise<void> {
    const current = this.visibleQuestion(question);
    if (current.continued) {
      throw new Error('主机仅接受继续回答这组问题');
    }
    await this.rejectOpenQuestion(current, false);
  }

  private visibleQuestion(question: DshQuestionRequest): DshQuestionRequest {
    const transcript = this.transcript;
    if (!transcript || transcript.sessionId !== question.sessionId || !this.sessionStream || !this.clientId) {
      throw new Error('这组问题已失效');
    }
    const current = question.continued ? transcript.continuedQuestions().find((item: DshQuestionRequest) =>
      item.id === question.id) : this.questions.get(question.id);
    if (!current || current.sessionId !== question.sessionId) {
      throw new Error('这组问题已失效');
    }
    return current;
  }

  private async rejectOpenQuestion(question: DshQuestionRequest, timeout: boolean): Promise<void> {
    const outcome: WireObject = {};
    outcome['kind'] = 'rejected';
    const error: WireObject = {};
    error['name'] = 'UserQuestionError';
    error['code'] = timeout ? 'ASK_TIMED_OUT' : 'ASK_CANCELLED';
    error['message'] = timeout ? 'ask_user_question timed out before the user answered' :
      'The user declined to answer this question.';
    outcome['error'] = error;
    await this.settleQuestion(question, outcome);
  }

  private async settleQuestion(question: DshQuestionRequest, outcome: WireObject): Promise<void> {
    this.visibleQuestion(question);
    const args: WireObject = {};
    args['clientId'] = this.clientId;
    args['eventId'] = question.id;
    args['outcome'] = outcome;
    await this.rpc('$events/result', args);
    this.questions.delete(question.id);
    this.releaseQuestionWait(question.id);
    this.publishChat();
  }

  private releaseQuestionWait(id: string): void {
    const wait = this.questionWaits.get(id);
    if (wait) {
      this.questionWaits.delete(id);
      clearTimeout(wait.timer);
      wait.stop?.();
      const question = this.questions.get(id);
      if (question) {
        question.remainingMs = undefined;
      }
    }
  }

  private claimVisibleQuestionWaits(): void {
    const sessionId = this.transcript?.sessionId;
    for (const question of this.questions.values()) {
      if (question.sessionId === sessionId && question.timed && question.callId && !this.questionWaits.has(question.id)) {
        this.claimQuestionWait(question).catch(() => {});
      }
    }
  }

  private async claimQuestionWait(question: DshQuestionRequest): Promise<void> {
    const wait: QuestionWait = {};
    this.questionWaits.set(question.id, wait);
    const args = agentArgs(question.sessionId);
    args['callId'] = question.callId;
    try {
      const stop = await this.openStream('userQuestions/attachWait', args, (value: WireObject): void => {
        if (this.questionWaits.get(question.id) !== wait) {
          return;
        }
        const remaining = number(value['remainingMs'], -1);
        if (!Number.isSafeInteger(remaining) || remaining < 0 || remaining > 2147483647) {
          return;
        }
        question.remainingMs = remaining;
        clearTimeout(wait.timer);
        wait.timer = setTimeout(() => {
          this.rejectOpenQuestion(question, true).catch(() => {
            if (this.questionWaits.get(question.id) === wait) {
              this.releaseQuestionWait(question.id);
              this.publishChat('无法结束提问等待');
            }
          });
        }, remaining);
        this.publishChat();
      }, () => {
        if (this.questionWaits.get(question.id) === wait) {
          this.releaseQuestionWait(question.id);
          this.publishChat();
        }
      });
      if (this.questionWaits.get(question.id) === wait) {
        wait.stop = stop;
      } else {
        stop();
      }
    } catch {
      if (this.questionWaits.get(question.id) === wait) {
        this.releaseQuestionWait(question.id);
      }
    }
  }

  async listSkills(sessionId: string): Promise<WireObject[]> {
    const result = object(await this.rpc('skills/list', requestArgs(sessionRequest(sessionId))));
    return array(result['skills']).map(object).filter((item: WireObject) => !!string(item['name']));
  }

  async listAgentPresets(): Promise<WireObject[]> {
    const result = object(await this.rpc('agentPresets/list', {}));
    return array(result['presets']).map(object).filter((item: WireObject) => !!string(item['id']));
  }

  async readAgentPreset(id: string): Promise<WireObject> {
    const args: WireObject = {};
    args['agentPreset'] = id;
    return object(await this.rpc('agentPresets/read', args));
  }

  async selectAgentPreset(sessionId: string, preset: string): Promise<string> {
    const args: WireObject = {};
    args['agentId'] = sessionId;
    args['agentPreset'] = preset;
    return string(await this.rpc('agentPresets/select', args)) || preset;
  }

  async permissionPresets(): Promise<DshPermissionCatalog> {
    return permissionCatalog(await this.rpc('permissionPresets/catalog', {}));
  }

  async setPermissionPreset(sessionId: string, preset: string): Promise<void> {
    if (!/^[a-zA-Z0-9_-]+$/.test(preset)) {
      throw new Error('权限预设格式无效');
    }
    if (!(await this.runCommandRequest(sessionId, 'permission', `/permission ${preset}`)).success) {
      throw new Error('主机未能切换会话权限');
    }
  }

  async listCommands(sessionId: string): Promise<DshCommand[]> {
    return commandCatalog(await this.rpc('commands/list', agentArgs(sessionId)));
  }

  async executeCommand(sessionId: string, line: string): Promise<DshCommandResult> {
    const trimmed = line.trim();
    const name = /^\/([a-z][a-z0-9_-]*)(?=$|[\t\n\r ])/.exec(trimmed)?.[1];
    if (!name) {
      throw new Error('命令格式无效');
    }
    const transcript = this.transcript;
    const result = await this.runCommandRequest(sessionId, name, trimmed);
    if (this.transcript === transcript && transcript?.sessionId === sessionId) {
      transcript.applyCommandResult(`local-${util.generateRandomUUID()}`, name, result);
      this.publishChat();
    }
    return result;
  }

  private async runCommandRequest(sessionId: string, name: string, line: string): Promise<DshCommandResult> {
    const args = agentArgs(sessionId);
    args['line'] = line;
    const attachments: Object[] = [];
    args['submittedAttachments'] = attachments;
    // The request owns cancellation, so a normal transfer deadline can abort a healthy compaction.
    return commandResult(name, await this.rpc('commands/execute', args, name === 'compact' ? 1800000 : undefined));
  }

  async sessionProjections(sessionId: string): Promise<DshSessionProjections | null> {
    const result = await this.rpc('session/projections', requestArgs(sessionRequest(sessionId)));
    return result === null ? null : sessionProjections(result);
  }

  async sessionPage(sessionId: string, beforeSeq?: number, maxMessages: number = 100,
    throughSeq?: number): Promise<DshSessionPage> {
    const address = sessionRequest(sessionId);
    address['kind'] = 'session';
    const request: WireObject = {};
    request['address'] = address;
    request['maxMessages'] = maxMessages;
    if (beforeSeq !== undefined) {
      request['beforeSeq'] = beforeSeq;
    }
    if (throughSeq !== undefined) {
      request['throughSeq'] = throughSeq;
    }
    return sessionPage(await this.rpc('session/page', requestArgs(request)));
  }

  async sessionDetail(sessionId: string): Promise<DshSessionDetail> {
    const projections = await this.sessionProjections(sessionId);
    const history = await this.sessionPage(sessionId, undefined, 100,
      projections && projections.asOfSeq >= 0 ? projections.asOfSeq : undefined);
    const values = projections?.values ?? {};
    return { projections: projections, history: history, goal: goalView(values['goal']),
      goalSupported: values['goal'] !== undefined, todos: projections?.todos, turns: turnTraces(history.records),
      contextPressure: values['contextPressure'] ? object(values['contextPressure']) : undefined,
      contextBreakdown: values['contextBreakdown'] ? object(values['contextBreakdown']) : undefined,
      sessionStats: values['sessionStats'] ? object(values['sessionStats']) : undefined,
      tokenUsage: values['tokenUsage'] ? object(values['tokenUsage']) : undefined };
  }

  async readGoal(sessionId: string): Promise<DshGoal | null> {
    const value = await this.rpc('goals/get', agentArgs(sessionId));
    return value === null || value === undefined ? null : this.requireGoal(value);
  }

  async createGoal(sessionId: string, objective: string, maxGoalRounds?: number): Promise<DshGoalRef> {
    const args = agentArgs(sessionId);
    args['request'] = this.goalEdits(objective, maxGoalRounds);
    return this.requireGoalRef(object(await this.rpc('goals/create', args))['ref']);
  }

  async editGoal(sessionId: string, ref: DshGoalRef, objective?: string, maxGoalRounds?: number): Promise<DshGoal> {
    const args = this.goalArgs(sessionId, ref);
    args['request'] = this.goalEdits(objective, maxGoalRounds);
    return this.requireGoal(await this.rpc('goals/edit', args));
  }

  async pauseGoal(sessionId: string, ref: DshGoalRef): Promise<DshGoal> {
    return this.requireGoal(await this.rpc('goals/pause', this.goalArgs(sessionId, ref)));
  }

  async resumeGoal(sessionId: string, ref: DshGoalRef): Promise<DshGoal> {
    return this.requireGoal(await this.rpc('goals/resume', this.goalArgs(sessionId, ref)));
  }

  async completeGoal(sessionId: string, ref: DshGoalRef): Promise<DshGoal> {
    return this.requireGoal(await this.rpc('goals/complete', this.goalArgs(sessionId, ref)));
  }

  async clearGoal(sessionId: string, ref: DshGoalRef): Promise<DshGoalRef> {
    return this.requireGoalRef(await this.rpc('goals/clear', this.goalArgs(sessionId, ref)));
  }

  private goalArgs(sessionId: string, ref: DshGoalRef): WireObject {
    const args = agentArgs(sessionId);
    const revision: DshGoalRef = { id: ref.id, revision: ref.revision };
    args['ref'] = revision;
    return args;
  }

  private goalEdits(objective?: string, maxGoalRounds?: number): WireObject {
    const edits: WireObject = {};
    if (objective !== undefined) {
      if (!objective.trim()) {
        throw new Error('请输入目标');
      }
      edits['objective'] = objective.trim();
    }
    if (maxGoalRounds !== undefined) {
      edits['maxGoalRounds'] = maxGoalRounds;
    }
    if (objective === undefined && maxGoalRounds === undefined) {
      throw new Error('请输入目标或轮数');
    }
    return edits;
  }

  private requireGoal(value: Object | null | undefined): DshGoal {
    const goal = goalView(value);
    if (!goal) {
      throw new Error('主机没有返回有效目标');
    }
    return goal;
  }

  private requireGoalRef(value: Object | null | undefined): DshGoalRef {
    const ref = goalRef(value);
    if (!ref) {
      throw new Error('主机没有返回目标版本');
    }
    return ref;
  }

  async scheduleCatalog(): Promise<WireObject[]> {
    return array(await this.rpc('schedule/catalog', {})).map(object);
  }

  async scheduleHistory(id: string, sessionId?: string, limit: number = 20, before?: string): Promise<WireObject> {
    const request: WireObject = {};
    request['id'] = id;
    request['limit'] = limit;
    if (sessionId !== undefined) {
      request['sessionId'] = sessionId;
    }
    if (before !== undefined) {
      request['before'] = before;
    }
    return object(await this.rpc('schedule/history', requestArgs(request)));
  }

  async editSchedule(id: string, action: string, expectedUpdatedAt?: string, patch?: WireObject): Promise<WireObject> {
    const request: WireObject = {};
    request['id'] = id;
    request['action'] = action;
    if (expectedUpdatedAt !== undefined) {
      request['expectedUpdatedAt'] = expectedUpdatedAt;
    }
    if (patch !== undefined) {
      request['patch'] = patch;
    }
    return object(await this.rpc('schedule/edit', requestArgs(request)));
  }

  async runSchedule(id: string): Promise<WireObject> {
    const request: WireObject = {};
    request['id'] = id;
    return object(await this.rpc('schedule/run', requestArgs(request)));
  }

  async killJob(sessionId: string, jobId: string): Promise<boolean> {
    const request = sessionRequest(sessionId);
    request['jobId'] = jobId;
    const result = object(await this.rpc('job/kill', requestArgs(request)));
    return result['outcome'] === 'requested';
  }

  async watchJobs(sessionId: string, onItems: (items: WireObject[]) => void,
    onClose: (error?: string) => void): Promise<DshSubscription> {
    return this.openStream('job/list', requestArgs(sessionRequest(sessionId)), (value: WireObject) => {
      onItems(array(value['jobs']).map(object));
    }, onClose);
  }

  async followJob(sessionId: string, jobId: string, onFrame: (value: WireObject) => void,
    onClose: (error?: string) => void, from?: number): Promise<DshSubscription> {
    const request = sessionRequest(sessionId);
    request['jobId'] = jobId;
    if (from !== undefined) {
      request['from'] = from;
    }
    return this.openStream('job/follow', requestArgs(request), onFrame, onClose);
  }

  async pluginInventory(): Promise<WireObject> {
    return object(await this.rpc('pluginInventory/list', {}));
  }

  async listPluginBundles(): Promise<WireObject[]> {
    return array(await this.rpc('pluginManager/listBundles', {})).map(object);
  }

  async listPlugins(): Promise<WireObject[]> {
    return array(await this.rpc('pluginManager/listPlugins', {})).map(object);
  }

  async setBundleEnabled(name: string, enabled: boolean): Promise<WireObject> {
    const args: WireObject = {};
    args['name'] = name;
    args['enabled'] = enabled;
    return object(await this.rpc('pluginManager/setBundleEnabled', args));
  }

  async setPluginEnabled(id: string, enabled: boolean): Promise<WireObject> {
    const args: WireObject = {};
    args['id'] = id;
    args['enabled'] = enabled;
    return object(await this.rpc('pluginManager/setPluginEnabled', args));
  }

  async engineCapabilities(): Promise<DshEngineCapabilities> {
    const results = await Promise.all([this.describeSettings(), this.pluginInventory()]);
    const settings = results[0];
    const inventory = results[1];
    return {
      local: this.local, settingsWritable: settings['writable'] !== false,
      pluginManagement: inventory['managementAvailable'] === true,
      settingsNamespaces: array(settings['namespaces']).map((value: Object) => string(object(value)['ns']))
        .filter((id: string) => id.length > 0),
      presets: array(inventory['agentPresets']).map((value: Object) => string(object(value)['id']))
        .filter((id: string) => id.length > 0)
    };
  }

  async request(method: string, args: WireObject = {}, timeoutMs?: number): Promise<Object | null | undefined> {
    if (!/^\$?[A-Za-z][A-Za-z0-9-]*(?:\/[A-Za-z][A-Za-z0-9-]*)+$/.test(method)) {
      throw new Error('DSH 请求端点格式无效');
    }
    if (timeoutMs !== undefined && (!Number.isSafeInteger(timeoutMs) || timeoutMs <= 0 || timeoutMs > 1800000)) {
      throw new Error('DSH 请求超时时间无效');
    }
    return this.rpc(method, args, timeoutMs);
  }

  async bridgeJson(method: string, path: string, query: WireObject = {}, body?: WireObject,
    timeoutMs: number = 10000): Promise<Object | null> {
    const read = method === 'GET' && (/^\/dsh-go\/v1\/(contributions|inventory|plugin-config)$/.test(path) ||
      /^\/dsh-go\/v1\/(views|plugin-config)\/[A-Za-z0-9_.%~-]+(?:\/[A-Za-z0-9_.%~-]+)*$/.test(path));
    const write = method === 'POST' && (path === '/dsh-go/v1/invoke' ||
      /^\/dsh-go\/v1\/plugin-config\/[A-Za-z0-9_.%~-]+$/.test(path));
    if ((!read && !write) || path.includes('..') || /%2e|%25|%5c/i.test(path) ||
      !Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 60000) throw new Error('插件请求路径无效');
    const http = this.http;
    if (!http || !this.clientId) throw new Error('DSH 主机未连接');
    const params: string[] = [];
    for (const key of Object.keys(query)) {
      const value = query[key];
      if (typeof value !== 'string' || value.length > 65536 || !/^[A-Za-z][A-Za-z0-9]*$/.test(key)) {
        throw new Error('插件请求参数无效');
      }
      params.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
    }
    const serialized = body === undefined ? undefined : JSON.stringify(body);
    if (serialized && serialized.length > 262144) throw new Error('插件请求过大');
    const request = new rcp.Request(`${this.base}${path}${params.length ? '?' + params.join('&') : ''}`, method, {
      cookie: this.headers.cookie, authorization: this.headers.authorization, 'content-type': 'application/json'
    }, serialized);
    request.configuration = { proxy: this.proxy, transfer: { autoRedirect: false,
      timeout: { connectMs: 10000, transferMs: timeoutMs } } };
    const response = await http.fetch(request);
    if (this.http !== http) throw new Error('主机连接已变更');
    if (response.statusCode === 404 && read && ['/dsh-go/v1/contributions', '/dsh-go/v1/inventory',
      '/dsh-go/v1/plugin-config'].includes(path)) return null;
    const contentType = response.headers['content-type'];
    if (typeof contentType !== 'string' || !/^application\/json(?:\s*;|$)/i.test(contentType) ||
      !response.body || response.body.byteLength > 1048576) throw new Error(`插件接口响应无效（HTTP ${response.statusCode}）`);
    let value: Object;
    try { value = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(response.body))) as Object; }
    catch { throw new Error('插件接口返回了无效 JSON'); }
    if (response.statusCode !== 200) {
      const code = string(object(value)['code']) || string(object(object(value)['error'])['code']);
      throw new Error(`插件请求失败（${code || 'HTTP ' + response.statusCode}）`);
    }
    return value;
  }

  async webBootPage(): Promise<string> {
    const http = this.http, generation = this.generation;
    if (!http || !this.clientId) throw new Error('DSH 主机未连接');
    const request = new rcp.Request(this.base + '/', 'GET', { cookie: this.headers.cookie, authorization: this.headers.authorization });
    const chunks: Uint8Array[] = []; let size = 0, invalid = false;
    const fail = (): void => { invalid = true; try { http.cancel(request); } catch {} };
    const events: rcp.HttpEventsHandler = {
      onStatusCodeReceive: (status: number): void => { if (status !== 200) fail(); },
      onDataReceive: (data: ArrayBuffer): void => { size += data.byteLength; if (size > 4194304 || generation !== this.generation) fail(); if (!invalid) chunks.push(new Uint8Array(data).slice()); }
    };
    request.configuration = { proxy: this.proxy, transfer: { autoRedirect: false, timeout: { connectMs: 8000, transferMs: 10000 } }, tracing: { httpEventsHandler: events } };
    const response = await http.fetch(request);
    if (invalid || response.statusCode !== 200 || generation !== this.generation || this.http !== http) throw new Error('主机网页读取失败');
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes);
  }

  async pluginAsset(pkg: string, path: string, current: () => boolean = () => true): Promise<Uint8Array> {
    if (!/^(?:@[a-z0-9._~-]+\/)?[a-z0-9._~-]+$/.test(pkg) || path.length > 512 ||
      !/^([A-Za-z0-9_~-][A-Za-z0-9._~-]*(\/[A-Za-z0-9_~-][A-Za-z0-9._~-]*)*)\.(png|jpe?g|webp|gif)$/i.test(path)) throw new Error('插件图片来源无效');
    const http = this.http, generation = this.generation;
    if (!http || !this.clientId) throw new Error('DSH 主机未连接');
    const request = new rcp.Request(this.base + '/dsh-go/v1/assets/' + pkg.split('/').map(encodeURIComponent).join('/') + '/' + path.split('/').map(encodeURIComponent).join('/'),
      'GET', { cookie: this.headers.cookie, authorization: this.headers.authorization });
    let received = 0, invalid = false, accepted = false;
    const chunks: Uint8Array[] = [];
    const cancel = (): void => { invalid = true; try { http.cancel(request); } catch {} };
    const events: rcp.HttpEventsHandler = {
      onStatusCodeReceive: (status: number): void => { if (status !== 200) cancel(); },
      onHeaderReceive: (headers: rcp.ResponseHeaders): void => {
        const type = headers['content-type'], size = headers['content-length'];
        accepted = typeof type === 'string' && /^image\/(png|jpe?g|webp|gif)(?:\s*;|$)/i.test(type);
        if (typeof type !== 'string' || !/^image\/(png|jpe?g|webp|gif)(?:\s*;|$)/i.test(type) || (typeof size === 'string' && Number(size) > 4194304)) cancel();
      },
      onDataReceive: (data: ArrayBuffer): void => { received += data.byteLength; if (!accepted || received > 4194304 || !current() || generation !== this.generation) cancel(); if (!invalid) chunks.push(new Uint8Array(data).slice()); }
    };
    request.configuration = { proxy: this.proxy, transfer: { autoRedirect: false, timeout: { connectMs: 8000, transferMs: 15000 } }, tracing: { httpEventsHandler: events } };
    try {
      const response = await http.fetch(request);
      if (invalid || !accepted || !received || !current() || generation !== this.generation || this.http !== http || response.statusCode !== 200) throw new Error('插件图片不可用');
      const bytes = new Uint8Array(received); let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
      return bytes;
    } catch { throw new Error('插件图片不可用'); }
  }

  // A separately subscribed client for the companion room. It shares only the
  // current authenticated origin; closing either child never closes its parent.
  async forkConnection(onDisconnected?: (reason: string) => void): Promise<DshClient> {
    if (!this.http || !this.clientId) throw new Error('DSH 主机未连接');
    const generation = this.generation;
    const child = new DshClient(onDisconnected);
    child.base = this.base; child.local = this.local; child.proxy = this.proxy;
    child.headers = {};
    if (this.headers.cookie) child.headers.cookie = this.headers.cookie;
    if (this.headers.authorization) child.headers.authorization = this.headers.authorization;
    child.http = rcp.createSession({ requestConfiguration: { proxy: this.proxy,
      transfer: { autoRedirect: false, timeout: { connectMs: 10000, transferMs: 20000 } } } });
    child.connectionOwner = this; this.ownedConnections.add(child);
    try {
      await child.openSocket();
      if (generation !== this.generation || !this.clientId) throw new Error('主机连接已变更');
      return child;
    } catch (error) { child.close(); throw error as Error; }
  }

  ownsCompanionRunReceipt(receipt:CompanionRunReceipt):boolean { return this.signalReceipts.has(receipt); }

  async companionSignalCapabilities(): Promise<CompanionSignalCapability | undefined> {
    const http=this.http,generation=this.generation;if(!http||!this.clientId)throw new Error('DSH 主机未连接');
    const request=new rcp.Request(this.base+'/dsh-go/v1/companion/signals','GET',{cookie:this.headers.cookie,authorization:this.headers.authorization});
    let status=0,oversized=false;const bytes:number[]=[];
    const events:rcp.HttpEventsHandler={onStatusCodeReceive:(value:number):void=>{status=value},onDataReceive:(data:ArrayBuffer):void=>{if(bytes.length+data.byteLength>4096){oversized=true;http.cancel(request);return}for(const byte of new Uint8Array(data))bytes.push(byte)}};
    request.configuration={proxy:this.proxy,transfer:{autoRedirect:false,timeout:{connectMs:8000,transferMs:8000}},tracing:{httpEventsHandler:events}};
    try{const response=await http.fetch(request);if(!status)status=response.statusCode}catch(error){if(oversized)throw new Error('伙伴信号能力超过大小限制');throw new Error(error instanceof Error?error.message:'伙伴信号能力请求失败')}
    if(this.http!==http||this.generation!==generation||!this.clientId)throw new Error('主机连接已变更');if(oversized)throw new Error('伙伴信号能力超过大小限制');
    const text=signalDecode(bytes);let value:WireObject={};try{value=object(JSON.parse(text))}catch{if(status===404&&['Not Found','Not found','Not Found\n','Not found\n'].includes(text))return undefined;throw new Error('伙伴信号能力无效')}
    if(status===404&&object(value['error'])['code']==='companion/not-found')return undefined;if(status!==200)throw new Error('伙伴信号能力请求失败（HTTP '+status+'）');
    const capability=signalCapability(value);this.signalCapabilities.set(capability,generation);return capability;
  }

  companionSignalEvents(capability:CompanionSignalCapability,hostKey:string,isAllowed:()=>boolean,monotonic:()=>number,
    onEvent:(receipt:CompanionRunReceipt)=>void,onClose:(reason:string)=>void,onReady:()=>void=()=>{}):DshSubscription {
    const http=this.http,generation=this.generation;
    if(!http||!this.clientId||this.signalCapabilities.get(capability)!==generation||!capability.available||!signalId(hostKey))throw new Error('伙伴信号需要当前主机的有效能力');
    const parser=new CompanionSignalSse(capability.generation);let active=true,accepted=false,status=0,timer=-1,connectionTimer=-1;
    const request=new rcp.Request(this.base+'/dsh-go/v1/companion/signals/stream','GET',{cookie:this.headers.cookie,authorization:this.headers.authorization,accept:'text/event-stream'});
    const local=():boolean=>active&&this.http===http&&this.generation===generation&&!!this.clientId&&this.signalCapabilities.get(capability)===generation;
    const stop=():void=>{if(!active)return;active=false;clearTimeout(timer);clearInterval(connectionTimer);this.signalSubscriptions.delete(stop);try{http.cancel(request)}catch{}};
    const fail=(reason:string):void=>{if(!active)return;stop();onClose(reason)};
    const current=():boolean=>{if(!local()){stop();return false}let allowed=false;try{allowed=isAllowed()}catch{}if(!allowed||!local()){stop();return false}return true};
    const touch=():void=>{clearTimeout(timer);timer=setTimeout(()=>fail('伙伴信号连接超时'),45000)};
    const events:rcp.HttpEventsHandler={
      onStatusCodeReceive:(value:number):void=>{status=value;if(value!==200)fail('伙伴信号连接失败（HTTP '+value+'）')},
      onHeaderReceive:(headers:rcp.ResponseHeaders):void=>{const type=headers['content-type'];accepted=typeof type==='string'&&/^text\/event-stream(?:\s*;|$)/i.test(type);if(!accepted)fail('伙伴信号返回无效类型')},
      onDataReceive:(bytes:ArrayBuffer):void=>{if(!current())return;touch();if(!accepted||status!==200){fail('伙伴信号缺少有效响应头');return}try{parser.push(new Uint8Array(bytes),(frame:CompanionSignalFrame):void=>{if(!current())return;if(frame.event==='companion/ready'){onReady();current();return}if(frame.event==='companion/unavailable'){fail(string(frame.value['reason']));return}const signal=signalRun(frame.value,capability.generation,hostKey,new Date().toISOString());if(signal.id!==frame.id)throw new Error('伙伴信号标识不匹配');const receipt:CompanionRunReceipt={client:this,connection:generation,capability:capability,signal:signal,received:monotonic(),current:():boolean=>current()&&parser.ready,locallyCurrent:():boolean=>local()&&parser.ready};this.signalReceipts.add(receipt);if(current())onEvent(receipt);current()})}catch{fail('伙伴信号协议无效')}}
    };
    request.configuration={proxy:this.proxy,transfer:{autoRedirect:false,timeout:{connectMs:8000,transferMs:2147483647}},tracing:{httpEventsHandler:events}};
    this.signalSubscriptions.add(stop);if(!current())return stop;touch();connectionTimer=setInterval(()=>{current()},250);
    void http.fetch(request).then(()=>fail('伙伴信号连接已结束')).catch(()=>fail('伙伴信号连接失败'));return stop;
  }

  async companionJson(method: string, endpoint: string, body?: WireObject, sessionId?: string): Promise<Object | null> {
    const reads: string[] = ['', '/memories', '/prompt-context', '/signals', '/recall', '/export'];
    const writes: string[] = ['/events', '/memories', '/memories/delete', '/memories/clear', '/prompt-context', '/signals', '/recall/bind', '/recall/revoke'];
    if (!(method === 'GET' && (reads.includes(endpoint) || /^\/recall\/bindings\/[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(endpoint)) || method === 'POST' && writes.includes(endpoint))) throw new Error('伙伴请求路径无效');
    const http = this.http; if (!http || !this.clientId) throw new Error('DSH 主机未连接');
    const encoded = body === undefined ? undefined : JSON.stringify(body);
    if (encoded && encoded.length > 262144) throw new Error('伙伴请求过大');
    if (sessionId !== undefined && (endpoint !== '/prompt-context' || method !== 'GET' || !sessionId || sessionId.length > 128 || /[\x00-\x1f\x7f]/.test(sessionId))) throw new Error('伙伴会话参数无效');
    const request = new rcp.Request(this.base + '/dsh-go/v1/companion' + endpoint + (sessionId ? '?sessionId=' + encodeURIComponent(sessionId) : ''), method,
      { cookie: this.headers.cookie, authorization: this.headers.authorization, 'content-type': 'application/json' }, encoded);
    request.configuration = { proxy: this.proxy, transfer: { autoRedirect: false, timeout: { connectMs: 8000, transferMs: 10000 } } };
    const response = await http.fetch(request); if (this.http !== http) throw new Error('主机连接已变更');
    if (!response.body || response.body.byteLength > 1048576) throw new Error('伙伴接口返回无效内容');
    let value: Object; try { value = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(response.body))) as Object; }
    catch { throw new Error('伙伴接口返回无效 JSON'); }
    if (response.statusCode !== 200) { const row = object(value); const code = string(row['code']) || string(object(row['error'])['code']); if (response.statusCode === 404 && method === 'GET' && (endpoint === '' || endpoint === '/prompt-context' || endpoint === '/recall') && (!code || code === 'not-found' || code === 'route/not-found' || code === 'companion/not-found')) return null; throw new Error('伙伴请求失败（' + (code || response.statusCode.toString()) + '）'); }
    return value;
  }

  async dsBotCall(endpoint: string, payload: WireObject = {}, timeoutMs: number = 20000): Promise<Object | null> {
    if (!DSBOT_ENDPOINTS.includes(endpoint) || !Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 60000) throw new Error('DS Bot 请求无效');
    const http = this.http;
    if (!http || !this.clientId) throw new DshRpcError('bot/offline', 'DSH 主机未连接');
    const body: WireObject = { 'endpoint': endpoint, 'payload': payload };
    const serialized = JSON.stringify(body);
    if (serialized.length > 262144) throw new Error('DS Bot 请求过大');
    const request = new rcp.Request(`${this.base}/api/bot`, 'POST', {
      cookie: this.headers.cookie, authorization: this.headers.authorization, 'content-type': 'application/json'
    }, serialized);
    request.configuration = { proxy: this.proxy, transfer: { autoRedirect: false, timeout: { connectMs: 10000, transferMs: timeoutMs } } };
    const response = await http.fetch(request);
    if (this.http !== http) throw new DshRpcError('bot/connection-changed', '主机连接已变更');
    if (response.statusCode !== 200) throw new DshRpcError('bot/http-' + response.statusCode, 'DS Bot 请求失败');
    const contentType = response.headers['content-type'];
    if (typeof contentType !== 'string' || !/^application\/json(?:\s*;|$)/i.test(contentType) || !response.body || response.body.byteLength > 2097152) throw new DshRpcError('bot/protocol', 'DS Bot 返回了无效响应');
    let answer: Object;
    try { answer = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(response.body))) as Object; }
    catch { throw new DshRpcError('bot/protocol', 'DS Bot 返回了无效响应'); }
    return dsBotAnswer(answer);
  }

  dsBotFeed(onEvent: (event: DsBotEvent) => void, onClose: (reason: string) => void): DshSubscription {
    const http = this.http;
    if (!http || !this.clientId) throw new DshRpcError('bot/offline', 'DSH 主机未连接');
    const parser = new DsBotSseParser(), decoder = util.TextDecoder.create('utf-8');
    let active = true, accepted = false, timer = -1;
    const request = new rcp.Request(`${this.base}/api/bot/feed`, 'GET', {
      cookie: this.headers.cookie, authorization: this.headers.authorization, accept: 'text/event-stream'
    });
    const stop = (): void => { active = false; clearTimeout(timer); try { http.cancel(request); } catch {} };
    const fail = (reason: string): void => { if (!active) return; stop(); if (this.http === http) onClose(reason); };
    const heartbeat = (): void => { clearTimeout(timer); timer = setTimeout(() => fail('DS Bot 实时连接超时'), 50000); };
    const events: rcp.HttpEventsHandler = {
      onStatusCodeReceive: (status: number): void => { if (status !== 200) fail('DS Bot 实时连接失败（HTTP ' + status + '）'); },
      onHeaderReceive: (headers: rcp.ResponseHeaders): void => { const type = headers['content-type']; accepted = typeof type === 'string' && /^text\/event-stream(?:\s*;|$)/i.test(type); if (!accepted) fail('DS Bot 实时连接返回无效类型'); },
      onDataReceive: (data: ArrayBuffer): void => {
        if (!active || this.http !== http) { stop(); return; }
        heartbeat(); if (!accepted) return;
        try { const text = decoder.decodeWithStream(new Uint8Array(data), { stream: true }); for (const event of parser.push(text)) onEvent(event); }
        catch { fail('DS Bot 实时事件无效'); }
      }
    };
    request.configuration = { proxy: this.proxy, transfer: { autoRedirect: false, timeout: { connectMs: 10000, transferMs: 600000 } }, tracing: { httpEventsHandler: events } };
    heartbeat(); void http.fetch(request).then(() => fail('DS Bot 实时连接已断开')).catch(() => fail('DS Bot 实时连接失败'));
    return stop;
  }

  async voiceScribeRequest(body: WireObject): Promise<WireObject> {
    const http = this.http;
    if (!http || !this.clientId) throw new Error('DSH 主机未连接');
    if (body['action'] !== 'get-settings' && body['action'] !== 'set-settings') {
      throw new Error('语音速记请求无效');
    }
    const serialized = JSON.stringify(body);
    if (serialized.length > 65536) throw new Error('语音速记设置过大');
    const request = new rcp.Request(`${this.base}/voice-input`, 'POST', {
      cookie: this.headers.cookie, authorization: this.headers.authorization, 'content-type': 'application/json'
    }, serialized);
    request.configuration = { proxy: this.proxy,
      transfer: { autoRedirect: false, timeout: { connectMs: 10000, transferMs: 20000 } } };
    const response = await http.fetch(request);
    if (this.http !== http) throw new Error('主机连接已变更');
    if (response.statusCode !== 200) throw new Error(`语音速记请求失败（HTTP ${response.statusCode}）`);
    const contentType = response.headers['content-type'];
    if (typeof contentType !== 'string' || !/^application\/json(?:\s*;|$)/i.test(contentType) ||
      !response.body || response.body.byteLength > 262144) throw new Error('语音速记返回了无效响应');
    let envelope: WireObject;
    try { envelope = object(JSON.parse(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(response.body)))); }
    catch { throw new Error('语音速记返回了无效响应'); }
    if (envelope['ok'] !== true) throw new Error(wireError(envelope['error']));
    const value = envelope['value'];
    if (body['action'] === 'set-settings' && value === undefined) return {};
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('语音速记返回了无效设置');
    return object(value);
  }

  pendingAttention(): WireObject[] {
    const rows: WireObject[] = [];
    for (const pending of this.approvals.values()) rows.push({ 'id': pending.request.id, 'sessionId': pending.request.sessionId, 'kind': 'approval' });
    for (const question of this.questions.values()) if (!question.continued) rows.push({ 'id': question.id, 'sessionId': question.sessionId, 'kind': 'question' });
    return rows;
  }

  onHostEvent(listener: (event: WireObject) => void): DshSubscription {
    this.hostListeners.add(listener);
    return () => { this.hostListeners.delete(listener); };
  }

  async openStream(endpoint: string, args: WireObject, onItem: (value: WireObject) => void,
    onClose: (error?: string) => void): Promise<DshSubscription> {
    const stream = await this.openDuplexStream(endpoint, args, onItem, onClose);
    return stream.cancel;
  }

  async openDuplexStream(endpoint: string, args: WireObject, onItem: (value: WireObject) => void,
    onClose: (error?: string) => void): Promise<DshDuplexStream> {
    if (!this.socket || !this.clientId) {
      throw new Error('DSH 主机未连接');
    }
    const id = util.generateRandomUUID();
    const stream: Subscription = { id: id, consume: onItem, fail: (reason: string): void => onClose(reason || undefined) };
    this.streams.set(id, stream);
    try {
      await this.send(createMuxOpen(id, endpoint, args));
    } catch {
      this.streams.delete(id);
      throw new Error('无法打开 DSH 订阅');
    }
    const cancel = (): void => {
      if (this.streams.delete(id)) {
        this.cancelStream(id).catch(() => {});
      }
    };
    const write = async (value: WireObject): Promise<void> => {
      if (this.streams.get(id) !== stream) throw new Error('DSH 订阅已关闭');
      const frame: WireObject = {};
      frame['type'] = 'item';
      frame['streamId'] = id;
      frame['value'] = value;
      await this.send(frame);
    };
    return { write: write, cancel: cancel };
  }

  private checkCredentialRef(ref: string): void {
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(ref)) {
      throw new Error('凭据名称格式无效');
    }
  }

  private async rpc(method: string, args: WireObject, timeoutMs?: number,
    setCancel?: (cancel: DshSubscription) => void): Promise<Object | null | undefined> {
    const http = this.http;
    if (!http || !this.clientId) {
      throw new Error('DSH 主机未连接');
    }
    const rpcId = util.generateRandomUUID();
    const body = JSON.stringify(createRpcRequest(rpcId, method, args));
    const headers: rcp.RequestHeaders = {
      cookie: this.headers.cookie, authorization: this.headers.authorization, 'content-type': 'application/json'
    };
    let response: rcp.Response;
    try {
      const request = new rcp.Request(`${this.base}/api/${method}`, 'POST', headers, body);
      if (timeoutMs !== undefined) {
        request.configuration = {
          proxy: this.proxy,
          transfer: { autoRedirect: false, timeout: { connectMs: Math.min(timeoutMs, 10000), transferMs: timeoutMs } }
        };
      }
      const pending = http.fetch(request);
      let active = true;
      setCancel?.(() => {
        if (active && this.http === http) {
          try { http.cancel(request); } catch { /* The request may already have completed. */ }
        }
      });
      try { response = await pending; } finally { active = false; }
    } catch {
      throw new Error('与 DSH 主机通信失败');
    }
    if (this.http !== http) {
      throw new Error('主机连接已变更');
    }
    if (response.statusCode !== 200) {
      if (response.statusCode === 401 || response.statusCode === 403) {
        throw new Error('主机拒绝请求，请检查令牌、代理认证和 DSH 的受信任主机配置');
      }
      if (response.statusCode === 404 && method.startsWith('speech/')) {
        throw new DshRpcError('gateway/endpoint-not-found', '这台主机未提供语音服务');
      }
      if (response.statusCode === 404 && (method.startsWith('goals/') || method.startsWith('permissionPresets/') ||
        method.startsWith('userQuestions/') || method.startsWith('commands/'))) {
        throw new Error('这台主机不支持此功能');
      }
      throw new Error(`主机请求失败（HTTP ${response.statusCode}）`);
    }
    const bodyBytes = response.body;
    const contentTypeHeader = response.headers['content-type'];
    const contentType = typeof contentTypeHeader === 'string' ? contentTypeHeader : '';
    if (bodyBytes && /^multipart\/form-data\s*;/i.test(contentType)) {
      return parseBinaryRpcResponse(bodyBytes, contentType, rpcId, method);
    }
    if (method === 'session/attachment' && bodyBytes && bodyBytes.byteLength > 28 * 1024 * 1024) {
      throw new Error('图片超出预览范围。');
    }
    const responseText = bodyBytes ? util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(bodyBytes)) : '';
    return parseRpcResponse(responseText, rpcId, method);
  }

  private async openSocket(): Promise<void> {
    const socket = webSocket.createWebSocket();
    this.socket = socket;
    await new Promise<void>((resolve: () => void, reject: (error: Error) => void) => {
      let ready = false;
      const timer = setTimeout(() => fail('等待 DSH 主机响应超时'), 15000);
      const fail = (reason: string): void => {
        clearTimeout(timer);
        if (this.socket !== socket) {
          reject(new Error('连接已关闭'));
        } else if (!ready) {
          reject(new Error(reason));
        } else {
          this.close();
          this.onDisconnected?.(reason);
        }
      };
      const id = util.generateRandomUUID();
      this.events = {
        id: id,
        consume: (value: WireObject): void => {
          if (ready) {
            this.applyHostEvent(value);
            return;
          }
          const clientId = string(value['clientId']);
          if (value['type'] !== 'ready' || !clientId) {
            fail('主机没有返回 DSH 就绪帧');
            return;
          }
          ready = true;
          this.clientId = clientId;
          clearTimeout(timer);
          resolve();
        },
        fail: fail
      };
      socket.on('open', () => {
        if (this.socket === socket) {
          this.send(createMuxOpen(id, '$events', {})).catch(() => fail('无法订阅 DSH 主机事件'));
        }
      });
      socket.on('message', (error, value) => {
        if (this.socket === socket && !error && typeof value === 'string') {
          this.receive(value);
        }
      });
      socket.on('close', () => fail('DSH 主机连接已断开'));
      socket.on('error', () => fail('WebSocket 连接失败，请检查代理的升级转发和受信任主机设置'));
      const options: webSocket.WebSocketRequestOptions = { header: this.headers, proxy: this.proxy };
      if (deviceInfo.sdkApiVersion >= 26) {
        options.supportOriginPort = true;
      }
      socket.connect(`${this.base.replace(/^http/, 'ws')}/api/remote.mux`, options)
        .catch(() => fail('无法连接 DSH 的 WebSocket'));
    });
  }

  private async send(frame: WireObject): Promise<void> {
    const socket = this.socket;
    if (socket) {
      try {
        if (await socket.send(JSON.stringify(frame))) {
          return;
        }
      } catch {
        // The connection may have closed between frames.
      }
    }
    throw new Error('无法发送 WebSocket 消息');
  }

  private async stop(stream?: Subscription): Promise<void> {
    if (stream) {
      stream.fail('订阅已切换');
      await this.cancelStream(stream.id);
    }
  }

  private async cancelStream(id: string): Promise<void> {
    const frame: WireObject = {};
    frame['type'] = 'cancel';
    frame['streamId'] = id;
    await this.send(frame).catch(() => {});
  }

  private receive(text: string): void {
    let frame: WireObject;
    try {
      frame = object(JSON.parse(text));
    } catch {
      this.events?.fail('DSH 返回了无效的 WebSocket 消息');
      return;
    }
    const id = string(frame['streamId']);
    const generic = this.streams.get(id);
    const stream = generic ?? [this.events, this.workspaceStream, this.sessionStream]
      .find((candidate: Subscription | undefined) => candidate?.id === id);
    if (!stream) {
      return;
    }
    if (frame['type'] === 'item') {
      stream.consume(object(frame['value']));
    } else if (frame['type'] === 'error' || frame['type'] === 'end') {
      if (generic) {
        this.streams.delete(id);
      }
      stream.fail(frame['type'] === 'error' ? wireError(frame['error']) : (generic ? '' : '主机关闭了订阅'));
    }
  }

  private applyWorkspace(value: WireObject): void {
    switch (value['type']) {
      case 'replace':
      case 'baseline': {
        const baseline = object(value['value']);
        this.workspaces = array(baseline['items']).map((item: Object) => this.workspace(item)).filter((item) => !!item.id);
        this.archived = strings(baseline['archivedSessionIds']);
        this.pinned = strings(baseline['pinnedSessionIds']);
        break;
      }
      case 'upsert': {
        const row = this.workspace(value['workspace']);
        const index = this.workspaces.findIndex((item: DshWorkspace) => item.id === row.id);
        if (index >= 0) {
          this.workspaces[index] = row;
        } else if (row.id) {
          this.workspaces.push(row);
        }
        break;
      }
      case 'remove':
        this.workspaces = this.workspaces.filter((item: DshWorkspace) => item.id !== value['workspaceId']);
        break;
      case 'order': {
        const ids = strings(value['workspaceIds']);
        this.workspaces.sort((a: DshWorkspace, b: DshWorkspace) => ids.indexOf(a.id) - ids.indexOf(b.id));
        break;
      }
      case 'archived':
        this.archived = strings(value['archivedSessionIds']);
        break;
      case 'pinned':
        this.pinned = strings(value['pinnedSessionIds']);
        break;
    }
  }

  private workspace(value: Object | null | undefined): DshWorkspace {
    const row = object(value);
    const path = string(row['path']);
    return {
      id: string(row['workspaceId']), title: string(row['title']) || path, path: path,
      sessionIds: strings(row['sessionIds'])
    };
  }

  private applyHostEvent(value: WireObject): void {
    this.hostListeners.forEach((listener: (event: WireObject) => void) => listener(value));
    const approval = approvalFromEvent(value);
    if (approval) {
      const request = object(value['request']);
      const pending: PendingApproval = {
        request: approval,
        callId: string(request['callId']),
        toolName: string(request['toolName'])
      };
      this.approvals.set(approval.id, pending);
      if (this.transcript?.sessionId === approval.sessionId) {
        this.publishChat();
      }
      return;
    }
    const question = questionFromEvent(value);
    if (question) {
      this.questions.set(question.id, question);
      if (this.transcript?.sessionId === question.sessionId && this.sessionStream) {
        this.claimVisibleQuestionWaits();
        this.publishChat();
      }
      return;
    }
    if (value['type'] === 'cancel') {
      const id = string(value['eventId']);
      const pending = this.approvals.get(id);
      this.approvals.delete(id);
      const pendingQuestion = this.questions.get(id);
      this.questions.delete(id);
      this.releaseQuestionWait(id);
      if ((pending && pending.request.sessionId === this.transcript?.sessionId) ||
        (pendingQuestion && pendingQuestion.sessionId === this.transcript?.sessionId)) {
        this.publishChat();
      }
      return;
    }
    const args = array(value['args']);
    const transcript = this.transcript;
    if (value['type'] === 'emit' && value['event'] === 'goal/activation-changed' && transcript) {
      const payload = object(args[0]);
      if (payload['sessionId'] === transcript.sessionId) {
        transcript.applyGoalActivation(payload['goal']);
        this.publishChat();
      }
    }
    if (value['type'] === 'emit' && transcript && args[0] === transcript.sessionId) {
      if (value['event'] === 'api-session/status' && typeof args[1] === 'boolean') {
        transcript.applySessionStatus(args[1] === true);
        this.publishChat();
      } else if (value['event'] === 'api-session/error') {
        transcript.applySessionError(string(args[1]));
        this.publishChat();
      }
    }
  }

  private approvalView(pending: PendingApproval): DshApproval {
    const request = pending.request;
    return this.transcript?.reviewApproval(request, pending.callId, pending.toolName) ??
      { id: request.id, sessionId: request.sessionId, canAllow: false, title: '请在主机上查看完整审批详情。' };
  }

  private publishChat(error?: string): void {
    const transcript = this.transcript;
    if (!transcript || !this.chatCallback) {
      return;
    }
    const pending = this.sessionStream ? Array.from(this.approvals.values())
      .find((item: PendingApproval) => item.request.sessionId === transcript.sessionId) : undefined;
    const liveQuestions = this.sessionStream ? Array.from(this.questions.values())
      .filter((item: DshQuestionRequest) => item.sessionId === transcript.sessionId) : [];
    const questions = liveQuestions.concat(transcript.continuedQuestions().filter((item: DshQuestionRequest) =>
      !liveQuestions.some((live: DshQuestionRequest) => live.callId === item.callId)));
    const update: DshChatUpdate = {
      sessionId: transcript.sessionId, messages: transcript.messages(), records: transcript.sessionRecords(), running: transcript.running,
      approval: pending ? this.approvalView(pending) : undefined, error: error, sessionError: transcript.sessionError,
      tools: transcript.tools(), notices: transcript.turnNotices(), turnFailureCode: transcript.turnFailureCode,
      commands: transcript.commandNotices(), compacting: transcript.compacting,
      queue: transcript.queuedPrompts(),
      questions: questions, projections: transcript.projections(), todos: transcript.todos(), goal: transcript.goal(),
      goalSupported: transcript.goalSupported()
    };
    this.chatCallback(update);
  }
}
