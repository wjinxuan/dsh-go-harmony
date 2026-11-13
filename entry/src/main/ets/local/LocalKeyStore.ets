import { util } from '@kit.ArkTS';
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { normalizeProviderKey } from '../dsh/DshWire';

const KEY_ALIAS: string = 'dsh-go.local.deepseek-api-key.v1';
const MAX_KEY_BYTES: number = 1024;

function queryByAlias(): asset.AssetMap {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, util.TextEncoder.create('utf-8').encodeInto(KEY_ALIAS));
  return query;
}

function missing(error: Object): boolean {
  return (error as BusinessError).code === asset.ErrorCode.NOT_FOUND;
}

function storageError(error: Object, message: string): Error {
  const code = (error as BusinessError).code;
  return new Error(code === asset.ErrorCode.STATUS_MISMATCH || code === asset.ErrorCode.ACCESS_DENIED ?
    '无法访问已保存的 API Key。请解锁手机后重试。' : message);
}

export async function hasLocalApiKey(): Promise<boolean> {
  const query = queryByAlias();
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ATTRIBUTES);
  try {
    return (await asset.query(query)).length > 0;
  } catch (error) {
    if (missing(error as Object)) {
      return false;
    }
    throw storageError(error as Object, '无法检查已保存的 API Key，请重试。');
  }
}

export async function loadLocalApiKey(): Promise<string | undefined> {
  const query = queryByAlias();
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
  let rows: asset.AssetMap[];
  try {
    rows = await asset.query(query);
  } catch (error) {
    if (missing(error as Object)) {
      return undefined;
    }
    throw storageError(error as Object, '无法读取已保存的 API Key，请重试或重新输入。');
  }
  if (!rows.length) {
    return undefined;
  }
  const secret = rows[0].get(asset.Tag.SECRET);
  if (!(secret instanceof Uint8Array)) {
    throw new Error('已保存的 API Key 无法读取，请重新输入。');
  }
  try {
    return normalizeProviderKey(util.TextDecoder.create('utf-8').decodeToString(secret));
  } catch {
    throw new Error('已保存的 API Key 无法读取，请重新输入。');
  } finally {
    secret.fill(0);
  }
}

export async function saveLocalApiKey(key: string): Promise<void> {
  const secret = util.TextEncoder.create('utf-8').encodeInto(normalizeProviderKey(key));
  try {
    if (secret.length > MAX_KEY_BYTES) {
      throw new Error('API Key 太长，无法保存。');
    }
    const attributes = queryByAlias();
    attributes.set(asset.Tag.SECRET, secret);
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
    attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    try {
      await asset.add(attributes);
    } catch (error) {
      throw storageError(error as Object, '无法保存 API Key，请重试。');
    }
  } finally {
    secret.fill(0);
  }
}

export async function removeLocalApiKey(): Promise<void> {
  try {
    await asset.remove(queryByAlias());
  } catch (error) {
    if (!missing(error as Object)) {
      throw storageError(error as Object, '无法移除已保存的 API Key，请重试。');
    }
  }
}
