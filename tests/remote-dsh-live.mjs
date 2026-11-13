import assert from 'node:assert/strict';
import { execFile, spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { once } from 'node:events';
import { mkdir, mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { loadDshClient } from './dsh-client-node-fixture.mjs';

const [bin, flag, hdc] = process.argv.slice(2);
assert.ok(bin && (!flag || (flag === '--phone' && hdc)),
  'Usage: node tests/remote-dsh-live.mjs /path/to/official/dsh/lib/bin.js [--phone /path/to/hdc]');
const dshBin = resolve(bin);
const clientPath = fileURLToPath(new URL('../entry/src/main/ets/dsh/DshClient.ets', import.meta.url));
const run = promisify(execFile);
const version = '0.2.2-rc.1';
const model = 'deepseek-flash';
const providerKey = 'synthetic-remote-fixture';
const payload = 'file created by the Mac DSH fixture';
const shellOutput = 'mac-shell-fixture';
const jobOutput = 'mac-job-fixture';
const cases = {
  'fixture-write': ['write', { file_path: 'fixture.txt', content: payload }],
  'fixture-read': ['read', { file_path: 'fixture.txt' }],
  'fixture-missing': ['read', { file_path: 'missing-fixture.txt' }],
  'fixture-bash': ['bash', {
    command: "printf mac-shell-fixture > shell-proof.txt && printf mac-shell-fixture",
    description: 'Write and print a shell proof'
  }],
  'fixture-job': ['bash', {
    command: "sleep 1; printf mac-job-fixture > job-proof.txt && printf mac-job-fixture",
    description: 'Run a background proof command',
    run_in_background: true
  }],
  'fixture-approval': ['bash', {
    command: 'printf mac-approval-fixture > approval-proof.txt',
    description: 'Request approval for a harmless command',
    sandbox_permissions: 'danger-full-access',
    justification: 'Check that the phone can review and reject this fixture command.'
  }]
};
const answer = prompt => `Remote fixture finished: ${prompt}`;
const stop = new AbortController();
const stopSoon = () => stop.abort();
process.once('SIGINT', stopSoon);
process.once('SIGTERM', stopSoon);
process.umask(0o077);
const root = await realpath(await mkdtemp(join(tmpdir(), 'dsh-mac-remote-')));
const workspace = join(root, 'workspace');
let child;
let client;
let reverse;
let providerError;
let startupDependencyMissing = false;

function sendModelResponse(response, id, prompt, tool) {
  const content = tool ? [
    { type: 'content_block_start', content_block: { type: 'tool_use', id: `call-${id}`, name: tool[0], input: {} } },
    { type: 'content_block_delta', delta: { type: 'input_json_delta', partial_json: JSON.stringify(tool[1]) } }
  ] : [
    { type: 'content_block_start', content_block: { type: 'text', text: '' } },
    { type: 'content_block_delta', delta: { type: 'text_delta', text: answer(prompt) } }
  ];
  response.writeHead(200, { 'Content-Type': 'text/event-stream' });
  for (const event of [
    { type: 'message_start', message: { id, type: 'message', role: 'assistant', model,
      content: [], usage: { input_tokens: 1, output_tokens: 0 } } },
    ...content.map(block => ({ ...block, index: 0 })),
    { type: 'content_block_stop', index: 0 },
    { type: 'message_delta', delta: { stop_reason: tool ? 'tool_use' : 'end_turn' }, usage: { output_tokens: 1 } },
    { type: 'message_stop' }
  ]) response.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
  response.end();
}

const provider = createServer(async (request, response) => {
  try {
    assert.equal(request.headers['x-api-key'] === providerKey, true, 'Unexpected fixture provider authentication');
    if (request.method === 'GET' && /\/models$/.test(request.url)) {
      response.writeHead(200, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ data: [{ id: model, name: 'Synthetic remote fixture' }] }));
      return;
    }
    assert.equal(request.method, 'POST');
    let body = '';
    for await (const chunk of request) body += chunk;
    const payload = JSON.parse(body);
    assert.equal(payload.model, model);
    const lastUserIndex = payload.messages.findLastIndex(message => message.role === 'user' &&
      (typeof message.content === 'string' ||
        Array.isArray(message.content) && message.content.some(part => part.type === 'text')));
    const lastUser = payload.messages[lastUserIndex];
    const prompt = (typeof lastUser?.content === 'string' ? lastUser.content :
      lastUser?.content.find(part => part.type === 'text')?.text)?.trim() ?? '';
    const continued = payload.messages.slice(lastUserIndex + 1).some(message => message.role === 'tool' ||
      Array.isArray(message.content) && message.content.some(part => part.type === 'tool_result'));
    const tool = continued || !Object.hasOwn(cases, prompt) ? undefined : cases[prompt];
    if (tool) assert.ok(payload.tools?.some(entry => entry.name === tool[0]), `Model has no ${tool[0]} tool`);
    sendModelResponse(response, randomUUID(), prompt, tool);
  } catch (error) {
    providerError = error.message;
    response.writeHead(500).end();
  }
});

