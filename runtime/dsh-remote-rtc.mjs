// DSH Remote WebRTC signaling and RTCH framing derived from ds-harness-remote (MIT).
// Copyright (c) 2026 DSH Remote contributors. See THIRD_PARTY_NOTICES.md.
import { createRequire } from 'node:module';
import { isIP } from 'node:net';
import { isObject, parseWire, text } from './dsh-remote-wire.mjs';

const require = createRequire(new URL('./webrtc-deps/package.json', import.meta.url));
const chunkSize = 8192;
const maxMessage = 4 * 1024 * 1024;
const headerSize = 12;
const magic = Buffer.from('RTCH');
const turnUrl = /^turns?:/i;
const relayCandidate = /(?:^|\s)typ\s+relay(?:\s|$)/i;

function failure(code) {
  return Object.assign(new Error(code), { code });
}

export class RtcChunks {
  #next = 1;
  #pending = new Map();

  *split(bytes) {
    if (bytes.length > maxMessage) throw failure('SECURE_CHANNEL_FAILED');
    if (bytes.length <= chunkSize) { yield bytes; return; }
    const id = this.#next;
    this.#next = id === 0xffffffff ? 1 : id + 1;
    const total = Math.ceil(bytes.length / chunkSize);
    for (let i = 0; i < total; i++) {
      const header = Buffer.alloc(headerSize);
      magic.copy(header);
      header.writeUInt32BE(id, 4);
      header.writeUInt16BE(i, 8);
      header.writeUInt16BE(total, 10);
      yield Buffer.concat([header, bytes.subarray(i * chunkSize, (i + 1) * chunkSize)]);
    }
  }

