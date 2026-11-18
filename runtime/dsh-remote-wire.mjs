// DSH Remote v1 protocol derived from ds-harness-remote (MIT).
// Copyright (c) 2026 DSH Remote contributors. See THIRD_PARTY_NOTICES.md.
import {
  createCipheriv, createDecipheriv, createHash, createHmac, createPrivateKey, createPublicKey,
  diffieHellman, hkdfSync, randomBytes, randomUUID
} from 'node:crypto';

const empty = Buffer.alloc(0);
const privatePrefix = Buffer.from('302e020100300506032b656e04220420', 'hex');
const publicPrefix = Buffer.from('302a300506032b656e032100', 'hex');
const protocol = Buffer.from('Noise_IK_25519_ChaChaPoly_SHA256');
const hash = (...parts) => parts.reduce((ctx, part) => ctx.update(part), createHash('sha256')).digest();
const mac = (key, ...parts) => parts.reduce((ctx, part) => ctx.update(part), createHmac('sha256', key)).digest();
export const b64 = data => Buffer.from(data).toString('base64url');

export function bytes(value, length, maxLength = 1024 * 1024) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]+$/.test(value) || value.length > Math.ceil(maxLength * 4 / 3)) {
    throw new Error('INVALID_MESSAGE');
  }
  const decoded = Buffer.from(value, 'base64url');
  if (b64(decoded) !== value || (length !== undefined && decoded.length !== length)) throw new Error('INVALID_MESSAGE');
  return decoded;
}

function privateKey(raw) {
  return createPrivateKey({ key: Buffer.concat([privatePrefix, raw]), format: 'der', type: 'pkcs8' });
}

function dh(secret, peer) {
  return diffieHellman({ privateKey: privateKey(secret),
    publicKey: createPublicKey({ key: Buffer.concat([publicPrefix, peer]), format: 'der', type: 'spki' }) });
}

export function x25519Key(raw = randomBytes(32)) {
  const publicKey = createPublicKey(privateKey(raw)).export({ format: 'der', type: 'spki' }).subarray(-32);
  return { privateKey: b64(raw), publicKey: b64(publicKey) };
}

export function fingerprint(key) {
  return hash(bytes(key, 32)).toString('hex');
}

export function pairingProof(secret, peer, sessionId, path, body, side = 'mobile') {
  const shared = dh(bytes(secret, 32), bytes(peer, 32));
  const key = Buffer.from(hkdfSync('sha256', shared, sessionId, 'dsh-pairing-v1/' + side, 32));
  shared.fill(0);
  try {
    return b64(mac(key, 'POST\n' + path + '\n' + hash(body).toString('hex')));
  } finally {
    key.fill(0);
  }
}

function hkdf2(chain, input) {
  const key = mac(chain, input);
  const first = mac(key, Buffer.of(1));
  const second = mac(key, first, Buffer.of(2));
  key.fill(0);
  return [first, second];
}

class Cipher {
  constructor(key) { this.key = key; }
  counter = 0;

  process(input, aad, decrypt) {
    if (!this.key || this.counter >= Number.MAX_SAFE_INTEGER) throw new Error('SECURE_CHANNEL_FAILED');
    const nonce = Buffer.alloc(12);
    nonce.writeBigUInt64LE(BigInt(this.counter), 4);
    let result;
    if (decrypt) {
      if (input.length < 16) throw new Error('SECURE_CHANNEL_FAILED');
      const decipher = createDecipheriv('chacha20-poly1305', this.key, nonce, { authTagLength: 16 });
      decipher.setAAD(aad);
      decipher.setAuthTag(input.subarray(-16));
      result = Buffer.concat([decipher.update(input.subarray(0, -16)), decipher.final()]);
    } else {
      const cipher = createCipheriv('chacha20-poly1305', this.key, nonce, { authTagLength: 16 });
      cipher.setAAD(aad);
      result = Buffer.concat([cipher.update(input), cipher.final(), cipher.getAuthTag()]);
    }
    this.counter++;
    return result;
  }

  destroy() { this.key.fill(0); }
}

