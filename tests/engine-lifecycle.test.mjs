import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { EngineLifecycle, HEALTHY_MS, redactEngineLog } from '../runtime/engine-lifecycle.mjs';
function root(t) { const path = mkdtempSync(join(tmpdir(), 'engine-life-')); t.after(() => rmSync(path, { recursive: true, force: true })); return path; }
function command(path, values) { writeFileSync(join(path, 'runtime-command.json'), JSON.stringify({ requestId: randomUUID(), ...values })); }
test('two counted normal startup failures select safe mode without deleting normal profile', t => {
  const path = root(t); mkdirSync(join(path, 'profile')); writeFileSync(join(path, 'profile/cordis.patch.yml'), 'user settings');
  let run = new EngineLifecycle(path); run.failed(new Error('bad plugin')); assert.equal(run.state.safeState, 'off');
  run = new EngineLifecycle(path); run.failed(new Error('bad plugin')); assert.equal(run.state.safeState, 'on');
  run = new EngineLifecycle(path); assert.equal(run.safe, true); run.failed(new Error('safe failed')); assert.equal(run.state.strikes, 2);
  assert.equal(readFileSync(join(path, 'profile/cordis.patch.yml'), 'utf8'), 'user settings');
});
test('normal trial returns to safe after one early failure', t => {
  const path = root(t); command(path, { mode: 'safe' }); let run = new EngineLifecycle(path); run.stopped();
  command(path, { mode: 'normal' }); run = new EngineLifecycle(path); assert.equal(run.state.safeState, 'probation');
  run.ready(); run.failed(new Error('failed')); assert.equal(run.state.safeState, 'on'); assert.equal(run.state.safeReason, 'probation');
  run = new EngineLifecycle(path); assert.equal(run.safe, true, 'old normal command cannot reset automatic safe state'); run.stopped();
});
test('auto-safe disabled, full disk and killed process do not spuriously select safe', t => {
  const path = root(t); command(path, { autoSafe: false });
  for (let i = 0; i < 3; i++) new EngineLifecycle(path).failed(new Error('bad'));
  let run = new EngineLifecycle(path); assert.equal(run.safe, false); const strikes = run.state.strikes;
  run.failed(Object.assign(new Error('disk full'), { code: 'ENOSPC' })); assert.equal(run.state.strikes, strikes);
  run = new EngineLifecycle(path); run = new EngineLifecycle(path); assert.equal(run.state.failure.kind, 'killed'); assert.equal(run.state.strikes, strikes); run.stopped();
});
test('healthy normal run saves good profile and clears strikes; late crash does not count', t => {
  const path = root(t); let now = 1000; mkdirSync(join(path, 'profile')); writeFileSync(join(path, 'profile/cordis.patch.yml'), '[]\n');
  let run = new EngineLifecycle(path, { now: () => now }); run.failed(new Error('once'));
  run = new EngineLifecycle(path, { now: () => now }); run.ready(); now += HEALTHY_MS; run.healthy();
  assert.equal(run.state.strikes, 0); assert.equal(readFileSync(join(path, 'profile/cordis.good.patch.yml'), 'utf8'), '[]\n');
  run.failed(new Error('late')); assert.equal(run.state.strikes, 0); assert.equal(run.state.failure.kind, 'crashedLate');
});
test('runtime log redacts credential formats and never contains URL login secrets', t => {
  const path = root(t); const run = new EngineLifecycle(path);
  const raw = 'Bearer eyJ_token apiKey=private123 https://a:p@host/?token=token123 sk-123456789012 password="hide"';
  run.log(raw); run.stopped(); const log = readFileSync(join(path, 'runtime.log'), 'utf8');
  for (const secret of ['eyJ_token', 'private123', 'a:p@', 'token123', 'sk-123456789012', 'hide']) assert.equal(log.includes(secret), false);
  assert.match(redactEngineLog(raw), /redacted/);
});
test('a new ready run clears the stale failure persistently without resetting strikes or probation before healthy', t => {
  const path = root(t); let now = 1000;
  let run = new EngineLifecycle(path, { now: () => now }); run.failed(new Error('owned prior early failure'));
  command(path, { mode: 'safe' }); run = new EngineLifecycle(path, { now: () => ++now }); run.stopped();
  command(path, { mode: 'normal' }); run = new EngineLifecycle(path, { now: () => ++now });
  const before = { strikes: run.state.strikes, safeState: run.state.safeState, safeReason: run.state.safeReason };
  assert.ok(run.state.failure, 'failure remains diagnosable until the new run is actually ready');
  assert.equal(before.safeState, 'probation'); assert.equal(before.strikes, 1);
  run.ready();
  assert.equal(run.state.failure, undefined);
  assert.deepEqual({ strikes: run.state.strikes, safeState: run.state.safeState, safeReason: run.state.safeReason }, before);
  assert.equal(readFileSync(join(path, 'runtime.log'), 'utf8').includes('owned prior early failure'), true, 'history is retained');
  assert.equal(JSON.parse(readFileSync(join(path, 'runtime-state.json'), 'utf8')).failure, undefined, 'clear is persisted');
  run.stopped(); run = new EngineLifecycle(path, { now: () => ++now });
  assert.equal(run.state.failure, undefined, 'a clean stopped restart does not resurrect the old failure'); run.stopped();
});
test('killed and safe-mode failures clear only on actual readiness; a later failure is still recorded', t => {
  const path = root(t); let now = 1000;
  new EngineLifecycle(path, { now: () => now });
  let run = new EngineLifecycle(path, { now: () => ++now });
  assert.equal(run.state.failure.kind, 'killed'); assert.equal(run.state.strikes, 0);
  run.ready(); assert.equal(run.state.failure, undefined); run.stopped();
  command(path, { mode: 'safe' }); run = new EngineLifecycle(path, { now: () => ++now });
  run.failed(new Error('owned safe startup failure'));
  run = new EngineLifecycle(path, { now: () => ++now });
  assert.equal(run.state.failure.kind, 'startupFailed'); assert.equal(run.safe, true);
  const before = { strikes: run.state.strikes, safeState: run.state.safeState, safeReason: run.state.safeReason };
  run.ready(); assert.equal(run.state.failure, undefined);
  assert.deepEqual({ strikes: run.state.strikes, safeState: run.state.safeState, safeReason: run.state.safeReason }, before);
  run.failed(new Error('owned later safe failure')); assert.equal(run.state.failure.kind, 'crashedEarly');
  assert.equal(run.state.failure.summary, 'owned later safe failure'); assert.equal(run.state.strikes, before.strikes);
});
