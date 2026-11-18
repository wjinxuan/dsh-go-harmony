#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
sed "s|'../dsh/DshWire'|'./DshWire.ts'|g" "$project_dir/entry/src/main/ets/ui/StartupData.ets" > "$test_dir/StartupData.ts"
cp "$project_dir/entry/src/main/ets/dsh/DshWire.ets" "$test_dir/DshWire.ts"
cp "$project_dir/tests/startup.test.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/startup.test.mjs"
node --test "$project_dir/tests/engine-lifecycle.test.mjs" "$project_dir/tests/engine-reset.test.mjs" "$project_dir/tests/engine-log.test.mjs"
