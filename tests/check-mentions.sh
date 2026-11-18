#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/ui" "$test_dir/dsh"
sed -e "s|import { util } from '@kit.ArkTS'|import { util } from '../mention-fixture.mjs'|" \
  -e "s|import type { DshClient } from '../dsh/DshClient'|import type { DshClient } from '../dsh/DshClient.ts'|" \
  -e "s|object, string, WireObject, DshSession|object, string|" \
  -e "s|'../dsh/DshWire'|'../dsh/DshWire.ts'|" \
  "$project_dir/entry/src/main/ets/ui/MentionData.ets" > "$test_dir/ui/MentionData.ts"
cp "$project_dir/entry/src/main/ets/dsh/DshWire.ets" "$test_dir/dsh/DshWire.ts"
cp "$project_dir/tests/mention-fixture.mjs" "$project_dir/tests/mentions.test.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/mentions.test.mjs"
if [ "${1:-}" = '--live' ]; then
  unzip -q "$project_dir/entry/src/main/resources/rawfile/dsh-runtime.zip" -d "$test_dir/runtime"
  cp "$project_dir/tests/mentions-live.mjs" "$project_dir/tests/dsh-client-node-fixture.mjs" "$test_dir/"
  node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/mentions-live.mjs" \
    "$project_dir/entry/src/main/ets/dsh/DshClient.ets" "$test_dir/runtime" "$project_dir/tests/local-flock-fixture.cjs"
fi
