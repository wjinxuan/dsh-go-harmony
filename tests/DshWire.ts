export type WireObject = Record<string, Object | null | undefined>;

export interface DshWorkspace {
  id: string;
  title: string;
  path: string;
  sessionIds: string[];
}

export interface DshSession {
  id: string;
  title: string;
  cwd: string;
  updatedAt: number;
  origin?: string;
  parentSessionId?: string;
  archived?: boolean;
  pinned?: boolean;
  model?: DshModelSelection;
}

export interface DshMessage {
  id: string;
  role: string;
  text: string;
  requestId?: string;
  reasoning?: string;
  usage?: DshTokenUsage;
  content?: WireObject[];
  seq?: number;
}

export interface DshAttachmentRef {
  kind: string;
  id: string;
  name: string;
  bytes: number;
  reference: WireObject;
  offloaded: boolean;
}

export function messageAttachments(content: WireObject[]): DshAttachmentRef[] {
  const items: DshAttachmentRef[] = [];
  for (const part of content) {
    const kind = string(part['type']);
    const reference = object(part['attachment']);
    const id = string(reference['attachmentId']);
    const bytes = number(reference['bytes'], 0);
    if ((kind !== 'image' && kind !== 'file') || !/^sha256:[a-f0-9]{64}$/.test(id) || bytes < 0) continue;
    const name = string(reference['name']).replace(/[\x00-\x1f\x7f/\\]/g, '').slice(0, 255);
    items.push({ kind: kind, id: id, name: name || (kind === 'image' ? '图片' : '附件'), bytes: bytes,
      reference: reference, offloaded: part['offloaded'] === true });
  }
  return items;
}

export interface DshTokenUsage {
  inputTokens: number;
  outputTokens: number;
  totalTokens?: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
  reasoningTokens?: number;
}

export interface DshTool {
  callId: string;
  name: string;
  arguments: string;
  result?: string;
  isError?: boolean;
  content?: WireObject[];
  meta?: Object | null;
  failure?: WireObject;
  seq: number;
}

export interface DshModelSelection {
  provider: string;
  model: string;
  reasoningEffort?: string;
}

export interface DshReasoningEffort {
  id: string;
  name: string;
  description?: string;
}

export interface DshModelInfo {
  provider: string;
  id: string;
  name: string;
  description?: string;
  efforts: DshReasoningEffort[];
  defaultEffort?: string;
}

export interface DshProviderGroup {
  id: string;
  name: string;
  models: DshModelInfo[];
}

export interface DshModelCatalogFailure {
  provider: string;
  name: string;
}

export interface DshModelCatalog {
  groups: DshProviderGroup[];
  defaultSelection?: DshModelSelection;
  routableProviders: string[];
  failures: DshModelCatalogFailure[];
}

export interface DshModelDefaultSave {
  status: string;
  code?: string;
}

export interface DshModelSelectionResult {
  selected: DshModelSelection;
  defaultSave?: DshModelDefaultSave;
}

export interface DshSettingsOp {
  op: string;
  path: string[];
  value?: Object | null;
}

export interface DshWorkspaceEntry {
  name: string;
  type: string;
  size?: number;
}

export interface DshWorkspaceListing {
  path: string;
  entries: DshWorkspaceEntry[];
  truncated: boolean;
}

export interface DshWorkspaceText {
  text: string;
  lines: number;
  eof: boolean;
  offset: number;
  absolutePath: string;
  version: string;
  bytes?: number;
}

export interface DshApproval {
  id: string;
  sessionId: string;
  title: string;
  canAllow?: boolean;
}

export type DshQueueTarget = 'next-turn' | 'next-step';
export type DshQueueAction = 'edit' | 'remove' | 'steer';

export interface DshQueuedPrompt {
  id: string;
  requestId?: string;
  text: string;
  target: DshQueueTarget;
  automatic: boolean;
  resendable: boolean;
  hasAttachments?: boolean;
}

export interface DshQueueMoveResult {
  sent: boolean;
  recoverable: DshQueuedPrompt[];
  error?: string;
}

export interface DshQuestionOption {
  label: string;
  description?: string;
}

export interface DshQuestion {
  id: string;
  question: string;
  detail?: string;
  header?: string;
  options: DshQuestionOption[];
  multiSelect: boolean;
  intent?: WireObject;
}

export interface DshQuestionRequest {
  id: string;
  sessionId: string;
  callId?: string;
  timed: boolean;
  continued: boolean;
  remainingMs?: number;
  questions: DshQuestion[];
}

export interface DshQuestionAnswer {
  id: string;
  selected: string[];
  custom?: string;
}

export interface DshPermissionOption {
  value: string;
  name: string;
  description?: string;
}

export interface DshPermissionCatalog {
  options: DshPermissionOption[];
  defaultOptions: DshPermissionOption[];
  defaultPreset: string;
}

export interface DshTodo {
  content: string;
  status: string;
  activeForm?: string;
}

export interface DshGoalRef {
  id: string;
  revision: number;
}

export interface DshGoal extends DshGoalRef {
  objective: string;
  phase: string;
  roundsStarted: number;
  maxGoalRounds?: number;
  activation?: string;
  blockedReason?: string;
}

export interface DshSessionProjections {
  asOfSeq: number;
  values: WireObject;
  kind?: string;
  agentPreset?: string;
  permissionPreset?: string;
  todos?: DshTodo[];
}

export interface DshSessionRecord {
  seq: number;
  type: string;
  time: number;
  data: WireObject;
}

export interface DshSessionPage {
  cursor: number;
  records: DshSessionRecord[];
  hasMore: boolean;
  beforeSeq?: number;
}

export interface DshSessionSearchHit {
  sessionId: string;
  snippet: string;
}

export interface DshSessionSearch {
  items: DshSessionSearchHit[];
  hasMore: boolean;
}

export type DshTraceKind = 'model' | 'tool' | 'approval' | 'question';

export interface DshTraceSpan {
  kind: DshTraceKind;
  step: number;
  seq: number;
  start: number;
  end?: number;
  provider?: string;
  model?: string;
  usage?: DshTokenUsage;
  firstToken?: number;
  lastToken?: number;
  retries?: number;
  callId?: string;
  toolName?: string;
  arguments?: string;
  outcome?: string;
  failed?: boolean;
  cutShort?: boolean;
}

export interface DshTurnTrace {
  turn: number;
  startSeq: number;
  endSeq?: number;
  start: number;
  end?: number;
  reason?: string;
  steps: number;
  spans: DshTraceSpan[];
}

export interface DshSessionDetail {
  projections: DshSessionProjections | null;
  goal?: DshGoal;
  goalSupported: boolean;
  todos?: DshTodo[];
  contextPressure?: WireObject;
  contextBreakdown?: WireObject;
  sessionStats?: WireObject;
  tokenUsage?: WireObject;
  turns: DshTurnTrace[];
  history: DshSessionPage;
}

export type DshTurnNoticeKind = 'error' | 'retry' | 'stopped' | 'max-tokens' | 'blocked' | 'interrupted';

export interface DshTurnNotice {
  seq: number;
  turn?: number;
  kind: DshTurnNoticeKind;
  text: string;
  code?: string;
  credentialTarget?: 'deepseek' | 'provider';
  subscription?: 'openai-codex' | 'anthropic';
  retrying?: boolean;
  actionable?: boolean;
  recovery?: 'retry' | 'continue';
  retryText?: string;
}

export interface DshCommand {
  name: string;
  definitionId?: string;
  label: string;
  description: string;
  hint?: string;
}

export interface DshCommandResult {
  id?: string;
  success: boolean;
  text?: string;
}

export interface DshCommandNotice {
  id: string;
  name: string;
  args?: string;
  seq?: number;
  done: boolean;
  success?: boolean;
  text?: string;
}

