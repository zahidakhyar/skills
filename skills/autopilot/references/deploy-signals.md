# Deploy signals

How phase 2 knows dev runs the merge commit. Try the signals in this order and use the first one the repo has. The `deploy_signal` section of `.claude/autopilot.md` names which one applies; when it is missing, detect it as below and write what you found back into that file in the next PR.

Every wait has a deadline (`deploy_timeout`, default 20 minutes). A failed or timed-out deploy ends phase 2: report it, never run E2E against the old code.

## 1. App endpoint that reports the commit

Detect: a route such as `/version`, `/health`, `/api/health` or `/_meta` whose response includes the commit SHA. Search the repo for `GIT_SHA`, `COMMIT_SHA`, `RAILWAY_GIT_COMMIT_SHA`, `SOURCE_VERSION`, `BUILD_SHA`.

Wait (Bash with `run_in_background: true`, one notification when it exits):

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/wait_deploy.sh --sha <merge-sha> --timeout-min 20 \
  --endpoint https://<dev-host>/version --jq '.commit'
```

The endpoint is read without credentials, so the host gate does not apply to it.

## 2. GitHub Actions deploy workflow

Detect: a workflow under `.github/workflows/` that deploys on push to `dev` (Azure: `azure/webapps-deploy`, `Azure/functions-action`, `azure/container-apps-deploy-action`; others: `railway up`, `vercel deploy`).

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/wait_deploy.sh --sha <full 40-char merge sha> --timeout-min 20 \
  --gh-workflow <workflow file name> --repo <owner/repo>
```

A successful workflow run means the deploy was submitted; some providers still take a minute to swap before the new code serves traffic.

## 3. Provider

### Railway

- First confirm the target: `list-domains` on the Railway MCP (load its tools with ToolSearch, query `railway`) tells you which service and environment own the dev host. Check that the service deploys from the PR's base branch; if not, report it and stop, because the merge will never show up there.
- Wait for the newest deployment whose commit equals the merge SHA to reach `SUCCESS`. `FAILED` or `CRASHED` → FAILED.
  - CLI installed and linked → Bash `until` loop in the background on `railway deployment list --json`, 30s interval, same deadline.
  - MCP only → a background `sleep 90` as the timer, then one `list-deployments` call when it fires. Repeat until the deadline. MCP tools can't be called from inside a Bash loop.

### Azure (when the `az` CLI is not installed)

- Use claude-in-chrome (the user's real Chrome), read-only: open the App Service / Static Web App / Container App the config names, then Deployment Center (or Revisions for Container Apps). Read the latest deployment's commit and status.
- Chrome must already be signed in to the Azure portal. If you see a sign-in page, stop and ask the user to sign in. Never type credentials, never click anything that changes the resource (restart, swap, redeploy, settings).
- Re-check every 1–2 minutes until the deadline. Each check is one page read, not a loop of clicks.

## Nothing detected

Ask once in chat how to tell that dev is updated. Offer as the button the signal that looks closest. Then record the answer in `.claude/autopilot.md`.
