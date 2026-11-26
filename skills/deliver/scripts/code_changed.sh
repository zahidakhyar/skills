#!/usr/bin/env bash
# Usage: code_changed.sh <sha>
# Exit 0: a file outside .claude/features/ changed in <sha>..HEAD.
# Exit 1: nothing changed, or only .claude/features/ (map-only commits are not code).
# Exit 2: <sha> is not a commit in this repository.
set -euo pipefail

sha="${1:?usage: code_changed.sh <sha>}"
if ! git rev-parse -q --verify "${sha}^{commit}" >/dev/null; then
  echo "code_changed: $sha is not a commit in this repository" >&2
  exit 2
fi
if git diff --quiet "$sha"..HEAD -- . ':(exclude).claude/features'; then
  exit 1
fi
exit 0
