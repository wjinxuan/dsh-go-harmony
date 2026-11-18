#!/bin/sh
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
archive=${1:-"$project/entry/src/main/resources/rawfile/dsh-runtime.zip"}
node "$project/tests/require-runtime-node.mjs"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
unzip -q "$archive" -d "$stage"
DSH_RTC_TEST_RUNTIME="$stage" node --jitless --no-addons --test "$project/tests/dsh-remote-rtc.test.mjs"
