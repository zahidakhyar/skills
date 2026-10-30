---
name: ship
description: Use when the user wants current changes turned into a PR — types `/ship [base] [--issue N] [--draft] [--auto-fix]`, or asks variations of "commit dan push lalu buat PR", "buat branch baru base dev, push, PR target dev", "ship ini", "ship sekalian auto-fix". Covers the full branch → commit → push → PR cycle.
---

# Ship

Run the branch → commit → gate → push → PR cycle in one go, without stopping for confirmation. Final output: the PR URL.

## Arguments

A token starting with `--` is a flag; the one remaining token is the base/target branch. No base → step 2 decides it.

| Flag | Effect |
|---|---|
| `--issue N` | Issue number for `Closes #N`, used when neither the branch name nor the commit message mentions one (step 8). Issue in another repo → `--issue owner/repo#N`: the `Closes` line writes it exactly like that, because a bare `#N` points at the PR's repo. |
| `--draft` | Create the PR as a draft (step 8). In a repo without branch protection, draft is the only thing that keeps an unreviewed PR from being merged. |
| `--reviewed` | Skip step 6c (code and security review); the checks in 6b still run. Used by `/orchestrate`, whose review-fix loop already reviewed this branch. |
| `--auto-fix` | Once the PR exists, turn on the app's Auto-fix switch for it (step 10): this session is woken through `<ci-monitor-event>` when CI fails, a merge conflict appears, or a review comment arrives. Without this flag step 10 only offers it. The name follows the checkbox label in the app's CI popover, not a synonym. |

## Flow

1. Check state — `git status --porcelain` + `git log HEAD --not --remotes --oneline 2>/dev/null` (commits not on any remote).
   No uncommitted changes AND no unpushed commits → stop: "nothing to ship".

2. Decide the base/target branch — use the argument if given (`/ship main`). Otherwise:
   ```bash
   git branch -a --format='%(refname:short)' | grep -qxE '(origin/)?dev' && echo dev \
     || (git branch -a --format='%(refname:short)' | grep -qxE '(origin/)?develop' && echo develop) \
     || git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|origin/||' | grep . \
     || gh repo view --json defaultBranchRef -q .defaultBranchRef.name
   ```
   Order: `dev` → `develop` → the repo's default branch (`origin/HEAD`, or `gh` when the remote was added by hand with `git remote add`).

3. Decide the working branch:
   - On the base or default branch → create a new branch from the current position: `git checkout -b <type>/<slug>`. Derive the name from the change (e.g. `feat/margin-filter-page`, `fix/otp-expiry`).
   - Already on a feature branch → use it, do not create a new one.

4. Format — tidy only the files this branch changed, before staging: commits since branching from base, staged, unstaged, and untracked. Skip silently when prettier is not installed in this repo:
   ```bash
   mb=$(git merge-base "origin/<base>" HEAD 2>/dev/null || git merge-base "<base>" HEAD)
   [ -x node_modules/.bin/prettier ] && { git diff --name-only --diff-filter=ACMR -z "$mb"; git ls-files --others --exclude-standard -z; } | xargs -0 node_modules/.bin/prettier --write --ignore-unknown
   ```
   Diff against the merge-base, not `HEAD`: `git diff HEAD` only sees the working tree, so a branch whose commits were made before `/ship` arrives here with a clean tree and nothing gets formatted. Do not use `pnpm format` — that script rewrites all of `src/**` and fills the PR diff with noise. This is the formatter only; lint (eslint/oxlint) does not run here and does not block the ship.

   **Generated files must be in `.prettierignore` before this step runs** — lockfiles, `openapi.json`, `src/api/generated/`, `dist/`, `coverage/`. Prettier honours `.prettierignore` even for files passed explicitly, but without that file this step would tidy machine artefacts: a reformatted `openapi.json` makes `contract:check` drift, and a lockfile must never be formatted by hand. Repo has no `.prettierignore` yet → create it first and include it in this commit.

