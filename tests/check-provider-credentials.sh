#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
unzip -q "${1:-$project_dir/entry/src/main/resources/rawfile/dsh-runtime.zip}" -d "$test_dir/runtime"
DSH_TEST_RUNTIME="$test_dir/runtime" node --test "$project_dir/tests/provider-credentials.test.mjs" "$project_dir/tests/local-credentials-unlock.test.mjs" "$project_dir/tests/engine-reset.test.mjs"
node "$project_dir/tests/provider-credentials-live.mjs" "$test_dir/runtime"
