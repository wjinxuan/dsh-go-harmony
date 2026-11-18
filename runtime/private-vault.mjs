import { randomBytes, createCipheriv, createDecipheriv } from 'node:crypto';
import { constants } from 'node:fs';
import { open, mkdir, rename, rm, lstat } from 'node:fs/promises';
import { join } from 'node:path';
// The caller obtains this 32-byte key from Harmony AssetStore DEVICE_UNLOCKED / NEVER sync.
// Only authenticated loopback native control may supply it; it is never stored beside this ciphertext.
export class PrivateVault {
  constructor(root, filename, masterKey, { maxBytes=1024*1024 }={}) {
    if(!/^[.a-zA-Z0-9_-]+\.json$/.test(filename) || !/^[A-Za-z0-9_-]{43}$/.test(masterKey))throw Error('Invalid vault configuration');
    this.key=Buffer.from(masterKey,'base64url');if(this.key.length!==32)throw Error('Invalid vault key');
    this.root=root;this.path=join(root,filename);this.aad=Buffer.from('dsh-harmony-vault-v1:'+filename);this.maxBytes=maxBytes;
  }
  async load() {
    let file;
    try {
      file=await open(this.path,constants.O_RDONLY|constants.O_NOFOLLOW);
      const info=await file.stat();if(!info.isFile()||info.size>this.maxBytes*2)throw Error('Invalid vault file');
      const envelope=JSON.parse(await file.readFile('utf8'));
      if(envelope?.version!==1||typeof envelope.iv!=='string'||typeof envelope.tag!=='string'||typeof envelope.data!=='string')throw Error('Invalid vault envelope');
      const iv=Buffer.from(envelope.iv,'base64url'),tag=Buffer.from(envelope.tag,'base64url');if(iv.length!==12||tag.length!==16)throw Error('Invalid vault envelope');
      const decipher=createDecipheriv('aes-256-gcm',this.key,iv);decipher.setAAD(this.aad);decipher.setAuthTag(tag);
      const plain=Buffer.concat([decipher.update(Buffer.from(envelope.data,'base64url')),decipher.final()]);
      try{if(plain.length>this.maxBytes)throw Error('Vault too large');return JSON.parse(plain.toString('utf8'));}finally{plain.fill(0);}
    }catch(error){if(error.code==='ENOENT')return undefined;throw error;}finally{await file?.close();}
  }
  async save(value) {
    const plain=Buffer.from(JSON.stringify(value));
    let envelope;
    try {
      if(plain.length>this.maxBytes)throw Error('Vault too large');
      const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',this.key,iv);cipher.setAAD(this.aad);
      const data=Buffer.concat([cipher.update(plain),cipher.final()]);envelope=JSON.stringify({version:1,iv:iv.toString('base64url'),tag:cipher.getAuthTag().toString('base64url'),data:data.toString('base64url')});
    }finally{plain.fill(0);}
    await mkdir(this.root,{recursive:true,mode:0o700});const info=await lstat(this.root);if(!info.isDirectory()||info.isSymbolicLink())throw Error('Invalid vault directory');
    const staged=this.path+'.'+randomBytes(12).toString('hex')+'.tmp';let file;
    try {file=await open(staged,constants.O_CREAT|constants.O_EXCL|constants.O_WRONLY|constants.O_NOFOLLOW,0o600);await file.writeFile(envelope);await file.sync();await file.close();file=undefined;await rename(staged,this.path);}
    finally{await file?.close();await rm(staged,{force:true});}
  }
  destroy(){this.key.fill(0);}
}
