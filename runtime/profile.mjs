import { createRequire } from 'node:module';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);

// Preset subtrees resolve relative to the private data directory in embedded Node.
function bundledPlugin(name) {
  return pathToFileURL(require.resolve(name)).href;
}

const disabled = [
  'credentials', 'directory-picker', 'tool-working-directory', 'plugin-manager', 'hmr', 'session-title-llm', 'session-log-deepseek', 'session-telemetry-otel',
  'desktop-product-telemetry', 'product-analytics', 'subprocess', 'sandbox', 'bash-sandbox', 'pwsh-sandbox',
  'ptc-runtime', 'tool-executor-ptc', 'web-search-deepseek', 'web-deepseek-api', 'web-fetch-http',
  'open-in-app', 'terminal-controller', 'office-to-pdf', 'client-hmr', 'harness-dev-context',
  'preset-standard', 'preset-ptc', 'preset-minimal', 'preset-cordis'
];

export function localPatches(runtimeRoot, workspaceDir) {
  const patches = disabled.map(id => ({ id, disabled: true }));
  const workspaceFs = pathToFileURL(join(runtimeRoot, 'workspace-fs.mjs')).href;
  patches.push(
    { id: 'fs-sandbox', disabled: true },
    { insert: [
      { id: 'harmony-memory-credentials', name: pathToFileURL(join(runtimeRoot, 'credentials.mjs')).href },
      { id: 'harmony-shell-policy', name: pathToFileURL(join(runtimeRoot, 'workspace-shell-policy.mjs')).href },
      { id: 'harmony-workspace-fs', name: workspaceFs, config: { cwd: workspaceDir } },
      { id: 'harmony-directory-picker', name: pathToFileURL(join(runtimeRoot, 'workspace-directory-picker.mjs')).href }
    ] },
    { id: 'system-prompt', config: { personaPrefix: 'You are a helpful coding assistant.' } },
    { id: 'working-directory', config: { defaultDirectory: workspaceDir } },
    { id: 'sandbox-policy', config: { mode: 'workspace-write', workspaceRoot: workspaceDir } },
    { id: 'session-controller', config: { nativeOpen: false } },
    { id: 'session-query-sqlite', config: { path: ':memory:', openAt: 'first-search' } },
    { id: 'web-runtime', config: { openBrowser: false, printUrl: false, surfaceContext: false } },
    { insert: [{ id: 'preset-harmony', name: '@deepseek-ai/dsh-agent-preset', config: {
      id: 'standard', order: 1, plugins: [
        { id: 'tool-fs', name: bundledPlugin('@deepseek-ai/dsh-tool-fs'), config: { readImage: false, applyPatch: false } },
        { id: 'skill-filesystem', name: bundledPlugin('@deepseek-ai/dsh-skill-filesystem'), config: {
          dshHome: join(workspaceDir, '.dsh'), agentsHome: join(workspaceDir, '.agents'),
          watch: false, watchFollowSymlinks: false
        } },
        { id: 'tool-skill', name: bundledPlugin('@deepseek-ai/dsh-tool-skill') },
        { id: 'tool-ask-user', name: bundledPlugin('@deepseek-ai/dsh-tool-ask-user') },
        { id: 'tool-todo', name: bundledPlugin('@deepseek-ai/dsh-tool-todo'), config: { allowParallelInProgress: true } },
        { id: 'tool-subagent-control', name: bundledPlugin('@deepseek-ai/dsh-tool-subagent-control') },
        { id: 'tool-subagent', name: bundledPlugin('@deepseek-ai/dsh-tool-subagent'),
          config: { provider: 'spawn', toolName: 'subagent', modelSelection: true, modelDiscovery: true } },
        { id: 'tool-subagent-fork', name: bundledPlugin('@deepseek-ai/dsh-tool-subagent'),
          config: { provider: 'fork', toolName: 'subagent_fork' } }
      ]
    } }] }
  );
  return patches;
}
