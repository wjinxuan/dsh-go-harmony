import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rename, rm, symlink } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { resetBeforeStart } from '../runtime/engine-reset.mjs';
import { randomBytes } from 'node:crypto';
import { PrivateVault } from '../runtime/private-vault.mjs';
async function fixture(t) {
  const base = await mkdtemp('/tmp/dsh-reset-test-'), root = join(base, 'data');
  t.after(() => rm(base, { recursive: true, force: true })); await mkdir(root); return root;
}
async function file(root, path, text = path) { await mkdir(dirname(join(root, path)), { recursive: true }); await writeFile(join(root, path), text); }
const plan = (uiAndSkills, pluginsAndSettings) => ({ version: 1, uiAndSkills, pluginsAndSettings });
test('no explicit reset request never changes existing user data', async t => {
  const root = await fixture(t); await file(root, 'workspace/data', 'keep'); assert.equal(await resetBeforeStart(root), false);
  assert.equal(await readFile(join(root, 'workspace/data'), 'utf8'), 'keep');
});
test('reset preserves exactly selected UI/skills and config; removes chats/accounts/model/workspace', async t => {
  const root = await fixture(t);
  const kept = ['dsh-go/ui.json', 'skills/a.md', 'workspace/.dsh/skills/b.md', 'workspace/.agents/skills/c.md', 'profile/cordis.patch.yml', '.env', 'cordis.patch.yml', '.harmony-bundled-bot.json'];
  const removed = ['sessions/chat.jsonl', '.harmony-account-credentials.json', '.harmony-subscription-credentials.json', 'speech-to-text/sensevoice/models/a', 'workspace/source.txt'];
  for (const path of [...kept, ...removed]) await file(root, path);
  await writeFile(root + '.reset-request', JSON.stringify(plan(true, true)));
  assert.equal(await resetBeforeStart(root), true);
  for (const path of kept) assert.equal(await readFile(join(root, path), 'utf8'), path);
  for (const path of removed) await assert.rejects(readFile(join(root, path)), { code: 'ENOENT' });
});
test('interrupted preserve resumes moved paths and removes retired only after completing', async t => {
  const root = await fixture(t); await file(root, 'dsh-go/ui.json', 'ui'); await file(root, 'profile/cordis.patch.yml', 'cfg');
  await file(root, 'harmony-reset-plan.json', JSON.stringify(plan(true, true))); await rename(root, root + '.retired');
  await mkdir(root); await rename(root + '.retired/dsh-go', root + '/dsh-go');
  assert.equal(await resetBeforeStart(root), true);
  assert.equal(await readFile(root + '/dsh-go/ui.json', 'utf8'), 'ui');
  assert.equal(await readFile(root + '/profile/cordis.patch.yml', 'utf8'), 'cfg');
  await assert.rejects(readFile(root + '.retired/harmony-reset-plan.json'), { code: 'ENOENT' });
});
test('preservation conflict or malicious plan leaves retired data recoverable', async t => {
  const root = await fixture(t); await file(root, 'profile/cordis.patch.yml', 'old');
  await file(root, 'harmony-reset-plan.json', JSON.stringify(plan(false, true))); await rename(root, root + '.retired');
  await file(root, 'profile/cordis.patch.yml', 'new');
  await assert.rejects(resetBeforeStart(root), /conflicts/);
  assert.equal(await readFile(root + '.retired/profile/cordis.patch.yml', 'utf8'), 'old');
  assert.equal(await readFile(root + '/profile/cordis.patch.yml', 'utf8'), 'new');
});
test('unrecognized reset fields cannot supply paths to delete', async t => {
  const root = await fixture(t); await file(root, 'workspace/keep', 'keep');
  await writeFile(root + '.reset-request', JSON.stringify({ ...plan(false, false), path: '/' }));
  await assert.rejects(resetBeforeStart(root), /Invalid reset/);
  assert.equal(await readFile(root + '/workspace/keep', 'utf8'), 'keep');
});
test('symlinked skill ancestors cannot move data outside retired runtime', async t => {
  const root = await fixture(t); const external = root + '-external'; await mkdir(external); await file(external, 'skills/keep', 'outside');
  await mkdir(root + '/workspace'); await symlink(external, root + '/workspace/.dsh');
  await writeFile(root + '.reset-request', JSON.stringify(plan(true, false)));
  await assert.rejects(resetBeforeStart(root), /Unsafe reset source/);
  assert.equal(await readFile(external + '/skills/keep', 'utf8'), 'outside');
});
test('generic encrypted credentials follow the plugins/settings preservation choice exactly', async t => {
  for (const keep of [true, false]) {
    const root = await fixture(t), key = randomBytes(32).toString('base64url');
    const vault = new PrivateVault(root, '.harmony-provider-credentials.json', key);
    const value = { version: 1, refs: { SYNTHETIC_API_KEY: 'reset-fixture-secret' } };
    await vault.save(value); const before = await readFile(vault.path);
    await writeFile(root + '.reset-request', JSON.stringify(plan(false, keep)));
    assert.equal(await resetBeforeStart(root), true);
    if (keep) { assert.deepEqual(await readFile(vault.path), before); assert.deepEqual(await vault.load(), value); }
    else await assert.rejects(readFile(vault.path), { code: 'ENOENT' });
    vault.destroy();
  }
});
