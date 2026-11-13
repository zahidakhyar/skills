#!/usr/bin/env bash
# Tests for skills/recheck/scripts/pr_state.sh, with gh stubbed and a real git repo.
set -euo pipefail

script="$(cd "$(dirname "$0")/../.." && pwd)/skills/recheck/scripts/pr_state.sh"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export FIX="$tmp/fix"
mkdir -p "$FIX"

# gh stub: serves fixture files and applies -q the way gh does (raw strings).
bin="$tmp/bin"
mkdir -p "$bin"
cat >"$bin/gh" <<'EOF'
#!/usr/bin/env bash
q=""; rest=""
while [ $# -gt 0 ]; do
  case "$1" in
    -q) q="$2"; shift 2 ;;
    --json) shift 2 ;;
    --paginate) shift ;;
    *) rest="$rest $1"; shift ;;
  esac
done
case "$rest" in
  " repo view") json='{"nameWithOwner":"o/r"}' ;;
  " pr view 7") json=$(cat "$FIX/pr.json") ;;
  " api repos/o/r/issues/7/comments") json=$(cat "$FIX/issue_comments.json") ;;
  " api repos/o/r/pulls/7/reviews") json=$(cat "$FIX/reviews.json") ;;
  " api repos/o/r/pulls/7/comments") json=$(cat "$FIX/review_comments.json") ;;
  " api user") json='{"login":"me"}' ;;
  *) echo "unexpected gh call:$rest" >&2; exit 1 ;;
esac
if [ -n "$q" ]; then jq -r "$q" <<<"$json"; else printf '%s\n' "$json"; fi
EOF
chmod +x "$bin/gh"
export PATH="$bin:$PATH"

# origin (bare) and a clone: A on main; feat = A - B - C.
git init -q --bare "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/repo" 2>/dev/null
repo="$tmp/repo"
commit() { # commit <file> <message> → prints the sha
  echo "$2" >>"$repo/$1"
  git -C "$repo" add "$1"
  git -C "$repo" commit -q -m "$2"
  git -C "$repo" rev-parse HEAD
}
git -C "$repo" checkout -q -b main
commit base.txt "base" >/dev/null
git -C "$repo" push -q origin main
git -C "$repo" checkout -q -b feat
B=$(commit src.txt "feature")
C=$(commit fix.txt "fix review finding")

fixtures() { # fixtures <head> <issue_comments> <reviews> <review_comments>
  printf '{"baseRefName":"main","headRefOid":"%s"}\n' "$1" >"$FIX/pr.json"
  printf '%s\n' "$2" >"$FIX/issue_comments.json"
  printf '%s\n' "$3" >"$FIX/reviews.json"
  printf '%s\n' "$4" >"$FIX/review_comments.json"
}
state() { "$script" 7 "$repo"; }
want() { # want <case> <jq filter> <expected>
  local got
  got=$(jq -c "$2" <<<"$out")
  [ "$got" = "$3" ] || fail "$1: $2 = $got, want $3"
}
marker_review() { # marker_review <sha> <submitted_at>
  printf '{"id":1,"state":"CHANGES_REQUESTED","user":{"login":"me"},"commit_id":"%s","submitted_at":"%s","body":"Request changes.\\n<!-- reviewed: %s -->"}' "$1" "$2" "$1"
}

# never reviewed
fixtures "$C" '[]' '[]' '[]'
out=$(state)
want "never reviewed" .baseline_source '"none"'
want "never reviewed" .baseline null

# marker in a review body: the delta is the commits after it
fixtures "$C" '[]' "[$(marker_review "$B" 2026-01-01T00:00:00Z)]" '[]'
out=$(state)
want "review marker" .baseline "\"$B\""
want "review marker" .baseline_source '"marker"'
want "review marker" .force_pushed false
want "review marker" .unchanged false
want "review marker" '.commits | length' 1
want "review marker" .changed_files '["fix.txt"]'

# a newer plain "reviewed:" comment beats an older review marker
fixtures "$C" "[{\"user\":{\"login\":\"me\"},\"created_at\":\"2026-02-01T00:00:00Z\",\"body\":\"reviewed: $C\\nnotes\"}]" \
  "[$(marker_review "$B" 2026-01-01T00:00:00Z)]" '[]'
out=$(state)
want "newest marker wins" .baseline "\"$C\""
want "newest marker wins" .unchanged true
want "newest marker wins" .commits '[]'

