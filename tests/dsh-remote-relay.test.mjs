// Run with a packaged runtime directory and the pinned upstream crypto source installed for Node.
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { once } from 'node:events';
import { mkdtemp, realpath, rm } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { loadDshClient } from './dsh-client-node-fixture.mjs';
import { createRequire } from 'node:module';
import { createPhoneTurnFixture } from './phone-turn-fixture.mjs';

const [runtime, responderPath, realServerPath, rtcDirectory] = process.argv.slice(2);
if (!runtime || !responderPath || !realServerPath || !rtcDirectory) {
  throw new Error('Run tests/check-dsh-remote.sh with the pinned upstream checkout.');
}
const fromRuntime = path => import(pathToFileURL(join(runtime, path)).href);
const { WebSocket, WebSocketServer } = await fromRuntime('node_modules/ws/wrapper.mjs');
const { startTransportControl } = await fromRuntime('transport-control.mjs');
const { createDshRemoteHandler } = await fromRuntime('dsh-remote.mjs');
const { NoiseIkSession, createNoisePrologue, generateKeyPair } = await import(pathToFileURL(responderPath).href);
const { RtcDataChannelTransport } = await import(pathToFileURL(join(rtcDirectory, 'rtc-data-channel.ts')).href);
const { loadWeriftFactory, buildWeriftFactory } = await import(pathToFileURL(join(rtcDirectory, 'werift-rtc.ts')).href);
const { pairingProof, Fragments } = await fromRuntime('dsh-remote-wire.mjs');
const phoneTurn = process.env.DSH_PHONE_TURN === '1';
const { RTCPeerConnection } = phoneTurn ? createRequire(join(runtime, 'webrtc-deps/package.json'))('werift') : {};
const rtcFactory = phoneTurn ? buildWeriftFactory({ RTCPeerConnection: class extends RTCPeerConnection {
  constructor(config) { super({ ...config, iceInterfaceAddresses: { udp4: '127.0.0.1' }, iceUseIpv6: false }); }
} }, { interfaces: {} }) : await loadWeriftFactory();
assert.ok(rtcFactory);
let phoneFixture;

const serverKeys = generateKeyPair();
const hostKeys = generateKeyPair();
const host = { deviceId: randomUUID(), name: 'Fixture Mac', role: 'host', platform: 'darwin', identityKey: hostKeys.publicKey };
const sessionId = randomUUID();
const ticket = randomBytes(32).toString('base64url');
let expiresAt = Date.now() + 90000;
let origin;
let attach = false;
let useRtc = false;
let forceFallback = false;
let badHandshake = false;
const attempts = [];
let device;
let token;
let phoneApproved = false;
let hostApproved = false;
let refreshes = 0;
let staleToken = false;
let keyChanged = false;
let replay;
let relaySockets = new Set();
const home = await realpath(await mkdtemp(join(tmpdir(), 'harmony-dsh-remote-')));
const clientPath = fileURLToPath(new URL('../entry/src/main/ets/dsh/DshClient.ets', import.meta.url));
const DshClient = await loadDshClient(clientPath, join(runtime, 'main.cjs'), home);
const abort = new AbortController();
const expire = setTimeout(() => abort.abort(new Error('Relay integration deadline')), phoneTurn ? 1200000 : 60000);

function reply(res, result, status = 200) {
  res.writeHead(status, { 'content-type': 'application/json' }).end(JSON.stringify(result));
}

function tokens() {
  token = 'fixture-access-' + randomUUID();
  return { accessToken: token, accessTokenExpiresAt: Date.now() + 120000,
    refreshToken: 'fixture-refresh-' + randomUUID(), refreshTokenExpiresAt: Date.now() + 360000 };
}

