import { createHash } from 'node:crypto';
import { deflateRawSync, inflateRawSync } from 'node:zlib';

export const MAX_FILE = 4 * 1024 * 1024;
const MAX_BODY = 16 * 1024 * 1024, MAX_CODE = 6 * 1024 * 1024;
const object = v => v && typeof v === 'object' && !Array.isArray(v);
const integer = v => typeof v === 'number' && Number.isFinite(v) && v >= 0 ? Math.round(v) : undefined;
function prefix(text, length) { return text.slice(0, length - (/^[\uDC00-\uDFFF]$/.test(text[length] ?? '') ? 1 : 0)); }
const str = (v, n) => typeof v === 'string' && v ? v.length <= n ? v : prefix(v, n) + '…' : undefined;
const line = (v, n) => typeof v === 'string' ? str(v.replace(/\s+/g, ' ').trim(), n) : undefined;
const clean = value => Object.fromEntries(Object.entries(value).filter(([, v]) => v !== undefined));
export const assetId = bytes => createHash('sha256').update(bytes).digest().subarray(0, 9).toString('base64url');
const checksum = bytes => createHash('sha256').update(bytes).digest().subarray(0, 6).toString('base64url');

export function encodeCode(body) {
  const bytes = Buffer.from(JSON.stringify(body));
  if (bytes.length > MAX_BODY) throw new Error('分享内容超过大小限制');
  const code = deflateRawSync(bytes, { level: 9 }).toString('base64url') + '.' + checksum(bytes);
  if (code.length > MAX_CODE) throw new Error('分享码超过大小限制');
  return code;
}

export function decodeCode(value) {
  if (typeof value !== 'string' || value.length > MAX_CODE) throw new Error('分享码超过大小限制');
  const code = value.trim(), parts = code.split('.');
  if (parts.length !== 2 || !/^[\w-]+$/.test(parts[0]) || !/^[\w-]{8}$/.test(parts[1])) throw new Error('分享码格式有误');
  const compressed = Buffer.from(parts[0], 'base64url');
  if (compressed.toString('base64url') !== parts[0]) throw new Error('分享码编码有误');
  let bytes;
  try { bytes = inflateRawSync(compressed, { maxOutputLength: MAX_BODY }); }
  catch { throw new Error('分享内容损坏或超过大小限制'); }
  if (checksum(bytes) !== parts[1]) throw new Error('分享码校验失败');
  let body;
  try { body = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)); }
  catch { throw new Error('分享内容不是有效 JSON'); }
  if (!object(body)) throw new Error('分享内容必须是对象');
  if (body.kind !== 'conversation' && (bytes.length > 1024 * 1024 || code.length > 1024 * 1024)) throw new Error('分享内容超过大小限制');
  return body;
}

export function conversation(body) {
  if (!object(body) || !Number.isInteger(body.v) || body.v < 1 || body.v > 2 || body.kind !== 'conversation' || body.schema !== 1) {
    throw new Error('不是兼容的会话文件，可能需要更新应用');
  }
  if (typeof body.start !== 'string' || !Number.isFinite(Date.parse(body.start))) throw new Error('会话缺少有效时间');
  if (!Array.isArray(body.entries) || body.entries.length > 20000) throw new Error('会话条目无效或过多');
  const entries = body.entries.map(entry).filter(Boolean), r = body.range;
  return clean({ v: 2, kind: 'conversation', schema: 1, title: line(body.title, 120) || '对话',
    start: new Date(body.start).toISOString(), model: line(body.model, 80), app: line(body.app, 40),
    created: typeof body.created === 'string' && Number.isFinite(Date.parse(body.created)) ? new Date(body.created).toISOString() : undefined,
    range: object(r) && [r.from, r.to, r.of].every(v => integer(v) !== undefined) ? { from: integer(r.from), to: integer(r.to), of: integer(r.of) } : undefined,
    include: { thinking: body.include?.thinking !== false, tools: body.include?.tools !== false }, entries });
}

