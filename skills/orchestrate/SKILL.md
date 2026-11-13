---
name: orchestrate
description: Use when one or more implementation plans are ready and the user wants them built in separate builder sessions while this session stays the coordinator — types `/orchestrate [plan path ...] [--contract <path>] [--opus]`, or says "orchestrate ini", "kerjakan plan 1", "jalankan plan ini di session lain", "handoff ke builder", "session ini planner/parent, buat child-nya", "task cross repo", "BE dan FE sekaligus", "kerjakan di 2 repo", "jadi parent untuk ini". Especially use it for cross-repo work (backend + frontend, service + client) where several repos must agree on one API contract. Not for writing the plans (writing-plans) and not for interval loops (/loop).
---

# Orchestrate

This session is the **coordinator**. It hands each plan to its own child session (one per repo), keeps the shared contract, relays changes between children, and reviews the combined result. It never edits code itself: once it starts building, its context fills up and nobody is left holding the overall picture.

One plan in one repo is just the N=1 case of the same flow.

Children execute their plan **inline** (`superpowers:executing-plans`) by default, whatever execution skill the plan recommends. This skill already reviews at the end (step 5 review-fix loop, step 6 seam check, the coordinator's diff review, the child's advisor), so the per-task review of `superpowers:subagent-driven-development` mostly duplicates it, while costing a cold-start subagent per task and handing tasks it judges mechanical to a cheap model. Inline, the child's own model writes every line, so the model choice below is what actually shapes the code. Exception: a plan with more than 10 tasks uses `subagent-driven-development`, because one context carrying that many tasks degrades by the last ones, and a fresh subagent per task is worth its cost there.

Children run on Sonnet. Quality comes from three backstops rather than a pricier default: the child's advisor (a stronger reviewer model, from `advisorModel` in the user's Claude Code settings; without it the checkpoints are skipped) at fixed checkpoints in the builder prompt, a review of each finished branch by a fresh reviewer on the coordinator's model (step 5), and a temporary escalation to the coordinator's model when a child is stuck (see "Escalation").

The model is set **per child**, because in cross-repo work usually only one side needs it: a UI-heavy frontend plan benefits from Opus, while the backend child does fine on Sonnet with its advisor. An Opus child costs several times a Sonnet one, so the coordinator recommends it per plan (step 3) and the user decides. `--opus` skips the question and runs every child on Opus.

## Flow

### 1. Collect the plans

Arguments = plan paths, or unambiguous references from context ("plan 1 and 2" = plan files already named in the conversation). No argument → `ls -t docs/superpowers/plans/*.md | head -1` in the current repo. Any path ambiguous or missing → stop and ask.

