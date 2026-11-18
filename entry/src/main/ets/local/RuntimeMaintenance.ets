import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import legacyFileIo from '@ohos.fileio';
import { object, string, number } from '../dsh/DshWire';

export interface RuntimeMaintenanceState {
  phase: string;
  mode: string;
  safeState: string;
  autoSafe: boolean;
  strikes: number;
  nodeVersion: string;
  dshVersion: string;
  runtimeVersion: string;
  failure: string;
  goodProfileAvailable: boolean;
}
export function emptyRuntimeMaintenanceState(): RuntimeMaintenanceState {
  return { phase: 'stopped', mode: 'normal', safeState: 'off', autoSafe: true, strikes: 0,
    nodeVersion: '', dshVersion: '', runtimeVersion: '', failure: '', goodProfileAvailable: false };
}
const root = (context: common.UIAbilityContext): string => context.filesDir + '/dsh-local-data';
async function regularFile(path: string, limit: number): Promise<boolean> {
  if (!await fs.access(path)) return false;
  const info = await fs.lstat(path);
  if (!info.isFile() || info.isSymbolicLink() || info.size > limit) throw new Error('本机维护文件无效');
  return true;
}
export async function readRuntimeMaintenance(context: common.UIAbilityContext): Promise<RuntimeMaintenanceState> {
  const path = root(context) + '/runtime-state.json';
  if (!await regularFile(path, 32768)) return emptyRuntimeMaintenanceState();
  const value = object(JSON.parse(await fs.readText(path, { length: 32768 })));
  const failure = object(value['failure']);
  const state: RuntimeMaintenanceState = { phase: string(value['phase']), mode: string(value['mode']), safeState: string(value['safeState']),
    autoSafe: value['autoSafe'] !== false, strikes: number(value['strikes'], 0), nodeVersion: string(value['nodeVersion']),
    dshVersion: string(value['dshVersion']), runtimeVersion: string(value['runtimeVersion']), failure: string(failure['summary']),
    goodProfileAvailable: await regularFile(root(context) + '/profile/cordis.good.patch.yml', 1024 * 1024) };
  return state;
}
async function writeAtomic(path: string, text: string): Promise<void> {
  const staged = path + '.' + util.generateRandomUUID() + '.tmp';
  const data = util.TextEncoder.create('utf-8').encodeInto(text);
  const file = await fs.open(staged, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.NOFOLLOW | fs.OpenMode.WRITE_ONLY);
  try {
    await legacyFileIo.fchmod(file.fd, 0o600);
    if (await fs.write(file.fd, data.buffer) !== data.byteLength) throw new Error('维护设置写入不完整');
    await fs.fsync(file.fd);
  } finally { await fs.close(file); }
  try { await fs.rename(staged, path); }
  finally { if (await fs.access(staged)) await fs.unlink(staged); }
}
export async function requestRuntimeMode(context: common.UIAbilityContext, mode: string, autoSafe: boolean): Promise<void> {
  if (!['safe', 'normal', ''].includes(mode)) throw new Error('无效的引擎模式');
  if (!await fs.access(root(context))) await fs.mkdir(root(context));
  await writeAtomic(root(context) + '/runtime-command.json', JSON.stringify({ requestId: util.generateRandomUUID(), mode: mode, autoSafe: autoSafe }));
}
export async function readRuntimeLog(context: common.UIAbilityContext): Promise<string> {
  const path = root(context) + '/runtime.log';
  if (!await regularFile(path, 1024 * 1024)) return '暂无本机引擎日志。';
  const text = await fs.readText(path, { length: 1024 * 1024 });
  return text.split('\n').slice(-300).join('\n');
}
export async function restoreGoodRuntimeProfile(context: common.UIAbilityContext): Promise<void> {
  const native = (await import('libdshlocal.so')).default;
  if (native.status() === -1) throw new Error('请先停止本机引擎');
  const profile = root(context) + '/profile';
  const good = profile + '/cordis.good.patch.yml';
  if (!await regularFile(good, 1024 * 1024)) throw new Error('还没有上次正常配置');
  const current = profile + '/cordis.patch.yml';
  if (await regularFile(current, 1024 * 1024)) await writeAtomic(current + '.before-restore-' + util.generateRandomUUID(),
    await fs.readText(current, { length: 1024 * 1024 }));
  await writeAtomic(current, await fs.readText(good, { length: 1024 * 1024 }));
  await requestRuntimeMode(context, 'normal', true);
}
export async function probeRuntimeShell(): Promise<string> {
  const native = (await import('libdshlocal.so')).default;
  const result = object(JSON.parse(await native.probeShell()));
  if (result['handshake'] === true) return '本机系统 Shell 与 PTY 握手成功。交互终端仍需设备端进一步验证。';
  if (result['timedOut'] === true) return '本机 Shell 检查超时，测试进程已终止。';
  const pty = number(result['ptyError'], 0), spawn = number(result['spawnError'], 0);
  return pty ? `系统拒绝或无法打开 PTY（${pty}）。` : spawn ? `普通应用无法启动系统 Shell（${spawn}）。` : '系统 Shell 未完成 PTY 握手。';
}

export async function requestRuntimeReset(context: common.UIAbilityContext, uiAndSkills: boolean, pluginsAndSettings: boolean): Promise<void> {
  const native = (await import('libdshlocal.so')).default;
  if (native.status() === -1) throw new Error('请先停止本机引擎');
  await writeAtomic(root(context) + '.reset-request', JSON.stringify({ version: 1, uiAndSkills: uiAndSkills, pluginsAndSettings: pluginsAndSettings }));
}
