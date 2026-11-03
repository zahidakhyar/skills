# Changelog

All notable changes to this plugin are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the plugin uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `autopilot` skill: one task from pass criteria to a PR with local E2E evidence, then the same E2E scenarios on dev after you merge, reported in five lines. `merged` suggests `/autopilot continue <PR>` when a run is pending.

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

[Unreleased]: https://github.com/zahidakhyar/skills/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/zahidakhyar/skills/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/zahidakhyar/skills/releases/tag/v0.1.0
