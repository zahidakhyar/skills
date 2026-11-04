#!/usr/bin/env bash
# List open issues the coordinator may pick up, across local clones.
#
#   issues.sh [--root <dir>]
#
# --root  where the clones live (default: $AUTOPILOT_ROOT, then $REVIEW_QUEUE_ROOT;
#         one of the three is required).
#
# A clone is watched only when its .claude/autopilot.md has a "## Pickup"
# section with an uncommented line:
#   rule: assignee:@me        issues assigned to the gh user
#   rule: label:<name>        issues carrying that label
#   base: <branch>            optional, passed through
# Issues that an open PR already closes are dropped.
#
# Prints one JSON array of {repo, number, title, url, clone, rule, base}.
# Clones are matched by their origin remote; worktrees (.git file) never count.
set -euo pipefail

root="${AUTOPILOT_ROOT:-${REVIEW_QUEUE_ROOT:-}}"
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="${2:?--root needs a directory}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$root" ]; then
  echo "no clone root: pass --root <dir> or set AUTOPILOT_ROOT" >&2; exit 2
fi
if [ ! -d "$root" ]; then
  echo "clone root is not a directory: $root" >&2; exit 2
fi

# pickup <config> <key>: value of "<key>:" inside ## Pickup, comments skipped.
pickup() {
  awk -v key="$2" '
    /^## / { in_section = ($0 ~ /^## Pickup[[:space:]]*$/); next }
    !in_section || /^[[:space:]]*<!--/ { next }
    $0 ~ "^[[:space:]]*" key ":" {
      sub("^[[:space:]]*" key ":[[:space:]]*", ""); sub(/[[:space:]]*(#.*)?$/, "")
      print; exit
    }' "$1"
}

seen=""
find "$root" -maxdepth 6 \( -name node_modules -o -name .worktrees -o -name worktrees \) -prune \
  -o -type d -name .git -print 2>/dev/null \
  | while IFS= read -r gitdir; do
      dir=${gitdir%/.git}
      printf '%s\t%s\n' "$(printf '%s' "$dir" | tr -cd '/' | wc -c | tr -d ' ')" "$dir"
    done | sort -n | cut -f2- \
  | while IFS= read -r dir; do
      config="$dir/.claude/autopilot.md"
      [ -f "$config" ] || continue
      rule="$(pickup "$config" rule)"
      [ -n "$rule" ] || continue
      base="$(pickup "$config" base)"
      url="$(git -C "$dir" remote get-url origin 2>/dev/null)" || continue
      repo="$(printf '%s' "$url" | sed -E 's#^.*github\.com[:/]##; s#\.git$##')"
      case " $seen " in *" $repo "*) continue ;; esac
      seen="$seen $repo"

      case "$rule" in
        assignee:*) filter=(--assignee "${rule#assignee:}") ;;
        label:*) filter=(--label "${rule#label:}") ;;
        *) echo "skipping $repo: unknown rule '$rule'" >&2; continue ;;
      esac

      # gh reads stdin; without </dev/null it swallows the clone list.
      issues="$(gh issue list -R "$repo" --state open --limit 50 "${filter[@]}" \
        --json number,title,url </dev/null)" || { echo "skipping $repo: gh issue list failed" >&2; continue; }
      closed="$(gh pr list -R "$repo" --state open --limit 100 --json closingIssuesReferences \
        --jq '[.[].closingIssuesReferences[].number]' </dev/null)" || closed='[]'

      jq -c --arg repo "$repo" --arg clone "$dir" --arg rule "$rule" --arg base "$base" \
        --argjson closed "$closed" \
        '.[] | select(.number as $n | $closed | index($n) | not)
         | {repo: $repo, number, title, url, clone: $clone, rule: $rule,
            base: (if $base == "" then null else $base end)}' <<<"$issues"
    done | jq -s .
