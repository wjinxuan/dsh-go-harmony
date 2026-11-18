import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
const source = readFileSync(new URL('../entry/src/main/ets/local/LocalEngine.ets', import.meta.url), 'utf8');
const code = stripTypeScriptTypes(source.slice(source.indexOf('export class LocalEngine')).replace('export class', 'class') + '\nLocalEngine');
const settled = () => new Promise(resolve => setImmediate(resolve));
function fixture({ keyFailure = false, status = 200, response = { unlocked: true }, delayed = false } = {}) {
  const master = 'synthetic-asset-store-master', control = { url: 'http://127.0.0.1:43210', authorization: 'Bearer ' + 'a'.repeat(43) };
  const endpoint = { url: 'http://127.0.0.1:43211/?token=synthetic', workspaceDir: '/isolated/dsh-local-data/workspace', transportControl: control };
  const calls = [], names = [], configs = []; let closed = 0, release;
  const pending = new Promise(resolve => { release = resolve; });
  const Engine = vm.runInNewContext(code, {
    fs: { async access(path) { return !path.endsWith('/error.json'); }, async readText(path) { assert.ok(path.endsWith('/ready.json')); return JSON.stringify(endpoint); } },
    util: { TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder().decode(bytes) }) } },
    rcp: { Request: class { constructor(url, method, headers, body) { Object.assign(this, { url, method, headers, body }); } },
      createSession(config) { configs.push(config); return { async fetch(request) { calls.push(request); if (delayed) await pending;
        return { statusCode: status, body: new TextEncoder().encode(JSON.stringify(response)).buffer }; }, close() { closed++; } }; } },
    privateVaultKey: async name => { names.push(name); if (keyFailure) throw Error('synthetic private error ' + master); return master; }
  });
  const engine = new Engine(); engine.engine = { status: () => -1 };
  return { engine, endpoint, master, calls, names, configs, release, closed: () => closed };
}

test('LocalEngine returns the ready endpoint only after the AssetStore credential key unlock succeeds', async () => {
  const f = fixture({ delayed: true }); let returned = false;
  const start = f.engine.start({ filesDir: '/isolated' }, () => {}).then(value => { returned = true; return value; });
  await settled(); assert.equal(returned, false); assert.deepEqual(f.names, ['credentials']);
  assert.equal(f.calls.length, 1); assert.equal(f.calls[0].url, f.endpoint.transportControl.url + '/credentials/unlock');
  assert.equal(f.calls[0].headers.authorization, f.endpoint.transportControl.authorization);
  assert.deepEqual(JSON.parse(f.calls[0].body), { masterKey: f.master });
  assert.equal(f.configs[0].requestConfiguration.proxy, 'no-proxy'); assert.equal(f.configs[0].requestConfiguration.transfer.autoRedirect, false);
  f.release(); assert.deepEqual(JSON.parse(JSON.stringify(await start)), f.endpoint); assert.equal(f.closed(), 1);
});

test('each local reconnect unlocks against the current ready endpoint; no remote client path changes', async () => {
  const f = fixture(); await f.engine.start({ filesDir: '/isolated' }, () => {}); await f.engine.start({ filesDir: '/isolated' }, () => {});
  assert.equal(f.calls.length, 2); assert.deepEqual(f.names, ['credentials', 'credentials']); assert.equal(f.closed(), 2);
  assert.doesNotMatch(readFileSync(new URL('../entry/src/main/ets/dsh/DshClient.ets', import.meta.url), 'utf8'), /credentials\/unlock|privateVaultKey/);
});

test('locked AssetStore and failed or malformed unlock replies fail closed and release the request session', async () => {
  for (const options of [{ keyFailure: true }, { status: 500 }, { response: { unlocked: false } }, { response: {} }]) {
    const f = fixture(options); await assert.rejects(f.engine.start({ filesDir: '/isolated' }, () => {}), e => /渠道凭据未能解锁/.test(e.message) && !e.message.includes(f.master));
    assert.equal(f.closed(), 1); assert.equal(f.calls.length, options.keyFailure ? 0 : 1);
  }
});
