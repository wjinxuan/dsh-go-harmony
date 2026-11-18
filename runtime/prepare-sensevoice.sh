#!/bin/sh
set -eu
runtime_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cache="$runtime_dir/.sensevoice"
libs="$runtime_dir/../entry/libs/arm64-v8a"
mkdir -p "$cache" "$libs"
archive="$cache/sherpa-onnx-v1.13.8-ohos-arm64-v8a.tar.bz2"
if [ ! -f "$archive" ]; then
  curl --fail --location --retry 3 'https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-ohos-arm64-v8a.tar.bz2' -o "$archive.tmp"
  mv "$archive.tmp" "$archive"
fi
(cd "$cache" && shasum -a 256 -c <<'SUMS'
7473e1f6138c2d33a26adda01dd94f4d618089370957ed374f8cc0d50b8cdfa7  sherpa-onnx-v1.13.8-ohos-arm64-v8a.tar.bz2
SUMS
)
tar -xjf "$archive" -C "$cache"
source_dir="$cache/sherpa-onnx-v1.13.8-ohos-arm64-v8a"
cp "$source_dir/lib/libsherpa-onnx-c-api.so" "$source_dir/lib/libonnxruntime.so" "$libs/"
printf '%s\n' 'OHOS SenseVoice runtime prepared (sherpa-onnx 1.13.8)'
