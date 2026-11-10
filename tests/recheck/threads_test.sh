#!/usr/bin/env bash
# Tests for skills/recheck/scripts/threads.sh, with gh stubbed.
set -euo pipefail

script="$(cd "$(dirname "$0")/../.." && pwd)/skills/recheck/scripts/threads.sh"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

bin="$tmp/bin"
mkdir -p "$bin"
export GH_LOG="$tmp/gh.log"
page() { # page <thread json, comma separated>
  printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[%s]}}}}}\n' "$1"
}
thread() { printf '{"id":"%s","isResolved":%s,"path":"src/x.ts"}' "$1" "$2"; }
# Two pages, the way `gh api graphql --paginate` prints them: one document each.
{ page "$(thread T1 false),$(thread T2 true)"; page "$(thread T3 false)"; } >"$tmp/pages.json"
export PAGES="$tmp/pages.json"
cat >"$bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
case "$*" in
  "repo view "*) echo "o/r" ;;
  "api graphql --paginate "*) cat "$PAGES" ;;
  "api graphql "*) echo '{"data":{}}' ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$bin/gh"
export PATH="$bin:$PATH"

# list: unresolved threads from every page
got=$("$script" list 7 | jq -c 'map(.id)')
[ "$got" = '["T1","T3"]' ] || fail "list: $got, want [\"T1\",\"T3\"]"
grep -q -- '-F pr=7 -f owner=o -f name=r' "$GH_LOG" || fail "list: PR and repo not passed to the query"

# all: resolved threads too
got=$("$script" all 7 | jq -c 'map(.id)')
[ "$got" = '["T1","T2","T3"]' ] || fail "all: $got, want all three"

# resolve: one mutation for that thread id
: >"$GH_LOG"
"$script" resolve T1 >/dev/null
grep -q -- '-f id=T1 .*resolveReviewThread' <(tr '\n' ' ' <"$GH_LOG") || fail "resolve: mutation or id missing"

# reply: id and body both reach the mutation
: >"$GH_LOG"
"$script" reply T3 "still broken at src/x.ts:4" >/dev/null
flat=$(tr '\n' ' ' <"$GH_LOG")
case "$flat" in
  *"-f id=T3 -f body=still broken at src/x.ts:4 "*"addPullRequestReviewThreadReply"*) ;;
  *) fail "reply: id or body missing" ;;
esac

# missing arguments are refused before any gh call
: >"$GH_LOG"
for args in "" "list" "resolve" "reply T1"; do
  rc=0
  # shellcheck disable=SC2086
  "$script" $args >/dev/null 2>&1 || rc=$?
  [ "$rc" != "0" ] || fail "'$args': exit 0, want a usage error"
done
[ -s "$GH_LOG" ] && fail "usage errors still called gh: $(tr '\n' ' ' <"$GH_LOG")"

[ "$fails" -eq 0 ] && echo "threads: all pass" || exit 1
