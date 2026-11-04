#!/usr/bin/env bash
# List open issues the coordinator may pick up, across local clones.
#
#   issues.sh [--root <dir>]
#
# --root  where the clones live (default: $AUTOPILOT_ROOT, then $REVIEW_QUEUE_ROOT;
#         one of the three is required).
#
# A clone is watched only when a .claude/autopilot.md has a "## Pickup"
# section with an uncommented rule line. The clone's own file wins; without
# one, the nearest folder above it (up to --root) that has the section is
# used, so one file at a workspace root covers every clone under it:
#   rule: assignee:@me        issues assigned to the gh user
#   rule: label:<name>        issues carrying that label
#   base: <branch>            optional, passed through
# Issues an open PR closes or mentions as "#N" (any base branch) are dropped.
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

root="$(cd "$root" && pwd -P)"

# pickup_config <dir>: nearest .claude/autopilot.md with a Pickup rule, from
# <dir> up to $root. Prints nothing when there is none.
pickup_config() {
  local d="$1" f
  while :; do
    f="$d/.claude/autopilot.md"
    if [ -f "$f" ] && [ -n "$(pickup "$f" rule)" ]; then
      echo "$f"
      return
    fi
    [ "$d" = "$root" ] && return
    d="$(dirname "$d")"
    case "$d" in "$root"|"$root"/*) ;; *) return ;; esac
  done
}

seen=""
find "$root" -maxdepth 6 \( -name node_modules -o -name .worktrees -o -name worktrees \) -prune \
  -o -type d -name .git -print 2>/dev/null \
  | while IFS= read -r gitdir; do
      dir=${gitdir%/.git}
      printf '%s\t%s\n' "$(printf '%s' "$dir" | tr -cd '/' | wc -c | tr -d ' ')" "$dir"
    done | sort -n | cut -f2- \
  | while IFS= read -r dir; do
      config="$(pickup_config "$dir")"
      [ -n "$config" ] || continue
      rule="$(pickup "$config" rule)"
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
      # Any open PR, whatever its base: closing keywords only register on PRs
      # into the default branch, so a "#N" in the body counts as well.
      if ! prs="$(gh pr list -R "$repo" --state open --limit 100 \
        --json body,closingIssuesReferences </dev/null)"; then
        echo "warning: $repo: gh pr list failed, issues with an open PR may be listed" >&2
        prs='[]'
      fi

      jq -c --arg repo "$repo" --arg clone "$dir" --arg rule "$rule" --arg base "$base" \
        --argjson prs "$prs" \
        'def closes($n): (.closingIssuesReferences // [])
           | any(.number == $n
                 and ((.repository.owner.login + "/" + .repository.name) | ascii_downcase)
                     == ($repo | ascii_downcase));
         def mentions($n): (.body // "") | test("(^|[^A-Za-z0-9_/])#\($n)\\b");
         .[] | .number as $n
         | select([$prs[] | closes($n) or mentions($n)] | any | not)
         | {repo: $repo, number, title, url, clone: $clone, rule: $rule,
            base: (if $base == "" then null else $base end)}' <<<"$issues"
    done | jq -s .