export function noisePrologue(connectionId, hostId, clientId) {
  if ([connectionId, hostId, clientId].some(value => typeof value !== 'string' || !value || value.includes('\0'))) {
    throw new Error('INVALID_MESSAGE');
  }
  return Buffer.from('DSH-REMOTE\0v=1\0connection=' + connectionId + '\0host=' + hostId + '\0client=' + clientId);
}

export class NoiseInitiator {
  #remote;
  #static;
  #ephemeral;
  #hash;
  #chain;
  #handshake;
  #sending;
  #receiving;

  constructor(identity, peer, prologue, seed = randomBytes(32)) {
    this.#remote = bytes(peer, 32);
    this.#static = bytes(identity.privateKey, 32);
    if (x25519Key(this.#static).publicKey !== identity.publicKey) throw new Error('PEER_IDENTITY_MISMATCH');
    this.#ephemeral = Buffer.from(seed);
    this.#chain = protocol.length > 32 ? hash(protocol) : Buffer.concat([protocol, Buffer.alloc(32 - protocol.length)]);
    this.#hash = hash(hash(this.#chain, prologue), this.#remote);
  }

  #mixKey(secret, peer) {
    const shared = dh(secret, peer);
    const [chain, key] = hkdf2(this.#chain, shared);
    shared.fill(0);
    this.#chain.fill(0);
    this.#chain = chain;
    this.#handshake?.destroy();
    this.#handshake = new Cipher(key);
  }

  #mixHash(value) { this.#hash = hash(this.#hash, value); }

  start(payload = empty) {
    if (this.#handshake) throw new Error('SECURE_CHANNEL_FAILED');
    const ephemeralPublic = bytes(x25519Key(this.#ephemeral).publicKey, 32);
    this.#mixHash(ephemeralPublic);
    this.#mixKey(this.#ephemeral, this.#remote);
    const encryptedIdentity = this.#handshake.process(bytes(x25519Key(this.#static).publicKey, 32), this.#hash, false);
    this.#mixHash(encryptedIdentity);
    this.#mixKey(this.#static, this.#remote);
    const encryptedPayload = this.#handshake.process(payload, this.#hash, false);
    this.#mixHash(encryptedPayload);
    return Buffer.concat([ephemeralPublic, encryptedIdentity, encryptedPayload]);
  }

  finish(frame) {
    if (!this.#handshake || this.#sending || frame.length < 48 || frame.length > 65535) {
      throw new Error('SECURE_CHANNEL_FAILED');
    }
    const ephemeral = frame.subarray(0, 32);
    this.#mixHash(ephemeral);
    this.#mixKey(this.#ephemeral, ephemeral);
    this.#mixKey(this.#static, ephemeral);
    const payload = this.#handshake.process(frame.subarray(32), this.#hash, true);
    const [sending, receiving] = hkdf2(this.#chain, empty);
    this.#sending = new Cipher(sending);
    this.#receiving = new Cipher(receiving);
    this.#destroyHandshake();
    return payload;
  }

  encrypt(plain) {
    const counter = this.#sending?.counter;
    return { counter, ciphertext: b64(this.encryptBytes(plain)) };
  }

  encryptBytes(plain) {
    if (!this.#sending || plain.length > 65519) throw new Error('SECURE_CHANNEL_FAILED');
    return this.#sending.process(plain, empty, false);
  }

  decrypt(counter, encrypted) {
    if (!this.#receiving || counter !== this.#receiving.counter) throw new Error('SECURE_CHANNEL_FAILED');
    return this.decryptBytes(bytes(encrypted, undefined, 65535));
  }

  decryptBytes(encrypted) {
    if (!this.#receiving || !Buffer.isBuffer(encrypted) || encrypted.length > 65535) throw new Error('SECURE_CHANNEL_FAILED');
    return this.#receiving.process(encrypted, empty, true);
  }

  #destroyHandshake() {
    this.#ephemeral.fill(0);
    this.#static.fill(0);
    this.#chain.fill(0);
    this.#handshake?.destroy();
  }

  destroy() {
    this.#destroyHandshake();
    this.#sending?.destroy();
    this.#receiving?.destroy();
    this.#sending = this.#receiving = undefined;
  }
}

export const maxMessage = 4 * 1024 * 1024;
const fragmentBytes = 48 * 1024;
const fragmentHeader = 17;
const magic = Buffer.from('DSHF');

export class Fragments {
  #next = 1;
  #incoming = new Map();

  *split(message) {
    if (message.length > maxMessage) throw new Error('FRAME_TOO_LARGE');
    if (message.length <= fragmentBytes) { yield message; return; }
    const id = this.#next;
    this.#next = id === 0xffffffff ? 1 : id + 1;
    const total = Math.ceil(message.length / fragmentBytes);
    for (let index = 0; index < total; index++) {
      const header = Buffer.alloc(fragmentHeader);
      magic.copy(header);
      header[4] = 1;
      header.writeUInt32BE(id, 5);
      header.writeUInt16BE(index, 9);
      header.writeUInt16BE(total, 11);
      header.writeUInt32BE(message.length, 13);
      yield Buffer.concat([header, message.subarray(index * fragmentBytes, (index + 1) * fragmentBytes)]);
    }
  }

  add(frame) {
    if (!frame.subarray(0, 4).equals(magic)) {
      if (frame.length > fragmentBytes) throw new Error('INVALID_MESSAGE');
      return frame;
    }
    if (frame.length < fragmentHeader || frame[4] !== 1) throw new Error('INVALID_MESSAGE');
    const id = frame.readUInt32BE(5);
    const index = frame.readUInt16BE(9);
    const total = frame.readUInt16BE(11);
    const size = frame.readUInt32BE(13);
    if (id === 0 || total < 2 || index >= total || size <= fragmentBytes || size > maxMessage ||
        total !== Math.ceil(size / fragmentBytes) || frame.length - fragmentHeader !== Math.min(fragmentBytes, size - index * fragmentBytes)) {
      throw new Error('INVALID_MESSAGE');
    }
    let parts = this.#incoming.get(id);
    if (!parts) {
      if (index !== 0 || this.#incoming.size >= 8) throw new Error('INVALID_MESSAGE');
      parts = { size, chunks: [] };
      this.#incoming.set(id, parts);
    }
    if (parts.size !== size || parts.chunks.length !== index) throw new Error('INVALID_MESSAGE');
    parts.chunks.push(frame.subarray(fragmentHeader));
    if (index + 1 < total) return undefined;
    this.#incoming.delete(id);
    return Buffer.concat(parts.chunks, size);
  }

  reset() { this.#incoming.clear(); }
}

const decoder = new TextDecoder('utf-8', { fatal: true });
export function parseWire(input) {
  try {
    const text = typeof input === 'string' ? input : decoder.decode(input);
    const value = JSON.parse(text);
    const objects = [];
    for (let i = 0; i < text.length; i++) {
      const char = text[i];
      if (char === '{') objects.push(new Set());
      else if (char === '[') objects.push(undefined);
      else if (char === '}' || char === ']') objects.pop();
      else if (char === '"') {
        const start = i;
        for (i++; i < text.length; i++) {
          if (text[i] === '\\') i++;
          else if (text[i] === '"') break;
        }
        let next = i + 1;
        while (/\s/u.test(text[next] ?? '')) next++;
        if (text[next] !== ':') continue;
        const keys = objects.at(-1);
        const key = JSON.parse(text.slice(start, i + 1));
        if (keys.has(key)) throw new Error();
        keys.add(key);
      }
    }
    return value;
  } catch { throw new Error('INVALID_MESSAGE'); }
}

export const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
export const text = (value, max = 128) => typeof value === 'string' && !!value && value.length <= max && !/[\x00-\x1f\x7f]/u.test(value);

export function envelope(input, types) {
  const frame = parseWire(input);
  if (!isObject(frame) || Object.keys(frame).length !== 5 || frame.v !== 1 || !text(frame.id) || !types.has(frame.type) ||
      !Number.isSafeInteger(frame.timestamp) || frame.timestamp <= 0 || !isObject(frame.payload)) throw new Error('INVALID_MESSAGE');
  return frame;
}

export function frame(type, payload) {
  return { v: 1, id: randomUUID(), type, timestamp: Date.now(), payload };
}
