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
  await writeFile(new URL('./SpeechData.ts', testDir), (await readFile(join(dirname(clientPath), 'SpeechData.ets'), 'utf8'))
    .replace("'./DshWire'", "'./DshWire.ts'"));
  await writeFile(new URL('./DshBinaryResponse.ts', testDir), (await readFile(join(dirname(clientPath), 'DshBinaryResponse.ets'), 'utf8'))
    .replace(', WireObject', '').replace("'./DshWire'", "'./DshWire.ts'"));
  await writeFile(new URL('./DsBotProtocol.ts', testDir), (await readFile(join(dirname(clientPath), 'DsBotProtocol.ets'), 'utf8'))
    .replace(', WireObject', '').replace("'./DshWire'", "'./DshWire.ts'"));
  await writeFile(new URL('./CompanionSignalProtocol.ts', testDir), (await readFile(join(dirname(clientPath), 'CompanionSignalProtocol.ets'), 'utf8'))
    .replace(', WireObject', '').replace("'./DshWire'", "'./DshWire.ts'"));
  const modules = new Map([
    ['@kit.ArkTS', 'url,util'], ['@kit.NetworkKit', 'webSocket'], ['@kit.RemoteCommunicationKit', 'rcp'],
    ['@kit.CoreFileKit', 'fileIo'], ['@kit.BasicServicesKit', 'deviceInfo']
  ]);
  const mockFiles = new Map();
  class UploadFromFile { constructor(path) { this.path = path; } }
  const deviceInfo = fixtures.deviceInfo ?? { sdkApiVersion: 26 };
  globalThis.dshLiveFixtureKits = {
    deviceInfo,
    url: { URL: { parseURL(text) { const value = new URL(text); value.params = value.searchParams; return value; } } },
    util: { generateRandomUUID: randomUUID, Base64Helper: class {
      encodeToString(bytes) { return Buffer.from(bytes).toString('base64'); }
      async decode(text) { return Buffer.from(text, 'base64'); }
    }, TextDecoder: { create() {
      const decoder = new TextDecoder('utf-8');
      return { decodeToString: bytes => decoder.decode(bytes), decodeWithStream: (bytes, options) => decoder.decode(bytes, options) };
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
      UploadFromFile,
      Request: class { constructor(uri, method, headers, body) { Object.assign(this, { uri, method, headers, body }); } },
      createSession: ({ requestConfiguration }) => ({ close() {}, cancel(request) { request.cancelled?.abort(); }, async fetch(request) {
        const { uri, method, headers, body, configuration, destination } = request;
        fixtures.proxyOptions?.push(configuration?.proxy ?? requestConfiguration.proxy);
        request.cancelled = new AbortController();
        if (destination && fixtures.exportRequest) return fixtures.exportRequest(request);
        const response = await fetch(uri, { method, body: body instanceof UploadFromFile ? await readFile(body.path) : body, redirect: 'manual',
          headers: Object.fromEntries(Object.entries(headers).filter(([, value]) => value !== undefined)),
          signal: AbortSignal.any([request.cancelled.signal, AbortSignal.timeout(configuration?.transfer.timeout.transferMs ?? 20000)]) });
        const events = configuration?.tracing?.httpEventsHandler;
        if (events?.onDataReceive) {
          events.onStatusCodeReceive?.(response.status);
          events.onHeaderReceive?.({ 'content-type': response.headers.get('content-type') ?? undefined });
          for await (const chunk of response.body || []) await events.onDataReceive(chunk.buffer.slice(chunk.byteOffset, chunk.byteOffset + chunk.byteLength));
          return { statusCode: response.status, headers: {}, body: undefined };
        }
        if (destination?.kind === 'file' && response.body) {
          await pipeline(response.body, createWriteStream(destination.file), { signal: request.cancelled.signal });
        }
        return { statusCode: response.status, headers: { 'set-cookie': response.headers.getSetCookie(),
          'content-type': response.headers.get('content-type') ?? undefined },
          body: destination ? undefined : await response.arrayBuffer() };
      } })
    }
  };

  const source = (await readFile(clientPath, 'utf8')).replace(', DsBotEvent', '')
    .replace(/import \{[^}]+\} from '\.\/DshWire';/, `import { approvalFromEvent, array, commandCatalog, commandResult, createMuxOpen,
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
    if (specifier === './CompanionSignalProtocol' && context.parentURL === nativeClient.href) {
      return { url: new URL('./CompanionSignalProtocol.ts', testDir).href, shortCircuit: true };
    }
    if (specifier === './DsBotProtocol' && context.parentURL === nativeClient.href) {
      return { url: new URL('./DsBotProtocol.ts', testDir).href, shortCircuit: true };
    }
    if (specifier === './SpeechData' && context.parentURL === nativeClient.href) {
      return { url: new URL('./SpeechData.ts', testDir).href, shortCircuit: true };
    }
    if (specifier === './DshBinaryResponse' && context.parentURL === nativeClient.href) {
      return { url: new URL('./DshBinaryResponse.ts', testDir).href, shortCircuit: true };
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
