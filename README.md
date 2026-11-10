# skills

[![Validate](https://github.com/zahidakhyar/skills/actions/workflows/validate.yml/badge.svg)](https://github.com/zahidakhyar/skills/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Agent skills for Claude Code, packaged as a plugin so you and your team work with the same ones. The repo is both the plugin and its marketplace: install it once and every skill in `skills/` comes with it, including ones added later.

- [Install](#install)
- [Skills](#skills)
- [Per-repo configuration](#per-repo-configuration)
- [Requirements](#requirements)
- [Updating](#updating)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Install

### For yourself

In Claude Code:

```
/plugin marketplace add zahidakhyar/skills
/plugin install zahidakhyar-skills@zahidakhyar
```

Or from a shell:

```bash
claude plugin marketplace add zahidakhyar/skills
```

```bash
claude plugin install zahidakhyar-skills@zahidakhyar
```

Start a new session afterwards. Check that it loaded:

```bash
claude plugin details zahidakhyar-skills
```

### For a whole project

Commit this to the project's `.claude/settings.json`. Anyone who opens the project in Claude Code is offered the marketplace and the plugin, with no manual step:

```json
{
  "extraKnownMarketplaces": {
    "zahidakhyar": { "source": { "source": "github", "repo": "zahidakhyar/skills" } }
  },
  "enabledPlugins": { "zahidakhyar-skills@zahidakhyar": true }
}
```

### Calling a skill

Plugin skills are namespaced: `/zahidakhyar-skills:ship`, `/zahidakhyar-skills:pr-review`, and so on. A slash command is optional. Claude also picks the right skill from a plain request, in English or Indonesian ("ship ini", "review PR #123", "sudah ku merge, cleanup").

## Skills

| Skill | When to use it |
|---|---|
| [`ship`](#ship) | You have local changes and want a PR |
| [`pr-review`](#pr-review) | A teammate asked you to review their PR |
| [`recheck`](#recheck) | The author pushed fixes after your review |
| [`review-queue`](#review-queue) | Work through every PR waiting on your review, one session per PR |
| [`merged`](#merged) | A PR was merged and the local leftovers need cleaning |
| [`release`](#release) | Cut a new version of a JS/TS project or a Claude Code plugin |
| [`orchestrate`](#orchestrate) | Build one or more implementation plans in separate sessions |
| [`deliver`](#deliver) | One task end to end, with E2E proof locally and on dev |
| [`autopilot`](#autopilot) | Your assistant: picks up issues, review requests and Slack mentions, one session each |
| [`learned`](#learned) | Save what this session taught Claude to memory |

The first five form one PR loop:

```mermaid
flowchart LR
    ship["ship<br/><i>author</i>"] --> review["pr-review<br/><i>reviewer</i>"]
    review -- "request changes" --> fix["author pushes fixes"]
    fix --> recheck["recheck<br/><i>reviewer</i>"]
    recheck -- "still open" --> fix
    review -- approve --> merge(["merge on GitHub<br/><i>human</i>"])
    recheck -- approve --> merge
    merge --> merged["merged<br/><i>author</i>"]
    merged -. "when cutting a version" .-> release["release<br/><i>maintainer</i>"]
```

### ship

Branch → format → commit → gate → push → PR, in one command.

```
/zahidakhyar-skills:ship [base] [--issue N] [--draft] [--auto-fix] [--reviewed]
```

| Flag | Effect |
|---|---|
| `base` | Target branch. Default: `dev`, then `develop`, then the repo's default branch |
| `--issue N` | Adds `Closes #N` when the branch name and commits don't mention an issue. Other repo: `--issue owner/repo#N` |
| `--draft` | Opens the PR as a draft |
| `--auto-fix` | Turns on the desktop app's Auto-fix for the PR, so the session wakes on CI failures, conflicts and review comments. Never enables auto-merge |
| `--reviewed` | Skips the code/security review in the gate (typecheck, lint and tests still run). Used by `orchestrate` |

What the gate does before anything is pushed:

1. Picks a risk tier (Low / Medium / High) from the changed paths. The tier goes into the PR body as a `## Risk` line, and reviewers use it to set review depth.
2. Runs typecheck, lint and the related tests, with commands taken from the repo's `package.json` scripts or CI workflow.
3. Runs `code-review` at the tier's effort, and `security-review` when the diff touches auth, endpoint input, queries, uploads, user HTML or secrets.

```mermaid
flowchart TD
    changes[local changes] --> branch[branch + format + commit]
    branch --> tier[risk tier from changed paths]
    tier --> checks[typecheck, lint, related tests]
    checks --> review[code-review / security-review]
    review --> fixable{red check or<br/>High/Medium finding?}
    fixable -- no --> push[push + open PR]
    fixable -- "yes, fixed" --> fixcommit[fix: commit, rerun checks]
    fixcommit --> push
    fixable -- "yes, can't fix" --> stop([stop, branch stays local])
```

Example: `/zahidakhyar-skills:ship dev --issue 42 --auto-fix`

### pr-review

First review of someone else's PR, posted as a single GitHub review (one notification for the author).

```
/zahidakhyar-skills:pr-review <PR number|URL> [--comment]
```

- No PR given → lists PRs where your review is requested and asks which one.
- Checks the PR out in a throwaway worktree under `.worktrees/`, so your working tree is untouched.
- Runs `code-review`, plus `security-review`, a deploy-window check (migrations, cache keys, worker routing) and an `impeccable` UI audit when the diff calls for them.
- Every finding must have a concrete failure scenario and gets a label: **High**, **Medium**, **Low**, **Nit** or **Pre-existing**. Any High/Medium → request changes; otherwise approve.
- Shows you the draft and posts only after you say yes. `--comment` posts without asking.
- Writes a hidden `<!-- reviewed: <sha> -->` marker so `recheck` knows what you already saw.

Running it on a PR you already reviewed points you to `recheck`.

### recheck

Re-review after the author pushed fixes.

```
/zahidakhyar-skills:recheck <PR number|URL>
```

- Reviews only the delta since your last review (found through the `reviewed:` marker). After a force-push it reviews the whole PR again.
- Reads unresolved inline threads, review bodies and issue comments, all paginated.
- Gives each earlier finding a verdict: `FIXED`, `PARTIAL`, `NOT FIXED`, `REBUTTED-VALID` or `REBUTTED-REJECTED`, based on the code at the new head, never on the author's reply.
- Resolves fixed threads, replies under the ones still open, and posts one review with the verdict and any new findings from the fix commits.

### review-queue

Finds every open PR that requests your review and starts a separate session for each, so one PR's context never mixes into another's review. Desktop app only: it uses the app's session tools.

```
/zahidakhyar-skills:review-queue [--team] [--root <dir>] [--comment] [--every <interval>]
```

- Picks `pr-review` for a PR you never reviewed and `recheck` for one with new commits since your `reviewed:` marker. A PR with no new commits is listed as skipped.
- Reviews in your existing local clones, found by their `origin` remote under `--root` (default `$REVIEW_QUEUE_ROOT`, else `~/Repositories`). Each review runs in its own throwaway worktree, so your checked-out branch is untouched. A missing clone is reported, never cloned for you.
- `--team` also includes PRs that request a review from one of your teams.
- Shows the queue and asks once before starting anything. Runs at most 2 review sessions at a time, 1 per repo. When one finishes it reports and offers a "Start next" button for the rest.
- Finds earlier review sessions whose PR is now merged and offers to archive them in the same confirmation, even when no PR is waiting.
- A `pr-review` session shows its draft and waits for your yes there; `--comment` is passed on and makes it post without asking. A `recheck` session posts on its own, as `recheck` always does.
- `--every 30m` keeps checking through `/loop`: each new PR head is announced once (notification plus a "Start reviews" button), quiet ticks say nothing. The loop runs in that session only, while the app is open, and expires after 7 days.

### merged

Post-merge cleanup.

```
/zahidakhyar-skills:merged [PR number | branch] [--close-issues] [--dry-run]
```

- Confirms the PR is merged, removes its worktree, switches to the base and pulls, deletes the local and remote branch.
- Asks before touching anything with uncommitted changes.
- GitHub only auto-closes `Closes #N` issues for PRs into the default branch. For a PR into `dev`, the skill reports which issues are still open; `--close-issues` closes them.
- After a hotfix into `main`, checks whether `dev` needs a back-merge.
- Works in a folder with several sub-repos.
- `--dry-run` prints the commands without running them.

### release

Version bump plus release PR for a JS/TS project (`package.json`) or a Claude Code plugin (`.claude-plugin/plugin.json`).

```
/zahidakhyar-skills:release <major|minor|patch>
```

- Requires a clean tree and a `package.json`. No argument → shows the current version and asks.
- Bumps with `npm version --no-git-tag-version` (safe with yarn/pnpm), updates `CHANGELOG.md` if the repo has one, creates an annotated tag, and pushes branch and tag together.
- Opens a `release: vX.Y.Z` PR with a body built from the commits since the last tag.
- Merge it with "Create a merge commit", not squash; squash leaves the tag outside the target branch's history.
- After the merge, tell Claude the release PR is merged and it creates the GitHub release from the tag.

### orchestrate

Builds implementation plans in separate builder sessions while the current session coordinates. Made for cross-repo work (backend + frontend) where both sides must agree on one API contract.

```
/zahidakhyar-skills:orchestrate [plan path ...] [--contract <path>] [--opus]
```

- No path → the newest file in `docs/superpowers/plans/`.
- Two or more repos → locks a shared contract first, or uses `--contract <path>`.
- One builder session per plan, each in its own worktree. Builders run on Sonnet by default; the coordinator suggests Opus per plan where it pays off, and `--opus` puts every builder on Opus.
- When builders finish, runs a review-fix loop per repo and a combined cross-repo check, then has each builder `ship` its own PR when you say so.

```mermaid
sequenceDiagram
    actor You
    participant C as Coordinator (this session)
    participant BE as Builder: backend
    participant FE as Builder: frontend
    You->>C: /orchestrate plan-be.md plan-fe.md
    C->>C: lock API contract
    par one worktree each
        C->>BE: start session with plan + contract
        C->>FE: start session with plan + contract
    end
    BE-->>C: DONE / BLOCKED / CONTRACT
    FE-->>C: DONE / BLOCKED / CONTRACT
    loop until no High/Medium finding
        C->>BE: REVIEW / FIX
        C->>FE: REVIEW / FIX
    end
    C->>You: report per repo
    You->>C: ship it
    C->>BE: /ship --auto-fix --reviewed
    C->>FE: /ship --auto-fix --reviewed
```

Works only in the Claude desktop app's Code tab, which provides the session tools.

### deliver

One task carried to evidence: pass criteria, build, local E2E, PR, and after you merge, the same E2E scenarios on dev.

```
/zahidakhyar-skills:deliver <task | #issue | issue URL>
/zahidakhyar-skills:deliver continue [PR]
```

- Phase 1 writes 3–7 pass criteria and one scenario per criterion, builds with TDD in its own worktree under `.worktrees/` (your checkout, uncommitted files and running dev server stay untouched; the local run gets its own port and database), then runs every scenario locally (Playwright via the `playwright-cli` skill for web, HTTP calls for APIs). Evidence goes to `.deliver/<date>-<slug>/` in the main checkout, excluded from git.
- The app won't start locally → stops before `ship`, with no PR or draft PR, and names what is missing. Otherwise it runs `ship --auto-fix`; the PR's Test plan lists each local scenario.
- The merge is yours. Tell Claude it is merged and give the dev URL (`merged` also suggests `/deliver continue <PR>`). Phase 2 waits for the merge commit to be live (`/version` endpoint, GitHub Actions, Railway, or the Azure portal through Chrome), reruns the scenarios on dev, and comments the results on the PR.
- Logs in on dev only when the hostname has a test label (`dev`, `staging`, `test`, `qa`, `sandbox`, `preview`), with test accounts from the repo's seed or fixtures. Never touches prod, never merges.
- Every phase ends with the same five lines:

```
Verdict: PASS | PARTIAL | FAIL
Tested: <N> scenarios — <names>
Local: <n>/<N> pass
Dev: <n>/<N> pass @ <host> <sha7> | pending merge
Evidence: <path to report.md>
```

- Install, tests, build and the local E2E run one at a time across the whole machine (a lock in `~/.local/state`), so parallel sessions don't freeze a small laptop.
- Was called `autopilot` up to v0.3.0. Runs started under `.autopilot/` are still found.

### autopilot

Your assistant. One coordinator session watches your queues and starts one session per item, so you can spend your time writing the next issues.

```
/zahidakhyar-skills:autopilot [--root <dir>] [--every 10m] [--max 4] [--no-slack] [--dry-run]
```

- **Issues** come from a rule per repo, in `.claude/autopilot.md`:

  ```markdown
  ## Pickup
  rule: assignee:@me            # team repo
  # rule: label:ready-for-agent # solo repo
  base: dev                     # optional
  ```

  Each issue goes to its own `deliver` session. Repos without the section are not watched for issues. In a workspace folder that holds several clones, one `## Pickup` at the workspace root covers every clone under it; a clone's own section overrides it.
- **Review requests** go to `pr-review` / `recheck` sessions, as in `review-queue`.
- **Slack mentions** are classified. Status replies (`[Autopilot] Sudah direview …`, `[Autopilot] Diambil …`) are drafted and sent only after you approve the exact text. Questions and decisions are passed to you. A Slack message never starts work by itself.
- Up to `--max` sessions code in parallel; sessions waiting on you don't count. Heavy commands still run one at a time.
- `/autopilot` starts the first batch right away. Later checks (every `--every`) can't start sessions on their own, so they notify you and ask "Start these?".
- After a `deliver` PR is merged it asks for the dev URL and continues that session's dev E2E.
- Desktop app only. It runs while the app is open; nothing runs in the cloud.

### learned

Turns corrections, confirmed choices and project decisions from the session into memory files Claude reads next time.

```
/zahidakhyar-skills:learned
/zahidakhyar-skills:learned consolidate
```

- Writes one fact per file to the project's memory directory and updates the `MEMORY.md` index. Updates an existing memory instead of adding a duplicate.
- Skips what the code, git history or CLAUDE.md already say.
- Also triggers by itself after a correction or "remember this" / "catat ini".
- `consolidate` merges duplicates and prunes stale memories via `anthropic-skills:consolidate-memory`.

## Per-repo configuration

The skills read their conventions from the repo they run in. None of these files are required.

| File / convention | Read by | Effect |
|---|---|---|
| `REVIEW.md` at the repo root | `pr-review`, `recheck` | Overrides the [default review protocol](skills/pr-review/references/review-protocol.md): severity definitions, Nit limit, review language, areas whose bugs are always High. Read from the PR's base branch, so a PR cannot change its own rules |
| `CLAUDE.md` / `AGENTS.md` | `pr-review`, `recheck` | Project rules that findings and author rebuttals are checked against |
| `## Risk` line in the PR body | `pr-review` | Sets review depth. `ship` writes it; for PRs opened without it, the tier is derived from the changed files |
| `package.json` scripts, `.github/workflows/*.yml` | `ship`, `pr-review`, `recheck` | Source of the typecheck, lint and test commands. A green CI check that already runs them is cited instead of re-run |
| `dev` / `develop` branch | `ship`, `orchestrate` | Default PR target when present |
| `CHANGELOG.md` | `release` | Updated on each release when present |
| `.claude/autopilot.md` | `deliver`, `autopilot` | Local start command, dev URL hint, deploy signal, test-account source (drafted by `deliver` on its first run and committed in that PR). The `## Pickup` section opts the repo into `autopilot` |

## Requirements

- Claude Code with plugin support.
- `git`, `gh` (logged in with `gh auth login`) and `jq` on the PATH.

Optional plugins. The skills skip the step when the plugin is missing:

| Plugin | Used by | For |
|---|---|---|
| `humanizer` | `pr-review`, `release` | Rewriting review and PR prose so it reads naturally |
| `impeccable` | `pr-review` | UI audit on frontend diffs |
| `superpowers` | `orchestrate`, `deliver` | Plan execution inside builder sessions; TDD during the build |
| `anthropic-skills` | `learned` | `/learned consolidate` |

`code-review` and `security-review` are built into Claude Code.

## Updating

```bash
claude plugin marketplace update zahidakhyar
```

Installed copies are cached per version (`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`), so a change reaches users only after the maintainer bumps `version` in `.claude-plugin/plugin.json`. Release notes are in [CHANGELOG.md](CHANGELOG.md).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `/zahidakhyar-skills:ship` is not recognised | Start a new session after installing; check `claude plugin details zahidakhyar-skills` |
| Every skill shows up twice | The skills are loaded from both the plugin and `~/.claude/skills/`. Keep only one (see [local setup](CONTRIBUTING.md#local-setup)) |
| A change on `main` doesn't arrive | Check that `version` was bumped, then run `claude plugin marketplace update zahidakhyar` |
| `gh: command not found` / `HTTP 401` | Install `gh` and run `gh auth login` |
| `orchestrate` can't start sessions | It needs the Claude desktop app's Code tab |

## Contributing

Bug reports, fixes and new skills are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for local setup, how to write a skill, and the checks CI runs. Report security problems through [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
