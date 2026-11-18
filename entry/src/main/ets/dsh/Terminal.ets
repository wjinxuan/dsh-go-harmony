import type { DshClient, DshDuplexStream, DshSubscription } from './DshClient';
import { array, number, object, string } from './DshWire';
import type { WireObject } from './DshWire';

export interface TerminalShell { path: string; name: string; }
export interface TerminalInfo {
  id: string;
  title: string;
  shell: TerminalShell;
  cwd: string;
  cols: number;
  rows: number;
  state: string;
  exitCode?: number;
}
export interface TerminalEnvironment {
  cwd: string;
  maxCols: number;
  maxRows: number;
  maxInputBytes: number;
  maxBufferedBytes: number;
}
export interface TerminalFrame {
  type: string;
  info?: TerminalInfo;
  screen?: string;
  data?: string;
  writable?: boolean;
}

function limit(value: Object | null | undefined, fallback: number): number {
  const n = number(value, fallback);
  return Number.isSafeInteger(n) && n > 0 ? n : fallback;
}

function terminalShell(value: Object | null | undefined): TerminalShell | undefined {
  const item = object(value);
  const path = string(item['path']);
  return path ? { path: path, name: string(item['name']) || path.split('/').pop() || path } : undefined;
}

function terminalInfo(value: Object | null | undefined): TerminalInfo | undefined {
  const item = object(value);
  const id = string(item['id']);
  if (!/^[\w-]{1,128}$/.test(id)) return undefined;
  const shell = terminalShell(item['shell']) ?? { name: 'Shell', path: '' };
  const exitCode = item['exitCode'];
  return { id: id, title: string(item['title']) || shell.name, shell: shell, cwd: string(item['cwd']),
    cols: limit(item['cols'], 80), rows: limit(item['rows'], 24), state: string(item['state']),
    exitCode: typeof exitCode === 'number' ? exitCode : undefined };
}

export class TerminalApi {
  private client: DshClient;
  private sessionId: string;

  constructor(client: DshClient, sessionId: string) { this.client = client; this.sessionId = sessionId; }

  private target(id?: string): WireObject {
    const args: WireObject = {};
    args['agentId'] = this.sessionId;
    args['id'] = id;
    return args;
  }

  async environment(): Promise<TerminalEnvironment> {
    const value = object(await this.client.request('terminal/environment', this.target()));
    if (typeof value['cwd'] !== 'string') throw new Error('主机未提供终端环境');
    return { cwd: string(value['cwd']), maxCols: Math.max(2, limit(value['maxCols'], 500)),
      maxRows: limit(value['maxRows'], 200), maxInputBytes: limit(value['maxInputBytes'], 65536),
      maxBufferedBytes: limit(value['maxBufferedBytes'], 2097152) };
  }

  async shells(): Promise<TerminalShell[]> {
    const result: TerminalShell[] = [];
    for (const value of array(await this.client.request('terminal/shells', this.target()))) {
      const shell = terminalShell(value);
      if (shell) result.push(shell);
    }
    return result;
  }

  async list(): Promise<TerminalInfo[]> {
    const args: WireObject = {};
    args['sessionId'] = this.sessionId;
    const value = await this.client.request('terminal/list', args);
    if (!Array.isArray(value)) throw new Error('主机未提供终端列表');
    const result: TerminalInfo[] = [];
    for (const entry of array(value)) {
      const info = terminalInfo(entry);
      if (info) result.push(info);
    }
    return result;
  }

  async create(id: string, cols: number, rows: number, shellPath?: string): Promise<TerminalInfo> {
    const request: WireObject = {};
    request['id'] = id;
    request['cols'] = cols;
    request['rows'] = rows;
    request['shellPath'] = shellPath;
    const args = this.target();
    args['request'] = request;
    const info = terminalInfo(await this.client.request('terminal/create', args));
    if (!info || info.id !== id) throw new Error('主机没有确认终端');
    return info;
  }

  async rename(id: string, title: string): Promise<void> {
    const args = this.target(id);
    args['title'] = title;
    await this.client.request('terminal/rename', args);
  }

  async close(id: string): Promise<void> {
    await this.client.request('terminal/close', this.target(id));
  }

  retain(id: string): Promise<DshSubscription> {
    const args: WireObject = {};
    args['sessionId'] = this.sessionId;
    args['id'] = id;
    return this.client.openStream('terminal/retain', args, () => {}, () => {});
  }
}

interface TerminalInput { command: WireObject; bytes: number; }

