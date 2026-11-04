#!/usr/bin/env bash
# Tests for skills/deliver/scripts/heavy.sh
set -euo pipefail

script="$(cd "$(dirname "$0")/../.." && pwd)/skills/deliver/scripts/heavy.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
export HEAVY_LOCK="$tmp/lock" HEAVY_POLL_SEC=0.1

# runs and propagates exit code
rc=0
"$script" sh -c 'exit 3' || rc=$?
[ "$rc" = "3" ] || fail "exit code $rc, want 3"
[ -e "$HEAVY_LOCK" ] && fail "lock left behind after run"

# serialises
log="$tmp/log"
"$script" sh -c "echo a1 >>'$log'; sleep 1; echo a2 >>'$log'" &
first=$!
sleep 0.3
"$script" sh -c "echo b1 >>'$log'" 2>/dev/null
wait "$first"
[ "$(tr '\n' ' ' <"$log")" = "a1 a2 b1 " ] || fail "order '$(tr '\n' ' ' <"$log")', want 'a1 a2 b1 '"

# stale dead pid
true &
dead=$!
wait "$dead"
mkdir -p "$HEAVY_LOCK"
echo "$dead" >"$HEAVY_LOCK/pid"
echo "whatever" >"$HEAVY_LOCK/start"
start=$SECONDS
"$script" true 2>/dev/null || fail "stale dead pid: run failed"
[ $((SECONDS - start)) -le 2 ] || fail "stale dead pid: took too long"

# stale reused pid (alive, different start time)
mkdir -p "$HEAVY_LOCK"
echo "$$" >"$HEAVY_LOCK/pid"
echo "Thu Jan  1 00:00:00 1970" >"$HEAVY_LOCK/start"
start=$SECONDS
"$script" true 2>/dev/null || fail "stale reused pid: run failed"
[ $((SECONDS - start)) -le 2 ] || fail "stale reused pid: took too long"

# releases on signal
"$script" sleep 5 &
holder=$!
sleep 0.3
kill -TERM "$holder"
wait "$holder" 2>/dev/null || true
sleep 0.5
[ -e "$HEAVY_LOCK" ] && fail "lock left behind after TERM"

[ "$fails" -eq 0 ] && echo "heavy: all pass" || exit 1
