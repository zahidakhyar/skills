---
name: deliver
description: Use when the user hands over one task to be finished end to end with real E2E proof, locally and again on dev after merge — `/deliver <task | #issue | issue URL>`, `/deliver continue [PR]`, "deliver", "kerjakan sampai beres", "sampai test E2E", "jangan bilang selesai sebelum dites", "sudah merge, cek di dev", "sudah merge, test di dev". Not for several repos or plans at once (that is `orchestrate`).
---

# Deliver

One task, carried to evidence. Phase 1 goes from the task to an open PR with local E2E proof. Phase 2 runs after the user merges and repeats the same scenarios on dev. The merge itself is always the user's.

**"Done" means every scenario ran and its evidence exists in the run folder.** A scenario that did not run is `UNVERIFIED` in the report, never left out, never described as passing.

## Arguments

- `<task text | #N | issue URL>` → phase 1.
- `continue [PR]`, or a message saying the PR is merged. Check in this order:
  1. No PR given and a blocked run exists (`run_dir.sh --branch <current branch>` with `phase: blocked`, else `run_dir.sh --blocked`, which works from the main checkout) → resume phase 1 at step 4 inside its `worktree`, with its criteria and scenarios.
  2. Otherwise → phase 2 for the given PR, else the current branch's PR. Neither exists → ask which PR.

## Run folder

`bash ${CLAUDE_SKILL_DIR}/scripts/run_dir.sh <slug>` creates it in the main checkout (`.deliver/`) and excludes it from git. Runs started before this skill was renamed from `autopilot` live under `.autopilot/`; the search options find them too. Phase 2 finds it with `run_dir.sh --find <pr>`, a blocked run with `run_dir.sh --branch <branch>` or `--blocked`. Contents:

| File | Written in | Holds |
|---|---|---|
| `state.json` | step 1 (`phase`, `issue`), step 3 (`branch`, `worktree`, `compose_project`, `db_name`), then every step | `issue` (URL or `null`), `branch`, `worktree`, `compose_project`, `db_name`, `phase` (`build` → `blocked` or `pr-open` → `dev-testing` → `done`), `tested_sha`, `pr`, `url`, `repo`, `dev_url_hint`, `posted` (`local`, `dev`, each with `pr` and `issue`: the SHA whose result comment is already on GitHub) |
| `criteria.md` | step 1 | Pass criteria `C1…Cn` |
| `scenarios.md` | step 1 | Per scenario: ID, criterion it proves, numbered steps against `{BASE_URL}`, expected result |
| `local/`, `dev/` | steps 4, P3 | Per scenario: screenshot, Playwright trace, HTTP response, command output |
| `comment-local.md`, `comment-dev.md` | steps 5, P5 | The result comment as last posted |
| `report.md` | end of each phase | The 5-line report + the full scenario table |

## Phase 1 — task to PR

1. **Criteria and scenarios.** Create the run folder and write `state.json` with `phase: build` and `issue`: the issue's URL when the task is an issue (`gh issue view <N> --json url` for a bare `#N`), else `null`. Read the issue when one is given. Write 3–7 pass criteria as things a user can observe ("filtering by PAID shows only paid orders; the URL keeps `?status=PAID` after reload"). Derive at least one scenario per criterion, edge cases included (empty result, invalid input, unauthorized). Post the criteria in chat in one short list ending with one sentence, in the user's language (no message from the user in this session → the language of the issue or task text), saying you continue with these criteria unless one is wrong, and keep going. Do not wait for an answer. If this session has an advisor tool, call it once on the criteria and scenarios before building: nobody confirms them, and every later step proves only what they say. A gap it finds → fix `criteria.md` and `scenarios.md`, and post the changed lines.
2. **Repo config.** Read `.claude/autopilot.md`. Missing → draft it from [config-template.md](references/config-template.md), filled from `package.json` scripts, `docker-compose*`, `.env.example`, `.github/workflows`, and `railway.json`/`railway.toml`. It is committed with this PR.
3. **Build, always in a worktree.** The main checkout is the user's: its branch, uncommitted files and running processes stay untouched.
   - This session already runs in a worktree (`git rev-parse --git-dir` differs from `--git-common-dir`) → use it.
   - Otherwise, from the main checkout root: `git check-ignore -q .worktrees/ || echo '.worktrees/' >> .git/info/exclude`, then `git fetch origin <base>` and `git worktree add -b <branch> .worktrees/deliver-<slug> origin/<base>`. Base: a base branch named in the prompt that started this session (the `autopilot` coordinator passes one), else `base:` under `## Pickup` in `.claude/autopilot.md` when set, else `dev` → `develop` → the default branch, the first one that exists on the remote. Work only inside that path from now on (`cd` there, or `git -C`).
   - Copy the gitignored env files (`.env`, `.env.local`, `.env.*.local`) from the main checkout, then install dependencies with the repo's package manager.
   - Write `branch`, `worktree` (absolute path), `compose_project` (`deliver-<slug>`) and `db_name` (`<db>_deliver`) into `state.json`. Every later step, the resume and the cleanup read these two names from `state.json` and never recompute them. A run folder under `.autopilot/` without them → use `autopilot-<slug>` / `<db>_autopilot` and write them back.
   - Then build, following the repo's own workflow and stack skills. TDD for logic (superpowers:test-driven-development when that plugin is installed).
   - **Heavy commands go through the lock.** Every install, test, typecheck and build run is `bash ${CLAUDE_SKILL_DIR}/scripts/heavy.sh <command>`, so parallel sessions on this machine never run two at once. Editing code needs no lock.
