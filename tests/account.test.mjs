import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { chmod, mkdir, readFile, realpath, stat, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { dirname, join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { pathToFileURL } from 'node:url';
import { loadDshClient } from './dsh-client-node-fixture.mjs';
import * as accountData from './ui/AccountData.ts';
const { formatAccountWallets, loadAccountOverview } = accountData;
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

const localOrigin = 'http://127.0.0.1:45123';
const authorize = 'https://platform.deepseek.com/dsh/authorize?session_id=fixture';
assert.equal(accountData.accountCallbackOrigin(localOrigin), localOrigin);
for (const invalid of ['http://127.0.0.1:0', 'http://127.0.0.1:65536', localOrigin + '?token=secret',
  'https://remote.test', 'http://127.0.0.1@remote.test:9000', localOrigin + '/proxy']) {
  assert.equal(accountData.accountCallbackOrigin(invalid), '');
}
assert.equal(accountData.accountAuthorizeUrl(authorize), authorize);
for (const invalid of ['https://platform.deepseek.com.evil.invalid/dsh/authorize?fixture',
  'http://platform.deepseek.com/dsh/authorize?fixture', 'https://platform.deepseek.com@evil.invalid/dsh/authorize?fixture',
  'https://platform.deepseek.com/dsh/authorize?fixture#fragment', 'https://platform.deepseek.com/dsh/authorize/extra?fixture',
  'https://platform.deepseek.com/dsh/authorize?fixture\n', 'https://platform.deepseek.com/dsh/authorize?fixture\\next']) {
  assert.equal(accountData.accountAuthorizeUrl(invalid), '');
}

const active = (phase, details = {}) => ({ status: 'signed-out', attempt: { id: 'attempt-1', phase, ...details } });
const attempts = [active('initializing'), active('waiting-browser', { authorizeUrl: authorize }),
  active('exchanging'), { status: 'credential-stored' }];
const browserUrls = [];
const attemptCalls = [];
const loginOutcome = await accountData.runAccountSignIn(async (method, args) => {
  attemptCalls.push({ method, args });
  return attempts.shift();
}, client, localOrigin, () => true, async attempt => {
  if (attempt.phase === 'waiting-browser') browserUrls.push(attempt.authorizeUrl);
}, async () => {});
assert.equal(loginOutcome, 'signed-in');
assert.deepEqual(browserUrls, [authorize]);
assert.deepEqual(attemptCalls, [{ method: 'account/startSignIn', args: { client, callbackOrigin: localOrigin, loginSource: 'web' } },
  ...Array.from({ length: 3 }, () => ({ method: 'account/getState', args: {} }))]);

let loginCurrent = true;
let connectionCurrent = true;
const cancellationCalls = [];
for (const lostConnection of [false, true]) {
  loginCurrent = true;
  connectionCurrent = true;
  const before = cancellationCalls.length;
  const stopped = await accountData.runAccountSignIn(async method => {
    cancellationCalls.push(method);
    if (method === 'account/startSignIn') {
      loginCurrent = false;
      if (lostConnection) connectionCurrent = false;
      return active('waiting-browser', { authorizeUrl: authorize });
    }
    return active('cancelled');
  }, client, localOrigin, () => loginCurrent, async () => assert.fail('Stale browser opened'), async () => {},
  () => connectionCurrent);
  assert.equal(stopped, 'cancelled');
  assert.deepEqual(cancellationCalls.slice(before), lostConnection ? ['account/startSignIn'] :
    ['account/startSignIn', 'account/cancelSignIn']);
}

const rejectedCalls = [];
assert.equal(await accountData.runAccountSignIn(async method => {
  rejectedCalls.push(method);
  return method === 'account/startSignIn' ? active('waiting-browser', { authorizeUrl: 'https://example.invalid/' }) :
    active('cancelled');
}, client, localOrigin, () => true, async () => assert.fail('Unsafe browser opened'), async () => {}), 'unsafe-url');
assert.deepEqual(rejectedCalls, ['account/startSignIn', 'account/cancelSignIn']);

let stillWaiting = true;
assert.equal(await accountData.runAccountSignIn(async method => {
  if (method === 'account/startSignIn') return active('initializing');
  assert.equal(method, 'account/getState');
  stillWaiting = false;
  return { status: 'credential-stored', attempt: { id: 'attempt-1', phase: 'succeeded' } };
}, client, localOrigin, () => stillWaiting, async () => {}, async () => {}, () => true), 'signed-in');

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
  const moduleDir = join(root, 'runtime');
  const credentialsHome = join(root, 'credential-persistence');
  await mkdir(credentialsHome, { mode: 0o700 });
  const { Context } = await import(pathToFileURL(join(moduleDir, 'node_modules/@deepseek-ai/cordis/lib/index.js')));
  const { default: MemoryCredentials } = await import(pathToFileURL(join(moduleDir, 'credentials.mjs')));
  const previousDshHome = process.env.DSH_HOME;
  process.env.DSH_HOME = credentialsHome;
  try {
    const first = new Context();
    const second = new Context();
    await Promise.all([first.plugin(MemoryCredentials), second.plugin(MemoryCredentials)]);
    const grantKey = 'deepseek-account-platform/default';
    const deviceKey = 'deepseek-account-platform/device';
    const grant = { kind: 'grant', payload: { version: 1, issuer: 'https://platform.deepseek.com', token: 'fixture-grant' } };
    const device = { kind: 'grant', payload: { id: '03bd2539-c4d0-47e7-a078-623cae144575' } };
    await first.credentials.set('DEEPSEEK_API_KEY', 'fixture-session-only');
    await Promise.all([first.credentials.modifyRecord(grantKey, () => grant),
      second.credentials.modifyRecord(deviceKey, () => device)]);
    const restarted = new Context();
    await restarted.plugin(MemoryCredentials);
    assert.deepEqual(await restarted.credentials.readRecord(grantKey), grant);
    assert.deepEqual(await restarted.credentials.readRecord(deviceKey), device);
    assert.equal(await restarted.credentials.resolve('DEEPSEEK_API_KEY'), undefined);
    const path = join(credentialsHome, '.harmony-account-credentials.json');
    assert.equal((await stat(path)).mode & 0o777, 0o600);
    await restarted.credentials.deleteRecord(grantKey);
    assert.equal(await first.credentials.readRecord(grantKey), undefined);
    assert.deepEqual(await first.credentials.readRecord(deviceKey), device);
    await chmod(path, 0o644);
    await assert.rejects(first.credentials.readRecord(deviceKey), /账号凭据/);
    await chmod(path, 0o600);
    await writeFile(path, '{"invalid":"fixture-secret"}');
    await assert.rejects(first.credentials.modifyRecord(grantKey, () => grant), error =>
      /账号凭据/.test(error.message) && !error.message.includes('fixture-secret'));
    assert.equal(await readFile(path, 'utf8'), '{"invalid":"fixture-secret"}');
    assert.equal((await first.credentials.resolve('DEEPSEEK_API_KEY')).value, 'fixture-session-only');
    console.log('账号授权跨重启、并行写入、退出和损坏文件检查通过');
  } finally {
    if (previousDshHome === undefined) delete process.env.DSH_HOME;
    else process.env.DSH_HOME = previousDshHome;
  }
  const DshClient = await loadDshClient(clientPath, runtime, root);
  let platformOrigin;
  let oauth;
  let exchanged = 0;
  let revokedGrant = false;
  const platform = createServer(async (req, res) => {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const body = JSON.parse(Buffer.concat(chunks).toString() || '{}');
    let data = {};
    switch (req.url) {
      case '/models':
        assert.equal(req.headers['x-dsh-auth-token'], 'fixture-oauth-grant');
        res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({
          data: ['deepseek-flash', 'deepseek-pro'].map(id => ({ id, api_capabilities: { anthropic_messages: {} } }))
        }));
        return;
      case '/auth-api/v0/dsh/auth_init':
        assert.equal(body.code_challenge_method, 'S256');
        assert.equal(body.login_source, 'web');
        oauth = body;
        data = { authorize_url: platformOrigin + '/dsh/authorize?fixture=1', authorize_id: 'fixture-attempt', expires_in: 90 };
        break;
      case '/auth-api/v0/dsh/auth_exchange':
        assert.equal(body.code, 'fixture-code');
        assert.equal(body.redirect_uri, oauth.redirect_uri);
        assert.ok(body.code_verifier.length >= 43);
        exchanged++;
        data = { token: 'fixture-oauth-grant', authorized_url: platformOrigin + '/dsh/authorized' };
        break;
      case '/auth-api/v0/dsh/auth_cancel':
        assert.equal(body.authorize_id, 'fixture-attempt');
        break;
      case '/auth-api/v0/users/logout':
        assert.equal(req.headers['x-dsh-auth-token'], 'fixture-oauth-grant');
        revokedGrant = true;
        break;
      default:
        res.writeHead(404).end();
        return;
    }
    res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ code: 0,
      data: { biz_code: 0, biz_data: data } }));
  });
  platform.listen(0, '127.0.0.1');
  await once(platform, 'listening');
  platformOrigin = `http://127.0.0.1:${platform.address().port}`;
  const client = new DshClient();
  let child;
  let ended;
  const stop = async () => {
    client.close();
    if (!child) return;
    if (child.exitCode === null && child.signalCode === null) {
      if (await stat(join(home, 'ready.json')).then(() => true, () => false)) await writeFile(join(home, 'stop'), '');
      else child.kill('SIGTERM');
      if (!await Promise.race([ended.then(() => true), delay(2500, false, { ref: false })])) child.kill('SIGKILL');
    }
    await ended;
    child = undefined;
  };
  const start = async () => {
    child = spawn(process.execPath, ['--jitless', '--no-addons', '--expose-internals', '--require', flockFixture,
      runtime, home], { cwd: root, env: { HOME: root, PATH: `${dirname(process.execPath)}:/usr/bin:/bin` }, stdio: 'ignore' });
    ended = once(child, 'exit');
    let ready;
    for (let i = 0; i < 200 && !ready && child.exitCode === null; i++) {
      ready = await readFile(join(home, 'ready.json'), 'utf8').then(JSON.parse, () => undefined);
      if (!ready) await delay(100);
    }
    assert.equal(typeof ready?.url, 'string', 'Isolated DSH did not publish readiness');
    await client.connect(ready.url, undefined, true);
    return new URL(ready.url).origin;
  };
  const waitAttempt = async phase => {
    for (let i = 0; i < 120; i++) {
      const state = await client.request('account/getState');
      if (state.attempt?.phase === phase) return state;
      assert.notEqual(state.attempt?.phase, 'failed', `OAuth attempt failed with ${state.attempt?.errorCode}`);
      await delay(50);
    }
    assert.fail(`OAuth attempt did not reach ${phase}`);
  };
  try {
    await mkdir(home, { mode: 0o700 });
    await writeFile(join(home, 'cordis.patch.yml'), JSON.stringify([{ id: 'deepseek-account',
      config: { platformOrigin, inferenceOrigin: platformOrigin, allowLoopbackHttp: true } },
    { id: 'llm-deepseek-account', config: { baseURL: platformOrigin } }]));
    const callbackOrigin = await start();
    assert.equal(client.localAccountCallbackOrigin(), callbackOrigin);
    const metadata = { version: '1.0.0', locale: 'zh-CN', timezoneOffsetSeconds: 28800 };
    const views = [];
    await loadAccountOverview((method, args, timeout) => client.request(method, args, timeout),
      metadata, () => true, view => views.push(view));
    assert.deepEqual(views, [{ status: 'signed-out' }]);
    const args = { client: metadata, callbackOrigin, loginSource: 'web' };
    await assert.rejects(client.request('account/startSignIn', { ...args, callbackOrigin: 'https://example.invalid' }));
    await client.request('account/startSignIn', args);
    const waiting = await waitAttempt('waiting-browser');
    const cancelled = await client.request('account/cancelSignIn', { attemptId: waiting.attempt.id });
    assert.equal(cancelled.status, 'signed-out');
    assert.equal(cancelled.attempt.phase, 'cancelled');
    await client.request('account/startSignIn', args);
    await waitAttempt('waiting-browser');
    assert.equal(oauth.redirect_uri, callbackOrigin + '/oauth/callback');
    const callback = new URL(oauth.redirect_uri);
    callback.searchParams.set('code', 'fixture-code');
    callback.searchParams.set('state', 'wrong-state');
    assert.equal((await fetch(callback, { redirect: 'manual' })).status, 400);
    assert.equal(exchanged, 0);
    callback.searchParams.set('state', oauth.state);
    const accepted = await fetch(callback, { redirect: 'manual' });
    assert.equal(accepted.status, 302);
    assert.equal(accepted.headers.get('location'), platformOrigin + '/dsh/authorized?login_source=web');
    assert.equal(exchanged, 1);
    const signedIn = await waitAttempt('succeeded');
    assert.equal(signedIn.status, 'credential-stored');
    assert.doesNotMatch(JSON.stringify(signedIn), /fixture-oauth-grant/);
    const models = await client.listModels();
    assert.ok(models.groups.some(group => group.id === 'deepseek-account' && group.models.length > 0));
    await client.request('session/initializeDefaultModel');
    assert.equal((await client.listModels()).defaultSelection.provider, 'deepseek-account');
    await stop();
    await start();
    assert.equal((await client.request('account/getState')).status, 'credential-stored');
    assert.equal((await client.listModels()).defaultSelection.provider, 'deepseek-account');
    assert.equal((await client.request('account/signOut', { client: metadata })).status, 'signed-out');
    for (let i = 0; i < 40 && !revokedGrant; i++) await delay(50);
    assert.equal(revokedGrant, true);
    await stop();
    await start();
    assert.equal((await client.request('account/getState')).status, 'signed-out');
    console.log('隔离 DSH 原版账号 RPC 已验证取消、回调状态校验、登录、默认账号模型、重启保留与退出撤销');
  } finally {
    await stop();
    platform.closeAllConnections();
    await new Promise(resolve => platform.close(resolve));
  }
}
