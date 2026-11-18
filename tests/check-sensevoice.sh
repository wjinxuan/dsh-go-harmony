#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node --test "$project_dir/tests/sensevoice.test.mjs"
