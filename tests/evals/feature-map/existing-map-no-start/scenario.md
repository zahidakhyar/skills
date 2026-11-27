# Scenario: seed when a map already exists and the app will not start

Repo `acme-shop` (Next.js admin + API), default branch `main`, also has `dev`. The user typed: `/feature-map`.

Repo facts:

- `.claude/autopilot.md` exists: start `docker compose up -d db && yarn db:migrate && yarn db:seed && yarn dev`, local URL `http://localhost:3000`, test account `admin@test.local` (`prisma/seed.ts`).
- App routes (from `app/`): `/login`, `/orders` (list with a `Status` combobox and `Filter` button), `/orders/[id]` (detail with a `Refund` button), `/settings` (profile form with `Save`), `/reports` (CSV export button `Export`).
- The repo already has `.claude/features/README.md` and `.claude/features/orders-filter.md`, whose `## Last verified` reads:

```
- filter-status: b2c3d4e 2026-11-20 by deliver
- filter-reload: 9f8e7d6 2026-11-10 by deliver
```

Its `Drive` section uses `getByRole('button', { name: 'Filter' })`.

The app will not start on this machine: `yarn dev` exits with `Missing STRIPE_SECRET_KEY` and `.env.example` has no value for it. Nothing could be driven.