export interface DshChatUpdate {
  sessionId: string;
  messages: DshMessage[];
  records?: DshSessionRecord[];
  running: boolean;
  approval?: DshApproval;
  error?: string;
  sessionError?: string;
  tools?: DshTool[];
  notices: DshTurnNotice[];
  commands?: DshCommandNotice[];
  compacting?: boolean;
  turnFailureCode?: string;
  queue?: DshQueuedPrompt[];
  questions?: DshQuestionRequest[];
  projections?: DshSessionProjections;
  todos?: DshTodo[];
  goal?: DshGoal;
  goalSupported?: boolean;
}

export function object(value: Object | null | undefined): WireObject {
  if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
    return value as WireObject;
  }
  return {};
}

export function array(value: Object | null | undefined): Object[] {
  return Array.isArray(value) ? value as Object[] : [];
}

export function string(value: Object | null | undefined): string {
  return typeof value === 'string' ? value : '';
}

function commandText(value: Object | null | undefined, limit: number): string {
  return string(value).slice(0, limit).replace(/[\x00-\x09\x0B-\x1F\x7F-\x9F\u202A-\u202E\u2066-\u2069]/g, '').trim();
}

export function commandCatalog(value: Object | null | undefined): DshCommand[] {
  if (!Array.isArray(value)) {
    throw new Error('DSH 返回的命令列表无效');
  }
  const commands: DshCommand[] = [];
  for (const item of array(value)) {
    const row = object(item);
    const name = string(row['name']);
    if (!/^[a-z][a-z0-9_-]*$/.test(name) || commands.some((command: DshCommand) => command.name === name)) {
      continue;
    }
    const input = object(row['input']);
    const definitionId = string(row['definitionId']);
    const command: DshCommand = { name: name, definitionId: definitionId || undefined, label: name,
      description: commandText(row['description'], 240),
      hint: row['input'] && typeof row['input'] === 'object' && !Array.isArray(row['input']) ?
        commandText(input['hint'], 120) : undefined };
    if (name === 'compact' && (!definitionId || definitionId === '@deepseek-ai/dsh-command-compact')) {
      command.label = '压缩';
      command.description = '压缩以上对话内容，腾出上下文';
    } else if (name === 'permission' && (!definitionId || definitionId === '@deepseek-ai/dsh-permission-presets')) {
      command.label = '权限';
      command.description = '切换权限预设（沙箱模式与审批策略）';
      if (command.hint !== undefined) command.hint = '<预设名>';
    } else if (name === 'plan' && (!definitionId || definitionId === '@deepseek-ai/dsh-plan-mode')) {
      command.label = '计划';
      command.description = '进入或退出计划模式';
      if (command.hint !== undefined) command.hint = '[off | 要求]';
    } else if (name === 'goal' && (!definitionId || definitionId === '@deepseek-ai/dsh-command-goal')) {
      command.label = '目标';
      command.description = '设置或查看长期任务目标';
      if (command.hint !== undefined) command.hint = '[目标 | clear | pause | resume]';
    } else if (name === 'feedback' && (!definitionId || definitionId === '@deepseek-ai/dsh-command-feedback')) {
      command.label = '反馈';
      command.description = '发送关于当前对话的反馈';
      if (command.hint !== undefined) command.hint = '<内容>';
    }
    commands.push(command);
  }
  return commands;
}

function commandOutcome(name: string, success: boolean, value: Object | null | undefined): string | undefined {
  const text = commandText(value, 2000);
  if (name === 'compact') {
    if (text === 'No compactable history yet.') return '暂无可压缩的对话内容';
    const compacted = /^Compacted (\d+) history items \(~(\d+) tokens\)\.$/.exec(text);
    if (compacted) return `已压缩 ${compacted[1]} 条历史记录（约 ${compacted[2]} token）`;
    switch (text) {
      case 'Usage: /compact (no arguments)': return '/compact 无需参数';
      case 'Compaction is unavailable because this process has an active compaction, or the agent is not idle.':
        return '当前会话或主机正在处理任务，请稍后压缩';
      case 'Compaction cancelled.': return '已取消压缩';
      case 'The history selected for compaction changed before it could be replaced. The attempt is recorded in the session log.':
        return '压缩期间对话内容发生变化，请检查会话后再试';
      case 'Compaction could not produce a useful summary. The attempt is recorded in the session log.':
        return '未能生成可用的上下文摘要';
      case 'Compaction did not finish cleanly; some session history may have changed. Inspect the current session state before retrying.':
        return '压缩未能完成，对话内容可能已变化，请检查后再试';
      case 'Compaction finished, but the session could not be saved.': return '压缩完成，但主机未能保存会话';
    }
  }
  if (name === 'feedback') {
    if (text === 'Feedback text is required. Usage: /feedback <text>') return '请输入反馈内容';
    if (/^Feedback recorded for session [^\n]+\nAnonymous user: [^\n]+\.$/.test(text)) return '反馈已提交';
  }
  // A failed durable result can be a thrown host exception containing private data.
  return success ? text || undefined : '命令执行失败，请在主机上查看详情';
}

export function commandResult(name: string, value: Object | null | undefined): DshCommandResult {
  if (value === undefined || value === null) {
    return { success: false, text: '这台主机没有这条命令' };
  }
  const row = object(value);
  const id = string(row['commandId']);
  const result = object(row['result']);
  const kind = result['kind'];
  if (!id || (kind !== 'success' && kind !== 'error')) {
    throw new Error('DSH 返回的命令结果无效');
  }
  return { id: id, success: kind === 'success', text: commandOutcome(name, kind === 'success', result['text']) };
}

export function strings(value: Object | null | undefined): string[] {
  return array(value).map(string).filter((item: string) => item.length > 0);
}

export function number(value: Object | null | undefined, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function optionalNumber(value: Object | null | undefined): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}

function tokenUsage(value: Object | null | undefined): DshTokenUsage | undefined {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return undefined;
  }
  const row = object(value);
  return {
    inputTokens: number(row['inputTokens'], 0), outputTokens: number(row['outputTokens'], 0),
    totalTokens: optionalNumber(row['totalTokens']), cacheReadTokens: optionalNumber(row['cacheReadTokens']),
    cacheWriteTokens: optionalNumber(row['cacheWriteTokens']), reasoningTokens: optionalNumber(row['reasoningTokens'])
  };
}

export function modelSelection(value: Object | null | undefined): DshModelSelection | undefined {
  const row = object(value);
  const provider = string(row['provider']);
  const model = string(row['model']);
  return provider && model ? { provider: provider, model: model, reasoningEffort: string(row['reasoningEffort']) || undefined } : undefined;
}

export function modelCatalog(value: Object | null | undefined): DshModelCatalog {
  const row = object(value);
  const groups: DshProviderGroup[] = [];
  for (const item of array(row['groups'])) {
    const group = object(item);
    const id = string(group['id']);
    const models: DshModelInfo[] = [];
    for (const entry of array(group['models'])) {
      const model = object(entry);
      const modelId = string(model['id']);
      const reasoning = object(model['reasoning']);
      const efforts: DshReasoningEffort[] = [];
      for (const value of array(reasoning['efforts'])) {
        const effort = object(value);
        const effortId = string(effort['id']);
        efforts.push({ id: effortId, name: string(effort['name']) || effortId,
          description: string(effort['description']) || undefined });
      }
      models.push({ provider: id, id: modelId, name: string(model['name']) || modelId,
        description: string(model['description']) || undefined, efforts: efforts,
        defaultEffort: string(reasoning['defaultEffort']) || undefined });
    }
    groups.push({ id: id, name: string(group['name']) || id, models: models });
  }
  const failures: DshModelCatalogFailure[] = array(row['failures']).map((item: Object): DshModelCatalogFailure => {
    const failure = object(item);
    return { provider: string(failure['id']), name: string(failure['name']) };
  });
  return { groups: groups, defaultSelection: modelSelection(row['default']),
    routableProviders: strings(row['routableProviders']), failures: failures };
}

export function modelSelectionResult(value: Object | null | undefined, fallback: DshModelSelection): DshModelSelectionResult {
  const row = object(value);
  const save = object(row['defaultSave']);
  const status = string(save['status']);
  const result: DshModelSelectionResult = { selected: modelSelection(row['selected']) ?? fallback };
  if (status) {
    result.defaultSave = { status: status, code: string(save['code']) || undefined };
  }
  return result;
}