const server = createServer(async (req, res) => {
  try {
    const parts = [];
    for await (const chunk of req) parts.push(chunk);
    const raw = Buffer.concat(parts).toString();
    const body = raw ? JSON.parse(raw) : {};
    const route = req.url;
    if (route === '/api/v1/auth/oauth/providers') return reply(res, { capabilities: {
      devicePairing: 'dsh-pairing-v1', devicePairingQr: 'fragment-ticket-v1'
    }, items: [{ id: 'github', displayName: 'GitHub', qrStartUrl: '/api/v1/auth/oauth/qr/start?provider=github' }] });
    if (route === '/api/v1/auth/oauth/qr/start?provider=github') return reply(res, {
      qrId: 'fixture-browser-qr-id-000000', scanUrl: origin + '/api/v1/auth/q/fixture', expiresIn: 60, provider: 'github'
    });
    if (route === '/api/v1/auth/oauth/qr/fixture-browser-qr-id-000000') {
      return reply(res, { status: 'complete', token: 'fixture-web-account-token' });
    }
    if (route === '/api/v1/auth/me') {
      assert.equal(req.headers.authorization, 'Bearer fixture-web-account-token');
      return reply(res, { account: 'fixture-account' });
    }
    if (route === '/api/v1/devices/register') {
      assert.equal(req.headers.authorization, 'Bearer fixture-web-account-token');
      assert.equal(body.device.deviceId, device.deviceId);
      assert.equal(body.device.identityKey, device.identityKey);
      return reply(res, tokens());
    }
    if (route === '/api/v1/device-pairing/resolve') {
      assert.equal(body.ticket, ticket);
      if (phoneTurn) expiresAt = Date.now() + 90000;
      return reply(res, { v: 1, sessionId, expiresAt, serverPublicKey: serverKeys.publicKey, scanSecret: ticket, host });
    }
    if (route.startsWith('/api/v1/device-pairing/sessions/')) {
      const op = route.split(sessionId + '/')[1];
      if (op === 'claim') {
        assert.equal(body.scanSecret, ticket);
        assert.equal(body.device.role, 'client');
        device = body.device;
      }
      assert.equal(req.headers['x-dsh-pairing-proof'],
        pairingProof(serverKeys.privateKey, device.identityKey, sessionId, route, raw));
      if (op === 'claim') { phoneApproved = true; return reply(res, { state: 'claimed', verificationCode: '00123456', expiresAt }); }
      if (op === 'mobile/status') return reply(res, { v: 1, sessionId, host, mobile: device,
        state: hostApproved ? 'completed' : 'claimed',
        ...(hostApproved ? { credentials: { account: 'fixture-account', accountKind: 'device_only', device, tokens: tokens(),
          inboundOnly: false, pairingRestricted: true } } : {}) });
      if (op === 'mobile/cancel') return reply(res, {});
    }
    if (route === '/api/v1/auth/refresh') { staleToken = false; refreshes++; return reply(res, tokens()); }
    if (route.startsWith('/api/v1/turn/credentials?')) {
      assert.equal(req.headers.authorization, 'Bearer ' + token);
      return reply(res, { iceServers: phoneFixture?.iceServers || [] });
    }
    if (route.startsWith('/api/v1/devices')) {
      assert.equal(req.headers.authorization, 'Bearer ' + token);
      if (route === '/api/v1/devices') {
        if (staleToken) return reply(res, { error: { code: 'TOKEN_EXPIRED' } }, 401);
        return reply(res, { items: [{ ...host, membershipId: 'fixture-membership', online: true }] });
      }
      if (route === '/api/v1/devices/' + host.deviceId) return reply(res, { ...host,
        identityKey: keyChanged ? generateKeyPair().publicKey : host.identityKey, membershipId: 'fixture-membership', online: true });
      if (route === '/api/v1/devices/self' && req.method === 'DELETE') return reply(res, {});
    }
    return reply(res, { error: { code: 'DEVICE_NOT_FOUND' } }, 404);
  } catch { reply(res, { error: { code: 'FIXTURE_ASSERTION_FAILED' } }, 500); }
});

