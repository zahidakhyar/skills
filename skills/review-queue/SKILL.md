---
name: review-queue
description: Use when the user wants every pull request that requests their review handled, each in its own session — `/review-queue [--team] [--root <dir>] [--comment] [--every <interval>]`, "cek PR yang minta review ke aku", "cek tiap 30 menit PR yang request review", "review semua PR yang request ke aku", "ada PR apa aja yang nunggu review-ku", "review queue", "kerjakan antrian review", "review requested PRs". Not for one known PR (that is `/pr-review` or `/recheck` directly).
---

# Review Queue

This session is the **dispatcher**. It finds the PRs waiting on the user's review, decides per PR whether it needs `pr-review` (never reviewed) or `recheck` (reviewed before, new commits since), and starts one session per PR, so no PR's diff, findings or gate output leaks into another's review. It never reviews code itself.

Arguments:
- `--team`: also include PRs that request a review from one of the user's teams. Default: only PRs that name the user directly.
- `--root <dir>`: where the local clones live. Default `$REVIEW_QUEUE_ROOT`. With neither set, ask first (step 1); there is no built-in default.
- `--comment`: passed on to every `pr-review` child, which then posts without showing a draft first. Without it, a `pr-review` child shows its draft and waits for the user's yes in that child session. `recheck` has no draft step: it resolves threads and posts on its own, as it does when run directly.
- `--every <interval>` (e.g. `30m`): keep checking on that interval. See "Interval mode".

Needs `gh` (authenticated) and `jq`. Reviews run in the user's existing local clones; each child's review skill makes its own throwaway worktree there, so the clone's checked-out branch is never touched.

## 1. Build the queue

No `--root` and no `$REVIEW_QUEUE_ROOT` → ask the user which folder holds their local clones before running anything. Never guess a path. Use the answer as `--root` for the rest of this run, interval ticks included, and mention that setting `REVIEW_QUEUE_ROOT` skips the question next time.

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/queue.sh" [--team] [--root <dir>]
```

One JSON array, one object per open PR: `repo`, `number`, `title`, `author`, `url`, `isDraft`, `clone`, `head`, `action`, `reason`.

| `action` | Meaning |
|---|---|
| `pr-review` | No earlier review by the user |
| `recheck` | Reviewed before; new commits since the `reviewed:` marker, or the branch was force-pushed |
| `skip` | `reason` says why: no new commits since the last review, no local clone, or `pr_state.sh` failed |

Empty array → no PR is waiting on the user's review. Still run step 2: its archive sweep does not depend on the queue. Stop only when that sweep finds nothing either.

## 2. Check existing review sessions

Call `mcp__ccd_session_mgmt__list_sessions` with `limit: 100` (the default 20 misses older ones), not `linked: true`: children from an earlier run belong to another dispatcher session. A review session is one whose title matches `^(Review|Recheck) .+#([0-9]+):` (the step 4 title). Find its PR from the title and `cwd`, never from `name` (trimmed to 24 chars, which can cut off the number) and never from `prState` (a review session opens no PR, so the app binds none; the app's `auto_archive_on_pr_close` setting never fires for these either).

- **Open session:** one still running or waiting for the user for a PR in the queue → mark the PR `skip` with reason "session already open" and link that session.
- **Archive sweep:** for every review session with `isRunning: false`, take the number from the title and the repo from `git -C <cwd> remote get-url origin` (strip up to `github.com[:/]` and the trailing `.git`, as `queue.sh` does), then `gh pr view <number> -R <owner/repo> --json state -q .state`. `MERGED` → add it to the archive list as `repo#number` plus the session link. Any other state, a missing `cwd` or a failed lookup → leave the session alone.

## 3. Confirm once

Show the queue as one table: `repo#number` (linked to `url`), title, author, planned action or skip reason, and `draft` when `isDraft`. A non-empty archive list from step 2 gets a second table: `repo#number`, the session link, `merged`. Then ask one question covering both: start the sessions for every `pr-review` and `recheck` row, and archive the listed sessions? The user may drop rows from either table. A draft PR is listed but starts only when the user picks it. A PR skipped for "no new commits" stays skipped: `recheck` itself stops on unchanged code.

No local clone → tell the user which repo is missing and that `gh repo clone <repo>` under the root fixes it. Never clone on your own.

## 4. Start the sessions

**At most 2 children working at once, and at most 1 per repo.** Each child may run typecheck and tests locally, and two reviews in one checkout race on `git fetch` and `git worktree add`. The rest wait in the queue (step 5).

First `mcp__ccd_session_mgmt__get_session("self")` → this session's `local_…` id, for the child prompt.

