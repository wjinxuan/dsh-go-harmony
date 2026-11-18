#!/bin/sh
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
upstream=${1:?"Pass the ds-harness-remote source checkout at 04edf424e08909f2929f74c23abaa8ad86670a7d"}
archive=${2:-"$project/entry/src/main/resources/rawfile/dsh-runtime.zip"}
test "$(git -C "$upstream" rev-parse HEAD)" = 04edf424e08909f2929f74c23abaa8ad86670a7d
git -C "$upstream" diff --quiet HEAD -- packages/crypto/src packages/protocol/src apps/server/src
node "$project/tests/require-runtime-node.mjs"
node --test "$project/tests/dsh-remote-wire.test.mjs"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/responder" "$stage/server" "$stage/protocol" "$stage/rtc"
git -C "$upstream" show HEAD:packages/crypto/src/index.ts | sed "s|'./noise.js'|'./noise.ts'|" > "$stage/responder/index.ts"
git -C "$upstream" show HEAD:packages/crypto/src/noise.ts | sed "s|'./index.js'|'./index.ts'|" > "$stage/responder/noise.ts"
cat > "$stage/package.json" <<'PACKAGE'
{"type":"module","private":true,"dependencies":{"@lukeburns/clatterjs":"1.0.0","@noble/ciphers":"1.1.3","@noble/curves":"1.7.0","@noble/hashes":"1.6.1","zod":"4.6.7"}}
PACKAGE
npm install --prefix "$stage" --ignore-scripts --no-audit --no-fund --loglevel=error
for file in server store gateway ice logger config; do
  git -C "$upstream" show "HEAD:apps/server/src/$file.ts" | sed -e "s|\.js'|.ts'|g" \
    -e "s|'@dsh-remote/protocol'|'../protocol/index.ts'|g" > "$stage/server/$file.ts"
done
for file in index loopback wire-json close-semantics; do
  git -C "$upstream" show "HEAD:packages/protocol/src/$file.ts" | sed "s|\.js'|.ts'|g" > "$stage/protocol/$file.ts"
done
for file in rtc-data-channel rtc-adapter rtc-chunking; do
  git -C "$upstream" show "HEAD:packages/webrtc/src/$file.ts" | sed "s|\.js'|.ts'|g" > "$stage/rtc/$file.ts"
done
for file in werift-rtc native-rtc-helper; do
  git -C "$upstream" show "HEAD:packages/plugin/src/$file.ts" | sed -e "s|\.js'|.ts'|g" \
    -e "s|'@dsh-remote/webrtc'|'./rtc-adapter.ts'|g" \
    -e "s|'@dsh-remote/protocol'|'../protocol/index.ts'|g" > "$stage/rtc/$file.ts"
done
unzip -q "$archive" -d "$stage/runtime"
ln -s "$stage/runtime/node_modules/ws" "$stage/node_modules/ws"
ln -s "$stage/runtime/webrtc-deps/node_modules/werift" "$stage/node_modules/werift"
node --disable-warning=ExperimentalWarning --experimental-transform-types \
  "$project/tests/dsh-remote-relay.test.mjs" "$stage/runtime" "$stage/responder/index.ts" "$stage/server/server.ts" "$stage/rtc"
