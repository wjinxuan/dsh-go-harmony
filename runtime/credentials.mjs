import { constants } from 'node:fs';
import { open } from 'node:fs/promises';
import { join } from 'node:path';
import { timingSafeEqual } from 'node:crypto';
import { withFileLock, writeFileAtomic } from '@deepseek-ai/dsh-atomic-write';
import { CredentialProvider } from '@deepseek-ai/dsh-credentials';
import { PrivateVault } from './private-vault.mjs';

const grantKey = 'deepseek-account-platform/default';
const deviceKey = 'deepseek-account-platform/device';
const accountKeys = new Set([grantKey, deviceKey]);
const subscriptionKeys = new Set(['llm-pi-ai/openai-codex', 'llm-pi-ai/anthropic']);
const persistentKeys = new Set([...accountKeys, ...subscriptionKeys]);
const accountFileLimit = 64 * 1024;
const referencesFilename = '.harmony-provider-credentials.json';
// The existing DeepSeek "remember key" switch is implemented by LocalKeyStore.
// Keep its runtime copy ephemeral; every other reference uses this encrypted vault.
const ephemeralRef = 'DEEPSEEK_API_KEY';

function validateRef(ref) {
  if (typeof ref !== 'string' || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(ref)) throw new Error('凭据名称无效');
}

async function readReferences(vault) {
  try {
    const value = await vault.load();
    if (value === undefined) return {};
    if (!value || value.version !== 1 || Object.keys(value).length !== 2 || !value.refs ||
        typeof value.refs !== 'object' || Array.isArray(value.refs)) throw new Error();
    for (const [ref, secret] of Object.entries(value.refs)) {
      validateRef(ref);
      if (ref === ephemeralRef || typeof secret !== 'string' || !secret) throw new Error();
    }
    return value.refs;
  } catch {
    throw new Error('无法读取已保存的渠道凭据，请解锁手机后重试');
  }
}

function validateAccountRecord(key, record) {
  const payload = record?.payload;
  if (record?.kind !== 'grant' || Object.keys(record).length !== 2 || !payload ||
    typeof payload !== 'object' || Array.isArray(payload)) throw new Error('账号凭据记录无效');
  if (key === deviceKey && Object.keys(payload).length === 1 &&
    typeof payload.id === 'string' && /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(payload.id)) return;
  if (key === grantKey && Object.keys(payload).length === 3 && payload.version === 1 &&
    typeof payload.issuer === 'string' && typeof payload.token === 'string' && /^[\x21-\x7e]+$/.test(payload.token)) return;
  throw new Error('账号凭据记录无效');
}

function validateSubscriptionRecord(key, record) {
  const payload = record?.payload;
  const validJson = (value, depth = 0) => {
    if (depth > 32) return false;
    if (value === null || typeof value === 'string' || typeof value === 'boolean') return true;
    if (typeof value === 'number') return Number.isFinite(value);
    if (Array.isArray(value)) return value.every(item => validJson(item, depth + 1));
    return typeof value === 'object' && Object.getPrototypeOf(value) === Object.prototype &&
      Object.values(value).every(item => validJson(item, depth + 1));
  };
  if (!subscriptionKeys.has(key) || record?.kind !== 'grant' || Object.keys(record).length !== 2 ||
      !payload || Array.isArray(payload) || payload.type !== 'oauth' ||
      typeof payload.access !== 'string' || !payload.access || typeof payload.refresh !== 'string' || !payload.refresh ||
      !Number.isFinite(payload.expires) || payload.expires < 0 || !validJson(payload)) throw new Error('订阅授权记录无效');
}

