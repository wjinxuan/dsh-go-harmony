#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
"${CXX:-c++}" -std=c++20 -Wall -Wextra -Werror -I "$project_dir/entry/src/main/cpp" "$project_dir/tests/native/deletion-marker.cpp" -o "$scratch/deletion-marker"
"$scratch/deletion-marker"
