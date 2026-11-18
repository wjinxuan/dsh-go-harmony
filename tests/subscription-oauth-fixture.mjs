// Test-only replacement of external pi-ai OAuth. Host RPC, authorization registry,
// credential commits, settings, route declaration and restart remain real.
import { registerHooks } from 'node:module';
registerHooks({ load(url, context, nextLoad) {
  const result=nextLoad(url,context);
  if (!url.endsWith('/@deepseek-ai/dsh-llm-pi-ai/lib/index.js')) return result;
  const source=String(result.source), start=source.indexOf('\t\t\tasync run(session) {',source.indexOf('function registerPiAiFlows('));
  const end=source.indexOf('\n\t\t\t}\n\t\t});',start);
  if(start<0||end<0)throw Error('Upstream OAuth fixture boundary changed');
  const fixture=`\t\t\tasync run(session) {
    session.notify({url:'https://fixture.invalid/oauth',code:'TEST-CODE'});
    await new Promise(resolve=>setTimeout(resolve,50));
    const answer=await session.prompt({kind:'text',placeholder:'synthetic-code',signal:session.signal});
    if(answer!=='synthetic-code')throw new Error('authorization failed');
    await session.commit({kind:'grant',payload:{type:'oauth',access:'synthetic-access',refresh:'synthetic-refresh',expires:Date.now()+3600000}});`;
  return {...result,source:source.slice(0,start)+fixture+source.slice(end)};
} });
