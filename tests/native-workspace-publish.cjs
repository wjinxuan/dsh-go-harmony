const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');

const data = process.argv[2];
const root = path.join(data, 'workspace');
fs.mkdirSync(root, { recursive: true, mode: 0o700 });
const test = fs.mkdtempSync(path.join(root, 'native-publish-'));
const outside = fs.mkdtempSync(path.join(data, 'outside-'));
const publish = globalThis.dshHarmonyPublishWorkspaceFile;
assert.equal(typeof publish, 'function');
function stageFor(final, content = 'new file') {
  const folder = path.join(path.dirname(final), `.${path.basename(final)}.${process.pid}.${randomUUID()}.tmpdir`);
  fs.mkdirSync(folder, { mode: 0o700 });
  const stage = path.join(folder, `${path.basename(final)}.tmp`);
  fs.writeFileSync(stage, content);
  return stage;
}
try {
  const final = path.join(test, 'hello.md');
  const stage = stageFor(final);
  publish(stage, final);
  assert.equal(fs.readFileSync(final, 'utf8'), 'new file');
  assert.equal(fs.existsSync(stage), false);
  const collision = stageFor(final, 'must not replace');
  assert.throws(() => publish(collision, final), { code: 'EEXIST', syscall: 'renameat2' });
  assert.equal(fs.readFileSync(final, 'utf8'), 'new file');
  assert.equal(fs.readFileSync(collision, 'utf8'), 'must not replace');
  assert.throws(() => publish(collision + '\0', final), TypeError);
  assert.throws(() => publish(collision.replace(String(process.pid), '999999999'), final), TypeError);

  const external = path.join(outside, 'outside.md');
  const externalStage = stageFor(external);
  assert.throws(() => publish(externalStage, external), TypeError);
  assert.equal(fs.existsSync(external), false);

  const escaped = path.join(test, 'escape');
  fs.symlinkSync(outside, escaped);
  assert.throws(() => publish(externalStage.replace(outside, escaped), external.replace(outside, escaped)), TypeError);
  const linkedFinal = path.join(test, 'linked.md');
  const linkedStage = stageFor(linkedFinal);
  fs.unlinkSync(linkedStage);
  fs.symlinkSync(final, linkedStage);
  assert.throws(() => publish(linkedStage, linkedFinal), TypeError);
  assert.equal(fs.existsSync(linkedFinal), false);

  const nested = path.join(test, 'nested');
  fs.mkdirSync(nested);
  const nestedFinal = path.join(nested, 'nested.txt');
  const nestedStage = stageFor(nestedFinal, 'nested');
  publish(nestedStage, nestedFinal);
  assert.equal(fs.readFileSync(nestedFinal, 'utf8'), 'nested');
  console.log('Native workspace publish: atomic create, collision, path confinement and symlink refusal passed');
} finally {
  fs.rmSync(test, { recursive: true, force: true });
  fs.rmSync(outside, { recursive: true, force: true });
}
