import assert from 'node:assert/strict';import test from 'node:test';import {readFileSync,readdirSync} from 'node:fs';
import vm from 'node:vm';
import {settingsText,settingsFormat} from './SettingsLocaleData.ts';
const source=readFileSync(process.argv[2]+'/entry/src/main/ets/ui/SettingsLocaleData.ets','utf8');const dictionary=JSON.parse(source.slice(source.indexOf('{'),source.indexOf('\n}\n')+2));
test('dictionary entries preserve Chinese text and translate English with matching placeholders',()=>{
 assert.ok(Object.keys(dictionary).length>=1880);
 for(const [zh,en] of Object.entries(dictionary)){
  assert.ok(en.length>0,zh);assert.equal(settingsText(zh,'zh-CN'),zh);assert.equal(settingsText(zh,'en-US'),en);
  assert.ok(!/[\u4e00-\u9fff]/.test(en)||zh==='中文',zh+' => '+en);
  const slots=s=>[...s.matchAll(/\{(\d+)\}/g)].map(m=>m[1]).sort();assert.deepEqual(slots(en),slots(zh),zh);
 }
});
test('formatting preserves caller values without translating user content and works in both languages',()=>{
 assert.equal(settingsFormat('第 {0} 轮',[7],'en'),'Turn 7');assert.equal(settingsFormat('第 {0} 轮',[7],'zh'),'第 7 轮');
 assert.equal(settingsFormat('移除「{0}」？',['我的项目$&{0}'],'en'),'Remove “我的项目$&{0}”?');
 assert.equal(settingsText('Custom user message','en'),'Custom user message');
});
test('known dynamic errors from pure helpers are translated at presentation without losing captured values',()=>{
 assert.equal(settingsText('插件操作失败（OFFLINE）','en'),'Plugin action failed (OFFLINE)');assert.equal(settingsText('第 8 轮','en'),'Turn 8');
 assert.equal(settingsText('9 条热词规则','en'),'9 hotword rules');assert.equal(settingsText('unknown 3 ms','en'),'unknown 3 ms');
});

function etsFiles(root) { return readdirSync(root,{withFileTypes:true}).flatMap(entry=>entry.isDirectory()?etsFiles(root+'/'+entry.name):entry.name.endsWith('.ets')?[root+'/'+entry.name]:[]); }
test('literal localized UI calls across every shipped ArkTS module have English entries',()=>{
 const missing=[];
 for(const file of etsFiles(process.argv[2]+'/entry/src/main/ets')) {
  if(file.includes('SettingsLocale'))continue;
  const text=readFileSync(file,'utf8');
  for(const match of text.matchAll(/\b(?:this\.)?t\(((?:'(?:\\.|[^'\\])*')|(?:"(?:\\.|[^"\\])*"))\)/g)) {
   const value=vm.runInNewContext(match[1]);
   if(/[\u4e00-\u9fff]/.test(value)&&dictionary[value]===undefined)missing.push(file.split('/ets/')[1]+': '+value);
  }
 }
 assert.deepEqual([...new Set(missing)],[]);
});