function writeInput(data: string, bytes: number): TerminalInput {
  const command: WireObject = {};
  command['type'] = 'write';
  command['data'] = data;
  return { command: command, bytes: bytes };
}

export class TerminalAttachment {
  private client: DshClient;
  private sessionId: string;
  private id: string;
  private attachmentId: string;
  private environment: TerminalEnvironment;
  private onFrame: (frame: TerminalFrame) => void;
  private onClose: (error?: string) => void;
  private connection: number;
  private stream?: DshDuplexStream;
  private cancelFollow?: DshSubscription;
  private follow: boolean = false;
  private closed: boolean = false;
  private writable: boolean = false;
  private outputSequence: number = -1;
  private inputSequence: number = 0;
  private maxFrameBytes: number = 8192;
  private bufferedBytes: number = 0;
  private queued: TerminalInput[] = [];
  private pending?: TerminalInput;
  private timer: number = -1;
  private sizeKey: string = '';

  constructor(client: DshClient, sessionId: string, id: string, attachmentId: string, environment: TerminalEnvironment,
    onFrame: (frame: TerminalFrame) => void, onClose: (error?: string) => void) {
    this.client = client;
    this.sessionId = sessionId;
    this.id = id;
    this.attachmentId = attachmentId;
    this.environment = environment;
    this.onFrame = onFrame;
    this.onClose = onClose;
    this.connection = client.connectionIdentity();
  }

  async open(): Promise<void> {
    this.timer = setTimeout(() => this.finish('等待终端画面超时'), 12000);
    try {
      const stream = await this.client.openDuplexStream('terminal/attach', this.target(false),
        (frame: WireObject): void => { if (!this.follow) this.receive(frame); },
        (error?: string): void => this.duplexEnded(error));
      if (this.closed || this.follow) stream.cancel();
      else { this.stream = stream; this.pump(); }
    } catch { this.duplexEnded('无法连接终端'); }
  }

  private duplexEnded(error?: string): void {
    if (this.closed || this.follow) return;
    if (this.outputSequence >= 0 || this.connection !== this.client.connectionIdentity()) {
      this.finish(error ? '终端连接已中断' : undefined);
    } else {
      this.follow = true;
      this.stream?.cancel();
      void this.openFollow();
    }
  }

  private async openFollow(): Promise<void> {
    try {
      const cancel = await this.client.openStream('terminal/follow', this.target(true),
        (frame: WireObject): void => this.receive(frame),
        (error?: string): void => this.finish(error ? '当前连接无法附加终端' : undefined));
      if (this.closed) cancel();
      else { this.cancelFollow = cancel; this.pump(); }
    } catch { this.finish('当前连接无法附加终端'); }
  }

  private target(follow: boolean): WireObject {
    const args: WireObject = {};
    args['agentId'] = this.sessionId;
    args['id'] = this.id;
    args['attachmentId'] = follow ? this.attachmentId : undefined;
    return args;
  }

  private receive(value: WireObject): void {
    if (this.closed) return;
    const type = string(value['type']);
    const sequence = number(value['sequence'], -1);
    if (this.outputSequence < 0 && type !== 'snapshot') {
      this.finish('终端没有返回初始画面');
      return;
    }
    if (type === 'snapshot' || type === 'state') {
      const rawInfo = object(value['info']);
      const info = terminalInfo(rawInfo);
      if (!info || info.id !== this.id || info.cols > this.environment.maxCols || info.rows > this.environment.maxRows ||
        (type === 'snapshot' && (this.outputSequence >= 0 || !Number.isSafeInteger(sequence) || sequence < 0))) {
        this.finish('终端返回了无效状态');
        return;
      }
      if (type === 'snapshot') {
        clearTimeout(this.timer);
        this.outputSequence = sequence;
        const window = object(value['inputWindow']);
        const max = limit(window['maxBytes'], 65536);
        const overhead = Math.max(0, number(window['frameOverheadBytes'], 0));
        this.maxFrameBytes = Math.max(0, Math.min(8192, max - overhead));
      }
      const writable = (this.follow ? rawInfo['controllerId'] === this.attachmentId : value['writable'] === true) &&
        info.state === 'running';
      if (!writable) this.dropQueued();
      this.writable = writable;
      this.onFrame({ type: type, info: info, screen: type === 'snapshot' ? string(value['screen']) : undefined,
        writable: writable });
    } else if (type === 'output') {
      if (sequence !== this.outputSequence + 1 || typeof value['data'] !== 'string') {
        this.finish('终端输出中断，请重新连接以恢复画面');
        return;
      }
      this.outputSequence = sequence;
      this.onFrame({ type: type, data: string(value['data']) });
    } else if (type === 'ack' && !this.follow) {
      this.acknowledge(sequence, string(value['refusal']));
    }
  }

