#!/usr/bin/env bash
# Resolve deliver's run folder. It lives in the main checkout, not in a
# worktree, so post-merge cleanup of the worktree never deletes the evidence.
#
#   run_dir.sh <slug>         create and print <main>/.deliver/<YYYY-MM-DD>-<slug>
#   run_dir.sh --find <pr>    print the run folder whose state.json has .pr == <pr>
#   run_dir.sh --branch <b>   print the newest run folder whose state.json has .branch == <b>
#   run_dir.sh --blocked      print the newest run folder whose state.json has .phase == "blocked"
#
# Searches also look in .autopilot/, where runs started before the skill was
# renamed from autopilot live; a .deliver/ match always wins.
# The first create adds "/.deliver/" to .git/info/exclude so the folder never
# shows up as a change.
set -euo pipefail

common="$(git rev-parse --path-format=absolute --git-common-dir)"
main="$(cd "$(dirname "$common")" && pwd -P)"
root="$main/.deliver"
legacy="$main/.autopilot"

# newest <jq filter> [arg...]: print the newest run folder in $1 whose state matches.
newest() {
  local dir="$1" filter="$2" match="" state
  shift 2
  for state in "$dir"/*/state.json; do
    [ -f "$state" ] || continue
    if jq -e "$@" "$filter" "$state" >/dev/null 2>&1; then
      match="$(dirname "$state")"
    fi
  done
  [ -n "$match" ] && echo "$match"
}

# search <jq filter> [arg...]: .deliver first, then the legacy folder.
search() {
  newest "$root" "$@" || newest "$legacy" "$@"
}

case "${1:-}" in
  --find)
    pr="${2:?usage: run_dir.sh --find <pr>}"
    pr="${pr#\#}"
    search '(.pr | tostring) == $pr' --arg pr "$pr" && exit 0
    echo "no deliver run for PR $pr" >&2
    exit 1
    ;;
  --branch)
    branch="${2:?usage: run_dir.sh --branch <branch>}"
    search '.branch == $b' --arg b "$branch" && exit 0
    echo "no deliver run for branch $branch" >&2
    exit 1
    ;;
  --blocked)
    search '.phase == "blocked"' && exit 0
    echo "no blocked deliver run" >&2
    exit 1
    ;;
esac

slug="${1:?usage: run_dir.sh <slug> | --find <pr> | --branch <branch> | --blocked}"
case "$slug" in
  -*) echo "unknown option: $slug" >&2; exit 2 ;;
esac
dir="$root/$(date +%Y-%m-%d)-$slug"
mkdir -p "$dir"

exclude="$common/info/exclude"
mkdir -p "$(dirname "$exclude")"
grep -qx '/\.deliver/' "$exclude" 2>/dev/null || echo '/.deliver/' >> "$exclude"

echo "$dir"
