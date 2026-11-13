#!/bin/sh
set -eu

runtime_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output_dir=${1:-"$runtime_dir/../entry/src/main/resources/rawfile"}
mkdir -p "$output_dir"
output_dir=$(CDPATH= cd -- "$output_dir" && pwd)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
trap 'exit 1' HUP INT TERM
mkdir "$stage/root"
upstream=https://raw.githubusercontent.com/ccch1mneyyy/dsh-Go/a9877420ab9aee121134faf01b6a92a39ce0b05b/runtime/locks/dsh-0.2.2-rc.1
curl --fail --silent --show-error --location "$upstream/package.json" -o "$stage/root/package.json"
curl --fail --silent --show-error --location "$upstream/package-lock.json" -o "$stage/root/package-lock.json"
(
  cd "$stage/root"
  shasum -a 256 -c <<'SUMS'
ff39278b4a4eb3b92cb77f4b281be810bfebe24b4c9ce50b67e25959ea9c067f  package.json
9809a7a64fd5d40df441a30fb4407c037802162d75e8a8e39dc0ef2569bec2ab  package-lock.json
SUMS
  npm ci --ignore-scripts --omit=optional --no-audit --no-fund --loglevel=error
  test "$(node -p 'require("./node_modules/@deepseek-ai/dsh/package.json").version')" = '0.2.2-rc.1'
  test "$(node -p 'require("./node_modules/@deepseek-ai/node-addon-system/package.json").version')" = '0.1.2'
  cp "$runtime_dir/main.cjs" "$runtime_dir/profile.mjs" "$runtime_dir/credentials.mjs" "$runtime_dir/fetch.mjs" \
    "$runtime_dir/workspace-fs.mjs" "$runtime_dir/workspace-directory-picker.mjs" "$runtime_dir/workspace-shell-policy.mjs" .
  cp "$runtime_dir/flock.mjs" node_modules/@deepseek-ai/node-addon-system/lib/flock.js
  persistence=node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js
  shasum -a 256 -c <<'SUMS'
69efef5f84dddf947032bc1425067878fa610416c8885acde2ded9b01230c9b7  node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js
4cf6c66e65cce865d270fa89405b96d048ffa62e493e4ffbd1a826be2207a4cd  node_modules/@deepseek-ai/dsh-api-session-controller/lib/index.js
257848af0e4bacb15265660a3750c7909bb4002ab02a1c2a3188045f882ee39e  node_modules/@deepseek-ai/dsh-api-workspace-controller/lib/index.js
SUMS
  node - "$persistence" <<'PATCH'
const { readFileSync, writeFileSync } = require('node:fs');
const path = process.argv[2];
const source = readFileSync(path, 'utf8');
const original = '\t\t\tawait link(tmp, finalPath);';
if (source.split(original).length !== 2) throw new Error('Unexpected DSH session publication source');
// HarmonyOS application policy can deny hardlinks even within the app sandbox.
const replacement = [
  '\t\t\ttry {',
  '\t\t\t\tawait link(tmp, finalPath);',
  '\t\t\t} catch (error) {',
  '\t\t\t\tif (error?.syscall !== "link" || (error.code !== "EACCES" && error.code !== "EPERM") ||',
  '\t\t\t\t\ttypeof globalThis.dshHarmonyPublishFile !== "function") throw error;',
  '\t\t\t\tglobalThis.dshHarmonyPublishFile(tmp, finalPath);',
  '\t\t\t}'
].join('\n');
writeFileSync(path, source.replace(original, replacement));

function replaceController(packageName, replacements) {
  const path = `node_modules/@deepseek-ai/${packageName}/lib/index.js`;
  let source = readFileSync(path, 'utf8');
  for (const [original, replacement] of replacements) {
    if (source.split(original).length !== 2) throw new Error(`Unexpected ${packageName} source`);
    source = source.replace(original, replacement);
  }
  writeFileSync(path, source);
}

replaceController('dsh-api-session-controller', [[
  'const cwd = workspace?.path ?? request.cwd ?? this.defaultCwd;',
  `const fs = this.ctx.get("fs");
\t\tlet cwd = workspace?.path ?? request.cwd ?? this.defaultCwd;
\t\tif (fs?.workspaceDirectory) try {
\t\t\tcwd = await fs.workspaceDirectory(workspace?.path ?? request.cwd);
\t\t} catch (error) {
\t\t\tthrow new RemoteError("workspace/invalid-path", "Session directory is outside the local workspace or unavailable", {}, { cause: error });
\t\t}`
]]);
replaceController('dsh-api-workspace-controller', [
  ['const existing = await this.ctx.workspaceRegistry.resolveByPath(request.path);',
    `const fs = this.ctx.get("fs");
\t\t\t\tconst path = fs?.workspaceDirectory ? await fs.workspaceDirectory(request.path) : request.path;
\t\t\t\tconst existing = await this.ctx.workspaceRegistry.resolveByPath(path);`],
  ['this.ctx.workspaceRegistry.create(request.path)', 'this.ctx.workspaceRegistry.create(path)'],
  ['return await defaultWorkspaceDirectory(this.config.documentsDirectory, AbortSignal.any([signal, timeout]));',
    `const fs = this.ctx.get("fs");
\t\t\t\tif (fs?.workspaceDirectory) return await fs.workspaceDirectory();
\t\t\t\treturn await defaultWorkspaceDirectory(this.config.documentsDirectory, AbortSignal.any([signal, timeout]));`]
]);
PATCH
  rm -rf node_modules/.bin node_modules/node-pty/prebuilds node_modules/node-pty/third_party node_modules/@deepseek-ai/dsh-experimental-inspector/lib/devtools
  find node_modules -type f \( -name '*.map' -o -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' \) -delete
  find node_modules -type d -empty -delete
  if [ -n "$(find node_modules \( -type l -o -name '*.node' -o -name '*.so' -o -name '*.dylib' -o -name '*.wasm' -o -name '*.exe' -o -name '*.dll' \) -print -quit)" ]; then
    printf '%s\n' 'Unsupported native file or symbolic link in DSH JavaScript runtime' >&2
    exit 1
  fi
  zip -q -X -r "$stage/dsh-runtime.zip" main.cjs profile.mjs credentials.mjs fetch.mjs workspace-fs.mjs \
    workspace-directory-picker.mjs workspace-shell-policy.mjs package.json package-lock.json node_modules
)
shasum -a 256 "$stage/dsh-runtime.zip" | awk '{print $1}' > "$stage/dsh-runtime-version.txt"
cp "$stage/dsh-runtime.zip" "$output_dir/dsh-runtime.zip.tmp"
cp "$stage/dsh-runtime-version.txt" "$output_dir/dsh-runtime-version.txt.tmp"
mv "$output_dir/dsh-runtime.zip.tmp" "$output_dir/dsh-runtime.zip"
mv "$output_dir/dsh-runtime-version.txt.tmp" "$output_dir/dsh-runtime-version.txt"
ls -lh "$output_dir/dsh-runtime.zip"
