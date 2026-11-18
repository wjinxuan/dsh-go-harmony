'use strict';

const assert = require('node:assert/strict');
const { fstatSync, linkSync, unlinkSync } = require('node:fs');
const fsPromises = require('node:fs/promises');
const { syncBuiltinESMExports } = require('node:module');

// The production binding is native. A single fixture process uses DSH's in-process write ownership.
globalThis.dshHarmonyTryLock = fd => {
  assert.equal(fstatSync(fd).isFile(), true);
  return true;
};

if (process.env.DSH_HARMONY_TEST_DENY_LINK === '1' || process.env.DSH_HARMONY_TEST_WORKSPACE_LINK === '1' ||
    process.env.DSH_HARMONY_TEST_ATTACHMENT_LINK === '1') {
  const link = fsPromises.link;
  fsPromises.link = async (staged, final) => {
    const session = process.env.DSH_HARMONY_TEST_DENY_LINK === '1' && /\.jsonl(?:\.zstd)?$/.test(final);
    const workspace = process.env.DSH_HARMONY_TEST_WORKSPACE_LINK === '1' && staged.includes('.tmpdir/');
    const attachment = process.env.DSH_HARMONY_TEST_ATTACHMENT_LINK === '1' && final.includes('/attachments/v1/');
    if (attachment || ((session || workspace) && staged.endsWith('.tmp'))) {
      throw Object.assign(new Error('Fixture denied hardlink'), { code: 'EACCES', syscall: 'link' });
    }
    return link(staged, final);
  };
  syncBuiltinESMExports();
  globalThis.dshHarmonyPublishFile = (staged, final) => {
    // Preserve no-replace semantics on hosts without renameat2.
    linkSync(staged, final);
    unlinkSync(staged);
  };
  globalThis.dshHarmonyPublishWorkspaceFile = globalThis.dshHarmonyPublishFile;
  globalThis.dshHarmonyPublishAttachmentFile = globalThis.dshHarmonyPublishFile;
}
