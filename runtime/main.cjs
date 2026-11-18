'use strict';

const { mkdirSync, renameSync, rmSync, writeFileSync, existsSync } = require('node:fs');
const { isAbsolute, join, basename } = require('node:path');
const { pathToFileURL } = require('node:url');
const { syncBuiltinESMExports } = require('node:module');
const childProcess = require('node:child_process');

const dataDir = process.argv[2];
if (!dataDir || !isAbsolute(dataDir)) throw new Error('Absolute private data directory required');
const workspaceDir = join(dataDir, 'workspace');
const readyPath = join(dataDir, 'ready.json');
const errorPath = join(dataDir, 'error.json');
const stopPath = join(dataDir, 'stop');

function writeMarker(path, body) {
  const staged = `${path}.tmp`;
  writeFileSync(staged, JSON.stringify(body), { mode: 0o600 });
  renameSync(staged, path);
}

for (const method of ['exec', 'execFile', 'execFileSync', 'execSync', 'fork', 'spawn', 'spawnSync']) {
  childProcess[method] = () => { throw new Error('Child processes are unavailable in the Harmony DSH engine'); };
}
syncBuiltinESMExports();

let lifecycle;
async function main() {
  lifecycle = undefined;
  const { resetBeforeStart } = await import('./engine-reset.mjs');
  await resetBeforeStart(dataDir);
  const { EngineLifecycle } = await import('./engine-lifecycle.mjs');
  lifecycle = new EngineLifecycle(dataDir);
  lifecycle.state.runtimeVersion = /^dsh-runtime-([a-f0-9]{64})$/.exec(basename(__dirname))?.[1] ?? '';
  lifecycle.save();
  mkdirSync(workspaceDir, { recursive: true, mode: 0o700 });
  mkdirSync(join(workspaceDir, '.dsh'), { recursive: true, mode: 0o700 });
  for (const path of [readyPath, errorPath]) rmSync(path, { force: true });
  const mainConfig = join(dataDir, 'cordis.json');
  writeMarker(mainConfig, []);
  const homeBefore = process.env.DSH_HOME;
  process.env.DSH_HOME = dataDir;
  let ctx;
  let transportControl;
  let stopTimer;
  try {
    const { installJitlessFetch } = await import('./fetch.mjs');
    installJitlessFetch();
    const [{ boot, readProfilePatches, createRuntimeResolution, loadProfileDirectory, PluginPackages }, { provideCmdline }, { createLaunchEnvironmentSnapshot }, { localPatches }] = await Promise.all([
      import('@deepseek-ai/dsh-app-boot'), import('@deepseek-ai/dsh-cmdline'),
      import('@deepseek-ai/dsh-launch-environment'), import('./profile.mjs')
    ]);
    const packageManifest = join(__dirname, 'node_modules/@deepseek-ai/dsh/package.json');
    const profileDir = join(dataDir, lifecycle.safe ? 'safe-profile' : 'profile');
    mkdirSync(profileDir, { recursive: true, mode: 0o700 });
    const patchPath = join(profileDir, 'cordis.patch.yml');
    if (lifecycle.safe || !existsSync(patchPath)) writeFileSync(patchPath, '[]\n', { mode: 0o600 });
    const { ensureMutableBundledPlugins } = await import('./mutable-bundled-plugins.mjs');
    await ensureMutableBundledPlugins({ patchPath, runtimeRoot: __dirname });
    const startedBundles = ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app'];
    writeMarker(join(profileDir, 'package.json'), {
      name: 'dsh-profile-harmony', private: true, dependencies: {}, dsh: { profile: { bundles: startedBundles } }
    });
    const profile = {
      name: 'harmony', dir: profileDir, patchPath, installAnchor: packageManifest,
      startedBundles, cwd: workspaceDir, home: lifecycle.safe ? profileDir : dataDir, overlays: localPatches(__dirname, workspaceDir, lifecycle.safe),
      telemetryDisabledEnv: '1'
    };
    const resolution = await createRuntimeResolution({ installAnchor: packageManifest,
      profile: loadProfileDirectory('dsh', profileDir, packageManifest), home: profile.home });
    const patches = readProfilePatches('dsh', profile);
    const port = process.argv[3] ?? '0';
    if (!/^\d{1,5}$/.test(port) || Number(port) > 65535) throw new Error('Invalid loopback listen port');
    ctx = await boot('dsh', mainConfig, patches, async host => {
      host.provide('launchEnvironment', createLaunchEnvironmentSnapshot([]));
      host.provide('profileContext', profile);
      await host.plugin(PluginPackages, { resolution });
      provideCmdline(host, { args: ['--host', '127.0.0.1', '--port', port, '--no-open'], exit: () => {} });
    }, pathToFileURL(packageManifest).href);
    const { connection, webServer } = ctx;
    const origin = webServer.getOrigin();
    webServer.server.prependListener('upgrade', (request, socket) => {
      if (socket.remoteAddress === '127.0.0.1' && request.url === '/api/remote.mux' &&
          request.headers.host === `127.0.0.1:${webServer.port}` && request.headers.origin === 'http://127.0.0.1') {
        request.headers.origin = origin;
      }
    });
    const [{ startTransportControl }, { createDshRemoteHandler }, { createSshBridgeHandler }, { createSenseVoiceHandler }, { createWebProxyHandler }, { createShareHandler }, { createForumHandler }] = await Promise.all([
      import('./transport-control.mjs'), import('./dsh-remote.mjs'), import('./ssh-bridge.cjs'), import('./sensevoice-control.mjs'), import('./web-proxy.mjs'), import('./share-service.mjs'), import('./forum-service.mjs')
    ]);
    const { createBotBundleHandler } = await import('./bot-bundle.mjs');
    const { createPhoneHandler } = await import('./phone-service.mjs');
    const { createCredentialsHandler } = await import('./credentials.mjs');
    transportControl = await startTransportControl({ ssh: createSshBridgeHandler(), relay: createDshRemoteHandler(dataDir), sensevoice: createSenseVoiceHandler(), web: createWebProxyHandler(), share: createShareHandler(dataDir), forum: createForumHandler(dataDir), botBundle: createBotBundleHandler(dataDir, lifecycle.safe), phone: createPhoneHandler(dataDir), credentials: createCredentialsHandler(ctx.credentials) });
    if (!existsSync(stopPath)) {
      lifecycle.ready();
      writeMarker(readyPath, { url: connection.authenticatedUrl(origin), workspaceDir, runtimeVersion: lifecycle.state.runtimeVersion, transportControl: transportControl.endpoint });
    }
    await new Promise(resolve => {
      stopTimer = setInterval(() => { if (existsSync(stopPath)) resolve(); }, 100);
    });
  } finally {
    clearInterval(stopTimer);
    rmSync(readyPath, { force: true });
    rmSync(stopPath, { force: true });
    try {
      try { await transportControl?.close(); }
      finally { await ctx?.fiber.dispose(); }
    } finally {
      if (homeBefore === undefined) delete process.env.DSH_HOME;
      else process.env.DSH_HOME = homeBefore;
    }
  }
  lifecycle.stopped();
}

async function run() {
  const { captureEngineStream } = await import('./engine-log.mjs');
  captureEngineStream(process.stdout, line => lifecycle?.log(line));
  captureEngineStream(process.stderr, line => lifecycle?.log(line));
  while (true) {
    try { await main(); return; }
    catch (error) {
      lifecycle?.failed(error);
      if (lifecycle?.state.restartSafe && !lifecycle.safe) continue;
      if (process.env.DSH_HARMONY_DEBUG === '1') console.error(error);
      writeMarker(errorPath, { message: '本机 DSH 引擎启动或停止失败' });
      process.exitCode = 1;
      return;
    }
  }
}
run().catch(() => { process.exitCode = 1; });
