import { randomBytes, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';

export async function startTransportControl(handlers) {
  const authorization = `Bearer ${randomBytes(32).toString('base64url')}`;
  const expected = Buffer.from(authorization);
  const server = createServer({ requestTimeout: 15000, headersTimeout: 5000 }, (request, response) => {
    const supplied = Buffer.from(request.headers.authorization ?? '');
    if (request.headers.host !== `127.0.0.1:${server.address()?.port}` || request.headers.origin !== undefined ||
        supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) {
      response.writeHead(403, { connection: 'close' }).end();
      return;
    }
    const route = request.url?.split('?', 1)[0].split('/')[1];
    if (!Object.hasOwn(handlers, route) || !handlers[route].handle(request, response)) {
      response.writeHead(404).end();
    }
  });
  server.maxConnections = 20;
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => { server.off('error', reject); resolve(); });
  });
  return {
    endpoint: { url: `http://127.0.0.1:${server.address().port}`, authorization },
    async close() {
      const stopped = new Promise(resolve => server.close(resolve));
      server.closeAllConnections();
      const results = await Promise.allSettled(Object.values(handlers).map(async handler => handler.close()));
      await stopped;
      const failure = results.find(result => result.status === 'rejected');
      if (failure) throw failure.reason;
    }
  };
}