5. Commit — analyse `git diff` + `git status`, write a conventional commit: `<type>: <description>`, an optional body after a blank line, type one of `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`. Check the untracked list before staging: files that look like secrets/artefacts (`.env*`, credentials, `dist/`, etc.) stay out — report and skip them, `git add` the rest. **Plans/specs stay out**: files in `docs/superpowers/plans/`, `docs/superpowers/specs/`, `docs/plans/`, `docs/specs/` are never staged — if `.gitignore` does not list them yet, add the lines and include `.gitignore` in this commit. Step 4's output goes into this commit. Tree clean at step 1 and `git status --porcelain` still empty after step 4 → skip this step. Tree clean at step 1 but step 4 changed files → a separate `chore: format` commit, never an amend: the changes may belong to several earlier commits, not just the last one.

6. Gate — verify the branch before anything leaves the machine. Scope is the branch diff, `git diff --name-only "$mb"...HEAD`, with `mb` recomputed as in step 4 (shell state does not carry over). Diff touches only README, changelog or copy text → skip this step and say so in one Test plan line. Specs, plans, ADRs and design docs are not that case: skip (b), run (c) at the tier of the code they describe. Branch already on the remote (`git rev-parse -q --verify origin/<branch>`) → scope is `origin/<branch>...HEAD`, run (b) and (d) only, skip (c): the PR's own review (`/recheck`) covers new commits. `--reviewed` → skip (c) as well; the Test plan says which review ran before.

   a. Risk tier — decided from the changed paths; the review effort below and step 8's `## Risk` both use it. The highest-tier file sets the tier, and a file that fits two rows takes the higher one. A spec, plan, ADR or design doc takes the tier of the code it describes: a spec for a migration that drops a column is High, not docs. Tiers defined in the repo's `REVIEW.md` or PR template win over this table.

   | Tier | Changed paths or content | `code-review` effort |
   |---|---|---|
   | Low | README, changelog, comments, copy strings, tests only, formatting; an additive change behind a flag that is off by default, with no migration and no change to an existing API or event | `low` |
   | Medium | ordinary product change, cache, queues, config, env | `medium` |
   | High | money (wallet, ledger, payment, top-up, withdrawal, refund, quota), auth/session/permissions, a migration that rewrites or drops data, `.github/workflows/`, a path listed in `CODEOWNERS` | `high` |

   b. Checks — typecheck, lint, then tests, one command at a time. Commands come from the repo (`package.json` scripts, the CI workflow); [`references/gates.md`](references/gates.md) is the fallback and holds the worker caps (`--maxWorkers=2`, `1` while a dev server runs). Lint only the changed files: a repo `lint` script that sweeps all of `src` is replaced by `node_modules/.bin/eslint <files>`, so old warnings elsewhere do not block. Tests: only those related to the changed files (`jest --findRelatedTests <files> --passWithNoTests`, `vitest related <files> --passWithNoTests`); zero related tests is written as such in the Test plan, never as a pass. Typecheck covers the whole project; an error in a file this branch did not touch is pre-existing and goes under `## Out of scope`.

   c. Review — invoke the `code-review` skill with `args: "<effort> <branch>"`, effort from (a). Also run `security-review` when the diff touches auth, sessions or permissions, endpoint input (controller, DTO, route handler, server action, webhook), a query built from input, file upload, HTML rendered from user content, or secrets/env handling: dispatch one `general-purpose` subagent (foreground) with "`cd <absolute repo path>` and run every command there. Invoke the `security-review` skill and return its markdown report as your final reply." Never invoke it inline: its "nothing else" rule arrives as a user message and ends this turn before (d) and the push. Re-read the code behind each finding before acting on it. A real bug this diff introduced → fix it. A bug the diff did not introduce → `## Out of scope`. Style-only finding → skip.

   d. Result — fixes from (b) and (c) go into a new `fix:` commit on top, never an amend; then rerun typecheck and the related tests. Still red after the fix, or a High/Medium finding that cannot be fixed here → stop before the push, report the failing output or the finding, leave the branch local. A check that cannot start on this machine (connection refused to a database or service, missing credentials) → `- [ ] UNVERIFIED:` line, then continue; an assertion that fails is red, not UNVERIFIED. High tier with any UNVERIFIED test line → step 8 creates the PR with `--draft`. Every command run and the review result (`code-review medium` → 3 findings, 2 fixed, 1 out of scope) become step 8's Test plan lines.

