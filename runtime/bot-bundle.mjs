import { readFileSync, writeFileSync, renameSync, lstatSync, mkdirSync, rmSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { join } from 'node:path';
const NAME = '.harmony-bundled-bot.json';
export function bundledBotEnabled(root) {
  try {
    const path = join(root, NAME), stat = lstatSync(path);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 1024) throw new Error('Invalid bundled Bot setting');
    return JSON.parse(readFileSync(path, 'utf8')).enabled === true;
  } catch (error) { if (error.code === 'ENOENT') return false; throw error; }
}
export function createBotBundleHandler(root, safeMode = false) {
  const activeAtStart = !safeMode && bundledBotEnabled(root);
  const state = () => ({ enabled: bundledBotEnabled(root), activeAtStart,
    version: '0.2.3', sourceCommit: '4a7b55069ad300eae8be42a74f31bc170b40ead7', mobileCommit: '6f3e1b3e8603abd84820b334a7f99985236dbbdf', restartRequired: bundledBotEnabled(root) !== activeAtStart });
  return {
    handle(request, response) {
      if (request.url !== '/botBundle/state' && request.url !== '/botBundle/enable') return false;
      const send = (code, body) => { response.writeHead(code, { 'content-type': 'application/json' }).end(JSON.stringify(body)); };
      if (request.url.endsWith('/state') && request.method === 'GET') { send(200, state()); return true; }
      if (request.url.endsWith('/enable') && request.method === 'POST') {
        let body = '', size = 0;
        request.on('data', chunk => { size += chunk.length; if (size <= 1024) body += chunk; });
        request.on('end', () => {
          try {
            if (size > 1024) throw new Error('too large');
            const value = JSON.parse(body);
            if (typeof value.enabled !== 'boolean' || Object.keys(value).some(key => key !== 'enabled')) throw new Error('invalid');
            mkdirSync(root, { recursive: true, mode: 0o700 });
            const path = join(root, NAME), stage = path + '.' + randomUUID() + '.tmp';
            try { writeFileSync(stage, JSON.stringify({ enabled: value.enabled }), { mode: 0o600, flag: 'wx' }); renameSync(stage, path); }
            finally { rmSync(stage, { force: true }); }
            send(200, state());
          } catch { send(400, { error: 'Bundled Bot setting could not be saved' }); }
        }); return true;
      }
      send(405, { error: 'Method not allowed' }); return true;
    },
    async close() {}
  };
}
