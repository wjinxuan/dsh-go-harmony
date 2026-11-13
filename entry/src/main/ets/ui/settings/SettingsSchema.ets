import { array, number, object, string, strings, WireObject } from '../../dsh/DshWire';

export interface SettingsField {
  path: string[];
  title: string;
  description: string;
  kind: string;
  disabled: boolean;
  required: boolean;
  current: Object | null | undefined;
  inherited: Object | null | undefined;
  overridden: boolean;
  secretSet: boolean;
  choices: Object[];
  min?: number;
  max?: number;
  step?: number;
}

export interface SettingsSection {
  id: string;
  title: string;
  description: string;
  revision: number;
  writable: boolean;
  autoGenerate: boolean;
  fields: SettingsField[];
  value: WireObject;
}

const SECTION_NAMES: Record<string, string> = {
  'agent-default-model': '新对话默认模型',
  'subagent': '子代理',
  'subagent-model-selection-settings': '子代理模型',
  'agent-loop': '工具并发',
  'bash-sandbox': '命令执行',
  'pwsh-sandbox': '命令执行',
  'web': '网页搜索',
  'web-search-deepseek': 'DeepSeek 网页搜索',
  'web-deepseek-api': 'DeepSeek 搜索 API',
  'session-log-deepseek': '对话日志',
  'cot-translation': '思考过程翻译',
  'plugin-market': '插件索引',
  'permission': '权限',
  'agent-preset-registry': '代理预设'
};

const FIELD_NAMES: Record<string, string> = {
  'maxDepth': '最大子代理深度', 'maxActiveSubagents': '同时运行的子代理上限',
  'maxParallelToolCalls': '并行工具调用上限', 'timeoutMs': '命令超时（毫秒）',
  'maxOutputBytes': '最大输出（字节）', 'maxTimeoutMs': '最大超时（毫秒）',
  'maxSpillBytes': '最大溢出输出（字节）', 'graceMs': '结束宽限（毫秒）',
  'cwd': '默认工作目录', 'searchProvider': '搜索服务商', 'fetchProvider': '网页获取服务商',
  'apiKey': 'API Key', 'baseURL': '基础地址', 'maxUses': '最大搜索次数',
  'model': '模型', 'apiVersion': 'API 版本', 'maxTokens': '最大令牌数',
  'count': '每次搜索返回条数', 'sendOriginalQuestion': '发送原始问题',
  'targetLanguage': '目标语言', 'indexes': '插件索引地址', 'defaultPreset': '新对话默认权限',
  'selectedDefault': '默认代理预设', 'provider': '服务商', 'reasoningEffort': '思考深度',
  'allowedModels': '允许的模型', 'rememberLastSelection': '记住上次选择'
};

function localized(value: Object | null | undefined): string {
  const locales = object(value);
  const keys = Object.keys(locales);
  const chinese = keys.find((key: string) => /^zh(?:[-_]|$)/i.test(key) && string(locales[key]).trim());
  const english = keys.find((key: string) => /^en(?:[-_]|$)/i.test(key) && string(locales[key]).trim());
  const plain = string(locales['']);
  return string(value) || (chinese ? string(locales[chinese]) : '') ||
    (/[\u3400-\u9fff]/.test(plain) ? plain : '') || (english ? string(locales[english]) : '') || plain;
}

function resolve(ref: Object | null | undefined, refs: WireObject): WireObject {
  return typeof ref === 'number' || typeof ref === 'string' ? object(refs[String(ref)]) : object(ref);
}

function valueAt(source: WireObject, path: string[]): Object | null | undefined {
  let value: Object | null | undefined = source;
  for (const key of path) {
    value = object(value)[key];
  }
  return value;
}

function numeric(value: Object | null | undefined): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}

interface SchemaContext {
  refs: WireObject;
  value: WireObject;
  base: WireObject;
  user: WireObject;
  secrets: Map<string, boolean>;
  fields: SettingsField[];
}

function containsSecret(node: WireObject, refs: WireObject, depth: number): boolean {
  if (depth > 20 || ['secret', 'credential-ref'].includes(string(object(node['meta'])['role']))) {
    return true;
  }
  const children = object(node['dict']);
  return (node['inner'] !== undefined && containsSecret(resolve(node['inner'], refs), refs, depth + 1)) ||
    array(node['list']).some((ref: Object) => containsSecret(resolve(ref, refs), refs, depth + 1)) ||
    Object.keys(children).some((key: string) => containsSecret(resolve(children[key], refs), refs, depth + 1));
}

