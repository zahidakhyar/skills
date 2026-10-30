---
name: recheck
description: Re-review a pull request after the author pushed fix commits, in any language or stack. Use this whenever someone asks to re-check, re-review, re-verify, or "look again" at a PR that already has review comments — `/recheck <PR>`, "cek ulang PR #123", "sudah ada update, coba cek lagi", "sudah ada update terbaru, review lagi, jangan lupa cek comment", "the author pushed fixes, are they real?", "verify the fixes on that PR", "did they actually address my comments?", "close out the threads on #88" — and also when returning to a PR you reviewed earlier in the session. It finds the commits added since the last review, re-verifies each earlier finding against the code as it now stands, runs the repo's own typecheck and test gates, resolves only the threads whose code genuinely changed, states why each remaining thread stays open, and flags regressions the fix commits introduced. Use `/pr-review` instead only when the PR has never been reviewed at all.
---

# Recheck

A second pass over a PR that was already reviewed. The value here is narrow and specific: **deciding what the new commits actually changed about your earlier findings.** A fresh full review would re-derive things you already know and, worse, tends to soften prior findings that nobody actually fixed. First review → `/pr-review`.

Argument: `/recheck <PR number|URL>`. Missing → list open PRs carrying a `reviewed:` marker and ask which one.

Needs `gh` (authenticated) and `jq`. The repo can be any language — gates are detected from the repo, never assumed from habit.

**The one rule everything else serves:** a verdict comes from reading the post-fix code or from command output you paste into the report. Commit messages, PR descriptions, and author replies describe *intent*; they are evidence of what someone meant to do, not of what the code now does. Half the point of a recheck is catching the gap between the two.

## 1. Get the factual state

```bash
~/.claude/skills/recheck/scripts/pr_state.sh <PR> [repo-dir]
```

Returns one JSON object: `baseline`, `baseline_source`, `head`, `force_pushed`, `unchanged`, `commits[]`, `changed_files[]`. Three things it handles that are easy to get wrong by hand:

- **Baseline** = the commit the last review saw. It prefers the newest `reviewed: <sha>` marker, whether the hidden `<!-- reviewed: <sha> -->` line in a review body (what §7 writes) or a plain `reviewed: <sha>` comment (older runs, `reviewer-loop`), falling back to the newest review you submitted that has a body or a top-level inline comment. Thread replies also create review records, stamped with the head they were posted on, so the script skips them. `baseline_source: "none"` → this PR was never reviewed; stop and point at `/pr-review`.
- **`force_pushed: true`** → the branch was rewritten and the baseline commit is gone from history, so a `baseline..head` delta is fiction. Say so and review the PR as a whole instead; a delta computed across a rebase silently drops real changes.
- **`changed_files` excludes base-branch merges.** When an author merges `main` in, a naive diff hands you hundreds of upstream files. Reviewing those as if the author wrote them wastes the pass and buries the actual fix.

`unchanged: true` → no new commits. Report that and stop; re-reviewing identical code produces noise and, if you re-post findings, duplicate threads.

## 2. Run the gates

CI first: `gh pr checks <PR>`. When a check that runs typecheck and tests is green on `<head>`, that is the gate evidence; cite the check name in the report and do not run anything locally. Re-running what CI just proved costs minutes on this machine and proves the same thing.

Run gates locally only when there is no such check (some repos have no CI gate at all), the check is red or still pending, or a specific finding needs one test run that CI does not isolate. Then detect the toolchain and run typecheck/build + tests. Commands, parallelism caps, and how to narrow a suite that's too heavy: **`~/.claude/skills/ship/references/gates.md`** — read the row for this repo's stack.

Run in a throwaway worktree, so a half-installed dependency or a test that writes fixtures can't corrupt the working tree you actually use:

```bash
git -C <repo> check-ignore -q .worktrees/ || echo '.worktrees/' >> <repo>/.git/info/exclude
git -C <repo> worktree add .worktrees/recheck-<PR> <head>
# install deps, copy non-git setup (.env and friends) from the main working dir, run gates
git -C <repo> worktree remove --force .worktrees/recheck-<PR>
```