const wsServer = new WebSocketServer({ noServer: true });
server.on('upgrade', (req, sock, head) => {
  if (!['/ws/v1/connect', '/relay-fixture'].includes(req.url)) { sock.destroy(); return; }
  wsServer.handleUpgrade(req, sock, head, socket => {
    relaySockets.add(socket);
    socket.once('close', () => relaySockets.delete(socket));
    if (req.url === '/relay-fixture') configureData(socket);
    else configureControl(socket);
  });
});
const frame = (type, payload) => JSON.stringify({ v: 1, id: randomUUID(), type, timestamp: Date.now(), payload });
let routeState;
function configureData(socket) {
  socket.on('message', raw => {
    const { type, payload } = JSON.parse(raw.toString());
    try {
      if (type === 'relay.attach') {
        assert.equal(payload.ticket, routeState.ticket);
        assert.equal(payload.connectionId, routeState.id);
        assert.equal(payload.deviceId, device.deviceId);
        assert.equal(payload.peerDeviceId, host.deviceId);
        routeState.data = socket;
        socket.send(frame('relay.ready', { connectionId: routeState.id, epoch: 1 }));
      } else if (type === 'relay') routeState.receive(payload);
      else assert.fail(type);
    } catch { socket.terminate(); }
  });
}
function configureControl(socket) {
  const id = randomUUID();
  const incoming = new Fragments();
  const outgoing = new Fragments();
  const state = { id, data: undefined, ticket: 'dshrt.' + randomBytes(24).toString('base64url') };
  routeState = state;
  let noise;
  let rtc;
  let rtcSending = Promise.resolve();
  let selected = '';
  let preferred = [];
  const sendSignal = (type, payload) => socket.send(frame(type, { connectionId: id, targetDeviceId: device.deviceId, ...payload }));
  const send = (type, payload) => {
    for (const part of outgoing.split(Buffer.from(frame(type, payload)))) {
      if (rtc) {
        const ciphertext = noise.encrypt(part);
        rtcSending = rtcSending.then(() => rtc.send(ciphertext)).catch(() => socket.terminate());
        replay = () => { void rtc.send(ciphertext).catch(() => socket.terminate()); };
        continue;
      }
      const value = frame('relay', { connectionId: id, targetDeviceId: device.deviceId, counter: Number(noise.sendingCounter()),
        ciphertext: Buffer.from(noise.encrypt(part)).toString('base64url') });
      (state.data ?? socket).send(value);
      replay = () => (state.data ?? socket).send(value);
    }
  };
  state.receive = payload => {
    assert.equal(payload.targetDeviceId, host.deviceId);
    assert.equal(payload.counter, Number(noise.receivingCounter()));
    receiveCiphertext(Buffer.from(payload.ciphertext, 'base64url'));
  };
  function receiveCiphertext(ciphertext) {
    const opened = incoming.add(Buffer.from(noise.decrypt(ciphertext)));
    if (!opened) return;
    const packet = JSON.parse(opened.toString());
    assert.equal(packet.type, 'rpc.request');
    const { method, params } = packet.payload;
    let result;
    if (method === 'harness.transport.describe') result = { capabilities: ['harness.remote.v3', 'remote.history.compact.v1'] };
    else if (method === 'remote.history.configure') result = { compact: false };
    else if (phoneTurn && method === 'harness.remote.call' && params.endpoint === 'fixture/turn-probe') {
      assert.equal(params.payload.args.content, phoneFixture.outgoing, 'phone-to-Mac payload is byte exact');
      phoneFixture.evidence.receivedBytes = Buffer.byteLength(params.payload.args.content);
      phoneFixture.evidence.sentBytes = Buffer.byteLength(phoneFixture.incoming);
      result = { ok: true, value: { content: phoneFixture.incoming } };
    }
    else if (method === 'harness.remote.call' && params.endpoint === 'session/list') result = { ok: true, value: { items: [] } };
    else if (method === 'harness.remote.stream.open') {
      const value = params.endpoint === '$events' ? { type: 'ready', clientId: 'remote-host-owned-client' } :
        { type: 'fixture', content: 'A'.repeat(50000) };
      send('event', { event: 'harness.remote.frame', data: { streamId: params.streamId, hasValue: true, value } });
      result = { opened: true, streamId: params.streamId };
    } else if (method === 'harness.remote.stream.close') result = {};
    else throw new Error('Unexpected RPC');
    send('rpc.response', { requestId: packet.id, result });
  }
  socket.on('message', raw => {
    const { type, payload } = JSON.parse(raw.toString());
    try {
      if (type === 'hello') {
        assert.equal(payload.accessToken, token);
        assert.equal(payload.deviceId, device.deviceId);
        socket.send(frame('hello.ack', { protocol: 1, serverVersion: 'fixture', connectionSessionId: randomUUID(),
          heartbeatIntervalMs: 25000, maxControlFrameBytes: 65536, maxRelayFrameBytes: 1048576,
          capabilities: ['transport.relay', 'transport.relay.attach', ...payload.capabilities.filter(cap =>
            useRtc && ['transport.lan', 'transport.p2p', 'transport.turn'].includes(cap))] }));
      } else if (type === 'connect.request') {
        assert.equal(payload.hostDeviceId, host.deviceId);
        preferred = payload.preferredTransports;
        if (phoneTurn && preferred.length === 1) throw Error('Phone fixture forbids WebSocket relay fallback');
        attempts.push({ id, preferred });
        if (!attach && preferred.length === 1) selected = 'relay';
        socket.send(frame('connect.accepted', { connectionId: id, ...(attach ? {
          relayEndpoint: origin.replace('http:', 'ws:') + '/relay-fixture', relayTicket: state.ticket,
          relayNodeId: 'fixture', relayEpoch: 1
        } : {}) }));
      } else if (type === 'transport.selected') {
        assert.ok(preferred.includes(payload.transport));
        if (payload.transport === 'relay') assert.ok(state.data);
        else assert.ok(rtc);
        selected = payload.transport;
        if (phoneTurn) phoneFixture.evidence.selected.push(selected);
      } else if (type === 'signal.offer') {
        assert.ok(useRtc && preferred.some(value => value !== 'relay'));
        if (forceFallback || (phoneTurn && !preferred.includes('turn'))) return;
        if (phoneTurn) phoneFixture.evidence.offerCandidates.push(...payload.sdp.split(/\r?\n/).filter(line => line.startsWith('a=candidate:')));
        rtc = new RtcDataChannelTransport({ role: 'responder', factory: rtcFactory, onSignal: signal => {
          if (signal.type === 'answer') sendSignal('signal.answer', { sdp: signal.sdp });
          else if (signal.type === 'ice') sendSignal('signal.ice', { candidate: signal.candidate });
        }, ...(phoneTurn ? { onDiagnostic: event => {
          if (event.type === 'selected-path') phoneFixture.evidence.responder.push(event.selectedPath);
        } } : {}) });
        rtc.onMessage(data => { try { receiveCiphertext(Buffer.from(data)); } catch { socket.terminate(); } });
        void rtc.connect().catch(() => socket.terminate());
        rtc.handleSignal({ type: 'offer', sdp: payload.sdp });
      } else if (type === 'signal.ice') {
        if (phoneTurn && preferred.includes('turn')) phoneFixture.evidence.phoneCandidates.push(payload.candidate.candidate);
        rtc?.handleSignal({ type: 'ice', candidate: payload.candidate });
      } else if (type === 'secure.handshake') {
        assert.ok(selected);
        assert.equal(payload.targetDeviceId, host.deviceId);
        assert.equal(payload.step, 1);
        noise = new NoiseIkSession({ role: 'responder', localPrivateKey: hostKeys.privateKey, localPublicKey: hostKeys.publicKey,
          remotePublicKey: device.identityKey, prologue: createNoisePrologue(id, host.deviceId, device.deviceId) });
        assert.equal(noise.readHandshake(Buffer.from(payload.data, 'base64url')).length, 0);
        const handshake = Buffer.from(noise.writeHandshake());
        if (badHandshake) handshake[handshake.length - 1] ^= 1;
        socket.send(frame('secure.handshake', { connectionId: id, targetDeviceId: device.deviceId, step: 2,
          data: handshake.toString('base64url') }));
      } else if (type === 'relay' && selected === 'relay') state.receive(payload);
      else assert.fail(type);
    } catch (error) { if (phoneTurn) console.error('PHONE_FIXTURE_ERROR', error.message); socket.terminate(); }
  });
  socket.on('close', () => { noise?.destroy(); void rtc?.close().catch(() => {}); });
}

