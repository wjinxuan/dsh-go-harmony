// Test-only Web/client companion to the isolated native UI fixture. No npm install,
// user host, model calls or external network. Cleanup must precede the native fixture cleanup.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir,realpath,unlink,copyFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {dirname,join,resolve} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';
import {loadDshClient} from './dsh-client-node-fixture.mjs';
process.umask(0o077);
const [binArg,metaArg,nativeArg,outArg,flag]=process.argv.slice(2);
assert.ok(binArg&&metaArg&&nativeArg&&outArg&&(!flag||flag==='--cleanup'),'node tests/native-plugin-seat-device-fixture.mjs <official-bin> <owned-meta> <native-fixture-dir> <new-out-dir> [--cleanup]');
const bin=await realpath(binArg),metaPath=await realpath(metaArg),native=await realpath(nativeArg);await mkdir(outArg,{recursive:true});const out=await realpath(outArg),root=fileURLToPath(new URL('../',import.meta.url));
const meta=JSON.parse(await readFile(metaPath,'utf8')),mount=JSON.parse(await readFile(join(native,'mount.json'),'utf8'));
assert.equal(meta.host,'127.0.0.1');assert.equal(meta.state,'running');assert.equal(meta.dshPid,mount.pid);assert.equal(metaPath,mount.metaPath);
const pkg='dsh-harmony-device-native-fixture',cell='synthetic-seat-1118',label='合成网页席位',plugin=join(native,'plugin'),manifest=join(plugin,'package.json'),clientFile=join(plugin,'client.js'),patch=mount.patchPath;
const hash=v=>createHash('sha256').update(v).digest('hex');
const {withFileLock,writeFileAtomic}=await import(pathToFileURL(join(dirname(bin),'../../dsh-atomic-write/lib/index.js')));
async function cas(path,before,after){await withFileLock(join(dirname(path),'package.json'),async()=>{assert.equal(await readFile(path,'utf8'),before,'CAS refused: '+path);await writeFileAtomic(path,after,{mode:0o600});});}
async function wait(check,message){for(let i=0;i<300;i++){if(await check())return;await delay(50);}throw Error(message);}
const modules=join(out,'client');await mkdir(modules,{recursive:true});const Client=await loadDshClient(join(root,'entry/src/main/ets/dsh/DshClient.ets'),bin,modules),client=new Client();let browser,state,applied=false;
try{
 await client.connect((await readFile(meta.urlFile,'utf8')).trim());
 if(flag==='--cleanup'){
  state=JSON.parse(await readFile(join(out,'mount.json'),'utf8'));assert.equal(state.pid,meta.dshPid);assert.equal(state.metaPath,metaPath);
  const current=await readFile(patch,'utf8');assert.equal(current.split(state.blockAfter).length,2);
  await cas(manifest,state.manifestAfter,state.manifestBefore);await cas(patch,current,current.replace(state.blockAfter,state.blockBefore));
  assert.equal(hash(await readFile(clientFile)),state.clientSha256);await unlink(clientFile);
  await wait(async()=>!(await client.webBootPage()).includes('"id":"'+pkg+'"'),'Web client did not retire');
  await writeFile(join(out,'cleanup.json'),JSON.stringify({success:true,pid:meta.dshPid,manifestRestored:true,nativeBlockRestored:true,time:new Date().toISOString()},null,2));
  console.log('PASS only the owned seat extension reverted; original native fixture remains.');
 }else{
  assert.ok(process.env.DSH_RENDER_PLAYWRIGHT,'Set DSH_RENDER_PLAYWRIGHT to an existing local Playwright module');
  assert.equal(await readFile(join(out,'mount.json')).then(()=>true,()=>false),false,'Use new output directory');assert.equal(await readFile(clientFile).then(()=>true,()=>false),false);
  const before=await readFile(manifest,'utf8'),json=JSON.parse(before);assert.equal(json.name,pkg);assert.equal(json.dsh,undefined);assert.equal(json.exports,undefined);
  const originals={};for(const name of ['index.js','views.json','events.jsonl','assets/fixture.png'])originals[name]=hash(await readFile(join(plugin,name)));
  await copyFile(manifest,join(out,'package-before.json'));await copyFile(join(plugin,'events.jsonl'),join(out,'events-before.jsonl'));await copyFile(join(plugin,'assets/fixture.png'),join(out,'wallpaper-1118.png'));
  const web=`window.__ModuleLoader__.load({id:${JSON.stringify(pkg)},factory(require){const React=require('react'),h=React.createElement;function Seat(){const[count,setCount]=React.useState(0);return h('section',{'data-testid':'synthetic-seat',style:{padding:16,minHeight:280}},h('h1',null,${JSON.stringify(label)}),h('p',null,'独立本地测试，不发送模型请求。'),h('p',{'data-testid':'seat-count'},'合成计数 '+count),h('button',{'data-testid':'seat-add',onClick:()=>setCount(v=>v+1)},'合成加一'),h('button',{'data-testid':'seat-reset',onClick:()=>setCount(0)},'合成重置'));}function Icon(){return h('span',null,'S');}return{name:${JSON.stringify(pkg)},inject:['slots'],apply(ctx){ctx.slots.inject('main',()=>ctx.slots.register({name:'main',key:${JSON.stringify(cell)},label:${JSON.stringify(label)}},Seat));ctx.slots.inject('sidebar.panellist',()=>ctx.slots.register({name:'sidebar.panellist',id:${JSON.stringify(cell)},order:99,label:${JSON.stringify(label)}},Icon));}};}});\n`;
  json.exports={'.':'./index.js','./client':'./client.js','./package.json':'./package.json'};json.dsh={client:{platform:'web',immediately:true,inject:['@deepseek-ai/dsh-client-ui-layout','@deepseek-ai/dsh-client-ui-sidebar']}};
  const after=JSON.stringify(json,null,2)+'\n',beforePatch=await readFile(patch,'utf8');assert.equal(beforePatch.split(mount.block).length,2);
  const suffix='\n# END owned-device-native-ui\n',blockAfter=mount.block.replace(suffix,'\n      config:\n        syntheticSeatRevision: 1'+suffix);assert.notEqual(blockAfter,mount.block);
  state={pid:meta.dshPid,metaPath,manifestBefore:before,manifestAfter:after,blockBefore:mount.block,blockAfter,clientSha256:hash(web),originals,time:new Date().toISOString()};await writeFile(join(out,'mount.json'),JSON.stringify(state,null,2),{flag:'wx'});
  await writeFile(clientFile,web,{flag:'wx'});await cas(manifest,before,after);applied=true;await cas(patch,beforePatch,beforePatch.replace(mount.block,blockAfter));
  await wait(async()=>{const rows=await client.listPlugins();return rows.some(r=>r.entryId==='include:device-native-ui'&&r.fiberPhase==='active')},'Owned row did not become active');
  await wait(async()=>{const html=await client.webBootPage();return html.includes(pkg)&&html.includes('/client.js')},'Official web boot did not include fixture');
  const {chromium}=createRequire(import.meta.url)(process.env.DSH_RENDER_PLAYWRIGHT);browser=await chromium.launch({headless:true,executablePath:process.env.DSH_RENDER_BROWSER||undefined});const page=await browser.newPage({viewport:{width:393,height:852}}),outside=[],errors=[];
  page.on('pageerror',e=>errors.push(e.message));await page.route('**/*',route=>{const url=new URL(route.request().url());if(url.protocol==='data:'||url.hostname==='127.0.0.1'||url.hostname==='localhost')return route.continue();outside.push(url.origin);return route.abort();});
  await page.goto((await readFile(meta.urlFile,'utf8')).trim(),{waitUntil:'domcontentloaded'});await page.waitForFunction(()=>window.__dshGoBridge?.report,{timeout:20000});await page.waitForFunction(pkg=>window.__DSH_BOOT__.entries.some(v=>v.id===pkg),pkg);await page.evaluate(()=>window.__dshGoBridge.report());
  await wait(async()=>{const v=await client.bridgeJson('GET','/dsh-go/v1/inventory');return v?.slots?.main?.some(s=>s.package===pkg&&s.cell===cell)},'Actual browser occupancy did not report the fixture main slot');
  const inventory=await client.bridgeJson('GET','/dsh-go/v1/inventory');assert.equal(inventory.routeGuard,true);
  const script=await readFile(join(root,'entry/src/main/resources/rawfile/islands/island.js'),'utf8'),css=await readFile(join(root,'entry/src/main/resources/rawfile/islands/island.css'),'utf8');
  await page.evaluate(()=>{window.fixtureIslandMessages=[];window.DshGoIsland={postMessage:value=>window.fixtureIslandMessages.push(JSON.parse(value))};});await page.addScriptTag({content:script});await page.evaluate(({css,label,cell})=>window.__dshGoIsland.init({mode:'page',slot:'main',cell,stretch:'child',pad:[16,12],load:1,css,target:{then:{panel:[label]}},labels:{},bootMs:15000,slotMs:15000}),{css,label,cell});
  await page.waitForFunction(()=>window.fixtureIslandMessages.some(v=>v.t==='ready'),{timeout:20000});await page.getByTestId('synthetic-seat').waitFor({state:'visible'});assert.equal(await page.getByTestId('seat-count').innerText(),'合成计数 0');await page.getByTestId('seat-add').click();assert.equal(await page.getByTestId('seat-count').innerText(),'合成计数 1');await page.getByTestId('seat-reset').click();assert.equal(await page.getByTestId('seat-count').innerText(),'合成计数 0');await page.screenshot({path:join(out,'actual-web-island.png')});
  const slots=inventory.slots.main.filter(v=>v.package===pkg),messages=await page.evaluate(()=>window.fixtureIslandMessages);assert.equal(outside.length,0,'Browser tried external network');assert.deepEqual(errors,[]);
  for(const[name,sha]of Object.entries(originals))assert.equal(hash(await readFile(join(plugin,name))),sha,'Original native fixture changed: '+name);
  const sessions=await client.listSessions();process.kill(meta.dshPid,0);await writeFile(join(out,'verification.json'),JSON.stringify({success:true,officialClientModules:true,actualBrowserOccupancy:true,actualOriginalIsland:true,port:meta.port,pid:meta.dshPid,pkg,cell,label,slots,messages,counter:[0,1,0],nativeUnchanged:originals,webSha256:hash(web),manifestSha256:hash(after),wallpaperSha256:hash(await readFile(join(out,'wallpaper-1118.png'))),modelRequestsByThisFixture:0,sessionIds:sessions.map(v=>v.id),externalRequests:outside,time:new Date().toISOString()},null,2));console.log('PASS genuine official Web/client load + attributed main seat + original island + counter 0/1/0; native files/events unchanged.');
 }
}catch(error){
 if(applied&&state){try{const current=await readFile(patch,'utf8');assert.equal(current.split(state.blockAfter).length,2);await cas(manifest,state.manifestAfter,state.manifestBefore);await cas(patch,current,current.replace(state.blockAfter,state.blockBefore));if(hash(await readFile(clientFile))===state.clientSha256)await unlink(clientFile);await writeFile(join(out,'rollback.json'),JSON.stringify({restored:true,time:new Date().toISOString()}));}catch(rollback){await writeFile(join(out,'rollback.json'),JSON.stringify({restored:false,error:String(rollback)}));}}
 throw error;
}finally{await browser?.close();client.close();}
