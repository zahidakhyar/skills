---
name: ship
description: Use when the user wants current changes turned into a PR — types `/ship [base] [--issue N] [--draft] [--auto-fix] [--reviewed]`, or asks variations of "commit dan push lalu buat PR", "buat branch baru base dev, push, PR target dev", "ship ini", "ship sekalian auto-fix". Covers the full branch → commit → push → PR cycle.
---

# Ship

Run the branch → commit → gate → push → PR cycle in one go, without stopping for confirmation. Final output: the PR URL.

## Arguments

A token starting with `--` is a flag, and `--issue` takes the token after it as its value (`--issue=N` is the same); the one remaining token is the base/target branch. No base → step 2 decides it.

| Flag | Effect |
|---|---|
| `--issue N` | Issue number for `Closes #N`; it wins over a number found in the branch name or a commit message (step 8). Issue in another repo → `--issue owner/repo#N`: the `Closes` line writes it exactly like that, because a bare `#N` points at the PR's repo. |
| `--draft` | Create the PR as a draft (step 8). In a repo without branch protection, draft is the only thing that keeps an unreviewed PR from being merged. |
| `--reviewed` | Skip step 6c (code and security review); the checks in 6b still run. Used by `/orchestrate`, whose review-fix loop already reviewed this branch. |
| `--auto-fix` | Once the PR exists, turn on the app's Auto-fix switch for it (step 10): this session is woken through `<ci-monitor-event>` when CI fails, a merge conflict appears, or a review comment arrives. Without this flag step 10 only offers it. The name follows the checkbox label in the app's CI popover, not a synonym. |

## Flow

1. Check state — `git status --porcelain` + `git log HEAD --not --remotes --oneline 2>/dev/null` (commits not on any remote).
   - `origin` is a GitHub URL → `gh repo view --json name`, which reaches the repo the way `gh pr create` will. An authentication error → stop here with the `gh auth login` instruction, before anything is committed or reviewed for a PR that cannot be created.
   - `origin` is a GitHub URL and this is a feature branch (not `dev`, `develop`, the default branch or the branch the base argument names) → look up its PRs once: `gh pr list --head "$(git branch --show-current)" --state all --json url,state,baseRefName,isDraft,headRefOid`. The one whose state is `OPEN` is "the open PR" that steps 2, 6 and 8 reuse; several open → stop and list them, the user picks. Any other remote, any other branch, or a detached HEAD has no PR to find.
   - No uncommitted changes AND no unpushed commits → stop: "nothing to ship". Two cases do not stop. An open PR and a flag that acts on it (`--auto-fix`, `--draft`, `--issue`) → decide the base with step 2, skip steps 3 to 7, then run step 8's open-PR bullet and steps 9 and 10; nothing was pushed, so `## Risk` and the Test plan are left alone. One of those flags with no open PR to act on → the stop message also says the flag was not applied, and why. The other case continues through every step: a feature branch on GitHub with no open PR, no merged or closed PR whose `headRefOid` is `git rev-parse HEAD` (that one already shipped this commit), and commits ahead of its base. Decide the base with step 2 first, then `git rev-list --count "origin/<base>"..HEAD` (`<base>` when it is not on the remote) must be above 0. It was pushed by hand, or an earlier run stopped after the push, so its PR was never created.

2. Decide the base/target branch — the open PR from step 1 keeps its base: use its `baseRefName`, and when the argument names another branch, say in the output that it was ignored. No open PR → the argument if given (`/ship main`). Otherwise:
   ```bash
   git branch -a --format='%(refname:short)' | grep -qxE '(origin/)?dev' && echo dev \
     || (git branch -a --format='%(refname:short)' | grep -qxE '(origin/)?develop' && echo develop) \
     || git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|origin/||' | grep . \
     || gh repo view --json defaultBranchRef -q .defaultBranchRef.name
   ```
   Order: `dev` → `develop` → the repo's default branch (`origin/HEAD`, or `gh` when the remote was added by hand with `git remote add`).

3. Decide the working branch:
   - On the base or default branch → create a new branch from the current position: `git checkout -b <type>/<slug>`. Derive the name from the change (e.g. `feat/margin-filter-page`, `fix/otp-expiry`). A new branch has no PR, whatever step 1 found.
   - Already on a feature branch → use it, do not create a new one.

