import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import legacyFileIo from '@ohos.fileio';
import { util } from '@kit.ArkTS';
import { object } from '../dsh/DshWire';
import type { WireObject } from '../dsh/DshWire';
export function phoneBridgeRoot(context: common.Context): string { return context.filesDir + '/phone-control'; }
export async function phoneWriteFile(path: string, value: WireObject): Promise<void> {
  const stage = path + '.' + util.generateRandomUUID() + '.tmp', bytes = util.TextEncoder.create('utf-8').encodeInto(JSON.stringify(value));
  const file = await fs.open(stage, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY | fs.OpenMode.NOFOLLOW);
  try { await legacyFileIo.fchmod(file.fd, 0o600); if (await fs.write(file.fd, bytes.buffer) !== bytes.byteLength) throw new Error('手机操作写入不完整'); }
  finally { await fs.close(file); }
  try { await fs.rename(stage, path); } finally { if (await fs.access(stage)) await fs.unlink(stage); }
}
export async function phoneReadFile(path: string, limit: number = 262144): Promise<WireObject | undefined> {
  if (!await fs.access(path)) return undefined;
  const info = await fs.lstat(path);
  if (!info.isFile() || info.isSymbolicLink() || info.size > limit) throw new Error('手机操作文件无效');
  return object(JSON.parse(await fs.readText(path, { length: limit })));
}
export async function phoneRemoveFile(path: string): Promise<void> { if (await fs.access(path)) await fs.unlink(path); }