# a teammate's newer markers at head do not move my baseline
fixtures "$C" "[{\"user\":{\"login\":\"teammate\"},\"created_at\":\"2026-02-01T00:00:00Z\",\"body\":\"reviewed: $C\"}]" \
  "[$(marker_review "$B" 2026-01-01T00:00:00Z),
    {\"id\":2,\"state\":\"APPROVED\",\"user\":{\"login\":\"teammate\"},\"commit_id\":\"$C\",\"submitted_at\":\"2026-02-02T00:00:00Z\",\"body\":\"Approve.\\n<!-- reviewed: $C -->\"}]" '[]'
out=$(state)
want "teammate markers" .baseline "\"$B\""
want "teammate markers" .unchanged false
want "teammate markers" '.commits | length' 1

# only a teammate reviewed: I have no baseline
fixtures "$C" '[]' "[{\"id\":2,\"state\":\"APPROVED\",\"user\":{\"login\":\"teammate\"},\"commit_id\":\"$C\",\"submitted_at\":\"2026-02-02T00:00:00Z\",\"body\":\"Approve.\\n<!-- reviewed: $C -->\"}]" '[]'
out=$(state)
want "teammate only" .baseline_source '"none"'
want "teammate only" .baseline null

# a pending review's marker does not count
fixtures "$C" '[]' "[{\"id\":1,\"state\":\"PENDING\",\"user\":{\"login\":\"me\"},\"commit_id\":\"$B\",\"submitted_at\":null,\"body\":\"<!-- reviewed: $B -->\"}]" '[]'
out=$(state)
want "pending review" .baseline_source '"none"'

# no marker: my last review with a body is the baseline; my thread reply
# (empty body, only a reply comment, stamped with the new head) is skipped
fixtures "$C" '[]' "[
  {\"id\":1,\"state\":\"CHANGES_REQUESTED\",\"user\":{\"login\":\"me\"},\"commit_id\":\"$B\",\"submitted_at\":\"2026-01-01T00:00:00Z\",\"body\":\"Request changes.\"},
  {\"id\":2,\"state\":\"COMMENTED\",\"user\":{\"login\":\"author\"},\"commit_id\":\"$C\",\"submitted_at\":\"2026-01-02T00:00:00Z\",\"body\":\"done\"},
  {\"id\":3,\"state\":\"COMMENTED\",\"user\":{\"login\":\"me\"},\"commit_id\":\"$C\",\"submitted_at\":\"2026-01-03T00:00:00Z\",\"body\":\"\"}]" \
  '[{"pull_request_review_id":3,"in_reply_to_id":55}]'
out=$(state)
want "last-review fallback" .baseline "\"$B\""
want "last-review fallback" .baseline_source '"last-review"'
want "last-review fallback" '.commits | length' 1

# no marker: a review of mine with an empty body but a top-level inline comment counts
fixtures "$C" '[]' "[{\"id\":4,\"state\":\"COMMENTED\",\"user\":{\"login\":\"me\"},\"commit_id\":\"$B\",\"submitted_at\":\"2026-01-01T00:00:00Z\",\"body\":\"\"}]" \
  '[{"pull_request_review_id":4,"in_reply_to_id":null}]'
out=$(state)
want "inline-only review" .baseline "\"$B\""

# force push: the baseline commit is not in the head's history
git -C "$repo" checkout -q -b rewritten main
R=$(commit other.txt "rewritten history")
fixtures "$R" '[]' "[$(marker_review "$B" 2026-01-01T00:00:00Z)]" '[]'
out=$(state)
want "force push" .force_pushed true
want "force push" .commits '[]'

# force push: the baseline commit no longer exists at all
fixtures "$C" '[]' "[$(marker_review 0123456789abcdef0123456789abcdef01234567 2026-01-01T00:00:00Z)]" '[]'
out=$(state)
want "unknown baseline" .force_pushed true

# base merged in after the review: upstream files stay out of the delta
git -C "$repo" checkout -q main
commit upstream.txt "upstream change" >/dev/null
git -C "$repo" push -q origin main
git -C "$repo" fetch -q origin
git -C "$repo" checkout -q feat
git -C "$repo" merge -q --no-edit origin/main
E=$(commit fix2.txt "second fix")
fixtures "$E" '[]' "[$(marker_review "$C" 2026-01-01T00:00:00Z)]" '[]'
out=$(state)
want "base merge" .force_pushed false
want "base merge" '.commits | length' 1
want "base merge" .changed_files '["fix2.txt"]'

[ "$fails" -eq 0 ] && echo "pr_state: all pass" || exit 1
