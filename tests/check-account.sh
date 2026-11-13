#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/dsh" "$test_dir/ui"
cp "$project_dir/entry/src/main/ets/dsh/DshWire.ets" "$test_dir/dsh/DshWire.ts"
source="$project_dir/entry/src/main/ets/ui/AccountData.ets"
sed -e "s|'../dsh/DshWire'|'../dsh/DshWire.ts'|" -e 's|, WireObject }| }|' \
  "$source" > "$test_dir/ui/AccountData.ts"
cp "$project_dir/tests/account.test.mjs" "$project_dir/tests/dsh-client-node-fixture.mjs" "$test_dir/"
if [ "$#" -gt 0 ]; then
  node "$project_dir/tests/require-runtime-node.mjs"
  unzip -q "$1" -d "$test_dir/runtime"
  set -- "$test_dir" "$project_dir/entry/src/main/ets/dsh/DshClient.ets" "$project_dir/tests/local-flock-fixture.cjs"
fi
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/account.test.mjs" "$@"
