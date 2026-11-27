# Scenario: seed a feature map in a repo without one

Repo `acme-shop` (Next.js admin + API), default branch `main`, also has `dev`. The user typed: `/feature-map`.

Repo facts:

- `.claude/autopilot.md` exists: start `docker compose up -d db && yarn db:migrate && yarn db:seed && yarn dev`, local URL `http://localhost:3000`, test account `admin@test.local` (`prisma/seed.ts`).
- No `.claude/features/`.
- App routes (from `app/`): `/login`, `/orders` (list with a `Status` combobox and `Filter` button), `/orders/[id]` (detail with a `Refund` button), `/settings` (profile form with `Save`), `/reports` (CSV export button `Export`).

Run log (already happened, all heavy commands through `heavy.sh`):

1. App started in the seed worktree on `http://localhost:3517`; base commit `c3d4e5f`.
2. You drove only the orders filter: login as admin, `Orders` link, select `PAID`, click `Filter` → every row `PAID`. You did not drive reload, detail, settings or reports.
3. App stopped.
