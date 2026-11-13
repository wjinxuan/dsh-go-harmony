#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/dsh" "$test_dir/remote"
cp "$project_dir/entry/src/main/ets/dsh/DshWire.ets" "$test_dir/dsh/DshWire.ts"
sed -e "/^import { common } /d" -e "/^import { BusinessError } /d" \
  -e "s|'@kit.ArkData'|'../remote-hosts-fixture.mjs'|" \
  -e "s|'@kit.ArkTS'|'../remote-hosts-fixture.mjs'|" \
  -e "s|'@kit.AssetStoreKit'|'../remote-hosts-fixture.mjs'|" \
  -e 's|, WireObject }| }|' -e "s|'../dsh/DshWire'|'../dsh/DshWire.ts'|" \
  "$project_dir/entry/src/main/ets/remote/RemoteHosts.ets" > "$test_dir/remote/RemoteHosts.ts"
cp "$project_dir/tests/remote-hosts.test.mjs" "$project_dir/tests/remote-hosts-fixture.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/remote-hosts.test.mjs" "$@"
