---
name: visual-qa
description: Use when a branch changed web UI and the result must be checked as rendered pixels at several viewport widths before a PR — `/visual-qa [base] [--url <base URL>] [--routes <path,...>]`, "cek UI-nya di semua viewport", "screenshot dulu sebelum PR", "visual QA", "cek layout mobile dan desktop", "UI-nya mepet / rusak di layar lain", or when `ship` reaches its visual gate. Not for Expo / React Native screens (use `impeccable` audit there) and not for a design critique of taste.
---

# Visual QA

Render every route this branch changed at four widths, have a reviewer who never saw the code judge the screenshots against a fixed rubric, fix what it finds, and repeat until it returns PASS. The author of a change approves its own screenshots too easily: a layout that is cramped on a phone, stretched across a 1536px screen, or not widening at `xl` looks fine to the session that wrote it. The independent reviewer is the whole point of this skill.

Web only (Next.js, Vite, plain HTML). Needs `npx` (for `playwright screenshot`) and a way to start the app.

Arguments:
- `base`: diff base. Default: the open PR's base, else `dev` → `develop` → the default branch, the first that exists on the remote.
- `--url <base URL>`: an app that is already running. Without it, step 3 starts one.
- `--routes <path,...>`: the routes to capture, skipping step 2's mapping.

## 1. Scope

`mb=$(git merge-base HEAD origin/<base>)`, then `git diff --name-only "$mb"...HEAD`. UI files are `.tsx`, `.jsx`, `.vue`, `.svelte`, `.astro`, `.html`, `.css`, `.scss`, and Tailwind / theme config, outside test and story files. None → report `Visual QA: skipped (no UI change)` and stop. Only React Native / Expo files → `Visual QA: skipped (native screens)` and stop.

Run folder: `run=<repo root>/.visual-qa/<branch with / replaced by ->`, created fresh. Keep it out of git: `git check-ignore -q .visual-qa/ || echo '.visual-qa/' >> "$(git rev-parse --git-common-dir)/info/exclude"`.

## 2. Routes

Map each changed UI file to the routes that render it, and write them to `$run/routes.md` with the file that put each one there.

- A page or layout file → its route. Next.js app router: drop route groups `(x)` and the `page.tsx` name; `[slug]` needs a real value. Pages router, Vite router config, or file-based routers likewise.
- A component → grep its importers up to the pages that use it. Keep at most 3 routes per component, the ones where it is most prominent.
- A global style, theme or layout → the home route plus the 3 most-visited-looking routes (dashboard, list, form).
- A component that only shows after an action (sheet, modal, dropdown, error state) → note the action next to the route (`/cart — open the cart sheet`); step 4 captures that state too.
- Dynamic segment → take a real value from the seed, fixtures or the running app's own list page. None found → ask the user once for one value per segment. When nobody can answer (run from `ship` inside a builder session or an Auto-fix wake-up), mark that route `UNVERIFIED (no value for <segment>)` in the report and go on with the rest.

## 3. Run the app

`--url` given → use it. Otherwise start it from this checkout: the `## start` section of `.claude/autopilot.md` when it exists, else the `dev` script in `package.json`. Start it with Bash `run_in_background`, on a free port (`lsof -iTCP -sTCP:LISTEN -P`), and wait until the URL answers. Never stop or reuse a process you did not start. The app cannot start → report `Visual QA: UNVERIFIED (<the error line>)` and stop; never mark it passed.

Routes behind a login: build `$run/auth.json` once. A test account in the seed, fixtures or example env → sign in with it through a short `playwright` script that ends with `context.storageState({ path })`. None → ask the user to sign in themselves in `$pw codegen --save-storage=$run/auth.json <URL>/login`, and wait for their word; when nobody can answer, the routes behind the login are `UNVERIFIED (needs login)` and the rest still run. Never type a password the user gave in chat for a real service.

## 4. Capture

For every route × width × scheme, one full-page PNG:

| Width × height | Stands for |
|---|---|
| 375 × 812 | phone |
| 768 × 1024 | tablet, `md` |
| 1280 × 800 | laptop, `lg`/`xl` |
| 1536 × 864 | wide desktop, `2xl` |

Schemes: `light`, plus `dark` when the app has a dark mode (`dark:` classes, a `prefers-color-scheme` rule, or a theme provider). All four widths always run, also when the change "is mobile only": the defects this skill exists for show up at the widths nobody looked at.

