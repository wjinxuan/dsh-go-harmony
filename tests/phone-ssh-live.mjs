// Actual installed-phone SSH bridge; local mode only preflights this isolated fixture.
// Usage: DSH_PHONE_READY=<private ready.json> DSH_PHONE_SSH_DIR=<new directory>
// node tests/phone-ssh-live.mjs <official DSH 0.2.2-rc.1 lib/bin.js>
import assert from 'node:assert/strict';
import { spawn, execFile } from 'node:child_process';
import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { once } from 'node:events';
import { mkdir, mkdtemp, readFile, readdir, realpath, rm, writeFile } from 'node:fs/promises';
import { createServer as httpServer } from 'node:http';
import { createRequire } from 'node:module';
import { connect as tcpConnect } from 'node:net';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { promisify } from 'node:util';
import { loadDshClient } from './dsh-client-node-fixture.mjs';

const run = promisify(execFile);
const require = createRequire(import.meta.url);
const { Server, utils } = require('../runtime/ssh-deps/node_modules/ssh2');
const { bootstrapCommand } = require('../runtime/ssh-bootstrap.cjs');
const bin = resolve(process.argv[2] || '');
assert.ok(process.argv[2], 'Supply the existing official Mac DSH CLI');
assert.equal(JSON.parse(await readFile(join(dirname(bin), '../package.json'), 'utf8')).version, '0.2.2-rc.1');
const phone = !!process.env.DSH_PHONE_READY;
const directory = process.env.DSH_PHONE_SSH_DIR ? resolve(process.env.DSH_PHONE_SSH_DIR) :
  await mkdtemp(join(tmpdir(), 'dsh-phone-ssh-evidence-'));
await mkdir(directory, { recursive: true, mode: 0o700 });
for (const name of ['reverse-ready', 'bridge-ready', 'proof.json']) {
  assert.equal(await readFile(join(directory, name)).then(() => true, () => false), false, 'Use a fresh fixture directory');
}
const root = await realpath(await mkdtemp(join(tmpdir(), 'dsh-phone-ssh-private-')));
const home = join(root, 'home'), workspace = join(root, 'workspace');
await Promise.all([mkdir(home), mkdir(workspace)]);
const deadline = new AbortController();
const timer = setTimeout(() => deadline.abort(new Error('Phone SSH fixture timed out')), 15 * 60_000);
timer.unref();
const stop = () => deadline.abort(new Error('Phone SSH fixture interrupted'));
process.once('SIGTERM', stop); process.once('SIGINT', stop);
const proof = { result: 'RUNNING', device: phone ? 'installed Harmony Node transportControl' : 'Mac fixture preflight',
  scope: 'USB TCP forwarding to loopback SSH fixture; official Mac DSH and real node-pty; no phone terminal UI claim',
  checks: [], publicKeyAttempts: 0, signedKeyAuthentications: 0, bootstrapCommands: 0,
  forwardedConnections: 0, sshReceivedBytes: 0, sshSentBytes: 0, cleanup: {} };
