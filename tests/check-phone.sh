#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
sed "s|'../dsh/DshWire'|'./DshWire.ts'|g" "$project_dir/entry/src/main/ets/phone/PhoneData.ets" > "$test_dir/PhoneData.ts"
sed "s|'../dsh/DshWire'|'./DshWire.ts'|g" "$project_dir/entry/src/main/ets/phone/PhoneAccessibilityData.ets" > "$test_dir/PhoneAccessibilityData.ts"
sed -E "s|'@kit\.[A-Za-z]+'|'./phone-platform-fixture.mjs'|g; s|'../dsh/DshWire'|'./DshWire.ts'|g; s|'./PhoneData'|'./PhoneData.ts'|g; s|'./PhoneAccessibilityFiles'|'./phone-platform-fixture.mjs'|g; s|'../local/PrivateDirectory'|'./PrivateDirectory.ts'|g" "$project_dir/entry/src/main/ets/phone/PhoneControl.ets" > "$test_dir/PhoneControl.ts"
cp "$project_dir/entry/src/main/ets/dsh/DshWire.ets" "$test_dir/DshWire.ts"
cp "$project_dir/entry/src/main/ets/phone/PhoneTaskData.ets" "$test_dir/PhoneTaskData.ts"
sed -E "s|'../dsh/DshWire'|'./DshWire.ts'|g; s|'./PhoneAccessibilityData'|'./PhoneAccessibilityData.ts'|g" "$project_dir/entry/src/main/ets/phone/PhoneCollect.ets" > "$test_dir/PhoneCollect.ts"
sed -E "s|'@kit\.[A-Za-z]+'|'./phone-platform-fixture.mjs'|g" "$project_dir/entry/src/main/ets/local/PrivateDirectory.ets" > "$test_dir/PrivateDirectory.ts"
cp "$project_dir/tests/phone.test.mjs" "$project_dir/tests/phone-platform-fixture.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/phone.test.mjs"
for source in PhoneAccessibilityAbility PhoneAccessibilityClient PhoneAccessibilityFiles; do
  sed -E "s|'@kit\.[A-Za-z]+'|'./phone-accessibility-fixture.mjs'|g; s|'@ohos.fileio'|'./phone-accessibility-fixture.mjs'|g; s|'../dsh/DshWire'|'./DshWire.ts'|g; s|'./(PhoneAccessibility[A-Za-z]+)'|'./\1.ts'|g; s|'./PhoneData'|'./PhoneData.ts'|g; s|'../local/PrivateDirectory'|'./PrivateDirectory.ts'|g" "$project_dir/entry/src/main/ets/phone/$source.ets" > "$test_dir/$source.ts"
done
sed -E "s|'@kit\.[A-Za-z]+'|'./phone-accessibility-fixture.mjs'|g" "$project_dir/entry/src/main/ets/local/PrivateDirectory.ets" > "$test_dir/PrivateDirectory.ts"
cp "$project_dir/tests/phone-accessibility-fixture.mjs" "$project_dir/tests/phone-accessibility.test.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/phone-accessibility.test.mjs"
sed -E "s|'@kit\.[A-Za-z]+'|'./phone-intent-fixture.mjs'|g; s|'../dsh/DshWire'|'./DshWire.ts'|g" "$project_dir/entry/src/main/ets/phone/PhoneIntent.ets" > "$test_dir/PhoneIntent.ts"
cp "$project_dir/tests/phone-intent-fixture.mjs" "$project_dir/tests/phone-intent.test.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/phone-intent.test.mjs"
sed -E "s|'@kit\.[A-Za-z]+'|'./phone-platform-fixture.mjs'|g; s|'../dsh/DshWire'|'./DshWire.ts'|g; s|'./PhoneControl'|'./PhoneControl.ts'|g; s|'./PhoneAccessibilityClient'|'./phone-platform-fixture.mjs'|g; s|'./PhoneAccessibilityData'|'./PhoneAccessibilityData.ts'|g" "$project_dir/entry/src/main/ets/phone/PhoneScreenImage.ets" > "$test_dir/PhoneScreenImage.ts"
cp "$project_dir/tests/phone-screen-image.test.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/phone-screen-image.test.mjs"
