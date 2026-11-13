'use strict';

const { mkdirSync, renameSync, rmSync, writeFileSync, existsSync } = require('node:fs');
const { isAbsolute, join } = require('node:path');
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

async function main() {
  mkdirSync(workspaceDir, { recursive: true, mode: 0o700 });
  for (const path of [readyPath, errorPath]) rmSync(path, { force: true });
  const mainConfig = join(dataDir, 'cordis.json');
  writeMarker(mainConfig, []);
  const homeBefore = process.env.DSH_HOME;
  process.env.DSH_HOME = dataDir;
  let ctx;
  let stopTimer;
  try {
    const { installJitlessFetch } = await import('./fetch.mjs');
    installJitlessFetch();
    const [{ boot, readProfilePatches }, { provideCmdline }, { createLaunchEnvironmentSnapshot }, { localPatches }] = await Promise.all([
      import('@deepseek-ai/dsh-app-boot'), import('@deepseek-ai/dsh-cmdline'),
      import('@deepseek-ai/dsh-launch-environment'), import('./profile.mjs')
    ]);
    const packageManifest = join(__dirname, 'node_modules/@deepseek-ai/dsh/package.json');
    const profileDir = join(dataDir, 'profile');
    mkdirSync(profileDir, { recursive: true, mode: 0o700 });
    const patchPath = join(profileDir, 'cordis.patch.yml');
    if (!existsSync(patchPath)) writeFileSync(patchPath, '[]\n', { mode: 0o600 });
    const startedBundles = ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app'];
    writeMarker(join(profileDir, 'package.json'), {
      name: 'dsh-profile-harmony', private: true, dependencies: {}, dsh: { profile: { bundles: startedBundles } }
    });
    const profile = {
      name: 'harmony', dir: profileDir, patchPath, installAnchor: packageManifest,
      startedBundles, cwd: workspaceDir, home: dataDir, overlays: localPatches(__dirname, workspaceDir),
      telemetryDisabledEnv: '1'
    };
    const patches = readProfilePatches('dsh', profile);
    const port = process.argv[3] ?? '0';
    if (!/^\d{1,5}$/.test(port) || Number(port) > 65535) throw new Error('Invalid loopback listen port');
    ctx = await boot('dsh', mainConfig, patches, host => {
      host.provide('launchEnvironment', createLaunchEnvironmentSnapshot([]));
      host.provide('profileContext', profile);
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
    if (!existsSync(stopPath)) writeMarker(readyPath, { url: connection.authenticatedUrl(origin), workspaceDir });
    await new Promise(resolve => {
      stopTimer = setInterval(() => { if (existsSync(stopPath)) resolve(); }, 100);
    });
  } finally {
    clearInterval(stopTimer);
    rmSync(readyPath, { force: true });
    rmSync(stopPath, { force: true });
    try {
      await ctx?.fiber.dispose();
    } finally {
      if (homeBefore === undefined) delete process.env.DSH_HOME;
      else process.env.DSH_HOME = homeBefore;
    }
  }
}

main().catch(error => {
  if (process.env.DSH_HARMONY_DEBUG === '1') console.error(error);
  writeMarker(errorPath, { message: '本机 DSH 引擎启动或停止失败' });
  process.exitCode = 1;
});
