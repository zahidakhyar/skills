#!/usr/bin/env bash
# Resolve autopilot's run folder. It lives in the main checkout, not in a
# worktree, so post-merge cleanup of the worktree never deletes the evidence.
#
#   run_dir.sh <slug>         create and print <main>/.autopilot/<YYYY-MM-DD>-<slug>
#   run_dir.sh --find <pr>    print the run folder whose state.json has .pr == <pr>
#   run_dir.sh --branch <b>   print the newest run folder whose state.json has .branch == <b>
#   run_dir.sh --blocked      print the newest run folder whose state.json has .phase == "blocked"
#
# The first call adds "/.autopilot/" to .git/info/exclude so the folder never
# shows up as a change.
set -euo pipefail

common="$(git rev-parse --path-format=absolute --git-common-dir)"
main="$(cd "$(dirname "$common")" && pwd -P)"
root="$main/.autopilot"

if [ "${1:-}" = "--find" ]; then
  pr="${2:?usage: run_dir.sh --find <pr>}"
  pr="${pr#\#}"
  for state in "$root"/*/state.json; do
    [ -f "$state" ] || continue
    if jq -e --arg pr "$pr" '(.pr | tostring) == $pr' "$state" >/dev/null 2>&1; then
      dirname "$state"
      exit 0
    fi
  done
  echo "no autopilot run for PR $pr" >&2
  exit 1
fi

if [ "${1:-}" = "--branch" ]; then
  branch="${2:?usage: run_dir.sh --branch <branch>}"
  match=""
  for state in "$root"/*/state.json; do
    [ -f "$state" ] || continue
    if jq -e --arg b "$branch" '.branch == $b' "$state" >/dev/null 2>&1; then
      match="$(dirname "$state")"
    fi
  done
  [ -n "$match" ] && { echo "$match"; exit 0; }
  echo "no autopilot run for branch $branch" >&2
  exit 1
fi

if [ "${1:-}" = "--blocked" ]; then
  match=""
  for state in "$root"/*/state.json; do
    [ -f "$state" ] || continue
    if jq -e '.phase == "blocked"' "$state" >/dev/null 2>&1; then
      match="$(dirname "$state")"
    fi
  done
  [ -n "$match" ] && { echo "$match"; exit 0; }
  echo "no blocked autopilot run" >&2
  exit 1
fi

slug="${1:?usage: run_dir.sh <slug> | --find <pr> | --branch <branch> | --blocked}"
case "$slug" in
  -*) echo "unknown option: $slug" >&2; exit 2 ;;
esac
dir="$root/$(date +%Y-%m-%d)-$slug"
mkdir -p "$dir"

exclude="$common/info/exclude"
mkdir -p "$(dirname "$exclude")"
grep -qx '/\.autopilot/' "$exclude" 2>/dev/null || echo '/.autopilot/' >> "$exclude"

echo "$dir"
