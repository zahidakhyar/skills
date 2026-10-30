---
name: orchestrate
description: Use when one or more implementation plans are ready and the user wants them built in separate builder sessions while this session stays the coordinator — types `/orchestrate [plan path ...] [--contract <path>] [--opus]`, or says "orchestrate ini", "kerjakan plan 1", "jalankan plan ini di session lain", "handoff ke builder", "session ini planner/parent, buat child-nya", "task cross repo", "BE dan FE sekaligus", "kerjakan di 2 repo", "jadi parent untuk ini". Especially use it for cross-repo work (backend + frontend, service + client) where several repos must agree on one API contract. Not for writing the plans (writing-plans) and not for interval loops (/loop).
---

# Orchestrate

This session is the **coordinator**. It hands each plan to its own child session (one per repo), keeps the shared contract, relays changes between children, and reviews the combined result. It never edits code itself: once it starts building, its context fills up and nobody is left holding the overall picture.

One plan in one repo is just the N=1 case of the same flow.

Children execute their plan **inline** (`superpowers:executing-plans`) by default, whatever execution skill the plan recommends. This skill already reviews at the end (step 5 review-fix loop, step 6 seam check, the coordinator's diff review, the child's advisor), so the per-task review of `superpowers:subagent-driven-development` mostly duplicates it, while costing a cold-start subagent per task and handing tasks it judges mechanical to a cheap model. Inline, the child's own model writes every line, so the model choice below is what actually shapes the code. Exception: a plan with more than 10 tasks uses `subagent-driven-development`, because one context carrying that many tasks degrades by the last ones, and a fresh subagent per task is worth its cost there.

Children run on Sonnet. Quality comes from two backstops rather than a pricier default: the child's advisor (an Opus reviewer, from `advisorModel` in the user's Claude Code settings; without it the checkpoints are skipped) at fixed checkpoints in the builder prompt, and a temporary escalation to the coordinator's model when a child is stuck (see "Escalation").

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

