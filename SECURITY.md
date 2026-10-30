# Security policy

## Supported versions

Only the latest version on `main` gets fixes. Update with `claude plugin marketplace update zahidakhyar`.

## Reporting a vulnerability

Report it privately through [GitHub's private vulnerability reporting](https://github.com/zahidakhyar/skills/security/advisories/new). Do not open a public issue.

Include the skill involved, the steps or prompt that trigger the problem, and what an attacker gains. You get a first reply within 7 days.

## Scope

These skills run shell commands (`git`, `gh`, `jq`, the bundled scripts in `skills/*/scripts/`) with your permissions, and some of them post to GitHub on your behalf. In scope:

- A bundled script that can be made to run unintended commands, for example through a crafted branch name, PR title or review comment.
- Skill instructions that lead Claude to leak secrets (`.env` files, tokens) into commits, PR bodies or review comments.
- Skill instructions that lead Claude to push, merge, delete or post without the confirmation the skill promises.

Out of scope: problems in Claude Code itself, in `gh`, or in other plugins. Report those to their own maintainers.
