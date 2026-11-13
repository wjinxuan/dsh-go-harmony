#!/usr/bin/env bash
set -euo pipefail

runtime_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
node_dir="$runtime_dir/.node"
libs_dir="$runtime_dir/../entry/libs/arm64-v8a"
version=24.22.1
node_hash=efd4a03096bde322d1c171361a8a1d7b208ea34ddc70ae907e660750c56e6acf
libcxx_hash=60bce7be77b6dbb7be3151a14e5b0f83f04ee29d641dba025b8c1b7207e93d34

hash_is() {
  [[ -f "$2" ]] && [[ $(shasum -a "$1" "$2" | cut -d ' ' -f 1) == "$3" ]]
}

if [[ -f "$node_dir/prepared" && -f "$node_dir/include/node/node.h" ]] &&
  hash_is 256 "$libs_dir/libnode.so" "$node_hash" &&
  hash_is 256 "$libs_dir/libc++_shared.so" "$libcxx_hash"; then
  printf 'Node %s for HarmonyOS arm64 is already prepared.\n' "$version"
  exit 0
fi

mkdir -p "$node_dir"
stage=$(mktemp -d "$node_dir/staging.XXXXXXXX")
trap 'rm -rf "$stage"' EXIT

fetch() {
  curl --fail --silent --show-error --location --retry 2 --connect-timeout 10 \
    --max-time 300 "$1" --output "$stage/$2"
  if ! hash_is "$3" "$stage/$2" "$4"; then
    printf 'Checksum mismatch: %s\n' "$2" >&2
    exit 1
  fi
}

fetch "https://ohpm.openharmony.cn/ohpm/@fellow99/node-runtime/-/node-runtime-$version.har" \
  runtime.har 512 f07f36b4fac164b50ca0d0bb08f7a694136487c6bd9e8ee1e6b2b1426887c4e1009d7140ed4e62da8932225da2065dee93474c026928ed773e5ab5ba80e5bac1
fetch "https://nodejs.org/dist/v$version/node-v$version-headers.tar.gz" \
  headers.tgz 256 322e0a27db9088093ab8347bdc8c7e0aaa21dc9ed548390bf06b394494c09267

archive_libs=package/libs/arm64-v8a
tar -xf "$stage/runtime.har" -C "$stage" "$archive_libs/libnode.so" "$archive_libs/libc++_shared.so"
tar -xf "$stage/headers.tgz" -C "$stage" "node-v$version/include/node"
staged_libs="$stage/$archive_libs"
if ! hash_is 256 "$staged_libs/libnode.so" c3aad4381cdfc940db165b7497ebf0d6ad290abf2e5a79ee33db4bfe107724e3 ||
  ! hash_is 256 "$staged_libs/libc++_shared.so" "$libcxx_hash"; then
  printf 'Checksum mismatch in HarmonyOS native libraries.\n' >&2
  exit 1
fi

python3 - "$staged_libs/libnode.so" <<'PY'
import sys
from pathlib import Path

library = Path(sys.argv[1])
data = bytearray(library.read_bytes())
# Hvigor packages .so files. Match the loader name without moving any ELF offsets.
soname = b'\0libnode.so.137\0'
if data.count(soname) != 1:
    sys.exit('Expected exactly one versioned libnode SONAME')
data = data.replace(soname, b'\0libnode.so'.ljust(len(soname), b'\0'))

# shortcut: exact pinned ARM64 libuv only, remove when rebuilding libuv with io_uring disabled for OHOS.
# Both rings use this call. The caller only checks for -1 and falls back to epoll.
offset = 0x433e3e4
if data[offset - 8:offset + 4] != bytes.fromhex('20358052 e103152a 2bcd9f94'):
    sys.exit('Expected the pinned ARM64 io_uring_setup call')
data[offset:offset + 4] = bytes.fromhex('00008092')  # mov x0, #-1
library.write_bytes(data)
PY
if ! hash_is 256 "$staged_libs/libnode.so" "$node_hash" ||
  [[ ! -f "$stage/node-v$version/include/node/node.h" ]]; then
  printf 'Prepared libnode or Node headers failed verification.\n' >&2
  exit 1
fi

rm -f "$node_dir/prepared"
mkdir -p "$libs_dir"
mv -f "$staged_libs/libnode.so" "$libs_dir/libnode.so"
mv -f "$staged_libs/libc++_shared.so" "$libs_dir/libc++_shared.so"
rm -rf "$node_dir/include"
mv "$stage/node-v$version/include" "$node_dir/include"
touch "$node_dir/prepared"
printf 'Prepared Node %s for HarmonyOS arm64.\n' "$version"
