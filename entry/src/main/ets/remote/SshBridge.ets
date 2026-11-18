import { util } from '@kit.ArkTS';
import { rcp } from '@kit.RemoteCommunicationKit';
import { object, string, WireObject } from '../dsh/DshWire';
import { TransportControl, TransportEndpoint } from './TransportEndpoint';
import { SshHost } from './SshHosts';

const LOOPBACK = /^http:\/\/127\.0\.0\.1:([1-9]\d{0,4})$/;
const LAUNCH_URL = /^http:\/\/127\.0\.0\.1:([1-9]\d{0,4})\/\?token=[A-Za-z0-9%._~=-]{1,512}$/;
const BEARER = /^Bearer [A-Za-z0-9_-]{43}$/;
export const SSH_FINGERPRINT = /^SHA256:[A-Za-z0-9+/]{43}$/;

export class SshBridgeError extends Error {
  readonly code: string;
  readonly fingerprint: string;

  constructor(code: string, fingerprint: string = '') {
    super(sshErrorText(code));
    this.code = code;
    this.fingerprint = fingerprint;
  }
}

function sshErrorText(code: string): string {
  switch (code) {
    case 'host-key-mismatch': return 'SSH 主机指纹已变化，连接已拒绝。请向主机管理员核实新指纹。';
    case 'host-key-required': return '请核对并确认这台 SSH 主机的指纹。';
    case 'auth-failed': return 'SSH 登录失败，请检查用户名和认证凭据。';
    case 'key-invalid': return '无法读取 SSH 私钥，请检查私钥格式和口令。';
    case 'no-dsh': return '远程主机找不到 dsh。请先安装 DSH 或填写启动命令。';
    case 'bad-directory': return '无法打开远程工作目录，请检查路径。';
    case 'busy': return '远程 DSH 正在启动，请稍后再试。';
    case 'exited': return '远程 DSH 启动后退出，请在主机上检查启动命令。';
    case 'timeout': return '等待远程 DSH 启动超时。';
    case 'launch-invalid': return '远程 DSH 未返回有效的回环启动链接。';
    case 'forward-failed': return '无法转发远程 DSH 端口，请检查 SSH 服务器是否允许 TCP 转发。';
    case 'state-error': return '无法在远程主机保存 DSH 启动状态。';
    case 'shell-failed': return '无法在远程主机运行启动命令。';
    case 'cancelled': return '已取消 SSH 连接。';
    default: return '无法连接 SSH 主机，请检查地址、网络和服务状态。';
  }
}

export class SshBridge {
  private readonly id: string = util.generateRandomUUID();
  private readonly control: TransportControl;
  private cancelled: boolean = false;

  constructor(control: TransportControl) {
    this.control = control;
  }

  private async post(path: string, value: WireObject, timeout: number): Promise<WireObject> {
    const match = LOOPBACK.exec(this.control.url);
    if (!match || Number(match[1]) > 65535 || !BEARER.test(this.control.authorization)) {
      throw new SshBridgeError('invalid-control');
    }
    const session = rcp.createSession({ requestConfiguration: {
      proxy: 'no-proxy', transfer: { autoRedirect: false, timeout: { connectMs: 3000, transferMs: timeout } }
    } });
    try {
      const request = new rcp.Request(this.control.url + path, 'POST',
        { authorization: this.control.authorization, 'content-type': 'application/json' }, JSON.stringify(value));
      const response = await session.fetch(request);
      if (response.statusCode !== 200 || !response.body || response.body.byteLength > 4096) throw new Error();
      return object(JSON.parse(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(response.body))));
    } catch {
      throw new SshBridgeError('connect-failed');
    } finally {
      session.close();
    }
  }

  async connect(host: SshHost, secret: string, passphrase: string): Promise<TransportEndpoint> {
    if (this.cancelled) throw new SshBridgeError('cancelled');
    const value: WireObject = { 'id': this.id, 'host': host.host, 'port': host.port, 'user': host.user, 'auth': host.auth,
      'secret': secret, 'passphrase': passphrase, 'fingerprint': host.fingerprint, 'command': host.command,
      'directory': host.directory };
    const result = await this.post('/ssh/connect', value, 82000);
    if (this.cancelled) {
      await this.close();
      throw new SshBridgeError('cancelled');
    }
    const code = string(result['code']);
    const fingerprint = string(result['fingerprint']);
    if (code) throw new SshBridgeError(code, SSH_FINGERPRINT.test(fingerprint) ? fingerprint : '');
    const launchUrl = string(result['launchUrl']);
    const authorization = string(result['authorization']);
    const match = LAUNCH_URL.exec(launchUrl);
    if (!match || Number(match[1]) > 65535 || !BEARER.test(authorization)) {
      await this.close();
      throw new SshBridgeError('invalid-control');
    }
    return { launchUrl: launchUrl, authorization: authorization, name: host.name, scope: `ssh:${host.id}`,
      close: (): Promise<void> => this.close() };
  }

  async close(): Promise<void> {
    this.cancelled = true;
    await this.post('/ssh/close', { 'id': this.id }, 5000).catch(() => {});
  }
}
