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
printf '%s\nwhatever\nold\n' "$dead" >"$HEAVY_LOCK/info"
start=$SECONDS
"$script" true 2>/dev/null || fail "stale dead pid: run failed"
[ $((SECONDS - start)) -le 2 ] || fail "stale dead pid: took too long"

# stale reused pid (alive, different start time)
mkdir -p "$HEAVY_LOCK"
printf '%s\nThu Jan  1 00:00:00 1970\nold\n' "$$" >"$HEAVY_LOCK/info"
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

# no_overlap <log>: every "s <id>" is followed directly by "e <id>".
no_overlap() {
  awk '$1 == "s" { if (open != "") bad = 1; open = $2 } $1 == "e" { if (open != $2) bad = 1; open = "" } END { exit bad }' "$1"
}

# A slow ps widens the window between taking the lock and recording the
# holder's start time; waiters must never treat that window as stale.
fakebin="$tmp/fakebin"
mkdir -p "$fakebin"
realps="$(command -v ps)"
printf '#!/usr/bin/env bash\nsleep 0.3\nexec %s "$@"\n' "$realps" >"$fakebin/ps"
chmod +x "$fakebin/ps"

# concurrent waiters with a slow ps
log="$tmp/conc.log"
for i in 1 2 3 4; do
  PATH="$fakebin:$PATH" "$script" sh -c "echo 's $i' >>'$log'; sleep 0.3; echo 'e $i' >>'$log'" 2>/dev/null &
done
wait
[ "$(grep -c '^s ' "$log")" = "4" ] || fail "concurrent: not all 4 ran"
no_overlap "$log" || fail "concurrent: heavy runs overlapped: $(tr '\n' ',' <"$log")"
[ -e "$HEAVY_LOCK" ] && fail "concurrent: lock left behind"

# several waiters taking over the same stale lock
true &
dead=$!
wait "$dead"
mkdir -p "$HEAVY_LOCK"
printf '%s\nwhatever\nold\n' "$dead" >"$HEAVY_LOCK/info"
log="$tmp/stale.log"
for i in 1 2 3 4; do
  PATH="$fakebin:$PATH" "$script" sh -c "echo 's $i' >>'$log'; sleep 0.3; echo 'e $i' >>'$log'" 2>/dev/null &
done
wait
[ "$(grep -c '^s ' "$log")" = "4" ] || fail "stale takeover: not all 4 ran"
no_overlap "$log" || fail "stale takeover: heavy runs overlapped: $(tr '\n' ',' <"$log")"

[ "$fails" -eq 0 ] && echo "heavy: all pass" || exit 1