The worktree lives inside `<repo>` (paths after `git -C <repo>` resolve there), never beside it: when repos share a parent folder that is itself a git repo, a sibling directory shows up there as untracked.

If a gate can't run at all — missing services, no gate defined for the language — write `UNVERIFIED: <reason>` in the report. An unrun gate reported as passing is the single most damaging thing a recheck can produce, because it converts "nobody checked" into "someone checked and it was fine".

## 3. Gather the prior findings

They live in three places, and using only the first is the common miss:

```bash
~/.claude/skills/recheck/scripts/threads.sh list <PR>     # unresolved inline threads, every page
gh api --paginate repos/{owner}/{repo}/pulls/<PR>/reviews -q '.[] | select(.body != "") | {author:.user.login, state, body}'
gh api --paginate repos/{owner}/{repo}/issues/<PR>/comments -q '.[] | {author:.user.login, body}'
```

Run these inside the repo checkout (`{owner}/{repo}` resolve from it). `--paginate` is not optional: a bare `gh api` list stops at 30 items and `gh pr view --json reviews|comments` at 100, and on a PR that has been through several rounds the review you need is the newest one, which is exactly the one that gets cut.

The review body is the recap: one line per finding (`**<Severity>** `path:line` — gist`) plus any finding outside the diff written in full there, since it has no line to anchor to. Those out-of-diff findings have no thread to resolve, so they only get closed out by being addressed in the report; miss them and the most important finding is the one that silently vanishes. Older reviews may still carry a standalone summary comment, so read the issue comments too.

## 4. Assign one verdict per finding

Work through them in order. Each gets exactly one:

| Verdict | What it takes to claim it |
|---|---|
| `FIXED` | You read the file at `<head>` and the defect is gone. Quote the new `path:line`. |
| `PARTIAL` | Fixed at one site, still present at others — name each remaining `path:line`. |
| `NOT FIXED` | Still there at `<head>`. Quote the code. |
| `REBUTTED-VALID` | The author's argument holds after you re-read the code *and* the repo's CLAUDE.md / AGENTS.md. Say what changed your mind. |
| `REBUTTED-REJECTED` | It doesn't hold. Give the concrete failing scenario. |
| `UNTOUCHED` | File isn't in `changed_files`. The finding stands, unaddressed. |

Two failure modes worth guarding against, because both feel reasonable in the moment:

**Conceding to a rebuttal you haven't tested.** A confident reply plus a large diff makes retraction feel gracious. But you're the last check before this merges, and a finding withdrawn without re-reading the code is worse than never raising it — it converts an open question into a false all-clear. Re-read, then agree or don't.

**Calling a root-cause finding fixed from a single call site.** When the finding was "shared function `X` is missing a guard", grep every caller of `X` at `<head>`. A patch applied only at the path named in the thread is `PARTIAL` — the sibling callers are still broken, and the thread closing makes them invisible.

## 5. Resolve threads — narrowly

Resolve only when the verdict is `FIXED` **and** the thread's `path` is in `changed_files`. `REBUTTED-VALID` is the single exception: no code change is expected there, so say that explicitly in the reply.

```bash
~/.claude/skills/recheck/scripts/threads.sh resolve <thread-id>
~/.claude/skills/recheck/scripts/threads.sh reply <thread-id> "<body>"   # threads that stay open
```

Resolve a `FIXED` thread without a reply: the author already wrote what they changed under it, and the resolved state is the acknowledgement. A reply belongs only on threads that stay open (what is still wrong, one line) and on `REBUTTED-VALID` (say no change is expected). The verification detail goes in the review body's gate clause, once, not under each thread.

`isOutdated: true` is not grounds to resolve. It means the diff anchor moved, which happens when lines shift above it — it says nothing about whether the defect survived. Threads resolved on outdatedness are how real findings disappear.

Everything else stays open with a reply naming the reason, and gets listed in the report. The list is what makes the review auditable: the author can see exactly what's left, and nothing depends on either of you remembering.

