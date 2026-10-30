---
name: release
description: Use when the user wants to cut a new version release of a JS/TS project — types /release <major|minor|patch>, or asks variations of "release patch", "rilis versi baru", "bump version lalu buat PR release", "naikin versi minor", or says a release PR was merged and the GitHub release / CHANGELOG is still pending.
---

# Release

Run the version bump + CHANGELOG → push + tags → release PR cycle in one go, then the GitHub release after merge. Final output: the new version + the PR URL.

Arguments: `/release <major|minor|patch>`. No argument → ask for the bump type first (show the current version from `package.json` so the user can pick easily).

## Flow

1. **Check state** — `git status --porcelain` must be clean (`npm version` refuses a dirty tree). Uncommitted changes → stop: ask the user to commit/stash first. Also make sure a `package.json` exists; if not, this is not a JS project → stop.
   Multi-project workspace (e.g. `acme/`, the `workspace/` root): `cd` into the repo that owns the target `package.json` first, not the workspace root.

2. **Detect the repo's branch convention** (never assume, every repo differs):
   - Check the project's CLAUDE.md for a release convention (e.g. a `## Loop Config` block with `Release branch`).
   - Nothing there: repo has `dev`/`develop` + a default branch (`main`/`master`) → source = dev, PR target = default branch (the dev→main release pattern).
   - Repo has only one main branch → source = default branch, but the bump happens on a new branch `release/vx.x.x` (never commit straight to main), PR → default branch.
   - Still ambiguous (e.g. many long-lived branches, no clear pattern) → ask the user, do not guess.

