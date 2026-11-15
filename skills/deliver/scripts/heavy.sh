#!/usr/bin/env bash
# Run a heavy command (install, tests, build, typecheck, local E2E) while
# holding a machine-wide lock, so parallel sessions never run two at once.
#
#   heavy.sh <command> [args...]
#
# Exits with the command's exit code. The lock is the file "info" inside the
# lock directory, holding the holder's pid, process start time and command.
# It is written complete under a temporary name and then hard-linked into
# place: link(2) creates the name only if it is absent, so exactly one caller
# wins and a reader never sees it half-done. The directory itself stays, and
# releasing the lock is one unlink. A lock whose pid is gone, or whose pid now
# belongs to another process (start time differs), is stale. Taking over a
# stale lock happens under a second "reap" guard, re-checked inside, so two
# waiters never both remove it.
#
# HEAVY_LOCK      lock path (default ${XDG_STATE_HOME:-$HOME/.local/state}/claude-heavy.lock)
# HEAVY_POLL_SEC  seconds between attempts (default 5)
# HEAVY_WAIT_MAX  give up waiting after this many seconds, exit 124 (default 7200)
#
# A command run under the lock sees HEAVY_LOCK_HELD; a nested heavy.sh call
# (e.g. an install inside an E2E block) then runs straight through.
set -euo pipefail

[ $# -gt 0 ] || { echo "usage: heavy.sh <command> [args...]" >&2; exit 2; }

if [ -n "${HEAVY_LOCK_HELD:-}" ]; then
  exec "$@"
fi

lock="${HEAVY_LOCK:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-heavy.lock}"
reap="$lock.reap"
poll="${HEAVY_POLL_SEC:-5}"
wait_max="${HEAVY_WAIT_MAX:-7200}"
info="$lock/info"
grace=10 # seconds a reap guard may stay before it counts as abandoned

started() { ps -o lstart= -p "$1" 2>/dev/null || true; }

# claim <path>: create the file only if it is not there yet. Bash opens it
# with O_EXCL itself, so exactly one caller wins.
claim() { ( set -C; : >"$1" ) 2>/dev/null; }

# age <path>: seconds since last change; fails when the path is gone.
age() {
  local m
  m="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)" || return 1
  echo $(( $(date +%s) - m ))
}

# is_stale: the current lock belongs to nobody alive. A lock that vanished
# meanwhile is not stale (the next acquire decides).
is_stale() {
  local pid start now
  { IFS= read -r pid; IFS= read -r start; } <"$info" 2>/dev/null || return 1
  if kill -0 "$pid" 2>/dev/null; then
    now="$(started "$pid")"
    # Same process, or ps printed nothing for a pid that is still there.
    if [ "$now" = "$start" ] || { [ -z "$now" ] && kill -0 "$pid" 2>/dev/null; }; then
      return 1
    fi
  fi
  # The holder looks gone, but checking took time (ps can be slow) and it may
  # simply have finished meanwhile, with the next holder already in place. A
  # holder that ends normally removes its info before it exits, so the lock is
  # stale only if info still names that same holder.
  [ "$(sed -n '1,2p' "$info" 2>/dev/null)" = "$pid"$'\n'"$start" ]
}

take_over() {
  local a
  if ! claim "$reap"; then
    # Another waiter is reaping; clear its guard only if it was abandoned.
    # rmdir too: a guard left by an older version of this script is a directory.
    if a="$(age "$reap")" && [ "$a" -gt "$grace" ]; then
      rm -f "$reap" 2>/dev/null || rmdir "$reap" 2>/dev/null || true
    fi
    return 0
  fi
  if is_stale; then rm -f "$info"; fi
  rm -f "$reap" 2>/dev/null || true
}

me_start="$(started "$$")"
cmd="$*"

# acquire: take the lock by linking a finished info file into place. Neither
# mkdir nor removing a directory decides anything here: racing mkdir calls can
# all succeed under uutils coreutils (Ubuntu 26.04), and a directory that is
# being removed can still be entered.
acquire() {
  local tmp="$lock/info.$$" rc=0
  mkdir -p "$lock" 2>/dev/null || return 1
  printf '%s\n%s\n%s\n' "$$" "$me_start" "$cmd" >"$tmp" 2>/dev/null || return 1
  ln "$tmp" "$info" 2>/dev/null || rc=1
  rm -f "$tmp"
  return "$rc"
}

announced=""
waited_since=$(date +%s)
until acquire; do
  if [ $(( $(date +%s) - waited_since )) -ge "$wait_max" ]; then
    echo "gave up waiting for heavy lock after ${wait_max}s: $lock" >&2
    exit 124
  fi
  if is_stale; then
    take_over
    if [ -e "$info" ]; then sleep "$poll"; fi
    continue
  fi
  if [ -z "$announced" ]; then
    echo "waiting for heavy lock held by $(sed -n 3p "$info" 2>/dev/null || echo '?') (pid $(sed -n 1p "$info" 2>/dev/null || echo '?'))" >&2
    announced=1
  fi
  sleep "$poll"
done

child=""
release() {
  # Only remove the lock if it is still ours.
  [ "$(sed -n 1p "$info" 2>/dev/null)" = "$$" ] && rm -f "$info"
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
HEAVY_LOCK_HELD=$$ "$@" &
child=$!
rc=0
wait "$child" || rc=$?
exit "$rc"
