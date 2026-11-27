# Scenario: shipit on a Medium-tier branch

Repo `acme-api` (NestJS), GitHub remote, base `dev`. The user typed `/shipit`. Branch `feat/order-cache`, no open PR, nothing reviewed it yet.

Branch diff (`git diff --name-only origin/dev...HEAD`):

- `src/orders/orders.service.ts` (adds a 60-second in-memory cache to `listOrders`)
- `src/orders/orders.service.spec.ts`

Steps 1 to 5 are done; step 6b (typecheck, lint, related tests) passed. You are at step 6c.
