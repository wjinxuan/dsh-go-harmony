import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/ui/TerminalPanel.ets', import.meta.url), 'utf8');
const KeyboardAvoidMode = { OFFSET: 0, RESIZE: 1, OFFSET_WITH_CARET: 2, RESIZE_WITH_CARET: 3, NONE: 4 };

// Run the real component lifecycle methods at the UIContext boundary. This
// verifies terminal callbacks do not compete with Index's page-mode ownership.
// The shared route policy is exercised by page-keyboard-layout.test.mjs; actual
// ArkUI keyboard geometry remains a separate phone acceptance step.
function ownerClass(text, indent) {
  const methods = ['aboutToAppear', 'aboutToDisappear'].map(name => {
    const method = text.match(new RegExp('^ {' + indent + '}' + name + '\\([^]*?^ {' + indent + '}\\}', 'm'));
    assert.ok(method, name + ' lifecycle method');
    return method[0];
  }).join('\n');
  return Function('TerminalApi', 'KeyboardAvoidMode', 'return ' + stripTypeScriptTypes('(class Owner {' + methods + '})'))(
    class TerminalApi {}, KeyboardAvoidMode);
}

function fixture(Owner, initialMode = KeyboardAvoidMode.OFFSET) {
  let mode = initialMode, reads = 0, closed = 0, released = 0, reloads = 0;
  const writes = [];
  const context = { getKeyboardAvoidMode: () => mode, setKeyboardAvoidMode(value) { writes.push(value); mode = value; } };
  const owner = Object.assign(new Owner(), {
    getUIContext() { reads++; return context; },
    client: { connectionIdentity: () => 7 }, sessionId: 'owned-terminal', bridge: {}, revision: 0,
    reload() { reloads++; }, attach: { close() { closed++; } },
    retains: new Map([['owned-terminal', () => released++]]), retaining: new Set(['owned-terminal']),
    controller: { deleteJavaScriptRegister() {} }
  });
  return { owner, writes, mode: () => mode, setExternalMode(value) { mode = value; },
    counters: () => ({ reads, closed, released, reloads }) };
}

function lifecycleTests(label, Owner) {
  test(label + ': entering terminal leaves the route-owned mode intact and initializes terminal callbacks', () => {
    const f = fixture(Owner, KeyboardAvoidMode.RESIZE);
    f.owner.aboutToAppear();
    assert.equal(f.mode(), KeyboardAvoidMode.RESIZE);
    assert.deepEqual(f.writes, []);
    assert.equal(f.counters().reads, 0, 'Index is the only page keyboard owner');
    assert.equal(f.owner.active, true);
    assert.equal(f.owner.session, 'owned-terminal');
    assert.equal(typeof f.owner.bridge.onSize, 'function');
    assert.equal(f.counters().reloads, 1);
  });

  test(label + ': leaving terminal releases its subscriptions without changing any route policy', () => {
    for (const original of Object.values(KeyboardAvoidMode)) {
      const f = fixture(Owner, original);
      f.owner.aboutToAppear();
      assert.equal(f.mode(), original);
      f.owner.aboutToDisappear();
      assert.equal(f.mode(), original);
      assert.deepEqual(f.writes, []);
      assert.equal(f.owner.active, false);
      assert.equal(f.counters().closed, 1);
      assert.equal(f.counters().released, 1);
      assert.equal(f.owner.retains.size, 0);
      assert.equal(f.owner.retaining.size, 0);
      f.owner.aboutToDisappear();
      assert.deepEqual(f.writes, [], 'repeated disposal cannot overwrite the route owner');
    }
  });

  test(label + ': delayed terminal cleanup preserves the next page keyboard policy', () => {
    const f = fixture(Owner);
    f.owner.aboutToAppear();
    f.setExternalMode(KeyboardAvoidMode.NONE);
    f.owner.aboutToDisappear();
    assert.equal(f.mode(), KeyboardAvoidMode.NONE);
    assert.deepEqual(f.writes, []);
  });
}

lifecycleTests('source', ownerClass(source, 2));
if (process.argv[2]) {
  lifecycleTests('actual CompileArkTS output', ownerClass(readFileSync(process.argv[2], 'utf8'), 4));
}
