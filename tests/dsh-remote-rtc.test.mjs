import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { once } from 'node:events';
import { test } from 'node:test';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const runtime = resolve(process.env.DSH_RTC_TEST_RUNTIME || 'runtime');
const { openRtcData, fetchRtcIceServers, RtcChunks } = await import(pathToFileURL(runtime + '/dsh-remote-rtc.mjs'));
if (typeof WebAssembly === 'undefined') {
  const { installJitlessFetch } = await import(pathToFileURL(runtime + '/fetch.mjs'));
  installJitlessFetch();
}
const { RTCPeerConnection } = createRequire(runtime + '/webrtc-deps/package.json')('werift');
const settings = { bundlePolicy: 'max-bundle', iceServers: [], iceUseLinkLocalAddress: false };

test('RTCH wire layout, round trip and malformed/replayed chunks', () => {
  const tx = new RtcChunks();
  const rx = new RtcChunks();
  const value = randomBytes(50000);
  const packets = [...tx.split(value)];
  assert.equal(packets[0].subarray(0, 12).toString('hex'), '525443480000000100000007');
  assert.equal(packets[0].length, 8192 + 12);
  assert.throws(() => rx.accept(packets[1]), { code: 'SECURE_CHANNEL_FAILED' });
  for (const packet of packets.slice(0, -1)) assert.equal(rx.accept(packet), undefined);
  assert.deepEqual(rx.accept(packets.at(-1)), value);
  assert.throws(() => rx.accept(packets.at(-1)), { code: 'SECURE_CHANNEL_FAILED' });
  const wrongLength = Buffer.concat([packets[0], Buffer.of(0)]);
  assert.throws(() => rx.accept(wrongLength), { code: 'SECURE_CHANNEL_FAILED' });
});

test('ICE credentials are scoped by connection and redirects are refused', async () => {
  const server = createServer((req, res) => {
    if (req.url.endsWith('redirect')) { res.writeHead(302, { location: '/credential-leak' }).end(); return; }
    if (req.url === '/credential-leak') assert.fail('ICE credential request followed redirect');
    if (req.headers.authorization !== 'Bearer test-fixture') { res.writeHead(401).end(); return; }
    assert.equal(new URL(req.url, 'http://localhost').searchParams.get('connection_id'), 'connection id');
    res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ iceServers: [
      { urls: ['stun:127.0.0.1:3478', 'turn:127.0.0.1:3478?transport=udp'], username: 'fixture', credential: 'turn-secret' },
      { urls: 'turns:fixture.test:5349?transport=tcp' }, { urls: 'https://invalid.test' }
    ] }));
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const origin = 'http://127.0.0.1:' + server.address().port;
  try {
    assert.deepEqual(await fetchRtcIceServers(origin, 'connection id', 'test-fixture'), [
      { urls: 'stun:127.0.0.1:3478' },
      { urls: 'turn:127.0.0.1:3478?transport=udp', username: 'fixture', credential: 'turn-secret' }
    ]);
    await assert.rejects(fetchRtcIceServers(origin, 'connection id', 'wrong-fixture'), { code: 'AUTH_INVALID' });
    await assert.rejects(fetchRtcIceServers(origin, 'redirect', 'test-fixture'), { code: 'CONNECTION_FAILED' });
  } finally { await new Promise(resolve => server.close(resolve)); }
});

