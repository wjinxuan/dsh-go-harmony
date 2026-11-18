#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
unzip -q "${1:-$project_dir/entry/src/main/resources/rawfile/dsh-runtime.zip}" -d "$test_dir/runtime"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$project_dir/tests/media-live.mjs" "$test_dir"
