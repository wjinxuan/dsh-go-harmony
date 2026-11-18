import assert from 'node:assert/strict';
import { spawn, execFile } from 'node:child_process';
import { randomUUID, randomBytes } from 'node:crypto';
import { once } from 'node:events';
import { mkdir, mkdtemp, readdir, readFile, realpath, rm, symlink, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { userInfo, tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { loadDshClient } from './dsh-client-node-fixture.mjs';

const [bin, sshdBin = '/usr/sbin/sshd'] = process.argv.slice(2);
assert.ok(bin, 'Supply the original Mac DSH CLI entry file');
const dsh = resolve(bin);
const { Server: SshServer } = createRequire(import.meta.url)('../runtime/ssh-deps/node_modules/ssh2');
const run = promisify(execFile);
const root = await realpath(await mkdtemp(join(tmpdir(), 'dsh-ssh-fixture-')));
const home = join(root, 'home');
const auth = 'Bearer ' + randomBytes(32).toString('base64url');
const bridgePath = fileURLToPath(new URL('../runtime/ssh-bridge.cjs', import.meta.url));
let sshd;
let bridge;
let remotePid;
let client;
let passwordServer;
const passwordSockets = new Set();

try {
  await mkdir(home);
  await run('ssh-keygen', ['-q', '-t', 'ed25519', '-N', '', '-f', join(root, 'host')]);
  await run('ssh-keygen', ['-q', '-t', 'ed25519', '-a', '4', '-N', 'fixture-passphrase', '-f', join(root, 'client')]);
  const hostFingerprint = (await run('ssh-keygen', ['-lf', join(root, 'host.pub')])).stdout.split(' ')[1];
  const authorized = join(root, 'client.pub');
  const command = join(root, 'forced-shell');
  const script = '#!/bin/sh\nexport HOME=' + home + '\nexport DSH_HOME=' + join(root, 'engine') +
    '\ncd "$HOME"\nexec sh -c "$SSH_ORIGINAL_COMMAND"\n';
  await writeFile(command, script, { mode: 0o700 });
  const free = createServer().listen(0, '127.0.0.1');
  await once(free, 'listening');
  const port = free.address().port;
  await new Promise(done => free.close(done));
  sshd = spawn(sshdBin, ['-D', '-e', '-f', '/dev/null', '-p', String(port), '-h', join(root, 'host'),
    '-o', 'ListenAddress=127.0.0.1', '-o', `AuthorizedKeysFile=${authorized}`, '-o', 'StrictModes=no',
    '-o', 'UsePAM=no', '-o', 'PasswordAuthentication=no', '-o', 'AllowTcpForwarding=yes', '-o', `ForceCommand=${command}`,
    '-o', `PidFile=${join(root, 'sshd.pid')}`], { stdio: ['ignore', 'ignore', 'pipe'] });
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('Isolated sshd did not start')), 5000);
    sshd.once('error', error => { clearTimeout(timeout); reject(error); });
    sshd.once('exit', code => { clearTimeout(timeout); reject(new Error(`sshd exited with ${code}`)); });
    sshd.stderr.on('data', bytes => {
      if (!bytes.includes('Server listening')) return;
      clearTimeout(timeout);
      resolve();
    });
  });
  bridge = spawn(process.execPath, ['--jitless', '--no-addons', '-e', `
const { createServer } = require('node:http');
const { createSshBridgeHandler } = require(process.argv[1]);
const handler = createSshBridgeHandler();
const server = createServer((request, response) => {
  if (request.headers.authorization !== process.env.DSH_TEST_BRIDGE_BEARER || !handler.handle(request, response)) {
    response.writeHead(403).end();
  }
});
server.listen(0, '127.0.0.1', () => console.log(server.address().port));
process.once('SIGTERM', async () => {
  await handler.close();
  server.closeAllConnections();
  server.close();
});`, bridgePath], { env: { ...process.env, DSH_TEST_BRIDGE_BEARER: auth }, stdio: ['ignore', 'pipe', 'inherit'] });
  const [controlPort] = await once(bridge.stdout, 'data');
  const base = `http://127.0.0.1:${String(controlPort).trim()}`;
  const post = async (path, value) => {
    const response = await fetch(base + path, { method: 'POST', headers: { authorization: auth }, body: JSON.stringify(value),
      signal: AbortSignal.timeout(82000) });
    assert.equal(response.status, 200);
    return response.json();
  };
  const id = randomUUID();
  const host = { id, host: '127.0.0.1', port, user: userInfo().username, auth: 'key',
    secret: await readFile(join(root, 'client'), 'utf8'), passphrase: 'fixture-passphrase',
    command: `"${process.execPath}" "${dsh}" web`, directory: '~' };
  const unknown = await post('/ssh/connect', host);
  assert.deepEqual(unknown, { code: 'host-key-required', fingerprint: hostFingerprint });
  assert.deepEqual(await post('/ssh/connect', { ...host, fingerprint: 'SHA256:' + 'A'.repeat(43) }),
    { code: 'host-key-mismatch', fingerprint: hostFingerprint });
  const pinned = { ...host, fingerprint: hostFingerprint };
  assert.equal((await post('/ssh/connect', { ...pinned, passphrase: 'wrong' })).code, 'key-invalid');
  const first = await post('/ssh/connect', pinned);
  assert.ok(first.launchUrl && first.authorization, first.code);
  assert.ok((await readdir(join(home, '.dsh-harmony-remote'))).length > 0, 'Remote bootstrap used the isolated test home');
  assert.equal((await fetch(first.launchUrl, { redirect: 'manual' })).status, 403);
  assert.equal((await fetch(first.launchUrl, { redirect: 'manual', headers: {
    authorization: first.authorization, origin: 'https://example.invalid'
  } })).status, 403);
  const clientPath = fileURLToPath(new URL('../entry/src/main/ets/dsh/DshClient.ets', import.meta.url));
  const DshClient = await loadDshClient(clientPath, dsh, root);
  client = new DshClient();
  await client.connect(first.launchUrl, first.authorization);
  const session = await client.createSession();
  assert.ok((await client.listSessions()).some(item => item.id === session && item.cwd === home));
  let update;
  await client.watchSession(session, value => { update = value; });
  assert.equal(update.sessionId, session);
  await post('/ssh/close', { id });
  await assert.rejects(fetch(first.launchUrl, { signal: AbortSignal.timeout(2000) }));
  client.close();
  const state = join(home, '.dsh-harmony-remote');
  const [processDirectory] = await readdir(state);
  await symlink('999999999:dead', join(state, processDirectory, 'lock'));
  const second = await post('/ssh/connect', pinned);
  assert.ok(second.launchUrl && new URL(second.launchUrl).search === new URL(first.launchUrl).search, 'Remote DSH should be reused');
  await client.connect(second.launchUrl, second.authorization);
  assert.ok((await client.listSessions()).some(item => item.id === session));
  await post('/ssh/close', { id });

  let passwordAttempts = 0;
  const serverKey = await readFile(join(root, 'host'));
  passwordServer = new SshServer({ hostKeys: [serverKey] }, connection => {
    passwordSockets.add(connection);
    connection.on('close', () => passwordSockets.delete(connection));
    connection.on('error', () => {});
    connection.on('authentication', context => {
      if (context.method === 'password') passwordAttempts++;
      if (context.method === 'password' && context.password === 'fixture-password') context.accept();
      else context.reject(['password']);
    });
    connection.on('ready', () => connection.on('session', accept => {
      accept().on('exec', start => {
        const channel = start();
        channel.exit(127);
        channel.end('DSHAPP no-dsh\n');
      });
    }));
  });
  passwordServer.listen(0, '127.0.0.1');
  await once(passwordServer, 'listening');
  const passwordHost = { ...host, port: passwordServer.address().port, auth: 'password', secret: 'fixture-password' };
  assert.deepEqual(await post('/ssh/connect', passwordHost), { code: 'host-key-required', fingerprint: hostFingerprint });
  assert.equal(passwordAttempts, 0, 'Password must not be sent before a host key is trusted');
  assert.equal((await post('/ssh/connect', { ...passwordHost, fingerprint: hostFingerprint, secret: 'wrong' })).code, 'auth-failed');
  assert.equal((await post('/ssh/connect', { ...passwordHost, fingerprint: hostFingerprint })).code, 'no-dsh');
  assert.equal(passwordAttempts, 2, 'Password auth was attempted only for the pinned host');
  console.log('PASS: isolated OpenSSH, encrypted private key, password auth, host fingerprint checks, DSH HTTP/WSS, reuse and cleanup');
} finally {
  client?.close();
  for (const connection of passwordSockets) connection.end();
  if (passwordServer) await new Promise(done => passwordServer.close(done));
  for (const child of [bridge, sshd]) {
    if (!child || child.exitCode !== null || child.signalCode !== null) continue;
    const closed = once(child, 'exit');
    child.kill();
    await closed;
  }
  const state = join(home, '.dsh-harmony-remote');
  for (const key of await readdir(state).catch(() => [])) {
    remotePid = Number(await readFile(join(state, key, 'web.pid'), 'utf8').catch(() => ''));
    if (Number.isInteger(remotePid) && remotePid > 1) {
      try { process.kill(remotePid, 'SIGTERM'); } catch {}
    }
  }
  await rm(root, { recursive: true, force: true });
}
