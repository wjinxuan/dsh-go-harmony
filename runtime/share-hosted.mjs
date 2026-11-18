import { randomBytes, createCipheriv, createDecipheriv } from 'node:crypto';
import { gzipSync, gunzipSync } from 'node:zlib';

export const SHARE_ORIGIN = 'https://go.dshtui.com';
const MAX_BLOB = 20 * 1024 * 1024, MAX_PLAIN = 64 * 1024 * 1024;
export function encryptShare(text) {
  const plain = Buffer.from(text);
  if (plain.length > MAX_PLAIN) throw new Error('分享内容过大');
  const key = randomBytes(32), iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', key, iv);
  const bytes = Buffer.concat([Buffer.from('DSG1'), iv, cipher.update(gzipSync(plain)), cipher.final(), cipher.getAuthTag()]);
  if (bytes.length > MAX_BLOB) throw new Error('加密文件超过 20 MB');
  return { bytes, key: key.toString('base64url') };
}
export function decryptShare(bytes, encodedKey) {
  if (!Buffer.isBuffer(bytes)) bytes = Buffer.from(bytes);
  if (bytes.length < 32 || bytes.length > MAX_BLOB || bytes.subarray(0, 4).toString() !== 'DSG1' || !/^[\w-]{43}$/.test(encodedKey)) throw new Error('加密文件或密钥无效');
  const key = Buffer.from(encodedKey, 'base64url');
  if (key.length !== 32 || key.toString('base64url') !== encodedKey) throw new Error('链接密钥无效');
  try {
    const decipher = createDecipheriv('aes-256-gcm', key, bytes.subarray(4, 16));
    decipher.setAuthTag(bytes.subarray(-16));
    const compressed = Buffer.concat([decipher.update(bytes.subarray(16, -16)), decipher.final()]);
    return new TextDecoder('utf-8', { fatal: true }).decode(gunzipSync(compressed, { maxOutputLength: MAX_PLAIN }));
  } catch { throw new Error('无法解密，密钥错误或分享内容损坏'); }
}
export function hostedLink(value) {
  let url;
  try { url = new URL(value); } catch { throw new Error('分享链接无效'); }
  const match = /^\/c\/([A-Za-z0-9]{10})\/?$/.exec(url.pathname), key = new URLSearchParams(url.hash.slice(1)).get('k');
  if (url.origin !== SHARE_ORIGIN || url.username || url.password || url.search || !match || !key || !/^[\w-]{43}$/.test(key)) throw new Error('不是受支持的加密分享链接');
  return { id: match[1], key, url: SHARE_ORIGIN + '/c/' + match[1] + '#k=' + key };
}
async function readBounded(response, limit) {
  if (Number(response.headers.get('content-length')) > limit) { await response.body?.cancel(); throw new Error('服务器返回内容过大'); }
  const chunks = []; let size = 0;
  for await (const chunk of response.body ?? []) { size += chunk.length; if (size > limit) throw new Error('服务器返回内容过大'); chunks.push(chunk); }
  return Buffer.concat(chunks);
}
function status(response) {
  if (response.status === 404) return new Error('分享已失效或被删除');
  if (response.status === 413) return new Error('分享文件过大');
  if (response.status === 429) return new Error('分享过于频繁，请稍后再试');
  if ([401, 403].includes(response.status)) return new Error('分享服务拒绝了此操作');
  return new Error('分享服务暂时不可用（HTTP ' + response.status + '）');
}
export async function uploadShare(file, ttl, { signal, fetcher = fetch } = {}) {
  if (!['7d', '30d', 'forever'].includes(ttl)) throw new Error('无效的链接有效期');
  const encrypted = encryptShare(file);
  const response = await fetcher(SHARE_ORIGIN + '/api/v1/c?ttl=' + ttl, { method: 'POST', redirect: 'error', signal,
    headers: { 'content-type': 'application/octet-stream' }, body: encrypted.bytes });
  if (response.status !== 201) { await response.body?.cancel(); throw status(response); }
  let body;
  try { body = JSON.parse((await readBounded(response, 16384)).toString('utf8')); } catch { throw new Error('分享服务返回格式有误'); }
  if (!body || typeof body.id !== 'string' || !/^[A-Za-z0-9]{10}$/.test(body.id) || typeof body.deleteToken !== 'string' || !body.deleteToken || body.deleteToken.length > 4096 || /[\r\n]/.test(body.deleteToken)) throw new Error('分享服务没有返回有效管理凭据');
  return { id: body.id, key: encrypted.key, deleteToken: body.deleteToken, expiresAt: typeof body.expiresAt === 'string' ? body.expiresAt : undefined,
    url: SHARE_ORIGIN + '/c/' + body.id + '#k=' + encrypted.key };
}
export async function downloadShare(link, { signal, fetcher = fetch } = {}) {
  const parsed = hostedLink(link);
  const response = await fetcher(SHARE_ORIGIN + '/api/v1/c/' + parsed.id, { redirect: 'error', signal });
  if (response.status !== 200) { await response.body?.cancel(); throw status(response); }
  return decryptShare(await readBounded(response, MAX_BLOB), parsed.key);
}
export async function deleteShare(link, { signal, fetcher = fetch } = {}) {
  if (!link || !/^[A-Za-z0-9]{10}$/.test(link.id) || typeof link.deleteToken !== 'string' || !link.deleteToken || /[\r\n]/.test(link.deleteToken)) throw new Error('缺少有效删除凭据');
  const response = await fetcher(SHARE_ORIGIN + '/api/v1/c/' + link.id, { method: 'DELETE', redirect: 'error', signal, headers: { authorization: 'Bearer ' + link.deleteToken } });
  await response.body?.cancel();
  if (![204, 404].includes(response.status)) throw status(response);
}