4. Format — tidy only the files this branch changed, before staging: commits since branching from base, staged, unstaged, and untracked. Skip silently when prettier is not installed in this repo:
   ```bash
   mb=$(git merge-base "origin/<base>" HEAD 2>/dev/null || git merge-base "<base>" HEAD)
   [ -x node_modules/.bin/prettier ] && { git diff --name-only --diff-filter=ACMR -z "$mb"; git ls-files --others --exclude-standard -z; } | xargs -0 node_modules/.bin/prettier --write --ignore-unknown
   ```
   Diff against the merge-base, not `HEAD`: `git diff HEAD` only sees the working tree, so a branch whose commits were made before `/ship` arrives here with a clean tree and nothing gets formatted. Do not use `pnpm format` — that script rewrites all of `src/**` and fills the PR diff with noise. This is the formatter only; lint (eslint/oxlint) runs in step 6b.

   **Generated files must be in `.prettierignore` before this step runs** — lockfiles, `openapi.json`, `src/api/generated/`, `dist/`, `coverage/`. Prettier honours `.prettierignore` even for files passed explicitly, but without that file this step would tidy machine artefacts: a reformatted `openapi.json` makes `contract:check` drift, and a lockfile must never be formatted by hand. Repo has no `.prettierignore` yet → create it first and include it in this commit.

5. Commit — analyse `git diff` + `git status`, write a conventional commit: `<type>: <description>`, an optional body after a blank line, type one of `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`. Check the untracked list before staging: files that look like secrets/artefacts (`.env*`, credentials, `dist/`, etc.) stay out — report and skip them, `git add` the rest. **Plans/specs stay out**: files in `docs/superpowers/plans/`, `docs/superpowers/specs/`, `docs/plans/`, `docs/specs/` are never staged — if `.gitignore` does not list them yet, add the lines and include `.gitignore` in this commit. Step 4's output goes into this commit. Tree clean at step 1 and `git status --porcelain` still empty after step 4 → skip this step. Tree clean at step 1 but step 4 changed files → a separate `chore: format` commit, never an amend: the changes may belong to several earlier commits, not just the last one.

