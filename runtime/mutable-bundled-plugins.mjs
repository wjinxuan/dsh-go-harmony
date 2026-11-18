import { lstat, readFile, open, rename, unlink, copyFile } from 'node:fs/promises';
import { constants } from 'node:fs';
import { dirname, join } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { parseDocument, isSeq, isMap } from 'yaml';

// These shipped plugins have user-editable configuration. They belong in the
// writable profile, not its deployment overlays (which settings correctly lock).
const bundled = new Map([
  ['dsh-go-bridge', 'vendor/dsh-go-bridge/lib/index.js'],
  ['dsh-media', 'vendor/dsh-media/src/index.js'],
]);
export async function ensureMutableBundledPlugins({ patchPath, runtimeRoot }) {
  const stat = await lstat(patchPath);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 1024 * 1024) throw new Error('Bundled plugin profile is not a regular bounded file');
  const source = await readFile(patchPath, 'utf8');
  const doc = parseDocument(source, { uniqueKeys: true, customTags: [] });
  if (doc.errors.length || !isSeq(doc.contents)) throw new Error('Bundled plugin profile is malformed');
  // Reject aliases/tags rather than expanding untrusted YAML graphs during migration.
  if (/(?:^|\s)[&*!][\w<!]/m.test(source)) throw new Error('Bundled plugin profile aliases and tags are unsupported');
  const seen = new Set();
  let changed = false;
  for (const patch of doc.contents.items) {
    if (!isMap(patch)) throw new Error('Bundled plugin profile patch must be an object');
    const insert = patch.get('insert', true);
    if (insert !== undefined && !isSeq(insert)) throw new Error('Bundled plugin insertion must be an array');
    const rows = insert ? insert.items : [patch];
    for (const row of rows) {
      if (!isMap(row)) throw new Error('Bundled plugin entry must be an object');
      const id = row.get('id');
      if (!bundled.has(id)) continue;
      if (seen.has(id) || !insert) throw new Error('Conflicting bundled plugin profile entry: ' + id);
      seen.add(id);
      const suffix = bundled.get(id), name = row.get('name');
      let oldPath;
      try { oldPath = fileURLToPath(name); } catch { throw new Error('Unexpected bundled plugin source: ' + id); }
      if (!oldPath.endsWith('/' + suffix)) throw new Error('Unexpected bundled plugin source: ' + id);
      const current = pathToFileURL(join(runtimeRoot, suffix)).href;
      if (name !== current) { row.set('name', current); changed = true; }
    }
  }
  const missing = [...bundled].filter(([id]) => !seen.has(id));
  if (missing.length) {
    doc.contents.add(doc.createNode({ insert: missing.map(([id, suffix]) => ({ id, name: pathToFileURL(join(runtimeRoot, suffix)).href })) }));
    changed = true;
  }
  if (!changed) return false;
  const output = doc.toString();
  const backup = patchPath + '.before-bundled-' + randomUUID();
  await copyFile(patchPath, backup, constants.COPYFILE_EXCL);
  const temporary = join(dirname(patchPath), '.bundled-' + randomUUID());
  let file;
  try { file = await open(temporary, 'wx', 0o600); await file.writeFile(output); await file.sync(); await file.close(); file = undefined; await rename(temporary, patchPath); }
  finally { await file?.close(); await unlink(temporary).catch(() => {}); }
  return true;
}
