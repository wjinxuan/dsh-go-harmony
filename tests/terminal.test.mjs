import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { once } from 'node:events';
import { mkdir, mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setImmediate, setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test from 'node:test';
import { loadDshClient } from './dsh-client-node-fixture.mjs';

const dir = await mkdtemp(join(tmpdir(), 'dsh-terminal-tests-'));
const source = new URL('../entry/src/main/ets/dsh/', import.meta.url);
let TerminalAttachment;
let TerminalApi;
try {
  await writeFile(join(dir, 'DshWire.ts'), await readFile(new URL('DshWire.ets', source)));
  const code = (await readFile(new URL('Terminal.ets', source), 'utf8'))
    .replace(/import type .* from '\.\/DshClient'.*\n/g, '').replaceAll("from './DshWire'", "from './DshWire.ts'");
  await writeFile(join(dir, 'Terminal.ts'), code);
  ({ TerminalApi, TerminalAttachment } = await import(pathToFileURL(join(dir, 'Terminal.ts')).href));
} finally {
  await rm(dir, { recursive: true, force: true });
}

const info = { id: 'tab-1', title: 'zsh', shell: { name: 'zsh', path: '/bin/zsh' }, cols: 80, rows: 24, state: 'running' };
const environment = { cwd: '/work', maxCols: 500, maxRows: 200, maxInputBytes: 65536, maxBufferedBytes: 2097152 };

function fixture() {
  const sent = [];
  const frames = [];
  const failures = [];
  let receive;
  let closed = 0;
  const host = {
    connectionIdentity: () => 1,
    async openDuplexStream(_endpoint, _args, onItem) {
      receive = onItem;
      return { async write(value) { sent.push(value); }, cancel() { closed++; } };
    }
  };
  const attachment = new TerminalAttachment(host, 'session', info.id, 'attachment', environment,
    frame => frames.push(frame), error => failures.push(error));
  return { attachment, sent, frames, failures, receive: value => receive(value), closed: () => closed };
}

test('PTY output is ordered and input waits for host acknowledgements', async () => {
  const f = fixture();
  await f.attachment.open();
  f.receive({ type: 'snapshot', sequence: 5, info, screen: '\u001b[31m', writable: true });
  assert.equal(f.attachment.write('hello\r'), true);
  assert.equal(f.attachment.resize(42, 18), true);
  await setImmediate();
  assert.deepEqual(f.sent, [{ type: 'write', sequence: 1, data: 'hello\r' }]);
  f.receive({ type: 'output', sequence: 6, data: 'red' });
  f.receive({ type: 'ack', sequence: 1 });
  await setImmediate();
  assert.deepEqual(f.sent[1], { type: 'resize', sequence: 2, cols: 42, rows: 18 });
  f.receive({ type: 'ack', sequence: 2, refusal: 'read-only' });
  assert.equal(f.attachment.write('must not run'), false);
  assert.deepEqual(f.frames.filter(frame => frame.type === 'output').map(frame => frame.data), ['red']);
  f.attachment.close();
});

test('an output gap detaches and queued input is never replayed', async () => {
  const f = fixture();
  await f.attachment.open();
  f.receive({ type: 'snapshot', sequence: 5, info, screen: '', writable: true });
  f.attachment.write('first');
  f.attachment.write('second');
  f.receive({ type: 'output', sequence: 7, data: 'gap' });
  f.receive({ type: 'ack', sequence: 1 });
  await setImmediate();
  assert.equal(f.sent.length, 1);
  assert.equal(f.closed(), 1);
  assert.equal(f.failures.length, 1);
});

test('relay fallback retains attachment identity across unary input and resize', async () => {
  let follow;
  let closeDirect;
  const sent = [];
  const host = {
    connectionIdentity: () => 1,
    async openDuplexStream(_endpoint, _args, _onItem, onClose) {
      closeDirect = onClose;
      return { write: () => assert.fail('relay has no uplink'), cancel() {} };
    },
    async openStream(endpoint, args, onItem) {
      assert.equal(endpoint, 'terminal/follow');
      assert.equal(args.attachmentId, 'relay-attachment');
      follow = onItem;
      return () => {};
    },
    async request(endpoint, args) { sent.push([endpoint, args]); }
  };
  const attachment = new TerminalAttachment(host, 'session', info.id, 'relay-attachment', environment,
    () => {}, error => assert.fail(error));
  await attachment.open();
  closeDirect('endpoint unavailable');
  await setImmediate();
  follow({ type: 'snapshot', sequence: 1, info: { ...info, controllerId: 'relay-attachment' }, screen: '' });
  assert.equal(attachment.write('hello\r'), true);
  assert.equal(attachment.resize(100, 30), true);
  await setImmediate();
  assert.deepEqual(sent, [
    ['terminal/write', { agentId: 'session', id: info.id, attachmentId: 'relay-attachment', data: 'hello\r' }],
    ['terminal/resize', { agentId: 'session', id: info.id, attachmentId: 'relay-attachment', cols: 100, rows: 30 }]
  ]);
  attachment.close();
});

async function until(check, message) {
  for (let attempt = 0; attempt < 250; attempt++) {
    const value = check();
    if (value) return value;
    await delay(40);
  }
  assert.fail(message);
}

test('stock Mac PTY supports create, attach, input, resize, reattach, rename, exit and close', {
  skip: !process.env.DSH_TERMINAL_TEST_BIN
}, async () => {
  const bin = process.env.DSH_TERMINAL_TEST_BIN;
  const root = await realpath(await mkdtemp(join(tmpdir(), 'dsh-terminal-live-')));
  const workspace = join(root, 'workspace');
  const home = join(root, 'home');
  await Promise.all([mkdir(workspace), mkdir(home)]);
  const child = spawn(process.execPath, [bin, 'web', '--host', '127.0.0.1', '--port', '0', '--no-open'], {
    cwd: workspace,
    env: { ...process.env, HOME: home, DSH_HOME: join(home, '.dsh'), XDG_CONFIG_HOME: join(home, 'config'),
      XDG_CACHE_HOME: join(home, 'cache'), XDG_DATA_HOME: join(home, 'data'), NO_COLOR: '1' },
    stdio: ['ignore', 'pipe', 'ignore']
  });
  let logs = '';
  child.stdout.on('data', bytes => { logs += bytes.toString(); });
  let client;
  const attachments = [];
  const failures = [];
  const views = [];
  try {
    const launch = await until(() => {
      if (child.exitCode !== null) assert.fail(`Stock DSH exited (${child.exitCode})`);
      return /^dsh web: (http:\/\/127\.0\.0\.1:\d+\/\?token=\S+)\s*$/m.exec(logs)?.[1];
    }, 'Stock DSH did not start');
    const Client = await loadDshClient(fileURLToPath(new URL('DshClient.ets', source)), bin, root);
    client = new Client();
    await client.connect(launch);
    const session = await client.createSession(undefined, workspace);
    const terminal = new TerminalApi(client, session);
    const env = await terminal.environment();
    assert.equal(env.cwd, workspace);
    assert.deepEqual(await terminal.list(), []);
    const shells = await terminal.shells();
    const shell = shells.find(entry => entry.path === '/bin/zsh') ?? shells[0];
    assert.ok(shell);
    const id = randomUUID();
    const initial = await terminal.create(id, 80, 24, shell.path);
    assert.equal((await terminal.create(id, 80, 24, shell.path)).id, initial.id);
    const release = await terminal.retain(id);
    const attach = async () => {
      const frames = [];
      views.push(frames);
      const attached = new TerminalAttachment(client, session, id, randomUUID(), env,
        frame => frames.push(frame), error => { if (error) failures.push(error); });
      attachments.push(attached);
      await attached.open();
      const snapshot = await until(() => frames.find(frame => frame.type === 'snapshot'), 'No PTY snapshot');
      assert.equal(snapshot.writable, true);
      return attached;
    };
    const first = await attach();
    assert.equal(first.resize(91, 31), true);
    const command = "printf '\\033[31mDSH_%s\\033[0m\\n' 'PTY_MARKER'; stty size; printf 'pty-proof' > pty-proof.txt\r";
    assert.equal(first.write(command), true);
    await until(() => views[0].map(frame => frame.data ?? '').join('').includes('31 91'), 'PTY resize not applied');
    await until(() => views[0].map(frame => frame.data ?? '').join('').includes('\x1b[31mDSH_PTY_MARKER'), 'PTY did not emit ANSI');
    assert.equal(await readFile(join(workspace, 'pty-proof.txt'), 'utf8'), 'pty-proof');
    const second = await attach();
    await until(() => views[0].some(frame => frame.type === 'state' && frame.writable === false), 'First attachment retained control');
    assert.equal(first.write('must-not-reach-pty\r'), false);
    assert.match(views[1][0].screen, /DSH_PTY_MARKER/);
    first.close();
    await terminal.rename(id, 'PTY verification');
    assert.equal((await terminal.list())[0].title, 'PTY verification');
    assert.equal(second.write('exit 17\r'), true);
    const ended = await until(() => views[1].find(frame => frame.info?.state === 'exited'), 'PTY did not exit');
    assert.equal(ended.info.exitCode, 17);
    await terminal.close(id);
    await terminal.close(id);
    assert.deepEqual(await terminal.list(), []);
    assert.deepEqual(failures, []);
    release();
  } finally {
    for (const attachment of attachments) attachment.close();
    client?.close();
    if (child.exitCode === null && child.signalCode === null) {
      const exited = once(child, 'exit');
      child.kill('SIGTERM');
      if (!await Promise.race([exited.then(() => true), delay(2000, false, { ref: false })])) {
        child.kill('SIGKILL');
        await exited;
      }
    }
    await rm(root, { recursive: true, force: true });
  }
});
