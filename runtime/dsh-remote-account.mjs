// DSH Remote v1 pairing derived from ds-harness-remote (MIT).
// Copyright (c) 2026 DSH Remote contributors. See THIRD_PARTY_NOTICES.md.
import { createHash, randomUUID } from 'node:crypto';
import { constants } from 'node:fs';
import { mkdir, open } from 'node:fs/promises';
import { isIP } from 'node:net';
import { join } from 'node:path';
import { writeFileAtomic } from '@deepseek-ai/dsh-atomic-write';
import { RemoteFailure } from './dsh-remote-channel.mjs';
import { bytes, fingerprint, isObject, pairingProof, parseWire, text, x25519Key } from './dsh-remote-wire.mjs';

const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const pairType = 'dsh-pairing-v1';
const defaultOrigin = 'https://dsh.r2049.cn';
const maxRest = 512 * 1024;
const noAuth = new Set(['AUTH_INVALID', 'AUTH_REQUIRED', 'TOKEN_EXPIRED', 'ACCOUNT_AUTH_REQUIRED']);

function privateHost(host) {
  const ip = host.replace(/^\[|\]$/g, '');
  if (isIP(ip) === 6) return ip === '::1' || /^(?:f[cd]|fe[89ab])/i.test(ip);
  if (isIP(ip) !== 4) return ip === 'localhost' || /\.(?:local|localhost|test)$/i.test(ip);
  const [a, b] = ip.split('.').map(Number);
  return a === 10 || a === 127 || (a === 192 && b === 168) || (a === 172 && b >= 16 && b < 32) ||
    (a === 169 && b === 254) || (a === 100 && b >= 64 && b <= 127);
}