6. Gate — verify the branch before anything leaves the machine. Scope is the branch diff, `git diff --name-only "$mb"...HEAD`, with `mb` recomputed as in step 4 (shell state does not carry over). The whole branch diff touches only README, changelog or copy text → the tier is Low; skip the rest of this step and say so in one Test plan line. Specs, plans, ADRs and design docs are not that case: skip (b), run (c) at the tier of the code they describe. Open PR from step 1 → scope for (b) is `origin/<branch>...HEAD`, the commits the PR does not have yet (`git fetch origin <branch>` first when that ref is missing locally); run (a), (b) and (d), skip (c): the PR's own review (`/recheck`) covers new commits. Branch on a GitHub remote with no open PR → nothing has reviewed it: full branch scope, (c) included. Remote is not GitHub, where step 1 cannot see a PR, and the branch is already on it → treat it as the open-PR case. `--reviewed` → skip (c) as well; the Test plan says which review ran before.

   a. Risk tier — decided from the changed paths of the whole branch diff (`"$mb"...HEAD`), also when (b) runs on a narrower scope: `## Risk` describes the PR, not the last push. The review effort below and step 8's `## Risk` both use it. The highest-tier file sets the tier, and a file that fits two rows takes the higher one. A spec, plan, ADR or design doc takes the tier of the code it describes: a spec for a migration that drops a column is High, not docs. Tiers defined in the repo's `REVIEW.md` or PR template win over this table.

   | Tier | Changed paths or content | `code-review` effort |
   |---|---|---|
   | Low | README, changelog, comments, copy strings, tests only, formatting; an additive change behind a flag that is off by default, with no migration and no change to an existing API or event | `low` |
   | Medium | ordinary product change, cache, queues, config, env | `medium` |
   | High | money (wallet, ledger, payment, top-up, withdrawal, refund, quota), auth/session/permissions, a migration that rewrites or drops data, `.github/workflows/`, a path listed in `CODEOWNERS` | `high` |

   b. Checks — typecheck, lint, then tests, one command at a time. When `${CLAUDE_SKILL_DIR}/../deliver/scripts/heavy.sh` exists, run each of them as `bash ${CLAUDE_SKILL_DIR}/../deliver/scripts/heavy.sh <command>`, so parallel sessions never run two heavy commands at once. Commands come from the repo (`package.json` scripts, the CI workflow); [`references/gates.md`](references/gates.md) is the fallback and holds the worker caps (`--maxWorkers=2`, `1` while a dev server runs). Lint only the changed files: a repo `lint` script that sweeps all of `src` is replaced by `node_modules/.bin/eslint <files>`, so old warnings elsewhere do not block. Tests: only those related to the changed files (`jest --findRelatedTests <files> --passWithNoTests`, `vitest related <files> --passWithNoTests`); zero related tests is written as such in the Test plan, never as a pass. Typecheck covers the whole project; an error in a file this branch did not touch is pre-existing and goes under `## Out of scope`.

   c. Review — `code-review` at the effort from (a). Medium and High run in a context that did not write the diff:
      - Low → invoke the `code-review` skill inline with `args: "low <branch>"`.
      - Medium or High → dispatch one `general-purpose` subagent (foreground) with exactly: "Read only: no edit, commit, push or PR comment. `cd <absolute repo path>` and run every command there. Invoke the `code-review` skill with `args: "<effort> <branch>"`; the range to review is `<base ref>...<branch>`. Return its findings unchanged as your final reply, each with its `path:line`." `<base ref>` is `origin/<base>`, or `<base>` when it is not on the remote: a cold context cannot guess the base. The session that wrote the code shares its blind spots, so the prompt carries no summary of the change and no hint of what to look for. No tool to start a subagent in this session (ship itself runs inside one) → run it inline and say so in the Test plan.
      - `security-review` when the diff touches auth, sessions or permissions, endpoint input (controller, DTO, route handler, server action, webhook), a query built from input, file upload, HTML rendered from user content, or secrets/env handling → one more `general-purpose` subagent (foreground) with "Read only: no edit, commit or push. `cd <absolute repo path>` and run every command there. Invoke the `security-review` skill and return its markdown report as your final reply." Never invoke it inline: its "nothing else" rule arrives as a user message and ends this turn before (d) and the push. Both subagents needed → send them in one message, so they run together.

      The decisions stay in this session. Findings from a subagent arrive without a severity: re-read the code behind each one and set it here before acting. A real bug this diff introduced → fix it. A bug the diff did not introduce → `## Out of scope`. Style-only finding → skip.

      Visual QA — runs after the review whether or not the review ran (`--reviewed`, an open PR), when the branch diff touches web UI files (the list in the `visual-qa` skill, step 1). Skip it when `.visual-qa/<branch with / replaced by ->/result` reads `PASS <sha>` and `git diff --name-only <sha>..HEAD` holds no UI file. Otherwise invoke the `visual-qa` skill inline with `args: "<base>"`; it commits its own fixes. `PASS` → its report line goes into the Test plan. `FAIL` after its last round → stop before the push, like an unfixable High finding. `UNVERIFIED` (the app cannot start, no subagent tool) → a `- [ ] UNVERIFIED: Visual QA (<reason>)` line, then continue.

   d. Result — fixes from (b) and (c) go into a new `fix:` commit on top, never an amend; run step 4's formatter again before that commit, then rerun typecheck and the related tests. Still red after the fix, or a High/Medium finding that cannot be fixed here → stop before the push, report the failing output or the finding, leave the branch local. A check that cannot start on this machine (connection refused to a database or service, missing credentials) → `- [ ] UNVERIFIED:` line, then continue; an assertion that fails is red, not UNVERIFIED. High tier with any UNVERIFIED test line → step 8 creates the PR with `--draft`. Every command run and the review result (`code-review medium` → 3 findings, 2 fixed, 1 out of scope) become step 8's Test plan lines.

7. Push — `git push -u origin <branch>`.