export function workspaceListing(value: Object | null | undefined, fallbackPath: string): DshWorkspaceListing {
  const row = object(value);
  const entries: DshWorkspaceEntry[] = [];
  for (const entry of array(row['entries'])) {
    const item = object(entry);
    const name = string(item['name']);
    const type = string(item['type']);
    if (name) {
      entries.push({ name: name, type: type === 'file' || type === 'directory' ? type : 'other',
        size: optionalNumber(item['size']) });
    }
  }
  return { path: typeof row['path'] === 'string' ? string(row['path']) : fallbackPath, entries: entries,
    truncated: row['truncated'] === true };
}

export function workspaceText(value: Object | null | undefined, fallbackOffset: number): DshWorkspaceText {
  const row = object(value);
  return { text: string(row['text']), lines: number(row['lines'], 0), eof: row['eof'] === true,
    offset: number(row['offset'], fallbackOffset), absolutePath: string(row['absolutePath']),
    version: string(row['version']), bytes: optionalNumber(row['bytes']) };
}

export function createRpcRequest(rpcId: string, method: string, args: WireObject): WireObject {
  const payload: WireObject = {};
  payload['args'] = args;
  const envelope: WireObject = {};
  envelope['type'] = 'client-request';
  envelope['rpcId'] = rpcId;
  envelope['method'] = method;
  envelope['payload'] = payload;
  return envelope;
}

export function wireError(value: Object | null | undefined): string {
  const error = object(value);
  const code = string(error['code']);
  return /^[a-z0-9-]{1,40}\/[a-z0-9-]{1,40}$/.test(code) ?
    `主机请求失败（${code}）` : 'DSH 主机请求失败';
}

const INVALID_API_KEY_MESSAGE = 'API Key 格式无效，请只粘贴原始密钥，去掉内部空格、换行或其他非 ASCII 字符。';

export function normalizeProviderKey(key: string): string {
  const value = key.trim();
  if (!value) {
    throw new Error('请输入 API Key');
  }
  // Match the pinned DSH normalizeApiKey rule for HTTP header values.
  if (!/^[\x21-\x7E]+$/.test(value)) {
    throw new Error(INVALID_API_KEY_MESSAGE);
  }
  return value;
}

export function localSessionError(message: string, turnFailureCode?: string): string {
  if (turnFailureCode === 'INVALID_CREDENTIAL' || /\bINVALID_CREDENTIAL\b/.test(message) ||
    message.includes('contains characters no HTTP header can carry')) {
    return INVALID_API_KEY_MESSAGE;
  }
  const lock = /Session file lock failed \(([0-9]{1,3})\)/.exec(message);
  if (lock) {
    return `无法锁定本机会话（${lock[1]}）`;
  }
  const io = /\b(EACCES|EPERM|EROFS|ENOSPC|ENOSYS|ENOTSUP|EOPNOTSUPP|EIO|EINVAL|ENOENT|EXDEV):[^\n,]*, (link|rename|fsync|fdatasync|open|fstat|stat|mkdir|write)\b/.exec(message);
  if (io) {
    return `本机会话写入失败（${io[1]}/${io[2]}）`;
  }
  if (/\bAUTH\b/.test(message)) {
    return 'DeepSeek 拒绝了 API Key';
  }
  return '本机会话运行失败';
}

function turnFailureText(code: string): string {
  switch (code) {
    case 'AUTH':
    case 'INVALID_CREDENTIAL': return 'API Key 无效或已过期';
    case 'QUOTA': return '余额不足';
    case 'ACCOUNT_QUOTA': return '账号额度已用完';
    case 'ACCOUNT_SIGN_IN_REQUIRED': return '请登录当前引擎的 DeepSeek 账号';
    case 'ACCOUNT_TOKEN_INVALID': return 'DeepSeek 账号登录已失效，请重新登录';
    case 'RATE_LIMIT': return '请求太频繁，稍后再试';
    case 'CONTEXT_WINDOW_EXCEEDED': return '对话太长，请压缩上下文后重试，或新建对话';
    case 'SERVER': return '模型服务暂时不可用';
    case 'TIMEOUT': return '模型响应超时';
    case 'TRANSPORT': return '没能连上模型服务';
    case 'EMPTY_RESPONSE': return '模型没有返回内容';
    case 'CLIENT_UPGRADE_REQUIRED': return '这个模型需要新版引擎';
    case 'MODEL_UNSUPPORTED': return '当前模型不可用';
    case 'UNSUPPORTED_REASONING_EFFORT': return '当前模型不支持此推理档位，请调整档位或换模型';
    default: return /^HTTP_5\d\d$/.test(code) ? '模型服务暂时不可用' : '';
  }
}

function failedTurnNotice(seq: number, turn: number | undefined, failure: WireObject, local: boolean): DshTurnNotice {
  const code = string(failure['code']);
  const text = turnFailureText(code);
  const notice: DshTurnNotice = { seq: seq, turn: turn, kind: 'error', text: text || '本轮出错了',
    code: text || code === 'MISSING_CREDENTIAL' ? code : undefined };
  if (code === 'AUTH' || code === 'MISSING_CREDENTIAL') {
    const detail = string(failure['message']);
    const route = /OAuth (?:refresh failed|refresh returned a token that expires too soon|auth derivation failed) for ([\w.-]+)|no credential for provider route "([\w.-]+)"/.exec(detail);
    const subscription = route?.[1] || route?.[2];
    if (subscription === 'openai-codex' || subscription === 'anthropic') {
      notice.subscription = subscription;
      notice.text = `${subscription === 'openai-codex' ? 'ChatGPT' : 'Claude'} 登录已失效`;
    } else if (code === 'MISSING_CREDENTIAL') {
      notice.credentialTarget = detail.startsWith('llm-pi-ai') ? 'provider' : 'deepseek';
      notice.text = notice.credentialTarget === 'provider' ? '这个模型渠道还没有密钥' : '还没有 DeepSeek API Key';
    }
  } else if (local && code === 'INVALID_CREDENTIAL') {
    notice.text = INVALID_API_KEY_MESSAGE;
  }
  return notice;
}

function terminalTurnNotice(seq: number, turn: number | undefined, reason: WireObject, local: boolean): DshTurnNotice | undefined {
  switch (reason['kind']) {
    case 'error': return failedTurnNotice(seq, turn, object(reason['error']), local);
    case 'aborted': return { seq: seq, turn: turn, kind: 'stopped', text: '已停止' };
    case 'max-tokens': return { seq: seq, turn: turn, kind: 'max-tokens', text: '已达单次输出上限' };
    case 'blocked': return { seq: seq, turn: turn, kind: 'blocked', text: '本轮已被拦截' };
    case 'interrupted': return { seq: seq, turn: turn, kind: 'interrupted', text: '引擎重启过，本轮已中断' };
    default: return undefined;
  }
}

function positiveInteger(value: Object | null | undefined): number | undefined {
  const count = number(value, 0);
  return Number.isSafeInteger(count) && count > 0 ? count : undefined;
}

function retryTurnNotice(seq: number, data: WireObject, retrying: boolean): DshTurnNotice {
  const retry = positiveInteger(data['retry']);
  const max = positiveInteger(data['maxRetries']);
  const label = retry === undefined ? '' : (max !== undefined && max >= retry ? `（${retry}/${max}）` : `（第 ${retry} 次）`);
  const prefix = retrying ? '请求失败，正在重试' : '请求重试';
  return { seq: seq, turn: positiveInteger(data['turn']), kind: 'retry', text: `${prefix}${label}`,
    retrying: retrying || undefined };
}

interface DshNoticeTurn {
  turn: number;
  prompt?: DshMessage;
  worked: boolean;
}

interface DshNoticeRecovery {
  kind: 'retry' | 'continue';
  text?: string;
}