7. Push — `git push -u origin <branch>`.

8. PR — first check `gh pr list --head <branch> --json url,state`:
   - An open PR exists → skip create, show its URL.
   - None yet → find the issue number: branch name `<type>/<N>-slug`, then `#N` in the commit message, then the argument (`/ship --issue 271`). Found → `gh issue view <N> --json title,body` (issue in another repo: `gh issue view <N> -R owner/repo --json title,body`).
   - `gh pr create --base <base>` (add `--draft` when the flag is set or step 6d calls for it) with a conventional title and a body in the language the user's rules set for PR descriptions (CLAUDE.md or files it imports); no such rule → English. Section headings are translated into that language too, except the literal `Closes`, `## Risk` and its `Low|Medium|High` value, which other skills parse. The body follows the shape below, in this order. Sections marked *conditional* are written only when their condition holds; no section ever says "none" or "N/A".

     ```markdown
     Closes #N

     ## Summary

     <1–2 sentences: what changes for the user or the system after merge.>

     - <one change per bullet: what, where ([file.ts](src/path/file.ts)), why this approach>

     ### Why <approach>

     ## Flow

     **Before** <mermaid block>
     **After** <mermaid block>

     ## Rollout

     ## Risk

     <Low|Medium|High>: <the file or area that set the tier, one sentence.>

     ## Revert

     - <a `git revert` of the merge commit is enough, or one extra step per bullet>

     ## Test plan

     - [x] `<exact command>` → <result: files/tests count, exit code, measured numbers>
     - [ ] UNVERIFIED: <what was not run locally>. <Why, and who runs it (CI, after deploy).>

     ## Out of scope
     ```

     - **`Closes`** — the first line, one line per issue, only when an issue was found (`Closes owner/repo#N` for another repo). No opening paragraph above it.
     - **Summary** — the opening sentence states the outcome, the bullets state the changes. Each bullet is one line, at most 5 bullets; longer detail moves to the issue. When `## Flow` is written, the bullets are one per changed file, shaped `[file](path): <why it changed>`; states, steps, and their order appear only in the diagram. It says what changed and why, not the problem: the problem already lives in the issue, and repeating it creates two sources that can disagree. Exception: the issue body is empty, title-only, or there is no issue → add a 2–3 line `## Problem` before Summary, and say in the output that the issue needs filling in. A PR closing several issues → one bullet per issue, prefixed `#N:`.
     - **`### Why <approach>`** (conditional) — written only when the change compared two or more named options or measured something (numbers exist). No comparison or numbers → omit the section. Content is data, ideally a table (option, result, numbers), not opinion.
     - **`## Flow`** (conditional) — the diff changes call order, adds/removes a state transition, or moves a dependency between modules/services. One fenced `mermaid` block under **Before**, one under **After**: `sequenceDiagram` for call order, `stateDiagram-v2` for states, `flowchart` for dependencies; both blocks use the same type so they compare side by side. Every participant/node name is copied verbatim from an identifier or status in the diff (`createOrder`, `PENDING`); a generic label like `API`, `DB`, or `Service` that is not in the code is not a node. Max ~12 nodes per diagram; draw only the part that changed. A new flow with no prior version → **After** only.
     - **`## Rollout`** (conditional) — any of: a migration, `openapi.json` changed so another repo must regenerate, release order relative to a PR in another repo (write `owner/repo#N`), a new env var or service config, a manual step after deploy. One bullet per item, phrased as an action.
     - **`## Risk`** — always written, one line: the tier from step 6a and the file or area that set it. High → add which part a human reviewer should read first.
     - **`## Revert`** — always written. States whether a plain `git revert` of the merge commit undoes everything. When it does not, one bullet per extra step: the migration revert command (e.g. `yarn migration:revert`) and whether `down` loses data, a flag to turn off, env/config to roll back, data or queued jobs a revert leaves behind, a PR in another repo to revert first (`owner/repo#N`). Rollout holds the forward steps; Revert holds only how to undo them.
     - **Test plan** — step 6's commands and review result. Commands actually run and their results, not a plan. Checkboxes on every line. Anything not run is written as `- [ ] UNVERIFIED:` with the reason, never dropped. A test written first that failed before the fix → quote its failure message.
     - **`## Out of scope`** (conditional) — related things deliberately left out, or limitations found. Name the issue if one exists.
     - Length: the body, mermaid blocks excluded, fits one screen (~25 lines). Over that → cut detail from Summary; it belongs in the issue.
     - Tone: factual and specific (file names, functions, numbers). No promotional adjectives, no emoji other than the attribution footer, nothing repeated across two sections.