8. PR — create it, or update the open one from step 1:
   - An open PR exists → no create; its URL is this step's result. Fetch the body once, `gh pr view <url> --json body -q .body` into a file, apply the two rules below, and run `gh pr edit <url> --body-file <file>` only when the file changed. Every other section stays as written.
     - This run pushed commits → raise the `## Risk` line to the tier from 6a when that is higher, written as the Risk rule below says (a tier in the body that is already higher stays: a reviewer may have set it), and append this run's lines to the Test plan section under whatever heading the body gives it (add either section when the body has none).
     - `--issue N` is set and no `Closes` line names that issue → add one as the first line.

     `--draft` is set and `isDraft` is false → `gh pr ready <url> --undo`; step 6d's draft rule applies at creation only, so a PR a human marked ready stays ready.
   - None yet → find the issue number: the argument (`/ship --issue 271`), then branch name `<type>/<N>-slug`, then a GitHub closing keyword before `#N` in a commit message (`close`/`closes`/`closed`, `fix`/`fixes`/`fixed`, `resolve`/`resolves`/`resolved`). A bare `#N` in a commit message is a mention, not a close. Found → `gh issue view <N> --json title,body` (issue in another repo: `gh issue view <N> -R owner/repo --json title,body`).
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

9. Output — the PR URL, then a 1-line summary (branch, target, diff size from `git diff --shortstat origin/<base>...HEAD`, or `<base>...HEAD` when base is not on the remote, same as step 4). Diff >400 LOC → add one line suggesting a split; do not block. Step 10's line, when it has one, comes last.

10. Auto-fix — only when step 8 produced a PR URL (newly created or already open). No URL (no remote, remote is not GitHub) → `--auto-fix` does nothing; say in the output that the flag was skipped and why.
   - With `--auto-fix`, in this order:
     1. `mcp__ccd_pr__get_status` — check whether the PR bar is already bound to this PR. The app's cache can lag behind a `gh pr create` that just ran, so a PR missing here is not an error.
     2. Not bound → `mcp__ccd_pr__bind_pr({ url })` first.
     3. `mcp__ccd_pr__set_monitor({ auto_fix: true, address_comments: true, url })`. `address_comments` is required and must equal `auto_fix`; the app rejects the call when only one is sent.
     The approval dialog that appears here belongs to the app, not to the agent asking — it does not violate "no confirmation", do not skip the call.
   - Without `--auto-fix` → `mcp__ccd_pr__get_status` for CI status, then a one-line offer to turn Auto-fix on. Do not call `set_monitor`. A yes on the next turn runs the same three calls as the flag path, and so does `/ship --auto-fix` typed later on the same clean branch (step 1 lets it through).
   - `--auto-fix` **never** calls `mcp__ccd_pr__set_auto_merge`. Auto-merge is turned on only when the user asks for it by that word.
   - Do not poll `gh pr checks` after the PR is created; `get_status` already reads CI from the app's cache.

## Quick reference

| Situation | Behaviour |
|---|---|
| On `dev` with changes | New branch from dev → commit → gate → push → PR to dev |
| On a feature branch with changes | Commit on that branch → gate → push → PR to base |
| Clean working tree, unpushed commits | Format → `chore: format` commit only if step 4 changed files → gate → push → PR |
| An open PR already exists for this branch, new changes or commits | Format → commit if anything changed → gate on the new commits, no review → push → raise `## Risk` if needed and add Test plan lines in that PR, show its URL |
| Branch pushed, clean tree, never had a PR | Gate on the whole branch, review included → PR |
| Medium or High tier | `code-review` runs in a `general-purpose` subagent; Low runs inline |
| README/changelog/copy-only diff | Gate skipped, one Test plan line says so |
| Specs/plans/design docs only | Checks skipped, review runs at the tier of the code they describe |
| Gate still red after a fix, or a High/Medium finding that cannot be fixed | Stop before push, report it, branch stays local |
| `--auto-fix`, PR exists (new or existing) | Step 10: bind if needed → `set_monitor` auto_fix + address_comments |
| `--auto-fix`, no PR got created | Flag skipped, output states why |
| Clean, pushed, PR open, with `--auto-fix`, `--draft` or `--issue` | No commit, gate or push: the flag is applied to that PR |
| Nothing to ship | Stop with a message, never create an empty branch/PR |

## Error handling

- Remote is not GitHub / no remote → stop after the push (or before it, when there is no remote), explain why no PR was created.
- `gh` not authenticated → caught in step 1, before the gate: show the `gh auth login` instruction, do not retry blindly.
- Push rejected (non-fast-forward) → report and offer options; **never force-push**.
