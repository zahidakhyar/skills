# Changelog

All notable changes to this plugin are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the plugin uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.6.0] - 2026-11-13

### Added

- `deliver continue <PR>` runs dev E2E for a merged PR that never went through `deliver`: it writes the criteria and scenarios from the PR, its diff and its issue, and posts the dev result comment. `--with <PR URL> ...` waits for PRs in other repos to be live too and comments on each. (#19)
- `merged` suggests `/deliver continue <PR>` for a Medium or High risk PR without E2E in a repo that has a dev environment. (#19)
- `orchestrate` runs a local E2E across the repos before shipping: the server builder starts its app, the client builder runs one scenario per contract endpoint against it, and after `ship` the result is added to the client PR's Test plan and commented on every PR. (#20)
- `orchestrate` suggests one cross-repo dev E2E (`/deliver continue <client PR> --with <other PRs>`) once every PR is merged. (#19)

### Changed

- `deliver` posts its E2E results where the team reads them: one result comment per phase (local, then dev) on the PR and on the issue the task came from. Before, local results sat only in the PR body and the issue got nothing. (#18)
- `deliver` passes the issue to `ship`, so its PR carries `Closes #N`. (#18)
- `orchestrate` has each finished branch reviewed by a fresh reviewer subagent on the coordinator's model. Before, the builder reviewed its own branch. The builder now only fixes, can dispute a finding with evidence, and every round of fixes is reviewed again. (#21)

### Fixed

- `recheck` takes its baseline only from your own `reviewed:` markers. A teammate's marker at the PR head used to make a PR you had not re-reviewed look unchanged. (#22)
- `orchestrate`'s reviewer rates a finding by what happens when it fails: damage that cannot be undone is never below Medium, however rare its trigger, so it reaches the builder as a `FIX`. A rare over-deletion used to be labelled Low and stay in the report. (#23)

## [0.5.0] - 2026-11-10

### Added

- `orchestrate`: the coordinator consults its advisor once after the cross-repo seam check, and a builder consults its advisor before sending `BLOCKED`. (#13)
- `release` also releases a Claude Code plugin, bumping `version` in `.claude-plugin/plugin.json` when the repo has no `package.json`. (#14)
- `recheck`, `pr-review --comment` and `deliver` consult the advisor, when the session has one, before the step nobody else reviews: posting the review, and fixing the pass criteria. (#16)

### Changed

- `deliver` asks its two fixed questions in the user's language instead of Indonesian. (#16)
- Gates in `pr-review`, `recheck` and `orchestrate` builders run through the machine-wide `heavy.sh` lock, as `ship` and `deliver` already did. (#14)

### Fixed

- `merged` no longer suggests a plan that already shipped but whose checkboxes were never ticked. (#14)
- `autopilot` finds an open review session by its title; the trimmed session name could lose the PR number. (#14)
- `merged` also removes a leftover `pr-review-<N>` branch once that PR is merged. (#16)
- `heavy.sh` no longer lets two heavy commands run at once on Ubuntu 26.04, where racing `mkdir` calls can all succeed. (#14)

## [0.4.0] - 2026-11-05

### Changed

- `autopilot` is renamed to `deliver` (`/deliver <task>`, `/deliver continue [PR]`). Runs under `.autopilot/` are still found. Install, tests, build and the local E2E now run one at a time across the machine (`heavy.sh`). (#8)

### Added

- `autopilot`: a coordinator that picks up issues by a per-repo rule (`## Pickup` in `.claude/autopilot.md`), review requests and Slack mentions, and starts one session per item. One `## Pickup` at a workspace root covers every clone under it. Slack replies are drafts until you approve them. (#8, #10)
- `review-queue` offers to archive earlier review sessions whose PR has been merged, in the same confirmation as the new reviews. Interval ticks announce each one once. (#11)

### Fixed

- `autopilot` keeps only Slack messages that actually mention you. (#9)
- `merged` asks its Next step through AskUserQuestion, and `review-queue` sends a notification when its queue drains. (#7)

## [0.3.0] - 2026-11-03

### Added

- `autopilot` skill: one task from pass criteria to a PR with local E2E evidence, then the same E2E scenarios on dev after you merge, reported in five lines. `merged` suggests `/autopilot continue <PR>` when a run is pending. (#5)

## [0.2.0] - 2026-11-03

### Added

- `review-queue` skill: finds every PR that requests your review and runs `pr-review` or `recheck` on each in its own session. `--every <interval>` keeps checking on a loop. (#2)

### Fixed

- `review-queue` asks for the clone root when neither `--root` nor `REVIEW_QUEUE_ROOT` is set, instead of defaulting to `~/Repositories`. (#3)

## [0.1.0] - 2026-10-30

### Added

- Installable Claude Code plugin `zahidakhyar-skills`, served from the `zahidakhyar` marketplace in this repo.
- Skills: `ship`, `pr-review`, `recheck`, `merged`, `release`, `orchestrate`, `learned`.
- Bundled default review protocol for `pr-review` and `recheck`, overridable per repo with `REVIEW.md`.

[Unreleased]: https://github.com/zahidakhyar/skills/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/zahidakhyar/skills/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/zahidakhyar/skills/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/zahidakhyar/skills/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/zahidakhyar/skills/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/zahidakhyar/skills/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/zahidakhyar/skills/releases/tag/v0.1.0
