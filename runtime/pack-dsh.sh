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
  node "$runtime_dir/prepare-companion-recall.mjs" "$stage/root"
  node "$runtime_dir/prepare-companion-signals.mjs" "$stage/root"
  node "$runtime_dir/plugin-config-compat.mjs" "$stage/root"
  node --input-type=module - "$stage/root" <<'INTERNALS'
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
const path = join(process.argv[2], 'node_modules/@deepseek-ai/dsh-app-boot/lib/index.js');
const source = readFileSync(path, 'utf8');
const before = 'const addon = createRequire(import.meta.url)("node-addon-require-builtin");';
if (source.split(before).length !== 2) throw new Error('Unexpected DSH internal-loader source');
// The embedded Node host already passes --expose-internals. Preserve upstream's five
// internal module accesses and validation without loading a foreign native addon.
writeFileSync(path, source.replace(before, 'const addon = { requireBuiltin: createRequire(import.meta.url) };'));
INTERNALS
  test "$(node -p 'require("./node_modules/@deepseek-ai/dsh/package.json").version')" = '0.2.2-rc.1'
  test "$(node -p 'require("./node_modules/@deepseek-ai/node-addon-system/package.json").version')" = '0.1.2'
  cp "$runtime_dir/main.cjs" "$runtime_dir/profile.mjs" "$runtime_dir/credentials.mjs" "$runtime_dir/fetch.mjs" \
    "$runtime_dir/bot-bundle.mjs" "$runtime_dir/mutable-bundled-plugins.mjs" "$runtime_dir"/phone-*.mjs "$runtime_dir/phone-catalog.json" "$runtime_dir/PHONE_UPSTREAM_LICENSE.txt" "$runtime_dir/PHONE_SOURCE.md" \
    "$runtime_dir/workspace-fs.mjs" "$runtime_dir/workspace-directory-picker.mjs" "$runtime_dir/workspace-shell-policy.mjs" .
  cp "$runtime_dir"/attachment-*.mjs "$runtime_dir"/dsh-remote*.mjs "$runtime_dir"/ssh-*.cjs \
    "$runtime_dir/transport-control.mjs" "$runtime_dir/web-proxy.mjs" "$runtime_dir/plugin-manager-readonly.mjs" "$runtime_dir/private-vault.mjs" "$runtime_dir/forum-service.mjs" "$runtime_dir"/engine-*.mjs "$runtime_dir"/sensevoice-*.mjs "$runtime_dir"/subscription-auth*.mjs "$runtime_dir"/share-*.mjs .
  cp "$runtime_dir/../tests/fixtures/dsh-remote/LICENSE" dsh-remote-LICENSE.txt
  for dependency_dir in harmony-deps ssh-deps webrtc-deps media-deps; do
    mkdir "$dependency_dir"
    cp "$runtime_dir/$dependency_dir/package.json" "$runtime_dir/$dependency_dir/package-lock.json" "$dependency_dir/"
    npm ci --prefix "$dependency_dir" --ignore-scripts --omit=optional --no-audit --no-fund --loglevel=error
  done
  cp -R "$runtime_dir/vendor" vendor
  cp -R media-deps/node_modules/image-size node_modules/image-size
  rm -rf media-deps
  cp "$runtime_dir/webrtc-deps/LICENSE" webrtc-deps/
  rm -f ssh-deps/node_modules/ssh2/util/pagent.exe
  node "$runtime_dir/ssh-deps/prepare.cjs" "$stage/root/ssh-deps"
  cp "$runtime_dir/flock.mjs" node_modules/@deepseek-ai/node-addon-system/lib/flock.js
  persistence=node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js
  shasum -a 256 -c <<'SUMS'
