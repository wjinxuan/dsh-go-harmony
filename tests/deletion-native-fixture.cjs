'use strict';
// Synthetic platform-only exclusive publication; production uses the audited C++ helper.
require('./local-flock-fixture.cjs');
const fs = require('node:fs'), promises = require('node:fs/promises');
const {syncBuiltinESMExports} = require('node:module');
const original = promises.link;
promises.link = async (from,to) => {
 if (/\/.dsh-go-lifecycle\/[0-9a-f]{64}\/deleted\.json$/.test(to)) throw Object.assign(Error('Synthetic Harmony hardlink denial'),{code:'EACCES',syscall:'link'});
 return original(from,to);
};
globalThis.dshHarmonyPublishDeletionMarker = (from,to) => {
 const directory=require('node:path').dirname(to);
 if(!to.startsWith(process.argv[2]+'/sessions/.dsh-go-lifecycle/')||!/^\.[0-9a-f-]{36}\.tmp$/.test(require('node:path').basename(from))||require('node:path').dirname(from)!==directory)throw Error('Invalid fixture marker path');
 fs.linkSync(from,to);fs.unlinkSync(from);fs.appendFileSync(process.argv[2]+'/marker-publications','1\n');
};
syncBuiltinESMExports();
