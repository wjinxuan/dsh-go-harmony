import assert from 'node:assert/strict';
import { once } from 'node:events';
import https from 'node:https';
import { createServer } from 'node:net';
import { setTimeout as delay, setImmediate as turn } from 'node:timers/promises';
import test from 'node:test';
import { execFileSync } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openModelUrl } from '../runtime/sensevoice-models.mjs';

async function stalledTlsServer() {
  const sockets = new Set();
  let receivedHello;
  const hello = new Promise(resolve => { receivedHello = resolve; });
  const server = createServer(socket => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
    socket.once('data', receivedHello);
  }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  return {
    port: server.address().port, hello,
    async close() { for (const socket of sockets) socket.destroy(); await new Promise(resolve => server.close(resolve)); }
  };
}

test('model request does not inherit the HTTPS Agent five-second DNS/connect timeout', async () => {
  const server = await stalledTlsServer(), original = https.globalAgent, controller = new AbortController();
  const lookups = new Set();
  const agent = new https.Agent({ keepAlive: true, timeout: 5000, lookup(_host, options, callback) {
    const timer = setTimeout(() => {
      lookups.delete(timer);
      callback(null, options.all ? [{ address: '127.0.0.1', family: 4 }] : '127.0.0.1', 4);
    }, 7000);
    lookups.add(timer);
  } });
  https.globalAgent = agent;
  let outcome;
  const pending = openModelUrl(`https://delayed.invalid:${server.port}/model`, 0, controller.signal)
    .then(response => { response.destroy(); outcome = 'unexpected response'; }, error => { outcome = error; });
  try {
    await delay(5400);
    assert.equal(outcome, undefined, 'the advertised 60-second connection budget must not fail at the Agent default of 5 seconds');
  } finally {
    controller.abort(); await pending;
    for (const timer of lookups) clearTimeout(timer);
    https.globalAgent = original; agent.destroy(); await server.close();
  }
});

test('a connected TLS peer that never answers has a real 60-second response-header deadline', async t => {
  const server = await stalledTlsServer(), controller = new AbortController();
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let outcome;
  const pending = openModelUrl(`https://127.0.0.1:${server.port}/model`, 0, controller.signal)
    .then(response => { response.destroy(); outcome = 'unexpected response'; }, error => { outcome = error; });
  try {
    await server.hello;
    t.mock.timers.tick(59999); await turn();
    assert.equal(outcome, undefined, 'the connection deadline must not fire early');
    t.mock.timers.tick(1); await turn();
    assert.equal(outcome?.reason, 'timeout', 'socket inactivity alone cannot bound a stalled TLS handshake');
  } finally {
    controller.abort(); await pending; t.mock.timers.reset(); await server.close();
  }
});

test('model download preserves the upstream user agent across HTTPS redirects and range resume', async () => {
  const root = await mkdtemp(join(tmpdir(), 'sensevoice-https-'));
  const original = https.globalAgent;
  let server, agent;
  try {
    const keyPath = join(root, 'key.pem'), certPath = join(root, 'cert.pem');
    execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-sha256', '-nodes',
      '-keyout', keyPath, '-out', certPath, '-days', '1', '-subj', '/CN=localhost',
      '-addext', 'subjectAltName=IP:127.0.0.1'], { stdio: 'ignore' });
    const cert = await readFile(certPath), key = await readFile(keyPath), requests = [];
    // Trust only this disposable fixture certificate; production TLS checks remain enabled.
    agent = new https.Agent({ ca: cert });
    https.globalAgent = agent;
    server = https.createServer({ key, cert }, (request, response) => {
      requests.push({ path: request.url, headers: request.headers });
      if (request.url === '/model') response.writeHead(302, { location: '/cdn/model' }).end();
      else if (request.headers['user-agent'] !== 'dsh-go') response.writeHead(403).end('denied by UA ACL');
      else response.writeHead(206, { 'content-range': 'bytes 7-10/11', 'content-length': '4' }).end('data');
    }).listen(0, '127.0.0.1');
    await once(server, 'listening');
    const response = await openModelUrl(`https://127.0.0.1:${server.address().port}/model`, 7, new AbortController().signal);
    const chunks = [];
    for await (const chunk of response) chunks.push(chunk);
    assert.equal(response.statusCode, 206, 'ModelScope CDN requires the user agent already sent by the original app');
    assert.equal(Buffer.concat(chunks).toString(), 'data');
    assert.deepEqual(requests.map(request => request.path), ['/model', '/cdn/model']);
    for (const { headers } of requests) {
      assert.equal(headers['user-agent'], 'dsh-go');
      assert.equal(headers['accept-encoding'], 'identity');
      assert.equal(headers.range, 'bytes=7-');
    }
  } finally {
    https.globalAgent = original;
    agent?.destroy();
    if (server) { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
    await rm(root, { recursive: true, force: true });
  }
});
