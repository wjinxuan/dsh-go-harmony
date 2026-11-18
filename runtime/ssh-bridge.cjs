'use strict';

const { createHash, randomBytes, timingSafeEqual } = require('node:crypto');
const { createServer, request } = require('node:http');
const { Client, utils } = require('./ssh-deps/node_modules/ssh2');
const { bootstrapCommand, parseLaunch } = require('./ssh-bootstrap.cjs');

const loopback = '127.0.0.1';
const uuid = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const fingerprintPattern = /^SHA256:[A-Za-z0-9+/]{43}$/;

function respond(response, status, value) {
  if (response.destroyed) return;
  response.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
  response.end(JSON.stringify(value));
}

async function readBody(request) {
  let size = 0;
  const chunks = [];
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 64 * 1024) throw new Error('invalid-request');
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw new Error('invalid-request'); }
}

function parseConfig(value) {
  const { host, port, user, auth, secret, passphrase = '', fingerprint = '', command = 'dsh web', directory = '' } = value;
  const line = (text, max) => typeof text === 'string' && text.length <= max && !/[\x00-\x1f\x7f]/.test(text);
  if (typeof host !== 'string' || host.length > 253 || !/^[a-zA-Z0-9][a-zA-Z0-9.:_-]*$|^::[a-fA-F0-9:.]*$/.test(host) ||
      !Number.isInteger(port) || port < 1 || port > 65535 || !line(user, 128) || !user ||
      !['password', 'key'].includes(auth) || typeof secret !== 'string' || !secret || secret.length > 32768 ||
      !line(passphrase, 4096) || typeof fingerprint !== 'string' || (fingerprint && !fingerprintPattern.test(fingerprint)) ||
      !line(command, 2048) || !command || !line(directory, 2048)) throw new Error('invalid-config');
  return { host, port, user, auth, secret, passphrase, fingerprint, command, directory };
}

function openSsh(client, config, signal) {
  return new Promise((resolve, reject) => {
    let detected = '';
    let keyInvalid = false;
    let keyAttempted = false;
    const failed = (error) => {
      if (detected && detected !== config.fingerprint) {
        const failure = new Error(config.fingerprint ? 'host-key-mismatch' : 'host-key-required');
        failure.fingerprint = detected;
        reject(failure);
      } else {
        reject(new Error(keyInvalid ? 'key-invalid' : error?.level === 'client-authentication' ? 'auth-failed' : 'connect-failed'));
      }
    };
    client.once('ready', resolve);
    client.once('error', failed);
    client.once('close', failed);
    signal.addEventListener('abort', () => reject(new Error('cancelled')), { once: true });
    const password = config.auth === 'password' && config.fingerprint ? config.secret : undefined;
    if (password) {
      client.on('keyboard-interactive', (_name, _instructions, _language, prompts, finish) => {
        finish(prompts.length === 1 && /^password\s*:?\s*$/i.test(prompts[0].prompt) && !prompts[0].echo ? [password] : []);
      });
    }
    try {
      client.connect({ host: config.host, port: config.port, username: config.user, password,
        ...(config.auth === 'key' ? { authHandler: methods => {
          if (methods === null) return 'none';
          if (!methods.includes('publickey') || detected !== config.fingerprint || keyAttempted) return false;
          keyAttempted = true;
          const parsed = utils.parseKey(config.secret, config.passphrase || undefined);
          const key = Array.isArray(parsed) ? parsed[0] : parsed;
          if (key instanceof Error || !key?.isPrivateKey()) {
            keyInvalid = true;
            return false;
          }
          return { type: 'publickey', username: config.user, key };
        } } : {}),
        readyTimeout: 12000, keepaliveInterval: 15000, keepaliveCountMax: 3, tryKeyboard: !!password,
        hostVerifier: key => {
          detected = 'SHA256:' + createHash('sha256').update(key).digest('base64').replace(/=+$/, '');
          return detected === config.fingerprint;
        } });
    } catch { reject(new Error('connect-failed')); }
  });
}

