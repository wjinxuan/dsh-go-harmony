import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';

const generated = process.argv[2];

test('page construction initializes language storage before translated model state', () => {
  const source = readFileSync(join(generated, '../pages/Index.ts'), 'utf8');
  const initializers = source.split('\n').filter(line => /^\s*this\.__(?:localeLanguage|modelName) =/.test(line));
  assert.equal(initializers.length, 2);
  const getter = source.match(/get localeLanguage\(\) \{([^]*?)\n    \}/);
  assert.ok(getter, 'generated locale getter must be present');
  class Property {
    constructor(value) { this.value = value; }
    get() { return this.value; }
  }
  const page = {
    createStorageProp: () => new Property('en'),
    t(value) { return `${this.localeLanguage}:${value}`; }
  };
  Object.defineProperty(page, 'localeLanguage', { get: new Function(getter[1]) });
  assert.doesNotThrow(() => new Function('ObservedPropertySimplePU', initializers.join('\n')).call(page, Property));
  assert.equal(page.__modelName.get(), 'en:选择模型');
});

// Locale wrappers must stay inside the same generated observers. Normalize only
// label lookups so these checks keep testing state reactivity in either locale.
const normalized = source => source
  .replace(/this\.t\(("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')\)/g, (_match, literal) => "'" + literal.slice(1, -1) + "'")
  .replace(/this\.t\((this\.[A-Za-z_$][\w$]*|text\(\))\)/g, '$1');

function method(file, name) {
  const output = normalized(readFileSync(join(generated, `${file}.ts`), 'utf8'));
  const start = output.indexOf(`    private ${name}(`);
  assert.ok(start >= 0, `${file}.${name} missing from generated ArkUI output`);
  const end = output.indexOf('\n    }', start);
  assert.ok(end > start, `${file}.${name} has no method body`);
  return output.slice(start, end);
}

test('onboarding save reads current form and engine state inside its Button observer', () => {
  const form = method('OnboardingPanel', 'keyForm');
  const save = form.match(/observeComponentCreation2\(\(elmtId, isInitialRender\) => \{\s*Button\.createWithLabel\('保存并继续'\);([^]*?)\}, Button\);/);
  assert.ok(save, 'save Button must be built in a state observer');
  assert.ok(save[1].includes('Button.enabled(!this.saving && !this.engineBusy && this.keyDraft.trim().length > 0);'),
    'save Button must re-read all three state inputs');
  const finish = method('OnboardingPanel', 'finishing');
  assert.match(finish, /if \(this\.finished\)/);
  assert.match(finish, /Text\.create\(this\.stageText\)/);
});

test('settings buttons and text evaluate state inside the generated control observers', () => {
  for (const name of ['filledButton', 'secondaryButton']) {
    const button = method('SettingsPanel', name);
    assert.ok(button.includes('Button.createWithLabel(label());'), `${name} must re-evaluate its label`);
    assert.ok(button.includes('Button.enabled(enabled());'), `${name} must re-evaluate availability`);
  }
  const credential = method('SettingsPanel', 'credential');
  assert.match(credential, /'保存 API Key', \(\) => !this\.working && this\.keyInput\.trim\(\)\.length > 0/);
  assert.match(method('SettingsPanel', 'bodyText'), /Text\.create\(text\(\)\);/);
  assert.match(method('SettingsPanel', 'row'), /Text\.create\(value\(\)\);/);
});

test('settings body text resolves its default color inside the component observer', () => {
  const body = method('SettingsPanel', 'bodyText');
  const header = body.slice(0, body.indexOf('\n'));
  assert.doesNotMatch(header, /\bthis\./, 'builder parameter defaults must not capture component this');
  assert.match(body, /observeComponentCreation2\(\(elmtId, isInitialRender\) => \{[^]*?Text\.fontColor\(color \? color\(\) : this\.colors\.muted\);[^]*?\}, Text\);/);
});

test('session detail actions and context values keep their state dependencies', () => {
  const action = method('SessionDetailPanel', 'action');
  assert.ok(action.includes('Button.createWithLabel(label());'), 'detail action must re-evaluate its label');
  assert.ok(action.includes('Button.enabled(enabled());'), 'detail action must re-evaluate availability');
  const form = method('SessionDetailPanel', 'goalForm');
  assert.match(form, /\(\) => this\.working \? '保存中…' : '保存', \(\) => !this\.working && !!this\.objective\.trim\(\)/);
  assert.match(method('SessionDetailPanel', 'goalCard'), /text: this\.goal\?\.objective/);
  assert.match(method('SessionDetailPanel', 'metric'), /Text\.create\(`\$\{raw\(\)\}\$\{unit\}`\);/);
  assert.match(method('SessionDetailPanel', 'usage'), /\(\) => this\.usageValue\('tokenUsage', 'outputTokens'\)/);
});

test('account wallet observers re-read balance after the async response', () => {
  const wallet = method('AccountPanel', 'wallet');
  assert.match(wallet, /observeComponentCreation2\(\(elmtId, isInitialRender\) => \{[^]*?if \(lines\(\)\)/);
  assert.match(wallet, /forEachUpdateFunction\(elmtId, lines\(\)/);
  const output = normalized(readFileSync(join(generated, 'AccountPanel.ts'), 'utf8'));
  assert.match(output, /wallet\.bind\(this\)\('充值余额', \(\) => this\.overview\.recharge\)/);
  assert.match(output, /wallet\.bind\(this\)\('赠送余额', \(\) => this\.overview\.bonus\)/);
});

test('mention results and retained rows observe the revision after asynchronous updates', () => {
  const picker = normalized(readFileSync(join(generated, 'MentionPickerPanel.ts'), 'utf8'));
  assert.match(picker, /forEachUpdateFunction\(elmtId, this\.sections\(\)/);
  assert.match(picker, /forEachUpdateFunction\(elmtId, this\.items\(section\.title\)/);
  for (const name of ['sections', 'current', 'highlighted', 'loading']) {
    assert.match(method('MentionPickerPanel', name), /this\.revision/);
  }
  const row = method('MentionPickerPanel', 'itemRow');
  assert.match(row, /Text\.create\(this\.current\(item\)\.label\)/);
  assert.match(row, /Row\.backgroundColor\(this\.highlighted\(item\)/);
  assert.match(row, /this\.controller\.pick\(this\.current\(item\)\)/);
});

test('retained voice waveform bars read their current state in the generated observer', () => {
  const chat = method('../pages/Index', 'chatScreen');
  assert.match(chat, /observeComponentCreation2\(\(elmtId, isInitialRender\) => \{[^]*?Column\.height\(4 \+ this\.voiceLevels\[index\] \* 20\);/);
});

test('pet roaming pauses on current editor focus and list scroll state', () => {
  const index = normalized(readFileSync(join(generated, '../pages/Index.ts'), 'utf8'));
  assert.match(index, /idleBlocked: this\.composerFocused \|\| this\.chatScrolling/);
  assert.match(index, /List\.onScrollStart\([^]*?this\.chatScrolling = true/);
  assert.match(index, /List\.onScrollStop\([^]*?this\.chatScrolling = false/);
  const editor=normalized(readFileSync(join(generated, 'MentionEditor.ts'), 'utf8'));
  assert.match(editor,/RichEditor\.onFocus\([^]*?this\.onFocusChanged\(true\)/);
  assert.match(editor,/RichEditor\.onBlur\([^]*?this\.onFocusChanged\(false\)/);
});

test('companion signal switches read asynchronously loaded consent inside each Toggle observer', () => {
 const file=normalized(readFileSync(join(generated,'../companion/CompanionSignalSettings.ts'),'utf8'));
 assert.match(file,/observeComponentCreation2\(\(elmtId, isInitialRender\) => \{[^]*?Toggle\.create\(\{ type: ToggleType\.Switch, isOn: value\(\) \}\)/);
 for(const field of ['state','optionalSpeech','voice','nightCare'])assert.match(file,new RegExp('\\(\\)(?:: boolean)? => this\\.view\\.consent\\?\\.'+field+' === true'));
});

test('companion owners remount when host, connection generation or readiness changes', () => {
 const index=normalized(readFileSync(join(generated,'../pages/Index.ts'),'utf8'));
 assert.match(index,/forEachUpdateFunction\(elmtId, \[`\$\{this\.hostScope\(\)\}\|\$\{this\.connectionVersion\}\|\$\{this\.connected\}`\]/);
});
