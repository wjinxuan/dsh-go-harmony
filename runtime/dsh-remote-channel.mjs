// DSH Remote v1 protocol derived from ds-harness-remote (MIT).
// Copyright (c) 2026 DSH Remote contributors. See THIRD_PARTY_NOTICES.md.
import { EventEmitter } from 'node:events';
import { WebSocket } from 'ws';
import { b64, bytes, envelope, frame, Fragments, isObject, maxMessage, NoiseInitiator, noisePrologue, text } from './dsh-remote-wire.mjs';
import { fetchRtcIceServers, openRtcData } from './dsh-remote-rtc.mjs';

const CONTROL_LIMIT = 64 * 1024;
const RELAY_LIMIT = 1024 * 1024;
const relayCapabilities = ['transport.relay', 'transport.relay.attach'];
const directModes = { direct: ['lan', 'p2p'], turn: ['turn'], relay: [] };
const controlTypes = new Set(['hello.ack', 'connect.accepted', 'connect.rejected', 'secure.handshake', 'relay', 'ping',
  'pong', 'error', 'signal.answer', 'signal.ice', 'transport.selected']);
const dataTypes = new Set(['relay.ready', 'relay.detach', 'relay', 'secure.handshake', 'ping', 'pong', 'error']);
const rpcTypes = new Set(['rpc.response', 'rpc.error', 'event']);
const validCode = value => typeof value === 'string' && /^[A-Z][A-Z0-9_]{1,79}$/.test(value);
const positive = (value, max) => Number.isSafeInteger(value) && value > 0 && value <= max;

export class RemoteFailure extends Error {
  constructor(code, details) {
    super(validCode(code) ? code : 'RELAY_FAILED');
    this.code = this.message;
    this.details = details;
  }
}

export async function openDshRemoteChannel(options) {
  const modes = options.direct === false ? ['relay'] : ['direct', 'turn', 'relay'];
  for (const mode of modes) {
    try { return await openAttempt(options, mode); }
    catch (error) { if (error.code !== 'DIRECT_UNAVAILABLE' || mode === 'relay') throw error; }
  }
}

async function openAttempt(options, mode) {
  const channel = new DshRemoteChannel({ ...options, mode });
  try {
    await channel.ready;
    const info = await channel.rpc('harness.transport.describe', {}, 10000);
    const caps = info?.capabilities;
    if (!Array.isArray(caps) || caps.length > 128 || new Set(caps).size !== caps.length ||
        caps.some(value => !text(value, 256)) || !caps.includes('harness.remote.v3') || caps.includes('harness.remote.v1')) {
      throw new RemoteFailure('HARNESS_VERSION_INCOMPATIBLE');
    }
    if (caps.includes('remote.history.compact.v1')) {
      const history = await channel.rpc('remote.history.configure', { compact: false }, 10000);
      if (history?.compact !== false) throw new RemoteFailure('INVALID_MESSAGE');
    }
    channel.capabilities = new Set(caps);
    return channel;
  } catch (error) {
    channel.close();
    throw error;
  }
}

class DshRemoteChannel extends EventEmitter {
  #control;
  #data;
  #rtc;
  #rtcLifetime;
  #controlLimit = CONTROL_LIMIT;
  #relayLimit = RELAY_LIMIT;
  #phase = 'hello';
  #connection;
  #negotiated;
  #relayEpoch;
  #noise;
  #fragments = new Fragments();
  #pending = new Map();
  #done = false;
  #resolve;
  #reject;
  #opening;
  #watchdog;
  #lastControl = Date.now();
  #lastData = Date.now();
  #lastRpc = Date.now();
  #probe = false;
  #mode;
  #offered;
  #preferred = [];
  #rtcTimeout = 8000;
  #receivedDirect = [];
  #receivedDirectBytes = 0;

