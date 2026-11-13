#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
cp "$project_dir/entry/src/main/ets/ui/SessionExportData.ets" "$test_dir/SessionExportData.ts"
cp "$project_dir/tests/session-export.test.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-transform-types "$test_dir/session-export.test.mjs" "$@"
