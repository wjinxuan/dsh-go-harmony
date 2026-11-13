import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { url, util } from '@kit.ArkTS';
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { array, object, string, WireObject } from '../dsh/DshWire';

export interface RemoteHost {
  id: string;
  name: string;
  origin: string;
  hasCredential: boolean;
}

export interface RemoteHostConnection {
  id: string;
  name: string;
  launchUrl: string;
  authorization: string;
}

export interface RemoteHostDraft {
  id: string;
  name: string;
  launchUrl: string;
  authorization: string;
  remember: boolean;
}

export class RemoteHostError extends Error {}

interface HostAddress {
  launchUrl: string;
  authorization: string;
  origin: string;
  token: string;
}

interface HostProfile {
  id: string;
  name: string;
  origin: string;
}

const FILE: string = 'dsh-remote-hosts';
const KEY: string = 'hosts-v1';
const ALIAS_PREFIX: string = 'dsh-go.remote-host.v1.';
const MAX_ASSET_BYTES: number = 1024;
export const MAX_REMOTE_HOST_NAME: number = 64;
export const MAX_REMOTE_LAUNCH_URL: number = 4096;
export const MAX_REMOTE_AUTHORIZATION: number = 4096;
const UUID: RegExp = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
const CONTROL: RegExp = /[\x00-\x1f\x7f]/;
const RAW_AUTHORITY: RegExp = /^https?:\/\/([^/?#]+)/i;

function addressOf(value: string): url.URL {
  const authority = RAW_AUTHORITY.exec(value)?.[1] || '';
  if (!authority || authority.includes('@') || value.includes('\\') || CONTROL.test(value)) {
    throw new RemoteHostError('请输入完整的 DSH 启动链接。');
  }
  let address: url.URL;
  try {
    address = url.URL.parseURL(value);
  } catch {
    throw new RemoteHostError('请输入完整的 DSH 启动链接。');
  }
  const literalLoopback = /^(?:127\.0\.0\.1|\[::1\])(?::[0-9]+)?$/i.test(authority) &&
    (address.hostname === '127.0.0.1' || address.hostname === '[::1]');
  if (address.protocol !== 'https:' && !(address.protocol === 'http:' && literalLoopback)) {
    throw new RemoteHostError('远程主机链接必须使用 HTTPS。');
  }
  if (!address.hostname || address.username || address.password || value.includes('#')) {
    throw new RemoteHostError('启动链接不能包含用户名、密码或片段。');
  }
  return address;
}

function parseCredentials(launchUrl: string, authorization: string): HostAddress {
  const link = launchUrl.trim();
  if (!link || link.length > MAX_REMOTE_LAUNCH_URL) {
    throw new RemoteHostError('请输入完整的 DSH 启动链接。');
  }
  if (authorization.length > MAX_REMOTE_AUTHORIZATION || CONTROL.test(authorization)) {
    throw new RemoteHostError('反向代理授权格式无效或过长。');
  }
  const address = addressOf(link);
  const token = address.params.get('token') || '';
  if (!token.trim() || CONTROL.test(token) || address.params.getAll('token').length !== 1) {
    throw new RemoteHostError('请输入带有一个有效 token 参数的 DSH 启动链接。');
  }
  return { launchUrl: link, authorization: authorization.trim(), origin: address.origin, token: token };
}

function safeName(value: string): boolean {
  return value.length <= MAX_REMOTE_HOST_NAME && !CONTROL.test(value) &&
    !/(?:[\w+.-]+:\/\/|\btoken\s*=|\bauthorization\s*:|^(?:bearer|basic)\s)/i.test(value);
}

function profileName(name: string, origin: string, address?: HostAddress): string {
  const trimmed = name.trim();
  const token = address?.token || '';
  const authorization = address?.authorization || '';
  const headerValue = authorization.replace(/^\S+\s+/, '');
  if (!safeName(name) ||
    (token.length > 0 && (trimmed === token || (token.length >= 8 && trimmed.includes(token)))) ||
    (authorization.length > 0 && (trimmed === authorization || trimmed === headerValue ||
      (headerValue.length >= 8 && trimmed.includes(headerValue))))) {
    throw new RemoteHostError('请输入简短的主机名称，名称中请勿填写链接或凭据。');
  }
  return trimmed || addressOf(origin).host;
}

function readProfiles(store: preferences.Preferences): HostProfile[] {
  try {
    const encoded = store.getSync(KEY, '[]') as string;
    const decoded: Object = JSON.parse(encoded) as Object;
    if (!Array.isArray(decoded)) throw new Error();
    const seenIds: Set<string> = new Set();
    const seenOrigins: Set<string> = new Set();
    return array(decoded).map((value: Object): HostProfile => {
      const row = object(value);
      const id = string(row['id']);
      const name = string(row['name']);
      const origin = string(row['origin']);
      if (!UUID.test(id) || !name || !safeName(name) || addressOf(origin).origin !== origin ||
        seenIds.has(id) || seenOrigins.has(origin)) throw new Error();
      seenIds.add(id);
      seenOrigins.add(origin);
      return { id: id, name: name, origin: origin };
    });
  } catch {
    throw new RemoteHostError('无法读取已保存的远程主机。');
  }
}

async function hostPreferences(context: common.Context): Promise<preferences.Preferences> {
  try {
    return await preferences.getPreferences(context, FILE);
  } catch {
    throw new RemoteHostError('无法打开远程主机存储。');
  }
}

async function writeProfiles(store: preferences.Preferences, profiles: HostProfile[], previous: HostProfile[]): Promise<void> {
  try {
    store.putSync(KEY, JSON.stringify(profiles));
    await store.flush();
  } catch {
    // Restore the in-memory preference after a failed write.
    try {
      store.putSync(KEY, JSON.stringify(previous));
      await store.flush();
    } catch {}
    throw new RemoteHostError('无法更新远程主机列表，请重试。');
  }
}

async function writeHostChange(store: preferences.Preferences, previous: HostProfile[], next: HostProfile[],
  changeCredential: () => Promise<void>): Promise<void> {
  // Commit metadata before any operation that could destroy the old credential.
  await writeProfiles(store, next, previous);
  try {
    await changeCredential();
  } catch (error) {
    await writeProfiles(store, previous, next);
    if (error instanceof RemoteHostError) throw error;
    throw new RemoteHostError('无法更新主机凭据，请重试。');
  }
}

function assetQuery(id: string): asset.AssetMap {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, util.TextEncoder.create('utf-8').encodeInto(ALIAS_PREFIX + id));
  return query;
}

function assetError(error: Object, message: string): RemoteHostError {
  const code = (error as BusinessError).code;
  return new RemoteHostError(code === asset.ErrorCode.STATUS_MISMATCH || code === asset.ErrorCode.ACCESS_DENIED ?
    '无法访问已保存的主机凭据，请解锁手机后重试。' : message);
}

async function credentialRows(id: string, returnType: asset.ReturnType): Promise<asset.AssetMap[]> {
  const query = assetQuery(id);
  query.set(asset.Tag.RETURN_TYPE, returnType);
  try {
    return await asset.query(query);
  } catch (error) {
    if ((error as BusinessError).code === asset.ErrorCode.NOT_FOUND) return [];
    throw assetError(error as Object, '无法读取已保存的主机凭据，请重试。');
  }
}

function encodeCredential(address: HostAddress): Uint8Array {
  const value: WireObject = { 'launchUrl': address.launchUrl, 'authorization': address.authorization };
  const secret = util.TextEncoder.create('utf-8').encodeInto(JSON.stringify(value));
  if (secret.length > MAX_ASSET_BYTES) {
    secret.fill(0);
    throw new RemoteHostError('凭据超过安全存储的大小限制。取消勾选后仍可连接。');
  }
  return secret;
}

async function saveCredential(id: string, secret: Uint8Array): Promise<void> {
  const attrs = assetQuery(id);
  attrs.set(asset.Tag.SECRET, secret);
  attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
  attrs.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
  attrs.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
  try {
    await asset.add(attrs);
  } catch (error) {
    throw assetError(error as Object, '无法保存主机凭据，请重试。');
  } finally {
    secret.fill(0);
  }
}

async function removeCredential(id: string): Promise<void> {
  try {
    await asset.remove(assetQuery(id));
  } catch (error) {
    if ((error as BusinessError).code !== asset.ErrorCode.NOT_FOUND) {
      throw assetError(error as Object, '无法删除已保存的主机凭据，请重试。');
    }
  }
}

function publicHost(profile: HostProfile, hasCredential: boolean): RemoteHost {
  return { id: profile.id, name: profile.name, origin: profile.origin, hasCredential: hasCredential };
}

export async function listRemoteHosts(context: common.Context): Promise<RemoteHost[]> {
  const profiles = readProfiles(await hostPreferences(context));
  return Promise.all(profiles.map(async (profile: HostProfile): Promise<RemoteHost> =>
    publicHost(profile, (await credentialRows(profile.id, asset.ReturnType.ATTRIBUTES)).length > 0)));
}

export async function getRemoteHostConnection(host: RemoteHost): Promise<RemoteHostConnection | undefined> {
  if (!UUID.test(host.id)) return undefined;
  const rows = await credentialRows(host.id, asset.ReturnType.ALL);
  if (!rows.length) return undefined;
  const secret = rows[0].get(asset.Tag.SECRET);
  if (!(secret instanceof Uint8Array)) throw new RemoteHostError('已保存的主机凭据无法读取，请重新输入。');
  try {
    const value = object(JSON.parse(util.TextDecoder.create('utf-8').decodeToString(secret)) as Object);
    const address = parseCredentials(string(value['launchUrl']), string(value['authorization']));
    if (address.origin !== host.origin) throw new Error();
    return { id: host.id, name: host.name, launchUrl: address.launchUrl, authorization: address.authorization };
  } catch {
    throw new RemoteHostError('已保存的主机凭据无法读取，请重新输入。');
  } finally {
    secret.fill(0);
  }
}

export function remoteHostConnection(host: RemoteHost, launchUrl: string, authorization: string): RemoteHostConnection {
  const address = parseCredentials(launchUrl, authorization);
  if (address.origin !== host.origin) throw new RemoteHostError('启动链接与保存的主机地址不同。');
  return { id: host.id, name: host.name, launchUrl: address.launchUrl, authorization: address.authorization };
}

// Preferences transactions within this application must not interleave.
let mutation: Promise<void> = Promise.resolve();
function changeHosts<T>(work: () => Promise<T>): Promise<T> {
  const next = mutation.then(work);
  mutation = next.then(() => {}, () => {});
  return next;
}

export function saveRemoteHost(context: common.Context, draft: RemoteHostDraft): Promise<RemoteHost> {
  return changeHosts(async (): Promise<RemoteHost> => {
    const store = await hostPreferences(context);
    const profiles = readProfiles(store);
    const index = profiles.findIndex((item: HostProfile) => item.id === draft.id);
    const previous = profiles[index];
    if (draft.id && !previous) throw new RemoteHostError('找不到这台主机，请重新打开列表。');
    if (!draft.launchUrl.trim() && draft.authorization) throw new RemoteHostError('更换授权时请同时输入启动链接。');
    const address = draft.launchUrl.trim() || !previous ? parseCredentials(draft.launchUrl, draft.authorization) : undefined;
    const origin = address?.origin || previous.origin;
    if (profiles.some((item: HostProfile) => item.origin === origin && item.id !== draft.id)) {
      throw new RemoteHostError('这台主机已在列表中，请编辑现有主机。');
    }
    const saved = !address && previous && draft.name.trim() !== previous.name ?
      await getRemoteHostConnection(publicHost(previous, true)) : undefined;
    const name = profileName(draft.name, origin, address ||
      (saved ? parseCredentials(saved.launchUrl, saved.authorization) : undefined));
    const profile: HostProfile = { id: previous?.id || util.generateRandomUUID(), name: name, origin: origin };
    const next = profiles.slice();
    if (previous) next[index] = profile;
    else next.push(profile);

    const secret = draft.remember && address ? encodeCredential(address) : undefined;
    try {
      const hasCredential = secret !== undefined || (draft.remember && !address &&
        (await credentialRows(profile.id, asset.ReturnType.ATTRIBUTES)).length > 0);
      await writeHostChange(store, profiles, next, async () => {
        if (secret) await saveCredential(profile.id, secret);
        else if (!draft.remember && previous) await removeCredential(profile.id);
      });
      return publicHost(profile, hasCredential);
    } finally {
      secret?.fill(0);
    }
  });
}

export function deleteRemoteHost(context: common.Context, id: string): Promise<void> {
  return changeHosts(async (): Promise<void> => {
    const store = await hostPreferences(context);
    const profiles = readProfiles(store);
    const next = profiles.filter((item: HostProfile) => item.id !== id);
    if (next.length === profiles.length) return;
    await writeHostChange(store, profiles, next, () => removeCredential(id));
  });
}