function walk(node: WireObject, path: string[], inherited: WireObject, context: SchemaContext, depth: number): void {
  if (depth > 20 || context.fields.length >= 180) {
    return;
  }
  const meta = object(node['meta']);
  const kind = string(node['type']);
  if (meta['hidden'] === true || inherited['hidden'] === true || !kind) {
    return;
  }
  const effective: WireObject = {};
  for (const key of Object.keys(inherited)) {
    effective[key] = inherited[key];
  }
  for (const key of Object.keys(meta)) {
    effective[key] = meta[key];
  }
  effective['disabled'] = inherited['disabled'] === true || meta['disabled'] === true;
  const pathKey = JSON.stringify(path);
  const role = string(effective['role']);
  const secret = role === 'secret' || context.secrets.has(pathKey);
  if (role === 'credential-ref' || kind === 'const') {
    return;
  }
  if (!secret && (kind === 'lazy' || kind === 'transform')) {
    walk(resolve(node['inner'], context.refs), path, effective, context, depth + 1);
    return;
  }
  if (!secret && kind === 'intersect') {
    for (const entry of array(node['list'])) {
      walk(resolve(entry, context.refs), path, effective, context, depth + 1);
    }
    return;
  }
  if (!secret && kind === 'object') {
    const dict = object(node['dict']);
    const parent: WireObject = {};
    parent['disabled'] = effective['disabled'];
    for (const key of Object.keys(dict)) {
      walk(resolve(dict[key], context.refs), path.concat(key), parent, context, depth + 1);
    }
    return;
  }
  if (!path.length || context.fields.some((field: SettingsField) => JSON.stringify(field.path) === pathKey)) {
    return;
  }
  const choices: Object[] = [];
  if (kind === 'union') {
    for (const ref of array(node['list'])) {
      const choice = resolve(ref, context.refs);
      const value = choice['value'];
      if (choice['type'] === 'const' && (typeof value === 'string' || typeof value === 'number' ||
        typeof value === 'boolean')) {
        choices.push(value);
      }
    }
    if (choices.length !== array(node['list']).length) {
      choices.splice(0, choices.length);
    }
  }
  const key = path[path.length - 1];
  const protectedCollection = ['array', 'dict', 'tuple', 'union'].includes(kind) && containsSecret(node, context.refs, 0);
  context.fields.push({
    path: path,
    title: localized(effective['title']) || FIELD_NAMES[key] || path.join(' · '),
    description: localized(effective['description']) || string(effective['comment']),
    kind: secret ? 'secret' : protectedCollection ? 'protected' : choices.length ? 'enum' : kind,
    disabled: effective['disabled'] === true || protectedCollection || (secret && kind !== 'string' &&
      kind !== 'transform' && kind !== 'lazy'),
    required: effective['required'] === true,
    current: secret || protectedCollection ? undefined : valueAt(context.value, path),
    inherited: secret || protectedCollection ? undefined : valueAt(context.base, path) ?? effective['default'],
    overridden: secret ? context.secrets.get(pathKey) === true : valueAt(context.user, path) !== undefined,
    secretSet: secret && context.secrets.get(pathKey) === true,
    choices: choices,
    min: numeric(effective['min']), max: numeric(effective['max']), step: numeric(effective['step'])
  });
}

export function parseSettingsSection(raw: WireObject, writable: boolean): SettingsSection {
  const id = string(raw['ns']);
  const envelope = object(raw['schema']);
  const refs = object(envelope['refs']);
  const root = envelope['refs'] ? resolve(envelope['uid'], refs) : envelope;
  const meta = object(root['meta']);
  const secrets: Map<string, boolean> = new Map();
  for (const item of array(raw['secrets'])) {
    const slot = object(item);
    secrets.set(JSON.stringify(strings(slot['path'])), slot['set'] === true);
  }
  const value = object(raw['value']);
  const fields: SettingsField[] = [];
  const context: SchemaContext = {
    refs: refs, value: value, base: object(raw['base']), user: object(raw['user']), secrets: secrets, fields: fields
  };
  walk(root, [], {}, context, 0);
  return {
    id: id, title: SECTION_NAMES[id] || localized(meta['title']) || id,
    description: localized(meta['description']), revision: number(raw['revision'], 0),
    writable: writable && raw['writable'] !== false,
    autoGenerate: raw['autoGenerate'] !== false, fields: fields, value: value
  };
}

export function parseSettings(raw: WireObject): SettingsSection[] {
  return array(raw['namespaces']).map((item: Object) => parseSettingsSection(object(item), raw['writable'] !== false))
    .filter((section: SettingsSection) => section.id.length > 0);
}

export function editableField(field: SettingsField): boolean {
  return !field.disabled && ['boolean', 'number', 'string', 'enum', 'secret', 'array', 'dict', 'tuple'].includes(field.kind);
}

export function fieldText(field: SettingsField): string {
  if (field.kind === 'secret') {
    return field.secretSet ? '已设置' : '未设置';
  }
  if (field.kind === 'protected') {
    return '含受保护的字段';
  }
  if (field.current === null || field.current === undefined) {
    return '';
  }
  if (typeof field.current === 'object') {
    return JSON.stringify(field.current, undefined, 2);
  }
  return String(field.current);
}

export function fieldInput(field: SettingsField, value: string): Object | null {
  if ((field.kind === 'secret' || field.required) && value.trim() === '' && field.kind !== 'string') {
    throw new Error('此项为必填项');
  }
  if (field.kind === 'number') {
    const parsed = Number(value.trim());
    if (!value.trim() || !Number.isFinite(parsed)) {
      throw new Error('请输入有效数字');
    }
    if (field.min !== undefined && parsed < field.min) {
      throw new Error(`最小值为 ${field.min}`);
    }
    if (field.max !== undefined && parsed > field.max) {
      throw new Error(`最大值为 ${field.max}`);
    }
    if (field.step !== undefined && field.step > 0) {
      const increments = (parsed - (field.min ?? 0)) / field.step;
      if (Math.abs(increments - Math.round(increments)) > 0.0000001) {
        throw new Error(`请输入步长为 ${field.step} 的值`);
      }
    }
    return parsed;
  }
  if (field.kind === 'array' || field.kind === 'tuple' || field.kind === 'dict') {
    const parsed = JSON.parse(value) as Object | null;
    if (field.kind === 'dict' ? !parsed || typeof parsed !== 'object' || Array.isArray(parsed) : !Array.isArray(parsed)) {
      throw new Error(field.kind === 'dict' ? '请输入 JSON 对象' : '请输入 JSON 数组');
    }
    return parsed;
  }
  return value;
}
