'use strict';

const { createHash } = require('node:crypto');

function quote(value) {
  return "'" + value.replaceAll("'", "'\\''") + "'";
}

function bootstrapCommand(command, directory) {
  const key = createHash('sha256').update(JSON.stringify([command, directory])).digest('hex').slice(0, 24);
  const cwd = directory === '~' ? '"$HOME"' : directory.startsWith('~/') ? '"$HOME"/' + quote(directory.slice(2)) : quote(directory);
  const search = command === 'dsh web' ? `
if ! command -v dsh >/dev/null 2>&1; then
  for p in "$HOME/.local/bin" "$HOME/.npm-global/bin" "$HOME/.npm/bin" "$HOME/.volta/bin" "$HOME/.bun/bin" \\
    "$HOME/.local/share/pnpm" "$HOME/Library/pnpm" /usr/local/bin /opt/homebrew/bin \\
    "$HOME"/.nvm/versions/node/*/bin "$HOME"/.local/share/fnm/node-versions/*/installation/bin; do
    [ ! -x "$p/dsh" ] || PATH="$p:$PATH"
  done
  export PATH
fi
command -v dsh >/dev/null 2>&1 || { printf 'DSHAPP no-dsh\\n'; exit 127; }
` : '';
  // Distinct working directories and commands can be used by separate clients without stopping each other.
  return `sh -c ${quote(`
umask 077
D="$HOME/.dsh-harmony-remote/${key}"
mkdir -p "$D" && chmod 700 "$D" || { printf 'DSHAPP state-error\\n'; exit 1; }
_start() {
  if [ -r "/proc/$1/stat" ]; then
    S=$(cat "/proc/$1/stat") || return 1
    S=\${S##*) }
    set -- $S
    [ "$#" -ge 20 ] || return 1
    shift 19
    printf '%s\\n' "$1"
  else
    ps -p "$1" -o lstart= 2>/dev/null
  fi
}
owned() {
  case "$1" in ''|0*|*[!0-9]*) return 1;; esac
  [ "$1" -gt 1 ] 2>/dev/null && kill -0 "$1" 2>/dev/null || return 1
  A=$(_start "$1") || return 1
  [ -n "$A" ] && [ "$A" = "$2" ]
}
ready() {
  L=$(grep '^dsh web: http://127\\.0\\.0\\.1:' "$D/web.log" 2>/dev/null | tail -n 1)
  [ -n "$L" ] || return 1
  printf 'DSHAPP ready %s\\n' "$L"
}
LOCK="$$:$(_start "$$")"
i=0
while ! ln -s "$LOCK" "$D/lock" 2>/dev/null; do
  if mkdir "$D/reclaim" 2>/dev/null; then
    PREVIOUS=$(readlink "$D/lock" 2>/dev/null)
    case "$PREVIOUS" in
      *:*)
        if ! owned "\${PREVIOUS%%:*}" "\${PREVIOUS#*:}" && [ "$(readlink "$D/lock" 2>/dev/null)" = "$PREVIOUS" ]; then
          rm -f "$D/lock"
        fi;;
    esac
    rmdir "$D/reclaim"
  fi
  [ "$i" -lt 55 ] || { printf 'DSHAPP busy\\n'; exit 1; }
  sleep 1; i=$((i+1))
done
trap '[ "$(readlink "$D/lock" 2>/dev/null)" != "$LOCK" ] || rm -f "$D/lock"' EXIT
trap 'exit 1' HUP INT TERM
P=$(cat "$D/web.pid" 2>/dev/null)
STAMP=$(cat "$D/web.st" 2>/dev/null)
if owned "$P" "$STAMP"; then
  ready && exit 0
  printf 'DSHAPP busy\\n'; exit 1
fi
${directory ? `cd ${cwd} || { printf 'DSHAPP bad-directory\\n'; exit 1; }` : ''}
${search}
NO_COLOR=1; export NO_COLOR
: > "$D/web.log" || exit 1
nohup sh -c ${quote(`exec ${command} --host 127.0.0.1 --port 0 --no-open`)} </dev/null >>"$D/web.log" 2>&1 &
P=$!
STAMP=$(_start "$P") && printf '%s\\n' "$STAMP" > "$D/web.st" && printf '%s\\n' "$P" > "$D/web.pid" || exit 1
i=0
while [ "$i" -lt 55 ]; do
  if ! owned "$P" "$STAMP"; then printf 'DSHAPP exited\\n'; exit 1; fi
  ready && exit 0
  sleep 1; i=$((i+1))
done
printf 'DSHAPP timeout\\n'; exit 1
`)}`;
}

function parseLaunch(stdout) {
  const match = /^DSHAPP ready dsh web: http:\/\/127\.0\.0\.1:([1-9]\d{0,4})\/\?token=([A-Za-z0-9%._~=-]{1,512})\r?$/m.exec(stdout);
  if (match && Number(match[1]) <= 65535) {
    return { port: Number(match[1]), token: match[2] };
  }
  const code = /^DSHAPP (no-dsh|bad-directory|state-error|busy|exited|timeout)\r?$/m.exec(stdout)?.[1];
  throw new Error(code || 'launch-invalid');
}

module.exports = { bootstrapCommand, parseLaunch };
