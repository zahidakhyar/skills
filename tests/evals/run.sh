#!/usr/bin/env bash
# Run skill evals: dry runs through `claude -p`, graded by grep assertions.
# Usage: run.sh [skill[/case]] [--runs N] [--model M] [--skill-dir PATH]
# Each case dir holds prompt.md ({{SKILL_DIR}}, {{CASE_DIR}} placeholders), scenario.md
# and expect.txt (`must: <ERE>` / `must-not: <ERE>`, `#` comments).
# Exit 0 when every run passes, 1 otherwise. Calls the model: run it by hand, not in CI.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
evals_dir="${EVALS_DIR:-$here}"
out_dir="${EVALS_OUT:-$here/.out}"
claude_bin="${CLAUDE_BIN:-claude}"
skill_dir="$(cd "$here/../.." && pwd)/skills"
model=sonnet
runs=1
filter=""

while [ $# -gt 0 ]; do
  case "$1" in
    --runs) runs="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    --skill-dir) skill_dir="$2"; shift 2 ;;
    -*) echo "run.sh: unknown flag $1" >&2; exit 2 ;;
    *) filter="$1"; shift ;;
  esac
done

cases=()
while IFS= read -r d; do cases+=("$d"); done < <(
  find "$evals_dir" -mindepth 2 -maxdepth 2 -type d ! -path '*/.out/*' | sed "s|^$evals_dir/||" | sort
)

# check <output file> <expect file>: prints each failed assertion, returns 1 if any failed
check() {
  local out="$1" expect="$2" line kind pat failed=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    kind="${line%%: *}"
    pat="${line#*: }"
    case "$kind" in
      must) grep -Eq -- "$pat" "$out" || { echo "  missing  must: $pat"; failed=1; } ;;
      must-not) ! grep -Eq -- "$pat" "$out" || { echo "  present  must-not: $pat"; failed=1; } ;;
      *) echo "  bad expect line: $line"; failed=1 ;;
    esac
  done <"$expect"
  return "$failed"
}

total=0
failed=0
for c in "${cases[@]}"; do
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
  prompt="$(<"$dir/prompt.md")"
  prompt="${prompt//\{\{SKILL_DIR\}\}/$skill_dir}"
  prompt="${prompt//\{\{CASE_DIR\}\}/$dir}"
  mkdir -p "$out_dir/$c"
  for n in $(seq 1 "$runs"); do
    total=$((total + 1))
    res="$out_dir/$c/run-$n.txt"
    rc=0
    # The prompt goes on stdin: `--add-dir` takes several values and would swallow it as one.
    # claude runs from an empty directory, so the dry run reads only what --add-dir grants and never
    # the skills (or CLAUDE.md) of the checkout running the evals.
    sandbox="$(mktemp -d)"
    (cd "$sandbox" && printf '%s\n' "$prompt" | "$claude_bin" -p --model "$model" --allowedTools Read \
      --add-dir "$skill_dir" "$evals_dir") >"$res" 2>&1 || rc=$?
    rmdir "$sandbox" 2>/dev/null || true
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

echo "$((total - failed))/$total passed"
[ "$failed" = 0 ]
