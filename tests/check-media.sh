#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node --disable-warning=ExperimentalWarning --experimental-strip-types --test \
  "$project_dir/tests/media.test.mjs" "$project_dir/tests/media-parameter-reactivity.test.mjs" \
  "$project_dir/tests/media-result-state.test.mjs"
