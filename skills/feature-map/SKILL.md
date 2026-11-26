---
name: feature-map
description: Use when a repo needs a feature map for `deliver` before its first run, or more features added to it — `/feature-map [feature ...]`, "buat feature map", "petakan fitur repo ini", "seed feature map", "tambahkan fitur X ke feature map". Not for updating an entry after a task (`deliver` does that from its own E2E run).
---

# Feature map

Seed `.claude/features/` in the current repo: a `README.md` and one file per user-facing feature, in the format of [feature-map.md](../deliver/references/feature-map.md), which you read first. `deliver` reads these entries to write its E2E scenarios and keeps the ones it drives current; this skill gives it a starting map. At least one feature is driven for real, so the map ships with at least one recipe that is known to work.

Arguments: feature names or routes to map (`/feature-map orders settings`). None → the 3–5 features a user reaches first.

## Flow

1. **Worktree.** From the main checkout root: `git check-ignore -q .worktrees/ || echo '.worktrees/' >> .git/info/exclude`, then the base as `deliver` step 3 picks it (`base:` under `## Pickup` in `.claude/autopilot.md`, else `dev` → `develop` → the default branch, the first on the remote), `git fetch origin <base>` and `git worktree add -b docs/feature-map .worktrees/feature-map origin/<base>`. Work only there. Copy the gitignored env files from the main checkout and install dependencies, as `deliver` step 3 does. No `.deliver/` run folder and no `run_dir.sh`: this is not a `deliver` run.
2. **Config.** Read `.claude/autopilot.md`. Missing → draft it from [config-template.md](../deliver/references/config-template.md) as `deliver` step 2 does; it ships in this PR.
3. **Pick the features.** Read the routes, pages, menus, CLI commands or API docs. The repo already has `.claude/features/` → list it with `head -n1 .claude/features/*.md` and keep only features that have no file. Nothing left to add → stop and say so.
4. **Write the entries.** `README.md` when the directory is new, and one `<feature-id>.md` per picked feature, from the routes and visible labels: sub-features, entry points, a `Drive` recipe with Playwright locators, any gotcha you can see. Every `Last verified` line is `never` at this point. Never edit an existing file.
5. **Drive at least one.** Start the app as `deliver` step 4 does: free port, its own database or compose project (`feature-map` / `<db>_feature_map`), env files in the worktree rewritten before any migrate or seed, the whole start → drive → stop block in one `bash ${CLAUDE_SKILL_DIR}/../deliver/scripts/heavy.sh` call. Drive the most used new feature end to end through its `Drive` recipe, more if time allows. Correct every step that did not match the app, add each trap you hit to `Gotchas`, and set the driven sub-features' lines to `<sha7 of the base commit> <today> by feature-map`. Stop only what this run started and drop its database.
   - **The app will not start** (a secret, service or database the machine lacks): every line stays `never`, the map still ships, and the PR's Test plan gets `- [ ] UNVERIFIED: no feature driven, <what is missing>`. A `never` map is a set of hints for `deliver`, which checks each one before trusting it.
6. **Ship.** Commit `.claude/features/` (and a drafted `.claude/autopilot.md`) as `docs: seed feature map`, then invoke `shipit` with the base from step 1. The Test plan lists each driven sub-feature with its result and every `never` one as not driven.

## Output

The PR URL, then one line per feature: `<feature-id>: <n> driven, <m> never`.

## Never

- Overwrite or re-date an existing entry: a dated line belongs to the run that drove it.
- Drive the user's running app or migrate their database.
- Put source paths, component or function names in the map.
- Report a `never` sub-feature as verified in the PR.