function questionItems(value: Object | null | undefined): DshQuestion[] {
  return array(value).map((item: Object): DshQuestion => {
    const row = object(item);
    const options = array(row['options']).map((option: Object): DshQuestionOption => {
      const entry = object(option);
      return { label: string(entry['label']), description: string(entry['description']) || undefined };
    });
    return { id: string(row['id']), question: string(row['question']), detail: string(row['detail']) || undefined,
      header: string(row['header']) || undefined, options: options, multiSelect: row['multiSelect'] === true,
      intent: row['intent'] ? object(row['intent']) : undefined };
  }).filter((item: DshQuestion) => !!item.id && !!item.question);
}

export function questionFromEvent(frame: WireObject): DshQuestionRequest | undefined {
  if (frame['type'] !== 'waterfall' || frame['event'] !== 'user-questions/request') {
    return undefined;
  }
  const id = string(frame['eventId']);
  const sessionId = string(frame['agentId']);
  const request = object(frame['request']);
  const wait = object(request['wait']);
  const questions = questionItems(request['questions']);
  return id && sessionId && questions.length > 0 ? { id: id, sessionId: sessionId, questions: questions,
    callId: string(wait['callId']) || undefined, timed: wait['timed'] === true, continued: false } : undefined;
}

export function continuedQuestions(sessionId: string, value: Object | null | undefined): DshQuestionRequest[] {
  const result: DshQuestionRequest[] = [];
  for (const item of array(object(value)['active'])) {
    const row = object(item);
    const callId = string(row['callId']);
    const questions = questionItems(row['questions']);
    if (row['state'] === 'continued' && callId && questions.length > 0) {
      result.push({ id: callId, sessionId: sessionId, callId: callId, questions: questions, timed: true, continued: true });
    }
  }
  return result;
}

function permissionOptions(value: Object | null | undefined): DshPermissionOption[] {
  return array(value).map((item: Object): DshPermissionOption => {
    const row = object(item);
    const id = string(row['value']);
    return { value: id, name: string(row['name']) || id, description: string(row['description']) || undefined };
  }).filter((item: DshPermissionOption) => !!item.value);
}

export function permissionCatalog(value: Object | null | undefined): DshPermissionCatalog {
  const row = object(value);
  const options = permissionOptions(row['options']);
  return { options: options, defaultPreset: string(row['defaultPreset']),
    defaultOptions: Array.isArray(row['defaultOptions']) ? permissionOptions(row['defaultOptions']) :
      options.filter((item: DshPermissionOption) => item.value !== 'auto') };
}

function todoList(value: Object | null | undefined): DshTodo[] | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }
  return array(value).map((item: Object): DshTodo => {
    const row = object(item);
    return { content: string(row['content']), status: string(row['status']) || 'pending',
      activeForm: string(row['activeForm']) || undefined };
  });
}

export function sessionProjections(value: Object | null | undefined): DshSessionProjections {
  const row = object(value);
  const values = object(row['values']);
  return { asOfSeq: number(row['asOfSeq'], -1), values: values, kind: string(row['kind']) || undefined,
    agentPreset: string(values['agentPreset']) || undefined,
    permissionPreset: string(object(values['permissions'])['currentValue']) || undefined, todos: todoList(values['todos']) };
}

export function goalRef(value: Object | null | undefined): DshGoalRef | undefined {
  const row = object(value);
  const id = string(row['id']);
  const revision = number(row['revision'], -1);
  return id && revision > 0 && Number.isSafeInteger(revision) ? { id: id, revision: revision } : undefined;
}

export function goalView(value: Object | null | undefined): DshGoal | undefined {
  const wrapper = object(value);
  const row = wrapper['goal'] ? object(wrapper['goal']) : wrapper;
  const ref = goalRef(row);
  const phase = string(row['phase']);
  if (!ref || !['active', 'paused', 'blocked', 'complete'].includes(phase) || typeof row['objective'] !== 'string') {
    return undefined;
  }
  return { id: ref.id, revision: ref.revision, objective: string(row['objective']), phase: phase,
    roundsStarted: number(wrapper['roundsStarted'], 0), maxGoalRounds: optionalNumber(row['maxGoalRounds']),
    activation: string(wrapper['activation']) || undefined,
    blockedReason: string(object(row['blockedReason'])['message']) || undefined };
}

export function sessionPage(value: Object | null | undefined): DshSessionPage {
  const row = object(value);
  const records = array(row['records']).map((item: Object): DshSessionRecord => {
    const event = object(object(item)['event']);
    return { seq: number(event['seq'], -1), type: string(event['type']), time: number(event['time'], 0),
      data: object(event['data']) };
  }).filter((record: DshSessionRecord) => record.seq >= 0 && !!record.type);
  return { cursor: number(row['cursor'], -1), records: records, hasMore: row['hasMore'] === true,
    beforeSeq: records.length > 0 ? records[0].seq : undefined };
}

interface TokenBounds {
  first?: number;
  last?: number;
}

function tokenBounds(value: Object | null | undefined): TokenBounds {
  const bounds: TokenBounds = {};
  for (const item of array(value)) {
    const row = object(item);
    const type = string(row['type']);
    const chunkType = string(object(row['chunk'])['type']);
    const compact = ['text-chunks', 'reasoning-chunks', 'tool-call-chunks'].includes(type);
    if (!compact && !(type === 'chunk' && ['text-delta', 'reasoning-delta', 'tool-call-delta'].includes(chunkType))) {
      continue;
    }
    const start = optionalNumber(row[compact ? 'time0' : 'time']);
    if (start === undefined) {
      continue;
    }
    let end = start;
    for (const delta of array(row['dt'])) {
      end += number(delta, 0);
    }
    bounds.first = Math.min(bounds.first ?? start, start);
    bounds.last = Math.max(bounds.last ?? end, end);
  }
  return bounds;
}

class TurnTraceFold {
  readonly turn: DshTurnTrace;
  private boundary: number;
  private lastSeen: number;
  private lastStep: number = 0;
  private steps: Map<number, DshTraceSpan> = new Map();
  private tools: Map<string, DshTraceSpan> = new Map();
  private approvals: Map<string, DshTraceSpan> = new Map();

  constructor(start: DshSessionRecord) {
    this.turn = { turn: number(start.data['turn'], 0), startSeq: start.seq, start: start.time, steps: 0, spans: [] };
    this.boundary = start.time;
    this.lastSeen = start.time;
  }

  private model(step: number, time: number): DshTraceSpan {
    return { kind: 'model', step: step, seq: -1, start: time, retries: 0 };
  }

  apply(event: DshSessionRecord): void {
    const data = event.data;
    const step = number(data['step'], 0);
    this.lastSeen = Math.max(this.lastSeen, event.time);
    switch (event.type) {
      case 'step/start':
        this.lastStep = Math.max(this.lastStep, step);
        this.steps.set(step, this.model(step, event.time));
        break;
      case 'assistant/attempt':
      case 'llm/retry':
      case 'assistant/message':
        this.applyModel(event, step);
        break;
      case 'tool/call': {
        const callId = string(data['callId']);
        const name = string(data['name']);
        this.tools.set(callId, { kind: name === 'ask_user_question' ? 'question' : 'tool', step: step,
          seq: event.seq, start: event.time, callId: callId, toolName: name, arguments: string(data['arguments']) });
        break;
      }
      case 'approval/asked': {
        const callId = string(data['callId']);
        const tool = this.tools.get(callId);
        this.approvals.set(string(data['id']), { kind: 'approval', step: tool?.step ?? this.lastStep,
          seq: event.seq, start: event.time, callId: callId || undefined, toolName: string(data['toolName']),
          arguments: tool?.arguments });
        break;
      }
      case 'approval/decided': {
        const approval = this.approvals.get(string(data['id']));
        if (approval) {
          approval.outcome = string(data['outcome']) || undefined;
          this.closeSpan(approval, event.time);
          this.approvals.delete(string(data['id']));
          const tool = this.tools.get(approval.callId ?? '');
          if (tool) {
            tool.start = event.time;
            tool.outcome = approval.outcome;
          }
        }
        break;
      }
      case 'tool/result': {
        const message = object(data['message']);
        const callId = string(message['toolCallId']);
        const tool = this.tools.get(callId);
        if (tool) {
          for (const id of this.approvals.keys()) {
            const approval = this.approvals.get(id);
            if (approval?.callId === callId) {
              this.closeSpan(approval, event.time, true);
              this.approvals.delete(id);
            }
          }
          tool.failed = message['isError'] === true;
          this.closeSpan(tool, event.time);
          this.tools.delete(callId);
          this.boundary = event.time;
        }
        break;
      }
      case 'step/end':
      case 'user/message':
        this.boundary = Math.max(this.boundary, event.time);
        break;
    }
  }

