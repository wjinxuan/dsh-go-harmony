import { createRequire } from 'node:module';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { bundledBotEnabled } from './bot-bundle.mjs';

const require = createRequire(import.meta.url);

// Preset subtrees resolve relative to the private data directory in embedded Node.
function bundledPlugin(name) {
  return pathToFileURL(require.resolve(name)).href;
}

const disabled = [
  'credentials', 'directory-picker', 'tool-working-directory', 'hmr', 'session-title-llm', 'session-log-deepseek', 'session-telemetry-otel',
  'desktop-product-telemetry', 'product-analytics', 'subprocess', 'sandbox', 'bash-sandbox', 'pwsh-sandbox',
  'ptc-runtime', 'tool-executor-ptc', 'web-search-deepseek', 'web-deepseek-api', 'web-fetch-http',
  'open-in-app', 'terminal-controller', 'office-to-pdf', 'client-hmr', 'harness-dev-context',
  'preset-standard', 'preset-ptc', 'preset-minimal', 'preset-cordis'
];

export function localPatches(runtimeRoot, workspaceDir, safeMode = false) {
  const patches = disabled.map(id => ({ id, disabled: true }));
  const workspaceFs = pathToFileURL(join(runtimeRoot, 'workspace-fs.mjs')).href;
  patches.push(
    { id: 'fs-sandbox', disabled: true },
    { id: 'plugin-manager', disabled: true },
    { insert: [
      { id: 'harmony-plugin-manager-inventory', name: pathToFileURL(join(runtimeRoot, 'plugin-manager-readonly.mjs')).href },
      { id: 'speech-to-text', name: bundledPlugin('@deepseek-ai/dsh-experimental-speech-to-text'), config: { defaultProvider: 'sensevoice-local' } },
      { id: 'harmony-sensevoice', name: pathToFileURL(join(runtimeRoot, 'sensevoice-provider.mjs')).href },
      { id: 'api-speech-to-text', name: bundledPlugin('@deepseek-ai/dsh-experimental-api-speech-to-text') },
      { id: 'app-auth', name: pathToFileURL(join(runtimeRoot, 'subscription-auth.mjs')).href },
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
        { id: 'compaction', name: 'cordis:group', group: true,
          isolate: { compaction: true, toolResultPruner: true }, config: [
            { id: 'compaction-basic', name: bundledPlugin('@deepseek-ai/dsh-compaction-basic') },
            { id: 'command-compact', name: bundledPlugin('@deepseek-ai/dsh-command-compact') },
            { id: 'tool-result-pruner', name: bundledPlugin('@deepseek-ai/dsh-compaction-tool-result-pruner'),
              config: { thresholdChars: 8192, headChars: 4096, tailChars: 1024 } }
          ] },
        { id: 'agent-instructions', name: bundledPlugin('@deepseek-ai/dsh-agent-instructions'), config: { maxBytes: 65536, projectRootMarkers: ['.git', '.dsh'] } },
        { id: 'tool-fs', name: bundledPlugin('@deepseek-ai/dsh-tool-fs'), config: { readImage: false, applyPatch: false } },
        { id: 'skill-filesystem', name: bundledPlugin('@deepseek-ai/dsh-skill-filesystem'), config: {
          dshHome: join(workspaceDir, '.dsh'), agentsHome: join(workspaceDir, '.agents'),
          watch: false, watchFollowSymlinks: false
        } },
        { id: 'tool-skill', name: bundledPlugin('@deepseek-ai/dsh-tool-skill') },
        { id: 'tool-ask-user', name: bundledPlugin('@deepseek-ai/dsh-tool-ask-user') },
        { id: 'tool-schedule', name: bundledPlugin('@deepseek-ai/dsh-tool-schedule') },
        { id: 'tool-harmony-phone', name: pathToFileURL(join(runtimeRoot, 'phone-provider.mjs')).href },
        { id: 'tool-jobs', name: bundledPlugin('@deepseek-ai/dsh-tool-jobs') },
        { id: 'tool-todo', name: bundledPlugin('@deepseek-ai/dsh-tool-todo'), config: { allowParallelInProgress: true } },
        { id: 'tool-subagent-control', name: bundledPlugin('@deepseek-ai/dsh-tool-subagent-control') },
        { id: 'tool-subagent', name: bundledPlugin('@deepseek-ai/dsh-tool-subagent'),
          config: { provider: 'spawn', toolName: 'subagent', modelSelection: true, modelDiscovery: true } },
        { id: 'tool-subagent-fork', name: bundledPlugin('@deepseek-ai/dsh-tool-subagent'),
          config: { provider: 'fork', toolName: 'subagent_fork' } }
      ]
    } }] }
  );
  // Full companion uses the same app-scoped tools as the normal Harmony preset.
  // The real bridge provider supplies persona + scoped recall context; no inline prompt fallback.
  const standard = patches.flatMap(patch => patch.insert || []).find(row => row.id === 'preset-harmony');
  patches.push({ insert: [{ id: 'preset-harmony-companion-full', name: '@deepseek-ai/dsh-agent-preset', config: {
    id: 'dsh-go-companion-full', name: '伙伴·完整', order: 91,
    description: '保留伙伴人设，使用本机工作区工具与已授权的手机工具。',
    plugins: [
      { id: 'companion-full-context', name: pathToFileURL(join(runtimeRoot, 'vendor/dsh-go-bridge/lib/companion/full-context.js')).href },
      ...structuredClone(standard.config.plugins)
    ]
  } }] });
  if (!safeMode && process.env.DSH_HOME && bundledBotEnabled(process.env.DSH_HOME)) patches.push({ insert: [
    { id: 'harmony-bundled-ds-bot', name: pathToFileURL(join(runtimeRoot, 'vendor/ds-bot/index.js')).href, config: { updateCheck: false, workspace: workspaceDir } }
  ] });
  return patches;
}
