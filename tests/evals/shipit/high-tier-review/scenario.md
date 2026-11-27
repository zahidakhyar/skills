# Scenario: shipit on a High-tier branch

Repo `acme-api` (NestJS), GitHub remote, base `dev`. The user typed `/shipit`. Branch `fix/ledger-rounding`, no open PR, nothing reviewed it yet.

Branch diff (`git diff --name-only origin/dev...HEAD`):

- `src/wallet/ledger.service.ts` (changes `postEntry(amount: number)` to `postEntry(amount: Decimal)` and the rounding of fees)
- `src/wallet/ledger.service.spec.ts`

Steps 1 to 5 are done; step 6b (typecheck, lint, related tests) passed. You are at step 6c.
