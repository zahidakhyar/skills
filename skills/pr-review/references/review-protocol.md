# Review Protocol

The default rules `pr-review` and `recheck` apply. A repo `REVIEW.md` (read from the PR's base) adds project rules on top; where the two disagree (severity definitions, Nit limits, language), the repo file wins.

## One review, one notification

- No standalone summary comment. The recap is the review body, submitted together with the inline comments as one review: `gh api repos/<owner>/<repo>/pulls/<PR>/reviews --input review.json` with `{"event": "REQUEST_CHANGES"|"APPROVE"|"COMMENT", "body": "...", "comments": [{"path", "line", "side": "RIGHT", "body"}]}`.
- `event` is the verdict: never comment-only, never a separate `gh pr review` call afterwards. On your own PR `event` must be `COMMENT` (GitHub blocks the other two there); the verdict then sits in the body text.

## Severity

Every finding carries a label, inline and in the body:

| Label | Meaning | Verdict |
|---|---|---|
| **High** | Bug, data loss, security | Blocks merge |
| **Medium** | Wrong under realistic input | Fix before merge |
| **Low** | Minor, can follow up | Does not block |
| **Nit** | Style or naming | Does not block |
| **Pre-existing** | A bug the PR did not introduce | Never counts; the body suggests an issue for it |

Any High or Medium → `REQUEST_CHANGES`; only Low/Nit → `APPROVE`.

- At most 5 Nits per review.
- From the third review round on a PR (two or more earlier reviews from you on it), post new findings only when they are High or Medium: every Low or Nit costs the author one more commit and one more round.

## Body shape

- 1–2 findings → the verdict sentence only ("Request changes. One blocker at `path:line`, details inline.").
- 3 or more → verdict, then one line per finding, grouped by severity, highest first: `**<Severity>** \`path:line\` — <gist, under 8 words>`.
- Reasoning lives inline only. The one exception is a finding outside the diff, which cannot be anchored and is written in full in the body.

## Comment style

- Verdict first, each fact said once.
- Inline comments open with the severity label.
- No bold mini-headings, no em dashes, no design essays the author did not ask for, no explanations of GitHub mechanics the reader already knows, never repeat back what the author wrote.
- Length scales with what is wrong, not with how much was verified.

## Discipline

- Verify every claim in the PR description against the actual diff. Run the typecheck / tests before asserting a bug.
- Do not concede a finding to an author rebuttal without re-checking the code and the project rules.
