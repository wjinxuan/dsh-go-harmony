import { Readable } from 'node:stream';
import fetch from 'node-fetch';

export function installJitlessFetch() {
  if (typeof WebAssembly !== 'undefined') return;
  // Node's built-in fetch lazily loads Undici's WASM HTTP parser.
  globalThis.fetch = async (input, options = {}) => {
    const request = input instanceof Request ? new Request(input, options) : undefined;
    const response = await fetch(request?.url ?? input, request ? {
      method: request.method, headers: request.headers, signal: request.signal,
      body: request.body ? Readable.fromWeb(request.body) : undefined,
      redirect: request.redirect
    } : {
      ...options,
      body: options.body instanceof ReadableStream ? Readable.fromWeb(options.body) : options.body
    });
    const noBody = response.status === 204 || response.status === 205 || response.status === 304;
    const converted = new Response(noBody || !response.body ? null : Readable.toWeb(response.body), {
      status: response.status, statusText: response.statusText, headers: response.headers
    });
    Object.defineProperties(converted, {
      url: { value: response.url },
      redirected: { value: response.redirected },
      type: { value: response.type }
    });
    return converted;
  };
}
