import { CredentialProvider } from '@deepseek-ai/dsh-credentials';

export default class MemoryCredentials extends CredentialProvider {
  refs = new Map();
  records = new Map();
  writes = Promise.resolve();

  async resolve(ref) {
    const value = this.refs.get(ref);
    return value === undefined ? undefined : { value, source: 'memory' };
  }

  async describe(ref) {
    return this.refs.has(ref) ? { configured: true, source: 'memory', writable: true } : { configured: false, writable: true };
  }

  async set(ref, value) {
    if (!value) throw new Error('Empty credential');
    this.refs.set(ref, value);
    this.notifyUpdated(ref);
  }

  async unset(ref) {
    if (this.refs.delete(ref)) this.notifyUpdated(ref);
  }

  async readRecord(key) {
    return structuredClone(this.records.get(key));
  }

  async describeRecord(key) {
    const record = this.records.get(key);
    return record ? { configured: true, kind: record.kind, writable: true } : { configured: false, writable: true };
  }

  async listRecords() {
    return Array.from(this.records, ([key, record]) => ({ key, kind: record.kind }));
  }

  modifyRecord(key, mutate) {
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
    const operation = this.writes.then(() => {
      if (this.records.delete(key)) this.notifyRecordUpdated(key);
    });
    this.writes = operation.catch(() => {});
    return operation;
  }
}