  private applyModel(event: DshSessionRecord, step: number): void {
    const span = this.steps.get(step) ?? this.model(step, this.boundary);
    const bounds = tokenBounds(event.data['stream']);
    if (bounds.first !== undefined) {
      span.firstToken = Math.min(span.firstToken ?? bounds.first, bounds.first);
    }
    if (event.type === 'assistant/message') {
      const source = object(object(event.data['message'])['source']);
      span.seq = event.seq;
      span.lastToken = bounds.last;
      span.provider = string(source['provider']) || undefined;
      span.model = string(source['model']) || undefined;
      span.usage = tokenUsage(event.data['usage']);
      this.closeSpan(span, event.time);
      this.steps.delete(step);
      this.turn.steps++;
      this.lastStep = Math.max(this.lastStep, step);
      this.boundary = event.time;
      return;
    }
    if (event.type === 'llm/retry') {
      span.retries = (span.retries ?? 0) + 1;
    }
    this.steps.set(step, span);
  }

  private closeSpan(span: DshTraceSpan, time: number, cutShort: boolean = false): void {
    span.end = Math.max(span.start, time);
    span.cutShort = cutShort;
    this.turn.spans.push(span);
  }

  finish(end?: DshSessionRecord, interrupted: boolean = false): DshTurnTrace {
    const waiting = Array.from(this.approvals.values());
    const open = waiting.concat(Array.from(this.tools.values()).filter((tool: DshTraceSpan) =>
      !waiting.some((approval: DshTraceSpan) => approval.callId === tool.callId)), Array.from(this.steps.values()));
    if (end || interrupted) {
      this.turn.endSeq = end?.seq;
      this.turn.end = end?.time ?? this.lastSeen;
      this.turn.reason = end ? string(object(end.data['reason'])['kind']) || undefined : 'interrupted';
      for (const span of open) {
        this.closeSpan(span, this.turn.end, true);
      }
    } else {
      this.turn.spans = this.turn.spans.concat(open.length > 0 ? open : [this.model(this.lastStep + 1, this.boundary)]);
    }
    this.turn.spans.sort((a: DshTraceSpan, b: DshTraceSpan) => a.start - b.start || a.seq - b.seq);
    return this.turn;
  }
}

export function turnTraces(records: DshSessionRecord[]): DshTurnTrace[] {
  const turns: DshTurnTrace[] = [];
  let current: TurnTraceFold | undefined;
  for (const event of records) {
    if (event.type === 'turn/start') {
      if (current) {
        turns.push(current.finish(undefined, true));
      }
      current = new TurnTraceFold(event);
    } else if (current && event.type === 'turn/end') {
      turns.push(current.finish(event));
      current = undefined;
    } else if (current) {
      current.apply(event);
    }
  }
  if (current) {
    turns.push(current.finish());
  }
  return turns;
}

function queuedPrompt(value: Object, target: DshQueueTarget): DshQueuedPrompt {
  const row = object(value);
  const source = object(row['source']);
  const kind = string(source['kind']);
  const hidden = ['user-approval', 'plan-mode', 'working-directory', 'cordis-host-runner', 'subagent-settled',
    'agent-message', 'team-message', 'goal', 'schedule', 'user-question-reply', 'tool-goal', 'ptc-mode'].includes(kind);
  const parts = array(row['content']).map(object);
  const text = parts.filter((part: WireObject) => part['type'] === 'text').map((part: WireObject) => string(part['text'])).join('');
  return { id: hidden ? '' : string(row['id']), requestId: kind === 'user' ? string(source['rpcId']) || undefined : undefined, text: text,
    target: target, automatic: kind === 'tool-jobs',
    hasAttachments: kind === 'user' && parts.some((part: WireObject) => part['type'] === 'image' || part['type'] === 'file'),
    resendable: kind === 'user' && !!text.trim() && parts.every((part: WireObject) => part['type'] === 'text') };
}

export class DshRpcError extends Error {
  readonly code: string;
  readonly reason?: string;

  constructor(code: string, message: string, reason?: string) {
    super(message);
    this.code = code;
    this.reason = reason;
  }
}

export function parseRpcResponse(text: string, rpcId: string, method?: string): Object | null | undefined {
  let parsed: WireObject;
  try {
    parsed = object(JSON.parse(text));
  } catch {
    throw new Error('DSH 返回的请求结果无效');
  }
  const result = object(parsed['result']);
  if (parsed['type'] === 'server-response' && parsed['rpcId'] === rpcId) {
    if (result['ok'] === false) {
      const error = object(result['error']);
      const rawCode = string(error['code']);
      const code = /^[a-z0-9-]{1,40}\/[a-z0-9-]{1,40}$/.test(rawCode) ? rawCode : '';
      if (method === 'session/search' && code === 'gateway/internal' &&
        (object(error['details'])['code'] === 'SESSION_QUERY_SEARCH_DISABLED' ||
        string(error['message']).includes('session search is disabled: this deployment configures the session-query index'))) {
        throw new DshRpcError(code, '这台主机仅支持按标题搜索');
      }
      if (['gateway/definition-unavailable', 'gateway/invocation-unavailable', 'gateway/service-unavailable',
        'gateway/method-unavailable'].includes(code) &&
        (method?.startsWith('goals/') || method?.startsWith('permissionPresets/') || method?.startsWith('userQuestions/') ||
          method?.startsWith('commands/'))) {
        throw new DshRpcError(code, '这台主机不支持此功能');
      }
      const reason = object(error['details'])['reason'] === 'MODEL_DOES_NOT_SUPPORT_IMAGES' ?
        'MODEL_DOES_NOT_SUPPORT_IMAGES' : undefined;
      throw new DshRpcError(code, wireError(error), reason);
    }
    if (result['ok'] === true) {
      return result['value'];
    }
  }
  throw new Error('DSH 返回的请求结果无效');
}

export function createMuxOpen(streamId: string, endpoint: string, args: WireObject): WireObject {
  const payload: WireObject = {};
  payload['args'] = args;
  const frame: WireObject = {};
  frame['type'] = 'open';
  frame['streamId'] = streamId;
  frame['endpoint'] = endpoint;
  frame['payload'] = payload;
  return frame;
}

export function approvalFromEvent(value: WireObject): DshApproval | undefined {
  const id = string(value['eventId']);
  const sessionId = string(value['agentId']);
  if (value['type'] !== 'waterfall' || value['event'] !== 'approval/request' || !id || !sessionId) {
    return undefined;
  }
  const request = object(value['request']);
  const display = object(request['displayReason']);
  const title = string(display['zh']) || string(display['en']) || string(request['reason']) ||
    `是否允许运行 ${string(request['toolName']) || '工具'}？`;
  return { id: id, sessionId: sessionId, title: title };
}

const APPROVAL_UNSAFE_DISPLAY = /[\x00-\x08\x0b-\x1f\x7f\u061c\u200b-\u200f\u202a-\u202e\u2066-\u2069]/;
const MAX_APPROVAL_TEXT = 16384;

function completeApprovalInput(toolName: string, args: WireObject): boolean {
  const path = string(args['file_path']).trim();
  switch (toolName) {
    case 'write':
      return !!path && typeof args['content'] === 'string';
    case 'edit':
      return !!path && !!string(args['old_string']) && typeof args['new_string'] === 'string';
    case 'apply_patch':
      return !!string(args['input']).trim();
    default:
      return Object.keys(args).length > 0;
  }
}