async function echoThroughDataChannel(mode, servers, context) {
  const responder = new RTCPeerConnection(mode === 'turn' ? { ...settings, iceUseIpv6: false,
    iceInterfaceAddresses: { udp4: '127.0.0.1' } } : settings);
  const decode = new RtcChunks();
  const encode = new RtcChunks();
  const timeout = AbortSignal.timeout(18000);
  let rejection;
  let receive;
  let remoteReceive;
  let remoteReject;
  let remoteOpen;
  let remoteChannel;
  const peerReady = new Promise(resolve => { remoteOpen = resolve; });
  const peerReceived = new Promise((resolve, reject) => { remoteReceive = resolve; remoteReject = reject; });
  void peerReceived.catch(() => {});
  const response = new Promise((resolve, reject) => { receive = resolve; rejection = reject; });
  void response.catch(() => {});
  let signalTail = Promise.resolve();
  const clientCandidates = [];
  const offerCandidates = [];
  const rtc = openRtcData({
    mode,
    iceServers: servers,
    signal: timeout,
    sendSignal(type, payload) {
      signalTail = signalTail.then(async () => {
        if (type === 'signal.offer') {
          offerCandidates.push(...payload.sdp.split(/\r?\n/).filter(line => line.startsWith('a=candidate:')));
          await responder.setRemoteDescription({ type: 'offer', sdp: payload.sdp });
          await responder.setLocalDescription(await responder.createAnswer());
          rtc.receiveSignal('signal.answer', { sdp: responder.localDescription.sdp });
        } else {
          clientCandidates.push(payload.candidate.candidate);
          await responder.addIceCandidate(payload.candidate);
        }
      });
      void signalTail.catch(rejection);
    },
    onData: receive,
    onClose: code => rejection(new Error(code)),
  });
  responder.ondatachannel = ({ channel }) => {
    assert.equal(channel.label, 'dsh');
    assert.equal(channel.ordered, true);
    remoteChannel = channel;
    channel.onopen = remoteOpen;
    if (channel.readyState === 'open') remoteOpen();
    channel.onmessage = ({ data }) => {
      try { const whole = decode.accept(data); if (whole) remoteReceive(whole); } catch (error) { remoteReject(error); }
    };
  };
  try {
    const selected = await rtc.ready;
    await peerReady;
    const outgoing = randomBytes(50000);
    const incoming = randomBytes(50000);
    assert.notDeepEqual(outgoing, incoming);
    rtc.send(outgoing);
    for (const chunk of encode.split(incoming)) remoteChannel.send(chunk);
    const [atPeer, atClient] = await Promise.all([peerReceived, response]);
    assert.deepEqual(atPeer, outgoing, '50kB client-to-peer payload is byte exact');
    assert.deepEqual(atClient, incoming, 'independent 50kB peer-to-client payload is byte exact');
    if (mode === 'turn') {
      assert.equal(selected, 'turn');
      assert.ok(clientCandidates.length > 0 && clientCandidates.every(candidate => / typ relay(?: |$)/.test(candidate)), 'all signalled local ICE candidates are relay candidates');
      assert.ok(offerCandidates.every(candidate => / typ relay(?: |$)/.test(candidate)), 'offer SDP contains no non-relay candidates');
      context?.diagnostic(JSON.stringify({ transport: servers[0].urls.split('transport=')[1], selected, candidates: clientCandidates, sentBytes: outgoing.length, receivedBytes: incoming.length }));
    } else assert.ok(['lan', 'p2p'].includes(selected));
  } finally {
    rtc.close();
    await responder.close();
  }
}

test('real ICE, DTLS, SCTP and binary DataChannel', { timeout: 20000 }, async () => {
  await echoThroughDataChannel('direct', []);
});

const genericTurn = process.env.DSH_TEST_TURN_URL;
for (const transport of ['udp', 'tcp']) {
  const turn = process.env['DSH_TEST_TURN_' + transport.toUpperCase() + '_URL'] ||
    (genericTurn && new URL(genericTurn.replace(/^turn:/, 'http:')).searchParams.get('transport') === transport ? genericTurn : undefined);
  if (process.env.DSH_TEST_REQUIRE_TURN === '1') assert.ok(turn, 'Missing required ' + transport.toUpperCase() + ' TURN endpoint');
  test('forced TURN ' + transport.toUpperCase() + ' allocation with real bidirectional 50kB DataChannel', { skip: !turn, timeout: 20000 }, async context => {
    await echoThroughDataChannel('turn', [{ urls: turn, username: 'dsh-fixture', credential: 'turn-fixture-secret' }], context);
  });
}
