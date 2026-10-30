---
name: merged
description: Use when a pull request has just been merged and the local checkout still carries its leftovers — the user says "sudah ku merge, cleanup", "PR-nya sudah merge, bersihin", "cleanup branch", "post-merge cleanup", or types `/merged [PR number | branch] [--close-issues] [--dry-run]`. Also use right after a hotfix PR to main is merged, when dev may need a back-merge check, and when a merged PR's `Closes #N` did not close the issue because the PR targeted a non-default branch, or when a PR is merged and the user asks what to do next ("habis ini ngapain"). Not for merging the PR itself.
---

# Merged

Clean up after a PR merge, then point to the next piece of work. Runs without confirmation except at the points marked **ask**.

## Arguments

A token starting with `--` is a flag; the one remaining token is the PR ref (number or branch name). No ref → the current branch.

| Flag | Effect |
|---|---|
| `--dry-run` | Show the commands that would run; execute nothing that changes state. |
| `--close-issues` | Step 6 closes issues that are still `OPEN`. Without this flag step 6 only reports. Needed because GitHub acts on `Closes #N` only for PRs into the default branch; a PR into `dev` leaves its issue open. |

## Flow

0. **Repo** — detect sub-repos: `for d in */; do [ -d "$d.git" ] && echo "$d"; done`. No output → the current repo only. Output (a layout like `acme/` or the `workspace/` root) → look for the PR in each sub-repo (`gh pr view <ref>` from inside that directory); steps 1–7 run in the sub-repo that holds the PR. Other sub-repos are left alone: not pulled, not in the table. PR found in more than one sub-repo → pick the one whose head branch still exists locally (`git -C <dir> branch --list <head>`); still more than one, or none → **ask** which repo.

