import assert from 'node:assert/strict';
import test from 'node:test';
import { permissionConfirmation, permissionCopy } from './SessionPermissionCopy.ts';

test('renders original built-in names and hints, preserving extension copy', () => {
  assert.deepEqual(permissionCopy('read-only', 'Host read only', 'Host copy', false),
    { title: '仅可查看', hint: '只看文件，不做修改' });
  assert.deepEqual(permissionCopy('custom', 'Host custom', 'Host copy', false), { title: '自定义', hint: 'Host copy' });
  assert.deepEqual(permissionCopy('extension', 'Host extension', 'Host copy', false),
    { title: 'Host extension', hint: 'Host copy' });
  assert.equal(permissionCopy('extension', '', '', true).title, 'extension');
});

test('requests confirmation for full access and auto review, preserving the local file boundary', () => {
  assert.equal(permissionConfirmation('read-only', false), undefined);
  assert.equal(permissionConfirmation('workspace-write', true), undefined);
  assert.equal(permissionConfirmation('auto', false).action, '开启自动审查');
  assert.match(permissionConfirmation('danger-full-access', false).body, /执行命令/);
  assert.match(permissionConfirmation('danger-full-access', true).body, /限定在应用工作区/);
  assert.doesNotMatch(permissionCopy('workspace-write', '', '', true).hint, /越界/);
});
