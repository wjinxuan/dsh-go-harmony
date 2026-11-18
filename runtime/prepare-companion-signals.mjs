// Fixed upstream execution provenance and post-commit signals. Apply after recall gates.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, lstatSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const hash = value => createHash('sha256').update(value).digest('hex');
const manifestBytes = readFileSync(new URL('./vendor/companion-signals-patches/signals.json', import.meta.url));
const EXPECTED = '56bfe1400f1917910e3dd47c5adc1099bf5f990966be8d69243ac5ad399214a5';
if (hash(manifestBytes) !== EXPECTED) throw new Error('Companion signals patch manifest integrity mismatch');
export const signalPatchManifest = JSON.parse(manifestBytes);
export function prepareCompanionSignals(destination) {
  const pending = [];
  for (const entry of signalPatchManifest.files) {
    const path = join(resolve(destination), entry.file);
    if (!lstatSync(path).isFile()) throw new Error(`Companion signals source is not a regular file: ${entry.file}`);
    const source = readFileSync(path, 'utf8'), checksum = hash(source);
    if (checksum === entry.afterSha256) continue;
    if (checksum !== entry.beforeSha256) throw new Error(`Unexpected fixed companion signals source SHA256: ${entry.file}`);
    let patched = source;
    for (const operation of entry.operations) {
      if (patched.split(operation.before).length !== 2) throw new Error(`Companion signals patch anchor is not unique: ${entry.file}`);
      patched = patched.replace(operation.before, operation.after);
    }
    if (hash(patched) !== entry.afterSha256) throw new Error(`Companion signals output SHA256 mismatch: ${entry.file}`);
    pending.push({ path, patched });
  }
  // Validate every module before modifying the disposable build tree.
  for (const entry of pending) writeFileSync(entry.path, entry.patched);
  return pending.length;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (!process.argv[2]) throw new Error('Usage: prepare-companion-signals.mjs <locked-runtime>');
  console.log(`Companion signals gates: ${prepareCompanionSignals(process.argv[2])} modules patched`);
}
