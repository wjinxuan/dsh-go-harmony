import assert from 'node:assert/strict';
import test from 'node:test';
import { editableField, fieldInput, fieldText, parseSettings } from './ui/settings/SettingsSchema.ts';
import {
  providerDiscoveryArgs, providerEndpointValid, providerModelIds, providerRouteValid
} from './ui/settings/ProviderDraft.ts';

function section(schema, data = {}, writable = true) {
  return parseSettings({ writable, namespaces: [{ ns: 'example', schema, ...data }] })[0];
}

test('resolves schemastery references, localized copy, inherited values, and read-only metadata', () => {
  const view = section({ uid: 0, refs: {
    0: { type: 'object', meta: { title: { en: 'Parameters', zh_CN: '参数' } }, dict: { nested: 1, hidden: 4 } },
    1: { type: 'intersect', meta: { disabled: true }, list: [2] },
    2: { type: 'object', dict: { limit: 3 } },
    3: { type: 'number', meta: { default: 6, description: { '': '中文说明', en: 'English' } } },
    4: { type: 'string', meta: { hidden: true } }
  } }, {
    revision: 12, autoGenerate: false, value: { nested: { limit: 9 } }, base: { nested: { limit: 4 } },
    user: { nested: { limit: 9 } }
  }, false);
  assert.equal(view.title, '参数');
  assert.equal(view.revision, 12);
  assert.equal(view.writable, false);
  assert.equal(view.autoGenerate, false);
  assert.deepEqual(view.fields.map(field => field.path), [['nested', 'limit']]);
  const [limit] = view.fields;
  assert.equal(limit.current, 9);
  assert.equal(limit.inherited, 4);
  assert.equal(limit.overridden, true);
  assert.equal(limit.description, '中文说明');
  assert.equal(editableField(limit), false);
});

test('secret wrappers and collections expose state without editable or displayable values', () => {
  const view = section({ type: 'object', dict: {
    credential: { type: 'string', meta: { role: 'credential-ref' } },
    secret: { type: 'transform', meta: { role: 'secret' }, inner: { type: 'string' } },
    credentials: { type: 'array', inner: { type: 'string', meta: { role: 'secret' } } }
  } }, {
    value: { credential: 'EXAMPLE_REF', secret: 'synthetic fixture', credentials: ['synthetic fixture'] },
    base: { secret: 'synthetic fixture' }, secrets: [{ path: ['secret'], set: true }]
  });
  assert.deepEqual(view.fields.map(field => field.path), [['secret'], ['credentials']]);
  const [secret, collection] = view.fields;
  assert.equal(secret.current, undefined);
  assert.equal(secret.inherited, undefined);
  assert.equal(fieldText(secret), '已设置');
  assert.throws(() => fieldInput(secret, ' '), /必填/);
  assert.equal(collection.current, undefined);
  assert.equal(fieldText(collection), '含受保护的字段');
  assert.equal(editableField(collection), false);
});

test('preserves scalar choice types and validates numerical and structured settings input', () => {
  const view = section({ type: 'object', dict: {
    choice: { type: 'union', list: [false, 2, 'auto'].map(value => ({ type: 'const', value })) },
    bounded: { type: 'number', meta: { min: 0.05, max: 0.3, step: 0.1, default: 0.15 } },
    list: { type: 'array', inner: { type: 'string' } },
    options: { type: 'dict', inner: { type: 'string' } }
  } });
  const [choice, bounded, list, options] = view.fields;
  assert.deepEqual(choice.choices, [false, 2, 'auto']);
  assert.equal(bounded.inherited, 0.15);
  assert.equal(fieldInput(bounded, '0.25'), 0.25);
  assert.throws(() => fieldInput(bounded, ''), /数字/);
  assert.throws(() => fieldInput(bounded, '0.04'), /最小值/);
  assert.throws(() => fieldInput(bounded, '0.31'), /最大值/);
  assert.throws(() => fieldInput(bounded, '0.2'), /步长/);
  assert.deepEqual(fieldInput(list, '["one"]'), ['one']);
  assert.throws(() => fieldInput(list, '{}'), /数组/);
  assert.deepEqual(fieldInput(options, '{"one":"value"}'), { one: 'value' });
  assert.throws(() => fieldInput(options, '[]'), /对象/);
});

test('validates model channel routes and endpoints, preserving first model occurrence', () => {
  assert.equal(providerRouteValid('my-host-2'), true);
  for (const route of ['2host', 'MyHost', 'my--host', 'host-', 'host/x']) {
    assert.equal(providerRouteValid(route), false, route);
  }
  assert.equal(providerEndpointValid('http://127.0.0.1:8080/v1'), true);
  assert.equal(providerEndpointValid('https://example.test/v1'), true);
  for (const address of ['file:///etc/passwd', 'https://a@example.test', 'https://example.test?q=x',
    'https://example.test#x', 'https://example.test/bad path']) {
    assert.equal(providerEndpointValid(address), false, address);
  }
  assert.deepEqual(providerModelIds(' alpha\r\n\nbeta\nalpha\n gamma '), ['alpha', 'beta', 'gamma']);
});

test('discovery uses saved credentials only for unchanged endpoint and protocol without a draft key', () => {
  const address = 'https://example.test/v1';
  const api = 'openai-completions';
  assert.deepEqual(providerDiscoveryArgs(address, api, '', 'gateway', address, api), {
    settingsNs: 'llm-pi-ai', request: { provider: 'gateway' }
  });
  assert.deepEqual(providerDiscoveryArgs('https://new.example.test/v1', api, '', 'gateway', address, api).request, {
    baseURL: 'https://new.example.test/v1', api
  });
  assert.deepEqual(providerDiscoveryArgs(address, 'anthropic-messages', '', 'gateway', address, api).request, {
    baseURL: address, api: 'anthropic-messages'
  });
  assert.deepEqual(providerDiscoveryArgs(address, api, 'synthetic fixture', 'gateway', address, api).request, {
    baseURL: address, api, apiKey: 'synthetic fixture'
  });
});
