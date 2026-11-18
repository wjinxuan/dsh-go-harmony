// Fixed upstream safe deletion, after Harmony publication and recall/signal patches.
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,lstatSync,existsSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {fileURLToPath} from 'node:url';
const hash=value=>createHash('sha256').update(value).digest('hex');
const bytes=readFileSync(new URL('./vendor/session-deletion/patch.json',import.meta.url));
if(hash(bytes)!=='2041e3104cd737d7463f0bad24184e0a90c9d3bebffe9f1541582153d7c82090')throw Error('Session deletion patch manifest integrity mismatch');
export const deletionPatchManifest=JSON.parse(bytes);
export function prepareSessionDeletion(destination){
 const pending=[];
 for(const entry of deletionPatchManifest.files){const path=join(resolve(destination),entry.file);if(!lstatSync(path).isFile())throw Error('Session deletion source must be regular: '+entry.file);const original=readFileSync(path,'utf8'),sha=hash(original);if(sha===entry.afterSha256)continue;if(sha!==entry.beforeSha256)throw Error('Unexpected fixed session deletion source SHA256: '+entry.file);let source=original;
  for(const operation of entry.operations){if(source.split(operation.before).length!==2)throw Error('Session deletion anchor is not unique: '+entry.file);source=source.replace(operation.before,operation.after)}
  if(hash(source)!==entry.afterSha256)throw Error('Session deletion output SHA256 mismatch: '+entry.file);pending.push({path,source});
 }
 const core=readFileSync(new URL('./vendor/session-deletion/core.mjs',import.meta.url),'utf8');if(hash(core)!==deletionPatchManifest.coreSha256)throw Error('Session deletion core integrity mismatch');
 const target=join(resolve(destination),deletionPatchManifest.coreFile);if(existsSync(target)&&(!lstatSync(target).isFile()||hash(readFileSync(target))!==deletionPatchManifest.coreSha256))throw Error('Unexpected installed session deletion core');
 for(const entry of pending)writeFileSync(entry.path,entry.source);writeFileSync(target,core);return pending.length;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){if(!process.argv[2])throw Error('Usage: prepare-session-deletion.mjs <runtime>');console.log(`Session deletion: ${prepareSessionDeletion(process.argv[2])} modules patched`)}
