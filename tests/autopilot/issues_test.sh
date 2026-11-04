#!/usr/bin/env bash
# Tests for skills/autopilot/scripts/issues.sh, with gh stubbed.
set -euo pipefail

script="$(cd "$(dirname "$0")/../.." && pwd)/skills/autopilot/scripts/issues.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

root="$tmp/root"
clone() { # clone <name> [config text]
  git init -q "$root/$1"
  git -C "$root/$1" remote add origin "https://github.com/o/$1.git"
  if [ $# -gt 1 ]; then
    mkdir -p "$root/$1/.claude"
    printf '%b' "$2" >"$root/$1/.claude/autopilot.md"
  fi
}
clone a '# autopilot\n\n## start\n- Command: x\n\n## Pickup\nrule: assignee:@me\nbase: dev\n'
clone b '## Pickup\nrule: label:ready-for-agent\n\n## notes\n- rule: label:not-this-one\n'
clone c
clone d '## Pickup\n<!-- rule: assignee:@me -->\n'

bin="$tmp/bin"
mkdir -p "$bin"
log="$tmp/gh.log"
cat >"$bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$log"
case "\$*" in
  "issue list -R o/a "*"--assignee @me"*)
    echo '[{"number":1,"title":"one","url":"u1"},{"number":2,"title":"two","url":"u2"}]' ;;
  "issue list -R o/b "*"--label ready-for-agent"*)
    echo '[{"number":5,"title":"five","url":"u5"}]' ;;
  "pr list -R o/a "*) echo '[{"body":"Fixes #2 on dev","closingIssuesReferences":[]},{"body":"","closingIssuesReferences":[{"number":1,"repository":{"name":"other","owner":{"login":"x"}}}]}]' ;;
  "pr list -R o/b "*) echo '[{"body":"see #50 and #5x","closingIssuesReferences":[]}]' ;;
  *) echo "unexpected: \$*" >&2; exit 1 ;;
esac
EOF
chmod +x "$bin/gh"
export PATH="$bin:$PATH"
unset AUTOPILOT_ROOT REVIEW_QUEUE_ROOT

out="$("$script" --root "$root")" || fail "exit $? on valid root"

got="$(jq -r '[.[] | "\(.repo)#\(.number)"] | sort | join(" ")' <<<"$out")"
[ "$got" = "o/a#1 o/b#5" ] || fail "picks per-repo rule: got '$got', want 'o/a#1 o/b#5'"

[ "$(jq -r '.[] | select(.repo == "o/a") | .base' <<<"$out")" = "dev" ] || fail "o/a base not dev"
[ "$(jq -r '.[] | select(.repo == "o/b") | .base' <<<"$out")" = "null" ] || fail "o/b base not null"
[ "$(jq -r '.[] | select(.repo == "o/a") | .clone' <<<"$out")" = "$root/a" ] || fail "o/a clone path"
[ "$(jq -r '.[] | select(.repo == "o/b") | .rule' <<<"$out")" = "label:ready-for-agent" ] || fail "o/b rule"

grep -q " o/c" "$log" && fail "called gh for unconfigured clone c"
grep -q " o/d" "$log" && fail "called gh for clone d whose rule is commented out"
grep -q "not-this-one" "$log" && fail "read a rule line outside ## Pickup"

rc=0
"$script" >/dev/null 2>&1 || rc=$?
[ "$rc" = "2" ] || fail "no root: exit $rc, want 2"

rc=0
AUTOPILOT_ROOT="$root" "$script" >/dev/null 2>&1 || rc=$?
[ "$rc" = "0" ] || fail "AUTOPILOT_ROOT: exit $rc, want 0"

[ "$fails" -eq 0 ] && echo "issues: all pass" || exit 1
