import './require-runtime-node.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm, symlink, copyFile, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';

const runtime = resolve(process.env.DSH_TEST_RUNTIME || process.argv[2] || 'entry/src/main/resources/rawfile/missing-runtime');
const project = fileURLToPath(new URL('../', import.meta.url));
const modules = await mkdtemp(join(tmpdir(), 'dsh-provider-credentials-modules-'));
await symlink(join(runtime, 'node_modules'), join(modules, 'node_modules'));
for (const name of ['credentials.mjs', 'private-vault.mjs', 'transport-control.mjs']) await copyFile(join(project, 'runtime', name), join(modules, name));
const { Context } = await import(pathToFileURL(join(runtime, 'node_modules/@deepseek-ai/cordis/lib/index.js')));
const module = await import(pathToFileURL(join(modules, 'credentials.mjs')));
const { PrivateVault } = await import(pathToFileURL(join(modules, 'private-vault.mjs')));
const { startTransportControl } = await import(pathToFileURL(join(modules, 'transport-control.mjs')));
const oldHome = process.env.DSH_HOME;
const contexts = [], homes = [];
async function home() { const dir = await mkdtemp(join(tmpdir(), 'dsh-provider-credentials-home-')); homes.push(dir); return dir; }
async function host(dir) { process.env.DSH_HOME = dir; const ctx = new Context(); contexts.push(ctx); await ctx.plugin(module.default); return ctx.credentials; }
const key = () => randomBytes(32).toString('base64url');
const path = dir => join(dir, '.harmony-provider-credentials.json');
const cleanFailure = (error, ...secrets) => secrets.every(secret => !String(error?.message).includes(secret));

