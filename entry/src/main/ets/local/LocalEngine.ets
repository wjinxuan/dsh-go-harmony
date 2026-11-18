import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { zlib } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import type { TransportControl } from '../remote/TransportEndpoint';
import { privateVaultKey } from './PrivateVaultKey';

const ARCHIVE: string = 'dsh-runtime.zip';

interface NativeLocalEngine {
  start(script: string, dataDir: string): number;
  status(): number;
  stop(): number;
}

interface CredentialUnlockRequest { masterKey: string; }
interface CredentialUnlockResult { unlocked: boolean; }

export interface LocalEndpoint {
  url: string;
  workspaceDir: string;
  runtimeVersion?: string;
  transportControl?: TransportControl;
}

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => { setTimeout(resolve, ms); });
}

export async function bundledRuntimeVersion(context: common.UIAbilityContext): Promise<string> {
  const version = util.TextDecoder.create('utf-8').decodeToString(
    await context.resourceManager.getRawFileContent('dsh-runtime-version.txt')).trim();
  if (!/^[a-f0-9]{64}$/.test(version)) throw new Error('运行时版本清单无效');
  return version;
}

export class LocalEngine {
  private dataDir: string = '';
  private engine?: NativeLocalEngine;

  async start(context: common.UIAbilityContext, onStage: (message: string) => void): Promise<LocalEndpoint> {
    if (!this.engine) {
      try {
        this.engine = (await import('libdshlocal.so')).default;
      } catch {
        throw new Error('手机未能加载本机引擎的原生运行时');
      }
    }
    const engine = this.engine;
    this.dataDir = context.filesDir + '/dsh-local-data';
    if (!await fs.access(this.dataDir)) {
      await fs.mkdir(this.dataDir, true);
    }
    if (engine.status() !== -1) {
      onStage('正在准备本机运行时…');
      const script = await this.install(context);
      for (const name of ['ready.json', 'error.json', 'stop']) {
        await this.unlink(this.dataDir + '/' + name);
      }

      onStage('正在启动 DeepSeek Harness…');
      const status = engine.start(script, this.dataDir);
      if (status !== 0) {
        throw new Error(`本机运行时启动失败（${status}）`);
      }
    }

    for (let attempt = 0; attempt < 300; attempt++) {
      const status = engine.status();
      if (status !== -1 || await fs.access(this.dataDir + '/error.json')) {
        throw new Error(status > 0 ? `本机引擎已退出（${status}）` : '本机引擎未能启动');
      }
      const path = this.dataDir + '/ready.json';
      if (await fs.access(path)) {
        const endpoint = JSON.parse(await fs.readText(path, { length: 4096 })) as LocalEndpoint;
        if (!/^http:\/\/127\.0\.0\.1:[1-9]\d{0,4}\/\?token=[A-Za-z0-9%._~=-]+$/.test(endpoint?.url) ||
          endpoint.workspaceDir !== this.dataDir + '/workspace') {
          throw new Error('本机引擎返回了无效的连接信息');
        }
        const control = endpoint.transportControl;
        if (control && (!/^http:\/\/127\.0\.0\.1:[1-9]\d{0,4}$/.test(control.url) ||
          !/^Bearer [A-Za-z0-9_-]{43}$/.test(control.authorization))) {
          throw new Error('本机连接服务返回了无效的地址');
        }
        if (!control) throw new Error('本机连接服务返回了无效的地址');
        await this.unlockCredentials(control);
        return endpoint;
      }
      await delay(200);
    }
    throw new Error('等待本机引擎超时');
  }

  private async unlockCredentials(control: TransportControl): Promise<void> {
    const session = rcp.createSession({ requestConfiguration: { proxy: 'no-proxy', transfer: {
      autoRedirect: false, timeout: { connectMs: 5000, transferMs: 15000 }
    } } });
    try {
      const body: CredentialUnlockRequest = { masterKey: await privateVaultKey('credentials') };
      const response = await session.fetch(new rcp.Request(control.url + '/credentials/unlock', 'POST', {
        authorization: control.authorization, 'content-type': 'application/json'
      }, JSON.stringify(body)));
      if (response.statusCode !== 200 || !response.body || response.body.byteLength > 1024) throw new Error();
      const result = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(response.body))) as CredentialUnlockResult;
      if (result.unlocked !== true) throw new Error();
    } catch {
      throw new Error('渠道凭据未能解锁，请解锁手机后重试');
    } finally { session.close(); }
  }

  async stop(): Promise<void> {
    const engine = this.engine;
    if (!this.dataDir || !engine || engine.status() !== -1) {
      return;
    }
    try {
      const file = await fs.open(this.dataDir + '/stop', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      await fs.close(file);
      for (let attempt = 0; attempt < 50; attempt++) {
        if (engine.status() !== -1) {
          return;
        }
        await delay(100);
      }
    } finally {
      if (engine.status() === -1) {
        engine.stop();
      }
    }
    if (engine.status() === -1) {
      throw new Error('本机引擎正在退出，请稍后再试');
    }
  }

  private async install(context: common.UIAbilityContext): Promise<string> {
    const version = await bundledRuntimeVersion(context);
    const installed = context.filesDir + '/dsh-runtime-' + version;
    const script = installed + '/main.cjs';
    if (await fs.access(script)) {
      return script;
    }

    const stage = installed + '.stage';
    const zip = installed + '.zip';
    try {
      if (await fs.access(stage)) {
        await fs.rmdir(stage);
      }
      await fs.mkdir(stage);
      await this.copyRuntime(context, zip, version);
      await zlib.decompressFile(zip, stage);
      if (!await fs.access(stage + '/main.cjs')) {
        throw new Error('运行时缺少入口文件');
      }
      await fs.rename(stage, installed);
      return script;
    } finally {
      await this.unlink(zip);
      if (await fs.access(stage)) {
        await fs.rmdir(stage);
      }
    }
  }

  private async copyRuntime(context: common.UIAbilityContext, path: string, expected: string): Promise<void> {
    const resources = context.resourceManager;
    const raw = await resources.getRawFd(ARCHIVE);
    const digest = cryptoFramework.createMd('SHA256');
    try {
      const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        const buffer = new ArrayBuffer(1024 * 1024);
        let copied = 0;
        while (copied < raw.length) {
          fs.lseek(raw.fd, raw.offset + copied);
          const length = Math.min(buffer.byteLength, raw.length - copied);
          const received = await fs.read(raw.fd, buffer, { length: length });
          if (received <= 0 || await fs.write(file.fd, buffer, { length: received }) !== received) {
            throw new Error('写入运行时压缩包不完整');
          }
          await digest.update({ data: new Uint8Array(buffer, 0, received) });
          copied += received;
        }
        const checksum = await digest.digest();
        let actual = '';
        for (const byte of checksum.data) actual += byte.toString(16).padStart(2, '0');
        if (actual !== expected) throw new Error('运行时压缩包未通过完整性校验');
      } finally {
        await fs.close(file);
      }
    } finally {
      await resources.closeRawFd(ARCHIVE);
    }
  }

  private async unlink(path: string): Promise<void> {
    if (await fs.access(path)) {
      await fs.unlink(path);
    }
  }
}
