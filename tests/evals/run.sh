#!/usr/bin/env bash
# Run skill evals: dry runs through `claude -p`, graded by grep assertions.
# Usage: run.sh [skill[/case]] [--runs N] [--model M] [--skill-dir PATH]
# Each case dir holds prompt.md ({{SKILL_DIR}}, {{CASE_DIR}} placeholders), scenario.md
# and expect.txt (`must: <ERE>` / `must-not: <ERE>`, `#` comments).
# Exit 0 when every run passes, 1 when one fails, 2 on bad usage.
# Calls the model: run it by hand, not in CI.
set -euo pipefail
# bash >= 5.2 would expand & in ${var//pat/rep}; paths must stay literal. Absent on bash 3.2.
shopt -u patsub_replacement 2>/dev/null || true

usage() { echo "run.sh: $*" >&2; echo "usage: run.sh [skill[/case]] [--runs N] [--model M] [--skill-dir PATH]" >&2; exit 2; }

here="$(cd "$(dirname "$0")" && pwd)"
evals_dir="$(cd "${EVALS_DIR:-$here}" && pwd)"
out_dir="${EVALS_OUT:-$here/.out}"
claude_bin="${CLAUDE_BIN:-claude}"
skill_dir="$(cd "$here/../.." && pwd)/skills"
model=sonnet
runs=1
filter=""

while [ $# -gt 0 ]; do
  case "$1" in
    --runs|--model|--skill-dir)
      [ $# -ge 2 ] || usage "$1 needs a value"
      case "$1" in
        --runs) runs="$2" ;;
        --model) model="$2" ;;
        --skill-dir) skill_dir="$(cd "$2" 2>/dev/null && pwd)" || usage "no such directory: $2" ;;
      esac
      shift 2 ;;
    -*) usage "unknown flag $1" ;;
    *) [ -z "$filter" ] || usage "only one skill or skill/case filter"; filter="$1"; shift ;;
  esac
done
[[ "$runs" =~ ^[1-9][0-9]*$ ]] || usage "--runs must be a positive integer"

# check <output file> <expect file>: prints each failed assertion, returns 1 if any failed
check() {
  local out="$1" expect="$2" line kind pat rc failed=0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in ''|'#'*) continue ;; esac
    kind="${line%%: *}"
    pat="${line#*: }"
    if [ "$kind" = "$line" ] || [ -z "$pat" ]; then
      echo "  bad expect line: $line"; failed=1; continue
    fi
    rc=0; grep -Eq -- "$pat" "$out" 2>/dev/null || rc=$?
    if [ "$rc" -gt 1 ]; then echo "  invalid regex: $pat"; failed=1; continue; fi
    case "$kind" in
      must) [ "$rc" = 0 ] || { echo "  missing  must: $pat"; failed=1; } ;;
      must-not) [ "$rc" = 1 ] || { echo "  present  must-not: $pat"; failed=1; } ;;
      *) echo "  bad expect line: $line"; failed=1 ;;
    esac
  done <"$expect"
  return "$failed"
}

sandbox=""
cleanup() { [ -z "$sandbox" ] || rm -rf "$sandbox"; }
trap cleanup EXIT

cases=()
while IFS= read -r d; do cases+=("$d"); done < <(
  find "$evals_dir" -mindepth 2 -maxdepth 2 -type d ! -path '*/.out*' | sed "s|^$evals_dir/||" | sort
)

total=0
failed=0
for c in ${cases[@]+"${cases[@]}"}; do
  case "$filter" in
    '') ;;
    */*) [ "$c" = "$filter" ] || continue ;;
    *) [ "${c%%/*}" = "$filter" ] || continue ;;
  esac
  dir="$evals_dir/$c"
  for f in prompt.md expect.txt; do
    if [ ! -f "$dir/$f" ]; then
      echo "FAIL $c: $f missing"
      total=$((total + 1)); failed=$((failed + 1))
      continue 2
    fi
  done
  mkdir -p "$out_dir/$c"
  for n in $(seq 1 "$runs"); do
    total=$((total + 1))
    res="$out_dir/$c/run-$n.txt"
    # Each run gets an empty working directory and a copy of the case without its answer key,
    # so the dry run sees only the skills under test and the scenario.
    sandbox="$(mktemp -d)"
    mkdir "$sandbox/cwd" "$sandbox/case"
    find "$dir" -maxdepth 1 -type f ! -name expect.txt ! -name prompt.md -exec cp {} "$sandbox/case/" \;
    prompt="$(<"$dir/prompt.md")"
    prompt="${prompt//\{\{SKILL_DIR\}\}/$skill_dir}"
    prompt="${prompt//\{\{CASE_DIR\}\}/$sandbox/case}"
    rc=0
    # The prompt goes on stdin: --add-dir takes several values and would swallow it as one.
    # --setting-sources "" keeps the user's CLAUDE.md, hooks and plugins out; --tools limits tools to Read.
    (cd "$sandbox/cwd" && printf '%s\n' "$prompt" | "$claude_bin" -p --model "$model" \
      --tools Read --setting-sources "" --strict-mcp-config --disable-slash-commands \
      --add-dir "$skill_dir" "$sandbox/case") >"$res" 2>&1 || rc=$?
    rm -rf "$sandbox"; sandbox=""
    if [ "$rc" -ne 0 ]; then
      echo "FAIL $c run $n: claude exited $rc (output in $res)"
      failed=$((failed + 1))
    elif report=$(check "$res" "$dir/expect.txt"); then
      echo "PASS $c run $n"
    else
      echo "FAIL $c run $n (output in $res)"
      echo "$report"
      failed=$((failed + 1))
    fi
  done
done

if [ "$total" = 0 ]; then
  echo "no eval case matches '${filter}'"
  exit 1
fi
echo "$((total - failed))/$total passed"
[ "$failed" = 0 ]
