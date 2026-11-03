#!/usr/bin/env bash
# Tests for skills/autopilot/scripts/host_gate.sh
set -euo pipefail

gate="$(cd "$(dirname "$0")/../.." && pwd)/skills/autopilot/scripts/host_gate.sh"
fails=0

check() {
  local want="$1" url="$2" got=0
  "$gate" "$url" >/dev/null 2>&1 || got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL: $url → exit $got, want $want"
    fails=$((fails + 1))
  fi
}

check 0 "https://app-dev.example.com"
check 0 "https://dev-api.example.com/login"
check 0 "https://staging.example.id"
check 0 "http://qa.x.io:8080"

check 1 "https://devices.example.com"
check 1 "https://shop-production.up.railway.app"
check 1 "https://shop.azurewebsites.net"
check 1 "https://developer.example.com"

check 1 "https://myapp.pages.dev"
check 1 "https://foo.workers.dev"
check 1 "https://shop.dev"
check 1 "https://prod.example.com?x=a.dev"
check 1 "https://prod.example.com#.staging"
check 0 "https://app-dev.vercel.app"
check 0 "https://foo-dev.pages.dev"

check 2 "not-a-url"

label="$("$gate" "https://app-dev.example.com" 2>/dev/null || true)"
[ "$label" = "dev" ] || { echo "FAIL: matched label '$label', want 'dev'"; fails=$((fails + 1)); }

[ "$fails" -eq 0 ] && echo "host_gate: all pass" || exit 1
