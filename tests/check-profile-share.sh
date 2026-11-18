#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
node --disable-warning=ExperimentalWarning --test "$project_dir/tests/profile-share.test.mjs" "$project_dir/tests/profile-share-controller.test.mjs"
# Optional official DSH bin: runs a fresh isolated host without model/provider traffic.
if [ "$#" -gt 0 ]; then
  node "$project_dir/tests/profile-share-provider-live.mjs" "$1"
fi
