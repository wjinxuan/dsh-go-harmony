#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/ui" "$test_dir/dsh"
sed -e "s|, SpeechCatalog, SpeechMode||" -e "s|'../dsh/SpeechData'|'../dsh/SpeechData.ts'|" \
  "$project_dir/entry/src/main/ets/ui/VoiceData.ets" > "$test_dir/ui/VoiceData.ts"
sed -e "s|'@kit.AbilityKit'|'../voice-fixture.mjs'|" -e "s|'@kit.AudioKit'|'../voice-fixture.mjs'|" \
  -e "s|'@kit.CoreSpeechKit'|'../voice-fixture.mjs'|" -e "s|'@kit.BasicServicesKit'|'../voice-fixture.mjs'|" \
  -e 's|VoiceBridge, VoiceCapabilities, VoiceEvent, ||' -e "s|'./VoiceData'|'./VoiceData.ts'|" \
  "$project_dir/entry/src/main/ets/ui/VoiceInput.ets" > "$test_dir/ui/VoiceInput.ts"
sed "s|'./DshWire'|'./DshWire.ts'|" "$project_dir/entry/src/main/ets/dsh/SpeechData.ets" > "$test_dir/dsh/SpeechData.ts"
cp "$project_dir/entry/src/main/ets/dsh/DshWire.ets" "$test_dir/dsh/DshWire.ts"
cp "$project_dir/tests/voice-fixture.mjs" "$project_dir/tests/voice.test.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/voice.test.mjs"
