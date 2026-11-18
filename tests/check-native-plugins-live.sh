#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
node --test "$project_dir/tests/native-plugin-reactivity.test.mjs"
node --test "$project_dir/tests/native-plugin-image-safe-area.test.mjs"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
unzip -q "${1:-$project_dir/entry/src/main/resources/rawfile/dsh-runtime.zip}" -d "$test_dir/runtime"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$project_dir/tests/native-plugins-live.mjs" "$test_dir"
