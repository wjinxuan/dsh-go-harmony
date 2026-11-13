import assert from 'node:assert/strict';
import test from 'node:test';
import { asset, assetReturnType, failAsset, storedAsset } from './onboarding-fixture.mjs';
import { hasLocalApiKey, loadLocalApiKey, removeLocalApiKey, saveLocalApiKey } from './local/LocalKeyStore.ts';
import {
  loadAppPreferences, loadOnboardingComplete, saveAppPreferences, saveOnboardingComplete
} from './ui/AppPreferences.ts';

test('stores one app-local protected asset, overwrites it and removes it idempotently', async () => {
  assert.equal(await loadLocalApiKey(), undefined);
  assert.equal(await hasLocalApiKey(), false);
  assert.equal(assetReturnType(), asset.ReturnType.ATTRIBUTES);
  await removeLocalApiKey();
  await saveLocalApiKey('  fixture-one  ');
  assert.equal(await hasLocalApiKey(), true);
  assert.equal(assetReturnType(), asset.ReturnType.ATTRIBUTES);
  assert.equal(await loadLocalApiKey(), 'fixture-one');
  assert.equal(assetReturnType(), asset.ReturnType.ALL);
  const attributes = storedAsset();
  assert.equal(attributes.get(asset.Tag.ACCESSIBILITY), asset.Accessibility.DEVICE_UNLOCKED);
  assert.equal(attributes.get(asset.Tag.SYNC_TYPE), asset.SyncType.NEVER);
  assert.equal(attributes.get(asset.Tag.CONFLICT_RESOLUTION), asset.ConflictResolution.OVERWRITE);
  assert.equal(attributes.has(asset.Tag.IS_PERSISTENT), false);
  await saveLocalApiKey('fixture-two');
  assert.equal(await loadLocalApiKey(), 'fixture-two');
  await removeLocalApiKey();
  await removeLocalApiKey();
  assert.equal(await loadLocalApiKey(), undefined);
});

test('rejects malformed or oversized input and sanitizes platform failures while allowing retry', async () => {
  await assert.rejects(saveLocalApiKey('fixture\n值'), /非 ASCII/);
  await assert.rejects(saveLocalApiKey('x'.repeat(1025)), /太长/);
  assert.equal(await loadLocalApiKey(), undefined);
  await saveLocalApiKey('fixture-before-lock');
  try {
    failAsset({ code: asset.ErrorCode.STATUS_MISMATCH, message: 'internal fixture diagnostic' });
    await assert.rejects(loadLocalApiKey(), { message: '无法访问已保存的 API Key。请解锁手机后重试。' });
    failAsset({ code: 24000008, message: 'internal fixture diagnostic' });
    await assert.rejects(hasLocalApiKey(), { message: '无法检查已保存的 API Key，请重试。' });
    await assert.rejects(saveLocalApiKey('fixture-unused'), { message: '无法保存 API Key，请重试。' });
    await assert.rejects(removeLocalApiKey(), { message: '无法移除已保存的 API Key，请重试。' });
  } finally {
    failAsset(undefined);
  }
  assert.equal(await loadLocalApiKey(), 'fixture-before-lock');
  await removeLocalApiKey();
});

test('adds onboarding completion without changing preferences saved by an earlier app version', async () => {
  const appearance = { accentId: 'dusk', themeMode: 'dark', fontSize: 18 };
  await saveAppPreferences({}, appearance);
  assert.equal(await loadOnboardingComplete({}), false);
  await saveOnboardingComplete({});
  assert.equal(await loadOnboardingComplete({}), true);
  assert.deepEqual(await loadAppPreferences({}), appearance);
  await saveAppPreferences({}, { accentId: 'mist', themeMode: 'system', fontSize: 16 });
  assert.equal(await loadOnboardingComplete({}), true);
});
