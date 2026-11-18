import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import * as nativeFs from 'node:fs/promises';
import { randomUUID, createHash } from 'node:crypto';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const path = new URL('../entry/src/main/ets/local/PrivateDirectory.ets', import.meta.url);
const source = await readFile(path, 'utf8');
const body = stripTypeScriptTypes(source.replace(/^import .*$/gm, '').replace('export ', ''));
const load = fs => new Function('fs', `${body};return ensurePrivateDirectory`)(fs);
const exists = Object.assign(new Error('File exists'), { code: 13900015 });

test('reopening the pet catalog does not fail when its private root already exists', async () => {
  const store = await readFile(new URL('../entry/src/main/ets/pets/PetStore.ets', import.meta.url), 'utf8');
  const tidySource = stripTypeScriptTypes(store.slice(store.indexOf('async function tidy('), store.indexOf('async function readPet(')));
  const fs = { mkdir: async () => { throw exists; }, listFile: async () => [],
    lstat: async () => ({ isDirectory: () => true, isSymbolicLink: () => false }) };
  const tidy = new Function('fs', 'ensurePrivateDirectory', `${tidySource};return tidy`)(fs, load(fs));
  await tidy('/private/pets');
  await tidy('/private/pets');
});

test('Harmony recursive mkdir accepts only an existing directory, including a concurrent creator', async () => {
  let present = false, calls = 0;
  const ensure = load({ mkdir: async () => { calls++; if (present) throw exists; present = true; },
    lstat: async () => ({ isDirectory: () => present, isSymbolicLink: () => false }) });
  await ensure('/private/pets');
  await Promise.all([ensure('/private/pets'), ensure('/private/pets')]);
  assert.equal(calls, 3);
});

test('existing files/symlinks and permission failures remain failures', async () => {
  for (const [directory, symlink] of [[false, false], [true, true]]) {
    await assert.rejects(load({ mkdir: async () => { throw exists; },
      lstat: async () => ({ isDirectory: () => directory, isSymbolicLink: () => symlink }) })('/private/pets'), e => e === exists);
  }
  const denied = Object.assign(new Error('Permission denied'), { code: 13900012 });
  await assert.rejects(load({ mkdir: async () => { throw denied; },
    lstat: () => { throw new Error('must not hide a permission failure'); } })('/private/pets'), e => e === denied);
});

async function implementation(relative, names, dependencies = {}) {
  const text = await readFile(new URL('../entry/src/main/ets/' + relative, import.meta.url), 'utf8');
  const code = stripTypeScriptTypes(text.replace(/^import .*$/gm, '').replace(/export /g, ''));
  return new Function(...Object.keys(dependencies), code + ';return {' + names.join(',') + '}')(...Object.values(dependencies));
}

// Actual temporary disk, with only Harmony's different recursive-mkdir result adapted.
function privateDisk() {
  const calls = new Map(), state = { deniedPath: '' };
  const denied = Object.assign(new Error('Permission denied'), { code: 13900012 });
  const fs = {
    async mkdir(path, recursive) {
      calls.set(path, (calls.get(path) || 0) + 1);
      if (path === state.deniedPath) throw denied;
      try { await nativeFs.lstat(path); }
      catch (error) { if (error.code === 'ENOENT') return nativeFs.mkdir(path, { recursive }); throw error; }
      throw exists;
    },
    lstat: nativeFs.lstat, listFile: nativeFs.readdir, copyFile: nativeFs.copyFile, rename: nativeFs.rename,
    async access(path) { try { await nativeFs.access(path); return true; } catch (error) { if (error.code === 'ENOENT') return false; throw error; } }
  };
  return { calls, state, denied, dependencies: {
    fs, ensurePrivateDirectory: load(fs),
    util: { generateRandomUUID: randomUUID, TextEncoder: class { encodeInto(text) { return new TextEncoder().encode(text); } } },
    writePrivate: (path, bytes) => nativeFs.writeFile(path, bytes, { mode: 0o600 }),
    removePrivate: path => nativeFs.rm(path, { recursive: true, force: true }),
    privateSha256: async bytes => createHash('sha256').update(bytes).digest('hex')
  } };
}

function storedZip(entries, crc) {
  const local = [], central = []; let offset = 0;
  for (const [name, value] of entries) {
    const filename = Buffer.from(name), bytes = Buffer.from(value), header = Buffer.alloc(30), row = Buffer.alloc(46);
    header.writeUInt32LE(0x04034b50); header.writeUInt16LE(20, 4); header.writeUInt16LE(0x800, 6);
    header.writeUInt32LE(crc(bytes), 14); header.writeUInt32LE(bytes.length, 18); header.writeUInt32LE(bytes.length, 22);
    header.writeUInt16LE(filename.length, 26); local.push(header, filename, bytes);
    row.writeUInt32LE(0x02014b50); row.writeUInt16LE(20, 6); row.writeUInt16LE(0x800, 8);
    row.writeUInt32LE(crc(bytes), 16); row.writeUInt32LE(bytes.length, 20); row.writeUInt32LE(bytes.length, 24);
    row.writeUInt16LE(filename.length, 28); row.writeUInt32LE(offset, 42); central.push(row, filename);
    offset += header.length + filename.length + bytes.length;
  }
  const directory = Buffer.concat(central), end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50);
  end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(directory.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...local, directory, end]);
}