function entry(e) {
  if (!object(e)) throw new Error('会话条目必须是对象');
  const base = { type: e.type, t: integer(e.t) ?? 0 }, d = integer(e.d);
  switch (e.type) {
    case 'turn': return clean({ ...base, d, end: str(e.end, 32), steps: integer(e.steps), tokens: integer(e.tokens) });
    case 'user': return clean({ ...base, text: str(e.text, 400000) || '', source: str(e.source, 32),
      images: (Array.isArray(e.images) ? e.images : []).slice(0, 20).filter(i => object(i) && typeof i.id === 'string' && /^[\w-]{8,32}$/.test(i.id))
        .map(i => clean({ id: i.id, w: integer(i.w), h: integer(i.h), name: str(i.name, 200) })),
      files: (Array.isArray(e.files) ? e.files : []).slice(0, 20).filter(i => object(i) && str(i.name, 200))
        .map(i => clean({ name: str(i.name, 200), size: integer(i.size) })) });
    case 'reply': return clean({ ...base, d, text: str(e.text, 400000) || '', think: str(e.think, 400000), plain: str(e.plain, 400000), model: str(e.model, 80), cut: e.cut === true });
    case 'tool': return clean({ ...base, d, name: str(e.name, 80) || 'tool', args: object(e.args) ? e.args : {}, summary: str(e.summary, 500) || '',
      verb: str(e.verb, 40), status: ['failed', 'denied', 'cancelled'].includes(e.status) ? e.status : 'ok', result: str(e.result, 64000), more: integer(e.more) ?? 0, error: str(e.error, 2000) });
    case 'notice': return { ...base, kind: str(e.kind, 32) || 'error', text: str(e.text, 4000) || '' };
    case 'todos': return { ...base, items: (Array.isArray(e.items) ? e.items : []).slice(0, 200).filter(i => object(i) && str(i.text, 500))
      .map(i => ({ text: str(i.text, 500), status: str(i.status, 20) || 'pending' })) };
    case 'goal': return clean({ ...base, text: str(e.text, 4000), phase: str(e.phase, 20) });
    case 'command': return clean({ ...base, line: str(e.line, 2000) || '/', ok: e.ok !== false, text: str(e.text, 8000) });
    default: return undefined;
  }
}

export function conversationAssets(raw, body) {
  const wanted = new Set(body.entries.filter(e => e.type === 'user').flatMap(e => e.images || []).map(i => i.id));
  const result = Object.create(null);
  for (const [id, value] of Object.entries(object(raw) ? raw : {})) {
    if (!wanted.has(id) || !object(value) || !['image/png', 'image/jpeg', 'image/webp', 'image/gif'].includes(value.type) ||
      typeof value.data !== 'string' || value.data.length > MAX_FILE || !/^[A-Za-z0-9+/]*={0,2}$/.test(value.data)) continue;
    const bytes = Buffer.from(value.data, 'base64');
    if (assetId(bytes) === id) result[id] = clean({ type: value.type, data: bytes.toString('base64'), w: integer(value.w), h: integer(value.h) });
  }
  return result;
}

export function conversationFile(body, assets) {
  const checked = conversation(body), code = encodeCode(checked), pictures = conversationAssets(assets, checked);
  const file = JSON.stringify({ dshgo: 2, kind: 'conversation', name: checked.title, code, ...(Object.keys(pictures).length ? { assets: pictures } : {}) }) + '\n';
  if (Buffer.byteLength(file) > MAX_FILE) throw new Error('会话文件超过 4 MB，请减少回合或关闭图片');
  return { body: checked, assets: pictures, code, file };
}

export function decodeFile(text) {
  if (typeof text !== 'string' || Buffer.byteLength(text) > MAX_FILE) throw new Error('会话文件超过 4 MB');
  const trimmed = text.trim(); let code = trimmed, assets;
  if (trimmed.startsWith('{')) {
    let value;
    try { value = JSON.parse(trimmed); } catch { throw new Error('文件不是有效 JSON'); }
    if (!object(value) || !Number.isInteger(value.dshgo) || typeof value.code !== 'string') throw new Error('不是 dsh-go 文件');
    code = value.code; assets = value.assets;
  }
  const body = conversation(decodeCode(code));
  return { body, assets: conversationAssets(assets, body), code };
}

export function conversationHtml(file, title, template) {
  const escape = v => v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
  const data = file.trim().replace(/[<>&\u2028\u2029]/g, c => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));
  return template.replace('__DSHGO_TITLE__', () => escape(title) + ' · DSH Go').replace('__DSHGO_DATA__', () => data);
}
