import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/ui/ConversationReplay.ets', import.meta.url), 'utf8');
const blank = 'about:blank', origin = 'https://dsh-replay.invalid/';
const html = '<!doctype html><html><body>owned replay fixture</body></html>';

function lifecycle(text, indent) {
  return ['aboutToAppear', 'aboutToDisappear'].map(name =>
    text.match(new RegExp('^ {' + indent + '}' + name + '\\([^]*?^ {' + indent + '}\\}', 'm'))?.[0] || '').join('\n');
}

function fixture(text, compiled = false) {
  const hooks = {}, properties = {}, calls = [];
  let document = '', fail = false;
  const controller = { loadData(...args) {
    if (fail) throw new Error('controller unavailable');
    calls.push(args); document = args[0];
  } };
  const Owner = Function('return ' + stripTypeScriptTypes('(class Owner {' + lifecycle(text, compiled ? 4 : 2) + '})'))();
  const owner = Object.assign(new Owner(), { html, controller, error: '', active: false, started: false, t: value => value });
  let web;
  const capture = (name, args) => {
    if (name === 'create') properties.src = args[0].src;
    else if (name.startsWith('on') && typeof args[0] === 'function') hooks[name] = args[0];
    else properties[name] = args[0];
    return web;
  };
  web = new Proxy(args => { properties.src = args.src; return web; }, {
    get(_target, name) { return (...args) => capture(name, args); }
  });
  const start = text.indexOf(compiled ? 'Web.create(' : 'Web({');
  const end = text.indexOf(compiled ? '\n        }, Web);' : '\n    }.width', start);
  assert.ok(start >= 0 && end > start, 'real Web configuration');
  Function('Web', 'MixedMode', stripTypeScriptTypes(text.slice(start, end))).call(owner, web, { None: 0 });
  owner.aboutToAppear?.();
  return { owner, hooks, properties, calls, document: () => document, fail() { fail = true; },
    // ArkUI binds the controller before first layout loads Web.src. This models
    // that documented lifecycle boundary, not a real ArkWeb renderer.
    attach() { hooks.onControllerAttached?.(); },
    finishInitialPage() { document = ''; hooks.onPageEnd?.({ url: properties.src }); } };
}

function checks(label, text, compiled = false) {
  test(label + ': initial blank navigation completes before the single replay load', () => {
    const f = fixture(text, compiled);
    assert.equal(f.properties.src, blank);
    f.attach();
    assert.equal(f.calls.length, 0, 'loadData during controller attachment is overwritten by the initial src navigation');
    f.finishInitialPage();
    assert.equal(f.document(), html);
    assert.deepEqual(f.calls, [[html, 'text/html', 'UTF-8', origin]]);
    f.hooks.onPageEnd?.({ url: origin });
    f.hooks.onPageEnd?.({ url: blank });
    assert.equal(f.calls.length, 1, 'document completion and repeated blank events must not restart playback');
  });

  test(label + ': finishing the initial page after leaving cannot load the old conversation', () => {
    const f = fixture(text, compiled);
    f.attach();
    f.owner.aboutToDisappear?.();
    f.finishInitialPage();
    assert.equal(f.calls.length, 0);
  });

  test(label + ': load failure is visible and does not create a retry loop', () => {
    const f = fixture(text, compiled); f.fail(); f.attach(); f.finishInitialPage();
    assert.equal(f.owner.error, '回放页面未能加载');
    f.hooks.onPageEnd?.({ url: blank });
    assert.equal(f.calls.length, 0);
  });

  test(label + ': offline rendering retains exact navigation and resource restrictions', () => {
    const f = fixture(text, compiled);
    for (const url of [blank, origin]) assert.equal(f.hooks.onOverrideUrlLoading({ getRequestUrl: () => url }), false);
    for (const url of ['https://example.org/', origin + 'other', 'http://127.0.0.1/', 'file:///private/file',
      'data:text/html,untrusted', 'javascript:alert(1)', 'https://dsh-replay.invalid.evil/']) {
      assert.equal(f.hooks.onOverrideUrlLoading({ getRequestUrl: () => url }), true, url);
    }
    assert.equal(f.properties.blockNetwork, true);
    for (const flag of ['fileAccess', 'domStorageAccess', 'multiWindowAccess', 'onlineImageAccess']) assert.equal(f.properties[flag], false, flag);
    assert.equal(f.properties.mixedMode, 0);
    assert.equal(f.properties.javaScriptAccess, true, 'the original hash-pinned inline replay script still runs');
  });
}

checks('source', source);
if (process.argv[2]) checks('actual CompileArkTS output', readFileSync(process.argv[2], 'utf8'), true);
