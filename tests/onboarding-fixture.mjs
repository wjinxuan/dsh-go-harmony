const records = new Map();
const prefValues = new Map();
const decoder = new TextDecoder();
let failure;
let lastReturnType;

export const ACCENTS = [{ id: 'mist' }, { id: 'dusk' }];

export const util = {
  TextEncoder: { create: () => ({ encodeInto: text => new TextEncoder().encode(text) }) },
  TextDecoder: { create: () => ({ decodeToString: value => decoder.decode(value) }) }
};

const missing = () => ({ code: 24000002 });
const alias = query => decoder.decode(query.get(asset.Tag.ALIAS));

function checkFailure() {
  if (failure) throw failure;
}

export const asset = {
  Tag: { ALIAS: 1, SECRET: 2, ACCESSIBILITY: 3, SYNC_TYPE: 4, CONFLICT_RESOLUTION: 5, RETURN_TYPE: 6, IS_PERSISTENT: 7 },
  ErrorCode: { NOT_FOUND: 24000002, ACCESS_DENIED: 24000004, STATUS_MISMATCH: 24000005 },
  Accessibility: { DEVICE_UNLOCKED: 2 },
  SyncType: { NEVER: 0 },
  ConflictResolution: { OVERWRITE: 0 },
  ReturnType: { ALL: 0, ATTRIBUTES: 1 },
  async query(query) {
    lastReturnType = query.get(asset.Tag.RETURN_TYPE);
    checkFailure();
    const record = records.get(alias(query));
    if (!record) throw missing();
    const response = structuredClone(record);
    if (lastReturnType === asset.ReturnType.ATTRIBUTES) response.delete(asset.Tag.SECRET);
    return [response];
  },
  async add(attributes) {
    checkFailure();
    records.set(alias(attributes), structuredClone(attributes));
  },
  async remove(query) {
    checkFailure();
    if (!records.delete(alias(query))) throw missing();
  }
};

export const preferences = {
  async getPreferences(_context, name) {
    if (!prefValues.has(name)) prefValues.set(name, new Map());
    const file = prefValues.get(name);
    return { getSync: (key, fallback) => file.get(key) ?? fallback,
      putSync: (key, value) => { file.set(key, value); }, flush: async () => {} };
  }
};

export function failAsset(error) { failure = error; }
export function storedAsset() { return records.values().next().value; }
export function assetReturnType() { return lastReturnType; }
