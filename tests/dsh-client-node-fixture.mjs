import { randomUUID } from 'node:crypto';
import { access, open, readFile, unlink, writeFile } from 'node:fs/promises';
import { createWriteStream } from 'node:fs';
import { createRequire, registerHooks } from 'node:module';
import { dirname, join } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { pathToFileURL } from 'node:url';

export async function loadDshClient(clientPath, dshBin, temp, fixtures = {}) {
  const { WebSocket } = createRequire(dshBin)('ws');
  const testDir = pathToFileURL(temp + '/');
  await writeFile(new URL('./DshWire.ts', testDir), await readFile(join(dirname(clientPath), 'DshWire.ets')));
  const modules = new Map([
    ['@kit.ArkTS', 'url,util'], ['@kit.NetworkKit', 'webSocket'], ['@kit.RemoteCommunicationKit', 'rcp'],
    ['@kit.CoreFileKit', 'fileIo'], ['@kit.BasicServicesKit', 'deviceInfo']
  ]);
  const mockFiles = new Map();
  const deviceInfo = fixtures.deviceInfo ?? { sdkApiVersion: 26 };
  globalThis.dshLiveFixtureKits = {
    deviceInfo,
    url: { URL: { parseURL(text) { const value = new URL(text); value.params = value.searchParams; return value; } } },
    util: { generateRandomUUID: randomUUID, TextDecoder: { create() {
      const decoder = new TextDecoder('utf-8');
      return { decodeToString: bytes => decoder.decode(bytes) };
    } } },
    fileIo: {
      OpenMode: { READ_ONLY: 0 },
      access: path => access(path).then(() => true, () => false),
      async open(path) { const file = await open(path, 'r'); mockFiles.set(file.fd, file); return file; },
      async read(fd, buffer) { return (await mockFiles.get(fd).read(new Uint8Array(buffer))).bytesRead; },
      async close(file) { mockFiles.delete(file.fd); await file.close(); },
      unlink
    },
    webSocket: { createWebSocket() {
      const listeners = new Map();
      let socket;
      return {
        on: (event, handler) => listeners.set(event, handler),
        off: event => listeners.delete(event),
        close: async () => socket?.close(),
        send: async value => { await new Promise((ok, fail) => socket.send(value, error => error ? fail(error) : ok())); return true; },
        connect: async (uri, options) => {
          fixtures.socketOptions?.push(options);
          const { header, supportOriginPort } = options;
          const address = new URL(uri);
          if (!supportOriginPort) address.port = '';
          const origin = address.origin.replace(/^ws/, 'http');
          socket = new WebSocket(uri, { headers: { ...header, Origin: origin } });
          for (const event of ['open', 'close', 'error']) socket.on(event, (...args) => listeners.get(event)?.(...args));
          socket.on('message', value => listeners.get('message')?.(undefined, value.toString()));
        }
      };
    } },
    rcp: {
      Request: class { constructor(uri, method, headers, body) { Object.assign(this, { uri, method, headers, body }); } },
      createSession: ({ requestConfiguration }) => ({ close() {}, cancel(request) { request.cancelled?.abort(); }, async fetch(request) {
        const { uri, method, headers, body, configuration, destination } = request;
        fixtures.proxyOptions?.push(configuration?.proxy ?? requestConfiguration.proxy);
        request.cancelled = new AbortController();
        if (destination && fixtures.exportRequest) return fixtures.exportRequest(request);
        const response = await fetch(uri, { method, body, redirect: 'manual',
          headers: Object.fromEntries(Object.entries(headers).filter(([, value]) => value !== undefined)),
          signal: AbortSignal.any([request.cancelled.signal, AbortSignal.timeout(configuration?.transfer.timeout.transferMs ?? 20000)]) });
        if (destination?.kind === 'file' && response.body) {
          await pipeline(response.body, createWriteStream(destination.file), { signal: request.cancelled.signal });
        }
        return { statusCode: response.status, headers: { 'set-cookie': response.headers.getSetCookie(),
          'content-type': response.headers.get('content-type') ?? undefined },
          body: destination ? undefined : await response.arrayBuffer() };
      } })
    }
  };

  const source = (await readFile(clientPath, 'utf8'))
    .replace(/import \{[^}]+\} from '\.\/DshWire';/, `import { approvalFromEvent, array, createMuxOpen,
      createRpcRequest, DshRpcError, DshTranscript, goalRef, goalView, localSessionError, modelCatalog, modelSelection,
      modelSelectionResult, normalizeProviderKey, number, object, parseRpcResponse, permissionCatalog, questionFromEvent,
      sessionPage, sessionProjections, string, strings, turnTraces, wireError, workspaceListing, workspaceText } from './DshWire';`)
    .replace(/export \{[^}]+\} from '\.\/DshWire';/, '');
  const nativeClient = new URL('./DshClient.ts', testDir);
  await writeFile(nativeClient, source);
  const hooks = registerHooks({ resolve(specifier, context, next) {
    if (modules.has(specifier)) {
      return { url: `data:text/javascript,export const {${modules.get(specifier)}}=globalThis.dshLiveFixtureKits;`, shortCircuit: true };
    }
    if (specifier === './DshWire' && context.parentURL === nativeClient.href) {
      return { url: new URL('./DshWire.ts', testDir).href, shortCircuit: true };
    }
    return next(specifier, context);
  } });
  try {
    return (await import(nativeClient.href)).DshClient;
  } finally {
    hooks.deregister();
    delete globalThis.dshLiveFixtureKits;
  }
}