  constructor({ origin, device, identity, host, accessToken, version, signal, mode }) {
    super();
    this.origin = origin;
    this.device = device;
    this.identity = identity;
    this.host = host;
    this.signal = signal;
    this.#mode = mode;
    this.transport = 'relay';
    this.#offered = [...directModes[mode].map(value => 'transport.' + value), ...relayCapabilities];
    this.ready = new Promise((resolve, reject) => {
      this.#resolve = resolve;
      this.#reject = reject;
    });
    const address = new URL('/ws/v1/connect', origin);
    address.protocol = address.protocol === 'https:' ? 'wss:' : 'ws:';
    this.#control = this.#socket(address, false);
    this.#control.once('open', () => {
      this.#send(this.#control, 'hello', { role: 'client', deviceId: device.deviceId, accessToken,
        protocols: [1], capabilities: this.#offered, clientVersion: version });
    });
    this.iceServers = (connection, rtcSignal) => fetchRtcIceServers(origin, connection, accessToken, rtcSignal);
    this.#opening = setTimeout(() => this.close('CONNECTION_FAILED'), 20000);
    this.#opening.unref();
    this.abort = () => this.close('CLIENT_CLOSED');
    if (signal?.aborted) this.abort();
    else signal?.addEventListener('abort', this.abort, { once: true });
  }

  #socket(url, data) {
    const socket = new WebSocket(url, { maxPayload: RELAY_LIMIT, perMessageDeflate: false, handshakeTimeout: 10000 });
    socket.on('error', () => this.close('CONNECTION_FAILED'));
    socket.on('close', (code, reason) => {
      const value = reason.toString();
      this.close(code === 4003 ? 'CONNECTION_REPLACED' : validCode(value) ? value : 'CONNECTION_FAILED');
    });
    socket.on('message', (raw, binary) => {
      if (this.#done) return;
      try {
        if (binary || raw.length > this.#relayLimit) throw new Error('INVALID_MESSAGE');
        const value = envelope(raw, data ? dataTypes : controlTypes);
        if (!data && value.type !== 'relay' && raw.length > this.#controlLimit) throw new Error('FRAME_TOO_LARGE');
        if (data) this.#lastData = Date.now();
        else this.#lastControl = Date.now();
        this.#receive(socket, value.type, value.payload, data);
      } catch (error) { this.close(validCode(error?.message) ? error.message : 'SECURE_CHANNEL_FAILED'); }
    });
    return socket;
  }

  #send(socket, type, payload) {
    if (this.#done || socket.readyState !== WebSocket.OPEN) throw new RemoteFailure('CONNECTION_FAILED');
    const encoded = JSON.stringify(frame(type, payload));
    const limit = socket === this.#data || type === 'relay' ? this.#relayLimit : this.#controlLimit;
    if (Buffer.byteLength(encoded) > limit) throw new RemoteFailure('FRAME_TOO_LARGE');
    if (socket.bufferedAmount > maxMessage * 2) throw new RemoteFailure('SLOW_CONSUMER');
    socket.send(encoded, error => { if (error) this.close('CONNECTION_FAILED'); });
  }

  #receive(socket, type, payload, data) {
    if (type === 'ping' || type === 'pong') {
      if (!text(payload.nonce, 256)) throw new Error('INVALID_MESSAGE');
      if (type === 'ping') this.#send(socket, 'pong', { nonce: payload.nonce });
      return;
    }
    if (type === 'error' || type === 'connect.rejected') {
      if (!data && payload.connectionId && this.#connection && payload.connectionId !== this.#connection) return;
      throw new RemoteFailure(validCode(payload.code) ? payload.code : 'CONNECTION_REJECTED');
    }
    if (type === 'hello.ack' && this.#phase === 'hello' && !data) {
      const caps = payload.capabilities ?? ['transport.relay'];
      if (payload.protocol !== 1 || !text(payload.connectionSessionId) || !text(payload.serverVersion, 256) ||
          !positive(payload.heartbeatIntervalMs, 120000) || !positive(payload.maxControlFrameBytes, CONTROL_LIMIT) ||
          !positive(payload.maxRelayFrameBytes, RELAY_LIMIT) || !Array.isArray(caps) || new Set(caps).size !== caps.length ||
          !caps.includes('transport.relay') || caps.some(cap => !this.#offered.includes(cap)) ||
          (payload.webrtcEnabled !== undefined && typeof payload.webrtcEnabled !== 'boolean') ||
          (payload.webrtcFallbackTimeoutMs !== undefined && !positive(payload.webrtcFallbackTimeoutMs, Number.MAX_SAFE_INTEGER))) {
        throw new Error('INVALID_MESSAGE');
      }
      this.#controlLimit = payload.maxControlFrameBytes;
      this.#relayLimit = payload.maxRelayFrameBytes;
      this.#negotiated = caps;
      this.#preferred = payload.webrtcEnabled === false ? [] : directModes[this.#mode].filter(mode => caps.includes('transport.' + mode));
      if (this.#mode === 'turn' && this.#preferred.length === 0) throw new RemoteFailure('DIRECT_UNAVAILABLE');
      this.#rtcTimeout = Math.min(15000, Math.max(8000, payload.webrtcFallbackTimeoutMs ?? 0));
      this.#phase = 'connect';
      this.#send(this.#control, 'connect.request', { hostDeviceId: this.host.deviceId, preferredTransports: [...this.#preferred, 'relay'] });
      const interval = payload.heartbeatIntervalMs;
      this.#watchdog = setInterval(() => {
        const now = Date.now();
        if (now - this.#lastControl > interval * 3 || (this.#data && now - this.#lastData > interval * 3)) {
          this.close('CONNECTION_FAILED');
        } else if (this.#phase === 'ready' && now - this.#lastRpc > 25000 && !this.#probe) {
          this.#probe = true;
          this.rpc('harness.transport.describe', {}, 10000).catch(() => this.close('CONNECTION_FAILED'))
            .finally(() => { this.#probe = false; });
        }
      }, interval);
      this.#watchdog.unref();
      return;
    }
    if (type === 'connect.accepted' && this.#phase === 'connect' && !data) {
      if (!text(payload.connectionId)) throw new Error('INVALID_MESSAGE');
      this.#connection = payload.connectionId;
      if (this.#preferred.length > 0) {
        this.#phase = 'rtc';
        clearTimeout(this.#opening);
        this.#opening = setTimeout(() => this.close('DIRECT_UNAVAILABLE'), this.#rtcTimeout + 11000);
        this.#opening.unref();
        void this.#openRtc().catch(error => this.close(validCode(error?.code) ? error.code : 'DIRECT_UNAVAILABLE'));
        return;
      }
      if (payload.relayEndpoint === undefined && payload.relayTicket === undefined &&
          payload.relayEpoch === undefined && payload.relayNodeId === undefined) {
        this.#handshake();
        return;
      }
      if (!this.#negotiated.includes('transport.relay.attach') || !text(payload.relayEndpoint, 2048) ||
          !text(payload.relayTicket, 8192) || !text(payload.relayNodeId) || !positive(payload.relayEpoch, Number.MAX_SAFE_INTEGER)) {
        throw new Error('INVALID_MESSAGE');
      }
      const address = new URL(payload.relayEndpoint);
      const wsOnLocal = address.protocol === 'ws:' && new URL(this.origin).protocol === 'http:' &&
        address.hostname === new URL(this.origin).hostname;
      if ((address.protocol !== 'wss:' && !wsOnLocal) || address.username || address.password || address.hash) {
        throw new Error('INVALID_MESSAGE');
      }
      this.#relayEpoch = payload.relayEpoch;
      this.#phase = 'attach';
      this.#lastData = Date.now();
      this.#data = this.#socket(address, true);
      this.#data.once('open', () => this.#send(this.#data, 'relay.attach', { connectionId: this.#connection,
        deviceId: this.device.deviceId, peerDeviceId: this.host.deviceId, ticket: payload.relayTicket }));
      return;
    }
    if (type === 'relay.ready' && this.#phase === 'attach' && data) {
      if (payload.connectionId !== this.#connection || payload.epoch !== this.#relayEpoch) throw new Error('INVALID_MESSAGE');
      this.#send(this.#control, 'transport.selected', { connectionId: this.#connection,
        targetDeviceId: this.host.deviceId, transport: 'relay' });
      this.#handshake();
      return;
    }
    if (type === 'relay.detach' && data) throw new Error('CONNECTION_FAILED');
    if (type === 'secure.handshake' && this.#phase === 'handshake' && (!this.#rtc || !data)) {
      this.#requirePeer(payload);
      if (payload.step !== 2 || this.#noise.finish(bytes(payload.data, undefined, 65535)).length !== 0) {
        throw new Error('SECURE_CHANNEL_FAILED');
      }
      this.#phase = 'ready';
      clearTimeout(this.#opening);
      for (const chunk of this.#receivedDirect) this.#receiveDirect(chunk);
      this.#receivedDirect = [];
      this.#receivedDirectBytes = 0;
      this.#resolve();
      return;
    }
    if (type === 'relay' && this.#phase === 'ready') {
      if (this.#rtc) return;
      if (this.#data && !data) return;
      this.#requirePeer(payload);
      const content = this.#fragments.add(this.#noise.decrypt(payload.counter, payload.ciphertext));
      if (content) this.#receiveRpc(content);
      return;
    }
    if (['signal.answer', 'signal.ice', 'transport.selected'].includes(type) && !data) {
      if (this.#phase !== 'rtc' || !this.#rtc || payload.connectionId !== this.#connection ||
          payload.targetDeviceId !== this.device.deviceId) return;
      if (type === 'signal.answer' && (typeof payload.sdp !== 'string' || !payload.sdp.length ||
          payload.sdp.length > this.#controlLimit || /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/u.test(payload.sdp)) ||
          type === 'signal.ice' && !isObject(payload.candidate)) throw new Error('INVALID_MESSAGE');
      if (type !== 'transport.selected') this.#rtc.receiveSignal(type, payload);
      return;
    }
    throw new Error('INVALID_MESSAGE');
  }

  #requirePeer(payload) {
    if (payload.connectionId !== this.#connection || payload.targetDeviceId !== this.device.deviceId) {
      throw new Error('PEER_IDENTITY_MISMATCH');
    }
  }

  async #openRtc() {
    const lifetime = new AbortController();
    this.#rtcLifetime = lifetime;
    let servers = [];
    try { servers = await this.iceServers(this.#connection, AbortSignal.any([lifetime.signal, AbortSignal.timeout(10000)])); }
    catch (error) {
      if (this.#done) return;
      if (!['CONNECTION_FAILED', 'CLIENT_CLOSED'].includes(error.code)) throw error;
    }
    if (this.#done) return;
    const rtc = openRtcData({ mode: this.#mode, iceServers: servers, preferredTransports: this.#preferred,
      signal: lifetime.signal, timeoutMs: this.#rtcTimeout,
      sendSignal: (type, payload) => this.#send(this.#control, type, { ...payload, connectionId: this.#connection,
        targetDeviceId: this.host.deviceId }),
      onData: data => {
        if (this.#done) return;
        try { this.#receiveDirect(data); }
        catch { this.close('SECURE_CHANNEL_FAILED'); }
      },
      onClose: code => this.close(code === 'SECURE_CHANNEL_FAILED' ? code :
        this.#phase === 'rtc' ? 'DIRECT_UNAVAILABLE' : 'CONNECTION_FAILED') });
    this.#rtc = rtc;
    const selected = await rtc.ready;
    if (this.#done) return;
    const wire = selected === 'lan' && !this.#preferred.includes('lan') ? 'p2p' : selected;
    if (!this.#preferred.includes(wire)) throw new RemoteFailure('DIRECT_UNAVAILABLE');
    this.transport = selected;
    this.#send(this.#control, 'transport.selected', { connectionId: this.#connection,
      targetDeviceId: this.host.deviceId, transport: wire });
    clearTimeout(this.#opening);
    this.#opening = setTimeout(() => this.close('CONNECTION_FAILED'), 10000);
    this.#opening.unref();
    this.#handshake();
  }

  #receiveDirect(data) {
    if (!Buffer.isBuffer(data) || data.length > 65535) throw new Error('SECURE_CHANNEL_FAILED');
    if (this.#phase !== 'ready') {
      if (this.#phase !== 'handshake' || this.#receivedDirect.length >= 128 ||
          this.#receivedDirectBytes + data.length > maxMessage) throw new Error('SECURE_CHANNEL_FAILED');
      this.#receivedDirect.push(data);
      this.#receivedDirectBytes += data.length;
      return;
    }
    const content = this.#fragments.add(this.#noise.decryptBytes(data));
    if (content) this.#receiveRpc(content);
  }

  #handshake() {
    this.#phase = 'handshake';
    this.#noise = new NoiseInitiator(this.identity, this.host.identityKey,
      noisePrologue(this.#connection, this.host.deviceId, this.device.deviceId));
    this.#send(this.#control, 'secure.handshake', { connectionId: this.#connection, targetDeviceId: this.host.deviceId,
      step: 1, data: b64(this.#noise.start()) });
  }

  #receiveRpc(content) {
    this.#lastRpc = Date.now();
    const { type, payload } = envelope(content, rpcTypes);
    if (type === 'event') {
      if (!text(payload.event, 256)) throw new Error('INVALID_MESSAGE');
      this.emit('event', payload.event, payload.data);
      return;
    }
    if (!text(payload.requestId)) throw new Error('INVALID_MESSAGE');
    const pending = this.#pending.get(payload.requestId);
    if (!pending) return;
    if (type === 'rpc.error' && (!validCode(payload.code) || !text(payload.message, 4096))) throw new Error('INVALID_MESSAGE');
    this.#pending.delete(payload.requestId);
    clearTimeout(pending.timer);
    if (type === 'rpc.error') pending.reject(new RemoteFailure(payload.code, payload.details));
    else pending.resolve(payload.result);
  }

  rpc(method, params, timeout = 65000) {
    if (this.#phase !== 'ready' || this.#done) return Promise.reject(new RemoteFailure('CONNECTION_FAILED'));
    if (this.#pending.size >= 128) return Promise.reject(new RemoteFailure('RATE_LIMITED'));
    const request = frame('rpc.request', { method, params });
    const raw = Buffer.from(JSON.stringify(request));
    if (raw.length > maxMessage) return Promise.reject(new RemoteFailure('FRAME_TOO_LARGE'));
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.#pending.delete(request.id);
        reject(new RemoteFailure('RPC_TIMEOUT'));
      }, timeout);
      timer.unref();
      this.#pending.set(request.id, { resolve, reject, timer });
      try {
        for (const piece of this.#fragments.split(raw)) {
          if (this.#rtc) this.#rtc.send(this.#noise.encryptBytes(piece));
          else this.#send(this.#data ?? this.#control, 'relay', { connectionId: this.#connection,
            targetDeviceId: this.host.deviceId, ...this.#noise.encrypt(piece) });
        }
      } catch (error) { this.close(validCode(error?.message) ? error.message : 'SECURE_CHANNEL_FAILED'); }
    });
  }

  close(code = 'CLIENT_CLOSED') {
    if (this.#done) return;
    this.#done = true;
    clearTimeout(this.#opening);
    clearInterval(this.#watchdog);
    this.signal?.removeEventListener('abort', this.abort);
    this.#noise?.destroy();
    this.#fragments.reset();
    this.#receivedDirect = [];
    this.#receivedDirectBytes = 0;
    const reason = new RemoteFailure(code);
    this.#reject(reason);
    for (const { timer, reject } of this.#pending.values()) {
      clearTimeout(timer);
      reject(reason);
    }
    this.#pending.clear();
    this.#rtcLifetime?.abort();
    this.#rtc?.close();
    this.#data?.terminate();
    this.#control?.terminate();
    this.emit('closed', reason);
  }
}
