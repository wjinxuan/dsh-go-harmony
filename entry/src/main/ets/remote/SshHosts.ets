import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { array, number, object, string } from '../dsh/DshWire';

export interface SshHost {
  id: string;
  name: string;
  host: string;
  port: number;
  user: string;
  auth: 'password' | 'key';
  fingerprint: string;
  command: string;
  directory: string;
}

const STORE = 'dsh-ssh-hosts';
const KEY = 'hosts-v1';
const UUID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
const HOST = /^(?:[A-Za-z0-9][A-Za-z0-9._:-]*|::[0-9A-Fa-f:.]*)$/;
const CONTROL = /[\x00-\x1f\x7f]/;

export function validateSshHost(host: SshHost): void {
  if (!UUID.test(host.id) || !host.name || host.name.length > 64 || CONTROL.test(host.name) ||
      !HOST.test(host.host) || host.host.length > 253 || !Number.isInteger(host.port) || host.port < 1 || host.port > 65535 ||
      !host.user || host.user.length > 128 || CONTROL.test(host.user) || !host.command || host.command.length > 2048 ||
      CONTROL.test(host.command) || host.directory.length > 2048 || CONTROL.test(host.directory) ||
      (host.auth !== 'password' && host.auth !== 'key') ||
      (host.fingerprint && !/^SHA256:[A-Za-z0-9+/]{43}$/.test(host.fingerprint))) {
    throw new Error('请检查 SSH 地址、端口、用户名和远程启动设置。');
  }
}

function readHosts(store: preferences.Preferences): SshHost[] {
  try {
    const value: Object = JSON.parse(store.getSync(KEY, '[]') as string) as Object;
    if (!Array.isArray(value)) throw new Error();
    return array(value).map((item: Object): SshHost => {
      const row = object(item);
      const auth = string(row['auth']);
      if (auth !== 'password' && auth !== 'key') throw new Error();
      const host: SshHost = { id: string(row['id']), name: string(row['name']), host: string(row['host']),
        port: number(row['port'], 0), user: string(row['user']), auth: auth,
        fingerprint: string(row['fingerprint']), command: string(row['command']), directory: string(row['directory']) };
      validateSshHost(host);
      return host;
    });
  } catch { throw new Error('无法读取已保存的 SSH 主机。'); }
}

export async function listSshHosts(context: common.Context): Promise<SshHost[]> {
  return readHosts(await preferences.getPreferences(context, STORE));
}

let mutation: Promise<void> = Promise.resolve();

export function updateSshHosts(context: common.Context, id: string, host?: SshHost): Promise<SshHost[]> {
  const task = mutation.then(async (): Promise<SshHost[]> => {
    if (host) validateSshHost(host);
    const store = await preferences.getPreferences(context, STORE);
    const previous = readHosts(store);
    const next = previous.filter((item: SshHost) => item.id !== id);
    if (host) next.push(host);
    try {
      store.putSync(KEY, JSON.stringify(next));
      await store.flush();
      return next;
    } catch {
      store.putSync(KEY, JSON.stringify(previous));
      throw new Error('无法保存 SSH 主机，请重试。');
    }
  });
  mutation = task.then(() => {}, () => {});
  return task;
}