  write(data: string): boolean {
    if (!this.canWrite() || !data) return false;
    if (data.length > Math.min(65536, this.environment.maxBufferedBytes)) return false;
    const budget = Math.min(this.maxFrameBytes - 96, this.environment.maxInputBytes);
    const chunks: TerminalInput[] = [];
    let chunk = '';
    let bytes = 0;
    for (const character of data) {
      const code = character.codePointAt(0) ?? 0;
      const size = code < 32 ? 6 : (code === 34 || code === 92 ? 2 :
        (code < 128 ? 1 : code < 2048 ? 2 : code < 65536 ? 3 : 4));
      if (size > budget) return false;
      if (bytes + size > budget) {
        chunks.push(writeInput(chunk, bytes + 96));
        chunk = ''; bytes = 0;
      }
      chunk += character;
      bytes += size;
    }
    chunks.push(writeInput(chunk, bytes + 96));
    const total = chunks.reduce((sum: number, input: TerminalInput) => sum + input.bytes, 0);
    if (this.bufferedBytes + total > Math.min(262144, this.environment.maxBufferedBytes)) return false;
    this.bufferedBytes += total;
    this.queued.push(...chunks);
    this.pump();
    return true;
  }

  resize(cols: number, rows: number): boolean {
    if (!this.canWrite() || !Number.isSafeInteger(cols) || !Number.isSafeInteger(rows)) return false;
    cols = Math.max(2, Math.min(cols, this.environment.maxCols));
    rows = Math.max(1, Math.min(rows, this.environment.maxRows));
    const key = `${cols}x${rows}`;
    if (key === this.sizeKey) return true;
    const command: WireObject = {};
    command['type'] = 'resize';
    command['cols'] = cols;
    command['rows'] = rows;
    const last = this.queued[this.queued.length - 1];
    if (last?.command['type'] === 'resize') last.command = command;
    else {
      if (this.maxFrameBytes < 96 || this.bufferedBytes + 96 > this.environment.maxBufferedBytes) return false;
      this.bufferedBytes += 96;
      this.queued.push({ command: command, bytes: 96 });
    }
    this.sizeKey = key;
    this.pump();
    return true;
  }

  private canWrite(): boolean {
    return this.writable && !this.closed && this.connection === this.client.connectionIdentity();
  }

  private pump(): void {
    if (!this.canWrite() || this.pending || !(this.follow ? this.cancelFollow : this.stream)) return;
    const input = this.queued.shift();
    if (!input) return;
    this.pending = input;
    const sequence = ++this.inputSequence;
    input.command['sequence'] = sequence;
    this.timer = setTimeout(() => this.finish('主机没有确认输入，请重新连接终端'), 20000);
    if (this.follow) void this.sendFollow(input.command, sequence);
    else void this.stream?.write(input.command).catch(() => this.finish('终端输入未确认，请重新连接'));
  }

  private async sendFollow(command: WireObject, sequence: number): Promise<void> {
    const target = this.target(true);
    try {
      if (command['type'] === 'write') {
        target['data'] = command['data'];
        await this.client.request('terminal/write', target);
      } else {
        target['cols'] = command['cols']; target['rows'] = command['rows'];
        await this.client.request('terminal/resize', target);
      }
      this.acknowledge(sequence, '');
    } catch { this.finish('终端输入未确认，请重新连接'); }
  }

  private acknowledge(sequence: number, refusal: string): void {
    if (this.closed) return;
    if (!this.pending || sequence !== this.inputSequence) {
      this.finish('主机确认顺序无效，请重新连接终端');
      return;
    }
    clearTimeout(this.timer);
    this.bufferedBytes -= this.pending.bytes;
    this.pending = undefined;
    if (refusal) {
      this.writable = false;
      this.dropQueued();
      this.onFrame({ type: 'refused', writable: false });
    }
    this.pump();
  }

  private dropQueued(): void {
    this.queued = [];
    this.bufferedBytes = this.pending?.bytes ?? 0;
    this.sizeKey = '';
  }

  private finish(error?: string): void {
    if (this.closed) return;
    this.close();
    this.onClose(error);
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    clearTimeout(this.timer);
    this.stream?.cancel();
    this.cancelFollow?.();
    this.dropQueued();
  }
}
