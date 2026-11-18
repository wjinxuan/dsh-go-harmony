#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/ui/settings" "$test_dir/dsh"
sed "s|'../dsh/DshWire'|'../dsh/DshWire.ts'|g" "$project_dir/entry/src/main/ets/ui/SubscriptionData.ets" > "$test_dir/ui/SubscriptionData.ts"
sed "s|'../../dsh/DshWire'|'../../dsh/DshWire.ts'|g" "$project_dir/entry/src/main/ets/ui/settings/ProviderModelData.ets" > "$test_dir/ui/settings/ProviderModelData.ts"
cp "$project_dir/entry/src/main/ets/dsh/DshWire.ets" "$test_dir/dsh/DshWire.ts"
cp "$project_dir/tests/subscriptions.test.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/subscriptions.test.mjs"
