#!/usr/bin/env bash
# Run a heavy command (install, tests, build, typecheck, local E2E) while
# holding a machine-wide lock, so parallel sessions never run two at once.
#
#   heavy.sh <command> [args...]
#
# Exits with the command's exit code. The lock is a directory; its "info" file
# holds the holder's pid, process start time and command, written in one
# rename so a reader never sees it half-done. A lock whose pid is gone, or
# whose pid now belongs to another process (start time differs), is stale.
# Taking over a stale lock happens under a second "reap" lock, re-checked
# inside, so two waiters never both remove and recreate it.
#
# HEAVY_LOCK      lock path (default ${XDG_STATE_HOME:-$HOME/.local/state}/claude-heavy.lock)
# HEAVY_POLL_SEC  seconds between attempts (default 5)
set -euo pipefail

[ $# -gt 0 ] || { echo "usage: heavy.sh <command> [args...]" >&2; exit 2; }

lock="${HEAVY_LOCK:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-heavy.lock}"
reap="$lock.reap"
poll="${HEAVY_POLL_SEC:-5}"
grace=10 # seconds a lock or reap dir without info may stay before it counts as abandoned
mkdir -p "$(dirname "$lock")"

started() { ps -o lstart= -p "$1" 2>/dev/null || true; }

# age <path>: seconds since last change; fails when the path is gone.
age() {
  local m
  m="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)" || return 1
  echo $(( $(date +%s) - m ))
}

# is_stale: the current lock belongs to nobody alive. A lock that vanished
# meanwhile is not stale (the next mkdir decides).
is_stale() {
  local pid start a
  if [ ! -f "$lock/info" ]; then
    a="$(age "$lock")" || return 1
    [ "$a" -gt "$grace" ]
    return
  fi
  { IFS= read -r pid; IFS= read -r start; } <"$lock/info" 2>/dev/null || return 1
  kill -0 "$pid" 2>/dev/null || return 0
  [ "$(started "$pid")" != "$start" ]
}

take_over() {
  if ! mkdir "$reap" 2>/dev/null; then
    a="$(age "$reap")" && [ "$a" -gt "$grace" ] && rmdir "$reap" 2>/dev/null
    return 0
  fi
  is_stale && rm -rf "$lock"
  rmdir "$reap"
}

me_start="$(started "$$")"
announced=""
until mkdir "$lock" 2>/dev/null; do
  if is_stale; then
    take_over
    continue
  fi
  if [ -z "$announced" ]; then
    echo "waiting for heavy lock held by $(sed -n 3p "$lock/info" 2>/dev/null || echo '?') (pid $(sed -n 1p "$lock/info" 2>/dev/null || echo '?'))" >&2
    announced=1
  fi
  sleep "$poll"
done

printf '%s\n%s\n%s\n' "$$" "$me_start" "$*" >"$lock/info.$$"
mv "$lock/info.$$" "$lock/info"

child=""
release() {
  # Only remove the lock if it is still ours.
  [ "$(sed -n 1p "$lock/info" 2>/dev/null)" = "$$" ] && rm -rf "$lock"
  return 0
}
on_signal() {
  if [ -n "$child" ]; then
    kill -TERM "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
  fi
  exit 143
}
trap release EXIT
trap on_signal INT TERM

# Background + wait, so a TERM to this script is handled at once instead of
# after the command finishes.
"$@" &
child=$!
rc=0
wait "$child" || rc=$?
exit "$rc"
