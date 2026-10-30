# Deploy-window pass

`code-review` reads one revision at a time. During a deploy, old and new code run side by side against one database and one cache, and rollback runs the old code on whatever schema the new code left. This pass covers that window.

## 1. How the repo deploys

Find it before answering anything, and cite the file:
- **Rollout:** rolling, blue/green or several replicas → old and new instances overlap. Single instance replaced in place (stop, then start), or nothing is deployed (library, CLI, mobile client) → skip questions A and B, keep C and D.
- **Migrations:** run on boot (ORM setting such as TypeORM `migrationsRun`, an entrypoint that calls `prisma migrate deploy`, `manage.py migrate`, `rails db:migrate`), as a separate pipeline step, or by hand.
- **Rollback:** what the repo really does. Image or release rollback only, unless a workflow or runbook also reverts migrations.
- **Shared state:** other services that read the same tables or cache keys, from the repo's or monorepo's docs (`CLAUDE.md`, `README`, architecture notes).

## 2. Questions

Answer each one with `path:line` evidence. Every "no" is a finding.

- **A. Old code on the new schema.** Does every column, table, enum value and cache key that the old code selects, inserts or routes on still exist and still get written? Grep the base branch for each one the PR drops, renames or stops writing, in this repo and in every service that shares the state.
- **B. New code on old data.** Does every new query and constraint accept rows that old instances write during the window (NULL in new columns, missing companion rows, old enum values)?
- **C. Rollback.** On the path from step 1, with window rows present: does each down migration still succeed, does it keep the rows written during the window, and does the old code start on the result?
- **D. Read-then-act.** Is state read in one transaction (status, availability, a count, a cached row) and acted on in another, without a lock or a re-check in the write's `WHERE`? Is a cache filled from a read that can start before a commit and finish after its invalidation?