export class DshTranscript {
  readonly sessionId: string;
  running: boolean = false;
  compacting: boolean = false;
  turnFailureCode?: string;
  sessionError?: string;
  private readonly local: boolean;
  private hostStatusRunning?: boolean;
  private terminalErrorSeen: boolean = false;
  private notices: DshTurnNotice[] = [];
  private commands: Map<string, DshCommandNotice> = new Map();
  private noticeTurn?: DshNoticeTurn;
  private latestEndNotice?: DshTurnNotice;
  private noticeRecovery?: DshNoticeRecovery;
  private retryingNotice?: DshTurnNotice;
  private retryingId: string = '';
  private lastTimelineSeq: number = -1;
  private committed: DshMessage[] = [];
  private records: DshSessionRecord[] = [];
  private cursor: number = -1;
  private attemptId: string = '';
  private draft: Map<number, string> = new Map();
  private draftReasoning: Map<number, string> = new Map();
  private draftUsage?: DshTokenUsage;
  private toolCalls: Map<string, DshTool> = new Map();
  private projectionValues: WireObject = {};
  private projectionSeq: Map<string, number> = new Map();
  private projectionCursor: number = -1;
  private nextTurn: Object[] = [];
  private nextStep: Object[] = [];
  private goalActivationRef?: DshGoalRef;
  private goalActivation?: string;

  constructor(sessionId: string, local: boolean = false) {
    this.sessionId = sessionId;
    this.local = local;
  }

  applySessionStatus(running: boolean): void {
    if (running && this.hostStatusRunning === false) {
      this.terminalErrorSeen = false;
      this.sessionError = undefined;
    }
    this.hostStatusRunning = running;
    this.running = running;
  }

  applySessionError(message: string): void {
    if (!this.terminalErrorSeen) {
      this.sessionError = this.local ? localSessionError(message) : 'DSH 主机报告错误，请在主机上查看详情';
    }
  }

  commandNotices(): DshCommandNotice[] {
    return Array.from(this.commands.values()).sort((a: DshCommandNotice, b: DshCommandNotice) =>
      (a.seq ?? Number.MAX_SAFE_INTEGER) - (b.seq ?? Number.MAX_SAFE_INTEGER));
  }

  applyCommandResult(localId: string, name: string, result: DshCommandResult): void {
    const id = result.id ?? localId;
    const previous = this.commands.get(id);
    if (!previous?.done) {
      this.commands.set(id, { id: id, name: previous?.name ?? name, args: previous?.args, seq: previous?.seq,
        done: true, success: result.success, text: result.text });
    }
  }

  turnNotices(): DshTurnNotice[] {
    const latest = this.latestEndNotice;
    const retrying = this.running ? this.retryingNotice : undefined;
    const actionable = latest && !this.running && this.hostStatusRunning !== true && this.lastTimelineSeq <= latest.seq;
    if (!actionable && !retrying) {
      return this.notices.slice();
    }
    const canRecover = this.nextTurn.length === 0 && this.nextStep.length === 0;
    return this.notices.map((notice: DshTurnNotice): DshTurnNotice => {
      if (retrying && notice.seq === retrying.seq) {
        return retrying;
      }
      if (actionable && notice === latest) {
        return { seq: notice.seq, turn: notice.turn, kind: notice.kind, text: notice.text, code: notice.code,
          credentialTarget: notice.credentialTarget, subscription: notice.subscription, actionable: true,
          recovery: canRecover ? this.noticeRecovery?.kind : undefined,
          retryText: canRecover ? this.noticeRecovery?.text : undefined };
      }
      return notice;
    });
  }

  private finishNoticeTurn(seq: number, data: WireObject): void {
    const turn = positiveInteger(data['turn']);
    const reason = object(data['reason']);
    const notice = terminalTurnNotice(seq, turn, reason, this.local);
    this.turnFailureCode = notice?.code;
    const active = this.noticeTurn;
    this.noticeTurn = undefined;
    this.latestEndNotice = notice;
    this.noticeRecovery = undefined;
    this.retryingNotice = undefined;
    this.retryingId = '';
    this.terminalErrorSeen = reason['kind'] === 'error';
    this.sessionError = undefined;
    if (!notice) {
      return;
    }
    this.notices.push(notice);
    const prompt = turn !== undefined && active?.turn === turn ? active.prompt : undefined;
    const code = string(object(reason['error'])['code']);
    if (prompt && (notice.kind === 'max-tokens' || notice.kind === 'interrupted' ||
      (notice.kind === 'error' && this.repeatableFailure(code, notice)))) {
      const textOnly = (prompt.content ?? []).every((part: WireObject): boolean => part['type'] === 'text');
      if (notice.kind === 'error' && !active?.worked && textOnly && prompt.text.trim()) {
        this.noticeRecovery = { kind: 'retry', text: prompt.text };
      } else {
        this.noticeRecovery = { kind: 'continue' };
      }
    }
  }

  private repeatableFailure(code: string, notice: DshTurnNotice): boolean {
    return !notice.subscription && !code.startsWith('ACCOUNT_') &&
      !['AUTH', 'INVALID_CREDENTIAL', 'MISSING_CREDENTIAL', 'QUOTA', 'CONTEXT_WINDOW_EXCEEDED',
        'CLIENT_UPGRADE_REQUIRED', 'MODEL_UNSUPPORTED', 'UNSUPPORTED_REASONING_EFFORT'].includes(code);
  }

  messages(): DshMessage[] {
    const messages = this.committed.slice();
    const text = this.draftText(this.draft);
    const reasoning = this.draftText(this.draftReasoning);
    if (text || reasoning) {
      messages.push({ id: `draft-${this.attemptId}`, role: 'assistant', text: text,
        reasoning: reasoning || undefined, usage: this.draftUsage });
    }
    return messages;
  }

  sessionRecords(): DshSessionRecord[] {
    return this.records.map((record: DshSessionRecord): DshSessionRecord => {
      let data: WireObject = {};
      if (record.type === 'user/message' || record.type === 'assistant/message') data = record.data;
      else if (record.type === 'turn/start') data = { 'turn': record.data['turn'] };
      else if (record.type === 'step/start') data = { 'step': record.data['step'], 'turn': record.data['turn'] };
      else if (record.type === 'todo/write') data = { 'todos': array(record.data['todos']).map((raw: Object): WireObject => {
        const todo = object(raw); return { 'content': todo['content'], 'status': todo['status'] };
      }) };
      else if (record.type === 'goal/change') {
        const goal = object(record.data['goal']);
        const view: WireObject = { 'objective': goal['objective'], 'phase': goal['phase'] };
        data = { 'operation': record.data['operation'], 'goal': view };
      }
      else if (record.type === 'tool/call') {
        data = { 'step': record.data['step'], 'turn': record.data['turn'], 'callId': record.data['callId'], 'name': record.data['name'],
          'arguments': record.data['arguments'] };
      } else if (record.type === 'tool/result') {
        const result = object(record.data['message']);
        const message: WireObject = { 'toolCallId': result['toolCallId'], 'isError': result['isError'] === true };
        const rawMeta = object(record.data['meta']);
        const meta: WireObject = {};
        for (const key of ['path', 'operation', 'diffs']) if (rawMeta[key] !== undefined) meta[key] = rawMeta[key];
        data = { 'step': record.data['step'], 'turn': record.data['turn'], 'message': message, 'meta': meta,
          'error': !!record.data['error'], 'failure': !!record.data['failure'] };
      } else if (record.type === 'deliverables/presented') {
        const files: WireObject[] = array(record.data['files']).map((raw: Object): WireObject => {
          const item = object(raw);
          return { 'path': item['path'], 'description': item['description'] };
        });
        data = { 'turn': record.data['turn'], 'callId': record.data['callId'], 'files': files };
      }
      else if (record.type === 'turn/end') {
        const reason = object(record.data['reason']);
        const safeReason: WireObject = { 'kind': reason['kind'] };
        data = { 'turn': record.data['turn'], 'reason': safeReason };
      }
      return { seq: record.seq, type: record.type, time: record.time, data: data };
    });
  }