69efef5f84dddf947032bc1425067878fa610416c8885acde2ded9b01230c9b7  node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js
4cf6c66e65cce865d270fa89405b96d048ffa62e493e4ffbd1a826be2207a4cd  node_modules/@deepseek-ai/dsh-api-session-controller/lib/index.js
257848af0e4bacb15265660a3750c7909bb4002ab02a1c2a3188045f882ee39e  node_modules/@deepseek-ai/dsh-api-workspace-controller/lib/index.js
ff717f87226b59d6224aff67796b43d5fd72b98d0e74fa91a952affaf3285f9d  node_modules/@deepseek-ai/dsh-attachment-local/lib/index.js
0e866969b6bf1aa93407ccd9c944b50bc27a1d961b7e4209ed60bd2b73d28805  node_modules/@deepseek-ai/dsh-tool-fs/lib/index.js
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
], [
  'const stored = await this.ctx.attachments.readImage(request.attachment);',
  `const observation = await this.ctx.sessionQuery.observeSession(request.sessionId);
			try {
				const known = observation.events.some(event => {
					const content = event?.type === "user/message" ? event.data.content :
						(event?.type === "assistant/message" || event?.type === "tool/result") ? event.data.message?.content : undefined;
					return content?.some(part => part.type === "image" && part.attachment?.attachmentId === request.attachment.attachmentId);
				});
				if (!known) throw new AttachmentError("Image was not attached to this session.", "ATTACHMENT_NOT_FOUND");
			} finally { observation[Symbol.dispose](); }
			const stored = await this.ctx.attachments.readImage(request.attachment);`
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
replaceController('dsh-attachment-local', [
  ['\t\tawait ensureDurableDirectory(home, parse(home).root);',
    `\t\t// The embedded engine's home is created below ArkUI context.filesDir.
\t\t// That app-owned parent is the durable boundary; sandbox ancestors are not readable.
\t\tconst boundary = typeof globalThis.dshHarmonyPublishAttachmentFile === "function" ? dirname(home) : parse(home).root;
\t\tawait ensureDurableDirectory(home, boundary);`],
  ['import { dirname, join, parse, resolve } from "node:path";',
    `import { dirname, join, parse, resolve } from "node:path";
import { encodePng, inspectPng } from "../../../../attachment-image.mjs";`],
  ['async function probeImage(data) {\n\tconst sharp = requireSharp();',
    `async function probeImage(data) {
	if (data[0] === 137) return inspectPng(data);
	const sharp = requireSharp();`],
  ['async function detectImage(data, limits) {\n\tconst sharp = requireSharp();',
    `async function detectImage(data, limits) {
	if (data[0] === 137) return inspectPng(data, limits);
	const sharp = requireSharp();`],
  ['async function normalizeImage(data, detected, policy) {',
    `async function normalizeImage(data, detected, policy) {
	if (detected.rgba) {
		const { width, height } = initialDimensions(detected, policy);
		return encodePng(detected, width, height, policy.maxBytes);
	}`],
  ['const encodedVersion = await encodeFirstWithinLimit(encodingLadder(pipeline(attachment, target), hasAlpha), target.maxBytes);',
    `if (attachment.ref.mediaType === "image/png") {
		const source = await inspectPng(attachment.data);
		const scale = Math.min(1, target.width / source.width, target.height / source.height);
		return encodePng(source, Math.max(1, Math.floor(source.width * scale)), Math.max(1, Math.floor(source.height * scale)), target.maxBytes);
	}
	const encodedVersion = await encodeFirstWithinLimit(encodingLadder(pipeline(attachment, target), hasAlpha), target.maxBytes);`],
  ['\t\t\tawait link(source, target);',
    `			try { await link(source, target); }
			catch (error) {
				if (!["EACCES", "EPERM"].includes(error?.code) || typeof globalThis.dshHarmonyPublishAttachmentFile !== "function") throw error;
				const staged = await stageImmutableObject(root, createReadStream(source));
				if (staged.sha256 !== sha256) {
					await removeTemporary(staged.path);
					throw new AttachmentError("Stored attachment failed integrity verification.", "ATTACHMENT_CORRUPT");
				}
				await publishStagedObject(root, target, staged);
				return;
			}`],
  ['\t\t\tawait link(staged.path, target);',
    `			try { await link(staged.path, target); }
			catch (error) {
				if (!["EACCES", "EPERM"].includes(error?.code) || typeof globalThis.dshHarmonyPublishAttachmentFile !== "function") throw error;
				globalThis.dshHarmonyPublishAttachmentFile(staged.path, target);
			}`],
  ['\t\tawait unlink(staged.path);', '\t\tawait removeTemporary(staged.path);']
]);
replaceController('dsh-tool-fs', [
  ['import z from "@deepseek-ai/schemastery";',
    `import z from "@deepseek-ai/schemastery";
import { sessionAttachmentRead } from "../../../../attachment-files.mjs";`],
  ['const inject = [\n\t"tools",\n\t"fs",',
    'const inject = [\n\t"tools",\n\t"fs",\n\t"sessionQuery",\n\t"attachments",'],
  ['const { target, info } = await resolveRegularReadTarget(ctx, exec, input.filePath);',
    `const attachment = await sessionAttachmentRead(ctx, exec, input.filePath);
			if (attachment) {
				const window = await buildWindow(attachment, { offset: input.offset, limit: input.limit,
					maxLineLength: caps.maxLineLength, maxBytes: caps.maxBytes }, input.filePath);
				return { path: input.filePath, offset: input.offset, lines: window.lines, totalLines: window.totalLines };
			}
			const { target, info } = await resolveRegularReadTarget(ctx, exec, input.filePath);`]
]);
PATCH
  node "$runtime_dir/prepare-session-deletion.mjs" "$stage/root"
  node "$runtime_dir/prepare-schedule-authorization.mjs" "$stage/root"
  rm -rf node_modules/.bin webrtc-deps/node_modules/.bin node_modules/node-pty/prebuilds node_modules/node-pty/third_party node_modules/@deepseek-ai/dsh-experimental-inspector/lib/devtools
  find node_modules webrtc-deps/node_modules -type f \( -name '*.map' -o -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' \) -delete
  find node_modules -type d -empty -delete
  if [ -n "$(find node_modules harmony-deps ssh-deps webrtc-deps vendor \( -type l -o -name '*.node' -o -name '*.so' -o -name '*.dylib' -o -name '*.wasm' -o -name '*.exe' -o -name '*.dll' \) -print -quit)" ]; then
    printf '%s\n' 'Unsupported native file or symbolic link in DSH JavaScript runtime' >&2
    exit 1
  fi
  zip -q -X -r "$stage/dsh-runtime.zip" main.cjs profile.mjs credentials.mjs fetch.mjs bot-bundle.mjs mutable-bundled-plugins.mjs phone-*.mjs phone-catalog.json PHONE_UPSTREAM_LICENSE.txt PHONE_SOURCE.md workspace-fs.mjs \
    workspace-directory-picker.mjs workspace-shell-policy.mjs transport-control.mjs web-proxy.mjs plugin-manager-readonly.mjs private-vault.mjs forum-service.mjs engine-*.mjs sensevoice-*.mjs subscription-auth*.mjs share-*.mjs attachment-*.mjs \
    dsh-remote*.mjs dsh-remote-LICENSE.txt ssh-*.cjs harmony-deps ssh-deps webrtc-deps vendor package.json package-lock.json node_modules
)
shasum -a 256 "$stage/dsh-runtime.zip" | awk '{print $1}' > "$stage/dsh-runtime-version.txt"
cp "$stage/dsh-runtime.zip" "$output_dir/dsh-runtime.zip.tmp"
cp "$stage/dsh-runtime-version.txt" "$output_dir/dsh-runtime-version.txt.tmp"
mv "$output_dir/dsh-runtime.zip.tmp" "$output_dir/dsh-runtime.zip"
mv "$output_dir/dsh-runtime-version.txt.tmp" "$output_dir/dsh-runtime-version.txt"
ls -lh "$output_dir/dsh-runtime.zip"
