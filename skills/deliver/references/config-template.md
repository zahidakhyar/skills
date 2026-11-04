# `.claude/autopilot.md` template

Copy into the target repo as `.claude/autopilot.md`, fill each section, delete the examples. Keep each section short; Claude reads it at the start of every run.

```markdown
# autopilot

## start
- Command: `docker compose up -d db && yarn prisma migrate dev && yarn prisma db seed && yarn start:dev`
- Local URL: http://localhost:3000
- Ready when: `curl -fsS http://localhost:3000/health` returns 200

## dev_url
https://app-dev.example.com   <!-- a suggestion; the user still names the host in chat -->

## deploy_signal
endpoint: GET /version → `.commit`
<!-- or: gh-workflow: deploy-dev.yml -->
<!-- or: railway: service "api", environment "dev" -->
<!-- or: azure: App Service "myapp-dev" (read via the portal in Chrome) -->

## test_accounts
`prisma/seed.ts` — users `admin@test.local`, `member@test.local`

## deploy_timeout
20

## notes
- Feature flag `ORDERS_V2` must be on locally (`.env.example` has it).

## Pickup
<!-- Optional. Read by the autopilot coordinator; deliver reads only base. A workspace root's section covers the clones under it. -->
<!-- rule: assignee:@me          (team repo: issues assigned to you) -->
<!-- rule: label:ready-for-agent (solo repo) -->
<!-- base: dev -->
```
