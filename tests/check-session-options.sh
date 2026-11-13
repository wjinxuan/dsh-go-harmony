#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
cp "$project_dir/entry/src/main/ets/ui/SessionPermissionCopy.ets" "$test_dir/SessionPermissionCopy.ts"
cp "$project_dir/tests/session-options.test.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/session-options.test.mjs" "$@"
