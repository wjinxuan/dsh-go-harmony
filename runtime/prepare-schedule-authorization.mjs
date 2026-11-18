// Original DSH Go explicit schedule authorization, after safe session deletion.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, lstatSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const hash = value => createHash('sha256').update(value).digest('hex');
const manifestBytes = readFileSync(new URL('./vendor/schedule-authorization/authorization.json', import.meta.url));
if (hash(manifestBytes) !== 'bc7df902fa6ccaef1bea986e324eb396a48bb38732454254e2b010602a605ba4') throw Error('Schedule authorization manifest integrity mismatch');
export const scheduleAuthorizationManifest = JSON.parse(manifestBytes);
const original = readFileSync(new URL('./vendor/schedule-authorization/authorization.upstream.diff', import.meta.url));
if (hash(original) !== scheduleAuthorizationManifest.upstreamSha256) throw Error('Schedule authorization upstream integrity mismatch');
export function prepareScheduleAuthorization(destination) {
  const pending = [];
  for (const entry of scheduleAuthorizationManifest.files) {
    const path = join(resolve(destination), entry.file);
    if (!lstatSync(path).isFile()) throw Error('Schedule authorization source must be regular: ' + entry.file);
    const input = readFileSync(path, 'utf8'), checksum = hash(input);
    if (checksum === entry.afterSha256) continue;
    if (checksum !== entry.beforeSha256) throw Error('Unexpected fixed schedule authorization source SHA256: ' + entry.file);
    let output = input;
    for (const operation of entry.operations) {
      if (output.split(operation.before).length !== 2) throw Error('Schedule authorization anchor is not unique: ' + entry.file);
      output = output.replace(operation.before, operation.after);
    }
    if (hash(output) !== entry.afterSha256) throw Error('Schedule authorization output SHA256 mismatch: ' + entry.file);
    pending.push({ path, output });
  }
  // Preflight every module before mutating the disposable packaging tree.
  for (const entry of pending) writeFileSync(entry.path, entry.output);
  return pending.length;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (!process.argv[2]) throw Error('Usage: prepare-schedule-authorization.mjs <runtime-after-session-deletion>');
  console.log(`Schedule authorization: ${prepareScheduleAuthorization(process.argv[2])} modules patched`);
}
