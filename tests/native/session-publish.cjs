'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const publish = globalThis.dshHarmonyPublishFile;
assert.equal(typeof publish, 'function');
const dir = fs.mkdtempSync(path.join(process.argv[2], 'session-publish-'));
const final = path.join(dir, 'session.v4.jsonl.zstd');
const stage = `${final}.0123456789ab.tmp`;
try {
  fs.writeFileSync(stage, 'first log');
  publish(stage, final);
  assert.equal(fs.existsSync(stage), false);
  assert.equal(fs.readFileSync(final, 'utf8'), 'first log');

  fs.writeFileSync(stage, 'should remain temporary');
  assert.throws(() => publish(stage, final), { code: 'EEXIST', syscall: 'renameat2', path: stage, dest: final });
  assert.equal(fs.readFileSync(stage, 'utf8'), 'should remain temporary');
  assert.equal(fs.readFileSync(final, 'utf8'), 'first log');
  assert.throws(() => publish(`${stage}\0`, final), TypeError);
  assert.throws(() => publish(stage, path.join(dir, 'other.v4.jsonl.zstd')), TypeError);
  assert.throws(() => publish(stage, path.join(dir, 'other', 'session.v4.jsonl.zstd')), TypeError);

  fs.unlinkSync(stage);
  fs.unlinkSync(final);
  assert.throws(() => publish(stage, final), { code: 'ENOENT', syscall: 'renameat2' });
  console.log(`Native session publish (Node ${process.versions.node}): atomic create, collision, errno and paths passed`);
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}