9. Output — the PR URL only, plus a 1-line summary (branch, target, diff size from `git diff --shortstat origin/<base>...HEAD`, or `<base>...HEAD` when base is not on the remote, same as step 4). Diff >400 LOC → add one line suggesting a split; do not block.

10. Auto-fix — only when step 8 produced a PR URL (newly created or already open). No URL (no remote, remote is not GitHub, `gh` not authenticated) → `--auto-fix` does nothing; say in the output that the flag was skipped and why.
   - With `--auto-fix`, in this order:
     1. `mcp__ccd_pr__get_status` — check whether the PR bar is already bound to this PR. The app's cache can lag behind a `gh pr create` that just ran, so a PR missing here is not an error.
     2. Not bound → `mcp__ccd_pr__bind_pr({ url })` first.
     3. `mcp__ccd_pr__set_monitor({ auto_fix: true, address_comments: true, url })`. `address_comments` is required and must equal `auto_fix`; the app rejects the call when only one is sent.
     The approval dialog that appears here belongs to the app, not to the agent asking — it does not violate "no confirmation", do not skip the call.
   - Without `--auto-fix` → `mcp__ccd_pr__get_status` for CI status, then a one-line offer to turn Auto-fix on. Do not call `set_monitor`. A yes on the next turn runs the same three calls as the flag path. Do not suggest re-running `/ship --auto-fix`: the tree is already clean and pushed, so step 1 stops before reaching here.
   - `--auto-fix` **never** calls `mcp__ccd_pr__set_auto_merge`. Auto-merge is turned on only when the user asks for it by that word.
   - Do not poll `gh pr checks` after the PR is created; `get_status` already reads CI from the app's cache.

## Quick reference

| Situation | Behaviour |
|---|---|
| On `dev` with changes | New branch from dev → commit → gate → push → PR to dev |
| On a feature branch with changes | Commit on that branch → gate → push → PR to base |
| Clean working tree, unpushed commits | Format → `chore: format` commit only if step 4 changed files → gate → push → PR |
| An open PR already exists for this branch | Format → commit if anything changed → gate → push, show the existing PR |
| README/changelog/copy-only diff | Gate skipped, one Test plan line says so |
| Specs/plans/design docs only | Checks skipped, review runs at the tier of the code they describe |
| Gate still red after a fix, or a High/Medium finding that cannot be fixed | Stop before push, report it, branch stays local |
| `--auto-fix`, PR exists (new or existing) | Step 10: bind if needed → `set_monitor` auto_fix + address_comments |
| `--auto-fix`, no PR got created | Flag skipped, output states why |
| Nothing to ship | Stop with a message, never create an empty branch/PR |

## Error handling

- Remote is not GitHub / no remote → stop after the push (or before it, when there is no remote), explain why no PR was created.
- `gh` not authenticated → show the `gh auth login` instruction, do not retry blindly.
- Push rejected (non-fast-forward) → report and offer options; **never force-push**.
