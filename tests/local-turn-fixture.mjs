// Real isolated coturn listeners. Separate UDP-only and TCP-only servers prove
// the TURN control transport cannot silently fall back to the other protocol.
import assert from 'node:assert/strict';
import { spawn, execFile } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { promisify } from 'node:util';
import { once } from 'node:events';
import { createServer, connect } from 'node:net';
import { createSocket } from 'node:dgram';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
const [binary, archive] = process.argv.slice(2);
assert.ok(binary && archive, 'Usage: local-turn-fixture.mjs <turnserver> <runtime.zip>');
const project = fileURLToPath(new URL('../', import.meta.url));
const temp = await mkdtemp(join(tmpdir(), 'dsh-turn-'));
const servers = [];
let tests;
const stop = new AbortController();
const interrupt = () => stop.abort();
process.once('SIGINT', interrupt); process.once('SIGTERM', interrupt);
async function terminate(child) {
  if (!child || child.exitCode !== null || child.signalCode !== null) return;
  const done = once(child, 'exit'); child.kill('SIGTERM');
  if (!await Promise.race([done.then(() => true), delay(2000, false, { ref: false })])) { child.kill('SIGKILL'); await done; }
}
async function reservePort() {
  for (let attempt = 0; attempt < 8; attempt++) {
    const tcp = createServer(), udp = createSocket('udp4');
    try { tcp.listen(0, '127.0.0.1'); await once(tcp, 'listening'); const port = tcp.address().port;
      udp.bind(port, '127.0.0.1'); await once(udp, 'listening'); return port;
    } catch (error) { if (error.code !== 'EADDRINUSE') throw error; }
    finally { await new Promise(ok => tcp.close(ok)); try { await new Promise(ok => udp.close(ok)); } catch {} }
  }
  throw Error('No free local UDP/TCP port');
}
async function probe(port, transport) {
  return new Promise(resolve => {
    let done = false;
    const socket = transport === 'udp' ? createSocket('udp4') : connect({ host: '127.0.0.1', port });
    const finish = value => { if (done) return; done = true; clearTimeout(timer); if (transport === 'udp') socket.close(); else socket.destroy(); resolve(value); };
    const timer = setTimeout(() => finish(false), 250);
    socket.once('error', () => finish(false));
    if (transport === 'tcp') socket.once('connect', () => finish(true));
    else {
      const request = Buffer.alloc(20); request.writeUInt16BE(1); request.writeUInt32BE(0x2112a442, 4); randomBytes(12).copy(request, 8);
      socket.on('message', response => { if (response.length >= 20 && response.readUInt32BE(4) === 0x2112a442 && response.subarray(8, 20).equals(request.subarray(8))) finish(true); });
      socket.bind(0, '127.0.0.1', () => socket.send(request, port, '127.0.0.1', error => { if (error) finish(false); }));
    }
  });
}
async function startServer(transport) {
  const port = await reservePort(), config = join(temp, transport + '.conf');
  await writeFile(config, [
    'listening-ip=127.0.0.1', 'relay-ip=127.0.0.1', `listening-port=${port}`,
    'realm=dsh-loopback-test.invalid', 'lt-cred-mech', 'user=dsh-fixture:turn-fixture-secret',
    transport === 'udp' ? 'no-tcp' : 'no-udp',
    'no-tls', 'no-dtls', 'no-cli', 'no-multicast-peers', 'allow-loopback-peers',
    'allowed-peer-ip=127.0.0.1', 'denied-peer-ip=0.0.0.0-126.255.255.255',
    'denied-peer-ip=127.0.0.2-255.255.255.255', 'denied-peer-ip=::-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff',
    'relay-threads=1', 'total-quota=8', 'user-quota=8', 'no-software-attribute',
    `pidfile=${join(temp, transport + '.pid')}`, 'log-file=stdout', 'simple-log'
  ].join('\n') + '\n', { mode: 0o600 });
  const child = spawn(resolve(binary), ['-c', config], { cwd: temp, stdio: ['ignore', 'pipe', 'pipe'] });
  const row = { child, port, transport, log: '' }; servers.push(row);
  child.stdout.on('data', value => { row.log += value; }); child.stderr.on('data', value => { row.log += value; });
  child.on('error', error => { row.log += error.message; });
  let ready = false;
  for (let attempt = 0; attempt < 40 && !ready; attempt++) {
    stop.signal.throwIfAborted(); assert.equal(child.exitCode, null, 'coturn exited before readiness:\n' + row.log);
    ready = await probe(port, transport); if (!ready) await delay(50);
  }
  assert.ok(ready, 'coturn listener did not start:\n' + row.log);
  assert.equal(await probe(port, transport === 'udp' ? 'tcp' : 'udp'), false, 'opposite TURN control transport is disabled');
  console.log(`Real coturn ${transport.toUpperCase()}-only at 127.0.0.1:${port}; other control transport disabled.`);
  return `turn:127.0.0.1:${port}?transport=${transport}`;
}
try {
  const udp = await startServer('udp'), tcp = await startServer('tcp');
  const runtime = join(temp, 'runtime');
  await promisify(execFile)('unzip', ['-q', resolve(archive), '-d', runtime]);
  stop.signal.throwIfAborted();
  tests = spawn(process.execPath, ['--jitless', '--no-addons', '--test', join(project, 'tests/dsh-remote-rtc.test.mjs')], {
    cwd: project, stdio: 'inherit', env: { ...process.env, DSH_RTC_TEST_RUNTIME: runtime,
      DSH_TEST_REQUIRE_TURN: '1', DSH_TEST_TURN_UDP_URL: udp, DSH_TEST_TURN_TCP_URL: tcp }
  });
  const cancel = () => { void terminate(tests); }; stop.signal.addEventListener('abort', cancel, { once: true });
  const [code, signal] = await once(tests, 'exit'); stop.signal.removeEventListener('abort', cancel);
  assert.equal(signal, null, 'RTC tests interrupted');
  assert.equal(code, 0, 'RTC tests failed:\n' + servers.map(row => row.log).join('\n'));
  for (const row of servers) assert.equal(row.child.exitCode, null, 'coturn unexpectedly exited during tests');
  console.log('PASS: real UDP-only and TCP-only TURN, relay-only local candidates, 50000 bytes each direction; no skipped cases.');
} finally {
  await terminate(tests); for (const row of servers) await terminate(row.child);
  if (process.env.DSH_TURN_LOG) await writeFile(resolve(process.env.DSH_TURN_LOG), servers.map(row => `=== ${row.transport} 127.0.0.1:${row.port} ===\n${row.log}`).join('\n'));
  process.removeListener('SIGINT', interrupt); process.removeListener('SIGTERM', interrupt);
  await rm(temp, { recursive: true, force: true });
}
