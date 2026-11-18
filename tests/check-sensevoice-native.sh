#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
models=${1:?Pass the verified model directory}
wave=${2:?Pass a Chinese 16 kHz PCM16 WAV fixture}
native_libs=${3:?Pass sherpa-onnx 1.13.8 host library directory}
headers="$project_dir/runtime/.sensevoice/sherpa-onnx-v1.13.8-ohos-arm64-v8a/include"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/home/speech-to-text/sensevoice"
cp -R "$models" "$scratch/home/speech-to-text/sensevoice/models"
case "$(uname -s)" in
  Darwin) dynamic='-undefined dynamic_lookup' ;;
  Linux) dynamic='' ;;
  *) printf '%s\n' 'This native harness supports macOS and Linux.' >&2; exit 1 ;;
esac
"${CXX:-c++}" -std=c++20 -shared -fPIC $dynamic -I "$project_dir/entry/src/main/cpp" \
  -isystem "$project_dir/runtime/.node/include/node" -I "$headers" \
  "$project_dir/tests/native/sensevoice-addon.cpp" "$project_dir/entry/src/main/cpp/sensevoice_engine.cpp" \
  "$project_dir/entry/src/main/cpp/sensevoice_bridge.cpp" -L "$native_libs" -lsherpa-onnx-c-api \
  "-Wl,-rpath,$native_libs" -o "$scratch/sensevoice.node"
node "$project_dir/tests/sensevoice-bridge.mjs" "$scratch/sensevoice.node" "$scratch/home" "$wave"
