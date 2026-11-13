#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
sed "1s/^import /import type /;1s|../dsh/DshWire|./DshWire.ts|" "$project_dir/entry/src/main/ets/ui/QuestionDrafts.ets" > "$test_dir/QuestionDrafts.ts"
cp "$project_dir/entry/src/main/ets/dsh/DshWire.ets" "$test_dir/DshWire.ts"
cp "$project_dir/entry/src/main/ets/ui/ComposerDrafts.ets" "$test_dir/ComposerDrafts.ts"
sed "1s/^import /import type /;1s|../dsh/DshWire|./DshWire.ts|" "$project_dir/entry/src/main/ets/ui/ChatProgress.ets" > "$test_dir/ChatProgress.ts"
cp "$project_dir/tests/question-drafts.test.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-transform-types "$test_dir/question-drafts.test.mjs"
