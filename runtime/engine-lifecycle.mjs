import { constants, openSync, closeSync, readFileSync, writeFileSync, renameSync, mkdirSync,
  statSync, fstatSync, existsSync, appendFileSync } from 'node:fs';
import { join } from 'node:path';

export const HEALTHY_MS = 120000;
export function redactEngineLog(value) {
  return String(value).replace(/\x1b\[[0-9;]*[A-Za-z]/g, '')
    .replace(/(Bearer\s+)[A-Za-z0-9._~+\/-]+/gi, '$1[redacted]')
    .replace(/([?&](?:token|key|secret|password|authorization)=)[^\s&#"']+/gi, '$1[redacted]')
    .replace(/((?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|secret|authorization)["']?\s*[:=]\s*["']?)[^\s,"'}]+/gi, '$1[redacted]')
    .replace(/\bsk-[A-Za-z0-9_-]{8,}/g, '[redacted]')
    .replace(/(https?:\/\/)[^/\s:@]+:[^/\s@]+@/gi, '$1[redacted]@');
}
function readJson(path) {
  let fd;
  try {
    fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
    const info = fstatSync(fd);
    if (!info.isFile() || info.size > 32768) throw new Error('Invalid runtime state file');
    return JSON.parse(readFileSync(fd, 'utf8'));
  } catch (error) { if (error.code === 'ENOENT') return undefined; throw error; }
  finally { if (fd !== undefined) closeSync(fd); }
}
function writeJson(path, value) {
  writeFileSync(path + '.tmp', JSON.stringify(value), { mode: 0o600,
    flag: constants.O_CREAT | constants.O_WRONLY | constants.O_TRUNC | constants.O_NOFOLLOW });
  renameSync(path + '.tmp', path);
}
export class EngineLifecycle {
  constructor(root, { now = Date.now } = {}) {
    this.root = root; this.now = now; this.path = join(root, 'runtime-state.json');
    this.logPath = join(root, 'runtime.log'); this.normalProfile = join(root, 'profile', 'cordis.patch.yml');
    mkdirSync(root, { recursive: true, mode: 0o700 });
    const prior = readJson(this.path) ?? {};
    this.state = { version: 1, safeState: ['off', 'on', 'probation'].includes(prior.safeState) ? prior.safeState : 'off',
      autoSafe: prior.autoSafe !== false, strikes: Number.isInteger(prior.strikes) ? Math.max(0, Math.min(1000, prior.strikes)) : 0,
      safeReason: typeof prior.safeReason === 'string' ? prior.safeReason : '',
      appliedRequestId: typeof prior.appliedRequestId === 'string' ? prior.appliedRequestId : '',
      failure: prior.failure, healthyAt: prior.healthyAt, phase: 'stopped', nodeVersion: process.versions.node, dshVersion: '0.2.2-rc.1' };
    if (['starting', 'running'].includes(prior.phase)) this.state.failure = { kind: 'killed', at: now(), summary: '上次本机进程未正常退出' };
    const command = readJson(join(root, 'runtime-command.json'));
    if (command && typeof command.requestId === 'string' && /^[a-f0-9-]{36}$/i.test(command.requestId) && command.requestId !== this.state.appliedRequestId) {
      if (command.mode === 'safe') { this.state.safeState = 'on'; this.state.safeReason = 'manual'; }
      if (command.mode === 'normal' && this.state.safeState === 'on') this.state.safeState = 'probation';
      if (typeof command.autoSafe === 'boolean') this.state.autoSafe = command.autoSafe;
      this.state.appliedRequestId = command.requestId;
    }
    this.safe = this.state.safeState === 'on';
    this.state.mode = this.safe ? 'safe' : 'normal';
    this.state.phase = 'starting'; this.state.startedAt = now(); this.state.readyAt = 0;
    this.save(); this.log(`启动本机引擎，模式：${this.state.mode}`);
  }
  save() { writeJson(this.path, this.state); }
  log(message) {
    const lines = redactEngineLog(message).split(/\r?\n/).filter(Boolean).slice(0, 40);
    if (!lines.length) return;
    try {
      if (existsSync(this.logPath) && statSync(this.logPath).size > 512 * 1024) renameSync(this.logPath, this.logPath + '.1');
      appendFileSync(this.logPath, lines.map(line => `${new Date(this.now()).toISOString()} ${line.slice(0, 2048)}\n`).join(''),
        { mode: 0o600, flag: constants.O_APPEND | constants.O_CREAT | constants.O_WRONLY | constants.O_NOFOLLOW });
    } catch { /* A full disk must not prevent the engine from reporting its failure. */ }
  }
  ready() {
    // Upstream clears the previous failure once listening; strikes wait for healthy().
    delete this.state.failure;
    this.state.phase = 'running'; this.state.readyAt = this.now(); this.save(); this.log('本机引擎已就绪');
    this.timer = setTimeout(() => this.healthy(), HEALTHY_MS); this.timer.unref();
  }
  healthy() {
    if (this.safe || this.state.phase !== 'running') return;
    this.state.strikes = 0; this.state.safeState = 'off'; this.state.safeReason = ''; this.state.healthyAt = this.now();
    try {
      const profile = readFileSync(this.normalProfile);
      if (profile.length > 1024 * 1024) throw new Error('Profile too large');
      const path = join(this.root, 'profile', 'cordis.good.patch.yml');
      writeFileSync(path + '.tmp', profile, { mode: 0o600 }); renameSync(path + '.tmp', path);
      this.state.goodProfileAvailable = true;
    } catch { this.state.goodProfileAvailable = false; }
    this.save(); this.log('正常模式连续运行两分钟，已记录正常配置');
  }
  failed(error) {
    clearTimeout(this.timer);
    const uptime = this.state.readyAt ? this.now() - this.state.readyAt : 0;
    const kind = error?.code === 'ENOSPC' ? 'noSpace' : !this.state.readyAt ? 'startupFailed' : uptime < HEALTHY_MS ? 'crashedEarly' : 'crashedLate';
    this.state.failure = { kind, at: this.now(), upSeconds: Math.floor(uptime / 1000),
      summary: redactEngineLog(error?.message ?? '本机引擎运行失败').slice(0, 2048), safeMode: this.safe };
    if (!this.safe && ['startupFailed', 'crashedEarly'].includes(kind)) {
      this.state.strikes++;
      if (this.state.safeState === 'probation' || (this.state.autoSafe && this.state.strikes >= 2)) {
        this.state.safeReason = this.state.safeState === 'probation' ? 'probation' : 'auto';
        this.state.safeState = 'on'; this.state.restartSafe = true;
      }
    }
    this.state.phase = 'error'; this.save(); this.log(`${kind}: ${this.state.failure.summary}`);
  }
  stopped() { clearTimeout(this.timer); this.state.phase = 'stopped'; this.save(); this.log('本机引擎已停止'); }
}