test('actual companion installer reuses extraction parents, reinstalls, and preserves the live pack on a permission failure', async () => {
  const directory = await nativeFs.mkdtemp(join(tmpdir(), 'dsh-private-pack-'));
  const disk = privateDisk(), root = join(directory, 'companion'), live = join(root, 'pack');
  try {
    // Synthetic existing runtime is solely a directory-copy sentinel, not a licensed/renderable Live2D fixture.
    await nativeFs.mkdir(join(live, 'runtime', 'nested'), { recursive: true });
    await nativeFs.writeFile(join(live, 'runtime', 'live2dcubismcore.min.js'), 'existing-runtime-sentinel');
    await nativeFs.writeFile(join(live, 'runtime', 'nested', 'asset.js'), 'nested-runtime-sentinel');
    const archive = await implementation('pets/PrivateArchive.ets', ['PrivateArchive', 'archivePath', 'archiveCrc']);
    const { installCompanionPack } = await implementation('companion/CompanionPack.ets', ['installCompanionPack'], {
      ...disk.dependencies, ...archive,
      inflatePrivate: () => { throw new Error('stored ZIP must not request inflation'); }
    });
    const packed = value => storedZip([
      ['model/face.model3.json', '{}'], ['model/textures/one.png', 'synthetic-one-' + value],
      ['model/textures/two.png', 'synthetic-two-' + value]
    ], archive.archiveCrc);
    await installCompanionPack({ filesDir: directory }, packed('first'));
    await installCompanionPack({ filesDir: directory }, packed('second'));
    const textures = join(live, 'character', 'textures');
    assert.equal(await nativeFs.readFile(join(textures, 'one.png'), 'utf8'), 'synthetic-one-second');
    assert.equal(await nativeFs.readFile(join(textures, 'two.png'), 'utf8'), 'synthetic-two-second');
    assert.equal(await nativeFs.readFile(join(live, 'runtime', 'nested', 'asset.js'), 'utf8'), 'nested-runtime-sentinel');
    assert.deepEqual(JSON.parse(await nativeFs.readFile(join(live, 'character', 'index.json'), 'utf8')),
      ['face.model3.json', 'textures/one.png', 'textures/two.png', 'character.json']);
    assert.equal(disk.calls.get(join(root, 'pack.staging', 'character', 'textures')), 4);
    disk.state.deniedPath = join(root, 'pack.staging', 'character', 'textures');
    await assert.rejects(installCompanionPack({ filesDir: directory }, packed('denied')), error => error === disk.denied);
    assert.equal(await nativeFs.readFile(join(textures, 'two.png'), 'utf8'), 'synthetic-two-second');
    await assert.rejects(nativeFs.access(join(root, 'pack.staging')), { code: 'ENOENT' });
    await assert.rejects(nativeFs.access(join(root, 'pack.previous')), { code: 'ENOENT' });
  } finally { await nativeFs.rm(directory, { recursive: true, force: true }); }
});

test('actual companion store saves repeatedly and retains the last atomic state when directory access is denied', async () => {
  const directory = await nativeFs.mkdtemp(join(tmpdir(), 'dsh-private-store-')), disk = privateDisk();
  try {
    const { CompanionLocalStore } = await implementation('companion/CompanionStore.ets', ['CompanionLocalStore'], disk.dependencies);
    const store = new CompanionLocalStore({ filesDir: directory }), file = join(directory, 'companion', 'light-chat.json');
    await store.saveLines([{ role: 'user', text: 'first' }]);
    const latest = [{ role: 'user', text: 'first' }, { role: 'assistant', text: 'second' }];
    await store.saveLines(latest);
    assert.deepEqual(JSON.parse(await nativeFs.readFile(file, 'utf8')), { v: 2, lines: latest });
    disk.state.deniedPath = join(directory, 'companion');
    await assert.rejects(store.saveLines([{ role: 'user', text: 'must not replace old state' }]), error => error === disk.denied);
    assert.deepEqual(JSON.parse(await nativeFs.readFile(file, 'utf8')), { v: 2, lines: latest });
    assert.deepEqual(await nativeFs.readdir(join(directory, 'companion')), ['light-chat.json']);
  } finally { await nativeFs.rm(directory, { recursive: true, force: true }); }
});
