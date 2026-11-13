#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/ui" "$test_dir/dsh"
cp "$project_dir/entry/src/main/ets/dsh/DshWire.ets" "$test_dir/dsh/DshWire.ts"
sed -e 's|DshModelInfo, DshModelSelection, DshProviderGroup, DshSessionProjections, ||' \
  -e "s|'../dsh/DshWire'|'../dsh/DshWire.ts'|" \
  "$project_dir/entry/src/main/ets/ui/ModelSelectionData.ets" > "$test_dir/ui/ModelSelectionData.ts"
awk '/^  @Builder/ { print "}"; exit } { print }' "$project_dir/entry/src/main/ets/ui/ModelPanel.ets" |
  sed -e "s|'../dsh/DshClient'|'../model-panel-fixture.mjs'|" \
    -e '/^import {$/,/from .*DshWire/d' -e "s|from './DshTheme'|from '../model-panel-fixture.mjs'|" \
    -e 's|ThemeColors, themeColors, DshGlyphs|themeColors|' \
    -e "s|'./ModelSelectionData'|'./ModelSelectionData.ts'|" \
    -e '/^@Component/d' -e 's/^export struct /export class /' \
    -e "s/@Prop @Watch('sessionChanged') //; s/@Prop //; s/@State //" > "$test_dir/ui/ModelPanel.ts"
cp "$project_dir/tests/model-panel.test.mjs" "$project_dir/tests/model-panel-fixture.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/model-panel.test.mjs" "$@"
