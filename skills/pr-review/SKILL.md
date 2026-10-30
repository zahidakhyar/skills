---
name: pr-review
description: Use when reviewing a teammate's pull request for the first time — `/pr-review <PR>`, "review PR #123", "tolong review PR-nya Budi", "ada PR yang minta review", "cek PR tim", "review requested". Not for a PR already reviewed once (that is `/recheck`) and not for your own unpushed changes (`/ship` runs its own gate).
---

# PR Review

First review of someone else's PR. It runs `code-review` and, when the diff calls for them, `security-review` and an `impeccable` UI audit, filters every finding through REVIEW.md, and posts the result as one review: one notification for the author. Every later round is `/recheck`, which finds this review through the `reviewed:` marker it writes.

Argument: `/pr-review <PR number|URL> [--comment]`. `--comment` posts the review as soon as step 7 has built it, without showing the draft first. Missing PR → `gh pr list --search "review-requested:@me" --json number,title,author` and ask which one. Run inside the repo checkout; needs `gh` and `jq`.

## 1. State

```bash
bash ~/.claude/skills/recheck/scripts/pr_state.sh <PR>
gh pr view <PR> --json title,body,author,baseRefName,headRefOid,isDraft,files
```

- `baseline_source` is not `"none"` → you reviewed this PR before. Stop and point at `/recheck <PR>`.
- `isDraft` → ask once whether to review a draft; the author may not be done.
- Author is you (`gh api user -q .login`) → the review `event` must be `COMMENT`.
- Repo rules: `git show "origin/<base>:REVIEW.md"` (and `CLAUDE.md`). Read them from the base, so the PR cannot change the rules it is reviewed against. Steps 2, 6 and 7 use them.

## 2. Tier and effort

The tier is the body's `## Risk` line (`Low|Medium|High: …`). No such line → apply the table in the `ship` skill, step 6a, to the PR's files. A repo `REVIEW.md` that defines tiers, or names areas whose bugs are High, wins over that table. Effort: Low → `low`, Medium → `medium`, High → `high`. High tier with more than 1,000 changed lines outside tests, lockfiles and generated files (`gh pr diff <PR> --name-only` plus `files[].additions/deletions`) → `xhigh`: `high` caps the findings and skips verification, which drops real bugs on a diff that size.

Deploy-window pass (step 5.2) is needed when the diff adds a migration, stops reading or writing a column or table, changes a cache key or its invalidation, or changes how work is routed or assigned between workers or users.

Security review is needed when the diff matches the condition in `ship` step 6c (auth, endpoint input, queries built from input, upload, user HTML, secrets/env).

## 3. Worktree at the PR head

```bash
git check-ignore -q .worktrees/ || echo '.worktrees/' >> .git/info/exclude
git fetch -q origin "pull/<PR>/head" "+refs/heads/<base>:refs/remotes/origin/<base>"
git worktree add -b pr-review-<PR> .worktrees/pr-review-<PR> <head>
git -C .worktrees/pr-review-<PR> log --oneline "origin/<base>..HEAD"
```

The last command must list only the PR's own commits (compare with `gh pr view <PR> --json commits`). Commits from other merged PRs in that list mean `origin/<base>` is stale: every review below would then read those PRs as part of this one.

`security-review` reads the branch that is checked out, and every finding is re-read at `<head>`, so both need this tree. It is removed in step 7, also when the skill stops early.

## 4. Gates

`gh pr checks <PR>` (it reports the checks of the PR head); `.github/workflows/*.yml` shows what each check runs. A check that runs typecheck and tests is green → cite its name, run nothing locally. No such check, or it is red or pending → run the gates in the worktree per `~/.claude/skills/ship/references/gates.md` (repo scripts first, related tests only, worker caps); copy `.env` and friends from the main checkout first. A gate that cannot start (no database, no credentials) → `UNVERIFIED: <reason>` in the body. A red gate is a High finding quoting the failure, unless the same check is also red on `<base>`, which makes it Pre-existing.

## 5. Review

Each skill below is a sub-step whose output feeds step 6. Some of them end with "your final reply must contain the report and nothing else" or report through `ReportFindings`: that governs the shape of their report, not the end of this run. After each one returns, the next item here is due, then steps 6 and 7 in the same turn. Before invoking the first, put "Filter findings" and "Draft and post review" on the task list, so they stay open while the sub-skills run. Task labels carry no step numbers.

