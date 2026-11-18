// A temporary, loopback-only SYNTHETIC provider + packaged DSH host for native UI QA.
// Only the extracted copy's media transport is replaced. Never points at paid providers.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { once } from 'node:events';
import { appendFile, chmod, copyFile, mkdir, mkdtemp, readFile, realpath, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { deflateSync } from 'node:zlib';
import { loadDshClient } from './dsh-client-node-fixture.mjs';
import { loadMediaModules } from './media-loader.mjs';
import './require-runtime-node.mjs';
import { unlockTestCredentials } from './unlock-test-credentials.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const archive = resolve(process.argv[2] || join(root, 'entry/src/main/resources/rawfile/dsh-runtime.zip'));
const dir = await realpath(await mkdtemp(join(tmpdir(), 'dsh-media-phone-')));
await chmod(dir, 0o700);
const runtime = join(dir, 'runtime'), home = join(dir, 'home');
await mkdir(home, { mode: 0o700 });
const unpack = spawnSync('/usr/bin/unzip', ['-q', archive, '-d', runtime], { encoding: 'utf8' });
assert.equal(unpack.status, 0, unpack.stderr);
const eventsPath = join(dir, 'events.jsonl');
const record = async (type, detail = {}) => appendFile(eventsPath, JSON.stringify({ at: new Date().toISOString(), type, ...detail }) + '\n', { mode: 0o600 });
// A real 320 x 180 PNG with deterministic colored panels, not a sprite atlas.
function crc32(bytes) {
  let value = 0xffffffff;
  for (const byte of bytes) { value ^= byte; for (let bit = 0; bit < 8; bit++) value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0); }
  return (value ^ 0xffffffff) >>> 0;
}
function chunk(type, bytes) {
  const name = Buffer.from(type), size = Buffer.alloc(4), crc = Buffer.alloc(4);
  size.writeUInt32BE(bytes.length); crc.writeUInt32BE(crc32(Buffer.concat([name, bytes])));
  return Buffer.concat([size, name, bytes, crc]);
}
function picture() {
  const w = 320, h = 180, header = Buffer.alloc(13), pixels = Buffer.alloc((w * 3 + 1) * h);
  header.writeUInt32BE(w); header.writeUInt32BE(h, 4); header[8] = 8; header[9] = 2;
  const colors = [[25, 120, 210], [240, 160, 25], [25, 170, 120], [200, 55, 95]];
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const color = colors[(x >= w / 2 ? 1 : 0) + (y >= h / 2 ? 2 : 0)];
    const offset = y * (w * 3 + 1) + 1 + x * 3;
    for (let c = 0; c < 3; c++) pixels[offset + c] = x < 6 || y < 6 || x >= w - 6 || y >= h - 6 ? 255 : color[c];
  }
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', deflateSync(pixels)), chunk('IEND', Buffer.alloc(0))]);
}
const png = picture(), video = await readFile(join(root, 'tests/fixtures/synthetic-media.mp4'));
await writeFile(join(dir, 'synthetic.png'), png, { mode: 0o600 });
await writeFile(join(dir, 'synthetic.mp4'), video, { mode: 0o600 });
const { parseGenerationMessage } = await import(pathToFileURL(join(runtime, 'vendor/dsh-media/src/header.js')));
const DshClient = await loadDshClient(join(root, 'entry/src/main/ets/dsh/DshClient.ets'), join(runtime, 'main.cjs'), dir);
const { readMediaFile, mediaMeta } = await loadMediaModules();
const mediaKey = 'synthetic-media-phone-only', modelKey = 'synthetic-model-phone-only';
let providerOrigin = '', sequence = 0;
const jobs = new Map();
const pendingImages = new Set();
const json = (res, value, status = 200) => { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(value)); };
const textOf = content => typeof content === 'string' ? content : (content || []).filter(c => c.type === 'text').map(c => c.text).join('\n');
const cancelled = text => /cancel|取消/i.test(text);
const server = createServer(async (req, res) => {
  try {
    if (req.url === '/synthetic.mp4') {
      assert.equal(req.headers.authorization, undefined, 'video download does not carry provider credentials');
      assert.equal(req.headers.cookie, undefined);
      await record('video_download', { bytes: video.length });
      res.writeHead(200, { 'content-type': 'video/mp4', 'content-length': video.length }); res.end(video); return;
    }
    const isProvider = req.url.startsWith('/provider/');
    const authorized = isProvider ? req.headers.authorization === 'Bearer ' + mediaKey :
      req.headers.authorization === 'Bearer ' + modelKey || req.headers['x-api-key'] === modelKey;
    if (!authorized) { await record('credential_rejected', { path: req.url }); json(res, { error: 'synthetic credential required' }, 401); return; }
    let raw = '';
    for await (const bytes of req) { raw += bytes; if (raw.length > 4 * 1024 * 1024) throw Error('fixture request too large'); }
    const body = raw ? JSON.parse(raw) : {};
    if (req.url === '/provider/images/generations' || req.url === '/provider/images/edits') {
      const id = ++sequence, shouldCancel = cancelled(body.prompt);
      await record('image_started', { id, cancel: shouldCancel, count: body.n || 1 });
      let timer;
      const pending = { res, id }; pendingImages.add(pending);
      res.on('close', () => { clearTimeout(timer); pendingImages.delete(pending); if (!res.writableFinished) void record('image_aborted', { id }); });
      if (!shouldCancel) timer = setTimeout(() => { json(res, { data: Array.from({ length: body.n || 1 }, () => ({ b64_json: png.toString('base64') })) }); void record('image_completed', { id }); }, 2000);
      return;
    }
    if (req.url === '/provider/tasks' && req.method === 'POST') {
      const id = 'synthetic-video-' + ++sequence, prompt = textOf(body.content);
      jobs.set(id, { at: Date.now(), cancel: cancelled(prompt), deleted: false });
      await record('video_started', { id, cancel: cancelled(prompt) }); json(res, { id }); return;
    }
    if (req.url.startsWith('/provider/tasks/')) {
      const id = decodeURIComponent(req.url.slice('/provider/tasks/'.length)), job = jobs.get(id);
      if (!job) { json(res, { error: 'missing synthetic job' }, 404); return; }
      if (req.method === 'DELETE') { job.deleted = true; await record('video_cancelled', { id }); json(res, {}); return; }
      const status = job.deleted ? 'cancelled' : job.cancel || Date.now() - job.at < 6000 ? 'queued' : 'succeeded';
      json(res, { id, status, ...(status === 'succeeded' ? { content: { video_url: providerOrigin + '/synthetic.mp4' } } : {}) }); return;
    }
    if (req.url === '/v1/models') { json(res, { data: [{ id: 'deepseek-flash' }] }); return; }
    if (req.url !== '/v1/messages') { json(res, { error: 'unknown synthetic route' }, 404); return; }
    await writeFile(join(dir, 'last-model-request.private.json'), JSON.stringify(body), { mode: 0o600 });
    const messages = body.messages || [], user = messages.findLast(m => m.role === 'user' && /^(?:〔生成(?:图像|视频)|Synthetic\b|cancel\b|合成)/i.test(textOf(m.content)));
    const prompt = textOf(user?.content), parsed = parseGenerationMessage(prompt);
    const kind = parsed?.kind || (/video|视频/i.test(prompt) ? 'video' : 'image');
    const turn = messages.slice(messages.lastIndexOf(user));
    const last = turn.findLast(m => Array.isArray(m.content) && m.content.some(c => c.type === 'tool_result'));
    const toolResult = !!last;
    const currentTurn = JSON.stringify(turn);
    const job = /视频已进入后台任务 ([^；\s]+)/.exec(currentTurn)?.[1];
    const lastResult = JSON.stringify(last);
    const videoNext = kind === 'video' && toolResult && job && !/AI 生成视频已保存|cancelled|已取消|失败/.test(lastResult);
    if (videoNext) await delay(1000);
    const events = [{ type: 'message_start', message: { id: 'synthetic-message-' + ++sequence, type: 'message', role: 'assistant', model: 'deepseek-flash', content: [], usage: { input_tokens: 1, output_tokens: 0 } } }];
    if (!user || (toolResult && !videoNext)) {
      events.push({ type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } },
        { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: '【合成测试服务】工具已返回。结果文件来自本地测试素材，未调用商业模型或付费媒体服务。' } },
        { type: 'content_block_stop', index: 0 }, { type: 'message_delta', delta: { stop_reason: 'end_turn' }, usage: { output_tokens: 1 } });
    } else {
      const input = videoNext ? { job_id: job } : { prompt: parsed?.prompt || prompt, serviceId: parsed?.model?.serviceId || (kind === 'video' ? 'video_fixture' : 'fixture'),
        modelId: parsed?.model?.id || (kind === 'video' ? 'doubao-seedance-2-5-260628' : 'gpt-image-2.5-flare'), aspect: parsed?.aspect || '1:1',
        ...(kind === 'video' ? { seconds: parsed?.seconds || 5, resolution: parsed?.quality || '720p' } : { n: parsed?.n || 1, ...(parsed?.quality ? { quality: parsed.quality } : {}) }) };
      const name = videoNext ? 'get_media_result' : kind === 'video' ? 'generate_video' : 'generate_image';
      await record('model_tool', { name, kind });
      events.push({ type: 'content_block_start', index: 0, content_block: { type: 'tool_use', id: 'synthetic-call-' + ++sequence, name, input: {} } },
        { type: 'content_block_delta', index: 0, delta: { type: 'input_json_delta', partial_json: JSON.stringify(input) } },
        { type: 'content_block_stop', index: 0 }, { type: 'message_delta', delta: { stop_reason: 'tool_use' }, usage: { output_tokens: 1 } });
    }
    events.push({ type: 'message_stop' }); res.writeHead(200, { 'content-type': 'text/event-stream' });
    for (const event of events) res.write('event: ' + event.type + '\ndata: ' + JSON.stringify(event) + '\n\n');
    res.end();
  } catch (error) { await record('fixture_error', { message: error.message }); if (!res.headersSent) json(res, { error: error.message }, 500); else res.destroy(); }
});
await new Promise(ok => server.listen(0, '127.0.0.1', ok));
providerOrigin = 'http://127.0.0.1:' + server.address().port;
const vendor = join(runtime, 'vendor/dsh-media/src/index.js');
await copyFile(vendor, join(runtime, 'vendor/dsh-media/src/index-production.js'));
await writeFile(vendor, `// SYNTHETIC PHONE FIXTURE ONLY: this file is in an isolated /tmp extraction.\nimport{Config,name,inject,installMedia}from'./index-production.js';import{createHttpTransport}from'./http.js';import{createStreamStager}from'./stream-staging.js';export{Config,name,inject};const send=createHttpTransport({allowLoopback:true});export function apply(ctx,config){return installMedia(ctx,config,{engineOptions:{pollMs:500,stageDownload:createStreamStager({allowLoopback:true}),transport:(url,options)=>{let path;if(url.startsWith('https://synthetic.invalid/v1/images/'))path='/provider/'+url.slice('https://synthetic.invalid/v1/'.length);else if(url.startsWith('https://ark.cn-beijing.volces.com/api/v3/contents/generations/tasks'))path='/provider/tasks'+url.slice('https://ark.cn-beijing.volces.com/api/v3/contents/generations/tasks'.length);else throw Error('fixture blocked external target');return send(${JSON.stringify(providerOrigin)}+path,options)}}})}\n`);
const child = spawn(process.execPath, ['--jitless', '--no-addons', '--expose-internals', '--require', join(root, 'tests/local-flock-fixture.cjs'), join(runtime, 'main.cjs'), home], { stdio: ['ignore', 'pipe', 'pipe'] });
const engineLog = join(dir, 'engine.log');
child.stdout.on('data', b => { void appendFile(engineLog, b, { mode: 0o600 }); });
child.stderr.on('data', b => { void appendFile(engineLog, b, { mode: 0o600 }); });
const client = new DshClient();
let cleaned = false;
async function cleanup() {
  if (cleaned) return; cleaned = true; client.close();
  for (const pending of pendingImages) pending.res.destroy();
  server.closeAllConnections(); await new Promise(ok => server.close(ok));
  await writeFile(join(home, 'stop'), '');
  if (child.exitCode === null) { await Promise.race([once(child, 'exit'), delay(5000)]); if (child.exitCode === null) child.kill('SIGKILL'); }
  await record('stopped');
}
process.once('SIGTERM', () => { void cleanup(); }); process.once('SIGINT', () => { void cleanup(); });
try {
  let ready;
  for (let i = 0; i < 300 && !ready; i++) { ready = await readFile(join(home, 'ready.json'), 'utf8').then(JSON.parse, () => undefined); if (child.exitCode !== null) throw Error('fixture engine exited; see private engine.log'); if (!ready) await delay(50); }
  assert.ok(ready, 'fixture host readiness'); await unlockTestCredentials(ready); await client.connect(ready.url, undefined, true);
  await client.setProviderKey(mediaKey, 'DSH_MEDIA_SLOT_1_API_KEY'); await client.setProviderKey(modelKey, 'DEEPSEEK_API_KEY');
  let settings = await client.describeSettings();
  const media = settings.namespaces.find(n => n.ns === 'dsh-media'); assert.ok(media);
  await client.updateSettings(media.ns, { services: [
    { id: 'fixture', label: '合成图像测试 · 不收费', provider: 'Synthetic fixture', profile: 'openai-gpt-image', baseUrl: 'https://synthetic.invalid/v1', keyRef: 'DSH_MEDIA_SLOT_1_API_KEY', models: 'gpt-image-2.5-flare', enabled: true, responseFormat: '' },
    { id: 'video_fixture', label: '合成视频测试 · 不收费', provider: 'Synthetic fixture', profile: 'ark-video', baseUrl: 'https://ark.cn-beijing.volces.com', keyRef: 'DSH_MEDIA_SLOT_1_API_KEY', models: 'doubao-seedance-2-5-260628', enabled: true, responseFormat: '' }
  ], defaults: { imageServiceId: 'fixture', imageModelId: 'gpt-image-2.5-flare', videoServiceId: 'video_fixture', videoModelId: 'doubao-seedance-2-5-260628' }, budget: { dailyCny: '100', unknownPriceHoldCny: '1' } }, media.revision);
  settings = await client.describeSettings(); const llm = settings.namespaces.find(n => n.ns === 'llm-deepseek');
  await client.updateSettings(llm.ns, { baseURL: providerOrigin + '/v1' }, llm.revision);
  const model = (await client.listModels()).groups.flatMap(g => g.models).find(m => m.id === 'deepseek-flash'); assert.ok(model);
  async function session(title) { const id = await client.createSession(undefined, ready.workspaceDir); await client.setModel(id, model.provider, model.id, model.defaultEffort); await client.renameSession(id, title); return id; }
  // Separate self-check session only; the phone session below never auto-approves.
  const check = await session('合成媒体 · 宿主自检'); let update; const approved = new Set();
  await client.watchSession(check, value => { update = value; if (value.approval && !approved.has(value.approval.id)) { approved.add(value.approval.id); void client.approve(value.approval.id, true); } });
  async function waitFor(predicate, label) { for (let i = 0; i < 800; i++) { if (predicate()) return; await delay(50); } throw Error('fixture self-check timeout: ' + label); }
  await delay(300);
  for (const kind of ['image', 'video']) {
    await client.prompt(check, 'Synthetic ' + kind, 'synthetic-self-' + kind); let found;
    await waitFor(() => { found = (update?.tools || []).map(t => mediaMeta(t.meta)).find(m => m?.kind === kind && m.status === 'done' && m.items.length); return found && !update.running; }, kind);
    const bytes = []; await readMediaFile(client, check, found.items[0].path, 32 * 1024 * 1024, async b => bytes.push(Buffer.from(b)), () => true);
    assert.deepEqual(Buffer.concat(bytes), kind === 'image' ? png : video); await record('selfcheck_pass', { kind, bytes: Buffer.concat(bytes).length });
  }
  await client.prompt(check, 'Synthetic image cancel', 'synthetic-self-cancel');
  await waitFor(() => pendingImages.size > 0, 'cancel started'); await client.cancel(check);
  await waitFor(() => pendingImages.size === 0 && !update.running, 'cancel propagated'); await record('selfcheck_pass', { kind: 'cancel' });
  const sessionId = await session('合成媒体手机测试 · 无商业调用');
  const configPath = join(dir, 'phone-config.private.json');
  await writeFile(configPath, JSON.stringify({ synthetic: true, hostUrl: ready.url, hostPort: Number(new URL(ready.url).port), providerPort: server.address().port, sessionId,
    workspaceDir: ready.workspaceDir, model: model.id, mediaKey, modelKey, runtime: archive, pid: process.pid, enginePid: child.pid,
    imageService: 'fixture', videoService: 'video_fixture', cancelPrompt: 'cancel 合成取消测试', eventLog: eventsPath }, null, 2), { mode: 0o600 });
  client.close();
  console.log(JSON.stringify({ status: 'READY_SYNTHETIC_ONLY', hostPort: Number(new URL(ready.url).port), providerPort: server.address().port, configPath, eventLog: eventsPath, selfChecks: ['image bytes', 'video bytes', 'cancel HTTP abort'] }));
  await once(child, 'exit');
} finally { await cleanup(); }
