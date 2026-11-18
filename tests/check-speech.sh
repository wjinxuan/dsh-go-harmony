#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node --disable-warning=ExperimentalWarning --experimental-strip-types --test "$project_dir/tests/speech.test.mjs"
if [ "${1:-}" = '--live' ]; then
  node "$project_dir/tests/require-runtime-node.mjs"
  test_dir=$(mktemp -d)
  trap 'rm -rf "$test_dir"' EXIT
  unzip -q "$project_dir/entry/src/main/resources/rawfile/dsh-runtime.zip" -d "$test_dir/runtime"
  cp "$project_dir/tests/speech-live.mjs" "$project_dir/tests/dsh-client-node-fixture.mjs" "$test_dir/"
  node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/speech-live.mjs" \
    "$project_dir/entry/src/main/ets/dsh/DshClient.ets" "$test_dir/runtime" "$project_dir/tests/local-flock-fixture.cjs"
fi
