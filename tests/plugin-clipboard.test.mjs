import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
const source = await readFile(new URL('../entry/src/main/ets/ui/NativePluginActions.ets', import.meta.url), 'utf8');
const methods = source.slice(source.indexOf('  private current('), source.indexOf('  build()'));
test('clipboard plugin actions require system paste consent and never forward data after a host switch', async () => {
  let reads = 0, identity = 1, value = Promise.resolve({ getPrimaryText: () => 'clipboard contents' });
  const calls = [];
  const Owner = vm.runInNewContext(stripTypeScriptTypes(`class Owner { ${methods} }; Owner`), {
    Error, object: v => v || {}, nativePluginLocale: () => 'en', pluginReplyEffects: () => [],
    pasteboard: { getSystemPasteboard: () => ({ getData: async () => { reads++; return value; } }) },
    NativePluginConnection: class { async open() { return 'stream'; } async result(v) { return v; } }
  });
  const owner = new Owner(); Object.assign(owner, { t: v => v, generation: 1, identity: 1, surface: 'composer.actions', scope: { sessionId: 'chat' }, draft: 'draft',
    client: { connectionIdentity: () => identity, bridgeJson: async (...args) => { calls.push(args); return {}; } } });
  const place = { pkg: 'fixture', id: 'paste', wants: ['clipboard'], effects: [] };
  await owner.tap(place); assert.equal(reads, 0); assert.equal(calls.length, 0);
  await owner.tap(place, true); assert.equal(reads, 1); assert.equal(calls.length, 1);
  assert.equal(calls[0][3].context.clipboard, 'clipboard contents');
  let resolve; value = new Promise(done => { resolve = done; });
  const pending = owner.tap(place, true); identity = 2; resolve({ getPrimaryText: () => 'private old host text' }); await pending;
  assert.equal(calls.length, 1);
});