  tools(): DshTool[] {
    return Array.from(this.toolCalls.values());
  }

  reviewApproval(request: DshApproval, callId: string, toolName: string): DshApproval {
    const call = this.toolCalls.get(callId);
    const title = request.title.length <= MAX_APPROVAL_TEXT && !APPROVAL_UNSAFE_DISPLAY.test(request.title) ?
      request.title : '需要确认工具操作';
    const unavailable: DshApproval = { id: request.id, sessionId: request.sessionId, canAllow: false,
      title: `${title}\n请在主机上查看完整审批详情。` };
    if (request.sessionId !== this.sessionId || !call || call.result !== undefined ||
      !/^[A-Za-z0-9_.:-]{1,160}$/.test(toolName) || call.name !== toolName ||
      !call.arguments || call.arguments.length > MAX_APPROVAL_TEXT || APPROVAL_UNSAFE_DISPLAY.test(call.arguments)) {
      return unavailable;
    }
    let args: WireObject;
    try {
      args = object(JSON.parse(call.arguments));
    } catch {
      return unavailable;
    }
    const shell = ['bash', 'pwsh', 'shell', 'powershell'].includes(toolName);
    const program = toolName === 'run_code';
    const source = string(args[shell ? 'command' : 'code']);
    if (!completeApprovalInput(toolName, args) ||
      ((shell || program) && (!source.trim() || APPROVAL_UNSAFE_DISPLAY.test(source)))) {
      return unavailable;
    }
    const details: string[] = [title, toolName];
    if (shell || program) {
      details.push(source);
      const cwd = string(args['workdir']);
      const scope = string(args['sandbox_permissions']);
      if (APPROVAL_UNSAFE_DISPLAY.test(cwd) || APPROVAL_UNSAFE_DISPLAY.test(scope)) {
        return unavailable;
      }
      if (cwd) details.push(`工作目录 ${cwd}`);
      if (scope) details.push(`沙箱权限 ${scope}`);
      if (args['run_in_background'] === true) details.push('后台运行');
    }
    details.push(call.arguments);
    const text = details.join('\n');
    if (text.length > MAX_APPROVAL_TEXT) {
      return unavailable;
    }
    return { id: request.id, sessionId: request.sessionId, canAllow: true, title: text };
  }

  queuedPrompts(): DshQueuedPrompt[] {
    return this.nextStep.map((item: Object) => queuedPrompt(item, 'next-step'))
      .concat(this.nextTurn.map((item: Object) => queuedPrompt(item, 'next-turn')))
      .filter((item: DshQueuedPrompt) => !!item.id);
  }

  projections(): DshSessionProjections {
    const wrapper: WireObject = {};
    wrapper['asOfSeq'] = this.projectionCursor;
    const values: WireObject = {};
    for (const key of Object.keys(this.projectionValues)) {
      values[key] = this.projectionValues[key];
    }
    wrapper['values'] = values;
    return sessionProjections(wrapper);
  }

  todos(): DshTodo[] | undefined {
    return todoList(this.projectionValues['todos']);
  }

  goalSupported(): boolean {
    return this.projectionValues['goal'] !== undefined;
  }

  goal(): DshGoal | undefined {
    const current = goalView(this.projectionValues['goal']);
    if (current && current.id === this.goalActivationRef?.id && current.revision === this.goalActivationRef.revision) {
      current.activation = this.goalActivation;
    }
    return current;
  }

  applyGoalActivation(value: Object | null | undefined): void {
    this.goalActivationRef = goalRef(value);
    this.goalActivation = string(object(value)['activation']) || undefined;
  }

  continuedQuestions(): DshQuestionRequest[] {
    return continuedQuestions(this.sessionId, this.projectionValues['userQuestions']);
  }

  applyControl(frame: WireObject): boolean {
    if (frame['type'] === 'baseline') {
      const sessions = object(object(frame['value'])['projections']);
      this.applyProjections(sessionProjections(sessions[this.sessionId]));
      return !!sessions[this.sessionId];
    }
    if (frame['type'] !== 'projection' || frame['sessionId'] !== this.sessionId) {
      return false;
    }
    const seq = number(frame['seq'], -1);
    if (Array.isArray(frame['changes'])) {
      for (const item of array(frame['changes'])) {
        const change = object(item);
        this.setProjection(string(change['key']), change['val'], seq);
      }
    } else {
      this.setProjection(string(frame['key']), frame['value'], seq);
    }
    return true;
  }

  private applyProjections(projections: DshSessionProjections): void {
    for (const key of Object.keys(projections.values)) {
      this.setProjection(key, projections.values[key], projections.asOfSeq);
    }
  }

  private setProjection(key: string, value: Object | null | undefined, seq: number): void {
    if (!key || seq < (this.projectionSeq.get(key) ?? -1)) {
      return;
    }
    this.projectionCursor = Math.max(this.projectionCursor, seq);
    this.projectionSeq.set(key, seq);
    this.projectionValues[key] = value;
    if (key === 'inbox') {
      const inbox = object(value);
      this.nextTurn = array(inbox['next-turn']).slice();
      this.nextStep = array(inbox['next-step']).slice();
    }
  }

  apply(value: WireObject): void {
    switch (value['type']) {
      case 'snapshot': {
        const relayBeforeSnapshot = this.sessionError;
        this.committed = [];
        this.records = [];
        this.toolCalls.clear();
        this.cursor = -1;
        this.running = false;
        this.compacting = false;
        for (const command of this.commands.values()) {
          if (command.seq !== undefined) this.commands.delete(command.id);
        }
        this.turnFailureCode = undefined;
        this.sessionError = undefined;
        this.terminalErrorSeen = false;
        this.notices = [];
        this.noticeTurn = undefined;
        this.latestEndNotice = undefined;
        this.noticeRecovery = undefined;
        this.retryingNotice = undefined;
        this.retryingId = '';
        this.lastTimelineSeq = -1;
        this.projectionValues = {};
        this.projectionSeq.clear();
        this.projectionCursor = -1;
        this.nextTurn = [];
        this.nextStep = [];
        this.applyProjections(sessionProjections(value['projections']));
        this.clearDraft();
        for (const record of array(value['records'])) {
          this.applyEvent(object(object(record)['event']));
        }
        this.cursor = number(value['cursor'], this.cursor);
        const attempt = object(object(value['assistantStream'])['activeAttempt']);
        this.attemptId = string(attempt['attemptId']);
        if (this.attemptId) {
          this.running = true;
          for (const item of array(attempt['stream'])) {
            const entry = object(item);
            if (entry['type'] === 'chunk') {
              this.applyChunk(object(entry['chunk']));
            } else if (entry['type'] === 'text-chunks' || entry['type'] === 'reasoning-chunks') {
              const index = number(entry['index'], -1);
              if (index >= 0) {
                const blocks = entry['type'] === 'text-chunks' ? this.draft : this.draftReasoning;
                blocks.set(index, (blocks.get(index) ?? '') + strings(entry['texts']).join(''));
              }
            }
          }
        }
        if (!this.terminalErrorSeen) {
          this.sessionError = relayBeforeSnapshot;
        }
        break;
      }
      case 'event':
        this.applyEvent(object(value['event']));
        break;
      case 'assistant-stream':
        this.applyStream(object(value['frame']));
        break;
    }
  }