export function normalizeRemoteOrigin(input = defaultOrigin) {
  if (typeof input !== 'string' || !input.trim() || /[\x00-\x20\x7f\\]/u.test(input.trim())) {
    throw new RemoteFailure('SERVER_ORIGIN_INVALID');
  }
  try {
    const value = input.trim();
    const url = new URL(value.includes('://') ? value : 'https://' + value);
    if (!url.hostname || url.username || url.password || url.pathname !== '/' || url.search || url.hash ||
        /[?#]/.test(value) || (url.protocol !== 'https:' && !(url.protocol === 'http:' && privateHost(url.hostname)))) throw new Error();
    return url.origin;
  } catch { throw new RemoteFailure('SERVER_ORIGIN_INVALID'); }
}

export async function readBounded(stream, limit) {
  if (!stream) return Buffer.alloc(0);
  const chunks = [];
  let size = 0;
  for await (const chunk of stream) {
    const data = Buffer.from(chunk);
    size += data.length;
    if (size > limit) throw new RemoteFailure('FRAME_TOO_LARGE');
    chunks.push(data);
  }
  return Buffer.concat(chunks, size);
}

async function rest(origin, path, { method = 'GET', body, token, proof, signal } = {}) {
  const target = new URL(path, origin);
  if (target.origin !== origin) throw new RemoteFailure('SERVER_ORIGIN_INVALID');
  const headers = { accept: 'application/json' };
  if (body !== undefined) headers['content-type'] = 'application/json';
  if (token) headers.authorization = 'Bearer ' + token;
  if (proof) headers['x-dsh-pairing-proof'] = proof;
  let res;
  let raw;
  try {
    const timeout = AbortSignal.timeout(10000);
    res = await fetch(target, { method, body, headers, redirect: 'error',
      signal: signal ? AbortSignal.any([signal, timeout]) : timeout });
    raw = await readBounded(res.body, maxRest);
  } catch (error) {
    if (error?.code === 'FRAME_TOO_LARGE') throw error;
    throw new RemoteFailure(signal?.aborted ? 'CLIENT_CLOSED' : 'CONNECTION_FAILED');
  }
  let result;
  if (raw.length) {
    try { result = parseWire(raw); }
    catch (error) { if (res.ok) throw error; }
  }
  if (res.ok) return result;
  const fallback = ({ 401: 'AUTH_INVALID', 403: 'AUTH_REQUIRED', 404: 'DEVICE_NOT_FOUND', 429: 'RATE_LIMITED' })[res.status];
  const failure = new RemoteFailure(result?.error?.code ?? result?.code ?? fallback ?? (res.status >= 500 ? 'CONNECTION_FAILED' : 'INVALID_MESSAGE'));
  failure.status = res.status;
  throw failure;
}

function device(value, role) {
  if (!isObject(value) || !text(value.deviceId) || !text(value.name, 256) || !text(value.platform, 64) || value.role !== role) {
    throw new RemoteFailure('PAIRING_IDENTITY_MISMATCH');
  }
  bytes(value.identityKey, 32);
  return { deviceId: value.deviceId, name: value.name, platform: value.platform, role, identityKey: value.identityKey };
}

const sameDevice = (a, b) => a.deviceId === b.deviceId && a.identityKey === b.identityKey && a.role === b.role;
const tokenValid = value => text(value, 8192) && value.length >= 16;
const expiry = value => Number.isSafeInteger(value) && value > 0;
const guardedText = value => value.replace(/[\u202a-\u202e\u2066-\u2069]/g, '');

function tokens(value, live = false) {
  if (!isObject(value) || Object.keys(value).length !== 4 || !tokenValid(value.accessToken) || !tokenValid(value.refreshToken) ||
      !expiry(value.accessTokenExpiresAt) || !expiry(value.refreshTokenExpiresAt) ||
      (live && (value.accessTokenExpiresAt <= Date.now() || value.refreshTokenExpiresAt <= Date.now()))) {
    throw new RemoteFailure('ACCOUNT_AUTH_REQUIRED');
  }
  return value;
}

function offer(origin, value, ticket) {
  if (!isObject(value) || value.v !== 1 || !uuid.test(value.sessionId) || !expiry(value.expiresAt) ||
      value.expiresAt < Date.now() - 120000 || value.expiresAt > Date.now() + 600000) throw new RemoteFailure('PAIRING_EXPIRED');
  bytes(value.scanSecret, 32);
  bytes(value.serverPublicKey, 32);
  const host = device(value.host, 'host');
  if ((ticket && ticket !== value.scanSecret) || value.serverPublicKey === host.identityKey) {
    throw new RemoteFailure('PAIRING_IDENTITY_MISMATCH');
  }
  return { origin, host, sessionId: value.sessionId, expiresAt: value.expiresAt,
    scanSecret: value.scanSecret, serverPublicKey: value.serverPublicKey };
}

function parseScan(raw) {
  if (typeof raw !== 'string' || Buffer.byteLength(raw) > 4096) throw new RemoteFailure('PAIRING_SCAN_INVALID');
  const scan = raw.trim();
  if (scan.startsWith('{')) {
    const value = parseWire(scan);
    if (!isObject(value) || value.type !== 'dsh.remote.pairing') throw new RemoteFailure('PAIRING_SCAN_INVALID');
    const origin = normalizeRemoteOrigin(value.serverUrl);
    if (origin !== value.serverUrl) throw new RemoteFailure('PAIRING_SCAN_INVALID');
    return { origin, legacy: value };
  }
  let url;
  try { url = new URL(scan); } catch { throw new RemoteFailure('PAIRING_SCAN_INVALID'); }
  if (url.pathname !== '/pair' || url.username || url.password || scan.includes('?') ||
      !/^#v1\.[A-Za-z0-9_-]{43}$/.test(url.hash)) throw new RemoteFailure('PAIRING_SCAN_INVALID');
  const ticket = url.hash.slice(4);
  bytes(ticket, 32);
  return { origin: normalizeRemoteOrigin(url.origin), ticket };
}

function providerRows(value) {
  if (!Array.isArray(value?.items) || value.items.length > 32) throw new RemoteFailure('INVALID_MESSAGE');
  const rows = [];
  for (const row of value.items) {
    if (!isObject(row) || typeof row.id !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(row.id) ||
        !text(row.displayName, 128) || rows.some(item => item.id === row.id)) throw new RemoteFailure('INVALID_MESSAGE');
    const start = row.qrStartUrl;
    if (start == null) continue;
    if (typeof start !== 'string' || !start.startsWith('/api/v1/auth/') || /[\\#\s]/u.test(start) ||
        start.split('?')[0].split('/').some(part => part === '.' || part === '..' || part.includes('%'))) {
      throw new RemoteFailure('INVALID_MESSAGE');
    }
    rows.push({ id: row.id, name: guardedText(row.displayName), start });
  }
  return rows;
}

function browserUrl(origin, raw) {
  if (!text(raw, 4096)) throw new RemoteFailure('INVALID_MESSAGE');
  const url = new URL(raw);
  if (url.origin !== origin || url.username || url.password || url.hash || !url.pathname.startsWith('/api/v1/auth/')) {
    throw new RemoteFailure('INVALID_MESSAGE');
  }
  return url.href;
}

export class RelayAccounts {
  #root;
  #accounts = new Map();
  #operations = new Map();
  #signal;

  constructor(dataDir, signal) {
    this.#root = join(dataDir, 'dsh-remote');
    this.#signal = signal;
  }

  async #load(origin) {
    const name = createHash('sha256').update(origin).digest('hex');
    const path = join(this.#root, name + '.json');
    let file;
    try { file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK); }
    catch (error) {
      if (error.code !== 'ENOENT') throw new RemoteFailure('RELAY_STORAGE_FAILED');
      return { origin, path, identity: undefined, credentials: undefined, pins: Object.create(null) };
    }
    try {
      const info = await file.stat();
      if (!info.isFile() || info.size > maxRest || (info.mode & 0o077)) throw new Error();
      const value = parseWire(await file.readFile());
      if (value.v !== 1 || value.origin !== origin || !isObject(value.identity) || !isObject(value.pins)) throw new Error();
      const identity = value.identity;
      if (!uuid.test(identity.deviceId) || x25519Key(bytes(identity.privateKey, 32)).publicKey !== identity.publicKey) throw new Error();
      for (const [id, key] of Object.entries(value.pins)) {
        if (!text(id)) throw new Error();
        bytes(key, 32);
      }
      if (value.credentials) {
        if (!text(value.credentials.account, 320)) throw new Error();
        tokens(value.credentials.tokens);
      }
      return { origin, path, identity, credentials: value.credentials, pins: Object.assign(Object.create(null), value.pins) };
    } catch { throw new RemoteFailure('RELAY_STORAGE_FAILED'); }
    finally { await file.close(); }
  }

  #account(origin) {
    if (!this.#accounts.has(origin)) {
      const loading = this.#load(origin).catch(error => { this.#accounts.delete(origin); throw error; });
      this.#accounts.set(origin, loading);
    }
    return this.#accounts.get(origin);
  }

  async #save(account, credentials, pins = account.pins) {
    const payload = JSON.stringify({ v: 1, origin: account.origin, identity: account.identity, credentials, pins });
    if (Buffer.byteLength(payload) > maxRest) throw new RemoteFailure('RELAY_STORAGE_FAILED');
    await mkdir(this.#root, { mode: 0o700, recursive: true });
    await writeFileAtomic(account.path, payload, { mode: 0o600, dirMode: 0o700 })
      .catch(() => { throw new RemoteFailure('RELAY_STORAGE_FAILED'); });
    account.credentials = credentials;
    account.pins = pins;
    account.rotated = undefined;
  }

  #op(origin, kind, details) {
    const now = Date.now();
    for (const [id, row] of this.#operations) if (row.expiresAt < now) this.#operations.delete(id);
    if (this.#operations.size >= 32) throw new RemoteFailure('RATE_LIMITED');
    const id = randomUUID();
    this.#operations.set(id, { origin, kind, ...details });
    return id;
  }

  #takeOperation(id, kind, allowExpired = false) {
    const operation = this.#operations.get(id);
    if (!operation || operation.kind !== kind || (!allowExpired && operation.expiresAt < Date.now())) {
      throw new RemoteFailure('PAIRING_EXPIRED');
    }
    return operation;
  }

  async #device(account) {
    if (!account.identity) account.identity = { deviceId: randomUUID(), ...x25519Key() };
    return { deviceId: account.identity.deviceId, name: 'Harness Pocket (HarmonyOS)', role: 'client',
      platform: 'dsh-app-harmonyos', identityKey: account.identity.publicKey };
  }

  async #access(account, force = false) {
    const stored = account.credentials;
    if (!stored || stored.tokens.refreshTokenExpiresAt <= Date.now()) throw new RemoteFailure('ACCOUNT_AUTH_REQUIRED');
    if (!account.rotated && !force && stored.tokens.accessTokenExpiresAt > Date.now() + 30000) return stored.tokens.accessToken;
    if (!account.rotated) {
      let reply;
      try {
        reply = await rest(account.origin, '/api/v1/auth/refresh', { method: 'POST', signal: this.#signal,
          body: JSON.stringify({ deviceId: account.identity.deviceId, refreshToken: stored.tokens.refreshToken }) });
      } catch (error) {
        if (!noAuth.has(error.code) && !['DEVICE_NOT_FOUND', 'DEVICE_REVOKED', 'REFRESH_REPLAY'].includes(error.code)) throw error;
        await this.#save(account, undefined);
        throw new RemoteFailure('ACCOUNT_AUTH_REQUIRED');
      }
      account.rotated = { account: stored.account, tokens: tokens(reply, true) };
    }
    // A failed disk write must never resend the refresh token the server just rotated.
    await this.#save(account, account.rotated);
    return account.credentials.tokens.accessToken;
  }

  async #auth(account, path) {
    const token = await this.#access(account);
    try { return await rest(account.origin, path, { token, signal: this.#signal }); }
    catch (error) {
      if (!noAuth.has(error.code)) throw error;
      return rest(account.origin, path, { token: await this.#access(account, true), signal: this.#signal });
    }
  }

  async providers(origin) {
    let rows;
    try { rows = await rest(origin, '/api/v1/auth/oauth/providers', { signal: this.#signal }); }
    catch (error) { if (error.status === 404) return { items: [] }; throw error; }
    return { items: providerRows(rows).map(row => ({ id: row.id, name: row.name })) };
  }

  async passwordLogin(origin, email, password) {
    if (!text(email, 254) || !text(password, 1024)) throw new RemoteFailure('AUTH_INVALID');
    const value = await rest(origin, '/api/v1/auth/login', { method: 'POST', signal: this.#signal,
      body: JSON.stringify({ email: email.trim(), password }) });
    if (!tokenValid(value?.token) || !text(value.account, 320)) throw new RemoteFailure('INVALID_MESSAGE');
    const account = await this.#account(origin);
    this.#assertAccount(account, value.account);
    const fresh = await this.#register(account, value.token);
    await this.#save(account, { account: value.account, tokens: fresh });
    return {};
  }

  async #register(account, token) {
    const mobile = await this.#device(account);
    return tokens(await rest(account.origin, '/api/v1/devices/register', { method: 'POST', token,
      body: JSON.stringify({ v: 1, device: { ...mobile, clientVersion: '1.0.0' } }), signal: this.#signal }), true);
  }

  async browserStart(origin, providerId) {
    const providers = providerRows(await rest(origin, '/api/v1/auth/oauth/providers', { signal: this.#signal }));
    const provider = providers.find(item => item.id === providerId);
    if (!provider) throw new RemoteFailure('ACCOUNT_AUTH_REQUIRED');
    const value = await rest(origin, provider.start, { method: 'POST', body: '{}', signal: this.#signal });
    if (!text(value?.qrId, 256) || value.qrId.length < 20 || !expiry(value.expiresIn) || value.expiresIn > 1800 ||
        (value.provider != null && value.provider !== provider.id)) throw new RemoteFailure('INVALID_MESSAGE');
    const url = browserUrl(origin, value.scanUrl);
    const expiresAt = Date.now() + value.expiresIn * 1000;
    const id = this.#op(origin, 'browser', { qrId: value.qrId, expiresAt });
    return { id, url, expiresAt };
  }

  async browserStatus(id) {
    const operation = this.#takeOperation(id, 'browser');
    const { origin } = operation;
    if (!operation.accountToken) {
      const value = await rest(origin, '/api/v1/auth/oauth/qr/' + encodeURIComponent(operation.qrId), { signal: this.#signal });
      if (value?.status === 'pending') return { state: 'pending' };
      if (value?.status === 'expired') {
        this.#operations.delete(id);
        return { state: 'expired' };
      }
      if (value?.status !== 'complete' || !tokenValid(value.token)) throw new RemoteFailure('INVALID_MESSAGE');
      operation.accountToken = value.token;
    }
    const account = await this.#account(origin);
    const token = operation.accountToken;
    const profile = await rest(origin, '/api/v1/auth/me', { token, signal: this.#signal });
    if (!text(profile?.account, 320)) throw new RemoteFailure('INVALID_MESSAGE');
    this.#assertAccount(account, profile.account);
    if (!operation.tokens) operation.tokens = await this.#register(account, token);
    await this.#save(account, { account: profile.account, tokens: operation.tokens });
    this.#operations.delete(id);
    return { state: 'completed' };
  }

  async pairResolve(raw, expected) {
    const scan = parseScan(raw);
    if (scan.origin !== expected) throw new RemoteFailure('PAIRING_SERVER_MISMATCH');
    const discovery = await rest(scan.origin, '/api/v1/auth/oauth/providers', { signal: this.#signal });
    if (discovery?.capabilities?.devicePairing !== pairType ||
        (scan.ticket && discovery.capabilities.devicePairingQr !== 'fragment-ticket-v1')) throw new RemoteFailure('PAIRING_UNSUPPORTED');
    const value = scan.ticket ? await rest(scan.origin, '/api/v1/device-pairing/resolve', { method: 'POST',
      body: JSON.stringify({ ticket: scan.ticket }), signal: this.#signal }) : scan.legacy;
    const resolved = offer(scan.origin, value, scan.ticket);
    const id = this.#op(scan.origin, 'pair', { offer: resolved, expiresAt: resolved.expiresAt + 420000 });
    return { id, origin: scan.origin, host: guardedText(resolved.host.name), expiresAt: resolved.expiresAt,
      hostFingerprint: fingerprint(resolved.host.identityKey), serverFingerprint: fingerprint(resolved.serverPublicKey) };
  }

  async #pairPost(operation, name, raw) {
    const { offer: resolved, identity } = operation;
    const path = '/api/v1/device-pairing/sessions/' + resolved.sessionId + '/' + name;
    const proof = pairingProof(identity.privateKey, resolved.serverPublicKey, resolved.sessionId, path, raw);
    return rest(resolved.origin, path, { method: 'POST', body: raw, proof, signal: this.#signal });
  }

  async pairClaim(id) {
    const operation = this.#takeOperation(id, 'pair');
    const { offer: resolved } = operation;
    if (resolved.expiresAt + 120000 < Date.now()) throw new RemoteFailure('PAIRING_EXPIRED');
    const account = await this.#account(operation.origin);
    if (!operation.mobile) {
      operation.mobile = await this.#device(account);
      operation.identity = account.identity;
      if (operation.mobile.deviceId === resolved.host.deviceId || operation.mobile.identityKey === resolved.host.identityKey) {
        throw new RemoteFailure('PAIRING_IDENTITY_MISMATCH');
      }
      operation.raw = JSON.stringify({ scanSecret: resolved.scanSecret, device: operation.mobile });
    }
    const value = await this.#pairPost(operation, 'claim', operation.raw);
    if (value?.state !== 'claimed' || typeof value.verificationCode !== 'string' ||
        !/^[0-9]{8}$/.test(value.verificationCode) || !expiry(value.expiresAt)) throw new RemoteFailure('PAIRING_FAILED');
    operation.claimed = true;
    return { code: value.verificationCode, expiresAt: value.expiresAt };
  }

  async pairStatus(id) {
    const operation = this.#takeOperation(id, 'pair');
    if (!operation.claimed) throw new RemoteFailure('PAIRING_FAILED');
    const { offer: resolved, mobile } = operation;
    const value = await this.#pairPost(operation, 'mobile/status', '{}');
    if (value?.v !== 1 || value.sessionId !== resolved.sessionId ||
        !sameDevice(device(value.host, 'host'), resolved.host) || !sameDevice(device(value.mobile, 'client'), mobile)) {
      throw new RemoteFailure('PAIRING_IDENTITY_MISMATCH');
    }
    if (value.state !== 'completed') {
      if (!['created', 'claimed', 'approved', 'failed', 'cancelled', 'expired'].includes(value.state)) {
        throw new RemoteFailure('PAIRING_FAILED');
      }
      if (['failed', 'cancelled', 'expired'].includes(value.state)) this.#operations.delete(id);
      return { state: value.state };
    }
    const grant = value.credentials;
    if (!isObject(grant) || !text(grant.account, 320) || !['device_only', 'standard'].includes(grant.accountKind) ||
        !sameDevice(device(grant.device, 'client'), mobile) || grant.inboundOnly !== false ||
        typeof grant.pairingRestricted !== 'boolean') throw new RemoteFailure('PAIRING_IDENTITY_MISMATCH');
    const account = await this.#account(operation.origin);
    this.#assertAccount(account, grant.account);
    this.#assertPin(account, resolved.host);
    const pins = Object.assign(Object.create(null), account.pins, { [resolved.host.deviceId]: resolved.host.identityKey });
    await this.#save(account, { account: grant.account, tokens: tokens(grant.tokens, true) }, pins);
    this.#operations.delete(id);
    return { state: 'completed', hostId: resolved.host.deviceId };
  }

  #assertAccount(account, name) {
    if (account.credentials?.tokens.refreshTokenExpiresAt > Date.now() && account.credentials.account !== name) {
      throw new RemoteFailure('PAIRING_ACCOUNT_CONFLICT');
    }
  }

  #assertPin(account, host) {
    if (account.pins[host.deviceId] && account.pins[host.deviceId] !== host.identityKey) {
      throw new RemoteFailure('PEER_IDENTITY_MISMATCH');
    }
  }

  async cancel(id) {
    const operation = this.#operations.get(id);
    this.#operations.delete(id);
    if (operation?.kind === 'pair' && operation.mobile) {
      await this.#pairPost(operation, 'mobile/cancel', '{}').catch(() => {});
    }
    return {};
  }

  async hosts(origin) {
    const account = await this.#account(origin);
    if (!account.credentials || account.credentials.tokens.refreshTokenExpiresAt <= Date.now()) return { signedIn: false, hosts: [] };
    let value;
    try { value = await this.#auth(account, '/api/v1/devices'); }
    catch (error) {
      if (error.code !== 'ACCOUNT_AUTH_REQUIRED') throw error;
      return { signedIn: false, hosts: [] };
    }
    if (!Array.isArray(value?.items) || value.items.length > 1024) throw new RemoteFailure('INVALID_MESSAGE');
    const hosts = [];
    for (const row of value.items) {
      if (row?.role !== 'host') continue;
      if (!text(row.deviceId) || !text(row.name, 256) || !text(row.membershipId)) throw new RemoteFailure('INVALID_MESSAGE');
      hosts.push({ id: row.deviceId, name: guardedText(row.name), online: row.online === true });
    }
    return { signedIn: true, hosts };
  }

  async peer(origin, hostId, accepted, forceRefresh = false) {
    if (!text(hostId)) throw new RemoteFailure('INVALID_MESSAGE');
    const account = await this.#account(origin);
    if (forceRefresh) await this.#access(account, true);
    const route = '/api/v1/devices/' + encodeURIComponent(hostId);
    const value = await this.#auth(account, route);
    const host = device(value, 'host');
    if (host.deviceId !== hostId || !text(value.membershipId)) throw new RemoteFailure('PEER_IDENTITY_MISMATCH');
    const presence = typeof value.online === 'boolean' ? value : await this.#auth(account, route + '/presence');
    if (typeof presence?.online !== 'boolean' || (presence.deviceId != null && presence.deviceId !== hostId)) {
      throw new RemoteFailure('INVALID_MESSAGE');
    }
    this.#assertPin(account, host);
    const print = fingerprint(host.identityKey);
    if (accepted === undefined) {
      return { id: hostId, name: guardedText(host.name), fingerprint: print, trusted: !!account.pins[hostId], online: presence.online };
    }
    if (!presence.online) throw new RemoteFailure('HOST_OFFLINE');
    if (!account.pins[hostId]) {
      if (accepted !== print) throw new RemoteFailure('HOST_KEY_UNTRUSTED');
      const pins = Object.assign(Object.create(null), account.pins, { [hostId]: host.identityKey });
      await this.#save(account, account.credentials, pins);
    }
    return { origin, device: await this.#device(account), identity: account.identity, host,
      accessToken: await this.#access(account), signal: this.#signal };
  }

  async logout(origin) {
    const account = await this.#account(origin);
    if (!account.credentials) return {};
    const token = await this.#access(account);
    await rest(origin, '/api/v1/devices/self', { method: 'DELETE', token, signal: this.#signal });
    await this.#save(account, undefined);
    return {};
  }
}
