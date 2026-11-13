import { randomUUID } from 'node:crypto';

const records = new Map();
const decoder = new TextDecoder();
const memory = new Map();
const disk = new Map();
let failure;
let queryType;

export const util = {
  generateRandomUUID: randomUUID,
  TextEncoder: { create: () => ({ encodeInto: text => new TextEncoder().encode(text) }) },
  TextDecoder: { create: () => ({ decodeToString: value => decoder.decode(value) }) }
};

export const url = {
  URL: { parseURL(value) {
    const parsed = new URL(value);
    parsed.params = parsed.searchParams;
    return parsed;
  } }
};

const missing = () => ({ code: 24000002 });
const alias = query => decoder.decode(query.get(asset.Tag.ALIAS));

function fail(operation) {
  if (failure?.operation !== operation) return;
  const error = failure.error;
  failure = undefined;
  throw error;
}

export const asset = {
  Tag: { ALIAS: 1, SECRET: 2, ACCESSIBILITY: 3, SYNC_TYPE: 4, CONFLICT_RESOLUTION: 5, RETURN_TYPE: 6 },
  ErrorCode: { NOT_FOUND: 24000002, ACCESS_DENIED: 24000004, STATUS_MISMATCH: 24000005 },
  Accessibility: { DEVICE_UNLOCKED: 2 },
  SyncType: { NEVER: 0 },
  ConflictResolution: { OVERWRITE: 0 },
  ReturnType: { ALL: 0, ATTRIBUTES: 1 },
  async query(query) {
    fail('query');
    queryType = query.get(asset.Tag.RETURN_TYPE);
    const record = records.get(alias(query));
    if (!record) throw missing();
    const response = structuredClone(record);
    if (queryType === asset.ReturnType.ATTRIBUTES) response.delete(asset.Tag.SECRET);
    return [response];
  },
  async add(attributes) {
    fail('add');
    records.set(alias(attributes), structuredClone(attributes));
  },
  async remove(query) {
    fail('remove');
    if (!records.delete(alias(query))) throw missing();
  }
};

export const preferences = {
  async getPreferences() {
    return {
      getSync: (key, fallback) => memory.get(key) ?? fallback,
      putSync: (key, value) => memory.set(key, value),
      async flush() {
        fail('flush');
        memory.forEach((value, key) => disk.set(key, value));
      }
    };
  }
};

export function resetStorage() {
  records.clear();
  memory.clear();
  disk.clear();
  failure = undefined;
  queryType = undefined;
}

export function failOnce(operation, error) { failure = { operation, error }; }
export function storedAssets() { return [...records.values()]; }
export function lastQueryType() { return queryType; }
export function persistedMetadata() { return JSON.parse(disk.get('hosts-v1') ?? '[]'); }