function runBootstrap(client, config, signal) {
  if (signal.aborted) return Promise.reject(new Error('cancelled'));
  return new Promise((resolve, reject) => {
    let stdout = '';
    let stream;
    const finish = (error, value) => {
      clearTimeout(timer);
      signal.removeEventListener('abort', cancel);
      if (error) {
        stream?.destroy();
        reject(error);
      } else resolve(value);
    };
    const cancel = () => finish(new Error('cancelled'));
    const timer = setTimeout(() => finish(new Error('timeout')), 60000);
    signal.addEventListener('abort', cancel, { once: true });
    client.exec(bootstrapCommand(config.command, config.directory), (error, channel) => {
      if (error) return finish(new Error('shell-failed'));
      if (signal.aborted) return channel.destroy();
      stream = channel;
      channel.on('data', chunk => {
        stdout += chunk.toString('utf8');
        if (stdout.length > 32768) finish(new Error('launch-invalid'));
      });
      channel.stderr.resume();
      channel.on('error', () => finish(new Error('shell-failed')));
      channel.on('close', () => {
        try { finish(undefined, parseLaunch(stdout)); }
        catch (error) { finish(error); }
      });
    });
  });
}

function openChannel(client, port, sourcePort, signal) {
  if (signal.aborted) return Promise.reject(new Error('cancelled'));
  return new Promise((resolve, reject) => {
    const limit = AbortSignal.any([signal, AbortSignal.timeout(8000)]);
    const cancel = () => reject(new Error('forward-failed'));
    limit.addEventListener('abort', cancel, { once: true });
    client.forwardOut(loopback, sourcePort, loopback, port, (error, channel) => {
      limit.removeEventListener('abort', cancel);
      if (limit.aborted) return channel?.destroy();
      if (error) reject(new Error('forward-failed'));
      else resolve(channel);
    });
  });
}

function createTunnel(client, remote, signal) {
  const authorization = 'Bearer ' + randomBytes(32).toString('base64url');
  const expected = Buffer.from(authorization);
  const sockets = new Set();
  let authority;
  const remoteAuthority = `${loopback}:${remote.port}`;
  const permitted = (incoming) => {
    const supplied = Buffer.from(incoming.headers.authorization ?? '');
    return incoming.headers.host === authority && supplied.length === expected.length && timingSafeEqual(supplied, expected) &&
      (!incoming.headers.origin || incoming.headers.origin === `http://${authority}` || incoming.headers.origin === `http://${loopback}`);
  };
  const outgoing = (incoming, channel) => {
    const headers = { ...incoming.headers, host: remoteAuthority };
    if (headers.origin) headers.origin = `http://${remoteAuthority}`;
    for (const name of ['authorization', 'proxy-authorization', 'forwarded', 'x-forwarded-host', 'x-forwarded-proto',
      'x-forwarded-port', 'x-forwarded-for']) delete headers[name];
    return request({ host: loopback, port: remote.port, method: incoming.method, path: incoming.url, headers,
      createConnection: () => channel });
  };
  const server = createServer(async (incoming, response) => {
    if (!permitted(incoming)) return respond(response, 403, { error: 'forbidden' });
    if (!incoming.url?.startsWith('/api/') && incoming.url !== `/?token=${remote.token}`) {
      return respond(response, 404, { error: 'not-found' });
    }
    try {
      const channel = await openChannel(client, remote.port, incoming.socket.remotePort, signal);
      if (response.destroyed) return channel.destroy();
      const remoteRequest = outgoing(incoming, channel);
      remoteRequest.on('response', upstream => {
        response.writeHead(upstream.statusCode, upstream.headers);
        upstream.on('error', () => response.destroy());
        upstream.pipe(response);
      });
      remoteRequest.on('error', () => response.headersSent ? response.destroy() : respond(response, 502, { error: 'forward-failed' }));
      response.on('close', () => remoteRequest.destroy());
      incoming.pipe(remoteRequest);
    } catch { respond(response, 502, { error: 'forward-failed' }); }
  });
  server.on('connection', socket => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
  });
  server.on('upgrade', async (incoming, socket, head) => {
    socket.on('error', () => socket.destroy());
    if (!permitted(incoming) || incoming.url !== '/api/remote.mux' || incoming.headers.upgrade?.toLowerCase() !== 'websocket') {
      return socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n');
    }
    try {
      const channel = await openChannel(client, remote.port, socket.remotePort, signal);
      if (socket.destroyed) return channel.destroy();
      const remoteRequest = outgoing(incoming, channel);
      remoteRequest.on('response', response => { response.resume(); socket.destroy(); });
      remoteRequest.on('error', () => socket.destroy());
      socket.on('close', () => channel.destroy());
      remoteRequest.on('upgrade', (response, upstream, remoteHead) => {
        const headers = [];
        for (let i = 0; i < response.rawHeaders.length; i += 2) {
          headers.push(`${response.rawHeaders[i]}: ${response.rawHeaders[i + 1]}`);
        }
        socket.write(['HTTP/1.1 101 Switching Protocols', ...headers, '', ''].join('\r\n'));
        if (remoteHead.length) socket.write(remoteHead);
        if (head.length) upstream.write(head);
        upstream.on('error', () => socket.destroy());
        upstream.on('close', () => socket.destroy());
        socket.pipe(upstream).pipe(socket);
      });
      remoteRequest.end();
    } catch { socket.destroy(); }
  });
  const close = () => {
    server.close();
    for (const socket of sockets) socket.destroy();
  };
  signal.addEventListener('abort', close, { once: true });
  return new Promise((resolve, reject) => {
    server.once('error', () => reject(new Error('forward-failed')));
    server.listen(0, loopback, () => {
      if (signal.aborted) {
        close();
        reject(new Error('cancelled'));
        return;
      }
      authority = `${loopback}:${server.address().port}`;
      resolve({ launchUrl: `http://${authority}/?token=${remote.token}`, authorization });
    });
  });
}

