import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { once } from 'node:events';
import { setTimeout as delay } from 'node:timers/promises';
const [runtime, fixture] = process.argv.slice(2).map(p => resolve(p));
const home = await mkdtemp('/tmp/dsh-engine-recovery-');
let child;
const snapshot = name => readFile(join(home, name), 'utf8').then(JSON.parse, () => undefined);
const start = () => spawn(process.execPath, ['--jitless', '--no-addons', '--expose-internals', '--require', fixture,
  join(runtime, 'main.cjs'), home], { stdio: 'ignore' });
async function waitFor(check) {
  for (let i = 0; i < 300; i++) { const value = await check(); if (value) return value; await delay(100); }
  throw new Error('Recovery runtime timed out');
}
try {
  await mkdir(join(home, 'profile')); await mkdir(join(home, 'workspace'));
  await writeFile(join(home, 'profile/cordis.patch.yml'), 'invalid: [');
  await writeFile(join(home, 'workspace/kept.txt'), 'user workspace');
  await writeFile(join(home, '.harmony-account-credentials.json'), '{}');
  child = start(); await once(child, 'exit');
  let state = await snapshot('runtime-state.json'); assert.equal(state.strikes, 1); assert.equal(state.safeState, 'off');
  assert.ok(state.failure, 'actual failed startup remains diagnosable before recovery');
  child = start(); await waitFor(() => snapshot('ready.json'));
  state = await snapshot('runtime-state.json'); assert.equal(state.mode, 'safe'); assert.equal(state.phase, 'running');
  assert.equal(state.strikes, 2);
  assert.equal(state.safeReason, 'auto');
  assert.equal(state.failure, undefined, 'actual recovered readiness clears the stale failure without clearing safe-mode strikes');
  assert.equal(await readFile(join(home, 'profile/cordis.patch.yml'), 'utf8'), 'invalid: [');
  assert.equal(await readFile(join(home, 'workspace/kept.txt'), 'utf8'), 'user workspace');
  assert.equal(await readFile(join(home, '.harmony-account-credentials.json'), 'utf8'), '{}');
  await writeFile(join(home, 'stop'), ''); await once(child, 'exit');
  assert.equal((await snapshot('runtime-state.json')).phase, 'stopped');
  assert.equal((await snapshot('runtime-state.json')).failure, undefined);
  console.log('Engine recovery: two actual broken-profile boots recover with a clean safe profile; ready clears the stale failure but preserves strikes and auto-safe reason; original settings/account/workspace preserved.');
} finally { child?.kill('SIGTERM'); await rm(home, { recursive: true, force: true }); }