For each plan, read sparingly. Do not `Read` whole plans, do not explore the codebases:
- `sed -n '1,25p' <plan>` → Goal.
- `grep -nE '^#{2,3} (Task|Phase) [0-9]+' <plan>` → N tasks (0 → ask whether this is a plan file). Execution skill: N ≤ 10 → `superpowers:executing-plans`, N > 10 → `superpowers:subagent-driven-development`.
- Repo root: `git -C "$(dirname <plan>)" rev-parse --show-toplevel`. Two plans in the same repo → ask whether they should run in one child, sequentially; two writers in one repo collide.
- Slug: file name without date prefix and `.md`.
- Base branch: `dev` → `develop` → the repo's default branch, first that exists as a local branch (`git -C <repo root> show-ref --verify --quiet refs/heads/<b>`). The worktree is cut from it, so a remote-only `origin/dev` does not count.
- Final verification: the `test`/`lint`/`typecheck` scripts in that repo's `package.json`, or the test command in its CLAUDE.md.
- Already done? `ls` the first and last `Create:` paths. Last exists → report it and drop that plan.
- UI-heavy? Run:
  ```bash
  files=$(grep -E '^\s*- (Create|Modify):' <plan> | grep -oE '`[^`]+`' | tr -d '`' | sed -E 's/:[0-9,-]+$//' | grep -E '\.[a-z]+$' | grep -vE '\.(test|spec|stories)\.' | sort -u)
  echo "$(echo "$files" | grep -cE '\.(tsx|jsx|vue|svelte|css|scss)$|tailwind\.config\.') of $(echo "$files" | grep -c .)"
  ```
  It takes every backticked path on `Create:`/`Modify:` lines (plans often list several per line), strips line ranges like `:86-122`, and drops tests, which do not need a design eye. UI files = component and style files; in a Next.js app router, components sit next to `page.tsx`, so file type beats folder name. More than half → UI-heavy. Keep the "X of Y" for the question in step 3.

### 2. Lock the contract (only when there are 2+ repos)

The contract is everything both sides must agree on: routes and methods, request/response shapes, field names and types, error codes, event names and payloads, env vars one side reads from the other.

- `--contract <path>` given → use it.
- Otherwise look for a contract section in the plans. Found → copy it into `docs/superpowers/contracts/<slug>.md` in the repo that owns the source of truth (usually the backend).
- Neither → draft it from the plans' Goal and task headers, write it to that path, and show it to the user. Spawn nothing until they confirm: a wrong contract means two children build the wrong thing in parallel.

Children read the contract by absolute path and must not edit it. A change goes through the coordinator (step 4), which is the whole point of having one.

Single repo → skip this step.

### 3. Spawn the children

Default: children in parallel, since the locked contract lets each side build against it, but **at most 2 working at once**. The limit is local RAM: agent reasoning runs remotely, while each child's `tsc`, test runs, and builds run on this machine and can take 1–2 GB each. With 3+ repos, the rest wait and start as a slot frees up. Run one after another only when one child needs the other's output to exist (a client generated from the backend's OpenAPI file, a migration the other side queries). Then spawn the dependent child after the first reports DONE.

First `mcp__ccd_session_mgmt__get_session("self")` → the coordinator's `local_…` id, which every builder prompt needs, and its model.

**Pick each child's model.**
- `--opus` → every child on Opus, no question.
- Otherwise, any UI-heavy plan → ask once, before spawning, in the same message as the contract confirmation when step 2 drafted one: "The <repo> plan is UI-heavy (<count> files). Run the <repo> child on Opus?" Yes → that child on Opus. The other children stay on Sonnet.
- No UI-heavy plan → all Sonnet, no question.

Any child on Opus → the coordinator must be on Opus too: the app caps a child at its parent's model, so the choice would silently do nothing. Not on Opus → stop and ask the user to switch this session to Opus in the model menu first.

For each plan, call `mcp__ccd_session__start_session`:
- `initiation`: `"user_asked"` (the user asked for builder sessions by invoking this skill)
- `context`: `"fresh"`
- `title`: `Build (<repo name>): <plan title without "Implementation Plan">`
- `name`: `<repo-name>-<slug>`, trimmed to 24 chars
- `cwd`: the repo root, when it differs from this session's folder
- `use_worktree`: `true`, `branch_name`: the slug, `source_branch`: the base branch
- `model`: the model picked above. Sonnet = the current Sonnet id from the system prompt's model list (e.g. `claude-sonnet-5-5`); Opus = this session's own model id. A wrong id is silently ignored
- `wake_when_done`: `true`
- `prompt`: the builder prompt below, filled in
- `background`: the overall goal across all repos, the other children's repos and what they build, and that the contract is locked

Record each child's `local_…` session id from the result. Link each one to the user as `[title](#<id>)`.

### 4. Coordinate

Two channels reach this session, and they arrive at different times:
- `BLOCKED` and `CONTRACT` come as cross-session messages from the child, the moment it sends them. This matters: end-of-turn notes only wake the coordinator once **every** child is idle, so a contract question sent only as a final message would wait while the other child keeps building against the old contract.
- `DONE` comes as the end-of-turn note, quoting the start of the child's final message.

Always address a child with `SendMessage` `to` = its `local_…` id from the `start_session` result, not its display name.

- `BLOCKED: <question>` → answer it from the plans, the contract, or the code. If they cannot settle it, ask the user and send the answer to the child.
- `CONTRACT: <proposed change>` → decide with the user. Accepted → edit the contract file, then `SendMessage` every affected child: the exact change and the contract path. Rejected → tell the requesting child to build against the contract as it stands.
- `DONE` → review that repo: `git -C <repo root> log --oneline <base>..<branch>` and `git -C <repo root> diff <base>...<branch>` against the plan's Goal. A finding to fix → `SendMessage` it to that child. This pass checks that the branch does what the plan says; the bug review is step 5's, by a separate reviewer.

A note is the child's claim, not proof. Check the diff before telling the user anything is done. A DONE line with "no advisor" means the child ran without its quality backstop; review that diff more closely and tell the user.

#### Escalation

Skip this for a child already on Opus: there is nothing to escalate to, and a stuck Opus child points at the plan or contract.

Two signals mean Sonnet is the bottleneck for this child, not the plan:
- the same child sends `BLOCKED` twice on the same task, or
- the review-fix loop (step 5) reaches round 3 with High/Medium still open.

Then, before sending the answer or the round-3 `FIX`: `mcp__ccd_session_mgmt__set_session_model(<child id>, <this session's own model id>)`. The child is idle while it waits, so the switch applies to exactly the turn you are about to start. Using the coordinator's own model avoids an approval prompt and the app's rule that a child cannot outrank its parent. When that turn ends, switch the child back to Sonnet, and mention the escalation in the final report. Escalate one child at a time and only for that turn; escalating as a default just turns the whole run into an Opus run.

### 5. Review-fix loop per repo (automatic)

Runs without asking the user, once every child is DONE. The goal is branches that reach the PR with no **High** or **Medium** finding left, so the PR review is a formality rather than the first real look.

The review runs in a **reviewer subagent of this session**, never in the child. A child reviewing its own branch brings the assumptions it built with, on the model that wrote the code. The reviewer starts from its brief alone and runs on the coordinator's model: pass this session's tier (`opus`, `fable`, …, from step 3's `get_session("self")`) as the `Agent` call's `model`, since an omitted `model` can fall back to a cheaper configured default. The child only fixes.

Same cap as the build: **at most 2 repos in this loop at once**, the rest wait for a free slot. A reviewer runs tests on this machine like a child does, so it counts against the cap, and a repo's reviewer never runs while its child is still working. A reviewer's result arrives when it finishes; a child's `FIXED` note arrives once every child is idle.

Before the first round, settle per repo:
- Effort, from `git -C <repo root> diff --name-only <base>...<branch>`: the risk tier from the table in the `ship` skill, step 6a. Low → `low`, Medium → `medium`, High → `high`.
- Security review, from the same list: needed when the diff matches the condition in `ship` step 6c (auth, endpoint input, queries built from input, upload, user HTML, secrets/env).
- The child's worktree path: `git -C <repo root> worktree list --porcelain`, the entry whose `branch` is the child's.

For each repo, up to 3 rounds:
1. Spawn the reviewer: `Agent`, `subagent_type: "general-purpose"`, `model` = this session's tier, `prompt` = the reviewer brief below, filled in. Put nothing else in it: not the child's DONE note, not your own reading of the diff. Round 1 with a security review needed → in the same message a second such `Agent` call: "The repo is the checkout at <worktree path>, branch <branch>, base <base>. Your shell starts in another folder and `cd` does not carry over between commands: begin every command with `cd <worktree path> &&`, including the ones the skill tells you to run. Read only: no edit, commit or checkout. Invoke the `security-review` skill and return its markdown report as your final reply." It needs its own subagent because that skill ends the turn it runs in. Give each of its findings a severity label and treat them like the reviewer's.
2. No High or Medium in the findings → this repo is clean, move to the next. Otherwise note `git -C <repo root> rev-parse <branch>` as the commit before the round, then `SendMessage` the child: `FIX: <every High and Medium finding, as the reviewer wrote it>. Check each one against the code first. Real → fix it. Wrong → leave the code alone and list it under disputed with your evidence (file:line, test output). Leave Low, Nit and Pre-existing alone. Then <final verification>, then commit. End your turn with FIXED: <count> fixed, disputed: <finding + evidence, or none>.`
3. On `FIXED`, check it yourself: `git -C <repo root> diff <commit before the round>..<branch>` (the fixes are real and in scope) and that verification passed. A disputed finding: read the child's evidence against the code. It holds → drop the finding. It does not → send it again as `FIX` with what the evidence misses; that counts as the next round.
4. The child committed fixes → next round: a new reviewer, with the round 2+ lines of the brief. It re-checks every earlier finding and reviews the fix commits, because a fix that does exactly what the finding asked is where the next bug tends to sit. Nothing committed and every dispute held → no High or Medium is left, the repo is clean.

Round 3's `FIX` runs escalated (step 4, "Escalation"). After 3 rounds with High/Medium still open, stop looping on that repo and carry the findings into the report. A loop that keeps failing is usually a plan or contract problem, which more automated rounds will not fix.

#### Reviewer brief

```
You review branch <branch> against base <base> in the checkout at <worktree path>. Your shell starts in another folder and `cd` does not carry over between commands: begin every command with `cd <worktree path> &&`, including the ones a skill tells you to run, and read files by absolute path. Read only: no edit, commit, checkout, stash, push or GitHub comment.
<Round 1:> Run /code-review <effort> <branch> against base <base>. No Skill tool, or that skill is not in your list → review `git diff <base>...<branch>` yourself at that effort: read every changed file in full, and the callers of each signature, query or shared helper that changed.
<Round 2+:> Earlier findings: <the findings sent in the last FIX, and any the child disputed>. Fix commits: <commit before the round>..<branch>. For each earlier finding answer fixed or still open, with the line that shows it. Then review `git diff <commit before the round>..<branch>` for bugs the fixes introduced: follow what the changed lines touch (locks and transactions, rule or statement order, connection use, callers).
<Only when heavy.sh exists; write its absolute path:> Run every test, typecheck or build as `bash <heavy.sh path> <command>`.
Reply with the findings only, most severe first, one per line:
<High|Medium|Low|Nit|Pre-existing> `path:line`: <the defect>. Fails when: <input or state → wrong result>.
High = bug, data loss or security hole. Medium = wrong under realistic input. Pre-existing = a bug this branch did not introduce. Nothing found → reply "No findings."
```

### 6. Combined review and fix (2+ repos, automatic)

Once every repo is clean, check the seams that no single child could see:
- Every contract route exists on the server side with the same method, path, and status codes.
- Client types and calls match the server's DTOs and response shapes field by field: names, optional vs required, enums, date formats.
- Error codes the client handles are ones the server actually returns.

Each mismatch is a finding with a severity label. Send it to the child that has to change (the side that deviates from the contract), with `FIX: <finding>, then <final verification>, commit, end your turn with FIXED`. Check the diff, then re-run this seam check. Up to 2 rounds, then carry what is left into the report.

#### Local E2E across the seam

The seam check compares text. This runs the client against the server, before anything ships. Start it once the seam check leaves no High or Medium and no child is working: two apps and a browser are the heaviest moment of the run. A server is a repo that serves contract endpoints; the client is the repo that calls them (several clients → one after another).

1. `SendMessage` each server child:
   ```
   SERVE: start your app from this worktree for a cross-repo E2E run, with the repo's own start command (the "## start" section of .claude/autopilot.md, else its package.json scripts and compose file).
   - Port: a free one (lsof -iTCP -sTCP:LISTEN -P shows what is taken).
   - Database: its own database name, or its own compose project (docker compose -p e2e-<short name, no slashes>) with host ports changed through env vars or an untracked override file. Never edit a tracked file for this, and never migrate or seed a database another process uses.
   - Env: gitignored .env* files missing here → copy them from <repo root>, then change port and database in the copy.
   - Never stop or reuse a process you did not start.
   - An app from an earlier SERVE still runs → stop it first, keep its database, and migrate again when a migration changed.
   Install, build, migrate and seed go through heavy.sh as usual. Only the app start does not: use Bash run_in_background, because it must outlive your turn and the lock would block the client's run. Note the PID and the compose project or database name for STOP.
   No test account in the seed or fixtures → say accounts: none; do not add one now.
   End your turn with SERVING: <base URL>, accounts: <path of the seed or fixture file with test accounts, or none>
   or CANNOT SERVE: <the variable or service that is missing>.
   ```
2. On `SERVING`, `SendMessage` the client child:
   ```
   E2E: the server runs at <base URL> (test accounts: <path>) <several servers: one "<repo>: <base URL>, accounts <path>" per server>. Run the contract <contract path> through your app against it.
   - <worktree>/.e2e/scenarios.md already exists → reuse it unchanged. Otherwise write it: one scenario per contract endpoint your repo calls, plus at least one error case the contract defines. Each has an ID (S1…), the criterion it proves (what the user sees when that endpoint behaves as the contract says), numbered steps, the expected result. Keep .e2e/ out of git: add it to "$(git rev-parse --git-common-dir)/info/exclude".
   - Point your app at that URL through the env var the contract names, else the one your app reads for the API base URL. Start it on a free port (lsof -iTCP -sTCP:LISTEN -P), never stopping a process you did not start, run every scenario, stop what you started. That whole block goes through heavy.sh.
   - Web → the playwright-cli skill. That skill is not installed, or there is no UI → HTTP calls through your client code, and say so in result.md.
   - Write <worktree>/.e2e/result.md. First line: E2E: <n>/<N> pass @ <your HEAD, 7 chars>. Then one line per scenario: pass, or fail with the request sent, what the contract expects, and what came back.
   End your turn with E2E: <n>/<N> pass, <absolute path of result.md>
   or CANNOT RUN: <what is missing>.
   ```
3. Read `result.md`, not the note. A failing scenario is a finding: compare what came back with the contract and send `FIX` to the side that deviates, as in the seam check. After any `FIX`, check the diff and re-run the seam check; after a server fix send `SERVE` again, then `E2E` again. Up to 2 rounds, counted apart from the seam check's, then carry the failure into the report.
4. Always, whatever the outcome: `SendMessage` each server child `STOP: stop the app you started for SERVE and remove its compose project with its volumes (docker compose -p <name> down -v) or drop its database. Nothing of yours is running → nothing to do. End your turn with STOPPED.` A server child that got `SERVE` and has not answered `STOPPED` (the run was interrupted) gets `STOP` before step 7 sends `/ship` and before step 8 archives it.
5. Record the tested commit per repo (`git -C <repo root> rev-parse --short <branch>`). `CANNOT SERVE` or `CANNOT RUN` → there is no result: the report says `UNVERIFIED: local E2E, <reason>`.

If this session has an advisor tool, call it once before leaving this step, after the last seam check and the local E2E, and before the report. Each child's advisor saw one repo only, so this is the one review in the flow with no second look. It reads only this conversation, so the contract and the server and client excerpts you compared must be in it, not just your conclusion. No advisor tool → skip it and add "seam check: no advisor" to the report.

### 7. Report and ship

Report to the user: per repo the branch, commits, verification result, review rounds run with the model that reviewed (this session's), and what was fixed; then anything still open with severity labels (**High**, **Medium**, **Low**, **Nit**), and the Pre-existing bugs from the reviewers' findings as issue candidates. "Clean" means `/code-review` and the seam check found nothing High or Medium, not that the code is proven bug-free; say it that way.

Branches stay unmerged and unpushed until the user says to ship. Then `SendMessage` each child "Run /ship with base <base> --auto-fix --reviewed"; each child opens its own PR from its own repo, and Auto-fix keeps CI and review comments handled there. `--reviewed` skips `/ship`'s own review, since step 5 already did it; its typecheck, lint and tests still run. Merging stays the user's call.

With 2+ repos the report also has the local E2E line (`E2E local: <n>/<N> pass`, the failing scenarios, or the `UNVERIFIED` reason) and says that shipping posts the result as a comment on every PR. A scenario still failing → when the user says to ship, ask once whether to ship with it open. `UNVERIFIED` does not hold the ship.

Once every child's `/ship` returned a PR URL and a local E2E result exists, `SendMessage` the client child:
```
E2E-COMMENT: the PRs are <client PR URL>, <other PR URLs>.
1. Under your PR body's "## Test plan" (no such section → add it at the end) put one line per scenario from .e2e/result.md, exactly: - [x] E2E local S1 (<criterion>): <steps in a few words> → pass   (a failed one: - [ ] … → fail). Lines starting "- [x] E2E local" or "- [ ] E2E local" already there → replace them. Use gh pr view <N> --json body, edit, gh pr edit <N> --body-file <file>.
2. Post the comment between the two ----- lines (without those lines) on your PR with gh pr comment <url> --body-file <file>, and on each other PR with one more list line "- PR: <your PR URL>".
-----
## E2E local: <PASS | FAIL>

- Commit: <commit line>
- Environment: local, isolated database

| Scenario | Proves | Result |
|---|---|---|
| S1 <short name> | <criterion> | pass |

<n>/<N> pass.
-----
An Auto-fix event about this "## E2E" comment needs no action. End your turn with COMMENTED.
```
Fill `<commit line>` yourself from step 6's tested commits, client first: `` `<sha7>`, `<server repo>@<sha7>` ``. Those are the commits E2E ran on; `/ship` may have added a format commit on top, and the comment does not claim it. The line format and the comment shape are the `deliver` skill's, so `/deliver continue` after the merge (step 8) rebuilds its scenarios from those lines and posts its dev result under this comment.

`/ship`'s gate can end three ways; report each repo's: a PR opened, a draft PR (High tier with an unverified test), or stopped before the push (a check still red). Stopped → the child's message carries the failing output; treat it like a step 5 round that left a finding open.

### 8. Cleanup after merge

Runs when the user says the PRs are merged ("merged", "the PRs are in", in any language). Check each PR really is merged (`gh pr view <PR> -R <owner/repo> --json state`) before touching anything. One still open → clean up only the merged ones and say which is left.

1. **Archive the children first.** Ask the user once for all of them ("archive N session builder?"), then `mcp__ccd_session_mgmt__archive_session` per child with reason `PR <owner/repo>#<n> merged`. Archiving stops the child and removes its worktree, which `/merged` would otherwise refuse to remove while the child still has it checked out.
2. **Run `/merged <PR>` for each repo.** The coordinator usually sits outside these repos, so run every git command of that skill as `git -C <repo root>` and every gh command with `-R <owner/repo>`. It removes the local branch, syncs the base, and checks linked issues.
3. **Dev E2E across the seam**, with 2+ repos only. Each `/merged` run may suggest its own `/deliver continue <PR>`; replace those with one suggestion, to be run in the repo that calls the contract (the client): `/deliver continue <its PR> --with <URL of every other PR>`. It waits until every repo's merge commit is deployed, then tests the contract's endpoints through the client on dev, which no single-repo test covered, and comments the result on every PR. Suggest it only when all PRs are merged; one still open → name it instead. This session does not run the E2E and never passes a dev URL along: `deliver` takes that from the user alone. One repo → keep `/merged`'s own suggestion.
4. **Report** with `/merged`'s table, one row per repo, then the suggestion from 3. Then offer to archive this coordinator session; that is the user's call.

## Builder prompt

```
You are the builder for plan <absolute plan path> (<N> tasks) in repo <repo root>. The coordinator is session <coordinator id>.
<Only with 2+ repos:> The API contract is <absolute contract path>. It is locked: read it, build against it exactly, and never edit it. Other repos building against the same contract: <repo: what it builds, one line each>.

1. You are already on your own worktree branch, cut from <base>. Use <execution skill> to execute every task in the plan. Decide on your own between tasks; do not ask the user.
<Only for an Opus child running subagent-driven-development:> The user chose quality over cost for this run. Override that skill's Model Selection: dispatch every subagent (implementers, reviewers, fixers) with model <opus id>, including tasks that look mechanical.
2. Each task: its own `Run:` commands from the plan, exit 0, then commit. After the last task: <final verification>, exit 0.
<Only when `${CLAUDE_SKILL_DIR}/../deliver/scripts/heavy.sh` exists; write its absolute path:> Run every install, test, typecheck and build command as `bash <heavy.sh path> <command>` (a command with `&&`, a pipe or an env prefix: `bash <heavy.sh path> sh -c '<command>'`), in FIX rounds too. It holds a machine-wide lock, so builders in other repos never run two heavy commands at once.
3. Report to the coordinator only in these cases:
   - BLOCKED: <the question>, when the plan, the contract, and the code cannot settle it.
   - CONTRACT: <the exact change you need and why>, when building to the contract as written is impossible or wrong.
   For these two, first send SendMessage to "<coordinator id>" with that line as the first line, then end your turn and wait for the reply. A final message alone does not reach the coordinator while other builders are still working.
   - DONE: when all tasks and the final verification pass, end your turn with a final message whose first line is: DONE: <branch from `git branch --show-current`>, <commit count> commits, verification passed. The coordinator sees only its first ~400 characters.
4. If you have an advisor tool, call it at these checkpoints, not only when you feel like it: before you start the first task, before reporting DONE, before sending BLOCKED or CONTRACT, and before ending a FIX round in which you dispute a finding or leave one unfixed. Its whole value is a second look at the moments a wrong call is expensive. If it settles a BLOCKED question by pointing at the plan, the contract, or the code, carry on without sending it; a product or scope decision it can only guess at still goes to the coordinator. No advisor tool in this session → skip this step and add "no advisor" to your DONE line.
5. After DONE, the coordinator sends FIX instructions (findings from a separate reviewer; you do not review your own branch), and for a cross-repo run SERVE, E2E, STOP and E2E-COMMENT. Do exactly what they say, commit any code change, and end your turn with the reply line the instruction asks for. Where an instruction says how to run a command (with or without heavy.sh), it wins over rule 2. These are part of your job, not a new task: stay on the same branch. After the PR exists, an Auto-fix event about a comment that starts with "## E2E" needs no action.
No push, no merge, no PR, no GitHub comment, no edits outside the plan and the coordinator's instructions, until the coordinator says so.
```

## Common mistakes

| Mistake | Fix |
|---|---|
| Coordinator starts editing code in one repo | It only plans, relays, and reviews |
| Spawning before the user confirmed a drafted contract | Children build the wrong thing in parallel; confirm first |
| A child edits the contract to unblock itself | The other child never learns; changes go through `CONTRACT:` |
| Relaying a contract change to only the child that asked | Send it to every child that builds against that part |
| Prompt says "the plan above" or "as discussed" | Children never saw this conversation; name every path and value |
| Trusting a DONE note | Read the diff before reporting |
| Two children writing in the same repo | One child per repo; run same-repo plans in sequence |
| More than 2 repos building or in review at once | Cap at 2; local `tsc`/tests across 3+ repos can exhaust a small machine's RAM |
| Asking the child to review its own branch | It repeats the assumptions it built with; step 5 spawns a fresh reviewer subagent on the coordinator's model |
| Passing the reviewer the DONE note or your own read of the diff | It then confirms what it was told; the brief carries paths, base, branch and effort only |
| Trusting FIXED without the fix diff | A child can fix past High/Medium or past the plan; check the diff stays in scope |
| Sending `/ship` without `--reviewed` | The branch gets a second full review on top of step 5 |
| Looping forever on a stubborn finding | Stop after the round cap and report it; it is likely a plan or contract issue |
| Calling the result "bug-free" | Say no High/Medium findings remain from review and seam check |
| Leaving an escalated child on Opus | Switch it back to Sonnet as soon as the escalated turn ends |
| Server app started through `heavy.sh` for the local E2E | It holds the machine-wide lock while it runs, so the client's E2E waits forever; `SERVE` starts it in the background, outside the lock |
| Reporting local E2E from the child's `E2E:` note | Read `result.md`; the note is a claim, and a fail needs the response to pick the side to fix |
| Leaving the server app running after the E2E | Send `STOP` whatever the outcome |
| Running `/merged` while the child still holds its worktree | Archive the children first, then `/merged` |
