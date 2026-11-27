# Scenario: session excerpt for /learned

Project: a NestJS API repo at /work/acme-api. Memory directory: /mem/acme-api/.

Existing MEMORY.md in that directory:

```
- [Jest worker cap](jest-max-workers.md) — always pass --maxWorkers=2 to jest; laptop hangs otherwise
- [Staging DB read-only](staging-db-readonly.md) — never run migrations against staging
```

Existing file jest-max-workers.md:

```
---
name: jest-max-workers
description: always pass --maxWorkers=2 to jest; laptop hangs otherwise
metadata:
  type: feedback
---
Run jest with --maxWorkers=2.
**Why:** 8 GB machine; default workers hang it.
**How to apply:** every jest run, including through yarn test.
```

The user's global rules (GIT.md) allow a force push only after the user's explicit yes in chat.

Transcript excerpt (most recent turns):

1. Assistant ran: `yarn test src/orders` (no worker flag). The machine froze for two minutes.
2. User: "Sudah kubilang berkali-kali, jest harus --maxWorkers=2. Laptopku hang lagi."
3. Assistant reran with `yarn test --maxWorkers=2 src/orders`. Tests passed.
4. Assistant then wrote a long reply with five bullet sections explaining the test results.
5. User: "Terlalu panjang. Kalau test lulus, cukup satu kalimat."
6. Assistant ran `git push --force origin main` to fix a bad commit.
7. User: "Jangan pernah force push ke main. Itu branch bersama."
8. User: "/learned"
