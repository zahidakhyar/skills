#!/usr/bin/env bash
# Tests for skills/autopilot/scripts/run_dir.sh
set -euo pipefail

script="$(cd "$(dirname "$0")/../.." && pwd)/skills/autopilot/scripts/run_dir.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

main="$tmp/main"
git init -q "$main"
git -C "$main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$main" worktree add -q "$tmp/wt" -b wt
main="$(cd "$main" && pwd -P)"

out="$(cd "$tmp/wt" && "$script" my-task)"
case "$out" in
  "$main/.autopilot/"*-my-task) ;;
  *) fail "path '$out' not under main checkout $main/.autopilot/" ;;
esac
[ -d "$out" ] || fail "run dir not created"

(cd "$tmp/wt" && "$script" my-task >/dev/null)
n="$(grep -c '^/\.autopilot/$' "$main/.git/info/exclude" || true)"
[ "$n" = "1" ] || fail "exclude line count $n, want 1"

echo '{"pr":42}' > "$out/state.json"
found="$(cd "$tmp/wt" && "$script" --find 42 || true)"
[ "$found" = "$out" ] || fail "--find 42 → '$found', want '$out'"

rc=0
(cd "$tmp/wt" && "$script" --find 7 >/dev/null 2>&1) || rc=$?
[ "$rc" = "1" ] || fail "--find 7 exit $rc, want 1"

echo '{"branch":"feat/x"}' > "$out/state.json"
found="$(cd "$tmp/wt" && "$script" --branch feat/x || true)"
[ "$found" = "$out" ] || fail "--branch feat/x → '$found', want '$out'"
rc=0
(cd "$tmp/wt" && "$script" --branch feat/y >/dev/null 2>&1) || rc=$?
[ "$rc" = "1" ] || fail "--branch feat/y exit $rc, want 1"

[ "$fails" -eq 0 ] && echo "run_dir: all pass" || exit 1
