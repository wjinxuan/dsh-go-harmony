// DSH Remote v1 tunnel derived from ds-harness-remote (MIT).
// Copyright (c) 2026 DSH Remote contributors. See THIRD_PARTY_NOTICES.md.
import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { WebSocket, WebSocketServer } from 'ws';
import { RelayAccounts, normalizeRemoteOrigin, readBounded } from './dsh-remote-account.mjs';
import { RemoteFailure, openDshRemoteChannel } from './dsh-remote-channel.mjs';
import { isObject, parseWire, text } from './dsh-remote-wire.mjs';

const directLimit = 2 * 1024 * 1024;
const transferLimit = 32 * 1024 * 1024;
const chunkSize = 512 * 1024;
const methodName = /^\$?[A-Za-z][A-Za-z0-9-]*(?:\/[A-Za-z][A-Za-z0-9-]*)+$/;
function equal(left, right) {
  if (typeof left !== 'string') return false;
  const actual = Buffer.from(left);
  const expected = Buffer.from(right);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function json(response, status, value) {
  if (!response.destroyed) response.writeHead(status, { 'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store' }).end(JSON.stringify(value));
}

function errorCode(error) {
  return error?.code && /^[A-Z][A-Z0-9_]{1,79}$/.test(error.code) ? error.code :
    error?.message === 'INVALID_MESSAGE' ? error.message : 'RELAY_FAILED';
}

function wireError(error) {
  return { code: 'relay/' + errorCode(error).toLowerCase().replaceAll('_', '-'), message: 'DSHarness Remote 请求失败。', details: {} };
}

async function readTransfer(channel, descriptor, id, current = () => true) {
  const { totalBytes, totalChunks } = descriptor;
  if (!Number.isSafeInteger(totalBytes) || totalBytes <= 0 || totalBytes > transferLimit ||
      totalChunks !== Math.ceil(totalBytes / chunkSize) || !text(id)) throw new RemoteFailure('FRAME_TOO_LARGE');
  const parts = [];
  for (let index = 0; index < totalChunks; index++) {
    if (!current()) throw new RemoteFailure('CLIENT_CLOSED');
    const result = await channel.rpc('harness.remote.transfer.read', { transferId: id, index });
    if (result?.transferId !== id || result.index !== index || typeof result.data !== 'string') {
      throw new RemoteFailure('INVALID_MESSAGE');
    }
    const bytes = Buffer.from(result.data, 'base64');
    if (bytes.length !== Math.min(chunkSize, totalBytes - index * chunkSize) || bytes.toString('base64') !== result.data) {
      throw new RemoteFailure('INVALID_MESSAGE');
    }
    parts.push(bytes);
  }
  return parseWire(Buffer.concat(parts, totalBytes));
}

function closeTransfer(channel, id) {
  return channel.rpc('harness.remote.transfer.close', { transferId: id }, 5000).catch(() => {});
}

async function callRemote(channel, method, payload) {
  const request = { endpoint: method, payload };
  const raw = Buffer.from(JSON.stringify(request));
  if (raw.length <= directLimit) return channel.rpc('harness.remote.call', request);
  if (raw.length > transferLimit || !channel.capabilities.has('harness.remote.transfer.v1')) {
    throw new RemoteFailure('FRAME_TOO_LARGE');
  }
  const id = randomUUID();
  const totalChunks = Math.ceil(raw.length / chunkSize);
  try {
    await channel.rpc('harness.remote.transfer.open', { transferId: id, totalBytes: raw.length, totalChunks });
    for (let index = 0; index < totalChunks; index++) {
      await channel.rpc('harness.remote.transfer.chunk', { transferId: id, index,
        data: raw.subarray(index * chunkSize, (index + 1) * chunkSize).toString('base64') });
    }
    const committed = await channel.rpc('harness.remote.transfer.commit', { transferId: id });
    if (committed?.kind === 'inline') return committed.response;
    if (committed?.kind !== 'chunked' || committed.transferId !== id) throw new RemoteFailure('INVALID_MESSAGE');
    return await readTransfer(channel, committed, id);
  } finally { void closeTransfer(channel, id); }
}

async function loopbackBridge(channel, onClose) {
  const token = randomBytes(32).toString('base64url');
  const cookie = 'dsh-auth-relay=' + randomBytes(32).toString('base64url');
  let host;
  let socket;
  let closed = false;
  const streams = new Map();
  const http = createServer((request, response) => {
    void receiveRequest(request, response).catch(() => {
      if (!response.headersSent) json(response, 400, {});
      else response.destroy();
    });
  });
  const wss = new WebSocketServer({ noServer: true, maxPayload: 1024 * 1024, perMessageDeflate: false });
  const authenticated = request => request.headers.host === host && request.socket.remoteAddress === '127.0.0.1' &&
    equal(request.headers.cookie, cookie);
  const send = value => {
    if (socket?.readyState !== WebSocket.OPEN) return;
    if (socket.bufferedAmount > transferLimit) { close(); return; }
    socket.send(JSON.stringify(value), error => { if (error) close(); });
  };
  const expire = setTimeout(() => close(), 30000);
  expire.unref();

  async function receiveRequest(request, response) {
    if (request.headers.host !== host || request.socket.remoteAddress !== '127.0.0.1') return json(response, 403, {});
    if (request.headers.origin !== undefined && request.headers.origin !== 'http://' + host) return json(response, 403, {});
    const url = new URL(request.url, 'http://' + host);
    if (request.method === 'GET' && url.pathname === '/' && equal(url.searchParams.get('token'), token)) {
      response.writeHead(302, { location: '/', 'set-cookie': cookie + '; HttpOnly; SameSite=Strict; Path=/',
        'cache-control': 'no-store' }).end();
      return;
    }
    if (!authenticated(request)) return json(response, 401, {});
    const method = url.pathname.slice('/api/'.length);
    if (request.method !== 'POST' || !url.pathname.startsWith('/api/') || url.search ||
        !methodName.test(method) || method === 'session/uploadFileBinary' || method === 'fileUploads/upload') {
      return json(response, 404, {});
    }
    if (method.startsWith('account/')) return json(response, 404, {});
    const body = parseWire(await readBounded(request, transferLimit));
    if (body?.type !== 'client-request' || !text(body.rpcId) || body.method !== method || !isObject(body.payload?.args)) {
      throw new RemoteFailure('INVALID_MESSAGE');
    }
    let result;
    try {
      result = await callRemote(channel, method, body.payload);
      if (result?.ok !== true && (result?.ok !== false || !isObject(result.error))) throw new RemoteFailure('INVALID_MESSAGE');
    } catch (error) { result = { ok: false, error: wireError(error) }; }
    json(response, 200, { type: 'server-response', rpcId: body.rpcId, result });
  }

  function releaseStream(id) {
    if (streams.delete(id)) void channel.rpc('harness.remote.stream.close', { streamId: id }, 5000).catch(() => {});
  }

  function streamError(id, error) {
    releaseStream(id);
    send({ type: 'error', streamId: id, error: wireError(error) });
  }

  function openStream(value) {
    const id = value.streamId;
    if (value.endpoint === 'terminal/attach') {
      send({ type: 'error', streamId: id, error: { code: 'gateway/method-unavailable', message: 'Use terminal/follow.' } });
      return;
    }
    if (streams.size >= 128 || streams.has(id) || typeof value.endpoint !== 'string' ||
        (value.endpoint !== '$events' && !methodName.test(value.endpoint)) || !isObject(value.payload?.args)) {
      throw new RemoteFailure('INVALID_MESSAGE');
    }
    const stream = { tail: Promise.resolve() };
    streams.set(id, stream);
    const params = { streamId: id, endpoint: value.endpoint, payload: value.payload };
    if (channel.capabilities.has('harness.remote.stream.transfer.v1')) params.transferFrames = true;
    void channel.rpc('harness.remote.stream.open', params, 15000).catch(error => {
      if (streams.get(id) === stream) streamError(id, error);
    });
  }

  channel.on('event', (event, data) => {
    if (!['harness.remote.frame', 'harness.remote.stream.closed'].includes(event) || !isObject(data)) return;
    const id = data.streamId;
    const stream = streams.get(id);
    if (!stream) return;
    stream.tail = stream.tail.then(async () => {
      if (streams.get(id) !== stream) return;
      if (event === 'harness.remote.stream.closed') {
        streams.delete(id);
        if (data.reason === 'peer-disconnected') { close(); return; }
        if (data.reason === 'failed') {
          send({ type: 'error', streamId: id, error: isObject(data.failure) ? data.failure : wireError({}) });
        } else send({ type: 'end', streamId: id });
        return;
      }
      if (data.hasValue !== true) return;
      let received = data;
      if (data.transfer) {
        const descriptor = data.transfer;
        const transferId = descriptor.transferId;
        if (descriptor.kind !== 'chunked' || Object.hasOwn(data, 'value') ||
            !channel.capabilities.has('harness.remote.stream.transfer.v1')) throw new RemoteFailure('INVALID_MESSAGE');
        try {
          received = await readTransfer(channel, descriptor, transferId, () => streams.get(id) === stream);
          if (received?.streamId !== id || received.hasValue !== true || received.transfer) throw new RemoteFailure('INVALID_MESSAGE');
        } finally { if (text(transferId)) await closeTransfer(channel, transferId); }
      }
      if (streams.get(id) === stream) send({ type: 'item', streamId: id, value: received.value });
    }).catch(error => { if (streams.get(id) === stream) streamError(id, error); });
  });

  http.on('upgrade', (request, connection, head) => {
    const origin = request.headers.origin;
    if (!authenticated(request) || request.url !== '/api/remote.mux' || socket ||
        (origin !== undefined && origin !== 'http://' + host && origin !== 'http://127.0.0.1')) {
      connection.destroy();
      return;
    }
    wss.handleUpgrade(request, connection, head, accepted => {
      socket = accepted;
      clearTimeout(expire);
      socket.on('error', () => close());
      socket.on('close', () => close());
      socket.on('message', (raw, binary) => {
        try {
          const value = parseWire(raw);
          if (binary || !text(value?.streamId)) throw new Error();
          if (value.type === 'open') openStream(value);
          else if (value.type === 'cancel') releaseStream(value.streamId);
          else streamError(value.streamId, new RemoteFailure('METHOD_NOT_ALLOWED'));
        } catch { close(); }
      });
    });
  });

  function close() {
    if (closed) return;
    closed = true;
    clearTimeout(expire);
    streams.clear();
    channel.close();
    socket?.terminate();
    wss.close();
    http.closeAllConnections();
    http.close();
    onClose();
  }
  channel.once('closed', close);
  try {
    await new Promise((resolve, reject) => {
      http.once('error', reject);
      http.listen(0, '127.0.0.1', () => {
        http.removeListener('error', reject);
        if (closed) { http.close(); reject(new RemoteFailure('CONNECTION_FAILED')); return; }
        resolve();
      });
    });
    host = '127.0.0.1:' + http.address().port;
    return { launchUrl: 'http://' + host + '/?token=' + token, close };
  } catch (error) { close(); throw error; }
}

export function createDshRemoteHandler(dataDir) {
  const lifetime = new AbortController();
  const accounts = new RelayAccounts(dataDir, lifetime.signal);
  const bridges = new Map();
  let queue = Promise.resolve();
  let opening = 0;

  async function route(path, body, signal) {
    if (signal.aborted) throw new RemoteFailure('CLIENT_CLOSED');
    if (path === '/relay/disconnect') {
      bridges.get(body.id)?.close();
      return {};
    }
    const origin = normalizeRemoteOrigin(body.origin);
    switch (path) {
      case '/relay/hosts': {
        const state = await accounts.hosts(origin);
        return { origin, ...state, hosts: state.hosts.map(host => ({ ...host,
          scope: 'relay-' + createHash('sha256').update(origin + '\0' + host.id).digest('hex') })) };
      }
      case '/relay/providers': return accounts.providers(origin);
      case '/relay/password': return accounts.passwordLogin(origin, body.email, body.password);
      case '/relay/browser/start': return accounts.browserStart(origin, body.provider);
      case '/relay/browser/status': return accounts.browserStatus(body.id);
      case '/relay/pair/resolve': return accounts.pairResolve(body.scan, origin);
      case '/relay/pair/claim': return accounts.pairClaim(body.id);
      case '/relay/pair/status': return accounts.pairStatus(body.id);
      case '/relay/cancel': return accounts.cancel(body.id);
      case '/relay/logout': {
        for (const bridge of bridges.values()) if (bridge.origin === origin) bridge.close();
        return accounts.logout(origin);
      }
      case '/relay/peer': return accounts.peer(origin, body.hostId);
      case '/relay/connect': {
        if (bridges.size + opening >= 4) throw new RemoteFailure('RATE_LIMITED');
        opening++;
        const id = randomUUID();
        let channel;
        try {
          const peer = await accounts.peer(origin, body.hostId, body.fingerprint ?? '');
          const options = { version: '1.0.0', signal, direct: body.direct !== false };
          try { channel = await openDshRemoteChannel({ ...peer, ...options }); }
          catch (error) {
            if (!['AUTH_INVALID', 'TOKEN_EXPIRED'].includes(error.code)) throw error;
            channel = await openDshRemoteChannel({ ...await accounts.peer(origin, body.hostId, body.fingerprint ?? '', true),
              ...options });
          }
          if (signal.aborted) throw new RemoteFailure('CLIENT_CLOSED');
          const bridge = await loopbackBridge(channel, () => bridges.delete(id));
          bridges.set(id, { origin, close: bridge.close });
          const scope = 'relay-' + createHash('sha256').update(origin + '\0' + peer.host.deviceId).digest('hex');
          return { id, launchUrl: bridge.launchUrl, name: peer.host.name.replace(/[\u202a-\u202e\u2066-\u2069]/g, ''),
            scope, transport: channel.transport };
        } catch (error) { channel?.close(); throw error; }
        finally { opening--; }
      }
      default: throw new RemoteFailure('METHOD_NOT_ALLOWED');
    }
  }

  function handle(request, response) {
    const path = request.url ?? '';
    if (path !== '/relay' && !path.startsWith('/relay/')) return false;
    if (request.method !== 'POST') { json(response, 405, {}); return true; }
    void (async () => {
      try {
        const body = parseWire(await readBounded(request, 16 * 1024));
        if (!isObject(body)) throw new RemoteFailure('INVALID_MESSAGE');
        // A single writer prevents simultaneous refresh-token rotation and credential/pin replacement.
        const cancellation = new AbortController();
        const abort = () => cancellation.abort();
        response.once('close', abort);
        const signal = AbortSignal.any([lifetime.signal, cancellation.signal]);
        const operation = queue.then(() => route(path, body, signal));
        queue = operation.catch(() => {});
        try { json(response, 200, { ok: true, value: await operation }); }
        finally { response.off('close', abort); }
      } catch (error) { json(response, 200, { ok: false, code: errorCode(error) }); }
    })();
    return true;
  }

  async function close() {
    lifetime.abort();
    for (const bridge of bridges.values()) bridge.close();
    await queue;
  }
  return { handle, close };
}
