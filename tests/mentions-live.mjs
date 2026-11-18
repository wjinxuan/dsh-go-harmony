import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { once } from 'node:events'
import { mkdtemp, readFile, mkdir, rm, writeFile } from 'node:fs/promises'
import { createServer } from 'node:http'
import { join, resolve } from 'node:path'
import { setTimeout as delay } from 'node:timers/promises'
import { fileURLToPath } from 'node:url'
import { loadDshClient } from './dsh-client-node-fixture.mjs'
import { decodeSessionReferenceUri, formatFileMention, parseMessageMentions } from './ui/MentionData.ts'

const [clientPath, runtime, lockFixture] = process.argv.slice(2).map(value => resolve(value))
const DshClient = await loadDshClient(clientPath, join(runtime, 'main.cjs'), fileURLToPath(new URL('.', import.meta.url)))
const home = await mkdtemp('/tmp/dsh-mention-live-')
const child = spawn(process.execPath, ['--jitless', '--no-addons', '--expose-internals', '--require', lockFixture,
  join(runtime, 'main.cjs'), home], { stdio: 'ignore' })
const client = new DshClient()
const bodies = []
let requestedRead = false
const provider = createServer(async (request, response) => {
  if (request.url === '/models') { response.end(JSON.stringify({ data: [{ id: 'deepseek-flash' }] })); return }
  let body = ''
  for await (const chunk of request) body += chunk
  bodies.push(JSON.parse(body))
  const readFile = body.includes('Read these:') && !requestedRead
  if (readFile) requestedRead = true
  response.writeHead(200, { 'Content-Type': 'text/event-stream' })
  for (const event of [
    { type: 'message_start', message: { id: 'fixture', type: 'message', role: 'assistant', model: 'deepseek-flash', content: [], usage: { input_tokens: 1, output_tokens: 0 } } },
    ...(readFile ? [
      { type: 'content_block_start', index: 0, content_block: { type: 'tool_use', id: 'read-reference', name: 'read', input: {} } },
      { type: 'content_block_delta', index: 0, delta: { type: 'input_json_delta', partial_json: JSON.stringify({ file_path: 'mention folder/nested proof.txt' }) } }
    ] : [
      { type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } },
      { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: 'mention fixture reply' } }
    ]),
    { type: 'content_block_stop', index: 0 },
    { type: 'message_delta', delta: { stop_reason: readFile ? 'tool_use' : 'end_turn' }, usage: { output_tokens: 1 } }, { type: 'message_stop' }
  ]) response.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`)
  response.end()
})
await new Promise(resolve => provider.listen(0, '127.0.0.1', resolve))
async function until(predicate, description) {
  for (let i = 0; i < 160; i++) { if (await predicate()) return; await delay(50) }
  throw new Error(`Timed out: ${description}`)
}
try {
  let ready
  await until(async () => {
    ready = await readFile(join(home, 'ready.json'), 'utf8').then(JSON.parse, () => undefined)
    if (child.exitCode !== null) throw new Error('engine exited')
    return !!ready
  }, 'ready')
  await client.connect(ready.url, undefined, true)
  await client.watchWorkspaces(() => {})
  await mkdir(join(ready.workspaceDir, 'mention folder'))
  await writeFile(join(ready.workspaceDir, 'mention folder', 'nested proof.txt'), 'UNIQUE_FILE_REFERENCE_PROOF')
  const workspace = await client.createWorkspace(ready.workspaceDir)
  const source = await client.createSession(workspace.id)
  await client.watchSession(source, () => {})
  await client.renameSession(source, 'Referenced proof conversation')
  await client.setProviderKey('synthetic-local-key')
  await client.mutateSettings('llm-deepseek', [{ op: 'set', path: ['baseURL'], value: `http://127.0.0.1:${provider.address().port}/v1` }])
  const catalog = await client.listModels()
  const model = catalog.groups.find(group => group.id === 'deepseek-official').models.find(model => model.id === 'deepseek-flash')
  await client.setModel(source, model.provider, model.id, model.defaultEffort)
  let sourceChat
  await client.watchSession(source, update => { sourceChat = update })
  await client.prompt(source, 'UNIQUE_SESSION_REFERENCE_PROOF')
  await until(() => sourceChat && !sourceChat.running && sourceChat.messages.some(message => message.role === 'assistant'), 'source prompt')
  const target = await client.createSession(workspace.id)
  await client.watchSession(target, () => {})
  await client.setModel(target, model.provider, model.id, model.defaultEffort)
  const files = await client.fileReferences(target, 'mention folder/')
  assert.ok(files.some(item => item.path === 'mention folder/nested proof.txt' && item.kind === 'file'))
  const fuzzyFiles = await client.fileReferences(target, 'nested')
  assert.ok(fuzzyFiles.some(item => item.path === 'mention folder/nested proof.txt'))
  const references = await client.sessionReferences(target, 'Referenced proof')
  const reference = references.find(item => item.sessionId === source)
  assert.ok(reference)
  assert.ok(!references.some(item => item.sessionId === target))
  const token = parseMessageMentions(reference.mention)[0]
  assert.equal(token.kind, 'session')
  assert.equal(decodeSessionReferenceUri(reference.mention.match(/\((dsh-session:[^)]*)\)/)[1]), source)
  let targetChat
  await client.watchSession(target, update => { targetChat = update })
  await client.prompt(target, `Read these: ${reference.mention} ${formatFileMention('mention folder/nested proof.txt')}`)
  await until(() => targetChat && !targetChat.running && targetChat.messages.some(message => message.role === 'assistant'), 'reference prompt')
  const sent = JSON.stringify(bodies.at(-1))
  assert.ok(sent.includes('UNIQUE_SESSION_REFERENCE_PROOF'), 'referenced conversation snapshot reaches model')
  assert.ok(sent.includes('UNIQUE_FILE_REFERENCE_PROOF'), 'referenced file content reaches model through the real read tool')
  assert.ok(targetChat.messages.some(message => message.role === 'user' && message.text.includes('@Referenced proof conversation')),
    'host stores resolved readable session reference')
  assert.ok((await client.listSessions(true, true)).some(item => item.id === source))
  console.log('Mention live: fuzzy files, folder drill, canonical session URI, real file/session context expansion and stored readable references passed')
} finally {
  client.close()
  provider.closeAllConnections()
  await new Promise(resolve => provider.close(resolve))
  if (child.exitCode === null) { child.kill('SIGTERM'); await once(child, 'exit') }
  await rm(home, { recursive: true, force: true })
}