## 6. Read the fix commits as new code

The fixes are themselves unreviewed. Scoped to `changed_files`:

- **Regressions** — check the callers of every changed signature. Fixes under review pressure tend to be narrow and local, which is exactly how a caller gets missed.
- **Tests newly skipped or weakened** — `.skip`, `xit`, `#[ignore]`, `@Disabled`, `t.Skip`, `@pytest.mark.skip`; assertions loosened; a test edited to match the buggy behaviour instead of the bug being fixed. Compare against the baseline rather than reading the current state alone, since a skip that was always there isn't news.
- **Collateral** — debug leftovers (`console.log`, `println!`, `print()`, `dd()`), commented-out code, a dependency added for something the stdlib already does.
- Anything the repo's `CLAUDE.md` / `AGENTS.md` rules out.

Same evidence bar as §4: `path:line` plus a concrete failure scenario. No scenario you can state → drop it rather than downgrade it. A speculative Medium still costs the author a round trip and teaches them to discount your Highs.

## 7. Report

The output of a recheck is the review itself, not a comment about the review. Each fact is said once, in the place the reader will look for it. Order: thread replies and resolves first, the review last, so the author's one notification is the verdict.

- **Thread that is fixed** → resolve it, no reply. The author already wrote what they changed; "Fixed, verified" under it repeats them back to themselves.
- **Thread not fixed, or only partly** → `threads.sh reply`, at most 3 lines: what is still wrong, `path:line`, the failure scenario. Leave it open.
- **A question the author asked** → `threads.sh reply` under their comment, one sentence.
- **New finding from the fix commits** → an entry in `comments[]` of the review below, anchored to the new line: severity label first, at most 4 lines: what, consequence, fix. It appears nowhere else.
- **Verdict** → one call publishes the body and the new inline findings together:

  ```bash
  gh api repos/{owner}/{repo}/pulls/<PR>/reviews --input review.json
  ```
  ```json
  {"event": "APPROVE" | "REQUEST_CHANGES", "commit_id": "<head-sha>", "body": "...",
   "comments": [{"path": "src/x.ts", "line": 42, "side": "RIGHT", "body": "**Nit** ..."}]}
  ```

  Body two or three lines: state plus head sha, gates in one clause, where anything new lives ("3 nit inline"). Findings still open get one line each: `**<Severity>** \`path:line\` — <reason>`. Last line is the hidden baseline marker: `<!-- reviewed: <head-sha> -->`. No new findings → omit `comments`.

No summary comment and no separate `gh pr review` call: the review body carries the verdict, and a second message with the same content is what gets the whole review skimmed. GitHub blocks approve/request-changes on your own PR; there `event` is `COMMENT` and the verdict is the body's first line, marker included.

Review body for a PR where everything is fixed:

> All 10 findings fixed, verified at `1cdc1bd` (350 pass, tsc 97 = dev). 3 new nits inline, non-blocking. `noUncheckedIndexedAccess`: yes, separate issue.
> <!-- reviewed: 1cdc1bd53ef402c89c57d0c31c1966af2ad68fdd -->

What stays out. Each of these is what once made a real recheck three times longer than its content:

- restating what the author fixed, or listing the new inline findings again in the body
- how you verified (mutation runs, what you re-read): the gate clause is the evidence, the rest is narration
- design observations nobody asked for ("altitude notes", root-cause essays): a follow-up issue if it matters, otherwise nothing
- process headings, bold mini-headings, em dashes, explanations of GitHub mechanics

## Where to stop

- `unchanged: true` → report "no new commits", stop.
- `baseline_source: "none"` → never reviewed; `/pr-review`, not this.
- `force_pushed: true` → delta is meaningless; say so and review the PR whole.
- Gates can't run → `UNVERIFIED:` with the reason, then continue with code-reading verdicts.
- The fix commits touch nothing related to any finding → say that plainly. Manufacturing a verdict to look thorough is how a review stops being worth reading.
