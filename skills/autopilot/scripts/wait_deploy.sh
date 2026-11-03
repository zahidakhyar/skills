#!/usr/bin/env bash
# Wait until the dev environment runs a given commit. Prints exactly one line.
#
#   wait_deploy.sh --sha <sha> --timeout-min <n> --endpoint <url> [--jq <filter>]
#   wait_deploy.sh --sha <sha> --timeout-min <n> --gh-workflow <name> --repo <owner/repo>
#
# --endpoint     GET the URL and read the deployed SHA with --jq
#                (default: .sha // .commit // .version). Short and full SHAs match by prefix.
# --gh-workflow  read the workflow run for --sha with `gh run list`; needs the full SHA.
#
# exit 0  DEPLOYED <sha> via <endpoint|gh>
# exit 1  FAILED <reason>
# exit 2  usage error
# exit 3  TIMEOUT after <n>m
set -euo pipefail

sha="" timeout_min="" endpoint="" filter='.sha // .commit // .version' workflow="" repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sha) sha="$2"; shift 2 ;;
    --timeout-min) timeout_min="$2"; shift 2 ;;
    --endpoint) endpoint="$2"; shift 2 ;;
    --jq) filter="$2"; shift 2 ;;
    --gh-workflow) workflow="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$sha" ] || [ -z "$timeout_min" ] || { [ -z "$endpoint" ] && [ -z "$workflow" ]; }; then
  echo "usage: wait_deploy.sh --sha <sha> --timeout-min <n> (--endpoint <url> | --gh-workflow <name> --repo <owner/repo>)" >&2
  exit 2
fi
if ! [[ "$sha" =~ ^[0-9a-f]{7,40}$ ]]; then
  echo "--sha must be 7-40 hex characters" >&2
  exit 2
fi
if ! [[ "$timeout_min" =~ ^[0-9]+$ ]]; then
  echo "--timeout-min must be a whole number of minutes" >&2
  exit 2
fi
if [ -n "$workflow" ] && ! [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "--gh-workflow needs the full 40-character SHA (gh run list --commit matches it exactly)" >&2
  exit 2
fi
if [ -n "$workflow" ] && [ -z "$repo" ]; then
  echo "--gh-workflow needs --repo" >&2
  exit 2
fi

poll="${AUTOPILOT_POLL_SEC:-30}"
deadline=$(( $(date +%s) + timeout_min * 60 ))

same_sha() {
  [[ "$1" =~ ^[0-9a-f]{7,40}$ ]] && { [[ "$1" == "$sha"* ]] || [[ "$sha" == "$1"* ]]; }
}

# Returns 0 deployed, 1 failed (prints reason), 2 not yet.
check_endpoint() {
  local body deployed
  body="$(curl -fsS --max-time 15 "$endpoint" 2>/dev/null)" || return 2
  deployed="$(printf '%s' "$body" | jq -r "($filter) // empty" 2>/dev/null)" || return 2
  same_sha "$deployed" && return 0
  return 2
}

check_gh() {
  local runs status conclusion
  runs="$(gh run list --repo "$repo" --workflow "$workflow" --commit "$sha" \
    --json status,conclusion -L 1 2>/dev/null)" || return 2
  status="$(printf '%s' "$runs" | jq -r '.[0].status // empty' 2>/dev/null)" || return 2
  [ "$status" = "completed" ] || return 2
  conclusion="$(printf '%s' "$runs" | jq -r '.[0].conclusion // empty')"
  [ "$conclusion" = "success" ] && return 0
  echo "deploy workflow concluded ${conclusion:-unknown}"
  return 1
}

while true; do
  rc=0
  if [ -n "$endpoint" ]; then
    reason="$(check_endpoint)" || rc=$?
    via=endpoint
  else
    reason="$(check_gh)" || rc=$?
    via=gh
  fi
  case "$rc" in
    0) echo "DEPLOYED $sha via $via"; exit 0 ;;
    1) echo "FAILED $reason"; exit 1 ;;
  esac
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "TIMEOUT after ${timeout_min}m"
    exit 3
  fi
  sleep "$poll"
done
