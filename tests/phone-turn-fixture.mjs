// USB-forwarded phone integration mode for the existing pinned relay responder.
// No phone-side test code: the installed app's transportControl executes RTC.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomBytes, createHash, randomUUID } from 'node:crypto';
import { once } from 'node:events';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createServer, connect } from 'node:net';
import { createSocket } from 'node:dgram';
import { join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

export async function createPhoneTurnFixture(signalPort) {
  const directory = resolve(process.env.DSH_PHONE_TURN_DIR || '/tmp/dsh-phone-turn');
  const readyPath = process.env.DSH_PHONE_READY;
  const binary = process.env.DSH_TURN_SERVER;
  assert.ok(readyPath && binary, 'DSH_PHONE_READY and DSH_TURN_SERVER are required');
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const ready = JSON.parse(await readFile(readyPath, 'utf8'));
  const endpoint = ready.transportControl;
  assert.ok(endpoint?.url?.startsWith('http://127.0.0.1:') && endpoint.authorization, 'private phone transportControl readiness');
  const reserve = createServer(); reserve.listen(0, '127.0.0.1'); await once(reserve, 'listening');
  const port = reserve.address().port; await new Promise(ok => reserve.close(ok));
  const config = join(directory, 'coturn.private.conf');
  await writeFile(config, ['listening-ip=127.0.0.1', 'relay-ip=127.0.0.1', `listening-port=${port}`,
    'realm=dsh-phone-loopback.invalid', 'lt-cred-mech', 'user=dsh-fixture:turn-fixture-secret',
    'no-udp', 'no-tls', 'no-dtls', 'no-cli', 'no-multicast-peers', 'allow-loopback-peers',
    'allowed-peer-ip=127.0.0.1', 'denied-peer-ip=0.0.0.0-126.255.255.255',
    'denied-peer-ip=127.0.0.2-255.255.255.255', 'denied-peer-ip=::-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff',
    'relay-threads=1', 'total-quota=4', 'user-quota=4', 'no-software-attribute',
    `pidfile=${join(directory, 'coturn.pid')}`, 'log-file=stdout', 'simple-log'].join('\n') + '\n', { mode: 0o600 });
  const child = spawn(resolve(binary), ['-c', config], { stdio: ['ignore', 'pipe', 'pipe'] });
  let log = ''; child.stdout.on('data', b => { log += b; }); child.stderr.on('data', b => { log += b; });
  let startError, udp, stopped = false;
  child.on('error', error => { startError = error; });
  async function stopCoturn() {
    if (stopped) return; stopped = true;
    try { udp?.close(); } catch { /* Probe was already closed. */ }
    if (child.pid && child.exitCode === null && child.signalCode === null) {
      const ended = once(child, 'exit'); child.kill('SIGTERM');
      await Promise.race([ended, delay(2000)]);
      if (child.exitCode === null && child.signalCode === null) { child.kill('SIGKILL'); await ended; }
    }
    await writeFile(join(directory, 'coturn.log'), log);
  }
  try {
  let open = false;
  for (let i = 0; i < 50 && !open; i++) {
    if (startError) throw startError;
    assert.equal(child.exitCode, null, 'coturn started');
    open = await new Promise(ok => { const socket = connect({ host: '127.0.0.1', port }); socket.once('connect', () => { socket.destroy(); ok(true); }); socket.once('error', () => ok(false)); });
    if (!open) await delay(50);
  }
  assert.ok(open, 'TURN TCP listener ready');
  udp = createSocket('udp4'); let udpAnswered = false;
  const binding = Buffer.alloc(20); binding.writeUInt16BE(1); binding.writeUInt32BE(0x2112a442, 4); randomBytes(12).copy(binding, 8);
  udp.on('message', () => { udpAnswered = true; }); udp.on('error', () => {});
  udp.bind(0, '127.0.0.1'); await once(udp, 'listening'); udp.send(binding, port, '127.0.0.1'); await delay(250); udp.close(); udp = undefined;
  assert.equal(udpAnswered, false, 'TURN UDP control disabled');
  const outgoing = randomBytes(25000).toString('hex'), incoming = randomBytes(25000).toString('hex');
  const evidence = { phoneCandidates: [], offerCandidates: [], selected: [], receivedBytes: 0, sentBytes: 0, responder: [] };
  const ports = { signalPort, turnTcpPort: port, controlPort: Number(new URL(endpoint.url).port),
    reverseReady: join(directory, 'reverse-ready'), bridgeReady: join(directory, 'bridge-ready') };
  await writeFile(join(directory, 'ports.json'), JSON.stringify(ports, null, 2));
  console.log('PHONE_TURN_WAIT_REVERSE ' + JSON.stringify(ports));
  async function waitMarker(path) { for (let i = 0; i < 1200; i++) { if (await readFile(path).then(() => true, () => false)) return; await delay(500); } throw Error('HDC forwarding confirmation timeout'); }
  let origin, bridgeId, isolatedOriginVerified = false;
  const request = async (path, args = {}) => {
    console.log('PHONE_TURN_RPC_START ' + path);
    const response = await fetch(endpoint.url + '/relay/' + path, { method: 'POST', signal: AbortSignal.timeout(path === 'connect' ? 45000 : 10000),
      headers: { authorization: endpoint.authorization, 'content-type': 'application/json' }, body: JSON.stringify({ origin, ...args }) });
    assert.equal(response.status, 200, 'phone transportControl HTTP status');
    const result = await response.json(); assert.equal(result.ok, true, path + ': ' + result.code);
    console.log('PHONE_TURN_RPC_OK ' + path); return result.value;
  };
  return { endpoint, outgoing, incoming, evidence, iceServers: [{ urls: `turn:127.0.0.1:${port}?transport=tcp`, username: 'dsh-fixture', credential: 'turn-fixture-secret' }],
    async run(value, host, ticket, approve) {
      origin = value; await waitMarker(ports.reverseReady);
      const initial = await request('hosts'); assert.equal(initial.signedIn, false, 'isolated fixture origin has no existing phone account');
      isolatedOriginVerified = true;
      const pairing = await request('pair/resolve', { scan: origin + '/pair#v1.' + ticket });
      await request('pair/claim', { id: pairing.id }); approve();
      assert.equal((await request('pair/status', { id: pairing.id })).hostId, host.deviceId);
      const bridge = await request('connect', { hostId: host.deviceId, direct: true });
      bridgeId = bridge.id; assert.equal(bridge.transport, 'turn', 'actual phone selected TURN, never WebSocket fallback');
      const bridgePort = Number(new URL(bridge.launchUrl).port);
      await writeFile(join(directory, 'bridge.private.json'), JSON.stringify(bridge), { mode: 0o600 });
      console.log('PHONE_TURN_WAIT_BRIDGE ' + JSON.stringify({ bridgePort, readyMarker: ports.bridgeReady }));
      await waitMarker(ports.bridgeReady);
      const login = await fetch(bridge.launchUrl, { redirect: 'manual', signal: AbortSignal.timeout(10000) });
      assert.equal(login.status, 302); const cookie = login.headers.get('set-cookie').split(';')[0];
      const response = await fetch(new URL('/api/fixture/turn-probe', bridge.launchUrl), { method: 'POST', signal: AbortSignal.timeout(20000),
        headers: { cookie, 'content-type': 'application/json' }, body: JSON.stringify({ type: 'client-request', rpcId: randomUUID(), method: 'fixture/turn-probe', payload: { args: { content: outgoing } } }) });
      const result = await response.json(); assert.equal(result.result.ok, true); assert.equal(result.result.value.content, incoming);
      assert.equal(evidence.receivedBytes, 50000); assert.equal(evidence.sentBytes, 50000);
      assert.ok(evidence.phoneCandidates.length && evidence.phoneCandidates.every(c => / typ relay(?: |$)/.test(c)), 'all phone trickle candidates are relay');
      assert.ok(evidence.offerCandidates.every(c => / typ relay(?: |$)/.test(c)), 'phone offer has no non-relay candidates');
      assert.deepEqual(evidence.selected, ['turn']);
      const proof = { result: 'PASS', device: 'installed Harmony app Node transportControl', transport: 'TURN TCP via USB forwarding',
        at: new Date().toISOString(), sentBytes: 50000, receivedBytes: 50000, independentPayloads: outgoing !== incoming,
        sentSha256: createHash('sha256').update(outgoing).digest('hex'), receivedSha256: createHash('sha256').update(incoming).digest('hex'), ...evidence };
      await writeFile(join(directory, 'proof.json'), JSON.stringify(proof, null, 2)); console.log('PHONE_TURN_PASS ' + JSON.stringify(proof));
    },
    async close() {
      if (bridgeId) await request('disconnect', { id: bridgeId }).catch(error => console.error('phone disconnect:', error.message));
      if (isolatedOriginVerified) await request('logout').catch(error => console.error('phone fixture logout:', error.message));
      await stopCoturn(); console.log('PHONE_TURN_STOPPED');
    }
  };
  } catch (error) {
    await stopCoturn().catch(() => {});
    throw error;
  }
}
