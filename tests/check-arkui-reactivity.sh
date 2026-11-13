#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
generated=${1:-"$project_dir/entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/ui"}
node "$project_dir/tests/arkui-reactivity.test.mjs" "$generated"
