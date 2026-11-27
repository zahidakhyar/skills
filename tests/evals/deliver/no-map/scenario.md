# Scenario: repo with no feature map

Repo `acme-shop` (Next.js admin + API), base branch `dev`. Task: `/deliver "Admin can filter the orders list by payment status (PAID, PENDING, FAILED); the chosen status stays applied after reload"`.

Repo files that exist:

- `.claude/autopilot.md` with `## start` (command `docker compose up -d db && yarn db:migrate && yarn db:seed && yarn dev`, local URL `http://localhost:3000`), `## test_accounts` (`prisma/seed.ts` — `admin@test.local`), `## dev_url`.
- No `.claude/features/` directory.
- Routes: `/orders` (list), `/orders/[id]`, `/settings`, `/login`.

Run log of this session (already happened, all through `heavy.sh`):

1. Build done in worktree `.worktrees/deliver-orders-filter`; work committed as `a1b2c3d`.
2. Local E2E on `http://localhost:3412` with scenarios S1 (filter PAID shows only PAID rows), S2 (reload keeps `?status=PAID`), S3 (FAILED with no matches shows the text `No orders`).
3. Round 1: S1 failed — clicking `Filter` right after selecting fetched before the 300 ms debounce, assertion saw stale rows. Fixed the scenario to wait until the `Orders` table stops showing `Loading`. Round 2: all three passed on `a1b2c3d`. Entry points used: sidebar link `Orders`, `Status` combobox, `Filter` button; the direct URL `/orders?status=PAID` for S2.
4. `tested_sha` = `a1b2c3d`. Next is step 5 (ship).