Default: children in parallel, since the locked contract lets each side build against it, but **at most 2 working at once**. The limit is local RAM (8 GB): agent reasoning runs remotely, while each child's `tsc`, test runs, and builds run on this machine and can take 1–2 GB each. With 3+ repos, the rest wait and start as a slot frees up. Run one after another only when one child needs the other's output to exist (a client generated from the backend's OpenAPI file, a migration the other side queries). Then spawn the dependent child after the first reports DONE.

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
- `DONE` → review that repo: `git -C <repo root> log --oneline <base>..<branch>` and `git -C <repo root> diff <base>...<branch>` against the plan's Goal. A finding to fix → `SendMessage` it to that child.

A note is the child's claim, not proof. Check the diff before telling the user anything is done. A DONE line with "no advisor" means the child ran without its quality backstop; review that diff more closely and tell the user.

#### Escalation

Skip this for a child already on Opus: there is nothing to escalate to, and a stuck Opus child points at the plan or contract.

Two signals mean Sonnet is the bottleneck for this child, not the plan:
- the same child sends `BLOCKED` twice on the same task, or
- the review-fix loop (step 5) reaches round 3 with High/Medium still open.

Then, before sending the answer or the round-3 `REVIEW`: `mcp__ccd_session_mgmt__set_session_model(<child id>, <this session's own model id>)`. The child is idle while it waits, so the switch applies to exactly the turn you are about to start. Using the coordinator's own model avoids an approval prompt and the app's rule that a child cannot outrank its parent. When that turn ends, switch the child back to Sonnet, and mention the escalation in the final report. Escalate one child at a time and only for that turn; escalating as a default just turns the whole run into an Opus run.

### 5. Review-fix loop per repo (automatic)

Runs without asking the user, once every child is DONE. The goal is branches that reach the PR with no **High** or **Medium** finding left, so the PR review is a formality rather than the first real look.

Same cap as the build: **at most 2 children reviewing at once**, the rest wait for a free slot. Running two in parallel means the coordinator wakes only when both have ended their round; handle both `REVIEWED` notes together, then start the next round for whichever still needs one.

Before the first round, settle two things per repo from `git -C <repo root> diff --name-only <base>...<branch>`:
- Effort: the risk tier from the table in the `ship` skill, step 6a. Low → `low`, Medium → `medium`, High → `high`.
- Security review: needed when the diff matches the condition in `ship` step 6c (auth, endpoint input, queries built from input, upload, user HTML, secrets/env).

For each child, up to 3 rounds:
1. `SendMessage` the child: `REVIEW: run /code-review <effort> <branch> against base <base>` + (round 1, security review needed) `and /security-review` + `. Fix only the High and Medium findings this branch introduced. A bug the branch did not introduce: list it as Pre-existing, leave the code alone. Skip Low and Nit. Then <final verification>, then commit the fixes. End your turn with REVIEWED: <fixed count> fixed, remaining High/Medium: <list or none>, Pre-existing: <list or none>.`
2. On `REVIEWED`, check it yourself: `git -C <repo root> diff <commit before the round>..<branch>` (the fixes are real and in scope) and that verification passed.
3. Remaining High/Medium, or the fix diff shows a new problem → next round. None → this repo is clean, move to the next child.

Round 3 runs escalated (step 4, "Escalation"). After 3 rounds with High/Medium still open, stop looping on that repo and carry the findings into the report. A loop that keeps failing is usually a plan or contract problem, which more automated rounds will not fix.

### 6. Combined review and fix (2+ repos, automatic)

Once every repo is clean, check the seams that no single child could see:
- Every contract route exists on the server side with the same method, path, and status codes.
- Client types and calls match the server's DTOs and response shapes field by field: names, optional vs required, enums, date formats.
- Error codes the client handles are ones the server actually returns.

Each mismatch is a finding with a severity label. Send it to the child that has to change (the side that deviates from the contract), with `FIX: <finding>, then <final verification>, commit, end your turn with FIXED`. Check the diff, then re-run this seam check. Up to 2 rounds, then carry what is left into the report.

### 7. Report and ship

Report to the user: per repo the branch, commits, verification result, review rounds run, and what was fixed; then anything still open with severity labels (**High**, **Medium**, **Low**, **Nit**), and the Pre-existing bugs from the `REVIEWED` lines as issue candidates. "Clean" means `/code-review` and the seam check found nothing High or Medium, not that the code is proven bug-free; say it that way.

Branches stay unmerged and unpushed until the user says to ship. Then `SendMessage` each child "Run /ship with base <base> --auto-fix --reviewed"; each child opens its own PR from its own repo, and Auto-fix keeps CI and review comments handled there. `--reviewed` skips `/ship`'s own review, since step 5 already did it; its typecheck, lint and tests still run. Merging stays the user's call.

`/ship`'s gate can end three ways; report each repo's: a PR opened, a draft PR (High tier with an unverified test), or stopped before the push (a check still red). Stopped → the child's message carries the failing output; treat it like a `REVIEW` round that left a finding open.

### 8. Cleanup after merge

Runs when the user says the PRs are merged ("merged", "the PRs are in", in any language). Check each PR really is merged (`gh pr view <PR> -R <owner/repo> --json state`) before touching anything. One still open → clean up only the merged ones and say which is left.

1. **Archive the children first.** Ask the user once for all of them ("archive N session builder?"), then `mcp__ccd_session_mgmt__archive_session` per child with reason `PR <owner/repo>#<n> merged`. Archiving stops the child and removes its worktree, which `/merged` would otherwise refuse to remove while the child still has it checked out.
2. **Run `/merged <PR>` for each repo.** The coordinator usually sits outside these repos, so run every git command of that skill as `git -C <repo root>` and every gh command with `-R <owner/repo>`. It removes the local branch, syncs the base, and checks linked issues.
3. **Report** with `/merged`'s table, one row per repo. Then offer to archive this coordinator session; that is the user's call.

## Builder prompt

```
You are the builder for plan <absolute plan path> (<N> tasks) in repo <repo root>. The coordinator is session <coordinator id>.
<Only with 2+ repos:> The API contract is <absolute contract path>. It is locked: read it, build against it exactly, and never edit it. Other repos building against the same contract: <repo: what it builds, one line each>.

1. You are already on your own worktree branch, cut from <base>. Use <execution skill> to execute every task in the plan. Decide on your own between tasks; do not ask the user.
<Only for an Opus child running subagent-driven-development:> The user chose quality over cost for this run. Override that skill's Model Selection: dispatch every subagent (implementers, reviewers, fixers) with model <opus id>, including tasks that look mechanical.
2. Each task: its own `Run:` commands from the plan, exit 0, then commit. After the last task: <final verification>, exit 0.
3. Report to the coordinator only in these cases:
   - BLOCKED: <the question>, when the plan, the contract, and the code cannot settle it.
   - CONTRACT: <the exact change you need and why>, when building to the contract as written is impossible or wrong.
   For these two, first send SendMessage to "<coordinator id>" with that line as the first line, then end your turn and wait for the reply. A final message alone does not reach the coordinator while other builders are still working.
   - DONE: when all tasks and the final verification pass, end your turn with a final message whose first line is: DONE: <branch from `git branch --show-current`>, <commit count> commits, verification passed. The coordinator sees only its first ~400 characters.
4. If you have an advisor tool, call it at these checkpoints, not only when you feel like it: before you start the first task, before reporting DONE, before sending CONTRACT, and before ending a REVIEW round that still leaves a High or Medium finding. Its whole value is a second look at the moments a wrong call is expensive. No advisor tool in this session → skip this step and add "no advisor" to your DONE line.
5. After DONE, the coordinator sends REVIEW and FIX instructions. Do exactly what they say, commit, and end your turn with the reply line the instruction asks for (REVIEWED or FIXED). These are part of your job, not a new task: stay on the same branch.
No push, no merge, no PR, no edits outside the plan and the coordinator's REVIEW/FIX instructions, until the coordinator says so.
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
| More than 2 children building or reviewing at once | Cap at 2; local `tsc`/tests across 3+ repos can exhaust 8 GB RAM |
| Trusting REVIEWED / FIXED without the fix diff | A child can fix past High/Medium or past the plan; check the diff stays in scope |
| Sending `/ship` without `--reviewed` | The branch gets a second full review on top of step 5 |
| Looping forever on a stubborn finding | Stop after the round cap and report it; it is likely a plan or contract issue |
| Calling the result "bug-free" | Say no High/Medium findings remain from review and seam check |
| Leaving an escalated child on Opus | Switch it back to Sonnet as soon as the escalated turn ends |
| Running `/merged` while the child still holds its worktree | Archive the children first, then `/merged` |
