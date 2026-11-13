#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/dsh" "$test_dir/local" "$test_dir/ui"
cp "$project_dir/entry/src/main/ets/dsh/DshWire.ets" "$test_dir/dsh/DshWire.ts"
sed -e "s|'@kit.ArkTS'|'../onboarding-fixture.mjs'|" \
  -e "s|'@kit.AssetStoreKit'|'../onboarding-fixture.mjs'|" \
  -e '/^import { BusinessError } /d' -e "s|'../dsh/DshWire'|'../dsh/DshWire.ts'|" \
  "$project_dir/entry/src/main/ets/local/LocalKeyStore.ets" > "$test_dir/local/LocalKeyStore.ts"
sed -e '/^import { common } /d' -e "s|'@kit.ArkData'|'../onboarding-fixture.mjs'|" \
  -e "s|'./DshTheme'|'../onboarding-fixture.mjs'|" \
  "$project_dir/entry/src/main/ets/ui/AppPreferences.ets" > "$test_dir/ui/AppPreferences.ts"
cp "$project_dir/tests/onboarding.test.mjs" "$project_dir/tests/onboarding-fixture.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/onboarding.test.mjs" "$@"
