#!/usr/bin/env bash
# Run a heavy command (install, tests, build, typecheck, local E2E) while
# holding a machine-wide lock, so parallel sessions never run two at once.
#
#   heavy.sh <command> [args...]
#
# Exits with the command's exit code. The lock is a directory holding the
# holder's pid, its process start time and the command. A lock whose pid is
# gone, or whose pid now belongs to a different process (start time differs),
# is stale and taken over.
#
# HEAVY_LOCK      lock path (default ${XDG_STATE_HOME:-$HOME/.local/state}/claude-heavy.lock)
# HEAVY_POLL_SEC  seconds between attempts (default 5)
set -euo pipefail

[ $# -gt 0 ] || { echo "usage: heavy.sh <command> [args...]" >&2; exit 2; }

lock="${HEAVY_LOCK:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-heavy.lock}"
poll="${HEAVY_POLL_SEC:-5}"
mkdir -p "$(dirname "$lock")"

started() { ps -o lstart= -p "$1" 2>/dev/null || true; }

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

is_stale() {
  local pid start
  pid="$(cat "$lock/pid" 2>/dev/null || true)"
  if [ -z "$pid" ]; then
    # Crash between mkdir and writing pid: stale once older than 10 s.
    [ $(( $(date +%s) - $(mtime "$lock") )) -gt 10 ]
    return
  fi
  kill -0 "$pid" 2>/dev/null || return 0
  start="$(cat "$lock/start" 2>/dev/null || true)"
  [ "$(started "$pid")" != "$start" ]
}

announced=""
until mkdir "$lock" 2>/dev/null; do
  if is_stale; then
    rm -rf "$lock"
    continue
  fi
  if [ -z "$announced" ]; then
    echo "waiting for heavy lock held by $(cat "$lock/cmd" 2>/dev/null || echo '?') (pid $(cat "$lock/pid" 2>/dev/null || echo '?'))" >&2
    announced=1
  fi
  sleep "$poll"
done

child=""
release() { rm -rf "$lock"; }
on_signal() {
  [ -n "$child" ] && kill -TERM "$child" 2>/dev/null || true
  release
  exit 143
}
trap release EXIT
trap on_signal INT TERM

echo "$$" >"$lock/pid"
started "$$" >"$lock/start"
echo "$*" >"$lock/cmd"

# Background + wait, so a TERM to this script is handled at once instead of
# after the command finishes.
"$@" &
child=$!
rc=0
wait "$child" || rc=$?
exit "$rc"
