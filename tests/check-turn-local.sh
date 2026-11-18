#!/bin/sh
# Real coturn on loopback. Use an installed server, or build the hash-pinned
# source in a disposable directory; nothing is installed or registered as a service.
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
archive=${1:-"$project/entry/src/main/resources/rawfile/dsh-runtime.zip"}
node_bin=$(command -v node)
"$node_bin" "$project/tests/require-runtime-node.mjs"
stage=$(mktemp -d)
runner=
cleanup() {
  if [ -n "$runner" ]; then kill -TERM "$runner" 2>/dev/null || true; wait "$runner" 2>/dev/null || true; fi
  rm -rf "$stage"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
server=${DSH_TURN_SERVER:-}
if [ -z "$server" ]; then server=$(command -v turnserver || true); fi
if [ -n "$server" ]; then
  server=$(command -v "$server" || true)
  if [ -z "$server" ] || [ ! -x "$server" ]; then
    echo 'DSH_TURN_SERVER must name an executable coturn turnserver.' >&2
    exit 1
  fi
else
  # libevent and matching OpenSSL development libraries, pkgconf/pkg-config,
  # a C compiler and make are the only build requirements. On this Mac:
  # brew install pkgconf libevent openssl@3
  # Optionally set PKG_CONFIG_PATH for nonstandard dependency prefixes.
  for directory in /opt/homebrew/bin /usr/local/bin; do
    if [ -d "$directory" ]; then PATH="$directory:$PATH"; fi
  done
  export PATH
  if ! command -v pkgconf >/dev/null 2>&1 && ! command -v pkg-config >/dev/null 2>&1; then
    echo 'Install pkgconf (or pkg-config), libevent and OpenSSL development dependencies, or set DSH_TURN_SERVER.' >&2
    exit 1
  fi
  if command -v brew >/dev/null 2>&1; then
    ssl=$(brew --prefix openssl@3 2>/dev/null || true)
    event=$(brew --prefix libevent 2>/dev/null || true)
    if [ -n "$ssl" ] && [ -n "$event" ]; then
      PKG_CONFIG_PATH="$ssl/lib/pkgconfig:$event/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
      export PKG_CONFIG_PATH
    fi
  fi
  source="$stage/coturn.tar.gz"
  curl --fail --location --silent --show-error --connect-timeout 20 --max-time 120 \
    'https://github.com/coturn/coturn/archive/refs/tags/4.19.0.tar.gz' -o "$source"
  "$node_bin" --input-type=module -e 'import{readFileSync}from"node:fs";import{createHash}from"node:crypto";if(createHash("sha256").update(readFileSync(process.argv[1])).digest("hex")!=="988b0090f6f30782a7e19c974a9d85cbd70cc1cd4788d21c4361bc2603dbc13d")throw Error("coturn source checksum mismatch")' "$source"
  tar -xzf "$source" -C "$stage"
  echo 'Building hash-pinned coturn 4.19.0 in a temporary directory…'
  if ! (cd "$stage/coturn-4.19.0" && \
    TURN_NO_PQ=1 TURN_NO_MYSQL=1 TURN_NO_MONGO=1 TURN_NO_HIREDIS=1 \
    TURN_NO_PROMETHEUS=1 TURN_NO_SYSTEMD=1 TURN_NO_SCTP=1 \
      ./configure --prefix="$stage/install" && make -j4) > "$stage/build.log" 2>&1; then
    cat "$stage/build.log" >&2
    exit 1
  fi
  server="$stage/coturn-4.19.0/bin/turnserver"
fi
"$node_bin" "$project/tests/local-turn-fixture.mjs" "$server" "$archive" &
runner=$!
status=0
wait "$runner" || status=$?
runner=
exit "$status"