1. **PR** — from the ref or the current branch.
   `gh pr view <ref> --json number,url,state,mergedAt,baseRefName,headRefName,body,closingIssuesReferences`
   `state` is not `MERGED` → stop, report the state. Delete nothing. Cleanup is only for PRs already in base.
   `<head>` is a long-lived branch (`dev`, `develop`, `main`, `master`, or the repo's default branch; the case of a `dev` → `main` release PR) → steps 2, 4 and 5 are skipped, their columns `-`. Steps 3, 6 and 7 still run.

2. **Worktree** — `git worktree list --porcelain`. If `<head>` is checked out in another worktree: `git -C <path> status --porcelain` must be empty → `git worktree remove <path>`. Has changes → **ask**.

3. **Base** — `git status --porcelain` in the current checkout must be empty; changes → **ask** before switching branches. Then `git checkout <base>`, `git pull --ff-only`, record `git rev-parse --short <base>` for the `base@sha` column. Fast-forward fails → report, never reset/force.

4. **Local branch** — if `git branch --list <head>` exists → `git branch -D <head>` (`-d` refuses squash-merged branches; `-D` is safe because step 1 already confirmed MERGED). Missing → column `bersih`, no command. Also leftover review branches: `git branch --list 'pr-*'`, take the number from `pr-<N>[-suffix]`, `gh pr view <N> --json state`; `MERGED` → `git branch -D`, otherwise leave it. The count goes in the `branch lokal` column.

5. **Remote** — `git fetch --prune`. If `git ls-remote --heads origin <head>` still exists → `git push origin --delete <head>`.

6. **Issue** — collect issue refs from two sources, merged without duplicates:
   - `closingIssuesReferences` from step 1 (GitHub fills it only for PRs into the default branch; for PRs into `dev` it is empty).
   - `body` from step 1, matched against GitHub's closing keywords (case-insensitive):
     `\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\s+([\w.-]+/[\w.-]+)?#(\d+)` — `#N` = this repo, `owner/repo#N` = another repo (use `-R owner/repo` in the `gh issue` command).

   No refs → column `-`. For each ref: `gh issue view <N> [-R owner/repo] --json state,url`.
   - `CLOSED` → `bersih`.
   - `OPEN` without `--close-issues` → column `open`, and below the table: `#N masih open — jalankan ulang dengan --close-issues`.
   - `OPEN` with `--close-issues` → `gh issue close <N> [-R owner/repo] --comment "Merged in <PR url>"` → column `ditutup`. The comment is required: GitHub's auto-close links the PR, and a manual close without a comment loses that trail. The board moves the issue to Done on its own through the built-in "Item closed" workflow; do not touch the board.

7. **Back-merge** — if base is `main` and a `dev` branch exists: `git merge-tree --write-tree origin/dev origin/main`, then compare its first line with `git rev-parse origin/dev^{tree}`. Equal → dev is not behind (merge or squash commits from a release do not count). Different → report "main punya perubahan yang belum ada di dev" plus `git log --no-merges --oneline origin/dev..origin/main` as information (it may include release squash commits); do not merge yourself. The user decides.

8. **Next** — read-only, runs even with `--dry-run`. Collect candidates in the repo steps 1–7 worked on:
   - **Plan** — `grep -c -- '- \[ \]' docs/superpowers/plans/*.md` (missing dir → skip). A plan whose title or filename matches this PR (head branch, PR title) and still has unchecked tasks → candidate "skipped step": list the unchecked task titles. Other plans with unchecked tasks → candidate "next plan", oldest file first. A spec in `docs/superpowers/specs/` whose phases have no plan file yet → candidate "plan not written".
   - **Session** — what this conversation left open and no other source records: work the user deferred ("nanti", "habis ini", "later", "after merge", "setelah ini"); follow-ups you named in replies or `wrap_up` recaps, and items reported as not done or not verified; `start_session` cards proposed but not started. When `/merged` runs in a session other than the one that built the PR, search that session instead: `search_session_transcripts` with the PR number and head branch (desktop app only; tool missing → skip this source and say so in one line). Drop any item a later message or this PR already settled.
   - **Follow-up** — `gh api repos/{owner}/{repo}/pulls/<N>/comments --jq '.[] | select(.body | test("^\\*\\*(Low|Pre-existing)\\*\\*")) | {path, line, body}'`. Keep only items no open issue references yet (`gh issue list --search "<path>" --state open`).
   - **Release** — base is `dev` → `git rev-list --count origin/main..origin/dev`; non-zero → candidate "`/release`" with the count.
   - **Issue** — `gh issue list --assignee @me --state open --limit 5 --json number,title,labels`, excluding issues step 6 just closed.

   Pick exactly one recommendation, in this priority: skipped step > deferred by the user > next plan > plan not written > release > follow-up (session or review) > issue.


## Output

One table, one row per repo that steps 1–7 worked on, no narration:

| repo | base@sha | branch lokal | remote | worktree | issue | back-merge |

Cell values: `dihapus` / `dilepas` / `ditutup` = done, `bersih` = already gone (or already closed) before cleanup, `open` = issue still open and the flag was not given, `-` = not relevant to this PR (e.g. no issue ref, base is not `main`). Anything needing a decision (dirty checkout, dirty worktree, issue still open, dev behind) is written below the table, one line per item.

Last, the result of step 8, always present:

```
Next: <recommendation> — <reason, under 12 words>
Lainnya: <at most 2 other candidates, one line each>
```

No candidates → only `Next: tidak ada kerjaan tersisa yang terlacak.` When the host has a next-step box (`wrap_up`), always call it with `ask` = the recommendation, `actions[0]` = do it, and `actions[1]` = the top `Lainnya` item; a recap-only `wrap_up` is wrong whenever a candidate exists.

## Never

- force-push, `reset --hard`, or delete a branch whose PR is not `MERGED`
- close an issue without `--close-issues`, or an issue this PR does not reference — issues are closed only through step 6
- merge `dev` ← `main` yourself — report only
- start the recommended work yourself — step 8 only suggests; the user picks
- repeat inspections (`git log`, `git branch -a`, `git status`) beyond what the flow names; `gh pr view` + `git worktree list` already give enough data
