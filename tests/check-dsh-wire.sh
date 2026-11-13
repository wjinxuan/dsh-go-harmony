#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
cp "$project_dir/tests/dsh-wire.test.mjs" "$test_dir/"
cp "$project_dir/entry/src/main/ets/dsh/DshWire.ets" "$test_dir/DshWire.ts"
cp "$project_dir/entry/src/main/ets/ui/ChatTimeline.ets" "$test_dir/ChatTimeline.ts"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/dsh-wire.test.mjs" "$@"
