import './require-runtime-node.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { prepareCompanionSignals, signalPatchManifest as manifest } from '../runtime/prepare-companion-signals.mjs';
const hash = value => createHash('sha256').update(value).digest('hex');
test('all 12 original signal hunks retain every added/removed byte in order', () => {
 const patch=readFileSync(new URL('../runtime/vendor/companion-signals-patches/signals.upstream.diff',import.meta.url),'utf8');
 assert.equal(hash(patch),manifest.upstreamSha256);
 let file,hunks=[],current;const source=new Map();
 function flush(){if(current)hunks.push(current);current=undefined}
 for(const line of patch.split('\n')){if(line.startsWith('--- a/')){flush();if(file)source.set(file,hunks);file=line.slice(6);hunks=[]}else if(line.startsWith('@@')){flush();current={before:[],after:[]}}else if(line.startsWith('+++')||line.startsWith('#'))continue;else if(current&&line.startsWith(' ')){current.before.push(line.slice(1));current.after.push(line.slice(1))}else if(current&&line.startsWith('-'))current.before.push(line.slice(1));else if(current&&line.startsWith('+'))current.after.push(line.slice(1));}flush();source.set(file,hunks);
 assert.equal(manifest.files.length,3);assert.equal(manifest.files.reduce((n,v)=>n+v.operations.length,0),12);
 for(const entry of manifest.files){const original=source.get(entry.file);assert.equal(entry.operations.length,original.length);entry.operations.forEach((operation,index)=>{const a=operation.before.split('\n'),b=operation.after.split('\n');while(a.length&&b.length&&a[0]===b[0]){a.shift();b.shift()}while(a.length&&b.length&&a.at(-1)===b.at(-1)){a.pop();b.pop()}const c=original[index].before,d=original[index].after;while(c.length&&d.length&&c[0]===d[0]){c.shift();d.shift()}while(c.length&&d.length&&c.at(-1)===d.at(-1)){c.pop();d.pop()}assert.deepEqual(a,c,entry.file);assert.deepEqual(b,d,entry.file)})}
});
const runtime=process.env.DSH_SIGNAL_RUNTIME;
test('fixed real module hashes, idempotence and all-file preflight reject tampering', {skip:!runtime},()=>{
 const root=mkdtempSync(join(tmpdir(),'signals-patch-'));
 try{for(const entry of manifest.files){let value=readFileSync(join(resolve(runtime),entry.file),'utf8');if(hash(value)===entry.afterSha256){for(const operation of [...entry.operations].reverse()){assert.equal(value.split(operation.after).length,2);value=value.replace(operation.after,operation.before)}}assert.equal(hash(value),entry.beforeSha256);mkdirSync(dirname(join(root,entry.file)),{recursive:true});writeFileSync(join(root,entry.file),value)}
 const last=join(root,manifest.files.at(-1).file),original=readFileSync(last,'utf8');writeFileSync(last,original+'\n// wrong source');assert.throws(()=>prepareCompanionSignals(root),/SHA256/);assert.equal(hash(readFileSync(join(root,manifest.files[0].file))),manifest.files[0].beforeSha256);
 writeFileSync(last,original);assert.equal(prepareCompanionSignals(root),3);assert.equal(prepareCompanionSignals(root),0);for(const entry of manifest.files)assert.equal(hash(readFileSync(join(root,entry.file))),entry.afterSha256);
 }finally{rmSync(root,{recursive:true,force:true})}
});
