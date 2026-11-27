#!/usr/bin/env bash
# Tests for tests/evals/run.sh, with a fake claude so no model is called.
set -euo pipefail

runner="$(cd "$(dirname "$0")" && pwd)/run.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

# Fake claude: prints $FAKE_OUT, or echoes the prompt it got on stdin when FAKE_OUT=echo; exits $FAKE_RC.
# The real `--add-dir` is variadic and would swallow a prompt passed as an argument, so the prompt must come on stdin.
# It also logs its args, and flags any directory it is given that holds an answer key or old outputs.
cat >"$tmp/claude" <<'EOF'
#!/usr/bin/env bash
pwd >"$FAKE_CWD_LOG"
printf '%s\n' "$@" >"$FAKE_ARGS_LOG"
for a in "$@"; do
  [ -d "$a" ] || continue
  if find "$a" -name expect.txt -o -name '.out' | grep -q .; then echo "LEAK $a" >>"$FAKE_ARGS_LOG"; fi
done
if [ "${FAKE_OUT:-}" = echo ]; then cat; else cat >/dev/null; cat "$FAKE_OUT"; fi
exit "${FAKE_RC:-0}"
EOF
chmod +x "$tmp/claude"
export CLAUDE_BIN="$tmp/claude" EVALS_DIR="$tmp/evals" EVALS_OUT="$tmp/out" FAKE_CWD_LOG="$tmp/cwd" FAKE_ARGS_LOG="$tmp/args"

mkcase() { # <skill/case> <expect text>
  mkdir -p "$EVALS_DIR/$1"
  printf 'Read {{CASE_DIR}}/scenario.md and {{SKILL_DIR}}/x/SKILL.md\n' >"$EVALS_DIR/$1/prompt.md"
  printf 'scenario\n' >"$EVALS_DIR/$1/scenario.md"
  printf '%s\n' "$2" >"$EVALS_DIR/$1/expect.txt"
}
rc=0; out=""
run() { rc=0; out=$(bash "$runner" "$@" 2>&1) || rc=$?; }

printf 'Enforce (repeat): jest\nno-force-push-main\nkey: value here\n' >"$tmp/output.txt"
export FAKE_OUT="$tmp/output.txt"

# pass
mkcase a/pass $'# comment\n\nmust: Enforce \\(repeat\\)\nmust-not: Skipped'
run a/pass; [ "$rc" = 0 ] || fail "pass: want rc 0"

# must_fail
rm -rf "$EVALS_DIR"; mkcase a/mustfail 'must: not-in-output'
run a/mustfail; [ "$rc" = 1 ] || fail "must_fail: want rc 1, got $rc"
case "$out" in *"FAIL a/mustfail run 1"*"must: not-in-output"*) ;; *) fail "must_fail: output '$out'";; esac

# must_not_fail
rm -rf "$EVALS_DIR"; mkcase a/mustnot 'must-not: no-force-push'
run a/mustnot; [ "$rc" = 1 ] || fail "must_not_fail: want rc 1"

# colon_in_pattern: split on the first ': ' only
rm -rf "$EVALS_DIR"; mkcase a/colon 'must: key: value'
run a/colon; [ "$rc" = 0 ] || fail "colon_in_pattern: want rc 0 ($out)"

# missing_expect
rm -rf "$EVALS_DIR"; mkcase a/noexpect 'must: x'; rm "$EVALS_DIR/a/noexpect/expect.txt"
run a/noexpect; [ "$rc" = 1 ] || fail "missing_expect: want rc 1, got $rc"
case "$out" in *"expect.txt"*) ;; *) fail "missing_expect: no message ($out)";; esac

# claude_error: non-zero exit is FAIL, output still saved
rm -rf "$EVALS_DIR"; mkcase a/err 'must: Enforce'
rc=0; FAKE_RC=3 bash "$runner" a/err >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "claude_error: want rc 1, got $rc"
[ -s "$EVALS_OUT/a/err/run-1.txt" ] || fail "claude_error: output not saved"

# filter: skill, skill/case, none
rm -rf "$EVALS_DIR"; mkcase a/one 'must: Enforce'; mkcase a/two 'must: Enforce'; mkcase b/three 'must: Enforce'
run a; [ "$(grep -c '^PASS' <<<"$out")" = 2 ] || fail "filter skill: '$out'"
run b/three; [ "$(grep -c '^PASS' <<<"$out")" = 1 ] || fail "filter case: '$out'"
run; [ "$(grep -c '^PASS' <<<"$out")" = 3 ] || fail "filter none: '$out'"

# runs: --runs 2 gives two results
run a/one --runs 2; [ "$(grep -c '^PASS' <<<"$out")" = 2 ] || fail "runs: '$out'"

