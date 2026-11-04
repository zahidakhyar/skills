#!/usr/bin/env bash
# Tests for skills/deliver/scripts/wait_deploy.sh, with curl and gh stubbed.
set -euo pipefail

script="$(cd "$(dirname "$0")/../.." && pwd)/skills/deliver/scripts/wait_deploy.sh"
bin="$(mktemp -d)"
trap 'rm -rf "$bin"' EXIT
fails=0

cat > "$bin/curl" <<'EOF'
#!/usr/bin/env bash
[ "${FAKE_CURL_RC:-0}" = 0 ] || exit "$FAKE_CURL_RC"
printf '%s' "${FAKE_CURL_BODY:-}"
EOF
cat > "$bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${FAKE_GH_BODY:-[]}"
EOF
chmod +x "$bin/curl" "$bin/gh"
export PATH="$bin:$PATH" DELIVER_POLL_SEC=0

# check <want-exit> <want-line-prefix> -- <args...>
check() {
  local want="$1" prefix="$2" out rc=0
  shift 3
  out="$("$script" "$@" 2>/dev/null)" || rc=$?
  if [ "$rc" != "$want" ] || [[ "$out" != "$prefix"* ]]; then
    echo "FAIL: $* → exit $rc '$out', want $want '$prefix…'"
    fails=$((fails + 1))
  fi
}

FAKE_CURL_BODY='{"sha":"abc1234def"}' \
  check 0 "DEPLOYED abc1234 via endpoint" -- --sha abc1234 --timeout-min 0 --endpoint https://x-dev.example.com/version

FAKE_CURL_BODY='{"sha":"0000000"}' \
  check 3 "TIMEOUT after 0m" -- --sha abc1234 --timeout-min 0 --endpoint https://x-dev.example.com/version

FAKE_CURL_RC=7 \
  check 3 "TIMEOUT after 0m" -- --sha abc1234 --timeout-min 0 --endpoint https://x-dev.example.com/version

FAKE_CURL_BODY='{"build":{"commit":"abc1234def"}}' \
  check 0 "DEPLOYED" -- --sha abc1234def99 --timeout-min 0 --endpoint https://x/v --jq .build.commit

FAKE_GH_BODY='[{"status":"completed","conclusion":"failure"}]' \
  check 1 "FAILED deploy workflow concluded failure" -- --sha abc1234abc1234abc1234abc1234abc1234abcde --timeout-min 0 --gh-workflow deploy.yml --repo o/r

FAKE_GH_BODY='[{"status":"completed","conclusion":"success"}]' \
  check 0 "DEPLOYED abc1234abc1234abc1234abc1234abc1234abcde via gh" -- --sha abc1234abc1234abc1234abc1234abc1234abcde --timeout-min 0 --gh-workflow deploy.yml --repo o/r

FAKE_GH_BODY='[]' \
  check 3 "TIMEOUT after 0m" -- --sha abc1234abc1234abc1234abc1234abc1234abcde --timeout-min 0 --gh-workflow deploy.yml --repo o/r

check 2 "" -- --sha abc1234 --timeout-min 0

FAKE_CURL_BODY='{"status":"ok","version":1}' \
  check 3 "TIMEOUT after 0m" -- --sha 1f00ba7deadbeef --timeout-min 0 --endpoint https://x/health

check 2 "" -- --sha a --timeout-min 0 --endpoint https://x/v
check 2 "" -- --sha abc1234 --timeout-min 20m --endpoint https://x/v

check 2 "" -- --sha abc1234 --timeout-min 0 --gh-workflow deploy.yml --repo o/r

[ "$fails" -eq 0 ] && echo "wait_deploy: all pass" || exit 1