  private applyEvent(event: WireObject): void {
    const seq = number(event['seq'], -1);
    if (seq <= this.cursor) {
      return;
    }
    this.cursor = seq;
    const type = string(event['type']);
    const data = object(event['data']);
    this.records.push({ seq: seq, type: type, time: number(event['time'], 0), data: data });
    this.applyProjectedEvent(type, data, seq);
    if (type === 'command/run' || type === 'command/done') {
      const id = string(data['commandId']);
      const previous = this.commands.get(id);
      if (id && type === 'command/run') {
        const name = string(data['name']);
        if (/^[a-z][a-z0-9_-]*$/.test(name)) {
          this.commands.set(id, { id: id, name: name, args: commandText(data['args'], 1000) || undefined,
            seq: seq, done: previous?.done ?? false, success: previous?.success, text: previous?.text });
        }
      } else if (id && previous && (data['kind'] === 'success' || data['kind'] === 'error')) {
        const success = data['kind'] === 'success';
        this.commands.set(id, { id: id, name: previous.name, args: previous.args, seq: previous.seq,
          done: true, success: success, text: commandOutcome(previous.name, success, data['text']) });
      }
      return;
    }
    if (type === 'compaction/start' || type === 'compaction/end') {
      this.compacting = type === 'compaction/start';
      return;
    }
    if (type === 'turn/start') {
      this.running = true;
      this.turnFailureCode = undefined;
      this.sessionError = undefined;
      this.terminalErrorSeen = false;
      this.latestEndNotice = undefined;
      this.noticeRecovery = undefined;
      this.retryingNotice = undefined;
      this.retryingId = '';
      const turn = positiveInteger(data['turn']);
      this.noticeTurn = turn === undefined ? undefined : { turn: turn, worked: false };
      return;
    }
    if (type === 'turn/end') {
      this.running = false;
      this.compacting = false;
      this.clearDraft();
      this.finishNoticeTurn(seq, data);
      return;
    }
    if (type === 'llm/retry') {
      this.notices.push(retryTurnNotice(seq, data, false));
      this.retryingId = string(data['retryId']);
      this.retryingNotice = this.running ? retryTurnNotice(seq, data, true) : undefined;
      return;
    }
    if (type === 'llm/retry-started') {
      if (this.retryingId === string(data['retryId'])) {
        this.retryingNotice = undefined;
        this.retryingId = '';
      }
      return;
    }
    if (type === 'tool/call') {
      const callId = string(data['callId']);
      const argumentsJson = string(data['arguments']);
      if (callId) {
        this.lastTimelineSeq = seq;
        if (this.noticeTurn) this.noticeTurn.worked = true;
        this.toolCalls.set(callId, { callId: callId, name: string(data['name']), arguments: argumentsJson, seq: seq });
      }
      return;
    }
    if (type === 'tool/result') {
      const result = object(data['message']);
      const callId = string(result['toolCallId']);
      if (callId) {
        this.lastTimelineSeq = seq;
        if (this.noticeTurn) this.noticeTurn.worked = true;
        const previous = this.toolCalls.get(callId);
        const content = array(result['content']).map(object);
        this.toolCalls.set(callId, { callId: callId, name: previous?.name ?? string(result['toolName']),
          arguments: previous?.arguments ?? '', seq: previous?.seq ?? seq,
          result: this.partText(content, 'text'), content: content, isError: result['isError'] === true,
          meta: data['meta'], failure: data['failure'] ? object(data['failure']) : undefined });
      }
      return;
    }
    let message: WireObject;
    let role: string;
    if (type === 'user/message' && object(data['source'])['kind'] === 'user') {
      message = data;
      role = 'user';
    } else if (type === 'assistant/message') {
      message = object(data['message']);
      role = 'assistant';
      this.clearDraft();
    } else {
      return;
    }
    const content = array(message['content']).map(object);
    const usage = tokenUsage(data['usage']);
    if (content.length > 0 || usage) {
      const row: DshMessage = { id: string(message['id']) || `event-${seq}`, role: role,
        requestId: role === 'user' ? string(object(message['source'])['rpcId']) || undefined : undefined,
        text: this.partText(content, 'text'), reasoning: this.partText(content, 'reasoning') || undefined,
        usage: usage, content: content, seq: seq };
      this.committed.push(row);
      this.lastTimelineSeq = seq;
      if (this.noticeTurn) {
        if (role === 'user') {
          this.noticeTurn.prompt = row;
        } else if (row.text.trim() || content.some((part: WireObject): boolean => part['type'] === 'tool-call')) {
          this.noticeTurn.worked = true;
        }
      }
    }
  }

  private applyProjectedEvent(type: string, data: WireObject, seq: number): void {
    if (type === 'agent/inbox/spliced' && seq > (this.projectionSeq.get('inbox') ?? -1)) {
      const target = string(data['target']);
      if (target !== 'next-turn' && target !== 'next-step') {
        return;
      }
      const items = target === 'next-turn' ? this.nextTurn : this.nextStep;
      const start = Math.max(0, Math.min(items.length, number(data['start'], 0)));
      const removed = Math.max(0, number(data['removedCount'], 0));
      const updated = items.slice(0, start).concat(array(data['inserted']), items.slice(start + removed));
      const inbox: WireObject = {};
      inbox['next-turn'] = target === 'next-turn' ? updated : this.nextTurn;
      inbox['next-step'] = target === 'next-step' ? updated : this.nextStep;
      this.setProjection('inbox', inbox, seq);
    } else if (type === 'todo/write' || (type === 'turn/start' && this.projectionValues['todos'] !== undefined)) {
      this.setProjection('todos', type === 'todo/write' ? data['todos'] : null, seq);
    } else if (type === 'goal/change') {
      this.setProjection('goal', data['operation'] === 'clear' ? null : data, seq);
    } else if (type === 'user/message' && this.goalSupported()) {
      const source = object(data['source']);
      const goal = this.goal();
      const round = number(source['round'], -1);
      if (goal && source['kind'] === 'goal' && source['goalId'] === goal.id && round > goal.roundsStarted) {
        const updated: WireObject = {};
        const previous = object(this.projectionValues['goal']);
        for (const key of Object.keys(previous)) {
          updated[key] = previous[key];
        }
        updated['roundsStarted'] = round;
        this.setProjection('goal', updated, seq);
      }
    } else if (type === 'permission/preset') {
      const current: WireObject = {};
      current['currentValue'] = data['preset'];
      this.setProjection('permissions', current, seq);
    } else if (type === 'agent-preset/selected') {
      this.setProjection('agentPreset', data['agentPreset'], seq);
    }
  }

  private applyStream(frame: WireObject): void {
    const id = string(frame['attemptId']);
    if (!id) {
      return;
    }
    if (frame['type'] === 'start') {
      this.clearDraft();
      this.attemptId = id;
    } else if (id === this.attemptId) {
      if (frame['type'] === 'chunk') {
        this.applyChunk(object(frame['chunk']));
      } else if (frame['type'] === 'end') {
        this.clearDraft();
      }
    }
  }

  private applyChunk(chunk: WireObject): void {
    if (chunk['type'] === 'usage') {
      this.draftUsage = tokenUsage(chunk['usage']);
      return;
    }
    const index = number(chunk['index'], -1);
    if (index < 0) {
      return;
    }
    if (chunk['type'] === 'text-delta') {
      this.draft.set(index, (this.draft.get(index) ?? '') + string(chunk['text']));
    } else if (chunk['type'] === 'reasoning-delta') {
      this.draftReasoning.set(index, (this.draftReasoning.get(index) ?? '') + string(chunk['text']));
    } else if (chunk['type'] === 'block-end') {
      const block = object(chunk['block']);
      if (block['type'] === 'text') {
        this.draft.set(index, string(block['text']));
      } else if (block['type'] === 'reasoning') {
        this.draftReasoning.set(index, string(block['text']));
      }
    }
  }

  private partText(content: WireObject[], type: string): string {
    return content.filter((part: WireObject) => part['type'] === type)
      .map((part: WireObject) => string(part['text'])).filter((text: string) => text.length > 0).join('\n');
  }

  private draftText(blocks: Map<number, string>): string {
    return Array.from(blocks.keys()).sort((a: number, b: number) => a - b)
      .map((key: number) => blocks.get(key) ?? '').join('\n');
  }

  private clearDraft(): void {
    this.attemptId = '';
    this.draft.clear();
    this.draftReasoning.clear();
    this.draftUsage = undefined;
  }
}