3. **Prepare the branch** — check out the source branch, `git pull --ff-only` to bring it up to date. Single-branch pattern: `git checkout -b release/next`; after step 4, `git branch -m release/v<new version>` (the new version comes from `npm version`'s output, so there is nothing to compute by hand).

4. **Bump + CHANGELOG in one release commit** — the tag must point at a commit that already carries its own CHANGELOG entry, so no follow-up CHANGELOG PR is ever needed.
   1. `NEW=$(npm version <major|minor|patch> --no-git-tag-version)` — edits `package.json` (and `package-lock.json` if present) without committing; prints `vx.x.x`. Safe with yarn/pnpm: it installs nothing. `git rev-parse -q --verify "refs/tags/$NEW"` succeeds → that version was released before, `git checkout -- .` and ask which bump.
   2. Repo has a `CHANGELOG.md` → insert `## [x.x.x] - YYYY-MM-DD` above the previous version heading, in the file's existing format (Keep a Changelog: `### Added` / `### Changed` / `### Fixed` / `### Removed`, one line per change with `(#N)`). Source: `rtk proxy git log "$(git describe --tags --abbrev=0)"..HEAD --no-merges --format='%s'`; group trivial bumps (deps, actions) into one line. An `## [Unreleased]` section with content → move its items under the new heading and leave `## [Unreleased]` empty. Run the repo's formatter on the file if it has one (e.g. `npx prettier --write CHANGELOG.md`). No `CHANGELOG.md` → skip, do not create one.
   3. `git commit -am "chore: release $NEW"` then `git tag -a "$NEW" -m "chore: release $NEW"`.

5. **Push** — `git push -u origin <branch> --follow-tags` (one command, the branch and the annotated tag go together).

6. **PR** — first check `gh pr list --head <branch> --base <target> --json url,state`:
   - An open PR exists → skip create, show its URL.
   - None yet → gather the material (6a), write the body exactly per the template (6b) to a file in the scratchpad, then `gh pr create --base <target> --title "release: vx.x.x" --body-file <file>`.

   **6a. Body material.** Range = `$PREV..HEAD~1` (the bump commit itself is excluded). Run this block in **one** Bash call, as is: `rtk proxy git` is required, because the rtk hook truncates `git log` at about 50 lines without any marker, even when piped into `wc`/`grep`.

   ```bash
   rgit() { rtk proxy git "$@"; }   # a function, not a variable (zsh does not word-split); not `g`, that is an oh-my-zsh alias
   PREV=$(rgit describe --tags --abbrev=0 HEAD~1 2>/dev/null || echo origin/<target>)  # no tag yet = first release
   rgit log "$PREV"..HEAD~1 --no-merges --format='%s'                    # commits, for Changes
   rgit log "$PREV"..HEAD~1 --no-merges --format='%B' | grep -n 'BREAKING CHANGE'  # + `type!:` subjects
   # Env: compare KEYS, not diff text (diff text mixes comment edits and dev defaults)
   ENV=$(ls .env.example .env.sample .env.template 2>/dev/null | head -1)
   keys() { rgit show "${1}:$ENV" 2>/dev/null | grep -oE '^[A-Z][A-Z0-9_]*=' | tr -d = | sort -u; }
   comm -13 <(keys "$PREV") <(keys HEAD)   # new env
   comm -23 <(keys "$PREV") <(keys HEAD)   # removed env
   rgit diff --name-status "$PREV"..HEAD -- '*migrations*'   # A = new migration, M = existing migration edited
   rgit diff --stat "$PREV"..HEAD -- 'openapi.*'  # API contract
   gh repo view --json nameWithOwner -q .nameWithOwner       # for the compare link
   ```

   Reading the results:
   - **New env**: its description = the comment directly above that key in the env example file, condensed to one sentence.
   - **Target service for env**: if the project's CLAUDE.md has a deployment table, list every service deployed from this repo (e.g. `api` and `worker`). No table → write "in the production environment".
   - **Migration `M`**: read its diff. It goes on the checklist only when the query itself changed. Formatting-only changes (prettier, quotes, indentation) are ignored.
   - **Breaking**: combine three sources. First, `type!:` subjects and `BREAKING CHANGE`. Second, if the repo commits an OpenAPI document, its diff: a removed or renamed path, field, or enum value is breaking for clients. Third, CHANGELOG entries that mention a removed field/endpoint or a changed format.

   **6b. Body template.** Write the body in the language the user's instructions set for PR descriptions (default English), translating the headings with it. `Summary` and `Changes` are always present. Empty `Changes` subsections and any `Before deploy` item with no content are dropped; when every item is empty, the whole `Before deploy` section goes.

   ```markdown
   ## Summary
   <1–3 sentences: what users get from this release. Main source: the CHANGELOG
   entry for this service (this version's heading, or `Unreleased`) if the project
   has a CHANGELOG; otherwise, infer it from the feat/fix commits.>

   ## Changes
   ### Features
   - <subject without the type prefix, first letter capitalized> (#N)
   ### Fixes
   - ...
   ### Performance
   - ...
   <details><summary>Other (<count> commits: <types actually present>)</summary>

   - ...
   </details>

   ## Before deploy
   - [ ] Breaking: <what changed and who is affected>
   - [ ] Set new env on <service>:
     - `KEY`: <description>
   - [ ] Remove env no longer used from <service>: `KEY`
   - [ ] Build-time env changed (`NEXT_PUBLIC_*`, `VITE_*`): needs a rebuild, a restart is not enough
   - [ ] New migrations (<count>): `<file name>`, ... (more than 5: write only the count, plus name any that drop a column/table)
   - [ ] Existing migration edited: `<file name>`. Databases that already ran it do not change, check manually

   Full diff: https://github.com/<owner>/<repo>/compare/<PREV>...v<new version>
   ```

   Content rules:
   - Env: key names only. Never write a value, including the defaults in the example file.
   - A commented-out key (`# S3_ENDPOINT ...`) is not a new env.
   - `<PREV>` in the compare link: the tag name, or the target branch name (`main`) on a first release.
   - `(#N)` references in squash-commit subjects are kept as they are.
   - The Summary and Breaking prose goes through `humanizer:humanizer` (embedded mode) before the PR is created.

7. **Output** — the new version + the PR URL, plus a 1-line summary (branch → target). If the body has a `Before deploy` section, state its item count so the user knows there is prep to do. Remind them to merge with "Create a merge commit", not squash: squash leaves the tag on a commit outside the target branch's history. Then offer the post-merge step (8).

8. **After the user says the PR is merged** — create the GitHub release with the CHANGELOG section as its notes (no CHANGELOG → `--generate-notes`):
   ```bash
   awk -v v="## [${NEW#v}]" 'index($(0),v)==1{f=1;next} /^## \[/{f=0} f' CHANGELOG.md > <scratchpad>/notes.md
   gh release create "$NEW" --title "$NEW" --notes-file <scratchpad>/notes.md --verify-tag
   ```

## Quick reference

| Situation | Behaviour |
|---|---|
| Repo with dev + main | Bump + CHANGELOG on dev → push dev + tag → PR dev → main |
| Repo with main only | Branch `release/vx.x.x` → bump + CHANGELOG → push → PR → main |
| Repo has `CHANGELOG.md` | Entry goes into the release commit itself, never a separate PR after merge |
| PR merged | `gh release create` with the CHANGELOG section as notes |
| Dirty working tree | Stop, ask to commit/stash first |
| Release PR already open | Push only, show the existing PR |
| No bump type argument | Ask major/minor/patch, show the current version |
| Env / migration / breaking changes | `Before deploy` checklist in the body |
| Nothing to prepare | Drop the `Before deploy` section, never fill it with "none" |

## Error handling

- `npm version` fails, or tag `vx.x.x` already exists (that version was released before) → show the error, `git checkout -- .` to drop the uncommitted bump, do not go on to commit or push; ask the user which bump they want.
- Push rejected (non-fast-forward) → report; **never force-push**, never delete/re-tag.
- Remote is not GitHub / `gh` not authenticated → stop after the push, explain why no PR was created + the `gh auth login` instruction.
