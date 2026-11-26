# Feature map contract

The feature map is a target repo's committed record of its user-facing features: how a user reaches each one, how to drive it, what observable end state proves it works, and the traps found along the way. `deliver` reads it to write scenarios and updates it after local E2E passes; `feature-map` seeds it. It is written for an agent that has never seen the app.

## Layout

```
.claude/features/
  README.md          # baseline and conventions for this repo
  <feature-id>.md    # one per user-facing feature, kebab-case id
```

There is no index file. List the features with `head -n1 .claude/features/*.md` (each file's H1 is its title), so parallel PRs that add different features never touch the same file.

## README.md

Four H2s, in this order:

1. `Baseline` — preconditions every recipe starts from. Point to `.claude/autopilot.md` for the start command, local URL and test accounts; never copy them here.
2. `Driving conventions` — web through `playwright-cli` with Playwright locators as targets (`"getByRole('button', { name: 'Save' })"`), never snapshot refs like `e15`, which change every run, nor CSS selectors or position; APIs through `curl`; data created by a run is named `deliver-<sha7>-…`.
3. `Proof standards` — capture the user action and the resulting state, not only the final screen; a mutation is proven by a second, read-only view of the stored value; a skipped entry point is never reported as verified through another one.
4. `Entry contract` — the feature-file shape below, in one paragraph.

## Feature file

An H1 title, one paragraph of user-visible behaviour, then exactly these H2s in order:

1. `Sub-features` — `- <id>: <one line>`, ids short and kebab-case.
2. `How to reach it` — every user entry point: route, menu item, keyboard shortcut, endpoint.
3. `Drive` — a `Preconditions:` list, then labelled bullets, each pairing a user action with the exact command or step and the observable result.
4. `Gotchas` — traps that waste or invalidate a run.
5. `Last verified` — one line per sub-feature: `- <id>: <sha7> <YYYY-MM-DD> by <deliver | feature-map>`, or `- <id>: never`.

Only user paths, stable handles, commands and observable proof belong in the map. No source file paths, component or function names.

## Rules for writers

- Write from what actually ran in this session. A sub-feature driven in this run gets a dated `Last verified` line; one not driven keeps its existing line, or gets `never` when it is new. The one exception is the `feature-map` seed, which may describe features it did not drive from the routes and visible labels: every such sub-feature is `never`.
- A step that no longer matches the app is corrected in place. Never add a second recipe beside a stale one.
- A gotcha hit during a fix round goes into `Gotchas`, phrased as the trap and how to avoid it.
- A dated `Last verified` line is rewritten only by a run that drove that sub-feature.

## Rules for readers

- A dated sub-feature is a recipe: reuse its entry points, handles and gotchas.
- A `never` sub-feature, or one whose date is older than the last change to its code, is a hint to check, not a recipe to trust.
- A gotcha listed for a feature becomes a scenario step or a precondition.

## Example

`.claude/features/orders-filter.md`:

```markdown
# Filter orders

A signed-in admin narrows the orders list by payment status; the filter survives a page reload.

## Sub-features

- filter-status: choose a status and see only matching orders
- filter-reload: the chosen status stays applied after a reload

## How to reach it

- Sidebar link `Orders`, then the `Status` combobox above the table.
- Direct URL `/orders?status=PAID`.

## Drive

Preconditions:

- Signed in as the admin account from `.claude/autopilot.md` `## test_accounts`.
- The seed has at least one `PAID` and one `PENDING` order.

- **Open list.** `playwright-cli click "getByRole('link', { name: 'Orders' })"`. A table named `Orders` shows both statuses.
- **Filter.** `playwright-cli select "getByRole('combobox', { name: 'Status' })" "PAID"`, then `playwright-cli click "getByRole('button', { name: 'Filter' })"`. Every row's `Status` cell reads `PAID`; the URL has `?status=PAID`.
- **Reload.** `playwright-cli reload`. The combobox still shows `PAID` and the rows are unchanged.

## Gotchas

- The list fetches after a 300 ms debounce; wait for the `Orders` table to stop showing `Loading`, not for a fixed time.
- An empty result shows `No orders`, not an empty table: assert the text.

## Last verified

- filter-status: 3e7b2a2 2026-11-26 by deliver
- filter-reload: never
```
