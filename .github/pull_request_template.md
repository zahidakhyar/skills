## Summary

<!-- What changes for users of the skill, and why. Link the issue: Closes #N -->

## Test plan

<!-- What you ran, and the result. -->

- [ ] `claude plugin validate .` passes
- [ ] `shellcheck -S warning skills/*/scripts/*.sh` passes (if scripts changed)
- [ ] Tried the changed skill in a session started with `claude --plugin-dir .`
- [ ] `CHANGELOG.md` has a line under `[Unreleased]` (if users would notice the change)
- [ ] README tables updated (if a skill, flag or dependency was added)
