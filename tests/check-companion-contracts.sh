#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
node --disable-warning=ExperimentalWarning --test "$project_dir/tests/companion-contracts.test.mjs" "$project_dir/tests/companion-recall-patch.test.mjs" "$project_dir/tests/companion-recall-markers.test.mjs" "$project_dir/tests/companion-recall-live-fixture.test.mjs" "$project_dir/tests/companion-signals.test.mjs" "$project_dir/tests/companion-signal-settings.test.mjs"
