#!/bin/sh
set -eu

if [ "$(uname -s)" != Linux ]; then
  printf '%s\n' 'Native publication checks require Linux and a matching Linux libnode.' >&2
  exit 1
fi

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
headers=${1:-"$project_dir/runtime/.node/include/node"}
node_library=${2:-'-Wl,-l:libnode.so.137'}
if [ ! -f "$headers/node.h" ]; then
  printf 'Node headers not found in %s. Pass a matching Node include directory as the first argument.\n' "$headers" >&2
  exit 1
fi

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
native_dir=$project_dir/entry/src/main/cpp
fixture_dir=$project_dir/tests/native
"${CXX:-c++}" -std=c++20 -I"$native_dir" -I"$fixture_dir/include" -isystem "$headers" \
  "$fixture_dir/runner.cpp" "$native_dir/node_engine.cpp" "$node_library" -luv -pthread -o "$scratch/runner"

mkdir "$scratch/data"
timeout 30s "$scratch/runner" "$project_dir/tests/native-workspace-publish.cjs" "$scratch/data"
timeout 30s "$scratch/runner" "$fixture_dir/session-publish.cjs" "$scratch/data"
timeout 30s "$scratch/runner" "$fixture_dir/attachment-publish.cjs" "$scratch/data"
timeout 30s "$scratch/runner" "$fixture_dir/recall-marker.cjs" "$scratch/data"
timeout 30s "$scratch/runner" "$fixture_dir/file-lock.cjs" "$scratch/data"

if [ -n "${DSH_NATIVE_TEST_RUNTIME:-}" ]; then
  timeout 30s "$scratch/runner" "$fixture_dir/attachment-store.cjs" "$scratch/data"
  DSH_LOCAL_ENGINE_TEST_RUNNER="$scratch/runner" node "$project_dir/tests/local-engine-smoke.mjs" \
    "$DSH_NATIVE_TEST_RUNTIME" --deepseek --tools --danger-full-access --compact
fi
