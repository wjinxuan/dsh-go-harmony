import assert from 'node:assert/strict';
import test from 'node:test';
import { advancedPreferences,wallpaperFrame } from './ui/AdvancedPreferencesData.ts';
import { customAccentColors,contrastRatio } from './ui/CustomAccent.ts';
import { notificationPreferences,notificationAllowed,requestNotification,turnNotification,NotificationDeduper } from './ui/NotificationData.ts';
const light={background:'#F0F4FD',backgroundTop:'#EBF1FE',backgroundBottom:'#F6F7FC',surface:'#FBFCFF',surfaceAlt:'#EEF1F9',text:'#1E232E',muted:'#4F5562',hint:'#646974',border:'#DCE0E8',codeSurface:'#EDF0F6',codeHeader:'#E7EBF3',codeBorder:'#DBDEE5',primary:'#4B67B4',onPrimary:'#FFFFFF',primaryContainer:'#DEE8FF',onPrimaryContainer:'#213262',bubble:'#D9E4FD',success:'#337250',warning:'#936123',danger:'#A54743'};
const dark={...light,background:'#1C1F28',backgroundTop:'#1D222C',backgroundBottom:'#1B1C23',surface:'#232730',surfaceAlt:'#272C36',text:'#E6E9F0',muted:'#B6BBC5',hint:'#9A9EA9',border:'#343841'};
test('custom OKLCH derivation retains contrast for saturated, near-white and dark colors',()=>{
 for(const color of ['#000000','#FFFFFF','#FF0000','#00FF00','#0000FF','#5F7A55','#FFD700'])for(const isDark of [false,true]){
  const actual=customAccentColors(isDark?dark:light,color,isDark);assert.ok(contrastRatio(actual.onPrimary,actual.primary)>=4.5,`${color} ${isDark}`);assert.ok(contrastRatio(actual.text,actual.surface)>=10);assert.equal(actual.danger,(isDark?dark:light).danger);
 }
});
test('advanced preference defaults and clamps preserve disabled choices and independent light/dark wallpaper tone',()=>{
 const value=advancedPreferences({customColor:'#bad',foldCompletedTurns:false,panelOpen:false,language:'en',wallpaper:{path:'private.png',on:false,zoom:99,alignX:-4,blur:4,lighten:.2,dim:.9}});
 assert.equal(value.customColor,'#5F7A55');assert.equal(value.foldCompletedTurns,false);assert.equal(value.wallpaper.zoom,5);assert.equal(value.wallpaper.alignX,-1);assert.equal(value.wallpaper.blur,1);assert.equal(value.wallpaper.path,'private.png');assert.equal(value.wallpaper.on,false);assert.equal(value.wallpaper.dim,.9);
});
test('wallpaper crop covers viewport and anchors remain correct across aspect ratios',()=>{
 const paper=advancedPreferences().wallpaper;paper.width=1000;paper.height=500;paper.zoom=2;paper.alignX=1;paper.alignY=-1;
 const frame=wallpaperFrame(paper,300,600);assert.deepEqual(frame,{width:2400,height:1200,x:-2100,y:-0});assert.ok(frame.x+frame.width>=300);assert.ok(frame.y+frame.height>=600);
 assert.deepEqual(wallpaperFrame(paper,0,600),{width:0,height:0,x:0,y:0});
});
test('notification waterfalls and nested session records map to types without conversation contents',()=>{
 const alert=requestNotification({type:'waterfall',event:'approval/request',eventId:'e',request:{sessionId:'s',reason:'secret command'}});assert.deepEqual(alert,{kind:'approval',sessionId:'s',key:'e',text:'有操作等待确认'});
 assert.equal(requestNotification({type:'cancel',eventId:'e'}),undefined);
 for(const [reason,kind] of [['completed','done'],['max-tokens','done'],['aborted','stopped'],['error','failed']])assert.equal(turnNotification('s',{records:[{type:'event',event:{seq:7,type:'turn/end',data:{reason:{kind:reason,error:{message:'secret'}}}}}]}).kind,kind);
 assert.equal(turnNotification('s',{records:[{type:'event',event:{seq:1,type:'turn/start'}}]}),undefined);
});
test('notification switches and dedup are scoped by host, session and event',()=>{
 const prefs=notificationPreferences({failed:false});assert.equal(notificationAllowed(prefs,'stopped'),false);assert.equal(notificationAllowed(prefs,'question'),true);prefs.enabled=false;assert.equal(notificationAllowed(prefs,'done'),false);
 const dedup=new NotificationDeduper(),item={kind:'done',sessionId:'s',key:'7',text:'done'};assert.equal(dedup.claim('local',item),true);assert.equal(dedup.claim('local',item),false);assert.equal(dedup.claim('remote',item),true);
});