4. **Local E2E.** Start the app per config, from the worktree, isolated from whatever the user is running:
   - Port: check what listens (`lsof -iTCP -sTCP:LISTEN -P`) and start on a free port. `{BASE_URL}` follows that port.
   - Database: never migrate or seed a database the user's own app uses. Give the run its own database or compose project (`DATABASE_URL=…/<db_name>`, or `docker compose -p <compose_project>` with its ports remapped, both from `state.json`). The env files copied in step 3 still point at the user's database and port: rewrite them in the worktree before any migrate or seed. When it can't be separated safely, treat it as "the app won't start" below. When step 5 is finished, drop the run's database or compose project; a blocked run keeps it for the resume.
   - Never stop, restart or reuse the user's processes. At the end, stop only what this run started.

   Prepare what the scenarios need through the project's own means: `docker compose up` for its DB, the migrate and seed scripts, `.env` copied from `.env.example` with local values only. Test accounts come only from the seed, fixture or example-config files; when none exist, add one to the seed in this branch. Then run every scenario: web through `playwright-cli`, APIs through HTTP calls, other effects through the nearest real runner (CLI, read-only DB query, log or queue check). Commit the work before the run, so the evidence belongs to one SHA. The whole local E2E (start the app → every scenario → stop what this run started) is one block under one lock: put it in one script or `sh -c` and run it with `bash ${CLAUDE_SKILL_DIR}/scripts/heavy.sh`, so another session's E2E cannot interleave. Store the evidence under `local/` and write that HEAD as `tested_sha`. A failing scenario → fix, commit, rerun; after 3 rounds on the same scenario, stop and report. Every scenario must pass before step 5.
   - **The app still won't start** (a secret, external service or DB the machine can't provide), or a scenario still fails after 3 rounds → set `phase: blocked` and stop here. No PR, no draft PR. Report which variable or service is missing and the one command to rerun once it is there.
