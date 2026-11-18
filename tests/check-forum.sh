#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
sed "s|'../dsh/DshWire'|'./DshWire.ts'|g" "$project_dir/entry/src/main/ets/forum/ForumData.ets" > "$test_dir/ForumData.ts"
cp "$project_dir/entry/src/main/ets/dsh/DshWire.ets" "$test_dir/DshWire.ts"
cp "$project_dir/entry/src/main/ets/forum/ForumCallback.ets" "$test_dir/ForumCallback.ts"
cp "$project_dir/tests/forum-data.test.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/forum-data.test.mjs"
if [ -n "${1:-}" ]; then
  node "$project_dir/tests/forum-service.mjs" "$1"
  node "$project_dir/tests/forum-http.mjs" "$1"
fi
