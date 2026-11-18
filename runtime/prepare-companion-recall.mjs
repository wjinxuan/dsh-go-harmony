// Fixed DSH Go admission, request provenance, exact-session memory and retirement
// gates. No capability flags are fabricated: the bridge inspects the real code.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, lstatSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const hash = value => createHash('sha256').update(value).digest('hex');
const manifestBytes = readFileSync(new URL('./vendor/companion-recall-patches/recall-gates.json', import.meta.url));
const EXPECTED = '74d47d35a3caf436128315303e60b630e2a310a89ea391510063ea8901e5fb89';
if (hash(manifestBytes) !== EXPECTED) throw new Error('Companion recall patch manifest integrity mismatch');
export const recallPatchManifest = JSON.parse(manifestBytes);
export function prepareCompanionRecall(destination) {
  const pending = [];
  for (const entry of recallPatchManifest.files) {
    const path = join(resolve(destination), entry.file);
    if (!lstatSync(path).isFile()) throw new Error(`Companion recall source is not a regular file: ${entry.file}`);
    const source = readFileSync(path, 'utf8'), checksum = hash(source);
    if (checksum === entry.afterSha256) continue;
    if (checksum !== entry.beforeSha256) throw new Error(`Unexpected fixed companion recall source SHA256: ${entry.file}`);
    let patched = source;
    for (const operation of entry.operations) {
      if (patched.split(operation.before).length !== 2) throw new Error(`Companion recall patch anchor is not unique: ${entry.file}`);
      patched = patched.replace(operation.before, operation.after);
    }
    if (hash(patched) !== entry.afterSha256) throw new Error(`Companion recall output SHA256 mismatch: ${entry.file}`);
    pending.push({ path, patched });
  }
  // Validate every module before modifying the disposable build tree.
  for (const entry of pending) writeFileSync(entry.path, entry.patched);
  return pending.length;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (!process.argv[2]) throw new Error('Usage: prepare-companion-recall.mjs <locked-runtime>');
  console.log(`Companion recall gates: ${prepareCompanionRecall(process.argv[2])} modules patched`);
}
