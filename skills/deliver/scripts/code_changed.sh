#!/usr/bin/env bash
# Usage: code_changed.sh <sha> [<head>]   (head defaults to HEAD)
# Exit 0: a file outside .claude/features/ changed in <sha>..<head>.
# Exit 1: nothing changed, or only .claude/features/ (map-only commits are not code).
# Exit 2: <sha> or <head> is not a commit in this repository.
set -euo pipefail

sha="${1:?usage: code_changed.sh <sha> [<head>]}"
head="${2:-HEAD}"
for ref in "$sha" "$head"; do
  if ! git rev-parse -q --verify "${ref}^{commit}" >/dev/null; then
    echo "code_changed: $ref is not a commit in this repository" >&2
    exit 2
  fi
done
if git diff --quiet "$sha".."$head" -- . ':(exclude).claude/features'; then
  exit 1
fi
exit 0
