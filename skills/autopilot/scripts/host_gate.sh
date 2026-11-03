#!/usr/bin/env bash
# Decide whether a hosted URL is a test environment autopilot may log in to.
# A host qualifies when one whole token of its name (split on "." and "-")
# is a test label. The TLD and shared hosting suffixes (pages.dev, vercel.app,
# up.railway.app, ...) are removed first: they name the platform, not the env.
#
#   host_gate.sh <url>
#
# exit 0  prints the matched label
# exit 1  no test label in the host
# exit 2  the argument has no host
set -euo pipefail

LABELS=(dev staging test qa sandbox preview)
SHARED_SUFFIXES=(pages.dev workers.dev web.app vercel.app netlify.app github.io
  up.railway.app railway.app azurewebsites.net azurestaticapps.net azurecontainerapps.io
  herokuapp.com onrender.com fly.dev run.app appspot.com)

url="${1:-}"
case "$url" in
  *://*) ;;
  *) echo "no host in '$url'" >&2; exit 2 ;;
esac

host="${url#*://}"
host="${host%%[/?#]*}"
host="${host##*@}"
host="${host%%:*}"
host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
[ -n "$host" ] || { echo "no host in '$url'" >&2; exit 2; }

name="$host"
for suffix in "${SHARED_SUFFIXES[@]}"; do
  case "$name" in
    *."$suffix") name="${name%."$suffix"}"; break ;;
  esac
done
[ "$name" = "$host" ] && name="${name%.*}"

IFS='.-' read -r -a tokens <<< "$name"
for token in "${tokens[@]}"; do
  for label in "${LABELS[@]}"; do
    if [ "$token" = "$label" ]; then
      echo "$label"
      exit 0
    fi
  done
done

echo "no test label in $host" >&2
exit 1
