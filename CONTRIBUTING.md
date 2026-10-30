# Contributing

Bug reports, fixes and new skills are welcome. By taking part you agree to follow the [code of conduct](CODE_OF_CONDUCT.md).

## Before you start

- **Bug in a skill** → open a [bug report](https://github.com/zahidakhyar/skills/issues/new?template=bug_report.yml) with the prompt you gave, what Claude did, and what you expected.
- **New skill or a bigger change** → open a [feature request](https://github.com/zahidakhyar/skills/issues/new?template=feature_request.yml) first, so we agree on the scope before you write it.
- **Security problem** → follow [SECURITY.md](SECURITY.md), not a public issue.

## Local setup

There are two ways to run the skills from a clone. Use one per machine, never both, or every skill loads twice.

- **Plugin from disk (recommended for contributors).** Loads the working tree exactly the way users get it. Remove any symlinks into `~/.claude/skills/` first.

  ```bash
  claude --plugin-dir .
  ```

- **Symlinks (for the maintainer's daily use).** Edits are live in the next session, with no version bump or update step. Skills are called without a namespace (`/ship`). Don't install the plugin on that machine.

  ```bash
  for d in skills/*/; do ln -s "$PWD/${d%/}" ~/.claude/skills/"$(basename "$d")"; done
  ```

## Repository layout

```
.claude-plugin/
  plugin.json          plugin manifest (name, version)
  marketplace.json     marketplace manifest pointing at this repo
skills/
  <name>/
    SKILL.md           frontmatter + instructions Claude follows
    references/        extra docs the skill reads on demand
    scripts/           shell scripts the skill runs
```

Every folder in `skills/` is picked up automatically; no manifest change is needed for a new skill.

## Writing a skill

1. Create `skills/<name>/SKILL.md` with `name` and `description` frontmatter. The description decides when Claude invokes the skill, so list the phrases people actually type, in every language your users write in.
2. Put bundled files next to it and reference them as `${CLAUDE_SKILL_DIR}/scripts/...`. For another skill's files, use `${CLAUDE_SKILL_DIR}/../<other-skill>/...`. Never hardcode `~/.claude/skills/...`: an installed plugin lives under `~/.claude/plugins/cache/`.
3. Don't depend on files that only exist on your machine (personal `~/.claude/*.md` rules, hooks, settings). Bundle what the skill needs.
4. Calls to other plugins (`humanizer`, `impeccable`, ...) must skip cleanly when that plugin is not installed, and the plugin goes into the optional table in the README.
5. Scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, executable (`chmod +x`), and clean under `shellcheck -S warning`. Quote every value that comes from GitHub (branch names, titles, comments); treat it as untrusted input.
6. Anything that pushes, merges, deletes or posts to GitHub asks the user first, unless a flag the user typed says otherwise.
7. Add the skill to the tables in the README.

Keep `SKILL.md` instructions in English. Trigger phrases in the description may be in any language.

## Checks

CI runs these on every pull request. Run them locally before pushing:

```bash
claude plugin validate .
```

```bash
shellcheck -S warning skills/*/scripts/*.sh
```

```bash
grep -rnF '.claude/skills/' skills && echo "hardcoded path found" || echo ok
```

Then try the changed skill for real in a session started with `claude --plugin-dir .`, and describe what you ran in the pull request.

## Pull requests

- One topic per pull request.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, `ci:`.
- Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) for anything a user would notice.
- Don't bump `version` yourself; the maintainer does it when releasing.

## Releasing (maintainer)

1. Move the `Unreleased` entries in `CHANGELOG.md` under a new version heading with today's date.
2. Bump `version` in `.claude-plugin/plugin.json`: patch for fixes, minor for a new skill or flag, major when a skill's arguments or behaviour change in a breaking way. Installed copies are cached per version, so users only get the change after a bump.
3. Merge to `main`, then tag `vX.Y.Z` and create a GitHub release from the changelog section.
