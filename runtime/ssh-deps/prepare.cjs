'use strict';

const { createHash } = require('node:crypto');
const { readFileSync, writeFileSync } = require('node:fs');
const { join } = require('node:path');

const directory = process.argv[2];
if (!directory) throw new Error('SSH dependency directory required');
function replace(name, hash, before, after) {
  const path = join(directory, 'node_modules/ssh2/lib/protocol', name);
  const source = readFileSync(path, 'utf8');
  if (createHash('sha256').update(source).digest('hex') !== hash || source.split(before).length !== 2) {
    throw new Error(`Unexpected ssh2 source in ${name}`);
  }
  writeFileSync(path, source.replace(before, after));
}

// Harmony runs Node with --jitless. Keep ssh2 from loading the optional Poly1305 WebAssembly implementation.
replace('crypto.js', 'a729d2064e787e2a4589c25a284444fe54a58b7434a4e6e5e8e9c73c6d91e28e',
  '  init: (() => {', "  init: (typeof WebAssembly === 'undefined' ? Promise.resolve() : (() => {");
const cryptoPath = join(directory, 'node_modules/ssh2/lib/protocol/crypto.js');
const cryptoSource = readFileSync(cryptoPath, 'utf8');
const closure = '  })(),\n\n  NullCipher,';
if (cryptoSource.split(closure).length !== 2) throw new Error('Unexpected ssh2 crypto closure');
writeFileSync(cryptoPath, cryptoSource.replace(closure, '  })()),\n\n  NullCipher,'));
replace('constants.js', 'a3894fdd8e294109b55f06fbda69e467741f15a250801b744b6b0487bbf32529',
  'DEFAULT_CIPHER = DEFAULT_CIPHER.filter(canUseCipher);',
  "DEFAULT_CIPHER = DEFAULT_CIPHER.filter(name => canUseCipher(name) &&\n  (typeof WebAssembly !== 'undefined' || name !== 'chacha20-poly1305@openssh.com'));" );