async function until(predicate, message, attempts = 200) {
  for (let n = 0; n < attempts; n++) {
    stop.signal.throwIfAborted();
    if (providerError) throw new Error(providerError);
    const value = await predicate();
    if (value) return value;
    await delay(50, undefined, { signal: stop.signal });
  }
  throw new Error(message);
}

async function stopChild() {
  if (!child || child.exitCode !== null || child.signalCode !== null || !child.pid) return;
  const ended = once(child, 'exit');
  child.kill('SIGTERM');
  if (await Promise.race([ended.then(() => true), delay(2500, false, { ref: false })])) return;
  child.kill('SIGKILL');
  await ended;
}

try {
  const home = join(root, 'home');
  await mkdir(home);
  await mkdir(workspace);
  const env = {
    PATH: `${dirname(process.execPath)}:/usr/bin:/bin:/usr/sbin:/sbin`,
    HOME: home,
    DSH_HOME: join(root, 'dsh'),
    XDG_CONFIG_HOME: join(home, 'config'),
    XDG_CACHE_HOME: join(home, 'cache'),
    XDG_DATA_HOME: join(home, 'data'),
    TMPDIR: root,
    NO_COLOR: '1'
  };
  const cli = await run(process.execPath, [dshBin, '--version'], { env, cwd: workspace, timeout: 15000 });
  assert.equal(cli.stdout.trim(), version);
  provider.listen(0, '127.0.0.1');
  await once(provider, 'listening');
  const baseURL = `http://127.0.0.1:${provider.address().port}/v1`;
  child = spawn(process.execPath, [dshBin, 'web', '--host', '127.0.0.1', '--port', '0', '--no-open'], {
    env: { ...env, DEEPSEEK_API_KEY: providerKey, DEEPSEEK_BASE_URL: baseURL },
    cwd: workspace,
    stdio: ['ignore', 'pipe', 'pipe']
  });
  let launchUrl;
  let line = '';
  child.stdout.on('data', bytes => {
    line += bytes.toString();
    const lines = line.split('\n');
    line = lines.pop();
    for (const text of lines) {
      const match = text.match(/^dsh web: (http:\/\/127\.0\.0\.1:\d+\/\?token=\S+)\s*$/);
      if (match) launchUrl = match[1];
    }
  });
  child.stderr.on('data', bytes => {
    if (bytes.includes('No usable native binding found')) startupDependencyMissing = true;
  });
  await until(() => {
    if (child.exitCode !== null) {
      const reason = startupDependencyMissing ? ' Check that the official Mac native dependencies are installed.' : '';
      throw new Error(`Official DSH exited before ready (${child.exitCode}).${reason}`);
    }
    return launchUrl;
  }, 'Official DSH did not publish a loopback URL', 400);

  const deviceInfo = { sdkApiVersion: 26 };
  const DshClient = await loadDshClient(clientPath, dshBin, root, { deviceInfo });
  client = new DshClient();
  const wrong = new URL(launchUrl);
  wrong.searchParams.set('token', 'intentionally-invalid-fixture-token');
  await assert.rejects(client.connect(wrong.href), /登录失败|令牌无效/);
  if (!hdc) {
    deviceInfo.sdkApiVersion = 25;
    await assert.rejects(client.connect(launchUrl), /WebSocket/);
    deviceInfo.sdkApiVersion = 26;
  }
  await client.connect(launchUrl);
  await client.mutateSettings('llm-deepseek', [{ op: 'set', path: ['baseURL'], value: baseURL }]);
  const remoteWorkspace = await client.createWorkspace(workspace);
  assert.equal(remoteWorkspace.path, workspace);

  if (hdc) {
    const port = new URL(launchUrl).port;
    const target = await run(hdc, ['list', 'targets', '-v'], { timeout: 5000 });
    const connected = target.stdout.split('\n').filter(line => /\bConnected\b/.test(line));
    assert.equal(connected.length, 1, 'One HDC device is required');
    assert.ok(/\bUSB\b/i.test(connected[0]), 'USB connection required');
    const forwarded = await run(hdc, ['rport', `tcp:${port}`, `tcp:${port}`], { timeout: 5000 });
    assert.match(forwarded.stdout, /Forwardport result:OK/i);
    reverse = [`tcp:${port}`, `tcp:${port}`];
    const secretPath = join(root, 'launch-url');
    await writeFile(secretPath, launchUrl + '\n', { mode: 0o600, flag: 'wx' });
    await writeFile(join(workspace, 'phone-fixture.txt'), 'This file resides in the isolated Mac workspace.\n');
    console.log(`Phone fixture ready. Private launch URL file: ${secretPath}`);
    console.log(`Mac workspace: ${workspace}`);
    try {
      await delay(30 * 60 * 1000, undefined, { signal: stop.signal });
    } catch (error) {
      if (!stop.signal.aborted) throw error;
    }
    for (const file of ['fixture.txt', 'shell-proof.txt', 'job-proof.txt']) {
      const found = await readFile(join(workspace, file), 'utf8').catch(() => '');
      console.log(`${file}: ${found ? 'present' : 'absent'}`);
    }
  } else {
    const defaultSession = await client.createSession();
    assert.equal((await client.listSessions()).find(item => item.id === defaultSession)?.cwd, workspace,
      'A session without an explicit workspace must use the isolated Mac workspace');
    const session = await client.createSession(remoteWorkspace.id);
    let chat;
    let jobs = [];
    let jobError;
    await client.watchSession(session, update => { chat = update; });
    await client.watchJobs(session, items => { jobs = items; }, error => { jobError = error; });
    const modelInfo = (await client.listModels()).groups.find(group => group.id === 'deepseek-official')?.models
      .find(entry => entry.id === model);
    assert.ok(modelInfo, 'Synthetic provider model was not listed');
    await client.setModel(session, modelInfo.provider, modelInfo.id);
    const completed = prompt => until(() => !chat?.running && chat?.messages.some(message =>
      message.role === 'assistant' && message.text === answer(prompt)), `No completed turn for ${prompt}`);
    const prompt = async name => {
      await client.prompt(session, name);
      await completed(name);
    };

    await prompt('fixture-write');
    assert.equal(await readFile(join(workspace, 'fixture.txt'), 'utf8'), payload);
    await prompt('fixture-read');
    assert.equal((await client.readWorkspaceText(session, 'fixture.txt')).text, payload);
    assert.ok(JSON.stringify(chat.tools).includes(payload), 'The model read did not return the fixture contents');
    await prompt('fixture-missing');
    assert.ok(chat.tools.some(tool => tool.name === 'read' && tool.isError), 'The missing file did not report a read error');
    await prompt('fixture-bash');
    assert.equal(await readFile(join(workspace, 'shell-proof.txt'), 'utf8'), shellOutput);
    assert.ok(chat.tools.some(tool => tool.name === 'bash' && tool.result?.includes(shellOutput) && !tool.isError));

    await prompt('fixture-job');
    const job = await until(() => jobs.find(item => item.id), 'No background job was listed');
    assert.equal(job.owner, session);
    const frames = [];
    await client.followJob(session, job.id, frame => frames.push(frame), error => { jobError = error; });
    await until(() => frames.some(frame => frame.type === 'status'), 'No terminal job status arrived');
    assert.equal(jobError, undefined);
    assert.equal(frames.find(frame => frame.type === 'status').job.status, 'completed');
    const stdout = frames.filter(frame => frame.type === 'output')
      .flatMap(frame => frame.chunks.filter(chunk => chunk.channel === 'stdout').map(chunk => chunk.text)).join('');
    assert.equal(stdout, jobOutput);
    assert.equal(await readFile(join(workspace, 'job-proof.txt'), 'utf8'), jobOutput);

    await client.prompt(session, 'fixture-approval');
    const approval = await until(() => chat?.approval, 'No approval request arrived');
    assert.match(approval.title, /approval-proof\.txt/);
    assert.equal(approval.canAllow, true);
    await client.approve(approval.id, false);
    await completed('fixture-approval');
    await assert.rejects(readFile(join(workspace, 'approval-proof.txt')), { code: 'ENOENT' });
    console.log('PASS: official Mac DSH authentication, file write/read/error, shell, background job and rejected approval');
  }
} finally {
  client?.close();
  try {
    if (reverse) {
      const result = await run(hdc, ['fport', 'rm', ...reverse], { timeout: 5000 });
      assert.match(result.stdout, /Remove forward ruler success/i);
    }
  } finally {
    try {
      await stopChild();
    } finally {
      provider.closeAllConnections();
      if (provider.listening) await new Promise(done => provider.close(done));
      await rm(root, { recursive: true, force: true });
    }
  }
}