  accept(bytes) {
    if (!bytes.subarray(0, 4).equals(magic)) {
      if (bytes.length > maxMessage) throw failure('SECURE_CHANNEL_FAILED');
      return bytes;
    }
    if (bytes.length <= headerSize) throw failure('SECURE_CHANNEL_FAILED');
    const id = bytes.readUInt32BE(4);
    const index = bytes.readUInt16BE(8);
    const total = bytes.readUInt16BE(10);
    const size = bytes.length - headerSize;
    if (!id || total < 2 || total > maxMessage / chunkSize || index >= total ||
        size > chunkSize || (index < total - 1 && size !== chunkSize)) throw failure('SECURE_CHANNEL_FAILED');
    const now = Date.now();
    for (const [key, assembly] of this.#pending) if (now - assembly.updatedAt > 30000) this.#pending.delete(key);
    let assembly = this.#pending.get(id);
    if (!assembly) {
      if (index !== 0 || this.#pending.size >= 8) throw failure('SECURE_CHANNEL_FAILED');
      assembly = { total, parts: [], updatedAt: now };
      this.#pending.set(id, assembly);
    }
    if (index !== assembly.parts.length || total !== assembly.total) throw failure('SECURE_CHANNEL_FAILED');
    assembly.parts.push(bytes.subarray(headerSize));
    assembly.updatedAt = now;
    if (assembly.parts.length < total) return undefined;
    this.#pending.delete(id);
    return Buffer.concat(assembly.parts);
  }

  reset() { this.#pending.clear(); }
}

export async function fetchRtcIceServers(origin, connectionId, accessToken, signal) {
  if (signal?.aborted) throw failure('CLIENT_CLOSED');
  const url = new URL('/api/v1/turn/credentials', origin);
  url.searchParams.set('connection_id', connectionId);
  const timeout = AbortSignal.timeout(4000);
  let response;
  try {
    response = await fetch(url, { headers: { authorization: 'Bearer ' + accessToken, accept: 'application/json' },
      redirect: 'error', signal: signal ? AbortSignal.any([signal, timeout]) : timeout });
  } catch { throw failure(signal?.aborted ? 'CLIENT_CLOSED' : 'CONNECTION_FAILED'); }
  if (response.status === 404) { await response.body?.cancel(); return []; }
  if (response.status === 401 || response.status === 403) {
    await response.body?.cancel();
    throw failure('AUTH_INVALID');
  }
  if (!response.ok) { await response.body?.cancel(); throw failure('CONNECTION_FAILED'); }
  let data;
  try {
    const parts = [];
    let length = 0;
    for await (const chunk of response.body ?? []) {
      length += chunk.length;
      if (length > 64 * 1024) throw failure('INVALID_MESSAGE');
      parts.push(Buffer.from(chunk));
    }
    data = parseWire(Buffer.concat(parts, length));
  } catch (error) {
    if (signal?.aborted) throw failure('CLIENT_CLOSED');
    if (timeout.aborted) throw failure('CONNECTION_FAILED');
    if (error?.message === 'INVALID_MESSAGE') throw failure('INVALID_MESSAGE');
    throw failure('CONNECTION_FAILED');
  }
  if (!isObject(data) || (data.iceServers !== undefined && !Array.isArray(data.iceServers))) throw failure('INVALID_MESSAGE');
  const list = [];
  for (const row of (data.iceServers ?? []).slice(0, 32)) {
    if (!isObject(row)) continue;
    const urls = Array.isArray(row.urls) ? row.urls : [row.urls];
    for (const candidate of urls.slice(0, 16)) {
      if (!text(candidate, 1024) || !/^(?:stun|turns?):(?:\[[\da-f:]+\]|[a-z\d.-]+)(?::[1-9]\d{0,4})?(?:\?transport=(?:udp|tcp))?$/i.test(candidate)) continue;
      if (turnUrl.test(candidate) && (!text(row.username, 1024) || !text(row.credential, 1024))) continue;
      list.push(turnUrl.test(candidate) ? { urls: candidate, username: row.username, credential: row.credential } : { urls: candidate });
    }
  }
  return list;
}

function localNetwork(address) {
  if (typeof address !== 'string' || !address) return false;
  if (isIP(address) === 6) return /^(?:f[cd]|fe[89ab])/i.test(address) || address === '::1';
  if (isIP(address) !== 4) return address.endsWith('.local');
  const [a, b] = address.split('.').map(Number);
  return a === 10 || a === 127 || (a === 169 && b === 254) || (a === 192 && b === 168) || (a === 172 && b >= 16 && b <= 31);
}

function selectedPath(stats) {
  const rows = [...stats.values()];
  const id = rows.find(row => row.type === 'transport' && row.selectedCandidatePairId)?.selectedCandidatePairId;
  const pair = rows.find(row => row.type === 'candidate-pair' && row.id === id) ??
    rows.find(row => row.type === 'candidate-pair' && row.nominated === true && row.state === 'succeeded');
  if (!pair) return undefined;
  const local = rows.find(row => row.id === pair.localCandidateId && row.type === 'local-candidate');
  const remote = rows.find(row => row.id === pair.remoteCandidateId && row.type === 'remote-candidate');
  if (!local || !remote) return undefined;
  if (local.candidateType === 'relay' || remote.candidateType === 'relay') return 'turn';
  const direct = type => type === 'host' || type === 'prflx';
  return direct(local.candidateType) && direct(remote.candidateType) && localNetwork(local.address) && localNetwork(remote.address)
    ? 'lan' : 'p2p';
}

function stripRelay(sdp) {
  return sdp.split('\n').filter(line => !line.trimStart().startsWith('a=candidate:') || !relayCandidate.test(line)).join('\n');
}

export function openRtcData({ mode, iceServers, sendSignal, onData, onClose, signal, timeoutMs = 10000, preferredTransports }) {
  let peer;
  let channel;
  let closed = false;
  let timer;
  let offered = false;
  let answered = false;
  let answerPending = false;
  let signaling = Promise.resolve();
  const localCandidates = [];
  const remoteCandidates = [];
  const incoming = new RtcChunks();
  const outgoing = new RtcChunks();
  const turn = mode === 'turn';
  let resolve;
  let reject;
  const ready = new Promise((ok, fail) => { resolve = ok; reject = fail; });

  function finish(code, notify) {
    if (closed) return;
    closed = true;
    clearTimeout(timer);
    signal?.removeEventListener('abort', abort);
    incoming.reset();
    outgoing.reset();
    localCandidates.length = 0;
    remoteCandidates.length = 0;
    channel?.close();
    if (peer) void peer.close().catch(() => {});
    reject(failure(code));
    if (notify) onClose(code);
  }

  const abort = () => finish('CLIENT_CLOSED', true);
  const stop = () => finish('DIRECT_UNAVAILABLE', true);
  const sendIce = candidate => sendSignal('signal.ice', { candidate });

  async function verifyRoute() {
    for (let attempt = 0; attempt < 6 && !closed; attempt++) {
      const path = selectedPath(await peer.getStats());
      if (path) {
        const allowed = !preferredTransports || preferredTransports.includes(path) ||
          (path === 'lan' && preferredTransports.includes('p2p'));
        if ((path === 'turn') !== turn || !allowed) return stop();
        clearTimeout(timer);
        resolve(path);
        return;
      }
      await new Promise(ok => setTimeout(ok, 50));
    }
    if (!closed) stop();
  }

  async function start() {
    if (signal?.aborted) { abort(); return; }
    signal?.addEventListener('abort', abort, { once: true });
    timer = setTimeout(stop, Math.min(Math.max(timeoutMs, 3000), 15000));
    timer.unref();
    const servers = iceServers.filter(row => turn || !turnUrl.test(row.urls));
    if (turn && !servers.some(row => turnUrl.test(row.urls))) throw failure('DIRECT_UNAVAILABLE');
    const { RTCPeerConnection } = require('werift');
    peer = new RTCPeerConnection({ bundlePolicy: 'max-bundle', iceServers: servers,
      iceTransportPolicy: turn ? 'relay' : 'all', iceStunGatherTimeout: 3, iceUseLinkLocalAddress: false });
    channel = peer.createDataChannel('dsh', { ordered: true });
    channel.onopen = () => { void verifyRoute().catch(stop); };
    channel.onclose = stop;
    channel.onerror = stop;
    channel.onmessage = event => {
      if (closed) return;
      try {
        if (typeof event.data === 'string') throw failure('SECURE_CHANNEL_FAILED');
        const data = incoming.accept(Buffer.from(event.data));
        if (data) onData(data);
      } catch { finish('SECURE_CHANNEL_FAILED', true); }
    };
    peer.onconnectionstatechange = () => {
      if (['failed', 'closed'].includes(peer.connectionState)) stop();
    };
    peer.onicecandidate = ({ candidate }) => {
      if (!candidate || closed) return;
      const value = candidate.toJSON();
      if ((turn && !relayCandidate.test(value.candidate)) || (!turn && relayCandidate.test(value.candidate))) return;
      try {
        if (offered) sendIce(value);
        else if (localCandidates.length < 128) localCandidates.push(value);
      } catch { stop(); }
    };
    const offer = await peer.createOffer();
    if (closed) return;
    // Werift's setLocalDescription waits for gathering; queue it before the answer but trickle candidates immediately.
    const setting = peer.setLocalDescription(offer);
    void setting.catch(stop);
    sendSignal('signal.offer', { sdp: turn ? offer.sdp : stripRelay(offer.sdp) });
    offered = true;
    for (const candidate of localCandidates.splice(0)) sendIce(candidate);
    await setting;
  }

  function receiveSignal(type, payload) {
    if (closed) return;
    if (type === 'signal.answer') {
      if (answerPending) return;
      if (typeof payload.sdp !== 'string' || !payload.sdp || Buffer.byteLength(payload.sdp) > 64 * 1024) {
        finish('SECURE_CHANNEL_FAILED', true);
        return;
      }
      answerPending = true;
      signaling = signaling.then(async () => {
        if (closed) return;
        await peer.setRemoteDescription({ type: 'answer', sdp: turn ? payload.sdp : stripRelay(payload.sdp) });
        if (closed) return;
        answered = true;
        for (const row of remoteCandidates.splice(0)) await peer.addIceCandidate(row).catch(() => {});
      }).catch(stop);
      return;
    }
    if (type === 'signal.ice') {
      const candidate = payload.candidate;
      if (!isObject(candidate) || typeof candidate.candidate !== 'string' || candidate.candidate.length > 8192 ||
          (candidate.sdpMid != null && !text(candidate.sdpMid, 256)) ||
          (candidate.sdpMLineIndex != null && (!Number.isSafeInteger(candidate.sdpMLineIndex) || candidate.sdpMLineIndex < 0))) {
        finish('SECURE_CHANNEL_FAILED', true);
        return;
      }
      if (!candidate.candidate || (!turn && relayCandidate.test(candidate.candidate))) return;
      if (!answered) {
        if (remoteCandidates.length >= 128) { finish('SECURE_CHANNEL_FAILED', true); return; }
        remoteCandidates.push(candidate);
      } else {
        signaling = signaling.then(() => closed ? undefined : peer.addIceCandidate(candidate)).catch(() => {});
      }
    }
  }

  function send(bytes) {
    if (closed || channel?.readyState !== 'open') throw failure('DIRECT_UNAVAILABLE');
    if (channel.bufferedAmount + bytes.length > maxMessage * 2) throw failure('DIRECT_UNAVAILABLE');
    for (const chunk of outgoing.split(bytes)) channel.send(chunk);
  }

  queueMicrotask(() => { if (!closed) void start().catch(stop); });
  return { ready, receiveSignal, send, close: () => finish('CLIENT_CLOSED', false) };
}
