#!/usr/bin/env bash
# Tests for skills/review-queue/scripts/queue.sh, with gh stubbed. pr_state.sh
# runs for real against small git repos.
set -euo pipefail

script="$(cd "$(dirname "$0")/../.." && pwd)/skills/review-queue/scripts/queue.sh"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export FIX="$tmp/fix" GH_LOG="$tmp/gh.log"
mkdir -p "$FIX"
root="$tmp/root"

# clone <dir under root> <owner/name>: A on main (= origin/main), then B and C.
clone() {
  local dir="$root/$1"
  git init -q "$dir"
  git -C "$dir" checkout -q -b main
  git -C "$dir" remote add origin "git@github.com:$2.git"
  local f
  for f in a b c; do
    echo "$f" >"$dir/$f.txt"
    git -C "$dir" add "$f.txt"
    git -C "$dir" commit -q -m "$f"
    [ "$f" = a ] && git -C "$dir" update-ref refs/remotes/origin/main HEAD
  done
  return 0
}
sha() { git -C "$root/$1" rev-parse "$2"; }
# pr <number> <head> <reviews json>: what gh answers for that PR
pr() {
  mkdir -p "$FIX/$1"
  printf '{"baseRefName":"main","headRefOid":"%s"}\n' "$2" >"$FIX/$1/pr.json"
  printf '%s\n' "$3" >"$FIX/$1/reviews.json"
}
marker() { printf '[{"id":1,"state":"APPROVED","user":{"login":"me"},"commit_id":"%s","submitted_at":"2026-01-01T00:00:00Z","body":"ok\\n<!-- reviewed: %s -->"}]' "$1" "$1"; }

clone work/api-folder o/API          # folder name differs from the repo; case differs from what gh reports
clone web o/web
clone deep/nested/web o/web          # a deeper copy of the same repo must lose
clone unchanged o/unchanged
clone broken o/broken

pr 1 "$(sha work/api-folder HEAD)" '[]'                                            # never reviewed
pr 2 "$(sha web HEAD)" "$(marker "$(sha web HEAD~1)")"                             # one new commit
pr 3 "$(sha unchanged HEAD)" "$(marker "$(sha unchanged HEAD)")"                   # nothing new
# PR 4 (o/broken) has no fixture: pr_state.sh fails. PR 5 (o/missing) has no clone.

bin="$tmp/bin"
mkdir -p "$bin"
cat >"$bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
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
  " search prs "*) json='[
    {"number":2,"title":"two","author":{"login":"ann"},"url":"u2","isDraft":false,"repository":{"nameWithOwner":"o/web"}},
    {"number":1,"title":"one","author":{"login":"bob"},"url":"u1","isDraft":true,"repository":{"nameWithOwner":"O/Api"}},
    {"number":3,"title":"three","author":{"login":"cy"},"url":"u3","isDraft":false,"repository":{"nameWithOwner":"o/unchanged"}},
    {"number":4,"title":"four","author":{"login":"di"},"url":"u4","isDraft":false,"repository":{"nameWithOwner":"o/broken"}},
    {"number":5,"title":"five","author":{"login":"ed"},"url":"u5","isDraft":false,"repository":{"nameWithOwner":"o/missing"}}]' ;;
  " repo view") json=$(git remote get-url origin | sed -E 's#^.*github\.com[:/]##; s#\.git$##' | jq -R '{nameWithOwner: .}') ;;
  " pr view "*) n=${rest##* }; [ -f "$FIX/$n/pr.json" ] || exit 1; json=$(cat "$FIX/$n/pr.json") ;;
  " api repos/"*"/pulls/"*"/reviews") n=${rest%/reviews}; n=${n##*/}; json=$(cat "$FIX/$n/reviews.json") ;;
  " api repos/"*"/comments") json='[]' ;;
  " api user") json='{"login":"me"}' ;;
  *) echo "unexpected gh call:$rest" >&2; exit 1 ;;
esac
if [ -n "$q" ]; then jq -r "$q" <<<"$json"; else printf '%s\n' "$json"; fi
EOF
chmod +x "$bin/gh"
export PATH="$bin:$PATH"
unset REVIEW_QUEUE_ROOT

row() { jq -c --argjson n "$1" '.[] | select(.number == $n) | '"$2" <<<"$out"; }
want() { # want <case> <number> <jq filter> <expected>
  local got
  got=$(row "$2" "$3")
  [ "$got" = "$4" ] || fail "$1: #$2 $3 = $got, want $4"
}

out=$("$script" --root "$root")
[ "$(jq -c 'map(.number)' <<<"$out")" = '[1,4,5,3,2]' ] || fail "order: $(jq -c 'map(.number)' <<<"$out"), want sorted by repo then number"
want "never reviewed" 1 .action '"pr-review"'
want "clone by remote" 1 .clone "\"$root/work/api-folder\""
want "draft kept" 1 .isDraft true
want "author flattened" 1 .author '"bob"'
want "new commits" 2 .action '"recheck"'
want "new commits" 2 .reason '"1 new commit(s) since my review"'
want "shallowest clone" 2 .clone "\"$root/web\""
want "head reported" 2 .head "\"$(sha web HEAD)\""
want "unchanged" 3 .action '"skip"'
want "unchanged" 3 .reason '"no new commits since my review"'
want "pr_state failure" 4 .reason '"pr_state.sh failed"'
want "no clone" 5 .reason '"no local clone"'
want "no clone" 5 .clone null
grep -q '^search prs user-review-requested:@me ' "$GH_LOG" || fail "default search is not user-review-requested:@me"

# force push since the review: recheck, whatever the commit count
pr 2 "$(sha web HEAD)" "$(marker 0123456789abcdef0123456789abcdef01234567)"
out=$("$script" --root "$root")
want "force push" 2 .reason '"force-pushed since last review"'
pr 2 "$(sha web HEAD)" "$(marker "$(sha web HEAD~1)")"

# --team switches to the flag form
: >"$GH_LOG"
"$script" --team --root "$root" >/dev/null
grep -q '^search prs --review-requested=@me ' "$GH_LOG" || fail "--team did not use --review-requested=@me"

# REVIEW_QUEUE_ROOT stands in for --root
out=$(REVIEW_QUEUE_ROOT="$root" "$script")
[ "$(jq length <<<"$out")" = 5 ] || fail "REVIEW_QUEUE_ROOT: $(jq length <<<"$out") rows, want 5"

# --new: only actionable rows, each PR head announced once
seen="$tmp/state/seen"
out=$("$script" --root "$root" --new "$seen")
[ "$(jq -c 'map(.number)' <<<"$out")" = '[1,2]' ] || fail "--new first run: $(jq -c 'map(.number)' <<<"$out"), want [1,2]"
out=$("$script" --root "$root" --new "$seen")
[ "$(jq -c . <<<"$out")" = '[]' ] || fail "--new second run: $(jq -c . <<<"$out"), want []"
git -C "$root/web" commit -q --allow-empty -m "another push"
pr 2 "$(sha web HEAD)" "$(marker "$(sha web HEAD~2)")"
out=$("$script" --root "$root" --new "$seen")
[ "$(jq -c 'map(.number)' <<<"$out")" = '[2]' ] || fail "--new after a push: $(jq -c 'map(.number)' <<<"$out"), want [2]"

# bad invocations exit 2
for args in "" "--root $tmp/nope" "--bogus"; do
  rc=0
  # shellcheck disable=SC2086
  "$script" $args >/dev/null 2>&1 || rc=$?
  [ "$rc" = "2" ] || fail "'$args': exit $rc, want 2"
done

[ "$fails" -eq 0 ] && echo "queue: all pass" || exit 1