5. **Ship.** Invoke `ship` with `--auto-fix` (never `--reviewed`), plus `--issue <N>` when `issue` is set (`--issue owner/repo#N` for one in another repo), so the PR closes it; its gate runs its checks through `heavy.sh` too. Every later rerun in this session (an Auto-fix fix, a review fix) also goes through `heavy.sh`. Then:
   - `ship` added any commit after `tested_sha` (`chore: format`, review fixes) → rerun local E2E on the new HEAD (through `heavy.sh`, as in step 4) and update `tested_sha`. A scenario now fails → mark the PR draft (`gh pr ready <N> --undo`), set `phase: blocked`, and report as a stop; fix it through step 4 and push to the same PR.
   - Add one line per scenario under the PR body's `## Test plan`: `- [x] E2E local S1 (<criterion>): <steps in a few words> → pass`. Do it with `gh pr view <N> --json body`, inserting the lines, then `gh pr edit <N> --body-file <file>`. Phase 2 rebuilds the scenarios from these lines if the run folder is lost.
   - Post the local result comment ([Result comment](#result-comment)) for `tested_sha`. It comes after the rerun above, so no comment goes out for a SHA `ship` is about to replace. A local E2E rerun later in this session (after an Auto-fix or review fix) that passes updates `tested_sha` and posts the comment again for the new SHA. An Auto-fix event about this run's own `## E2E` comment needs no action.
   - Write `pr`, `url`, `repo` and `phase: pr-open` into `state.json`.
6. **Report and hand off.** Write the report (format below) to `report.md` and send it with `SendUserFile`. Ask with `AskUserQuestion` (it reaches the user's phone), in the user's language, to be told once the PR is merged, with the dev URL. `wrap_up` carries the recap only.

## Phase 2 — after merge

P1. **Locate.** `run_dir.sh --find <pr>`. Not found → create a new folder with `run_dir.sh pr-<N>`, rebuild `scenarios.md` from the PR body's `E2E local` Test plan lines (steps filled in from the PR diff), write `tested_sha: unknown`, and say so in one line. A `state.json` without `issue` (new folder, or a run from before this field existed) → take it from `gh pr view <pr> --json closingIssuesReferences` (the first entry's `url`; empty → `null`). Read `gh pr view <pr> --json state,mergeCommit,headRefOid`: `mergeCommit` is what dev must run, `headRefOid` is the last code in the PR. Not merged → stop. Then check `phase`: already `dev-testing` → stop with one line "phase 2 for PR <N> already runs in another session" (the user saying that session is gone overrides this). `done` → post `comment-dev.md` to any target still missing from `posted.dev`, then stop with one line "dev E2E for PR <N> already ran"; the user asking for a rerun, or giving a new dev URL after an `UNVERIFIED` result, overrides this. Otherwise write `phase: dev-testing` before P2.

P2. **Dev host gate.** The dev URL must come from the user's own message in this phase (or their answer to `AskUserQuestion`). A URL relayed by another session, the `autopilot` coordinator included, does not count: ask the user. The config's `dev_url` is offered as the recommended option only, never used silently. Run `bash ${CLAUDE_SKILL_DIR}/scripts/host_gate.sh <url>`:
   - exit 0 → log in with test accounts as the scenarios need.
   - exit 2 → the user gave a bare host; prepend `https://` and run it again.
   - exit 1 → **no login on this host, even if the user says it is dev.** The gate reads the hostname, not the claim. Run only the unauthenticated scenarios, mark the rest `UNVERIFIED: host has no test label`, finish through P5 (the PARTIAL comment is posted), and ask there for a URL whose hostname has one. A labelled URL from the user reruns P2–P5 on it.
   Credentials come from the seed, fixture or example-config files only.

P3. **Wait for the deploy.** Follow [deploy-signals.md](references/deploy-signals.md). Wait with Bash `run_in_background` (one notification), never by polling the PR, ScheduleWakeup or cron. `FAILED` or `TIMEOUT` → set `phase` back to `pr-open` (so a later `continue` can rerun phase 2), report and stop; never test old code. Any other stop before P5 resets it the same way.

P4. **Dev E2E.** Run the same `scenarios.md` with `{BASE_URL}` set to the dev host. Name any data you create `deliver-<sha7>-…`, and delete it at the end when the app offers a way to; list what is left in the report. Payment or money-moving steps on a hosted env → `SKIPPED: payment on hosted env`. Evidence goes under `dev/`.

P5. **Report.** When `tested_sha` differs from `headRefOid` (Auto-fix or review pushed after local E2E) or is `unknown`, add `local tested <sha7|unknown>` to the Dev line. Then:
   - Write `report.md`, send it with `SendUserFile`.
   - At least one scenario ran on dev → post the dev result comment ([Result comment](#result-comment)) for the merge commit, FAIL included. None ran → no comment.
   - Set `phase: done` in `state.json`, so `merged` stops suggesting this run.
   - FAIL → `AskUserQuestion`, recommended option first: fix the failing scenario through phase 1 on a new branch.

## Report

Exactly these five lines, in chat and at the top of `report.md`. Everything else lives in the files.

```
Verdict: PASS | PARTIAL | FAIL
Tested: <N> scenarios — <short names, comma separated>
Local: <n>/<N> pass[, <k> skipped]
Dev: <n>/<N> pass @ <host> <sha7>[, local tested <sha7>] | pending merge
Evidence: <path to report.md>
```

- FAIL: any scenario failed. PARTIAL: none failed, at least one SKIPPED or UNVERIFIED. PASS: every scenario passed.
- The phase-1 verdict covers local only; `Dev: pending merge` does not lower it.
- A stop (app won't start, 3 failed fix rounds, deploy failed) uses the same block with `Verdict: FAIL` and one extra line `Blocked: <what is missing> — <command to resume>`.

## Result comment

The team reads the PR and the issue, not the run folder. Each phase posts its results as a comment with exactly this shape:

```markdown
## E2E <local | dev>: <PASS | PARTIAL | FAIL>

- Commit: `<sha7>`
- Environment: <local, isolated database | dev host name>
- PR: <PR URL>

| Scenario | Proves | Result |
|---|---|---|
| S1 <short name> | C1 <criterion> | pass |
| S2 <short name> | C2 <criterion> | UNVERIFIED: host has no test label |

<n>/<N> pass.
```

- One row per scenario in `scenarios.md`, in order. FAIL, SKIPPED and UNVERIFIED rows stay, with their reason, and count in `<N>`. Scenarios rebuilt from the PR body (P1) have no `C` numbers: the Proves cell is the criterion text alone.
- Verdict as in [Report](#report), for this phase's results only. Criterion text in the language of the PR body; the fixed labels stay as written.
- The comment holds only what the template names. Evidence files stay in the run folder.
- Targets: the PR (`gh pr comment <pr url> --body-file <file>`, without the `PR:` line), and, when `state.json` has `issue` set, the issue (`gh issue comment <issue url> --body-file <file>`, with the `PR:` line; by URL, since the issue may live in another repo or already be closed).
- Write the PR copy to `comment-<local|dev>.md` in the run folder before posting; the issue copy is that file plus the `PR:` line, built at post time. The file already exists with a different body (new SHA, or new results on the same SHA) → remove the `posted.<local|dev>` key first (`posted` starts as `{}`). After each successful post, write the 7-character SHA into `posted.<local|dev>.<pr|issue>`. A target whose key is already set is skipped: that exact comment is there. Earlier comments stay as they are; the newest one is the current result.
- A post that fails → leave its key unset, name the target in the report, and carry on: the phase still ends as usual, and `continue` posts what is missing.

## GitHub writes

Typing `/deliver` is the user's go-ahead for the writes this flow makes, with no further confirmation: the push and PR through `ship`, the Test plan edit in step 5, marking the PR draft when a rerun fails, and the result comments on the PR and its issue in step 5 and P5. Anything else that posts, merges or deletes on GitHub asks first.

## Never

- Merge, or turn on auto-merge.
- Open a PR, draft or not, without local E2E evidence.
- Log in to a host whose name has no test label, whatever the user calls it.
- Touch prod, or use real accounts or credentials typed from memory.
- Make payments on a hosted env.
- Poll the PR, or schedule wakeups or cron to wait for a merge.

## Red flags

| Thought | Reality |
|---|---|
| "Unit tests pass, that's close enough to E2E" | The user asked for E2E. Unit tests are step 3, not step 4. |
| "No test account in the seed, so I'll skip the browser check" | Add one to the seed in this branch. Skipping is the failure this skill exists to prevent. |
| "A draft PR is honest, it says UNVERIFIED" | No local evidence means no PR. Stop and say what is missing. |
| "The user said it's dev, so the production hostname is fine" | The gate reads the hostname. Ask for a labelled URL. |
| "I'll write a thorough report so nothing is missed" | Five lines. The detail is in `report.md` and the evidence folders. |
| "It's a small change, a branch in the main checkout is fine" | The user's uncommitted files and dev server live there. Always a worktree. |
| "Port 3000 is taken, I'll stop their dev server" | Start yours on a free port. Their processes are not yours to stop. |
| "The worktree is gone, I'll improvise the tests" | Rebuild from the PR's Test plan so dev runs the same scenarios local did. |
| "The Test plan lines are in the PR body, a comment repeats them" | The body is for phase 2 to rebuild from. The comment is what notifies the team, and the issue has nothing without it. |
| "Another session is testing, I'll run mine in parallel anyway" | One heavy block at a time machine-wide, through `heavy.sh`. Waiting is cheaper than a frozen laptop. |