async function readAccountRecords(path, validate = validateAccountRecord) {
  let file;
  try {
    file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  } catch (error) {
    if (error.code === 'ENOENT') return {};
    throw new Error('无法打开账号凭据文件');
  }
  try {
    const info = await file.stat();
    if (!info.isFile() || (info.mode & 0o077) !== 0 || info.size > accountFileLimit) throw new Error();
    const records = JSON.parse(await file.readFile('utf8'));
    if (!records || typeof records !== 'object' || Array.isArray(records)) throw new Error();
    for (const [key, record] of Object.entries(records)) validate(key, record);
    return records;
  } catch {
    throw new Error('无法读取账号凭据文件');
  } finally {
    await file.close();
  }
}

export default class MemoryCredentials extends CredentialProvider {
  refs = new Map();
  records = new Map();
  writes = Promise.resolve();
  accountPath = join(process.env.DSH_HOME, '.harmony-account-credentials.json');
  subscriptionPath = join(process.env.DSH_HOME, '.harmony-subscription-credentials.json');
  referenceRoot = process.env.DSH_HOME;
  referenceVault;

  constructor(ctx) {
    super(ctx);
    ctx.on('dispose', async () => {
      await this.writes;
      this.referenceVault?.destroy();
      this.referenceVault = undefined;
      this.refs.clear();
    });
  }

  unlockReferences(masterKey) {
    const operation = this.writes.then(async () => {
      let candidate;
      try {
        candidate = new PrivateVault(this.referenceRoot, referencesFilename, masterKey, { maxBytes: accountFileLimit });
        if (this.referenceVault && !timingSafeEqual(this.referenceVault.key, candidate.key)) throw new Error();
        await readReferences(candidate);
        if (!this.referenceVault) { this.referenceVault = candidate; candidate = undefined; }
        return { unlocked: true };
      } catch {
        throw new Error('渠道凭据未能解锁，请解锁手机后重试');
      } finally { candidate?.destroy(); }
    });
    this.writes = operation.catch(() => {});
    return operation;
  }

  requireReferenceVault() {
    if (!this.referenceVault) throw new Error('请解锁手机并连接本机引擎后保存渠道凭据');
    return this.referenceVault;
  }

  async resolve(ref) {
    validateRef(ref);
    const refs = ref === ephemeralRef ? undefined : await readReferences(this.requireReferenceVault());
    const value = ref === ephemeralRef ? this.refs.get(ref) : Object.hasOwn(refs, ref) ? refs[ref] : undefined;
    return value === undefined ? undefined : { value, source: ref === ephemeralRef ? 'memory' : 'file' };
  }

  async describe(ref) {
    validateRef(ref);
    if (ref !== ephemeralRef && !this.referenceVault) return { configured: false, writable: false };
    const result = await this.resolve(ref);
    return result ? { configured: true, source: result.source, writable: true } : { configured: false, writable: true };
  }

  async set(ref, value) {
    validateRef(ref);
    if (typeof value !== 'string' || !value) throw new Error('Empty credential');
    if (ref !== ephemeralRef) return this.modifyReference(ref, value);
    this.refs.set(ref, value);
    this.notifyUpdated(ref);
  }

  async unset(ref) {
    validateRef(ref);
    if (ref !== ephemeralRef) return this.modifyReference(ref, undefined);
    if (this.refs.delete(ref)) this.notifyUpdated(ref);
  }

  modifyReference(ref, value) {
    const operation = this.writes.then(async () => {
      const vault = this.requireReferenceVault();
      const changed = await withFileLock(vault.path, async () => {
        const refs = await readReferences(vault);
        const prior = Object.hasOwn(refs, ref) ? refs[ref] : undefined;
        if (prior === value) return false;
        const next = Object.fromEntries(Object.entries(refs).filter(([key]) => key !== ref));
        if (value !== undefined) Object.defineProperty(next, ref, { value, enumerable: true });
        try { await vault.save({ version: 1, refs: next }); }
        catch { throw new Error('渠道凭据未能安全保存，请重试'); }
        return true;
      }, { waitMs: 30000 });
      if (changed) this.notifyUpdated(ref);
    });
    this.writes = operation.catch(() => {});
    return operation;
  }