function createSshBridgeHandler() {
  const operations = new Map();
  function closeOperation(id) {
    const operation = operations.get(id);
    operations.delete(id);
    if (operation) {
      operation.abort.abort();
      operation.client.destroy();
    }
  }

  async function dispatch(incoming, response) {
    let id;
    let operation;
    try {
      const value = await readBody(incoming);
      if (!value || !uuid.test(value.id)) throw new Error('invalid-request');
      id = value.id;
      if (incoming.url === '/ssh/close') {
        closeOperation(id);
        respond(response, 200, { closed: true });
        return;
      }
      if (operations.size >= 4 || operations.has(id)) throw new Error('busy');
      const config = parseConfig(value);
      const client = new Client();
      const abort = new AbortController();
      operation = { client, abort };
      operations.set(id, operation);
      client.on('error', () => {});
      client.on('close', () => { if (operations.get(id) === operation) closeOperation(id); });
      const cancelled = () => { if (operations.get(id) === operation) closeOperation(id); };
      response.once('close', cancelled);
      await openSsh(client, config, abort.signal);
      const remote = await runBootstrap(client, config, abort.signal);
      const probe = await openChannel(client, remote.port, 0, abort.signal);
      probe.destroy();
      const endpoint = await createTunnel(client, remote, abort.signal);
      if (response.destroyed) cancelled();
      else {
        response.removeListener('close', cancelled);
        respond(response, 200, endpoint);
      }
    } catch (error) {
      if (operation && operations.get(id) === operation) closeOperation(id);
      const code = /^(?:invalid-(?:request|config)|host-key-(?:required|mismatch)|connect-failed|auth-failed|key-invalid|shell-failed|state-error|no-dsh|bad-directory|busy|exited|timeout|launch-invalid|forward-failed|cancelled)$/.test(error.message) ?
        error.message : 'connect-failed';
      respond(response, 200, { code, fingerprint: error.fingerprint });
    }
  }

  return {
    handle(incoming, response) {
      if (incoming.url !== '/ssh/connect' && incoming.url !== '/ssh/close') return false;
      if (incoming.method !== 'POST') respond(response, 405, { code: 'invalid-request' });
      else void dispatch(incoming, response);
      return true;
    },
    async close() { for (const id of operations.keys()) closeOperation(id); }
  };
}

module.exports = { createSshBridgeHandler };