# placeholders replaced
rm -rf "$EVALS_DIR"; mkcase a/ph 'must-not: \{\{'
export FAKE_OUT="echo"
mkdir -p "$tmp/skills-here"
run a/ph --skill-dir "$tmp/skills-here"; [ "$rc" = 0 ] || fail "placeholders: not replaced ($out)"
grep -q "$tmp/skills-here/x/SKILL.md" "$EVALS_OUT/a/ph/run-1.txt" || fail "placeholders: skill dir missing"
grep -q '/case/scenario.md' "$EVALS_OUT/a/ph/run-1.txt" || fail "placeholders: case dir missing"
grep -q "$EVALS_DIR" "$EVALS_OUT/a/ph/run-1.txt" && fail "placeholders: prompt points into the evals dir (answer key reachable)"

# isolation: claude runs from an empty directory outside the repo and the case dir,
# so a dry run can only read what --add-dir grants, never the skills of the checkout running the evals
repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
cwd="$(cat "$FAKE_CWD_LOG")"
case "$cwd" in "$repo_root"*|"$EVALS_DIR"*|"$(pwd -P)") fail "isolation: claude ran in $cwd";; esac
[ -z "$(ls -A "$cwd" 2>/dev/null)" ] || fail "isolation: claude cwd $cwd is not empty"

# isolation flags: only the Read tool, no user/project settings (CLAUDE.md, hooks), no MCP, no skills
for f in --tools Read --setting-sources --strict-mcp-config --disable-slash-commands; do
  grep -qx -- "$f" "$FAKE_ARGS_LOG" || fail "isolation flag $f not passed"
done
grep -qx -- --allowedTools "$FAKE_ARGS_LOG" && fail "isolation: --allowedTools does not limit tools, use --tools"

# answer key: no directory handed to claude holds expect.txt or .out
grep -q '^LEAK' "$FAKE_ARGS_LOG" && fail "answer key reachable: $(grep '^LEAK' "$FAKE_ARGS_LOG")"

# scenario still reachable through {{CASE_DIR}}
export FAKE_OUT="echo"
rm -rf "$EVALS_DIR"; mkcase a/scen 'must: scenario\.md'
cat >"$tmp/claude-cat" <<'EOF'
#!/usr/bin/env bash
p=$(cat); f=$(grep -oE '[^ ]+/scenario\.md' <<<"$p"); cat "$f"
EOF
chmod +x "$tmp/claude-cat"
rc=0; out=$(CLAUDE_BIN="$tmp/claude-cat" bash "$runner" a/scen 2>&1) || rc=$?
grep -qx scenario "$EVALS_OUT/a/scen/run-1.txt" || fail "scenario not readable from {{CASE_DIR}} ($out)"

# relative --skill-dir becomes absolute; a missing one is an error
mkdir -p "$tmp/rel/skills"
rm -rf "$EVALS_DIR"; mkcase a/rel 'must: ^Read /'
rc=0; out=$(cd "$tmp/rel" && bash "$runner" a/rel --skill-dir ./skills 2>&1) || rc=$?
grep -q "$tmp/rel/skills/x/SKILL.md\|$(cd "$tmp/rel/skills" && pwd -P)/x/SKILL.md" "$EVALS_OUT/a/rel/run-1.txt" || fail "relative skill dir not made absolute"
run a/rel --skill-dir "$tmp/nope"; [ "$rc" = 2 ] || fail "missing skill dir: want rc 2, got $rc"

# & in a path stays literal
mkdir -p "$tmp/a&b"
run a/rel --skill-dir "$tmp/a&b"; grep -qF "$tmp/a&b/x/SKILL.md" "$EVALS_OUT/a/rel/run-1.txt" || fail "& in path mangled"

# empty selection, bad --runs, flag without value
run nosuchskill; [ "$rc" = 1 ] || fail "empty selection: want rc 1, got $rc"
run a/rel --runs abc; [ "$rc" = 2 ] || fail "--runs abc: want rc 2, got $rc"
run a/rel --runs 0; [ "$rc" = 2 ] || fail "--runs 0: want rc 2, got $rc"
run a/rel --model; [ "$rc" = 2 ] || fail "--model without value: want rc 2, got $rc"

# expect.txt hygiene: invalid regex, CRLF, trailing space, empty pattern
export FAKE_OUT="$tmp/output.txt"
rm -rf "$EVALS_DIR"; mkcase a/badre 'must-not: (unbalanced'
run a/badre; [ "$rc" = 1 ] || fail "invalid must-not regex: want rc 1, got $rc"
rm -rf "$EVALS_DIR"; mkcase a/crlf $'must-not: no-force-push\r'
run a/crlf; [ "$rc" = 1 ] || fail "CRLF must-not: want rc 1 (pattern should still match), got $rc"
rm -rf "$EVALS_DIR"; mkcase a/trail 'must-not: no-force-push  '
run a/trail; [ "$rc" = 1 ] || fail "trailing-space must-not: want rc 1, got $rc"
rm -rf "$EVALS_DIR"; mkcase a/empty 'must: '
run a/empty; [ "$rc" = 1 ] || fail "empty pattern: want rc 1, got $rc"

[ "$fails" = 0 ] || exit 1
echo "evals runner: all tests passed"