One at a time:
1. Invoke the `code-review` skill with `args: "<effort> <PR>"`. No `--comment`, no `--fix`, even when `/pr-review` itself got `--comment`: this skill posts, and the author fixes.
2. Deploy-window pass needed (step 2) → do it yourself in the worktree, per `references/deploy-window.md`.
3. Security review needed → `git -C .worktrees/pr-review-<PR> branch --set-upstream-to=origin/<base>`, then dispatch one `general-purpose` subagent (foreground) with this prompt: "`cd <absolute worktree path>` and run every command there. Invoke the `security-review` skill with `args: \"base: origin/<base>\"` and return its markdown report as your final reply." Its findings feed step 6. Run inline, the skill's "nothing else" rule arrives as a user message and ends this turn before steps 6 and 7.
4. PR of specs, plans or design docs → `code-review` only sees the documents, so it checks them against each other. Also check every claim about existing code (a file, function, column, config value, current behaviour, a snippet the plan will compile) against the repo it names, at that repo's `origin/<base>`. A claim the code contradicts is a finding, at the severity of what building on it would break.
5. PR touches UI files (`.tsx`, `.jsx`, `.vue`, `.svelte`, `.css`/`.scss`, Expo / React Native screens) → `cd` into the worktree and invoke `impeccable:impeccable` with `args: "audit <changed UI files>"`. Source-only: its bundled detector plus reading the code, with no dev server, browser or screenshot. The audit only reads; `PRODUCT.md` and `DESIGN.md` stay as the base has them. Keep findings on lines this PR changed and map severity: P0 → High, P1 → Medium, P2 → Low, P3 → Nit. A finding earns its place with a user-facing failure (no label or keyboard path, layout that breaks on a phone or under touch, a missing error, empty or loading state); the health score, taste judgments and its suggested follow-up commands stay out of the review.

## 6. Filter

Every finding from step 5 goes through this before it can be posted:
- Re-read the code at `<head>`. No concrete failure scenario (input or state → wrong result) → drop it.
- Two findings with the same `path:line` or the same root cause → one finding, the higher severity.
- An old bug the PR adds a new path to (a new endpoint or caller that reaches it) → the PR's finding at normal severity, anchored at the new call site. The finding names the old function and every other caller (grep them at `<head>`).
- An old bug the PR adds no path to (the lines are outside the diff, `git blame` shows them older than the PR) → **Pre-existing**.
- New non-trivial logic with no test in the diff → Medium on a High-tier PR, Low otherwise. A green CI does not cover logic no test exercises.
- A failure that hits every request, every tenant or a whole feature during the deploy window, or that makes rollback fail → **High**. Severity is set by who it hits and whether it can be undone, not by how long it lasts: "only until the new revision is ready" is still an outage.
- Severity per REVIEW.md; the repo's `REVIEW.md` overrides it. Style-only → Nit, at most 5, keep the ones that matter most.
- PR description claims checked against the diff. A claim the diff does not support → finding in the body: Medium when it claims a test or verification that did not happen, Low otherwise.

## 7. Draft, confirm, post

Write `review.json` to the scratchpad, in the shape REVIEW.md defines:

```json
{"event": "REQUEST_CHANGES", "commit_id": "<head>", "body": "...",
 "comments": [{"path": "src/x.ts", "line": 42, "side": "RIGHT", "body": "**High** ..."}]}
```

- `event`: any High/Medium → `REQUEST_CHANGES`, else `APPROVE`; own PR → `COMMENT`. Pre-existing never counts.
- Inline comment: label first, then defect, failure scenario and fix, at most 4 lines. `line` must be a changed or context line of the diff on the RIGHT side: check each one against the hunks in `gh pr diff <PR>`. Anything else goes into the body in full.
- Body: REVIEW.md's body shape, one clause for the gates, Pre-existing items with a suggestion to open an issue, and the last line `<!-- reviewed: <head> -->`.
- Language: what the repo's `REVIEW.md` sets, else the language of the PR description. Run the prose through `humanizer:humanizer` in embedded mode.

Without `--comment`: show the user what the author will read (the verdict, the full body, and every inline comment with its `path:line`), then ask whether to post. Posting waits for a yes; requested edits → apply, show again.

With `--comment`: post straight away. The flag is the yes.

```bash
gh api repos/{owner}/{repo}/pulls/<PR>/reviews --input <scratchpad>/review.json -q .html_url
git worktree remove --force .worktrees/pr-review-<PR> && git branch -D pr-review-<PR>
```

A 422 naming a comment line → that line is not in the diff; move the comment into the body and post again. Output: the review URL and the verdict; with `--comment`, also one line per finding (`**<Severity>** path:line — gist`), since the user has not seen them yet.

## Where to stop

| Situation | Behaviour |
|---|---|
| Already reviewed by you | Point at `/recheck <PR>`, nothing else |
| Draft PR, the user says no | Stop, remove nothing (no worktree yet) |
| User declines to post | Keep `review.json`, remove the worktree, say where the file is |
| No finding survives step 6 | `APPROVE` with the gate clause and the marker; still confirm before posting, unless `--comment` |

## Common mistakes

| Mistake | Fix |
|---|---|
| Posting each skill's findings separately | One review, one `gh api` call |
| `code-review --comment` | Its format is not REVIEW.md's; this skill posts |
| Review body without the marker | `/recheck` loses its baseline and guesses |
| Labelling an old bug as the author's | Pre-existing, outside the verdict |
| Posting before the user says yes | Draft first, unless they passed `--comment` |
| Passing `--comment` on to `code-review` | Never; the flag belongs to this skill's step 7 |
| Labelling a deploy-window outage Low because it is temporary | High: it hits every user and blocks rollback (step 6) |
| Invoking `security-review` inline | Subagent only (step 5.3); inline, its "nothing else" rule ends the turn before steps 6 and 7 |
| Reviewing against a stale `origin/<base>` | Fetch the base with an explicit refspec and check `origin/<base>..HEAD` (step 3) |
| Trusting `code-review` alone on a migration PR | It reviews one revision; old and new code run together (step 5.2) |
