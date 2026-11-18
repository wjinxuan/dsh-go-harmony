import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, stat, chmod, rm } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
const runtime = resolve(process.argv[2]);
const { Context } = await import(pathToFileURL(join(runtime, 'node_modules/@deepseek-ai/cordis/lib/index.js')));
const { default: Credentials } = await import(pathToFileURL(join(runtime, 'credentials.mjs')));
const root = await mkdtemp('/tmp/dsh-subscription-credentials-');
const previous = process.env.DSH_HOME; process.env.DSH_HOME = root;
const contexts = [];
async function host() { const ctx = new Context(); contexts.push(ctx); await ctx.plugin(Credentials); return ctx.credentials; }
try {
  const first = await host(), second = await host();
  const keys = ['llm-pi-ai/openai-codex', 'llm-pi-ai/anthropic'];
  const grant = suffix => ({ kind: 'grant', payload: { type: 'oauth', access: 'synthetic-access-' + suffix,
    refresh: 'synthetic-refresh-' + suffix, expires: Date.now() + 3600000, accountId: suffix } });
  await Promise.all([first.modifyRecord(keys[0], () => grant('a')), second.modifyRecord(keys[1], () => grant('b'))]);
  const restarted = await host();
  for (const [i, key] of keys.entries()) assert.equal((await restarted.readRecord(key)).payload.accountId, i ? 'b' : 'a');
  const path = join(root, '.harmony-subscription-credentials.json'); assert.equal((await stat(path)).mode & 0o777, 0o600);
  assert.equal(await readFile(join(root, '.harmony-account-credentials.json')).catch(() => undefined), undefined);
  await Promise.all([first.modifyRecord(keys[0], record => ({ ...record, payload: { ...record.payload, access: 'refreshed' } })),
    second.modifyRecord(keys[1], record => record)]);
  assert.equal((await restarted.readRecord(keys[0])).payload.access, 'refreshed');
  await restarted.deleteRecord(keys[0]); assert.equal(await first.readRecord(keys[0]), undefined);
  assert.ok(await first.readRecord(keys[1]));
  const intact = await readFile(path, 'utf8');
  await assert.rejects(first.modifyRecord(keys[0], () => ({ kind: 'grant', payload: { type: 'oauth', access: 'secret' } })), /授权/);
  assert.equal(await readFile(path, 'utf8'), intact);
  await chmod(path, 0o644); await assert.rejects(first.readRecord(keys[1]), /凭据/); await chmod(path, 0o600);
  await writeFile(path, '{"unknown":"secret"}');
  await assert.rejects(first.modifyRecord(keys[0], () => grant('a')), error => !error.message.includes('secret'));
  assert.equal(await readFile(path, 'utf8'), '{"unknown":"secret"}');
  console.log('Subscription credentials: independent 0600 persistence, concurrent refresh, restart, sign-out and corrupt-file refusal passed.');
} finally {
  for (const ctx of contexts) await ctx.fiber.dispose();
  if (previous === undefined) delete process.env.DSH_HOME; else process.env.DSH_HOME = previous;
  await rm(root, { recursive: true, force: true });
}