let control;
async function rpc(path, args = {}) {
  const response = await fetch(control.endpoint.url + '/relay/' + path, { method: 'POST', signal: abort.signal,
    headers: { authorization: control.endpoint.authorization, 'content-type': 'application/json' },
    body: JSON.stringify({ origin, ...args }) });
  return response.json();
}
async function ok(path, args) {
  const reply = await rpc(path, args);
  assert.equal(reply.ok, true, path + ': ' + reply.code);
  return reply.value;
}
async function connectFacade(transport = 'relay', direct = true) {
  const endpoint = await ok('connect', { hostId: host.deviceId, direct });
  assert.equal(endpoint.transport, transport);
  if (attach) {
    let disconnected;
    const closed = new Promise(resolve => { disconnected = resolve; });
    const client = new DshClient(reason => disconnected(reason));
    try {
      await client.connect(endpoint.launchUrl);
      assert.deepEqual(await client.listSessions(), []);
      const received = new Promise((resolve, reject) => {
        client.openStream('session/follow', {}, value => resolve(value), reject).catch(reject);
      });
      assert.equal((await received).content.length, 50000);
      replay();
      await closed;
    } finally {
      client.close();
      await ok('disconnect', { id: endpoint.id });
    }
    return;
  }
  const login = await fetch(endpoint.launchUrl, { redirect: 'manual', signal: abort.signal });
  assert.equal(login.status, 302);
  const cookie = login.headers.get('set-cookie').split(';')[0];
  const base = new URL(endpoint.launchUrl).origin;
  assert.equal((await fetch(base + '/api/session/list', { method: 'POST', signal: abort.signal })).status, 401);
  assert.equal((await fetch(base + '/api/session/uploadFileBinary', { method: 'POST', signal: abort.signal,
    headers: { cookie } })).status, 404);
  const rpcId = randomUUID();
  const response = await fetch(base + '/api/session/list', { method: 'POST', signal: abort.signal,
    headers: { cookie, 'content-type': 'application/json' }, body: JSON.stringify({ type: 'client-request', rpcId,
      method: 'session/list', payload: { args: {} } }) });
  assert.deepEqual(await response.json(), { type: 'server-response', rpcId, result: { ok: true, value: { items: [] } } });
  const external = new WebSocket(base.replace('http:', 'ws:') + '/api/remote.mux',
    { headers: { cookie, origin: 'https://external.test' } });
  await assert.rejects(once(external, 'open', { signal: abort.signal }));
  const socket = new WebSocket(base.replace('http:', 'ws:') + '/api/remote.mux',
    { headers: { cookie, origin: base } });
  await once(socket, 'open', { signal: abort.signal });
  const ready = once(socket, 'message', { signal: abort.signal });
  socket.send(JSON.stringify({ type: 'open', streamId: 'events', endpoint: '$events', payload: { args: {} } }));
  assert.deepEqual(JSON.parse((await ready)[0].toString()), { type: 'item', streamId: 'events',
    value: { type: 'ready', clientId: 'remote-host-owned-client' } });
  const message = once(socket, 'message', { signal: abort.signal });
  socket.send(JSON.stringify({ type: 'open', streamId: 'work', endpoint: 'session/follow', payload: { args: {} } }));
  assert.equal(JSON.parse((await message)[0].toString()).value.content.length, 50000);
  const closed = once(socket, 'close', { signal: abort.signal });
  replay();
  await closed;
  await ok('disconnect', { id: endpoint.id });
}