  async readRecord(key) {
    if (accountKeys.has(key)) return (await readAccountRecords(this.accountPath))[key];
    if (subscriptionKeys.has(key)) return (await readAccountRecords(this.subscriptionPath, validateSubscriptionRecord))[key];
    return structuredClone(this.records.get(key));
  }

  async describeRecord(key) {
    const record = await this.readRecord(key);
    return record ? { configured: true, kind: record.kind, writable: true } : { configured: false, writable: true };
  }

  async listRecords() {
    const account = Object.entries(await readAccountRecords(this.accountPath));
    const subscriptions = Object.entries(await readAccountRecords(this.subscriptionPath, validateSubscriptionRecord));
    return [...this.records, ...account, ...subscriptions].map(([key, record]) => ({ key, kind: record.kind }));
  }

  modifyRecord(key, mutate) {
    if (persistentKeys.has(key)) return this.modifyAccountRecord(key, mutate, false);
    const operation = this.writes.then(async () => {
      const next = await mutate(await this.readRecord(key));
      if (next !== undefined) {
        this.records.set(key, structuredClone(next));
        this.notifyRecordUpdated(key);
      }
      return this.readRecord(key);
    });
    this.writes = operation.catch(() => {});
    return operation;
  }

  deleteRecord(key) {
    if (persistentKeys.has(key)) return this.modifyAccountRecord(key, undefined, true);
    const operation = this.writes.then(() => {
      if (this.records.delete(key)) this.notifyRecordUpdated(key);
    });
    this.writes = operation.catch(() => {});
    return operation;
  }

  async modifyAccountRecord(key, mutate, remove) {
    const path = subscriptionKeys.has(key) ? this.subscriptionPath : this.accountPath;
    const validate = subscriptionKeys.has(key) ? validateSubscriptionRecord : validateAccountRecord;
    const result = await withFileLock(path, async () => {
      const records = await readAccountRecords(path, validate);
      const current = records[key];
      const next = remove ? undefined : await mutate(structuredClone(current));
      if (remove ? current === undefined : next === undefined) return { changed: false, record: current };
      if (remove) delete records[key];
      else {
        validate(key, next);
        records[key] = next;
      }
      const serialized = JSON.stringify(records);
      if (Buffer.byteLength(serialized) > accountFileLimit) throw new Error('账号凭据记录过大');
      await writeFileAtomic(path, serialized, { mode: 0o600, dirMode: 0o700 });
      return { changed: true, record: next };
    }, { waitMs: 30000 });
    if (result.changed) this.notifyRecordUpdated(key);
    return result.record;
  }
}

// This handler is reachable only through the native authenticated loopback server.
// The public engine credentials RPC never accepts or exposes the AssetStore key.
export function createCredentialsHandler(credentials) {
  return {
    handle(request, response) {
      if (request.method !== 'POST' || request.url !== '/credentials/unlock') return false;
      const reply = (status, body) => {
        if (!response.destroyed) response.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' }).end(JSON.stringify(body));
      };
      (async () => {
        let body = '', bytes = 0;
        try {
          if (!/^application\/json(?:\s*;|$)/i.test(request.headers['content-type'] ?? '') ||
              Number(request.headers['content-length'] ?? 0) > 2048) { request.resume(); throw new Error(); }
          for await (const chunk of request) { bytes += chunk.length; if (bytes > 2048) { request.resume(); throw new Error(); } body += chunk; }
          const value = JSON.parse(body);
          if (!value || Object.keys(value).length !== 1 || typeof value.masterKey !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(value.masterKey)) throw new Error();
          return value.masterKey;
        } catch { reply(400, { error: 'Invalid credential unlock request' }); }
      })().then(async masterKey => {
        if (masterKey === undefined) return;
        try { reply(200, await credentials.unlockReferences(masterKey)); }
        catch { reply(500, { error: 'Credential vault could not be unlocked' }); }
      }).catch(() => reply(500, { error: 'Credential vault could not be unlocked' }));
      return true;
    },
    async close() {}
  };
}