`$pw` is `npx playwright` when the project already has `playwright` or `@playwright/test` in `node_modules`, else `npx -y playwright@1.64.1`. Run `$pw install chromium-headless-shell` once before the first capture: a Playwright version needs its own browser build, and without it every capture fails with "Please run … npx playwright install".

```bash
$pw screenshot --full-page --viewport-size="375,812" --color-scheme=light \
  --wait-for-timeout=1500 [--load-storage="$run/auth.json"] "<URL><route>" "$run/r1/<slug>-375-light.png"
```

A state that needs an action (open sheet, error state) needs a short `playwright` script instead, one per state, saving the same file names with a `-<state>` suffix. Such scripts (and the login script in step 3) live in `$run/`; when the project has no `playwright` of its own, `npm i --no-save --prefix "$run" playwright@1.64.1` first, so `node "$run/<script>.mjs"` can import it. When `${CLAUDE_SKILL_DIR}/../deliver/scripts/heavy.sh` exists, run each capture batch through it (`bash <heavy.sh> <command>`), so parallel sessions never run two browsers at once. A page that errors or redirects to login → that is a finding, captured as is.

## 5. Independent review

Dispatch one fresh `general-purpose` subagent (foreground; `model` = this session's tier). Its prompt is exactly the reviewer brief in [references/rubric.md](references/rubric.md), filled in with the round's PNG paths and, from round 2, the earlier defect table. Nothing else: not the diff, not the file names you changed, not what the change was meant to do, not your own opinion of the screenshots. A reviewer that knows the intent grades the intent.

Never replace this step with your own look at the screenshots, also when time is short or the change looks small: self-review is the failure this skill exists to stop. The subagent tool is unavailable → report `Visual QA: UNVERIFIED (no independent reviewer)`.

The reply is a defect table plus `VERDICT: PASS` or `VERDICT: FAIL`. Save the reply verbatim as `$run/r<n>/review.md`, never a summary: round n+1's reviewer gets that table as is.

## 6. Fix loop

`FAIL` (any P1 or P2) → fix each P1 and P2 in the code, commit them as one `fix: visual QA round <n>` commit, then capture **every** route at every width and scheme again into `$run/r<n+1>/`, never only the one that failed, since a fix at one width moves the others. The file set stays the one round 1 had: a state that no longer renders (the sheet that overflowed is gone) is a finding, not a fix. Then a **new** reviewer subagent (step 5) with the earlier table, never the same one.

At most 3 rounds. P3 never blocks and is not fixed unless it is a one-line change.

A reviewer finding you believe is wrong (the screenshot caught a loading state, the "overflow" is an intended carousel) → recapture that one shot with a longer `--wait-for-timeout` or note why, but do not drop it silently: it stays in the report as `disputed` with your reason.

## 7. Report

Stop the app you started. Write `<PASS|FAIL|UNVERIFIED> <git rev-parse HEAD>` to `$run/result`, which `ship` reads to skip a second run on unchanged UI. Report:

```
Visual QA: <PASS | FAIL | UNVERIFIED> — <R> routes × 4 widths × <schemes>, <n> rounds
| Route | Width | Scheme | Defect | Severity | Status (fixed in <sha> / open / disputed) |
Screenshots: <run>/r<last>/
```

`FAIL` after round 3 → the open P1/P2 rows are listed and the branch is not ready; the caller decides (for `ship`: stop before the push). The report line goes into the PR's `## Test plan` as `- [x] Visual QA: PASS (<R> routes × 4 widths, <n> rounds)` (or `- [ ]` with the open count).

## Common mistakes

| Shortcut | What it misses |
|---|---|
| "I checked the screenshots myself, they look fine" | The author's eye approves the author's layout. Step 5 is not optional. |
| "Only 375 and one desktop width" | Full-width forms show at 1280+, a sheet that should widen shows at 1536. All four widths. |
| "Cramped padding is just taste" | The rubric makes it P2: it is the defect users actually report. |
| "Re-screenshot only the route that failed" | A fix at one width changes the others. Recapture everything. |
| "Tell the reviewer what changed so it focuses" | It then checks the intent, not the pixels. Brief only. |
| "Skip dark mode, it was not touched" | Shared tokens and new surfaces break it silently. Capture it when the app has one. |
