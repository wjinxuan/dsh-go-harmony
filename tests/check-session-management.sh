#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/ui" "$test_dir/dsh"
sed -e 's|, DshSession, DshSessionSearchHit, WireObject }| }|' -e "s|'../dsh/DshWire'|'../dsh/DshWire.ts'|" \
  "$project_dir/entry/src/main/ets/ui/SessionManagementData.ets" > "$test_dir/ui/SessionManagementData.ts"
cp "$project_dir/entry/src/main/ets/dsh/DshWire.ets" "$test_dir/dsh/DshWire.ts"
cp "$project_dir/tests/session-management.test.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-transform-types "$test_dir/session-management.test.mjs" "$@"
