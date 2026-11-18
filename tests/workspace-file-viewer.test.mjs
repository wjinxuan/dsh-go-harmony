import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';
import { localizedSettingsText, localizedSettingsFormat } from './settings-locale-fixture.mjs';

let source = await readFile(new URL('../entry/src/main/ets/ui/WorkspaceFileViewer.ets', import.meta.url), 'utf8');
source = source.slice(source.indexOf('export struct WorkspaceFileViewer'), source.lastIndexOf('\n  build()')) + '\n}';
source = source.replace('export struct', 'class').replace(/@(?:Prop|State) /g, '').replace(/@StorageProp\('dshLanguage'\) /g, '');
const writes = []; const cached = [];
const Viewer = vm.runInNewContext(stripTypeScriptTypes(`${source}\nWorkspaceFileViewer`), {
  localizedSettingsText, localizedSettingsFormat, DshClient: class {}, themeColors: () => ({}),
  artifactKind: path => path.endsWith('.txt') ? 'text' : 'archive',
  object: value => value && typeof value === 'object' ? value : {}, string: value => typeof value === 'string' ? value : '',
  cacheMediaFile: async (_client, session, path, cache, _video, current) => { assert.equal(current(), true); cached.push({ session, path, cache }); return '/cache/original.zip'; },
  clearMediaFiles: async () => {}, fileUri: { getUriFromPath: path => `file://${path}` },
  fileIo: { OpenMode: { WRITE_ONLY: 1, TRUNC: 2 }, async open(path) { writes.push(['open', path]); return { fd: 4 }; },
    async copyFile(path, fd) { writes.push(['copy', path, fd]); }, async stat() { return { size: 10 }; },
    async fsync(fd) { writes.push(['sync', fd]); }, async close(file) { writes.push(['close', file.fd]); } },
  picker: { DocumentSaveOptions: class {}, DocumentViewPicker: class { async save(options) { writes.push(['picker', options.newFileNames]); return ['picked-uri']; } } }
});
function fixture() {
  const viewer = new Viewer();
  viewer.active = true; viewer.connection = 1; viewer.sessionId = 's1'; viewer.path = '/workspace/a.txt';
  viewer.getUIContext = () => ({ getHostContext: () => ({ cacheDir: '/cache' }) });
  viewer.client = { connectionIdentity: () => 1, async readWorkspaceText(_session, _path, offset) {
    return { text: offset === 1 ? 'first' : 'second', offset, lines: 1, eof: offset > 1, version: 'v1' };
  } };
  return viewer;
}

test('file preview advances exact line offsets and refuses a changed file without mixing versions', async () => {
  const viewer = fixture(); await viewer.load(); assert.equal(viewer.text, 'first'); assert.equal(viewer.textOffset, 2);
  await viewer.more(); assert.equal(viewer.text, 'first\nsecond'); assert.equal(viewer.eof, true);
  viewer.eof = false; viewer.client.readWorkspaceText = async () => ({ text: 'changed', version: 'v2', offset: 3, lines: 1, eof: true });
  await viewer.more(); assert.equal(viewer.text, 'first\nsecond'); assert.match(viewer.error, /变化/);
});

test('stale file reads cannot populate a switched connection and exports copy original bytes before reporting success', async () => {
  const stale = fixture(); let resolve;
  stale.client.readWorkspaceText = () => new Promise(done => { resolve = done; });
  const loading = stale.load(); stale.client.connectionIdentity = () => 2;
  resolve({ text: 'from old host', offset: 1, lines: 1, eof: true, version: 'v1' }); await loading;
  assert.equal(stale.text, '');
  const viewer = fixture(); viewer.path = '/workspace/report.zip';
  await viewer.exportFile(false);
  assert.equal(cached.at(-1).session, 's1'); assert.equal(cached.at(-1).path, '/workspace/report.zip');
  assert.equal(viewer.notice, '文件已保存'); assert.equal(viewer.working, false);
  assert.deepEqual(writes.map(row => row[0]), ['picker', 'open', 'copy', 'sync', 'close']);
});
