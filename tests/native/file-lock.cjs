const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const name = path.join(process.argv[2], 'native-file-lock');
const first = fs.openSync(name, 'a+', 0o600);
const second = fs.openSync(name, 'a+', 0o600);
let firstOpen = true;
try {
  const lock = globalThis.dshHarmonyTryLock;
  assert.equal(typeof lock, 'function');
  assert.equal(lock(first), true);
  assert.equal(lock(second), false, 'an independently opened descriptor must contend');
  fs.closeSync(first);
  firstOpen = false;
  assert.equal(lock(second), true, 'closing the owner releases the actual kernel lock');
  assert.throws(() => lock(-1), TypeError);
  assert.throws(() => lock('1'), TypeError);
  console.log('Native file lock: real POSIX contention, release/reacquire and invalid descriptor refusal passed');
} finally {
  if (firstOpen) fs.closeSync(first);
  fs.closeSync(second);
  fs.unlinkSync(name);
}
