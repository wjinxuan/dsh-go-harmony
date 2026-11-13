#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
runtime_zip=${1:-"$project_dir/entry/src/main/resources/rawfile/dsh-runtime.zip"}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
unzip -q "$runtime_zip" -d "$test_dir/runtime"
cp "$project_dir/tests/dsh-client-live.mjs" "$project_dir/tests/dsh-client-node-fixture.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/dsh-client-live.mjs" \
  "$project_dir/entry/src/main/ets/dsh/DshClient.ets" "$test_dir/runtime" "$project_dir/tests/local-flock-fixture.cjs"