Per PR, `mcp__ccd_session__start_session`:
- `initiation`: `"user_asked"`, `context`: `"fresh"`
- `title`: `Review <repo name>#<number>: <PR title>` for `pr-review`, `Recheck <repo name>#<number>: <PR title>` for `recheck`
- `name`: `rv-<repo name>-<number>`, trimmed to 24 chars
- `cwd`: the PR's `clone`, never an umbrella folder above it. When that folder is itself a git repo (a workspace holding many service repos), `gh` and the review skills' relative `.worktrees/` would resolve against the wrong repo
- `use_worktree`: `false`. Both review skills make their own throwaway worktree under `.worktrees/` inside the clone; an app worktree around it would only nest one in the other
- `wake_when_done`: `true`
- `prompt`:

  ```
  Invoke the <pr-review|recheck> skill with argument `<url>`<" --comment" when the user passed it, pr-review only>.
  PR: <url>, by <author>. You run inside its local clone.
  This session was started by the review-queue dispatcher (<dispatcher local_ id>). It never answers for the user: wait for the user before posting, unless --comment was passed.
  When done, end with one line: <url> — <verdict or "not posted"> — <review URL or reason>.
  ```

Link every started session to the user as `[title](#<local_ id>)`.

Then, per confirmed archive row, `mcp__ccd_session_mgmt__archive_session` with its `sessionId` and `reason: "<repo>#<number> merged"`. The app refuses a session that is working, pinned or open on screen; list those in one line and leave them.

## 5. Drain the queue

Start the first batch (up to 2) in the same turn the user confirmed. Later starts need a user turn: the app refuses a session start in another folder on a turn that a `<side-sessions-event>` began, and stops waking this session after several events in a row with no user message.

So on each `<side-sessions-event>`, start nothing. Report in one or two lines which reviews finished and which PRs still wait. While PRs still wait, send one `PushNotification` naming them (the `wrap_up` box does not reach the user's phone), then call `mcp__ccd_turn__wrap_up` with the ask "Start the next reviews?" and a first button labelled "Start next". On the user's click, start the next waiting PRs, in queue order, up to the cap of 2 working and 1 per repo.

A child waiting for the user's yes to post is not finished and keeps its slot. Say so in one line ("waiting for your OK in [title](#id)").

Never answer a child's question, and never send it a "yes, post it" on the user's behalf. Approval to post comes from the user, typed in that child session.

## 6. Report

When no child is working and the queue is empty, report one line per PR from the children's last lines: `repo#number — verdict — review URL`, plus the skipped rows with their reason and the archived sessions (`repo#number — merged, session archived`). A child's note is its claim, not proof: for each one that says it posted, confirm with `gh api repos/<repo>/pulls/<number>/reviews -q '[.[] | select(.user.login == "<me>")] | last | .html_url'`.

## Interval mode

`--every <interval>` → invoke the `loop` skill with `args: "<interval> <the command as the user typed it, minus --every and its value>"`, then run the first pass right away as a normal run (steps 1–6). Keep the command name the user typed: under the plugin install it is `/zahidakhyar-skills:review-queue`. Leaving `--every` in would schedule a new loop on every tick.

A tick is an automated turn: the app refuses session starts on it. So a tick never starts children itself:
1. `bash "${CLAUDE_SKILL_DIR}/scripts/queue.sh" [--team] [--root <dir>] --new "${REVIEW_QUEUE_STATE:-$HOME/.local/state/review-queue}/seen"`. It returns only `pr-review`/`recheck` rows whose `repo#N@head` was never announced, and records them, so each PR head is announced once.
2. Run step 2. Keep only archive rows whose `archive:<sessionId>` line is not in the same seen file, and append those lines, so each merged session is announced once. A tick never archives on its own.
3. Empty array and no new archive rows → end the tick with no text, no notification and no `wrap_up`. That is the normal case.
4. Otherwise → send one `PushNotification` naming the new PRs and the merged sessions, show the step 3 tables, and call `mcp__ccd_turn__wrap_up` with the ask "Start these reviews?" and a first button "Start reviews" (when only archive rows are new: "Archive these sessions?" and "Archive"). The click is a user turn and doubles as the step 3 confirmation; continue with step 4.

The loop lives in this session only: it fires while the app is open and this session is idle, and expires after 7 days. Every batch needs that one click, even with `--comment`.

## Common mistakes

| Mistake | Fix |
|---|---|
| Reviewing a PR in this session | Dispatcher only. Every PR gets its own session, or its context leaks into the next |
| Matching clones by folder name | `queue.sh` matches the `origin` remote; a fork or a renamed folder breaks name matching |
| Starting every child at once | 2 working at most, 1 per repo |
| Starting the next child from a `<side-sessions-event>` turn | Refused by the app; ask with a "Start next" button (step 5) |
| `use_worktree: true` | The review skills already make their own worktree inside the clone |
| Forwarding "post it" to a child | The user answers in the child; the dispatcher never posts or approves |
| Cloning a missing repo unasked | Report it with the `gh repo clone` command |
| `cwd` set to the umbrella folder that holds many repos | The PR's own clone (step 4) |
| Starting sessions from a loop tick | Refused by the app; announce and offer the "Start reviews" button |
| Passing `--every` on to the loop command | Strip it, or each tick schedules another loop |
| Guessing a clone root when none was given | Ask the user (step 1); `queue.sh` exits 2 without one |
| Finding a review session's PR from `name` or `prState` | Title number plus the `cwd` clone's origin (step 2); `name` is trimmed and review sessions have no bound PR |
| Stopping on an empty queue before the archive sweep | Step 2 runs either way |
| Archiving without the user's confirmation, or on a loop tick | Archive only rows the user confirmed in step 3 |
| Archiving a session whose PR is closed but not merged | `MERGED` only |
