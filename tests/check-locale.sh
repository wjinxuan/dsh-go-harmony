#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
cp "$project_dir/entry/src/main/ets/ui/SettingsLocaleData.ets" "$test_dir/SettingsLocaleData.ts"
cp "$project_dir/tests/locale.test.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/locale.test.mjs" "$project_dir"
