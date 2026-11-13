#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/ui/settings" "$test_dir/dsh"
cp "$project_dir/entry/src/main/ets/dsh/DshWire.ets" "$test_dir/dsh/DshWire.ts"
sed -e 's|, WireObject }| }|' -e "s|'../../dsh/DshWire'|'../../dsh/DshWire.ts'|" \
  "$project_dir/entry/src/main/ets/ui/settings/SettingsSchema.ets" > "$test_dir/ui/settings/SettingsSchema.ts"
sed '/^import { WireObject } /d' "$project_dir/entry/src/main/ets/ui/settings/ProviderDraft.ets" \
  > "$test_dir/ui/settings/ProviderDraft.ts"
cp "$project_dir/tests/settings.test.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/settings.test.mjs" "$@"
