# skills

Personal agent skills for Claude Code.

| Skill | Purpose |
|---|---|
| `ship` | Branch → commit → push → PR |
| `pr-review` | First-pass review of a teammate's PR |
| `recheck` | Re-review a PR after the author pushed fixes |
| `merged` | Post-merge cleanup of branches, worktrees and issues |
| `release` | Cut a version release of a JS/TS project |
| `orchestrate` | Run implementation plans in separate builder sessions |
| `learned` | Extract and persist session learnings to memory |

## Install

```bash
npx skills add zahidakhyar/skills
```

## Local development

This repo is the source of truth. Each `~/.claude/skills/<name>` is a symlink to `skills/<name>` here, so edits made anywhere show up in `git diff`.

```bash
ln -s "$PWD/skills/<name>" ~/.claude/skills/<name>
```
