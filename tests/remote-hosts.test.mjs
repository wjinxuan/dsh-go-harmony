import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';
import { deleteRemoteHost, getRemoteHostConnection, listRemoteHosts, remoteHostConnection, saveRemoteHost } from './remote/RemoteHosts.ts';
import { asset, failOnce, lastQueryType, persistedMetadata, resetStorage, storedAssets } from './remote-hosts-fixture.mjs';

const context = {};
const hostToken = 'example-test-token';
const proxyValue = 'Bearer example-test-proxy';
const hostUrl = `https://fixture.invalid/dsh/?token=${hostToken}&extra=keep`;
const draft = (fields = {}) => ({ id: '', name: '测试电脑', launchUrl: hostUrl,
  authorization: proxyValue, remember: false, ...fields });
beforeEach(resetStorage);

test('persists allowlisted metadata only and opts into encrypted credential storage explicitly', async () => {
  const host = await saveRemoteHost(context, draft());
  assert.equal(host.hasCredential, false);
  assert.deepEqual(storedAssets(), []);
  assert.deepEqual(persistedMetadata(), [{ id: host.id, name: '测试电脑', origin: 'https://fixture.invalid' }]);
  assert.equal(await getRemoteHostConnection(host), undefined);
  const saved = await saveRemoteHost(context, draft({ id: host.id, remember: true }));
  assert.equal(saved.id, host.id);
  assert.equal(saved.hasCredential, true);
  const [record] = storedAssets();
  assert.equal(record.get(asset.Tag.ACCESSIBILITY), asset.Accessibility.DEVICE_UNLOCKED);
  assert.equal(record.get(asset.Tag.SYNC_TYPE), asset.SyncType.NEVER);
  assert.deepEqual(await listRemoteHosts(context), [saved]);
  assert.equal(lastQueryType(), asset.ReturnType.ATTRIBUTES);
  assert.deepEqual(await getRemoteHostConnection(saved), {
    id: saved.id, name: saved.name, launchUrl: hostUrl, authorization: proxyValue
  });
  assert.doesNotMatch(JSON.stringify(persistedMetadata()), /token=|example-test|Bearer|extra=|\/dsh/);
});

test('retains IDs, blocks duplicate origins and removes credentials on opt out or delete', async () => {
  const initial = await saveRemoteHost(context, draft({ remember: true }));
  await assert.rejects(saveRemoteHost(context, draft({ launchUrl: 'https://FIXTURE.INVALID:443/?token=test' })), /已在列表/);
  const renamed = await saveRemoteHost(context, draft({ id: initial.id, name: '已重命名', launchUrl: '', authorization: '', remember: true }));
  assert.equal(renamed.id, initial.id);
  assert.equal((await getRemoteHostConnection(renamed))?.launchUrl, hostUrl);
  const revoked = await saveRemoteHost(context, draft({ id: initial.id, launchUrl: '', authorization: '' }));
  assert.equal(revoked.hasCredential, false);
  assert.deepEqual(storedAssets(), []);
  await saveRemoteHost(context, draft({ id: initial.id, remember: true }));
  await deleteRemoteHost(context, initial.id);
  assert.deepEqual(persistedMetadata(), []);
  assert.deepEqual(storedAssets(), []);
});

test('rejects unsafe links, unsafe authorization, credential names and oversize storage', async () => {
  for (const launchUrl of [
    'http://fixture.invalid/?token=secret', 'http://localhost/?token=secret', 'http://127.1/?token=secret',
    'https://user:secret@fixture.invalid/?token=secret', 'https://@fixture.invalid/?token=secret',
    'https://fixture.invalid/?token=secret#', 'https://fixture.invalid/?token=one&token=secret',
    'https://fixture.invalid/?token=%0a', 'https://fixture.invalid/?token=%20',
    'https://fixture.invalid/?other=secret', 'https://fixture.invalid/\\token?token=secret'
  ]) {
    await assert.rejects(saveRemoteHost(context, draft({ launchUrl })), error => {
      assert.doesNotMatch(error.message, /secret|fixture\.invalid/);
      return true;
    });
  }
  await assert.rejects(saveRemoteHost(context, draft({ authorization: 'Bearer secret\r\nX: injected' })), /授权格式/);
  for (const name of [hostUrl, hostToken, proxyValue, '名字 example-test-proxy']) {
    await assert.rejects(saveRemoteHost(context, draft({ name })), /名称/);
  }
  const host = await saveRemoteHost(context, draft({ launchUrl: 'http://127.0.0.1:12345/?token=test' }));
  assert.equal(host.origin, 'http://127.0.0.1:12345');
  assert.throws(() => remoteHostConnection(host, hostUrl, proxyValue), /地址不同/);
  const large = 'Bearer ' + 'x'.repeat(1000);
  await assert.rejects(saveRemoteHost(context, draft({ authorization: large, remember: true })), /大小限制/);
  assert.equal((await saveRemoteHost(context, draft({ authorization: large }))).hasCredential, false);
});

test('rolls back rejected asset saves and redacts platform errors', async () => {
  failOnce('add', { code: asset.ErrorCode.STATUS_MISMATCH, message: hostUrl });
  await assert.rejects(saveRemoteHost(context, draft({ remember: true })), error => {
    assert.match(error.message, /解锁/);
    assert.doesNotMatch(error.message, /example-test-token/);
    return true;
  });
  assert.deepEqual(await listRemoteHosts(context), []);
  assert.deepEqual(persistedMetadata(), []);
  const initial = await saveRemoteHost(context, draft({ remember: true }));
  await assert.rejects(saveRemoteHost(context, draft({ id: initial.id, name: hostToken, launchUrl: '',
    authorization: '', remember: true })), /名称/);
  failOnce('flush', { message: proxyValue });
  await assert.rejects(saveRemoteHost(context, draft({ id: initial.id, name: '另一名称', remember: true })), /无法更新/);
  assert.deepEqual(await listRemoteHosts(context), [initial]);
  assert.equal((await getRemoteHostConnection(initial))?.authorization, proxyValue);
});

test('failed opt-out or deletion preserves both the original profile and its credential', async () => {
  const host = await saveRemoteHost(context, draft({ remember: true }));
  const metadata = persistedMetadata();
  const original = await getRemoteHostConnection(host);
  const optOut = () => saveRemoteHost(context, draft({ id: host.id, name: '新名称', launchUrl: '', authorization: '' }));
  const remove = () => deleteRemoteHost(context, host.id);
  for (const action of [optOut, remove]) {
    failOnce('flush', { message: proxyValue });
    await assert.rejects(action(), /无法更新/);
    assert.deepEqual(persistedMetadata(), metadata);
    assert.deepEqual(await listRemoteHosts(context), [host]);
    assert.deepEqual(await getRemoteHostConnection(host), original);

    failOnce('remove', { code: asset.ErrorCode.ACCESS_DENIED, message: proxyValue });
    await assert.rejects(action(), /解锁/);
    assert.deepEqual(persistedMetadata(), metadata);
    assert.deepEqual(await listRemoteHosts(context), [host]);
    assert.deepEqual(await getRemoteHostConnection(host), original);
  }
});
