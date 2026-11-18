#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
node --test "$project_dir/tests/session-deletion-core.test.mjs" "$project_dir/tests/session-deletion-patch.test.mjs"
if [ -n "${DSH_DELETION_RUNTIME:-}" ]; then
 DSH_PREFIX="$DSH_DELETION_RUNTIME" node --require "$project_dir/tests/local-flock-fixture.cjs" --test "$project_dir/tests/session-deletion-inbox.test.mjs" "$project_dir/tests/session-deletion-durability.test.mjs"
fi