try {
  await test('generic writes require native unlock; explicit DeepSeek session-only behavior stays unchanged', async () => {
    const first = await host(await home());
    await assert.rejects(first.set('SYNTHETIC_API_KEY', 'fixture-key'), /解锁/);
    assert.deepEqual(await first.describe('SYNTHETIC_API_KEY'), { configured: false, writable: false });
    await first.set('DEEPSEEK_API_KEY', 'session-only');
    assert.equal((await first.resolve('DEEPSEEK_API_KEY')).value, 'session-only');
    assert.equal((await host(process.env.DSH_HOME)).resolve('DEEPSEEK_API_KEY') instanceof Promise, true);
    assert.equal(await (await host(process.env.DSH_HOME)).resolve('DEEPSEEK_API_KEY'), undefined);
  });
  await test('encrypted generic key survives fresh provider and never appears in metadata, file or environment', async () => {
    const dir = await home(), master = key(), secret = 'synthetic-restart-secret-123', first = await host(dir);
    // The old provider has no unlock API: still execute its real set/restart/resolve to reproduce key loss.
    if (typeof first.unlockReferences === 'function') await first.unlockReferences(master);
    await first.set('SYNTHETIC_API_KEY', secret);
    const restarted = await host(dir); if (typeof restarted.unlockReferences === 'function') await restarted.unlockReferences(master);
    assert.deepEqual(await restarted.resolve('SYNTHETIC_API_KEY'), { value: secret, source: 'file' });
    const metadata = await restarted.describe('SYNTHETIC_API_KEY');
    assert.deepEqual(metadata, { configured: true, source: 'file', writable: true });
    const bytes = await readFile(path(dir), 'utf8');
    for (const privateText of [secret, master, 'SYNTHETIC_API_KEY']) assert.ok(!bytes.includes(privateText));
    assert.ok(!JSON.stringify(metadata).includes(secret)); assert.equal(process.env.SYNTHETIC_API_KEY, undefined);
    assert.equal((await stat(path(dir))).mode & 0o777, 0o600);
  });
  await test('clear removes only the exact reference and stays cleared across restart', async () => {
    const dir = await home(), master = key(), first = await host(dir); await first.unlockReferences(master);
    await first.set('CLEAR_ME', 'first'); await first.set('KEEP_ME', 'second'); await first.unset('CLEAR_ME');
    const restarted = await host(dir); await restarted.unlockReferences(master);
    assert.equal(await restarted.resolve('CLEAR_ME'), undefined);
    assert.equal((await restarted.resolve('KEEP_ME')).value, 'second');
  });
  await test('concurrent providers reload under the real lock and preserve distinct writes', async () => {
    const dir = await home(), master = key(), first = await host(dir), second = await host(dir);
    await Promise.all([first.unlockReferences(master), second.unlockReferences(master)]);
    await Promise.all([first.set('KEY_A', 'A'), second.set('KEY_B', 'B')]);
    assert.equal((await first.resolve('KEY_B')).value, 'B'); assert.equal((await second.resolve('KEY_A')).value, 'A');
    await Promise.all([first.set('KEY_C', 'C'), second.unset('KEY_A')]);
    assert.equal(await first.resolve('KEY_A'), undefined); assert.equal((await second.resolve('KEY_C')).value, 'C');
  });
  await test('tampered ciphertext rejects reads and mutations without overwriting or leaking content', async () => {
    const dir = await home(), master = key(), first = await host(dir); await first.unlockReferences(master); await first.set('KEEP_ME', 'untouched-secret');
    const broken = '{"version":1,"data":"private-corrupt-content"}'; await writeFile(path(dir), broken);
    for (const run of [() => first.resolve('KEEP_ME'), () => first.set('NEXT', 'new-secret'), () => first.unset('KEEP_ME'), () => first.unlockReferences(master)]) {
      await assert.rejects(run(), e => cleanFailure(e, master, 'untouched-secret', 'new-secret', 'private-corrupt-content'));
      assert.equal(await readFile(path(dir), 'utf8'), broken);
    }
  });
  await test('wrong master key and encrypted invalid schema fail closed without replacing bytes', async () => {
    const dir = await home(), master = key(), first = await host(dir); await first.unlockReferences(master); await first.set('KEEP_ME', 'secret');
    const intact = await readFile(path(dir)); const wrong = key();
    await assert.rejects((await host(dir)).unlockReferences(wrong), e => cleanFailure(e, wrong, master));
    assert.deepEqual(await readFile(path(dir)), intact);
    const invalid = new PrivateVault(dir, '.harmony-provider-credentials.json', master, { maxBytes: 65536 });
    await invalid.save({ version: 1, refs: { 'invalid/ref': 'secret' } }); invalid.destroy();
    const bad = await readFile(path(dir)); await assert.rejects(first.set('NEXT', 'new-secret')); assert.deepEqual(await readFile(path(dir)), bad);
  });
  await test('symlink vault fails closed; an already unlocked empty store cannot change master key', async () => {
    const dir = await home(), first = await host(dir), master = key(); await first.unlockReferences(master);
    await assert.rejects(first.unlockReferences(key()));
    const outside = join(dir, 'outside.json'); await writeFile(outside, 'outside-secret'); await symlink(outside, path(dir));
    await assert.rejects(first.set('NEXT', 'new-secret')); assert.equal(await readFile(outside, 'utf8'), 'outside-secret');
  });
  await test('loopback unlock handler requires authentication, exact shape, method, route and bounded input', async () => {
    const dir = await home(), first = await host(dir), master = key();
    const control = await startTransportControl({ credentials: module.createCredentialsHandler(first) });
    const call = (body, options = {}) => fetch(control.endpoint.url + (options.path || '/credentials/unlock'), {
      method: options.method || 'POST', headers: { authorization: options.authorization ?? control.endpoint.authorization, 'content-type': 'application/json' }, body: options.method === 'GET' ? undefined : body
    });
    try {
      assert.equal((await call(JSON.stringify({ masterKey: master }), { authorization: 'Bearer wrong' })).status, 403);
      assert.equal((await call('{}', { method: 'GET' })).status, 404);
      assert.equal((await call('{}', { path: '/credentials/unlock?x=1' })).status, 404);
      for (const body of ['{', '{}', JSON.stringify({ masterKey: master, other: 'extra' }), 'x'.repeat(2049)]) {
        const response = await call(body); assert.equal(response.status, 400); assert.ok(!(await response.text()).includes(master));
      }
      const response = await call(JSON.stringify({ masterKey: master })); assert.equal(response.status, 200); assert.deepEqual(await response.json(), { unlocked: true });
      await first.set('READY', 'secret');
    } finally { await control.close(); }
  });
} finally {
  for (const ctx of contexts) await ctx.fiber.dispose();
  if (oldHome === undefined) delete process.env.DSH_HOME; else process.env.DSH_HOME = oldHome;
  await rm(modules, { recursive: true, force: true }); for (const dir of homes) await rm(dir, { recursive: true, force: true });
}
