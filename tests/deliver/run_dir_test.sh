#!/usr/bin/env bash
# Tests for skills/deliver/scripts/run_dir.sh
set -euo pipefail

script="$(cd "$(dirname "$0")/../.." && pwd)/skills/deliver/scripts/run_dir.sh"
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
  "$main/.deliver/"*-my-task) ;;
  *) fail "path '$out' not under main checkout $main/.deliver/" ;;
esac
[ -d "$out" ] || fail "run dir not created"

(cd "$tmp/wt" && "$script" my-task >/dev/null)
n="$(grep -c '^/\.deliver/$' "$main/.git/info/exclude" || true)"
[ "$n" = "1" ] || fail "exclude line count $n, want 1"

echo '{"pr":42}' > "$out/state.json"
found="$(cd "$tmp/wt" && "$script" --find 42 || true)"
[ "$found" = "$out" ] || fail "--find 42 → '$found', want '$out'"

rc=0
(cd "$tmp/wt" && "$script" --find 7 >/dev/null 2>&1) || rc=$?
[ "$rc" = "1" ] || fail "--find 7 exit $rc, want 1"

echo '{"pr":"43"}' > "$out/state.json"
found="$(cd "$tmp/wt" && "$script" --find '#43' || true)"
[ "$found" = "$out" ] || fail "--find '#43' with string pr → '$found', want '$out'"

echo '{"branch":"feat/x"}' > "$out/state.json"
found="$(cd "$tmp/wt" && "$script" --branch feat/x || true)"
[ "$found" = "$out" ] || fail "--branch feat/x → '$found', want '$out'"
rc=0
(cd "$tmp/wt" && "$script" --branch feat/y >/dev/null 2>&1) || rc=$?
[ "$rc" = "1" ] || fail "--branch feat/y exit $rc, want 1"

echo '{"branch":"feat/x","phase":"blocked"}' > "$out/state.json"
found="$(cd "$main" && "$script" --blocked || true)"
[ "$found" = "$out" ] || fail "--blocked → '$found', want '$out'"
echo '{"branch":"feat/x","phase":"pr-open"}' > "$out/state.json"
rc=0
(cd "$main" && "$script" --blocked >/dev/null 2>&1) || rc=$?
[ "$rc" = "1" ] || fail "--blocked with no blocked run exit $rc, want 1"

# legacy fallback: runs started before the rename live under .autopilot/
legacy="$main/.autopilot/2026-01-01-old"
mkdir -p "$legacy"
echo '{"pr":99,"branch":"old/b","phase":"blocked"}' > "$legacy/state.json"
found="$(cd "$tmp/wt" && "$script" --find 99 || true)"
[ "$found" = "$legacy" ] || fail "legacy --find 99 → '$found', want '$legacy'"
found="$(cd "$tmp/wt" && "$script" --branch old/b || true)"
[ "$found" = "$legacy" ] || fail "legacy --branch old/b → '$found', want '$legacy'"
found="$(cd "$main" && "$script" --blocked || true)"
[ "$found" = "$legacy" ] || fail "legacy --blocked → '$found', want '$legacy'"
echo '{"branch":"old/b","phase":"blocked"}' > "$out/state.json"
found="$(cd "$main" && "$script" --branch old/b || true)"
[ "$found" = "$out" ] || fail "--branch prefers .deliver over legacy → '$found', want '$out'"
new="$(cd "$tmp/wt" && "$script" new-task)"
case "$new" in "$main/.deliver/"*-new-task) ;; *) fail "new run '$new' not under .deliver/" ;; esac
grep -q '^/\.autopilot/$' "$main/.git/info/exclude" && fail "new run added /.autopilot/ to exclude"

[ "$fails" -eq 0 ] && echo "run_dir: all pass" || exit 1
