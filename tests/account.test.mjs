import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { readFile, realpath } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { loadDshClient } from './dsh-client-node-fixture.mjs';
import { formatAccountWallets, loadAccountOverview } from './ui/AccountData.ts';
const client = { version: '1.0.0', locale: 'zh-CN', timezoneOffsetSeconds: 28800 };
const profile = { status: 'ready', value: { id: 'private-id', name: '测试账号', contact: '138****5678',
  avatarUrl: 'https://private.invalid/token', token: 'private-grant' } };
const wallets = { status: 'ready', value: [{ currency: 'CNY', balance: '12.009' }],
  bonusWallets: [{ currency: 'USD', balance: '0E-16' }, { currency: 'USD', balance: '0.00001' }] };
const stored = { status: 'credential-stored', attempt: { authorizeUrl: 'https://private.invalid/authorize' } };

assert.deepEqual(formatAccountWallets([{ currency: 'CNY', balance: '9007199254740993.001' },
  { currency: 'CNY', balance: '0.009' }, { currency: 'USD', balance: '-0.005' }]),
['¥9,007,199,254,740,993.01', '$-0.01']);
assert.deepEqual(formatAccountWallets([]), ['¥0.00']);
assert.throws(() => formatAccountWallets([{ currency: 'CNY', balance: 'private-grant' }]), /余额/);

async function run(replies) {
  const calls = [];
  const views = [];
  await loadAccountOverview(async (method, args, timeout) => {
    calls.push({ method, args, timeout });
    if (!Object.hasOwn(replies, method)) assert.fail(`Unexpected method ${method}`);
    const reply = Array.isArray(replies[method]) ? replies[method].shift() : replies[method];
    if (reply instanceof Error) throw reply;
    return reply;
  }, client, () => true, view => views.push(view));
  return { calls, views, view: views.at(-1) };
}

const signedOut = await run({ 'account/getState': { status: 'signed-out' } });
assert.equal(signedOut.view.status, 'signed-out');
assert.equal(signedOut.calls.length, 1);
assert.equal((await run({ 'account/getState': new Error('主机请求失败（HTTP 404）') })).view.status, 'unsupported');
assert.equal((await run({ 'account/getState': new Error('HTTP 403 private-grant') })).view.status, 'error');
assert.equal((await run({ 'account/getState': { status: 'unknown' } })).view.status, 'error');

const ready = await run({ 'account/getState': stored, 'account/getProfile': profile, 'account/getBalance': wallets });
assert.deepEqual(ready.calls.slice(1), [
  { method: 'account/getProfile', args: { client }, timeout: undefined },
  { method: 'account/getBalance', args: { client }, timeout: 35000 }
]);
assert.deepEqual(ready.view.profile, { name: '测试账号', contact: '138****5678' });
assert.deepEqual(ready.view.recharge, ['¥12.00']);
assert.deepEqual(ready.view.bonus, ['$<0.01']);
assert.doesNotMatch(JSON.stringify(ready.views), /private|authorize|token/);

const partial = await run({ 'account/getState': stored, 'account/getProfile': profile,
  'account/getBalance': { status: 'failed' } });
assert.equal(partial.view.profile.name, '测试账号');
assert.equal(partial.view.balanceFailed, true);
assert.equal(partial.view.recharge, undefined);
const timeout = await run({ 'account/getState': stored, 'account/getProfile': new Error('private timeout'),
  'account/getBalance': wallets });
assert.equal(timeout.view.profileFailed, true);
assert.deepEqual(timeout.view.recharge, ['¥12.00']);
assert.doesNotMatch(JSON.stringify(timeout.views), /private timeout/);

const expired = await run({ 'account/getState': [stored, { status: 'signed-out' }],
  'account/getProfile': null, 'account/getBalance': wallets });
assert.deepEqual(expired.view, { status: 'signed-out' });

let releaseBalance;
let statusReads = 0;
const revokedViews = [];
const revoked = loadAccountOverview(async method => {
  if (method === 'account/getState') return statusReads++ ? { status: 'signed-out' } : stored;
  if (method === 'account/getProfile') return null;
  return new Promise(resolve => { releaseBalance = resolve; });
}, client, () => true, view => revokedViews.push(view));
await new Promise(resolve => setImmediate(resolve));
assert.deepEqual(revokedViews.at(-1), { status: 'signed-out' });
releaseBalance(wallets);
await revoked;
assert.deepEqual(revokedViews.at(-1), { status: 'signed-out' });

let current = true;
let releaseProfile;
const staleViews = [];
const stale = loadAccountOverview(async method => {
  if (method === 'account/getState') return stored;
  if (method === 'account/getBalance') return wallets;
  return new Promise(resolve => { releaseProfile = resolve; });
}, client, () => current, view => staleViews.push(view));
await new Promise(resolve => setImmediate(resolve));
assert.deepEqual(staleViews.at(-1).recharge, ['¥12.00']);
const count = staleViews.length;
current = false;
releaseProfile(profile);
await stale;
assert.equal(staleViews.length, count);
console.log('账号状态、余额精度和连接切换检查通过');

const [directory, clientPath, flockFixture] = process.argv.slice(2);
if (directory) {
  const root = await realpath(directory);
  const home = join(root, 'isolated');
  const runtime = join(root, 'runtime', 'main.cjs');
  const DshClient = await loadDshClient(clientPath, runtime, root);
  const client = new DshClient();
  const child = spawn(process.execPath, ['--jitless', '--no-addons', '--expose-internals', '--require', flockFixture,
    runtime, home], { cwd: root, env: { HOME: root, PATH: `${dirname(process.execPath)}:/usr/bin:/bin` }, stdio: 'ignore' });
  const ended = once(child, 'exit');
  try {
    let ready;
    for (let i = 0; i < 200 && !ready && child.exitCode === null; i++) {
      ready = await readFile(join(home, 'ready.json'), 'utf8').then(JSON.parse, () => undefined);
      if (!ready) await delay(100);
    }
    assert.equal(typeof ready?.url, 'string', 'Isolated DSH did not publish readiness');
    await client.connect(ready.url);
    const views = [];
    await loadAccountOverview((method, args, timeout) => client.request(method, args, timeout),
      { version: '1.0.0', locale: 'zh-CN', timezoneOffsetSeconds: 28800 }, () => true, view => views.push(view));
    assert.deepEqual(views, [{ status: 'signed-out' }]);
    console.log('隔离 DSH 账号 RPC 未登录状态检查通过');
  } finally {
    client.close();
    if (child.exitCode === null && child.signalCode === null) {
      child.kill('SIGTERM');
      if (!await Promise.race([ended.then(() => true), delay(2500, false, { ref: false })])) child.kill('SIGKILL');
    }
    await ended;
  }
}
