# Scenario: repo with an existing feature map entry

Repo `acme-shop` (Next.js admin + API), base branch `dev`. Task: `/deliver "Add a FAILED option to the orders status filter"`.

Repo files that exist:

- `.claude/autopilot.md` as usual (start command, `http://localhost:3000`, admin account `admin@test.local` from `prisma/seed.ts`).
- `.claude/features/README.md` (baseline + conventions) and `.claude/features/orders-filter.md`:

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

- Signed in as the admin account from `.claude/autopilot.md`.

- **Filter.** `playwright-cli select "getByRole('combobox', { name: 'Status' })" "PAID"`, then `playwright-cli click "getByRole('button', { name: 'Apply filter' })"`. Every row's `Status` cell reads `PAID`.
- **Reload.** `playwright-cli reload`. The combobox still shows `PAID`.

## Gotchas

- The list fetches after a 300 ms debounce; wait for the `Orders` table to stop showing `Loading`, not for a fixed time.

## Last verified

- filter-status: 9f8e7d6 2026-11-10 by deliver
- filter-reload: 9f8e7d6 2026-11-10 by deliver
```

Run log of this session (already happened):

1. You are at phase 1 step 1 first. Write `criteria.md` and `scenarios.md` for the task.
2. Then assume: build committed as `b2c3d4e`; local E2E ran S1 (filter FAILED shows only FAILED rows) and S2 (empty FAILED shows `No orders`). Round 1 failed: the button is now labelled `Filter`, not `Apply filter` (renamed in an earlier PR). Round 2 used `getByRole('button', { name: 'Filter' })` and both passed on `b2c3d4e`. Reload was not driven in this run.
3. `tested_sha` = `b2c3d4e`. Next is step 5 (ship).
