#!/usr/bin/env bash
# List open PRs that request my review directly, map each to a local clone,
# and decide whether it needs a first review or a recheck. One JSON array.
#
#   queue.sh [--team] [--root <dir>] [--new <seen-file>]
#
# --team  also include PRs that request a review from one of my teams.
# --root  where to look for clones (default: $REVIEW_QUEUE_ROOT; one of the two is required).
# --new   keep only pr-review/recheck rows whose "repo#N@head" key is not in
#         <seen-file>, then append their keys to it. For interval runs, so each
#         PR head is announced once.
#
# Fields per PR:
#   repo, number, title, author, url, isDraft, clone, head, action, reason
#   action: "pr-review" | "recheck" | "skip"
#
# Clones are matched by their origin remote, never by folder name. Worktrees and
# submodules have a .git file, not a directory, so they never count as clones.
set -euo pipefail

# user-review-requested has no gh flag, so it goes in the query string. Other
# qualifiers with @me are unreliable there; --team uses the flag instead.
search=("user-review-requested:@me")
root="${REVIEW_QUEUE_ROOT:-}"
seen=""
while [ $# -gt 0 ]; do
  case "$1" in
    --team) search=(--review-requested=@me); shift ;;
    --root) root="${2:?--root needs a directory}"; shift 2 ;;
    --new) seen="${2:?--new needs a file}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$root" ]; then
  echo "no clone root: pass --root <dir> or set REVIEW_QUEUE_ROOT" >&2; exit 2
fi
if [ ! -d "$root" ]; then
  echo "clone root is not a directory: $root" >&2; exit 2
fi

state_script="$(cd "$(dirname "$0")/../../recheck/scripts" && pwd)/pr_state.sh"
index=$(mktemp)
out=$(mktemp)
trap 'rm -f "$index" "$out" "$out.new"' EXIT

# "owner/name<TAB>path", shallowest path first so a top-level clone beats a nested copy.
find "$root" -maxdepth 6 \( -name node_modules -o -name .worktrees -o -name worktrees \) -prune \
  -o -type d -name .git -print 2>/dev/null \
  | while IFS= read -r gitdir; do
      dir=${gitdir%/.git}
      url=$(git -C "$dir" remote get-url origin 2>/dev/null) || continue
      slug=$(printf '%s' "$url" | sed -E 's#^.*github\.com[:/]##; s#\.git$##' | tr '[:upper:]' '[:lower:]')
      printf '%s\t%s\t%s\n' "$(printf '%s' "$dir" | tr -cd '/' | wc -c | tr -d ' ')" "$slug" "$dir"
    done | sort -n | cut -f2- > "$index"

gh search prs "${search[@]}" --state=open --limit 100 \
  --json number,title,author,url,isDraft,repository \
  | jq -c '.[] | {repo: .repository.nameWithOwner, number, title, author: .author.login, url, isDraft}' \
  | while IFS= read -r pr; do
      repo=$(jq -r .repo <<<"$pr")
      number=$(jq -r .number <<<"$pr")
      slug=$(tr '[:upper:]' '[:lower:]' <<<"$repo")
      clone=$(awk -F'\t' -v s="$slug" '$1 == s { print $2; exit }' "$index")

      if [ -z "$clone" ]; then
        jq -c '. + {clone: null, head: null, action: "skip", reason: "no local clone"}' <<<"$pr"
        continue
      fi

      # gh reads stdin; without </dev/null it swallows the rest of the PR list.
      if ! state=$(bash "$state_script" "$number" "$clone" </dev/null 2>/dev/null); then
        jq -c --arg c "$clone" '. + {clone: $c, head: null, action: "skip", reason: "pr_state.sh failed"}' <<<"$pr"
        continue
      fi

      jq -c --arg c "$clone" --argjson s "$state" '. + {clone: $c, head: $s.head} +
        if $s.baseline_source == "none" then {action: "pr-review", reason: "never reviewed"}
        elif $s.force_pushed then {action: "recheck", reason: "force-pushed since last review"}
        elif ($s.commits | length) == 0 then {action: "skip", reason: "no new commits since my review"}
        else {action: "recheck", reason: "\($s.commits | length) new commit(s) since my review"}
        end' <<<"$pr"
    done \
  | jq -s 'sort_by(.repo, .number)' > "$out"

if [ -z "$seen" ]; then
  cat "$out"
  exit 0
fi

mkdir -p "$(dirname "$seen")" && touch "$seen"
jq --rawfile seen "$seen" '
  ($seen | split("\n")) as $keys
  | map(select(.action != "skip" and ("\(.repo)#\(.number)@\(.head)" | IN($keys[]) | not)))' \
  "$out" | tee "$out.new"
jq -r '.[] | "\(.repo)#\(.number)@\(.head)"' "$out.new" >> "$seen"
