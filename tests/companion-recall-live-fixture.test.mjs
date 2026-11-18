import './require-runtime-node.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter, once } from 'node:events';
import { readFile } from 'node:fs/promises';

const source = await readFile(new URL('./companion-recall-live.mjs', import.meta.url), 'utf8');
const stop = source.match(/async function stop\(\)[\s\S]*?(?=\nasync function session)/)[0];
const until = source.match(/async function until\([\s\S]*?(?=\nconst savedDir)/)[0];
const tick = () => new Promise(resolve => setImmediate(resolve));

function harness() {
  const timers = [];
  const delay = (_ms, _value, options) => new Promise((resolve, reject) => {
    const timer = { active: true, fire: () => { if (timer.active) { timer.active = false; resolve(); } } };
    timers.push(timer);
    options?.signal?.addEventListener('abort', () => {
      if (timer.active) { timer.active = false; reject(Object.assign(new Error('aborted'), { name: 'AbortError' })); }
    }, { once: true });
  });
  const fixture = Function('delay', 'once', 'writeFile', 'join', `
    let child; const client={close(){}}; const home='/unused'; const log='isolated test process';
    ${stop}
    ${until}
    return {stop,until,setChild(value){child=value}};
  `)(delay, once, async () => {}, (...parts) => parts.join('/'));
  return { ...fixture, timers };
}

function processFixture() {
  const child = new EventEmitter();
  child.exitCode = null;
  child.signalCode = null;
  child.kills = [];
  child.kill = signal => { child.kills.push(signal); return true; };
  child.finish = (code = 0, signal = null) => { child.exitCode = code; child.signalCode = signal; child.emit('exit', code, signal); };
  return child;
}

test('a completed stop cannot later kill the next runtime after restart', async () => {
  const h = harness(), previous = processFixture(), successor = processFixture();
  h.setChild(previous);
  const stopping = h.stop();
  await tick();
  previous.finish();
  await stopping;
  h.setChild(successor);
  h.timers.forEach(timer => timer.fire());
  await tick();
  assert.deepEqual(successor.kills, [], 'old stop watchdog must not target new global child');
  assert.deepEqual(previous.kills, []);
  assert.ok(h.timers.every(timer => !timer.active));
});

test('a stop watchdog targets only its captured process and waits for actual exit', async () => {
  const h = harness(), previous = processFixture(), successor = processFixture();
  h.setChild(previous);
  let done = false;
  const stopping = h.stop().then(() => { done = true; });
  await tick();
  h.setChild(successor);
  h.timers[0].fire();
  await tick();
  try {
    assert.deepEqual(previous.kills, ['SIGKILL']);
    assert.deepEqual(successor.kills, []);
    assert.equal(done, false, 'next boot must not race a still-exiting old process');
  } finally { previous.finish(null, 'SIGKILL'); await stopping; }
});

test('runtime readiness reports signal exit instead of misclassifying it as timeout', async () => {
  const h = harness(), stopped = processFixture();
  stopped.finish(null, 'SIGKILL');
  h.setChild(stopped);
  const pending = h.until(async () => undefined, 'runtime ready').then(
    value => ({ value }), error => ({ error }));
  // The old loop waits on delay even though the child is already signal-dead.
  await tick();
  for (let i = 0; i < 351; i++) { h.timers.forEach(timer => timer.fire()); await tick(); }
  const outcome = await pending;
  assert.match(outcome.error?.message ?? '', /Runtime exited \(SIGKILL\)/);
});
