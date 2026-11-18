#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
node --test "$project_dir/tests/quick-panel-reactivity.test.mjs"
node --test "$project_dir/tests/workspace-panel-reactivity.test.mjs"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/ui" "$test_dir/dsh"
for name in WorkspaceViewData NewChatOptionsData ShellNavigationData; do
  sed "s|'../dsh/DshWire'|'../dsh/DshWire.ts'|g" "$project_dir/entry/src/main/ets/ui/$name.ets" > "$test_dir/ui/$name.ts"
done
cp "$project_dir/entry/src/main/ets/dsh/DshWire.ets" "$test_dir/dsh/DshWire.ts"
cp "$project_dir/tests/workspace-shell.test.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/workspace-shell.test.mjs"
