#!/usr/bin/env bash
# Emit the factual state a recheck needs, as one JSON object.
#
#   pr_state.sh <PR> [repo-dir]
#
# Fields:
#   repo, base, baseline, baseline_source, head, force_pushed,
#   commits[]        - author commits since the baseline, merges & upstream excluded
#   changed_files[]  - files those commits touched (NOT files pulled in by a base merge)
#
# force_pushed=true means baseline..head is meaningless: the branch was rewritten,
# so the old review anchored to commits that no longer exist. Fall back to reviewing
# the whole PR rather than a delta.
#
# Every list call is --paginate'd. Without it `gh api` stops at 30 items and the
# review carrying the newest marker is exactly the one that falls off the end.
set -euo pipefail

PR="${1:?usage: pr_state.sh <PR> [repo-dir]}"
cd "${2:-.}"

repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
base=$(gh pr view "$PR" --json baseRefName -q .baseRefName)
head=$(gh pr view "$PR" --json headRefOid -q .headRefOid)

# Baseline = the commit the previous review looked at.
# Two marker shapes: a plain "reviewed: <sha>" comment (older runs, reviewer-loop)
# or the hidden "<!-- reviewed: <sha> -->" line inside a review body. Newest wins.
baseline=$( {
  gh api --paginate "repos/$repo/issues/$PR/comments" -q '
    .[] | select(.body | test("^reviewed:"))
    | "\(.created_at) \(.body | sub("^reviewed:\\s*"; "") | split("\n")[0] | gsub("\\s"; ""))"'
  gh api --paginate "repos/$repo/pulls/$PR/reviews" -q '
    .[] | select(.state != "PENDING")
    | select(.body | test("<!-- *reviewed: *[0-9a-f]+ *-->"))
    | "\(.submitted_at) \(.body | capture("<!-- *reviewed: *(?<sha>[0-9a-f]+) *-->").sha)"'
} | sort | tail -1 | cut -d" " -f2)
baseline_source="marker"

# A thread reply also creates a review record: state COMMENTED, empty body,
# commit_id = head at reply time. So after the author pushes and replies, the
# newest review is their reply at the new head and baseline==head looks
# "unchanged". Anchor on my own reviews that carry a body or a top-level
# inline comment; replies (in_reply_to_id set) never qualify.
if [ -z "$baseline" ]; then
  me=$(gh api user -q .login)
  anchored=$(gh api --paginate "repos/$repo/pulls/$PR/comments" \
    | jq -sc '[.[][] | select(.in_reply_to_id == null) | .pull_request_review_id]')
  baseline=$(gh api --paginate "repos/$repo/pulls/$PR/reviews" \
    | jq -r --arg me "$me" --argjson anchored "$anchored" '
      .[] | select(.state != "PENDING" and .user.login == $me)
      | select(.body != "" or ([.id] | inside($anchored)))
      | .commit_id' | tail -1)
  baseline_source="last-review"
fi

if [ -z "$baseline" ]; then
  jq -nc --arg repo "$repo" --arg head "$head" \
    '{repo:$repo, head:$head, baseline:null, baseline_source:"none",
      note:"never reviewed - use /pr-review, not /recheck"}'
  exit 0
fi

git fetch -q origin "pull/$PR/head" "$base" 2>/dev/null || true

force_pushed=false
if ! git cat-file -e "${baseline}^{commit}" 2>/dev/null \
   || ! git merge-base --is-ancestor "$baseline" "$head" 2>/dev/null; then
  force_pushed=true
fi

commits='[]'; files='[]'
if [ "$force_pushed" = false ] && [ "$baseline" != "$head" ]; then
  # --not origin/<base> drops commits that arrived by merging the base branch in;
  # reviewing upstream churn as if the author wrote it wastes the whole pass.
  shas=$(git log --no-merges --format=%H "$baseline..$head" --not "origin/$base" || true)
  if [ -n "$shas" ]; then
    commits=$(git log --no-merges --format='%H %s' "$baseline..$head" --not "origin/$base" \
      | jq -R . | jq -sc .)
    files=$(for s in $shas; do git show --name-only --format= "$s"; done \
      | sed '/^$/d' | sort -u | jq -R . | jq -sc .)
  fi
fi

jq -nc \
  --arg repo "$repo" --arg base "$base" \
  --arg baseline "$baseline" --arg bsrc "$baseline_source" \
  --arg head "$head" --argjson fp "$force_pushed" \
  --argjson commits "$commits" --argjson files "$files" \
  '{repo:$repo, base:$base, baseline:$baseline, baseline_source:$bsrc, head:$head,
    force_pushed:$fp, unchanged:($baseline==$head), commits:$commits, changed_files:$files}'
