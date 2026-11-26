#!/usr/bin/env bash
# Tests for skills/deliver/scripts/code_changed.sh
set -euo pipefail

script="$(cd "$(dirname "$0")/../.." && pwd)/skills/deliver/scripts/code_changed.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

cd "$tmp"
git init -q
git config user.email t@t
git config user.name t
mkdir -p src .claude/features
echo a >src/a.ts
git add -A
git commit -qm base
base=$(git rev-parse HEAD)

rc_of() { local rc=0; bash "$script" "$@" 2>/dev/null || rc=$?; echo "$rc"; }

# no_change: HEAD == sha
[ "$(rc_of "$base")" = "1" ] || fail "no_change: want rc 1"

# map_only
echo map >.claude/features/orders.md
git add -A
git commit -qm map
[ "$(rc_of "$base")" = "1" ] || fail "map_only: want rc 1"

# code_change
map=$(git rev-parse HEAD)
echo b >src/a.ts
git commit -qam code
[ "$(rc_of "$map")" = "0" ] || fail "code_change: want rc 0"

# mixed: one commit touching map and code
mixed_base=$(git rev-parse HEAD)
echo c >src/a.ts
echo map2 >.claude/features/orders.md
git commit -qam mixed
[ "$(rc_of "$mixed_base")" = "0" ] || fail "mixed: want rc 0"

# bad_sha
[ "$(rc_of deadbeef)" = "2" ] || fail "bad_sha: want rc 2"

[ "$fails" = 0 ] || exit 1
echo "code_changed: all tests passed"
