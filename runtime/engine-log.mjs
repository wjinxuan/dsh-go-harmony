import { StringDecoder } from 'node:string_decoder';
// Capture complete lines so secrets divided between writes still pass through the redactor together.
export function captureEngineStream(stream, log) {
  const original = stream.write;
  const decoder = new StringDecoder('utf8');
  let pending = '', dropping = false;
  stream.write = function(chunk, encoding, callback) {
    try {
      const text = typeof chunk === 'string' ? chunk : decoder.write(chunk);
      for (const part of text.split(/(?<=\n)/)) {
        if (!dropping) pending += part;
        if (pending.length > 16384) { pending = ''; dropping = true; }
        if (part.endsWith('\n')) { if (dropping) log('[日志行过长，已省略]'); else if (pending.trim()) log(pending.trimEnd()); pending = ''; dropping = false; }
      }
    } catch { /* Logging cannot interfere with the engine stream or backpressure. */ }
    return original.call(this, chunk, encoding, callback);
  };
  return () => { stream.write = original; pending = ''; };
}
