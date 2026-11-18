import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
const source = await readFile(new URL('../entry/src/main/ets/dsh/DshClient.ets', import.meta.url), 'utf8');
const method = source.slice(source.indexOf('  async pluginAsset('), source.indexOf('  // A separately subscribed client'));
const Client = vm.runInNewContext(stripTypeScriptTypes(`class Client { ${method} }; Client`), { Uint8Array, ArrayBuffer, Error, encodeURIComponent,
  rcp: { Request: class { constructor(uri, method, headers) { Object.assign(this, {uri, method, headers}); } } } });
function setup({status=200, mime='image/png', chunks=[new Uint8Array([137,80,78,71])], length, beforeEnd}={}) {
  const requests=[]; let cancellations=0;
  const client=new Client(); const proxy={type:'fixture'};
  Object.assign(client,{base:'https://host.example',generation:1,clientId:'ready',headers:{cookie:'private-cookie',authorization:'Bearer private-token'},proxy});
  client.http={cancel(){cancellations++;},async fetch(request){requests.push(request);const events=request.configuration.tracing.httpEventsHandler;
    events.onStatusCodeReceive(status);events.onHeaderReceive({'content-type':mime,'content-length':length});
    for (const bytes of chunks) events.onDataReceive(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength));
    beforeEnd?.(client);return {statusCode:status,headers:{},body:undefined};}};
  return {client,requests,proxy,cancelled:()=>cancellations};
}
test('authenticated asset uses bounded RCP chunks (response body is absent) and inherited proxy',async()=>{
  const {client,requests,proxy}=setup({chunks:[new Uint8Array([137,80]),new Uint8Array([78,71])]});
  assert.deepEqual(await client.pluginAsset('@scope/plugin','nested/image.png'),new Uint8Array([137,80,78,71]));
  assert.equal(requests[0].uri,'https://host.example/dsh-go/v1/assets/%40scope/plugin/nested/image.png');
  assert.equal(requests[0].headers.authorization,'Bearer private-token');assert.equal(requests[0].headers.cookie,'private-cookie');
  assert.equal(requests[0].configuration.proxy,proxy);assert.equal(requests[0].configuration.transfer.autoRedirect,false);
});
test('asset paths, response types, redirects, empty and oversized data fail closed',async()=>{
  const {client,requests}=setup();
  for(const [pkg,path] of [['../p','img.png'],['p','../x.png'],['p','a/../b.png'],['p','x.svg'],['p','https://else/image.png'],['p','%2e%2e/a.png']])await assert.rejects(client.pluginAsset(pkg,path));
  assert.equal(requests.length,0);
  for(const options of [{status:302},{mime:'text/html'},{chunks:[]},{length:'4194305'},{chunks:[new Uint8Array(4194305)]}]){
    const fixture=setup(options);await assert.rejects(fixture.client.pluginAsset('p','x.png'));if(options.chunks?.length!==0)assert.ok(fixture.cancelled()>0);
  }
});
test('asset completion cannot repaint a retired view or changed connection',async()=>{
  let current=true;const stale=setup({beforeEnd(){current=false;}});await assert.rejects(stale.client.pluginAsset('p','x.png',()=>current));
  const swapped=setup({beforeEnd(client){client.generation++;}});await assert.rejects(swapped.client.pluginAsset('p','x.png'));
  const retired=setup();await assert.rejects(retired.client.pluginAsset('p','x.png',()=>false));assert.ok(retired.cancelled());
});
