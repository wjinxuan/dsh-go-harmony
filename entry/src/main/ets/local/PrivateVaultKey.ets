import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
function queryFor(name: string): asset.AssetMap {
  if (!/^[a-z][a-z0-9-]{0,48}$/.test(name)) throw new Error('安全存储名称无效');
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, util.TextEncoder.create('utf-8').encodeInto('dsh-go.vault.v1.' + name));
  return query;
}
async function read(name: string): Promise<string | undefined> {
  const query = queryFor(name); query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
  let rows: asset.AssetMap[];
  try { rows = await asset.query(query); }
  catch (error) { if ((error as BusinessError).code === asset.ErrorCode.NOT_FOUND) return undefined; throw new Error('请解锁手机后访问安全存储'); }
  if (rows.length !== 1) throw new Error('安全存储中的密钥不完整');
  const secret = rows[0].get(asset.Tag.SECRET);
  if (!(secret instanceof Uint8Array) || secret.length !== 32) throw new Error('安全存储中的密钥无效');
  try { return new util.Base64Helper().encodeToStringSync(secret).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); }
  finally { secret.fill(0); }
}
export async function privateVaultKey(name: string): Promise<string> {
  const existing = await read(name); if (existing) return existing;
  const generated = await cryptoFramework.createRandom().generateRandom(32);
  const attrs = queryFor(name); attrs.set(asset.Tag.SECRET, generated.data);
  attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
  attrs.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
  attrs.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.THROW_ERROR);
  try { await asset.add(attrs); }
  catch (error) { if ((error as BusinessError).code !== asset.ErrorCode.DUPLICATED) throw new Error('安全密钥未能保存，请解锁后重试'); }
  finally { generated.data.fill(0); }
  const saved = await read(name); if (!saved) throw new Error('安全密钥未能读取'); return saved;
}