const sockets = new Set(), children = new Set(), attachments = [];
const remoteProcesses = new Map();
let server, serverListening = false, localControl, localHandler, endpoint, client, operationId, release, terminal, terminalId;
const eq = (a, b) => a.length === b.length && timingSafeEqual(a, b);
const quote = value => "'" + value.replaceAll("'", "'\\''") + "'";
const command = `${quote(process.execPath)} ${quote(bin)} web`;
const expectedCommand = bootstrapCommand(command, workspace);
const processStamp = async pid => (await run('/bin/ps', ['-p', String(pid), '-o', 'lstart=']).catch(() => ({ stdout: '' }))).stdout.trim();
async function until(check, label, timeout = 15_000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    deadline.signal.throwIfAborted();
    const value = await check(); if (value) return value;
    await delay(50, undefined, { signal: deadline.signal });
  }
  throw new Error(label);
}
async function marker(name) {
  await until(() => readFile(join(directory, name)).then(() => true, () => false), 'Forwarding marker timeout: ' + name, 5 * 60_000);
}
async function captureRemote() {
  const state = join(home, '.dsh-harmony-remote');
  for (const key of await readdir(state).catch(() => [])) {
    const pid = Number(await readFile(join(state, key, 'web.pid'), 'utf8').catch(() => ''));
    const recorded = (await readFile(join(state, key, 'web.st'), 'utf8').catch(() => '')).trim();
    if (Number.isInteger(pid) && pid > 1 && recorded && await processStamp(pid) === recorded) remoteProcesses.set(pid, recorded);
  }
}
async function remotePort() {
  const state = join(home, '.dsh-harmony-remote');
  const entries = await readdir(state).catch(() => []);
  for (const key of entries) {
    const log = await readFile(join(state, key, 'web.log'), 'utf8').catch(() => '');
    const found = /^dsh web: http:\/\/127\.0\.0\.1:(\d+)\/\?token=/m.exec(log);
    if (found) return Number(found[1]);
  }
  return 0;
}
async function post(path, value, cleaning = false) {
  console.log('PHONE_SSH_RPC_START ' + path);
  const signal = cleaning ? AbortSignal.timeout(6000) : AbortSignal.any([deadline.signal, AbortSignal.timeout(path === '/ssh/connect' ? 82000 : 10000)]);
  const response = await fetch(endpoint.url + path, { method: 'POST', signal,
    headers: { authorization: endpoint.authorization, 'content-type': 'application/json' }, body: JSON.stringify(value) });
  assert.equal(response.status, 200, 'transportControl HTTP status');
  const valueOut = await response.json();
  console.log('PHONE_SSH_RPC_OK ' + path + (valueOut.code ? ' ' + valueOut.code : ''));
  return valueOut;
}
function checked(value) { proof.checks.push(value); console.log('PHONE_SSH_CHECK ' + value); }
let failure;
try {
  await run('ssh-keygen', ['-q', '-t', 'ed25519', '-N', '', '-f', join(root, 'host')]);
  const passphrase = randomBytes(24).toString('base64url');
  await run('ssh-keygen', ['-q', '-t', 'ed25519', '-a', '4', '-N', passphrase, '-f', join(root, 'client')]);
  const allowed = utils.parseKey(await readFile(join(root, 'client.pub')));
  assert.ok(!(allowed instanceof Error));
  const hostKey = await readFile(join(root, 'host'));
  const hostPublic = utils.parseKey(hostKey).getPublicSSH();
  const fingerprint = 'SHA256:' + createHash('sha256').update(hostPublic).digest('base64').replace(/=+$/, '');
  proof.hostFingerprint = fingerprint;
  server = new Server({ hostKeys: [hostKey] }, connection => {
    sockets.add(connection); connection.on('close', () => sockets.delete(connection)); connection.on('error', () => {});
    connection.on('authentication', context => {
      if (context.method === 'publickey') proof.publicKeyAttempts++;
      if (context.username !== 'dsh-fixture' || context.method !== 'publickey' || context.key.algo !== allowed.type ||
        !eq(context.key.data, allowed.getPublicSSH()) ||
        (context.signature && allowed.verify(context.blob, context.signature, context.hashAlgo) !== true)) return context.reject(['publickey']);
      if (context.signature) proof.signedKeyAuthentications++;
      context.accept();
    });
    connection.on('ready', () => {
      connection.on('session', accept => accept().on('exec', (start, reject, info) => {
        if (info.command !== expectedCommand) return reject();
        proof.bootstrapCommands++;
        const channel = start();
        // Exact production-generated bootstrap, confined to this fixture's own home/workspace.
        const child = spawn('/bin/sh', ['-c', info.command], { cwd: workspace, env: {
          PATH: dirname(process.execPath) + ':/usr/bin:/bin:/usr/sbin:/sbin', HOME: home, DSH_HOME: join(home, 'engine'),
          XDG_CONFIG_HOME: join(home, 'config'), XDG_CACHE_HOME: join(home, 'cache'), XDG_DATA_HOME: join(home, 'data'),
          TMPDIR: root, LANG: 'en_US.UTF-8', SHELL: '/bin/zsh', NO_COLOR: '1'
        }, stdio: ['ignore', 'pipe', 'pipe'] });
        children.add(child); child.on('error', () => { channel.exit(127); channel.end(); });
        child.stdout.pipe(channel, { end: false }); child.stderr.pipe(channel.stderr, { end: false });
        child.on('close', (code, signal) => { void captureRemote().finally(() => { children.delete(child); channel.exit(code ?? 128); channel.end(); }); });
      }));
      connection.on('tcpip', (accept, reject, info) => {
        void remotePort().then(port => {
          if (!port || info.destIP !== '127.0.0.1' || info.destPort !== port) return reject();
          const outgoing = tcpConnect({ host: '127.0.0.1', port }); sockets.add(outgoing);
          outgoing.once('error', () => { sockets.delete(outgoing); reject(); });
          outgoing.once('connect', () => {
            const channel = accept(); proof.forwardedConnections++;
            outgoing.removeAllListeners('error'); outgoing.on('error', () => channel.destroy()); channel.on('error', () => outgoing.destroy());
            channel.on('data', chunk => { proof.sshReceivedBytes += chunk.length; });
            outgoing.on('data', chunk => { proof.sshSentBytes += chunk.length; });
            channel.on('close', () => outgoing.destroy()); outgoing.on('close', () => { sockets.delete(outgoing); channel.destroy(); });
            channel.pipe(outgoing).pipe(channel);
          });
        }).catch(() => reject());
      });
    });
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening'); serverListening = true;
  const sshPort = server.address().port;
  if (phone) {
    const ready = JSON.parse(await readFile(process.env.DSH_PHONE_READY, 'utf8'));
    endpoint = ready.transportControl; proof.runtimeVersion = ready.runtimeVersion;
    assert.match(endpoint?.url || '', /^http:\/\/127\.0\.0\.1:\d+$/); assert.ok(endpoint.authorization);
  } else {
    localHandler = require('../runtime/ssh-bridge.cjs').createSshBridgeHandler();
    const authorization = 'Bearer ' + randomBytes(32).toString('base64url');
    localControl = httpServer((request, response) => {
      if (request.headers.authorization !== authorization || !localHandler.handle(request, response)) response.writeHead(403).end();
    });
    localControl.listen(0, '127.0.0.1'); await once(localControl, 'listening');
    endpoint = { url: 'http://127.0.0.1:' + localControl.address().port, authorization };
  }
  const ports = { sshPort, controlPort: Number(new URL(endpoint.url).port), reverseReady: join(directory, 'reverse-ready') };
  await writeFile(join(directory, 'ports.json'), JSON.stringify(ports, null, 2));
  console.log('PHONE_SSH_WAIT_REVERSE ' + JSON.stringify(ports));
  if (phone) await marker('reverse-ready');
  operationId = randomUUID();
  const host = { id: operationId, host: '127.0.0.1', port: sshPort, user: 'dsh-fixture', auth: 'key',
    secret: await readFile(join(root, 'client'), 'utf8'), passphrase, command, directory: workspace };
  assert.deepEqual(await post('/ssh/connect', host), { code: 'host-key-required', fingerprint });
  assert.equal(proof.publicKeyAttempts, 0); checked('unknown fingerprint rejected before public key authentication');
  assert.deepEqual(await post('/ssh/connect', { ...host, fingerprint: 'SHA256:' + 'A'.repeat(43) }), { code: 'host-key-mismatch', fingerprint });
  assert.equal(proof.publicKeyAttempts, 0); checked('mismatched fingerprint rejected before authentication');
  assert.equal((await post('/ssh/connect', { ...host, fingerprint, passphrase: 'incorrect' })).code, 'key-invalid');
  assert.equal(proof.signedKeyAuthentications, 0); checked('encrypted private key rejects wrong passphrase');
  const bridge = await post('/ssh/connect', { ...host, fingerprint });
  assert.ok(bridge.launchUrl && bridge.authorization, bridge.code); assert.equal(proof.signedKeyAuthentications, 1);
  await captureRemote(); assert.equal(remoteProcesses.size, 1, 'capture exact owned DSH PID and start time');
  checked('actual SSH signed key authentication and exact production bootstrap');
  await writeFile(join(directory, 'bridge.private.json'), JSON.stringify(bridge), { mode: 0o600 });
  const bridgePort = Number(new URL(bridge.launchUrl).port);
  console.log('PHONE_SSH_WAIT_BRIDGE ' + JSON.stringify({ bridgePort, readyMarker: join(directory, 'bridge-ready') }));
  if (phone) await marker('bridge-ready');
  assert.equal((await fetch(bridge.launchUrl, { redirect: 'manual', signal: AbortSignal.timeout(5000) })).status, 403);
  assert.equal((await fetch(bridge.launchUrl, { redirect: 'manual', signal: AbortSignal.timeout(5000),
    headers: { authorization: bridge.authorization, origin: 'https://example.invalid' } })).status, 403);
  checked('phone bridge denies missing bearer and foreign Origin');
  const source = fileURLToPath(new URL('../entry/src/main/ets/dsh/', import.meta.url));
  const DshClient = await loadDshClient(join(source, 'DshClient.ets'), bin, root);
  const terminalCode = (await readFile(join(source, 'Terminal.ets'), 'utf8'))
    .replace(/import type .* from '\.\/DshClient'.*\n/g, '').replaceAll("from './DshWire'", "from './DshWire.ts'");
  await writeFile(join(root, 'Terminal.ts'), terminalCode);
  const { TerminalApi, TerminalAttachment } = await import(pathToFileURL(join(root, 'Terminal.ts')).href);
  client = new DshClient(); await client.connect(bridge.launchUrl, bridge.authorization);
  const session = await client.createSession(undefined, workspace);
  assert.ok((await client.listSessions()).some(item => item.id === session && item.cwd === workspace));
  let snapshot; await client.watchSession(session, value => { snapshot = value; });
  await until(() => snapshot?.sessionId === session, 'SSH WebSocket session snapshot');
  checked('official DSH authenticated HTTP and WebSocket session through actual bridge');
  terminal = new TerminalApi(client, session); const environment = await terminal.environment();
  assert.equal(environment.cwd, workspace); assert.deepEqual(await terminal.list(), []);
  const shells = await terminal.shells(), shell = shells.find(value => value.path === '/bin/zsh') || shells[0];
  assert.ok(shell); terminalId = randomUUID();
  await terminal.create(terminalId, 80, 24, shell.path); release = await terminal.retain(terminalId);
  const failures = [], views = [];
  const attach = async () => {
    const frames = []; views.push(frames);
    const attachment = new TerminalAttachment(client, session, terminalId, randomUUID(), environment,
      frame => frames.push(frame), error => { if (error) failures.push(error); });
    attachments.push(attachment); await attachment.open();
    assert.equal((await until(() => frames.find(frame => frame.type === 'snapshot'), 'PTY snapshot')).writable, true);
    return attachment;
  };
  const first = await attach(); assert.equal(first.resize(91, 31), true);
  const nonce = randomBytes(12).toString('hex'), proofName = 'phone-ssh-' + nonce + '.txt';
  assert.equal(first.write(`printf '\\033[31mDSH_%s\\033[0m\\n' 'PHONE_SSH'; stty size; printf '${nonce}' > '${proofName}'\r`), true);
  await until(() => views[0].map(frame => frame.data ?? '').join('').includes('31 91'), 'PTY resize did not apply');
  await until(() => views[0].map(frame => frame.data ?? '').join('').includes('\x1b[31mDSH_PHONE_SSH'), 'PTY ANSI output missing');
  assert.equal(await readFile(join(workspace, proofName), 'utf8'), nonce);
  proof.terminal = { cols: 91, rows: 31, ansi: true, markerSha256: createHash('sha256').update(nonce).digest('hex') };
  checked('real PTY input, 91x31 resize, ANSI output and isolated file bytes');
  const second = await attach();
  await until(() => views[0].some(frame => frame.type === 'state' && frame.writable === false), 'old PTY attachment retained control');
  assert.equal(first.write('must-not-reach-pty\r'), false); assert.match(views[1][0].screen, /DSH_PHONE_SSH/); first.close();
  await terminal.rename(terminalId, 'Phone SSH fixture'); assert.equal((await terminal.list())[0].title, 'Phone SSH fixture');
  assert.equal(second.write('exit 17\r'), true);
  const ended = await until(() => views[1].find(frame => frame.info?.state === 'exited'), 'PTY did not exit');
  assert.equal(ended.info.exitCode, 17); await terminal.close(terminalId); await terminal.close(terminalId);
  assert.deepEqual(await terminal.list(), []); assert.deepEqual(failures, []); release(); release = undefined;
  checked('PTY reattach transfers control, history, rename, exit status and idempotent close');
  client.close(); await client.connect(bridge.launchUrl, bridge.authorization);
  assert.ok((await client.listSessions()).some(item => item.id === session));
  checked('client reconnect preserves isolated session over same SSH tunnel');
  assert.ok(proof.forwardedConnections > 2 && proof.sshReceivedBytes > 1000 && proof.sshSentBytes > 1000);
  client.close();
  assert.deepEqual(await post('/ssh/close', { id: operationId }), { closed: true });
  operationId = undefined; proof.cleanup.phoneCloseAcknowledged = true;
  await assert.rejects(fetch(bridge.launchUrl, { signal: AbortSignal.timeout(3000) }));
  checked('closing phone SSH operation closes its local bridge');
  proof.result = 'PASS';
} catch (error) {
  failure = error; proof.result = 'FAIL'; proof.error = error.message; console.error('PHONE_SSH_FAIL ' + error.message);
} finally {
  clearTimeout(timer);
  for (const attachment of attachments) attachment.close(); release?.(); client?.close();
  if (operationId && endpoint) {
    try { assert.deepEqual(await post('/ssh/close', { id: operationId }, true), { closed: true }); proof.cleanup.phoneCloseAcknowledged = true; }
    catch (error) { proof.cleanup.phoneCloseError = error.message; }
  }
  await localHandler?.close();
  if (localControl) { localControl.closeAllConnections(); await new Promise(done => localControl.close(done)); }
  for (const socket of sockets) { if (typeof socket.destroy === 'function') socket.destroy(); else socket.end(); }
  if (serverListening) { await new Promise(done => server.close(done)); serverListening = false; }
  for (const child of children) {
    if (child.exitCode !== null || child.signalCode !== null) continue;
    const exited = once(child, 'close'); child.kill('SIGTERM');
    if (!await Promise.race([exited.then(() => true), delay(2000, false)])) { child.kill('SIGKILL'); await exited; }
  }
  await captureRemote();
  for (const [pid, stamp] of remoteProcesses) {
    // Capture and verify this exact bootstrap PID/start time; never use a changing global child.
    if (await processStamp(pid) !== stamp) continue;
    process.kill(pid, 'SIGTERM');
    for (let i = 0; i < 40 && await processStamp(pid) === stamp; i++) await delay(50);
    if (await processStamp(pid) === stamp) {
      process.kill(pid, 'SIGKILL');
      for (let i = 0; i < 40 && await processStamp(pid) === stamp; i++) await delay(50);
    }
    if (await processStamp(pid) === stamp) proof.cleanup.remoteProcessError = 'owned DSH process did not exit';
  }
  proof.cleanup.fixtureListenerClosed = !serverListening;
  proof.cleanup.remoteProcessCount = remoteProcesses.size;
  proof.cleanup.remoteProcessesStopped = !proof.cleanup.remoteProcessError;
  await rm(root, { recursive: true, force: true }); proof.cleanup.privateFilesRemoved = true;
  proof.at = new Date().toISOString(); proof.exitCode = failure || proof.cleanup.phoneCloseError || proof.cleanup.remoteProcessError ? 1 : 0;
  await writeFile(join(directory, 'proof.json'), JSON.stringify(proof, null, 2));
  console.log('PHONE_SSH_FINISHED ' + JSON.stringify(proof));
  process.removeListener('SIGTERM', stop); process.removeListener('SIGINT', stop);
  if (proof.exitCode) process.exitCode = proof.exitCode;
}
