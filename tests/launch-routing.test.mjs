import { localizedSettingsText as t, localizedSettingsFormat as f } from './settings-locale-fixture.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import test from 'node:test';
const nav = readFileSync(new URL('../entry/src/main/ets/ui/ShellNavigationData.ets', import.meta.url), 'utf8')
  .replace(/^import .*\n/gm, '').replace(/^export /gm, '');
const shares = readFileSync(new URL('../entry/src/main/ets/ui/ShareLaunchData.ets', import.meta.url), 'utf8').replace(/^export /gm, '');
const forum = readFileSync(new URL('../entry/src/main/ets/forum/ForumCallback.ets', import.meta.url), 'utf8').replace(/^export /gm, '');
const entry = readFileSync(new URL('../entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');
const index = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const receive = entry.slice(entry.indexOf('  private receiveLaunch('), entry.indexOf('  onForeground('));
const dispatch = index.slice(index.indexOf('  private pendingLaunchChanged('), index.indexOf('  private openDestination('));
const store = new Map();
const globals = { object: value => value && typeof value === 'object' ? value : {},
  string: value => typeof value === 'string' ? value : '', strings: value => Array.isArray(value) ? value.filter(x => typeof x === 'string') : [],
  AppStorage: { setOrCreate: (key, value) => store.set(key, value) } };
const { Entry, Owner } = vm.runInNewContext(stripTypeScriptTypes(`${nav}\n${shares}\n${forum}\nclass Entry { ${receive} }\nclass Owner { ${dispatch} }\n({Entry, Owner})`), globals);
function owner() {
 const calls = [];
 const target = new Owner();
 Object.assign(target, { t, f, launchRequest: '', foreground: true, busy: false, sending: false, connected: true, page: 'chat',
  draft: 'existing draft', sessions: [{ id: 'known', title: 'Known' }],
  showShareImport() { calls.push('share'); }, home() { calls.push('home'); }, startVoice() { calls.push('voice'); }, hostScope: () => 'fixture',
  openSession: (id) => calls.push('session:' + id), openDestination: id => calls.push('page:' + id) });
 return { target, calls };
}
test('ability accepts only allowlisted deep links or bounded shortcut payloads', () => {
 store.clear(); const ability = new Entry();
 ability.receiveLaunch({ uri: 'dshgo://open/files?path=/private' });
 assert.equal(store.size, 0);
 ability.receiveLaunch({ uri: 'https://evil.invalid' }); assert.equal(store.size, 0);
 ability.receiveLaunch({ uri: 'dshgo://open/settings' });
 assert.equal(JSON.parse(store.get('dshLaunchRequest')).page, 'settings');
 store.clear(); ability.receiveLaunch({ parameters: { 'dsh.kind': 'new', 'dsh.text': 'x'.repeat(131073) } });
 assert.equal(store.size, 0);
 ability.receiveLaunch({ parameters: { 'dsh.kind': 'new', 'dsh.text': '/delete everything', token: 'never forward' } });
 const request = JSON.parse(store.get('dshLaunchRequest'));
 assert.equal(request.entry.text, '/delete everything'); assert.equal(JSON.stringify(request).includes('never forward'), false);
});
test('shortcut text stays in draft and waits through onboarding, sending, and disconnection', () => {
 const { target, calls } = owner();
 target.launchRequest = JSON.stringify({ entry: { kind: 'new', text: '/command' } });
 target.sending = true; target.pendingLaunchChanged(); assert.equal(calls.length, 0);
 target.sending = false; target.connected = false; target.pendingLaunchChanged(); assert.equal(calls.length, 0);
 target.connected = true; target.page = 'onboarding'; target.pendingLaunchChanged(); assert.equal(calls.length, 0);
 target.page = 'chat'; target.pendingLaunchChanged();
 assert.deepEqual(calls, ['home']); assert.equal(target.draft, 'existing draft\n\n/command'); assert.equal(target.launchRequest, '');
 target.pendingLaunchChanged(); assert.equal(calls.length, 1);
});
test('recent chats never cause automatic host switching; voice waits for foreground', () => {
 const { target, calls } = owner();
 target.launchRequest = JSON.stringify({ entry: { kind: 'chat', sessionId: 'known', host: 'other' } });
 target.pendingLaunchChanged(); assert.equal(calls.length, 0); assert.match(target.errorText, /主机/);
 target.launchRequest = JSON.stringify({ entry: { kind: 'voice' } }); target.foreground = false;
 target.pendingLaunchChanged(); assert.equal(calls.length, 0);
 target.foreground = true; target.pendingLaunchChanged(); assert.deepEqual(calls, ['home', 'voice']);
});

test('share launch opens a read-only importer and never sends conversation content', () => {
 const ability = new Entry(); store.clear();
 ability.receiveLaunch({ uri: 'dshgo://go.dshtui.com/c/abcdEF1234#k=' + 'A'.repeat(43) });
 const request = store.get('dshLaunchRequest'); assert.ok(request);
 const { target, calls } = owner(); target.connected = false; target.launchRequest = request; target.pendingLaunchChanged();
 assert.deepEqual(calls, ['share']); assert.match(target.shareInput, /^https:\/\/go.dshtui.com/); assert.equal(target.draft, 'existing draft');
 store.clear(); ability.receiveLaunch({ uri: 'file://docs/shared/opaque-id', type: 'application/vnd.dshgo+json' });
 target.launchRequest = store.get('dshLaunchRequest'); target.pendingLaunchChanged(); assert.equal(target.shareFile, 'file://docs/shared/opaque-id');
 store.clear(); ability.receiveLaunch({ uri: 'file:///data/private.key', type: 'text/plain' }); assert.equal(store.size, 0);
});

test('DS Bot launch uses the same bounded host and ID validation and retains the bot/group discriminator',()=>{
 const ability = new Entry();
 for (const kind of ['dsbot-bot','dsbot-room']) { store.clear(); ability.receiveLaunch({parameters:{'dsh.kind':kind,'dsh.sessionId':'a','dsh.host':'local'}}); const entry=JSON.parse(store.get('dshLaunchRequest')).entry; assert.equal(entry.kind,kind); assert.equal(entry.sessionId,'a'); assert.equal(entry.host,'local'); }
 store.clear(); ability.receiveLaunch({parameters:{'dsh.kind':'dsbot-bot','dsh.sessionId':'x'.repeat(257)}}); assert.equal(store.size,0);
});


test('inline codes accept the original conversation, profile and plugin links without executing them', () => {
 const ability = new Entry();
 for (const kind of ['conversation', 'profile', 'plugin']) {
  store.clear(); ability.receiveLaunch({ uri: 'dshgo://share/' + kind + '?p=AAab09_-.12345678' });
  const request = JSON.parse(store.get('dshLaunchRequest')); assert.match(request.share.link, /AAab09_-/);
 }
 for (const uri of ['dshgo://share/profile?p=abc.12345678&execute=1', 'https://evil.example/share#p=abc.12345678', 'dshgo://share/plugin?p=%00abc.12345678']) {
  store.clear(); ability.receiveLaunch({ uri }); assert.equal(store.size, 0);
 }
});

test('every original allowlisted destination has an implemented route and session search opens the shared drawer', () => {
 const route = index.slice(index.indexOf('  private openDestination('), index.indexOf('  private showSettings('));
 const { Router, ids } = vm.runInNewContext(stripTypeScriptTypes(`${nav}\nclass Router { ${route} }\n({Router,ids:PAGE_LINK_IDS})`), { ...globals });
 const calls = [], router = new Router(); Object.assign(router, { t, sessionId: 'chat', searchRequest: 0,
  openFeature: id => calls.push(id), showRemoteHosts() {}, showShareImport() {}, showSettings: id => calls.push(id), home() {},
  showDetail() {}, showFiles() {}, showSessionOptions: async () => {} });
 for (const id of ids) { router.errorText = ''; router.openDestination(id); assert.equal(router.errorText, '', id); }
 router.openDestination('search'); assert.equal(router.page, 'chat'); assert.equal(router.drawer, true); assert.equal(router.searchRequest, 1);
 router.openDestination('cordis'); assert.equal(router.page, 'nativePlugins'); assert.equal(router.pluginSection, 'cordis');
 router.openDestination('pets'); assert.equal(router.page, 'pets'); router.openDestination('companion'); assert.equal(router.page, 'companion');
});
test('home-screen companion card opens only its exact allowlisted page and sends no chat input',()=>{
 const ability=new Entry();store.clear();ability.receiveLaunch({parameters:{'dsh.page':'companion'}});
 const request=store.get('dshLaunchRequest');assert.equal(JSON.parse(request).page,'companion');
 const {target,calls}=owner();target.launchRequest=request;target.pendingLaunchChanged();assert.deepEqual(calls,['page:companion']);assert.equal(target.draft,'existing draft');
 for(const page of ['settings','../companion','Companion','companion?execute=1']){store.clear();ability.receiveLaunch({parameters:{'dsh.page':page}});assert.equal(store.size,0);}
});
test('system back lets the companion finish nested navigation or discard confirmation before leaving',()=>{
 const method=index.slice(index.indexOf('  onBackPress():'),index.indexOf('  private errorMessage('));
 const Back=vm.runInNewContext(stripTypeScriptTypes(`class Back {${method}};Back`));
 const target=new Back();target.page='companion';let calls=0;target.companionBack=()=>{calls++;return true;};
 assert.equal(target.onBackPress(),true);assert.equal(calls,1);assert.equal(target.page,'companion');
 target.companionBack=()=>false;assert.equal(target.onBackPress(),true);assert.equal(target.page,'features');
});