async function connectThroughOriginalGateway() {
  const register = async (path, data, bearer) => {
    const response = await fetch(origin + path, { method: 'POST', signal: abort.signal,
      headers: { 'content-type': 'application/json', ...(bearer ? { authorization: 'Bearer ' + bearer } : {}) },
      body: JSON.stringify(data) });
    assert.equal(response.status, 200, path);
    return response.json();
  };
  const login = await register('/api/v1/auth/login', { email: 'fixture@example.test', password: 'test-only-self-hosted-password' });
  const registration = await register('/api/v1/devices/register', { v: 1, device: { ...host, clientVersion: '0.6.4' } }, login.token);
  const socket = new WebSocket(origin.replace('http:', 'ws:') + '/ws/v1/connect');
  let rtc;
  let noise;
  let clientId;
  let connectionId;
  let selected;
  const send = (type, value) => socket.send(frame(type, value));
  const toClient = (type, value) => send(type, { ...value, connectionId, targetDeviceId: clientId });
  const online = Promise.withResolvers();
  const fail = error => { online.reject(error); socket.terminate(); };
  socket.once('error', fail);
  socket.on('message', raw => {
    try {
      const { type, payload } = JSON.parse(raw);
      if (type === 'hello.ack') online.resolve();
      else if (type === 'ping') send('pong', { nonce: payload.nonce });
      else if (type === 'connect.incoming') {
        assert.ok(payload.preferredTransports.includes('lan'));
        connectionId = payload.connectionId;
        clientId = payload.clientDeviceId;
        noise = new NoiseIkSession({ role: 'responder', localPrivateKey: hostKeys.privateKey, localPublicKey: hostKeys.publicKey,
          remotePublicKey: payload.clientIdentityKey, prologue: createNoisePrologue(connectionId, host.deviceId, clientId) });
        send('connect.accepted', { connectionId });
      } else if (type === 'signal.offer') {
        rtc = new RtcDataChannelTransport({ role: 'responder', factory: rtcFactory, onSignal: signal => {
          if (signal.type === 'answer') toClient('signal.answer', { sdp: signal.sdp });
          else if (signal.type === 'ice') toClient('signal.ice', { candidate: signal.candidate });
        } });
        rtc.onMessage(encrypted => {
          try {
            const packet = JSON.parse(Buffer.from(noise.decrypt(encrypted)).toString());
            assert.equal(packet.payload.method, 'harness.transport.describe');
            const reply = frame('rpc.response', { requestId: packet.id, result: { capabilities: ['harness.remote.v3'] } });
            void rtc.send(noise.encrypt(Buffer.from(reply))).catch(fail);
          } catch (error) { fail(error); }
        });
        void rtc.connect().catch(fail);
        rtc.handleSignal({ type: 'offer', sdp: payload.sdp });
      } else if (type === 'signal.ice') rtc.handleSignal({ type: 'ice', candidate: payload.candidate });
      else if (type === 'transport.selected') selected = payload.transport;
      else if (type === 'secure.handshake') {
        assert.equal(selected, 'lan');
        assert.equal(noise.readHandshake(Buffer.from(payload.data, 'base64url')).length, 0);
        toClient('secure.handshake', { step: 2, data: Buffer.from(noise.writeHandshake()).toString('base64url') });
      } else if (type === 'error' && payload.code !== 'CONNECTION_FAILED') assert.fail(payload.code);
    } catch (error) { fail(error); }
  });
  try {
    await once(socket, 'open', { signal: abort.signal });
    send('hello', { role: 'host', deviceId: host.deviceId, accessToken: registration.accessToken, protocols: [1],
      clientVersion: '0.6.4', capabilities: ['transport.lan', 'transport.p2p', 'transport.relay'] });
    await Promise.race([online.promise, delay(5000, null, { signal: abort.signal }).then(() => { throw new Error('Host hello timed out'); })]);
    const peer = await ok('peer', { hostId: host.deviceId });
    const endpoint = await ok('connect', { hostId: host.deviceId, fingerprint: peer.fingerprint });
    assert.equal(endpoint.transport, 'lan');
    await ok('disconnect', { id: endpoint.id });
  } finally {
    socket.terminate();
    noise?.destroy();
    await rtc?.close();
  }
}

