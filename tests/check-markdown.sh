#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
cp "$project_dir/tests/markdown.test.mjs" "$test_dir/"
cp "$project_dir/entry/src/main/ets/ui/MarkdownBlocks.ets" "$test_dir/MarkdownBlocks.ts"
node --disable-warning=ExperimentalWarning --experimental-transform-types "$test_dir/markdown.test.mjs" "$@"
