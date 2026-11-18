#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
node --disable-warning=ExperimentalWarning "$project_dir/tests/bundled-bot-lifecycle.test.mjs"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/ui" "$test_dir/dsh"
cp "$project_dir/entry/src/main/ets/dsh/DshWire.ets" "$test_dir/dsh/DshWire.ts"
sed -e 's/, WireObject//' -e "s|'./DshWire'|'./DshWire.ts'|" "$project_dir/entry/src/main/ets/dsh/DsBotProtocol.ets" > "$test_dir/dsh/DsBotProtocol.ts"
for name in DSBotData DSBotViewData; do
 sed -e 's/, WireObject//' -e "/^import { DsBotEvent }/d" -e "s|'../dsh/DshWire'|'../dsh/DshWire.ts'|" "$project_dir/entry/src/main/ets/ui/$name.ets" > "$test_dir/ui/$name.ts"
done
cp "$project_dir/tests/dsbot.test.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/dsbot.test.mjs" "$project_dir/tests/fixtures/dsbot"

node --test "$project_dir/tests/dsbot-schedules.test.mjs"
node --test "$project_dir/tests/dsbot-chat-layout.test.mjs"
