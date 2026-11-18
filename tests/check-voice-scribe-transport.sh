#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
unzip -q "$project_dir/entry/src/main/resources/rawfile/dsh-runtime.zip" -d "$test_dir/runtime"
cp "$project_dir/tests/voice-scribe-transport.mjs" "$project_dir/tests/dsh-client-node-fixture.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/voice-scribe-transport.mjs" \
 "$project_dir/entry/src/main/ets/dsh/DshClient.ets" "$test_dir/runtime"