try {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening', { signal: abort.signal });
  origin = 'http://127.0.0.1:' + server.address().port;
  if (phoneTurn) {
    useRtc = true;
    phoneFixture = await createPhoneTurnFixture(server.address().port);
    await phoneFixture.run(origin, host, ticket, () => { hostApproved = true; });
  } else {
  control = await startTransportControl({ relay: createDshRemoteHandler(home) });
  assert.equal((await fetch(control.endpoint.url + '/relay/hosts', { method: 'POST', signal: abort.signal })).status, 403);
  assert.deepEqual(await ok('hosts'), { origin, signedIn: false, hosts: [] });
  const resolved = await ok('pair/resolve', { scan: origin + '/pair#v1.' + ticket });
  assert.equal(resolved.host, host.name);
  assert.equal(phoneApproved, false, 'Resolve must not claim before confirmation');
  assert.equal((await ok('pair/claim', { id: resolved.id })).code, '00123456');
  assert.equal((await ok('pair/status', { id: resolved.id })).state, 'claimed');
  hostApproved = true;
  assert.equal((await ok('pair/status', { id: resolved.id })).hostId, host.deviceId);
  assert.equal((await ok('peer', { hostId: host.deviceId })).trusted, true);
  keyChanged = true;
  assert.equal((await rpc('connect', { hostId: host.deviceId })).code, 'PEER_IDENTITY_MISMATCH');
  keyChanged = false;
  await connectFacade();
  attach = true;
  await connectFacade();
  useRtc = true;
  await connectFacade('lan');
  assert.deepEqual(attempts.at(-1).preferred, ['lan', 'p2p', 'relay']);
  badHandshake = true;
  const beforeBadHandshake = attempts.length;
  assert.equal((await rpc('connect', { hostId: host.deviceId })).code, 'SECURE_CHANNEL_FAILED');
  assert.equal(attempts.length, beforeBadHandshake + 1, 'An invalid Noise handshake must not retry a different route');
  badHandshake = false;
  forceFallback = true;
  await connectFacade();
  const fallbackAttempts = attempts.slice(-3);
  assert.deepEqual(fallbackAttempts.map(value => value.preferred), [['lan', 'p2p', 'relay'], ['turn', 'relay'], ['relay']]);
  assert.equal(new Set(fallbackAttempts.map(value => value.id)).size, 3);
  await connectFacade('relay', false);
  assert.deepEqual(attempts.at(-1).preferred, ['relay']);
  await control.close();
  control = await startTransportControl({ relay: createDshRemoteHandler(home) });
  assert.equal((await ok('peer', { hostId: host.deviceId })).trusted, true);
  staleToken = true;
  const [one, two] = await Promise.all([ok('hosts'), ok('hosts')]);
  assert.equal(one.signedIn, true);
  assert.deepEqual(two, one);
  assert.equal(refreshes, 1);
  assert.deepEqual((await ok('providers')).items, [{ id: 'github', name: 'GitHub' }]);
  const browser = await ok('browser/start', { provider: 'github' });
  assert.equal(new URL(browser.url).origin, origin);
  assert.equal((await ok('browser/status', { id: browser.id })).state, 'completed');
  await ok('logout');
  assert.deepEqual(await ok('hosts'), { origin, signedIn: false, hosts: [] });
  console.log('DSH Remote pairing, browser login, pin persistence, upstream LAN, fresh TURN/relay fallback, encrypted HTTP/mux and replay rejection passed');
  const { createRemoteServer } = await import(pathToFileURL(realServerPath).href);
  const realServer = createRemoteServer({ account: 'fixture@example.test', password: 'test-only-self-hosted-password',
    publicUrl: 'http://127.0.0.1', dataFile: join(home, 'server-state.json'), logLevel: 'silent' });
  try {
    realServer.server.listen(0, '127.0.0.1');
    await once(realServer.server, 'listening', { signal: abort.signal });
    origin = 'http://127.0.0.1:' + realServer.server.address().port;
    assert.deepEqual(await ok('providers'), { items: [] });
    assert.equal((await rpc('password', { email: 'fixture@example.test', password: 'wrong-test-password' })).code, 'AUTH_INVALID');
    await ok('password', { email: 'fixture@example.test', password: 'test-only-self-hosted-password' });
    assert.deepEqual(await ok('hosts'), { origin, signedIn: true, hosts: [] });
    await connectThroughOriginalGateway();
    await ok('logout');
    assert.deepEqual(await ok('hosts'), { origin, signedIn: false, hosts: [] });
  } finally { await realServer.close(); }
  console.log('Pinned self-hosted server password login, device registration, LAN authorization/signaling and revocation passed');
  }
} finally {
  clearTimeout(expire);
  await phoneFixture?.close();
  await control?.close();
  for (const socket of relaySockets) socket.terminate();
  wsServer.close();
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  await delay(10);
  await rm(home, { recursive: true, force: true });
}
