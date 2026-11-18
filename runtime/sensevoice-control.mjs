import { getSenseVoiceManager } from './sensevoice-provider.mjs';

export function createSenseVoiceHandler() {
  return {
    handle(request, response) {
      if (!request.url?.startsWith('/sensevoice/')) return false;
      const reply = (status, body) => {
        if (!response.destroyed) response.writeHead(status, { 'content-type': 'application/json' }).end(JSON.stringify(body));
      };
      if (request.headers['transfer-encoding'] || Number(request.headers['content-length'] ?? 0) > 0) {
        request.resume(); reply(400, { error: 'Model actions do not accept a body' }); return true;
      }
      const manager = getSenseVoiceManager();
      if (!manager) { reply(503, { error: 'Local speech service is starting' }); return true; }
      const action = request.url.slice('/sensevoice/'.length);
      if (request.method === 'GET' && action === 'state') { reply(200, manager.snapshot()); return true; }
      if (request.method !== 'POST' || !['download', 'redownload', 'cancel', 'delete'].includes(action)) {
        reply(404, { error: 'Unknown model action' }); return true;
      }
      if (action === 'download' || action === 'redownload') {
        manager.start(action === 'redownload').catch(() => {});
        reply(202, manager.snapshot());
      } else {
        (action === 'cancel' ? manager.cancel() : manager.remove()).then(() => reply(200, manager.snapshot()),
          () => reply(500, { error: 'Could not finish the model operation' }));
      }
      return true;
    },
    async close() {}
  };
}
